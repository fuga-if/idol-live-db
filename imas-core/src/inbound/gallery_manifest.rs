//! 画像ギャラリーの manifest の FFI 面。規則は [`crate::domain::gallery_manifest`]。

use crate::domain::gallery_manifest::{self as domain, GalleryImageMeta};

/// 保存された manifest (無ければ None) とフォルダの画像ファイル名から、並び順 (先頭が代表) を決める。
#[uniffi::export]
pub fn gallery_manifest_reconcile(saved: Option<String>, files_on_disk: Vec<String>) -> Vec<GalleryImageMeta> {
    domain::reconcile(saved.as_deref(), &files_on_disk)
}

/// manifest.json に書く文字列。
#[uniffi::export]
pub fn gallery_manifest_encode(entries: Vec<GalleryImageMeta>) -> String {
    domain::encode(&entries)
}

/// ウィジェットのスライドショーに出すもの (1 枚も選ばれていなければ全件)。
#[uniffi::export]
pub fn gallery_slideshow_entries(entries: Vec<GalleryImageMeta>) -> Vec<GalleryImageMeta> {
    domain::slideshow_entries(&entries)
}
