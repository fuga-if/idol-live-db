//! ImasLiveDB 共有ドメインコア。
//!
//! iOS (Swift) / Android (Kotlin) から UniFFI 経由で呼ばれる。
//! 構成は howtocodeit.com の Hexagonal in Rust に倣う (docs/SHARED_CORE_STUDY.md §7.5 の読み替え付き):
//!   - `domain/`  … 純粋ロジック + テスト。OS SDK / UI / DB エンジンに依存しない
//!   - `inbound/` … `#[uniffi::export]` の API 面 (= driving adapter との境界)。委譲のみ
//! FFI 境界の設計規約は README.md 参照 (1 操作 1 呼び出し、射影で渡して index で返す)。

uniffi::setup_scaffolding!();

pub mod domain;
pub mod inbound;
pub mod outbound;
