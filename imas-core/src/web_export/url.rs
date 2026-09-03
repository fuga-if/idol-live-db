//! URL 規約と id の安全化。
//!
//! ## 生の id をそのまま URL に使う
//!
//! id には日本語・`@`・`×`・`'`・`(` が入っている。これをまとめて ASCII 化すると
//! 「URL を見て何のページか分かる」利点を全部失うので、**危険な id だけ**を
//! フォールバック slug に落とす部分適用にしてある。
//!
//! 現行データ (db/master.sql) で落ちるのは **5 件**で、内訳は:
//!
//! | 理由 | 件数 | 例 |
//! |---|---|---|
//! | [`FallbackReason::Unsafe`] (`/` を含む) | 2 (venues) | `venue_grandpeacepalace(慶熙大学,ソウル/韓国)` |
//! | [`FallbackReason::TooLong`] ([`MAX_SEGMENT_BYTES`] 超え) | 3 (events) | 200 バイトを超える長いイベント名由来の id |
//!
//! この件数はテストで固定してある (新しい壊れ id が入ったら気付けるように)。
//!
//! ## `share_text::escaped_id` は使わない
//!
//! あちらは Swift の `URL(string:)` の癖 (「1 文字でも不正なら既存の `%` ごと再エンコード」)
//! を意図的に再現していて、`@` が `%2540` になる。共有リンクの互換性のためにはそれが
//! 正しいが、静的アセットのパス照合とは両立しない。**別の目的の別の関数**として扱うこと。

/// percent-encode 前の、1 パスセグメントの UTF-8 バイト数の上限。
///
/// 255 ではなく 200 なのは、多くのファイルシステムの上限 255 バイトに対して
/// percent-encode 後 (最悪 3 倍) ではなく **encode 前**で測っているため。
/// Astro は生の値でディレクトリを掘るので、効くのは encode 前の長さ。
pub const MAX_SEGMENT_BYTES: usize = 200;

/// フォールバック slug に落ちた理由。stderr の内訳とテストで使う。
///
/// 理由を分けているのは、対処が違うから。[`Self::Unsafe`] はデータ側の id を直すべき
/// もの (CloudKit の PK 変更になるので別タスク)、[`Self::TooLong`] は id の付け方の
/// 問題で、URL が読めなくなるだけで壊れてはいない。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FallbackReason {
    /// パス構文を壊す文字を含む / 予約語 / `.` / 空。
    Unsafe,
    /// [`MAX_SEGMENT_BYTES`] を超える。
    TooLong,
}

/// この id がフォールバック slug に落ちるか、落ちるならなぜか。
pub fn fallback_reason(id: &str, reserved: &[&str]) -> Option<FallbackReason> {
    if is_safe_segment(id, reserved) {
        return None;
    }
    if id.len() > MAX_SEGMENT_BYTES {
        Some(FallbackReason::TooLong)
    } else {
        Some(FallbackReason::Unsafe)
    }
}

/// 1 パスセグメントとして安全に置けるか。
///
/// 弾くもの:
/// * パス構文やクエリを壊す文字 `/ \ % ? # : * " < > |` と制御文字
/// * `.` 単独 と `..` (相対パスとして解釈される)
/// * 空文字
/// * そのコレクションの予約語 (`upcoming` / `past` / `brand` など)
/// * [`MAX_SEGMENT_BYTES`] 超え
pub fn is_safe_segment(id: &str, reserved: &[&str]) -> bool {
    if id.is_empty() || id.len() > MAX_SEGMENT_BYTES {
        return false;
    }
    if id == "." || id == ".." {
        return false;
    }
    if reserved.contains(&id) {
        return false;
    }
    !id.chars().any(is_unsafe_char)
}

/// パスセグメントに置けない文字。
fn is_unsafe_char(c: char) -> bool {
    matches!(c, '/' | '\\' | '%' | '?' | '#' | ':' | '*' | '"' | '<' | '>' | '|')
        || c.is_control()
}

/// ファイル名 / `getStaticPaths` の params に使う値。
///
/// 安全なら id をそのまま返す。安全でなければ
/// `<id から拾った安全な先頭数文字>-<fnv1a64(id) の先頭 8 hex>` に落とす。
/// 安全な文字が 1 つも無いときは `prefix` を頭に使う。
///
/// **フォールバック名は id 単体から決まる**ので、行が増減しても既存 URL は動かない。
/// 連番による衝突回避を使わないのはそのため。
pub fn path_key(id: &str, reserved: &[&str], prefix: &str) -> String {
    if is_safe_segment(id, reserved) {
        return id.to_string();
    }
    let mut head = String::new();
    for c in id.chars().filter(|c| !is_unsafe_char(*c)) {
        if head.len() + c.len_utf8() > FALLBACK_HEAD_BYTES {
            break;
        }
        head.push(c);
    }
    let head = head.trim_matches(['.', '-']).to_string();
    let head = if head.is_empty() { prefix.to_string() } else { head };
    format!("{head}-{:08x}", (fnv1a64(id) >> 32) as u32)
}

/// フォールバック名の「読める部分」に使う最大バイト数。
const FALLBACK_HEAD_BYTES: usize = 48;

