//! 画面構成の FFI 口。

use crate::domain::screen_composition::{idol_profile_rows as rows, IdolProfileInput, ScreenRow};

/// アイドル詳細のプロフィール行を組み立てる (1 画面 = 1 呼び出し)。
#[uniffi::export]
pub fn idol_profile_rows(input: IdolProfileInput) -> Vec<ScreenRow> {
    rows(&input)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delegates_without_logic() {
        let input = IdolProfileInput {
            name_kana: Some("あ".into()),
            color: Some("#FFF".into()),
            ..Default::default()
        };
        assert_eq!(idol_profile_rows(input.clone()), rows(&input));
    }
}
