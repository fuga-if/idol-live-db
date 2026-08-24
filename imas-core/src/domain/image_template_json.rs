//! 画像一括インポート用の「型紙」JSON の組み立て。
//!
//! アイドル名/ブランド名/ユニット名をキーに、URL を空文字で並べた JSON を配って
//! ユーザーに埋めてもらう仕組み。名前には `"` や `\` や絵文字が入りうるので、
//! 手書きの継ぎ接ぎではなく専用のエスケープ関数で文字列化する。
//!
//! 出力はキー順を保つ (汎用シリアライザに辞書を渡すと順序が崩れるため、
//! 1 行ずつ組み立てている)。名前の並び = 一覧の並びのままにしておかないと、
//! 数百行の型紙から目的のアイドルを探すのが難しくなる。
//!
//! # なぜ serde_json でエスケープしないか
//!
//! iOS 版 (`JSONSerialization`) が既に配った型紙とバイト単位で同一の出力を
//! 保つため。`JSONSerialization` は既定で `/` を `\/` に エスケープするが、
//! serde_json はしない (どちらも合法な JSON だが表現が変わる)。
//! 他にも 0x08/0x0C を `\b`/`\f` の短縮形で書く・その他の制御文字は
//! 小文字 16 進の `\u00xx`・非 ASCII は生 UTF-8 のまま、という
//! `JSONSerialization` の流儀をここで再現している (Darwin 実機で確認済み)。

/// 型紙の 1 行分 (キー = 名前、値 = URL。生成時点では値は空文字)。
///
/// FFI 境界にはエンティティ全体ではなく、この射影だけを渡す。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ImageTemplatePair {
    pub key: String,
    pub value: String,
}

/// 画像一括インポート用の型紙 JSON を組み立てる。
///
/// - 入力順のまま 1 ペア 1 行で出力する (順序保持が要件)。
/// - 空入力は `{\n}` (`{}` ではない)。iOS 版の行組み立ての結果をそのまま踏襲。
/// - キーの重複排除はしない (呼び出し側の一覧に重複がなければ出ない)。
pub fn image_template_json(pairs: &[ImageTemplatePair]) -> String {
    let mut lines: Vec<String> = vec!["{".to_string()];
    for (i, pair) in pairs.iter().enumerate() {
        let comma = if i < pairs.len() - 1 { "," } else { "" };
        lines.push(format!(
            "  {}: {}{}",
            json_string_literal(&pair.key),
            json_string_literal(&pair.value),
            comma
        ));
    }
    lines.push("}".to_string());
    lines.join("\n")
}

