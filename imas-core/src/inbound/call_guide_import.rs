//! コール表の画像からの下書きの FFI 口。規則は `domain::call_guide_import`、
//! ChatGPT プランへの頼み方は `agent::tools::call_sheet_reader`。

use super::natural_search::PlanTaskRequest;
use crate::agent::tools::call_sheet_reader as reader;
use crate::domain::call_guide_import::{self as d, CallSheetPlacement, CallSheetReading, ImportTargetLine};

/// 1 回に読ませる画像の上限。
#[uniffi::export]
pub fn call_sheet_max_images() -> u32 {
    d::MAX_IMAGES as u32
}

/// 画像 (JPEG の base64) を読ませるリクエスト。画像が無ければ None。
#[uniffi::export]
pub fn call_sheet_request(images_base64: Vec<String>) -> Option<PlanTaskRequest> {
    reader::request(&images_base64).map(|r| {
        let mut request = PlanTaskRequest::from(r);
        // ツールを渡さないので 1 往復で終わる。
        request.max_rounds = 1;
        request.too_many_rounds_message = "画像を読めませんでした。もう一度試してください".into();
        request
    })
}

/// 答えの本文を読み、端末の文字認識の字と突き合わせる。使える中身でなければ None。
#[uniffi::export]
pub fn call_sheet_answer(text: String, ocr_text: String) -> Option<CallSheetReading> {
    reader::answer(&text, &ocr_text)
}

/// 歌詞の投稿画面の入力欄に入れる本文。
#[uniffi::export]
pub fn call_sheet_lyric_text(reading: CallSheetReading) -> String {
    d::lyric_text(&reading)
}

/// 歌詞の下書きに入る行の数 (文字認識で確かめられた行)。0 なら歌詞の下書きは作れない。
#[uniffi::export]
pub fn call_sheet_lyric_line_count(reading: CallSheetReading) -> u32 {
    d::lyric_line_count(&reading)
}

/// 読んだコールを今の歌詞 (本文の行だけ、表示順) に当てる。
#[uniffi::export]
pub fn call_sheet_place(reading: CallSheetReading, lines: Vec<ImportTargetLine>) -> CallSheetPlacement {
    d::place(&reading, &lines)
}
