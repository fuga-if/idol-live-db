//! ImasLiveDB 共有ドメインコア。
//!
//! iOS (Swift) / Android (Kotlin) から UniFFI 経由で呼ばれる。
//! 設計方針は docs/SHARED_CORE_STUDY.md、依存規約は docs/ARCHITECTURE.md の
//! Domain 核と同じ: OS SDK / UI / DB エンジンに依存しない純粋ロジックのみを置く。

uniffi::setup_scaffolding!();

mod jst_day;

pub use jst_day::{jst_is_today_or_later, jst_today};
