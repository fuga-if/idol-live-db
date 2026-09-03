//! ImasLiveDB の検索照合で使う、文字の畳み込み規則の**唯一の実体**。
//!
//! `imas-core` (iOS / Android) と、ブラウザで動く wasm の両方がここを呼ぶ。
//! 畳み方が 1 箇所でも分かれると「iOS では当たって Android では当たらない」という形で、
//! そのまま使う人にとっての不具合になる。規則を変えるときは必ずここから変えること。
//!
//! 畳むのは**大文字小文字**と**ひらがな↔カタカナ**、それに**単独の濁点・半濁点の合成**の
//! 3 つだけ。濁点の有無そのものと全角半角は畳まない (`ラブ` と `ラフ` は別の曲)。
//!
//! 依存は無い (std のみ)。`wasm32-unknown-unknown` にそのまま乗る前提なので、
//! ここに crate 依存を足さないこと。
//!
//! 緩めるときは [`fold_with_offsets`] (ハイライトの範囲) も同じ規則で動くことを確かめること。
//! 判定と表示で規則がズレると、索引が拾わなかった箇所に色が付いたり、
//! 一致しているのに説明が出なかったりする。

/// 索引側・検索語側の両方をこれに通す。
///
/// 原本 Swift の `String.lowercased()` と同じ「文脈を見ない」小文字化に、
/// かなの畳みと濁点の合成を重ねたもの (`imas-core` では `fold_lowercase` という名前だった)。
///
/// `str::to_lowercase` を使わないのは、Unicode SpecialCasing の Final_Sigma
/// 文脈規則を適用して語末の Σ (U+03A3) を ς に畳んでしまうから。原本 Swift は
/// 無条件写像のみで Σ→σ 固定なので、そのままだと "ΑΣ" が "ας" に畳まれて
/// 検索語 "σ" を外す等、旧アプリと当たり方が非対称になる (移植時の差分ファズで
/// 不一致は全て U+03A3 絡みのこの規則差だった)。`char::to_lowercase` は
/// 無条件の全小文字化写像 (U+0130 → "i\u{307}" の 1:N 展開含む) で Swift と一致する。
#[inline]
pub fn fold(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    // 直前の文字は変数で持つ。`out.chars().next_back()` で取り直すと 1 文字ごとに
    // 逆方向 UTF-8 デコードが走り、実測ではそこが支配的だった (3,154 曲の走査で 1.4ms 差)。
    let mut prev: Option<char> = None;
    for ch in text.chars().flat_map(char::to_lowercase).map(fold_kana) {
        match prev.and_then(|p| compose_voiced_mark(p, ch)) {
            Some(composed) => {
                out.pop();
                out.push(composed);
                prev = Some(composed);
            }
            None => {
                out.push(ch);
                prev = Some(ch);
            }
        }
    }
    out
}

/// 単独の濁点・半濁点を直前のかなに合成する (か + ゛ → が)。合成できなければ None。
///
/// 濁点付きのかなには合成済み (NFC: が U+304C) と分解済み (NFD: か + U+3099) の
/// 2 つの表し方がある。バイト列で比べる以上、片方だけでは当たらない。
/// 実データにも 1 曲・1 ライブ紛れていて、**自分の名前で検索できない**状態だった。
/// データを直しても、アプリ内編集や貼り付けで再び入ってくるのでここで吸収する。
///
/// 表を持たずに済むのは、ひらがなが濁点の有無で連続して並んでいるため
/// (か U+304B → が U+304C → 半濁点は は行のみ +2)。`fold_kana` の後に呼ぶ前提。
#[inline]
fn compose_voiced_mark(base: char, mark: char) -> Option<char> {
    const DAKUTEN: char = '\u{3099}';
    const HANDAKUTEN: char = '\u{309A}';
    let voiced = |c: char| char::from_u32(c as u32 + 1);
    let semi = |c: char| char::from_u32(c as u32 + 2);
    match (base, mark) {
        // う゛ = ゔ だけ並びから外れる。
        ('\u{3046}', DAKUTEN) => Some('\u{3094}'),
        // か行 さ行 た行 は行 (清音は 2 つおき / は行は 3 つおきに並ぶ)。
        ('\u{304B}'..='\u{3062}', DAKUTEN) if (base as u32 - 0x304B) % 2 == 0 => voiced(base),
        ('\u{3064}'..='\u{3068}', DAKUTEN) if (base as u32 - 0x3064) % 2 == 0 => voiced(base),
        ('\u{306F}'..='\u{307B}', DAKUTEN) if (base as u32 - 0x306F) % 3 == 0 => voiced(base),
        ('\u{306F}'..='\u{307B}', HANDAKUTEN) if (base as u32 - 0x306F) % 3 == 0 => semi(base),
        _ => None,
    }
}

