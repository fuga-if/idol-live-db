//! 声で答えるイントロドンの照合 (聞き取った文字列が、正解の曲名に当たるか)。
//!
//! iOS の `SpeechRecognitionService` だけにあった (Android に声の回答は無い)。
//! **かな・ローマ字への変換と読みの取り出しは OS に残す** (CFStringTransform や形態素の
//! 読みは OS の機能)。ここに置くのは、変換済みの文字列を受け取ってからの判断:
//! 曲名の飾りの落とし方・照合に使う綴りの選び方・閾値・「順に拾えるか」の照合。
//!
//! 文字数は Unicode のスカラー値で数える (Swift は書記素で数えていた。照合に使う綴りは
//! かなと英数字だけに正規化済みなので、実質は変わらない)。

/// 曲名の飾りを落とす: 括弧の中 (`(…)` `（…）` `[…]` `【…】` `〜…〜` `~…~`)、
/// ` / ` ` : ` ` - ` から後ろ、`feat.` `ft.` `with` から後ろ、記号・絵文字。
/// `@` / `＠` は `a` と読む (`M@STER` → `MaSTER`)。
pub fn strip_title_decorations(title: &str) -> String {
    let mut text = title.replace(['@', '＠'], "a");
    for (open, close) in [('(', ')'), ('（', '）'), ('[', ']'), ('【', '】'), ('〜', '〜'), ('~', '~')] {
        text = remove_bracketed(&text, open, close);
    }
    for separators in [&['/', '／'][..], &[':', '：'][..], &['-'][..]] {
        if let Some(at) = text.find(separators) {
            text = cut_before_whitespace(&text, at);
        }
    }
    for word in ["feat", "ft", "with"] {
        if let Some(at) = find_credit_word(&text, word) {
            text = cut_before_whitespace(&text, at);
        }
    }
    let kept: String = text
        .chars()
        .filter(|c| {
            let v = *c as u32;
            v < 0x2600 || (0x3040..=0x9FFF).contains(&v) || (0xFF00..=0xFF9F).contains(&v)
        })
        .collect();
    kept.trim().to_string()
}

/// `open` から次の `close` までを (両端ごと) 左から順に全部落とす。閉じが無ければそこで止める。
fn remove_bracketed(text: &str, open: char, close: char) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find(open) {
        let after_open = &rest[start + open.len_utf8()..];
        let Some(end) = after_open.find(close) else { break };
        out.push_str(&rest[..start]);
        rest = &after_open[end + close.len_utf8()..];
    }
    out.push_str(rest);
    out
}

/// `at` から後ろと、その直前に続く空白を落とす。
fn cut_before_whitespace(text: &str, at: usize) -> String {
    text[..at].trim_end().to_string()
}

/// `word` (大文字小文字を問わない) の後に `.` があってもよく、その後に空白が続く最初の位置。
fn find_credit_word(text: &str, word: &str) -> Option<usize> {
    let lower = text.to_ascii_lowercase();
    let mut from = 0;
    while let Some(found) = lower[from..].find(word) {
        let at = from + found;
        let mut tail = lower[at + word.len()..].chars();
        let mut next = tail.next();
        if next == Some('.') {
            next = tail.next();
        }
        if next.is_some_and(char::is_whitespace) {
            return Some(at);
        }
        from = at + word.len();
    }
    None
}

/// 照合に使う正解の綴り。OS が曲名 ([`strip_title_decorations`] を通したもの) から作った
/// 綴りをそのまま渡し、[`voice_answer_targets`] で選ぶ。
#[derive(uniffi::Record, Clone, Debug, Default, PartialEq, Eq)]
pub struct VoiceAnswerTargets {
    /// かなの綴り (正規化・カタカナ・ローマ字・読み)。重なりは除いてある。
    pub variants: Vec<String>,
    /// 英字の綴り (`Any-Latin` → ASCII)。
    pub latin_variants: Vec<String>,
}

/// OS が変換した綴りから、照合に使うものを選ぶ (2 文字以上のものだけ・重なりは 1 つ)。
/// カタカナとローマ字は、正規化した形と同じなら加えない。
pub fn voice_answer_targets(
    normalized: &str,
    katakana: &str,
    romaji: &str,
    reading: &str,
    latin: &str,
) -> VoiceAnswerTargets {
    let long_enough = |s: &str| s.chars().count() >= 2;
    let mut variants: Vec<String> = Vec::new();
    let mut push = |s: &str| {
        if long_enough(s) && !variants.iter().any(|v| v == s) {
            variants.push(s.to_string());
        }
    };
    push(normalized);
    if katakana != normalized {
        push(katakana);
    }
    if romaji != normalized {
        push(romaji);
    }
    push(reading);
    let latin_variants = if long_enough(latin) { vec![latin.to_string()] } else { Vec::new() };
    VoiceAnswerTargets { variants, latin_variants }
}

