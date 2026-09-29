//! 担当テーマ色解決の FFI 面。ロジックは domain::oshi_theme_resolution。
//!
//! アイドルのエンティティ全体は渡さず、射影 (`OshiThemePickIdol`) の列を受けて
//! 解決結果 (`OshiThemeResolution`) を 1 呼び出しで返す。担当は高々数十人なので
//! 射影列をそのまま渡しても境界コストは無視できる。

use crate::domain::oshi_theme_resolution::{OshiThemePickIdol, OshiThemeResolution};

/// 担当テーマ色を、現在の選択と担当一覧 (射影) から解決する。
/// `idol_id: None` は「現在の選択を変更しない」(OFF のとき)。
#[uniffi::export]
pub fn resolve_oshi_theme(
    is_enabled: bool,
    current_idol_id: String,
    pick_idols: Vec<OshiThemePickIdol>,
) -> OshiThemeResolution {
    crate::domain::oshi_theme_resolution::resolve_oshi_theme(
        is_enabled,
        &current_idol_id,
        &pick_idols,
    )
}