/// カタカナをひらがなへ畳む (1 文字 → 1 文字、UTF-8 では 3 バイト → 3 バイト)。
///
/// 範囲は U+30A1..=U+30F6 だけ。`ー` (U+30FC) と `・` (U+30FB) は対応するひらがなが
/// 無いうえ、`ー` は表記の一部として弁別に効くので触らない。
/// `ヷヸヹヺ` (U+30F7..=U+30FA) も対応が無いのでそのまま。
#[inline]
pub fn fold_kana(ch: char) -> char {
    if ('\u{30A1}'..='\u{30F6}').contains(&ch) {
        char::from_u32(ch as u32 - 0x60).unwrap_or(ch)
    } else {
        ch
    }
}

/// 畳んだバイト列と、その各バイトが元の文字列のどこから来たかの対応表。
///
/// ハイライトは**元の文字列**の範囲を必要とするが、照合は畳んだ列で行う。
/// 小文字化には 1 文字が 2 文字に開くもの (U+0130 → "i\u{307}") があるので、
/// 畳んだ位置をそのまま元の位置として使うとずれる。畳みながら対応を記録しておく。
pub fn fold_with_offsets(text: &str) -> (Vec<u8>, Vec<usize>, Vec<usize>) {
    let mut bytes = Vec::with_capacity(text.len());
    let mut starts = Vec::with_capacity(text.len());
    let mut ends = Vec::with_capacity(text.len());
    let mut buf = [0u8; 4];
    for (offset, ch) in text.char_indices() {
        let end = offset + ch.len_utf8();
        for folded in ch.to_lowercase().map(fold_kana) {
            // 直前の文字と合成できるなら、積んだ 1 文字ぶんを差し替える。
            // 元の 2 文字ぶんを覆うので、始まりは前の文字のまま・終わりだけ伸ばす。
            if let Some(composed) = last_char(&bytes).and_then(|prev| compose_voiced_mark(prev, folded)) {
                let previous = prev_char_len(&bytes);
                let start = starts[bytes.len() - previous];
                bytes.truncate(bytes.len() - previous);
                starts.truncate(bytes.len());
                ends.truncate(bytes.len());
                for _ in composed.encode_utf8(&mut buf).bytes() {
                    starts.push(start);
                    ends.push(end);
                }
                bytes.extend_from_slice(composed.encode_utf8(&mut buf).as_bytes());
                continue;
            }
            for _ in folded.encode_utf8(&mut buf).bytes() {
                starts.push(offset);
                ends.push(end);
            }
            bytes.extend_from_slice(folded.encode_utf8(&mut buf).as_bytes());
        }
    }
    (bytes, starts, ends)
}

/// 積んだバイト列の末尾 1 文字 (合成できるか見るため)。
#[inline]
fn last_char(bytes: &[u8]) -> Option<char> {
    std::str::from_utf8(bytes).ok()?.chars().next_back()
}

/// 積んだバイト列の末尾 1 文字のバイト数。
#[inline]
fn prev_char_len(bytes: &[u8]) -> usize {
    last_char(bytes).map_or(0, char::len_utf8)
}

/// 素朴な部分列探索。
///
/// UTF-8 は先頭バイトと継続バイトの範囲が重ならないので、バイト列としての一致が
/// そのまま文字列としての一致になる (途中のバイトから始まる偽の一致が起きない)。
/// 検索語は数文字なので Boyer-Moore 等を持ち込む必要はない。
pub fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    find(haystack, needle).is_some()
}

/// `contains` の位置を返す版。ハイライトの範囲を出すのに要る。
pub fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    // 空の検索語はここでは None (「絞り込まない」の判定は matches 側の責務)。
    let &first = needle.first()?;
    if haystack.len() < needle.len() {
        return None;
    }
    let last = haystack.len() - needle.len();
    // 先頭バイトで足切りしてから残りを比べる (原本 Swift 実装と同じ形)。
    (0..=last).find(|&i| haystack[i] == first && &haystack[i..i + needle.len()] == needle)
}