/// 聞き取った文字列を OS が変換したもの。聞き取りが途中で切れて貼り合わせたものは `combined_*`。
#[derive(uniffi::Record, Clone, Debug, Default, PartialEq, Eq)]
pub struct VoiceHeard {
    /// 今回の聞き取りを正規化したもの (かなはカタカナに寄せ、記号を落とす)。
    pub normalized: String,
    /// 漢字を含むときの読み (正規化済み)。無ければ `None`。
    pub reading: Option<String>,
    /// それまでの聞き取りと貼り合わせて正規化したもの。貼り合わせるものが無ければ `None`。
    pub combined: Option<String>,
    /// 貼り合わせたものの読み。
    pub combined_reading: Option<String>,
    /// 今回の聞き取りの英字。
    pub latin: String,
    /// 貼り合わせたものの英字。
    pub combined_latin: Option<String>,
}

/// 漢字を含むか (含むときだけ、OS は形態素の読みを取って [`VoiceHeard::reading`] に渡す)。
pub fn needs_reading(text: &str) -> bool {
    text.chars().any(|c| ('\u{4E00}'..='\u{9FFF}').contains(&c))
}

fn len(s: &str) -> usize {
    s.chars().count()
}

/// 正解の綴りの文字を、聞き取った文字列の中から順に拾っていって 7 割拾えれば当たり。
/// 聞き取り側が短すぎる (正解の 6 割未満) ときは当たりにしない。
pub fn sequential_match(input: &str, target: &str) -> bool {
    let target_len = len(target);
    if target_len < 2 || len(input) < (target_len * 6 / 10).max(2) {
        return false;
    }
    let mut chars = input.chars();
    let matched = target.chars().filter(|t| chars.by_ref().any(|c| c == *t)).count();
    matched >= target_len * 7 / 10
}

/// 読みが元の綴りと違うときだけ、その読み (同じなら照合し直す意味が無い)。
fn other_reading<'a>(reading: &'a Option<String>, base: &str) -> Option<&'a str> {
    reading.as_deref().filter(|r| *r != base)
}

fn hits(input: &str, target: &str) -> bool {
    input.contains(target) || sequential_match(input, target)
}