/// 文字列を JSON のリテラル (引用符込み) にする。
///
/// Darwin の `JSONSerialization` (options: []) と同じエスケープ規則:
/// `"` → `\"`, `\` → `\\`, `/` → `\/`, 0x08 → `\b`, 0x0C → `\f`,
/// LF/CR/TAB → `\n`/`\r`/`\t`, その他の 0x00..0x1F → 小文字 `\u00xx`。
/// 非 ASCII (日本語・絵文字・U+2028 等) はエスケープせず生のまま。
pub fn json_string_literal(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '/' => out.push_str("\\/"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0C}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pair(key: &str, value: &str) -> ImageTemplatePair {
        ImageTemplatePair {
            key: key.to_string(),
            value: value.to_string(),
        }
    }

    // ---- 全体の組み立て (期待値は iOS 実装を Darwin で実行した出力そのまま) ----

    /// 空入力。行組み立ての仕様上 `{}` ではなく `{\n}` になる。
    #[test]
    fn empty_input_is_open_close_braces_on_two_lines() {
        assert_eq!(image_template_json(&[]), "{\n}");
    }

    /// 単一要素。末尾カンマなし。
    #[test]
    fn single_pair_has_no_trailing_comma() {
        let json = image_template_json(&[pair("如月千早", "")]);
        assert_eq!(json, "{\n  \"如月千早\": \"\"\n}");
    }

    /// 複数要素は最後以外にカンマ。入力順を保つ。
    #[test]
    fn multiple_pairs_keep_input_order_with_commas() {
        let json = image_template_json(&[pair("B", ""), pair("A", ""), pair("C", "")]);
        assert_eq!(json, "{\n  \"B\": \"\",\n  \"A\": \"\",\n  \"C\": \"\"\n}");
    }

    /// 同値キーが並んでも重複排除せず、入力順のまま両方出す (順序安定性)。
    #[test]
    fn duplicate_keys_are_kept_in_input_order() {
        let json = image_template_json(&[pair("A", ""), pair("A", ""), pair("B", "")]);
        assert_eq!(json, "{\n  \"A\": \"\",\n  \"A\": \"\",\n  \"B\": \"\"\n}");
    }

    /// URL 入りの値: `/` が `\/` になる (JSONSerialization 互換)。
    /// Darwin での実行結果と 1 バイトも違わないことを固定する。
    #[test]
    fn value_with_url_escapes_slashes_like_json_serialization() {
        let json = image_template_json(&[
            pair("A", ""),
            pair("A", ""),
            pair("B\"x", "https://example.com/a.png"),
        ]);
        assert_eq!(
            json,
            "{\n  \"A\": \"\",\n  \"A\": \"\",\n  \"B\\\"x\": \"https:\\/\\/example.com\\/a.png\"\n}"
        );
    }

    // ---- json_string_literal (期待値は Darwin の JSONSerialization 出力) ----

    #[test]
    fn literal_escapes_quote_backslash_slash() {
        assert_eq!(json_string_literal("a\"b"), r#""a\"b""#);
        assert_eq!(json_string_literal("a\\b"), r#""a\\b""#);
        assert_eq!(json_string_literal("a/b"), r#""a\/b""#);
    }

    #[test]
    fn literal_uses_short_escapes_for_common_controls() {
        assert_eq!(json_string_literal("a\nb"), r#""a\nb""#);
        assert_eq!(json_string_literal("a\tb"), r#""a\tb""#);
        assert_eq!(json_string_literal("a\rb"), r#""a\rb""#);
        assert_eq!(json_string_literal("a\u{08}b"), r#""a\bb""#);
        assert_eq!(json_string_literal("a\u{0C}b"), r#""a\fb""#);
    }

    /// その他の制御文字は小文字 16 進の \u00xx (JSONSerialization は大文字にしない)。
    #[test]
    fn literal_uses_lowercase_u_escape_for_other_controls() {
        assert_eq!(json_string_literal("a\u{01}b"), r#""a\u0001b""#);
        assert_eq!(json_string_literal("a\u{1F}b"), r#""a\u001fb""#);
    }

    /// 非 ASCII はエスケープせず生 UTF-8。DEL (0x7F) や U+2028 も生のまま
    /// (JSONSerialization は 0x20 以上を一切エスケープしない)。
    #[test]
    fn literal_passes_non_ascii_through() {
        assert_eq!(json_string_literal("如月千早"), "\"如月千早\"");
        assert_eq!(json_string_literal("🎤アイドル"), "\"🎤アイドル\"");
        assert_eq!(json_string_literal("a\u{7F}b"), "\"a\u{7F}b\"");
        assert_eq!(json_string_literal("a\u{2028}b"), "\"a\u{2028}b\"");
    }

    /// 混在ケース (Darwin での実行結果と一致)。
    #[test]
    fn literal_combined_case_matches_darwin_output() {
        assert_eq!(
            json_string_literal("P\"A\\L/日\n🎶"),
            "\"P\\\"A\\\\L\\/日\\n🎶\""
        );
    }

    // ---- 妥当性: 出力が合法な JSON で、値が復元できること ----

    /// エスケープを自前実装しているので、serde_json でパースし直して
    /// 「合法な JSON であること」「キー/値が正しく復元されること」を保証する。
    #[test]
    fn output_round_trips_through_serde_json() {
        let pairs = [
            pair("如月千早", ""),
            pair("P\"A\\L/日\n🎶", "https://example.com/x.png"),
            pair("\u{01}\u{1F}\u{08}\u{0C}\t\r", ""),
        ];
        let json = image_template_json(&pairs);
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid JSON");
        let obj = parsed.as_object().expect("JSON object");
        for p in &pairs {
            assert_eq!(obj.get(&p.key).and_then(|v| v.as_str()), Some(p.value.as_str()));
        }
    }
}
