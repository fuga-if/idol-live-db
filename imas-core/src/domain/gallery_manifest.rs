//! アイドル・ユニットの画像ギャラリーの `manifest.json`: 並び順とスライドショー対象の規則。
//!
//! 画像ファイルそのものは端末のフォルダにあり、manifest は「どの順に並べるか (先頭が代表)」と
//! 「ホーム画面ウィジェットのスライドショーに出すか」だけを持つ。両 OS が同じ規則を別々に
//! 書いていて、壊れた manifest の読み方が割れていた (iOS は 1 要素でも欠けると全体を捨て、
//! Android は要素ごとに読んでいた)。ここでは要素ごとに読む方に揃える。
//!
//! OS 側はフォルダの画像ファイル名を列挙して [`reconcile`] に渡し、書き戻すときは [`encode`] を
//! 通すだけにする。

use serde_json::Value;

/// ギャラリーの 1 枚。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct GalleryImageMeta {
    /// フォルダ内のファイル名。
    pub name: String,
    /// ホーム画面ウィジェットのスライドショーに出すか (既定 true)。
    #[uniffi(default = true)]
    pub in_slideshow: bool,
}

impl GalleryImageMeta {
    fn new(name: &str) -> Self {
        Self { name: name.to_string(), in_slideshow: true }
    }
}

/// `manifest.json` の中身を読む。オブジェクトの配列 (`{"name", "inSlideshow"}`) が今の形式で、
/// ファイル名だけの配列は旧形式 (全件スライドショー対象として読む)。読めない要素は飛ばす。
pub fn parse(text: &str) -> Vec<GalleryImageMeta> {
    let Ok(Value::Array(items)) = serde_json::from_str::<Value>(text) else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|item| match item {
            Value::String(name) if !name.is_empty() => Some(GalleryImageMeta::new(name)),
            Value::Object(obj) => {
                let name = obj.get("name")?.as_str().filter(|n| !n.is_empty())?;
                let in_slideshow = obj.get("inSlideshow").and_then(Value::as_bool).unwrap_or(true);
                Some(GalleryImageMeta { name: name.to_string(), in_slideshow })
            }
            _ => None,
        })
        .collect()
}

/// [`parse`] の逆。キー名は既存の manifest と同じ。
pub fn encode(entries: &[GalleryImageMeta]) -> String {
    let items: Vec<Value> = entries
        .iter()
        .map(|e| serde_json::json!({ "name": e.name, "inSlideshow": e.in_slideshow }))
        .collect();
    Value::Array(items).to_string()
}

/// 保存された manifest をフォルダの実体と突き合わせて、並び順 (先頭が代表) を決める。
///
/// - フォルダから消えたファイルの行は落とす。
/// - 同じファイル名が 2 回あれば最初だけ残す。重複があると同じ画像が 2 マスに出て、
///   片方を消すと両方消える。
/// - manifest に無いのにフォルダにある画像は、名前順で末尾に足す (取りこぼさない)。
///
/// `files_on_disk` には画像ファイルだけを渡す。
pub fn reconcile(saved: Option<&str>, files_on_disk: &[String]) -> Vec<GalleryImageMeta> {
    let on_disk: std::collections::HashSet<&str> = files_on_disk.iter().map(String::as_str).collect();
    let mut seen = std::collections::HashSet::new();
    let mut order: Vec<GalleryImageMeta> = saved
        .map(parse)
        .unwrap_or_default()
        .into_iter()
        .filter(|e| on_disk.contains(e.name.as_str()) && seen.insert(e.name.clone()))
        .collect();
    let mut missing: Vec<&str> = on_disk.iter().copied().filter(|n| !seen.contains(*n)).collect();
    missing.sort_unstable();
    order.extend(missing.into_iter().map(GalleryImageMeta::new));
    order
}

/// スライドショーに出すもの。`in_slideshow` のものだけ。1 枚も選ばれていなければ
/// 全件を出す (ウィジェットを空にしない)。
pub fn slideshow_entries(entries: &[GalleryImageMeta]) -> Vec<GalleryImageMeta> {
    let included: Vec<GalleryImageMeta> = entries.iter().filter(|e| e.in_slideshow).cloned().collect();
    if included.is_empty() { entries.to_vec() } else { included }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn meta(name: &str, in_slideshow: bool) -> GalleryImageMeta {
        GalleryImageMeta { name: name.into(), in_slideshow }
    }

    fn names(entries: &[GalleryImageMeta]) -> Vec<&str> {
        entries.iter().map(|e| e.name.as_str()).collect()
    }

    #[test]
    fn 旧形式はすべてスライドショー対象として読む() {
        assert_eq!(parse(r#"["a.jpg","b.jpg"]"#), vec![meta("a.jpg", true), meta("b.jpg", true)]);
    }

    #[test]
    fn 壊れた要素だけを飛ばして残りは読む() {
        let text = r#"[{"name":"a.jpg"},{"inSlideshow":false},"",42,{"name":"b.jpg","inSlideshow":false}]"#;
        assert_eq!(parse(text), vec![meta("a.jpg", true), meta("b.jpg", false)]);
    }

    #[test]
    fn 配列でなければ空() {
        assert!(parse("").is_empty());
        assert!(parse("{}").is_empty());
        assert!(parse("not json").is_empty());
    }

    #[test]
    fn 書いたものを読み戻せる() {
        let entries = vec![meta("a.jpg", false), meta("b \"x\".png", true)];
        assert_eq!(parse(&encode(&entries)), entries);
        assert_eq!(encode(&[]), "[]");
    }

    #[test]
    fn 消えたファイルを落とし_重複は最初だけ_無いものは名前順で足す() {
        let saved = r#"[{"name":"c.jpg","inSlideshow":false},{"name":"gone.jpg","inSlideshow":true},{"name":"c.jpg","inSlideshow":true}]"#;
        let disk = vec!["b.jpg".to_string(), "c.jpg".to_string(), "a.png".to_string()];
        let order = reconcile(Some(saved), &disk);
        assert_eq!(names(&order), vec!["c.jpg", "a.png", "b.jpg"]);
        assert!(!order[0].in_slideshow);
        assert!(order[1].in_slideshow);
    }

    #[test]
    fn manifest_が無ければフォルダの名前順() {
        let disk = vec!["b.jpg".to_string(), "a.jpg".to_string()];
        assert_eq!(names(&reconcile(None, &disk)), vec!["a.jpg", "b.jpg"]);
        assert!(reconcile(Some("[]"), &[]).is_empty());
    }

    #[test]
    fn 一枚も選ばれていなければ全件() {
        let entries = vec![meta("a", false), meta("b", false)];
        assert_eq!(slideshow_entries(&entries), entries);
        assert!(slideshow_entries(&[]).is_empty());
    }
}