/// FNV-1a (64bit)。ハッシュの用途は衝突しにくい短い識別子を作ることだけで、
/// 暗号強度は要らない。実装が 5 行で済み、どの言語でも同じ値を再現できるのが利点。
pub fn fnv1a64(text: &str) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for b in text.as_bytes() {
        hash ^= *b as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// `href` に書く文字列 (1 セグメントぶん)。
///
/// 非エスケープ集合は **JavaScript の `encodeURIComponent` と完全に同じ**
/// (`A-Z a-z 0-9 - _ . ! ~ * ' ( )`)。RFC3986 の unreserved より広いが、そこを
/// 揃えることに意味がある: 検索 island は行の素材から
/// `prefix + encodeURIComponent(k) + "/"` で href を組むので、**Rust が書き出した
/// パスと JS が組んだ href がバイト単位で一致していないと、片方だけ
/// percent-encode された URL が生まれる**。同じ URL を 2 通りに書けてしまう状態を
/// 作らないために、狭い方 (RFC3986) ではなく JS 側に合わせている。
pub fn url_segment(key: &str) -> String {
    let mut out = String::with_capacity(key.len());
    for b in key.as_bytes() {
        let c = *b as char;
        if c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '!' | '~' | '*' | '\'' | '(' | ')')
        {
            out.push(c);
        } else {
            out.push('%');
            out.push_str(&format!("{b:02X}"));
        }
    }
    out
}

/// コレクションと id から、末尾スラッシュ付きの完成形 URL を作る。
pub fn detail_path(collection: &str, key: &str) -> String {
    format!("/{collection}/{}/", url_segment(key))
}

/// 各コレクションの予約語 (詳細ページの id がこれと衝突するとルートが曖昧になる)。
pub fn reserved_for(collection: &str) -> &'static [&'static str] {
    match collection {
        "events" => &["upcoming", "past", "brand"],
        "songs" => &["brand", "all"],
        "idols" => &["brand", "birth-month"],
        "units" => &["brand"],
        "venues" => &["pref"],
        _ => &[],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_ids_pass_through() {
        assert_eq!(path_key("ml_kasuga_mirai", &[], "idol"), "ml_kasuga_mirai");
        // 日本語・@ ・× は「安全」。URL には percent-encode して出す。
        assert_eq!(path_key("ev_the_idolm@ster_×_ふたご", &[], "ev"), "ev_the_idolm@ster_×_ふたご");
        assert_eq!(path_key("song_(remix)", &[], "song"), "song_(remix)");
        assert_eq!(path_key("o'hare", &[], "venue"), "o'hare");
    }

    #[test]
    fn dangerous_ids_fall_back() {
        // 実データで唯一落ちる形 (会場 2 件)。
        let key = path_key("venue_a/b", &[], "venue");
        assert!(!key.contains('/'), "{key}");
        assert!(key.starts_with("venue_ab-"), "{key}");
        // 同じ id からは常に同じ名前が出る (行が増減しても URL が動かない)。
        assert_eq!(key, path_key("venue_a/b", &[], "venue"));
        // 違う id なら違う名前。
        assert_ne!(key, path_key("venue_a/c", &[], "venue"));
    }

    #[test]
    fn reserved_words_and_dots_fall_back() {
        assert_ne!(path_key("brand", reserved_for("songs"), "song"), "brand");
        assert_ne!(path_key("all", reserved_for("songs"), "song"), "all");
        assert_ne!(path_key("upcoming", reserved_for("events"), "ev"), "upcoming");
        assert!(path_key(".", &[], "x").starts_with("x-"));
        assert!(path_key("..", &[], "x").starts_with("x-"));
        assert!(path_key("", &[], "x").starts_with("x-"));
    }

    #[test]
    fn overlong_ids_fall_back() {
        let long = "あ".repeat(100); // 300 バイト
        assert!(!is_safe_segment(&long, &[]));
        let key = path_key(&long, &[], "x");
        assert!(key.len() <= FALLBACK_HEAD_BYTES + 9, "{}", key.len());
    }

    #[test]
    fn url_segment_matches_encode_uri_component() {
        // encodeURIComponent が触らない文字はそのまま。
        assert_eq!(url_segment("aA0-_.!~*'()"), "aA0-_.!~*'()");
        // 触る文字は %XX (大文字 hex)。
        assert_eq!(url_segment("@"), "%40");
        assert_eq!(url_segment("×"), "%C3%97");
        assert_eq!(url_segment("ふ"), "%E3%81%B5");
        assert_eq!(url_segment(" "), "%20");
        assert_eq!(url_segment("/"), "%2F");
    }

    #[test]
    fn detail_path_is_trailing_slashed() {
        assert_eq!(detail_path("songs", "ml_x"), "/songs/ml_x/");
        assert_eq!(detail_path("events", "a@b"), "/events/a%40b/");
    }

    #[test]
    fn fnv1a64_matches_reference_vectors() {
        // 参照値 (FNV-1a 64bit の公開テストベクタ)。
        assert_eq!(fnv1a64(""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a64("a"), 0xaf63_dc4c_8601_ec8c);
        assert_eq!(fnv1a64("foobar"), 0x85944171f73967e8);
    }
}
