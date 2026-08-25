//! Driven (secondary) アダプタ層: ポートの裏の具体実装。
//! ここだけが rusqlite に依存してよい (domain は依存しない)。
pub mod sqlite_loader;

pub mod schema_apply;
