//! コール表の画像を、利用者の ChatGPT プランに読ませる。
//!
//! 頼むのは**書き写しだけ**: 画像に書いてある歌詞の行と、その行のどの字にどのコールが
//! 掛かっているか。ツールは渡さない (DB を引く用が無い)。1 往復で終わる。
//!
//! 答えの検証と、歌詞・コールの下書きへの直し方は [`crate::domain::call_guide_import`]。
//! モデルは有名な曲の歌詞を覚えで補うことがあるので、指示で禁じたうえで、端末の文字認識の
//! 字と突き合わせて裏の取れない行に印を付ける (あちらの `read_sheet`)。

use super::plan_loop::{parse_object, Request};
use crate::domain::call_guide_import::{read_sheet, CallSheetReading, MAX_IMAGES};
use serde_json::{json, Value};

const INSTRUCTIONS: &str = "\
あなたは、ライブのコール表 (歌詞にコールや手拍子の指示を書き込んだ画像) を書き写す係です。\n\
\n\
# 決まり\n\
- 画像に書いてある字だけを、書いてあるとおりに写す。**覚えている歌詞で補わない・直さない・足さない。**\n\
  読めない字は飛ばす。画像に歌詞もコールも無ければ lines を空にする。\n\
- 歌詞の行 (歌う字の行) を上から順に lines に入れる。行頭の ♪ などの印、曲名、作詞作曲の表記、凡例、版の番号は入れない。\n\
- 歌詞の行の中の括弧書きは、歌詞と同じ色・同じ書体で書いてあるものだけ歌詞に含める。\n\
  色違いで書き足された字 (コール) は、括弧に入っていても歌詞に入れない。振り仮名 (字の上の小さな字) は入れない。\n\
- 塊の変わり目 (前の行との間が空いている) は break_before を true にする。\n\
- 歌詞の行の下や脇に、色違いで書き込まれた字がコール。その行の calls に左から順に入れる。\n\
  - text: コールの字 (書いてあるとおり)。\n\
  - anchor: そのコールの真上にある歌詞の断片 (その行の lyric から、そのまま抜き出す)。\n\
    真上に歌詞が無い (歌の隙間で叫ぶ) ときは、直前の歌詞の断片を入れる。分からなければ空文字。\n\
  - timing: 歌と同じ字を同時に叫ぶなら over、歌のあと・隙間に返すなら after。\n\
- 手拍子の指示は、画像の凡例で種類が分かるときだけ、その行の clap に入れる\n\
  (裏拍 = back_beat、4 つ打ち = four_on_floor、PPPH = ppph)。分からなければ null にし、\n\
  書き込まれた字 (パッ パッ など) を calls に text としてそのまま入れる。\n\
- 複数の画像は、渡された順に続きとして読む。\n\
- 答えは決められた型の JSON だけ。説明は書かない。";

fn text_format() -> Value {
    json!({
        "type": "json_schema",
        "name": "call_sheet",
        "strict": true,
        "schema": {
            "type": "object",
            "properties": {
                "lines": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "lyric": { "type": "string" },
                            "break_before": { "type": "boolean" },
                            "clap": { "type": ["string", "null"], "enum": ["back_beat", "four_on_floor", "ppph", null] },
                            "calls": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "text": { "type": "string" },
                                        "anchor": { "type": "string" },
                                        "timing": { "type": "string", "enum": ["over", "after"] }
                                    },
                                    "required": ["text", "anchor", "timing"],
                                    "additionalProperties": false
                                }
                            }
                        },
                        "required": ["lyric", "break_before", "clap", "calls"],
                        "additionalProperties": false
                    }
                }
            },
            "required": ["lines"],
            "additionalProperties": false
        }
    })
}

/// 1 回のリクエスト。`images_base64` は JPEG を base64 にしたもの (多ければ先頭の [`MAX_IMAGES`] 枚)。
/// 画像が無ければ None。曲名は渡さない (名前から歌詞を思い出させないため)。
pub fn request(images_base64: &[String]) -> Option<Request> {
    let images: Vec<&String> = images_base64.iter().filter(|s| !s.is_empty()).take(MAX_IMAGES).collect();
    if images.is_empty() {
        return None;
    }
    let mut content = vec![json!({ "type": "input_text", "text": "このコール表を書き写してください。" })];
    content.extend(
        images.iter().map(|b64| json!({ "type": "input_image", "image_url": format!("data:image/jpeg;base64,{b64}") })),
    );
    Some(Request {
        instructions: INSTRUCTIONS.to_string(),
        input: vec![json!({ "role": "user", "content": content }).to_string()],
        // ツールは渡さない (本文の組み立てで null は省かれる)。
        tools: Value::Null,
        text_format: text_format(),
    })
}

/// 答えの本文を読む。読めない・歌詞が無いなら None。`ocr_text` は端末の文字認識が同じ画像から拾った字。
pub fn answer(text: &str, ocr_text: &str) -> Option<CallSheetReading> {
    read_sheet(&parse_object(text)?, ocr_text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 画像を載せたリクエストを組む() {
        assert!(request(&[]).is_none());
        let many: Vec<String> = (0..6).map(|i| format!("AAA{i}")).collect();
        let req = request(&many).unwrap();
        let item: Value = serde_json::from_str(&req.input[0]).unwrap();
        let content = item["content"].as_array().unwrap();
        assert_eq!(content.len(), 1 + MAX_IMAGES);
        assert_eq!(content[1]["image_url"], "data:image/jpeg;base64,AAA0");
        assert!(req.tools.is_null());
        assert!(req.instructions.contains("覚えている歌詞で補わない"));
    }

    #[test]
    fn 答えを読む() {
        let text = r#"```json
{"lines":[{"lyric":"飛べ！渡米！","break_before":false,"clap":null,"calls":[{"text":"渡米！","anchor":"渡米！","timing":"over"}]}]}
```"#;
        let reading = answer(text, "飛べ!渡米!").unwrap();
        assert_eq!(reading.call_count, 1);
        assert!(reading.ocr_checked && reading.doubtful_lines == 0);
        assert!(answer("読めませんでした", "").is_none());
    }
}
