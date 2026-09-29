//! 色の読み上げ名 (VoiceOver 用)。`#FF69B4` → 「ピンク」。
//!
//! iOS の `ColorDotView` と `PenlightColorBar` に同じ表が 2 つ写してあり、表に無い色は
//! 「先頭 4 桁が同じ色」を Dictionary の for-in で探していたので、候補が 2 つある
//! 桁 (`FFFF` = 黄 / 白、`00FF` = 緑 / 水色、`0000` = 青 / 黒) では起動のたびに
//! 読み上げが変わりえた。ここで 1 つにして、決め方を決定的にする (§8 P5-10)。

/// 主要色の表 (大文字 6 桁 → 名前)。
const COLOR_NAMES: [(&str, &str); 29] = [
    ("FF0000", "赤"), ("FF3333", "赤"), ("CC0000", "赤"),
    ("0000FF", "青"), ("3333FF", "青"), ("0033CC", "青"),
    ("FFFF00", "黄"), ("FFCC00", "黄"),
    ("00FF00", "緑"), ("33CC33", "緑"), ("008000", "緑"),
    ("FF69B4", "ピンク"), ("FF1493", "ピンク"), ("FF66B2", "ピンク"),
    ("FFA500", "オレンジ"), ("FF8C00", "オレンジ"),
    ("800080", "紫"), ("9B59B6", "紫"), ("8B008B", "紫"),
    ("FFFFFF", "白"), ("F5F5F5", "白"),
    ("000000", "黒"), ("1A1A1A", "黒"),
    ("808080", "グレー"), ("A9A9A9", "グレー"),
    ("00FFFF", "水色"), ("00CED1", "水色"),
    ("8B4513", "茶"), ("A0522D", "茶"),
];

/// 色が無いときの名前。
pub const UNKNOWN_COLOR_NAME: &str = "不明";

fn blue_channel(hex: &str) -> Option<u8> {
    hex.get(4..6).and_then(|b| u8::from_str_radix(b, 16).ok())
}

/// 色の名前。表にそのままあればその名前、無ければ**先頭 4 桁 (赤と緑) が同じ**表の色のうち
/// 青の成分がいちばん近いもの (同じ近さなら表の順で先)、それも無ければ `#RRGGBB` のまま。
/// `#` は前後どちらにあっても落とし、大文字にして比べる。
pub fn color_name(hex: Option<&str>) -> String {
    let normalized = hex.map(|h| h.trim_matches('#').to_uppercase()).unwrap_or_default();
    if normalized.is_empty() {
        return UNKNOWN_COLOR_NAME.to_string();
    }
    if let Some((_, name)) = COLOR_NAMES.iter().find(|(key, _)| *key == normalized) {
        return name.to_string();
    }
    let prefix: String = normalized.chars().take(4).collect();
    let blue = blue_channel(&normalized);
    let nearest = COLOR_NAMES
        .iter()
        .enumerate()
        .filter(|(_, (key, _))| key.starts_with(prefix.as_str()))
        .min_by_key(|(order, (key, _))| {
            let distance = match (blue, blue_channel(key)) {
                (Some(b), Some(k)) => b.abs_diff(k) as u16,
                _ => u16::MAX,
            };
            (distance, *order)
        });
    match nearest {
        Some((_, (_, name))) => name.to_string(),
        None => format!("#{normalized}"),
    }
}

/// ペンライトの色の帯の読み上げ (`ペンライト: 2色 ピンク、白`)。
pub fn penlight_label(hexes: &[String]) -> String {
    let names: Vec<String> = hexes.iter().map(|h| color_name(Some(h))).collect();
    format!("ペンライト: {}色 {}", hexes.len(), names.join("、"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_colors_read_their_names() {
        assert_eq!(color_name(Some("#FF69B4")), "ピンク");
        assert_eq!(color_name(Some("ff69b4")), "ピンク", "大文字小文字を問わない");
        assert_eq!(color_name(Some("#000000")), "黒");
        assert_eq!(color_name(None), "不明");
        assert_eq!(color_name(Some("#")), "不明", "空は色が無いのと同じ (以前は表から無作為に 1 つ)");
    }

    /// 先頭 4 桁に候補が 2 つある桁でも、毎回同じ名前になる (青の成分が近い方)。
    #[test]
    fn prefix_collisions_are_resolved_deterministically() {
        assert_eq!(color_name(Some("#FFFFF0")), "白");
        assert_eq!(color_name(Some("#FFFF10")), "黄");
        assert_eq!(color_name(Some("#00FFF0")), "水色");
        assert_eq!(color_name(Some("#00FF20")), "緑");
        assert_eq!(color_name(Some("#0000F0")), "青");
        assert_eq!(color_name(Some("#000010")), "黒");
        for _ in 0..20 {
            assert_eq!(color_name(Some("#FFFF80")), color_name(Some("#FFFF80")));
        }
    }

    #[test]
    fn unknown_colors_fall_back_to_the_hex() {
        assert_eq!(color_name(Some("#123456")), "#123456");
        assert_eq!(color_name(Some("abc")), "#ABC");
    }

    #[test]
    fn penlight_label_matches_the_ios_wording() {
        assert_eq!(
            penlight_label(&["#FF69B4".to_string(), "#FFFFFF".to_string()]),
            "ペンライト: 2色 ピンク、白"
        );
        assert_eq!(penlight_label(&[]), "ペンライト: 0色 ");
    }
}
