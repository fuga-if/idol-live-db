//! 画面構成の FFI 口。

use crate::domain::idol_queries::IdolProfileSource;
use crate::domain::screen_composition::{
    idol_profile_rows as rows, setlist_display_mode_from_stored as mode_from_stored,
    setlist_display_modes as modes, IdolProfileInput, ScreenRow, SetlistDisplayMode,
    SetlistDisplayModeOption,
};

/// アイドル詳細のプロフィール行を組み立てる (1 画面 = 1 呼び出し)。
#[uniffi::export]
pub fn idol_profile_rows(input: IdolProfileInput) -> Vec<ScreenRow> {
    rows(&input)
}

/// プロフィール行を**生の値から**組み立てる (1 画面 = 1 呼び出し)。
/// 「4月3日」「160cm」「A型 ・ 牡羊座」の整形もコアが持つ。アプリはエンティティを
/// [`IdolProfileSource`] に詰め替えて渡すだけにする。
#[uniffi::export]
pub fn idol_profile_rows_from_source(source: IdolProfileSource) -> Vec<ScreenRow> {
    crate::domain::idol_queries::idol_profile_rows_from_source(&source)
}

/// セトリの表示モードの選択肢一式 (順・保存値・文言)。
///
/// **これを並べるだけにする。** 3 モードの文言を各 OS の enum に書き写すと、
/// 言い方を直したときに 1 面だけ古いまま残る (`performer_name_options` と同じ理由)。
#[uniffi::export]
pub fn setlist_display_modes() -> Vec<SetlistDisplayModeOption> {
    modes()
}

/// 曲名と歌唱者だけに絞る形か。**行の作りを選ぶのはこの 1 本**で、
/// 各 OS が `mode == .simple` を書かないようにする
/// (モードが増えたとき、条件が両 OS に散らばっているとどちらかが取り残される)。
#[uniffi::export]
pub fn setlist_display_mode_is_compact(mode: SetlistDisplayMode) -> bool {
    mode.is_compact()
}

/// 保存されている値からセトリの表示モードを決める。
///
/// `legacy_simple_mode` は 3 値にする前の Bool (`setlist_simple_mode`)。
/// 新しい鍵がまだ無い端末はこれで移行する (判断はコア側 docs を参照)。
#[uniffi::export]
pub fn setlist_display_mode_from_stored(
    raw: Option<String>,
    legacy_simple_mode: bool,
) -> SetlistDisplayMode {
    mode_from_stored(raw.as_deref(), legacy_simple_mode)
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