/// 聞き取った文字列が正解に当たるか。
///
/// - 聞き取りが短すぎる (いちばん短い綴りの 7 割、少なくとも 3 文字に満たない) ときは判定しない。
/// - 照合に使う綴りは 3 文字以上のものだけ。
/// - 今回の聞き取り → その読み → 貼り合わせ → その読み → 英字 の順に、含むか・順に拾えるかを見る。
///   英字の貼り合わせは「含むか」だけを見る。
pub fn voice_answer_matches(targets: &VoiceAnswerTargets, heard: &VoiceHeard) -> bool {
    let min_target_len = targets
        .variants
        .iter()
        .chain(&targets.latin_variants)
        .map(|t| len(t))
        .min()
        .unwrap_or(2);
    if len(&heard.normalized) < (min_target_len * 7 / 10).max(3) {
        return false;
    }
    let kana: Vec<&str> = targets.variants.iter().map(String::as_str).filter(|t| len(t) >= 3).collect();
    let kana_hit = |input: &str| kana.iter().any(|t| hits(input, t));
    if kana_hit(&heard.normalized)
        || other_reading(&heard.reading, &heard.normalized).is_some_and(kana_hit)
    {
        return true;
    }
    if let Some(combined) = heard.combined.as_deref() {
        if kana_hit(combined) || other_reading(&heard.combined_reading, combined).is_some_and(kana_hit) {
            return true;
        }
    }
    let combined_latin = heard.combined_latin.as_deref().unwrap_or(&heard.latin);
    targets.latin_variants.iter().filter(|t| len(t) >= 3).any(|t| {
        hits(&heard.latin, t) || (combined_latin != heard.latin && combined_latin.contains(t.as_str()))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decorations_are_stripped_like_the_ios_patterns() {
        assert_eq!(strip_title_decorations("Thank You! (M@STER VERSION)"), "Thank You!");
        assert_eq!(strip_title_decorations("THE IDOLM@STER"), "THE IDOLMaSTER");
        assert_eq!(strip_title_decorations("お願い！シンデレラ 【CGSS】"), "お願い！シンデレラ");
        assert_eq!(strip_title_decorations("曲名 / 別の名前"), "曲名");
        assert_eq!(strip_title_decorations("曲名：副題"), "曲名");
        assert_eq!(strip_title_decorations("Song - Remix"), "Song");
        assert_eq!(strip_title_decorations("Song feat. Someone"), "Song");
        assert_eq!(strip_title_decorations("Song FT someone"), "Song");
        assert_eq!(strip_title_decorations("Stay with me"), "Stay");
        assert_eq!(strip_title_decorations("featuring"), "featuring", "後ろに空白の無い feat は飾りではない");
        assert_eq!(strip_title_decorations("〜序曲〜 本編"), "本編");
        assert_eq!(strip_title_decorations("星★"), "星", "記号は落とす");
        assert_eq!(strip_title_decorations("(閉じない"), "(閉じない");
    }

    #[test]
    fn targets_keep_distinct_spellings_of_two_or_more_chars() {
        let t = voice_answer_targets("オネガイシンデレラ", "オネガイシンデレラ", "onegaishinderera", "オネガイシンデレラ", "onegaishinderera");
        assert_eq!(t.variants, vec!["オネガイシンデレラ".to_string(), "onegaishinderera".to_string()]);
        assert_eq!(t.latin_variants, vec!["onegaishinderera".to_string()]);
        let short = voice_answer_targets("ア", "ア", "a", "", "a");
        assert!(short.variants.is_empty() && short.latin_variants.is_empty());
    }

    #[test]
    fn sequential_match_needs_seventy_percent_in_order() {
        assert!(sequential_match("オネガイシンデレラ", "オネガイシンデレラ"));
        assert!(sequential_match("オネガイノシンデレラ", "オネガイシンデレラ"), "間に余計な字があってもよい");
        assert!(!sequential_match("シンデレラ", "オネガイシンデレラ"), "頭の字が見つからないと先を拾えない");
        assert!(!sequential_match("オネ", "オネガイシンデレラ"), "聞き取りが短すぎる");
    }

    fn targets() -> VoiceAnswerTargets {
        voice_answer_targets("オネガイシンデレラ", "オネガイシンデレラ", "onegaishinderera", "オネガイシンデレラ", "onegaishinderera")
    }

    #[test]
    fn heard_text_hits_through_any_of_the_forms() {
        let exact = VoiceHeard { normalized: "オネガイシンデレラ".into(), latin: "onegaishinderera".into(), ..Default::default() };
        assert!(voice_answer_matches(&targets(), &exact));
        // 今回だけでは足りないが、前の聞き取りと貼り合わせると当たる。
        let split = VoiceHeard {
            normalized: "イシンデレラ".into(),
            combined: Some("オネガイシンデレラ".into()),
            latin: "ishinderera".into(),
            ..Default::default()
        };
        assert!(voice_answer_matches(&targets(), &split));
        assert!(
            !voice_answer_matches(&targets(), &VoiceHeard { combined: None, ..split.clone() }),
            "貼り合わせが無ければ当たらない"
        );
        // 漢字で聞き取られても、読みで当たる。
        let kanji = VoiceHeard {
            normalized: "御願いシンデレラ".into(),
            reading: Some("オネガイシンデレラ".into()),
            latin: "yuanxinderera".into(),
            ..Default::default()
        };
        assert!(voice_answer_matches(&targets(), &kanji));
        assert!(!voice_answer_matches(&targets(), &VoiceHeard { reading: None, ..kanji }), "読みが無ければ当たらない");
    }

    #[test]
    fn too_short_current_text_is_not_judged_even_if_the_combined_text_would_hit() {
        // 判定するかは今回の聞き取りの長さで決める (いちばん短い綴り 9 字の 7 割 = 6 字)。
        let split = VoiceHeard {
            normalized: "シンデレラ".into(),
            combined: Some("オネガイシンデレラ".into()),
            latin: "shinderera".into(),
            ..Default::default()
        };
        assert!(!voice_answer_matches(&targets(), &split));
    }

    #[test]
    fn readings_are_needed_only_for_kanji() {
        assert!(needs_reading("お願い"));
        assert!(!needs_reading("おねがい"));
        assert!(!needs_reading("Thank You"));
    }

    #[test]
    fn short_or_unrelated_text_does_not_hit() {
        let short = VoiceHeard { normalized: "オネ".into(), latin: "one".into(), ..Default::default() };
        assert!(!voice_answer_matches(&targets(), &short), "短すぎる聞き取りは判定しない");
        let other = VoiceHeard { normalized: "スターライトステージ".into(), latin: "sutaraitosuteji".into(), ..Default::default() };
        assert!(!voice_answer_matches(&targets(), &other));
    }
}
