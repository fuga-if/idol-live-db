//! ペンライトの指示 (ペンラ芸) の読み方。コールの一種 (`kind: "penlight"`) として歌詞の行に載る。
//!
//! 保存の形は Worker (imas-live-api/src/lyrics_calls.ts の `PenlightCue`) と 1:1 の契約:
//! - 色: `"oshi"` (各自の担当色) / `"idol:<idol_id>"` (そのアイドルの色) / `"#RRGGBB"` (決まった色) / なし
//! - 動き: `sway` / `pump` / `spin` / `raise` / `wave` / `off` / `on` / なし (色を変えるだけ)
//! - メモ: 自由な一言
//!
//! `text` は古いアプリ向けの代わりの文言で、アプリは [`fallback_text`] で作って送る
//! (色の名前はアプリがマスタから引いて渡す)。

/// 色の指示の種類。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PenlightColorKind {
    /// 各自の担当色 (人によって違う)。
    Oshi,
    /// あるアイドルのイメージカラー。
    Idol,
    /// 決まった色。
    Fixed,
}

/// 色の指示を読んだもの。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PenlightColor {
    pub kind: PenlightColorKind,
    /// `Idol` のときのアイドル id。
    pub idol_id: Option<String>,
    /// `Fixed` のときの色 (`0xRRGGBB`)。
    pub rgb: Option<u32>,
}

/// 動き 1 つ (入力の選択肢と凡例に使う)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PenlightMoveInfo {
    pub key: String,
    pub label: String,
}

/// 決まった色の選択肢 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PenlightPreset {
    /// 保存する値 (`#RRGGBB`)。
    pub value: String,
    pub rgb: u32,
    pub name: String,
}

const MOVES: [(&str, &str); 7] = [
    ("sway", "左右に振る"),
    ("pump", "縦に振る"),
    ("spin", "回す"),
    ("raise", "掲げる"),
    ("wave", "ウェーブ"),
    ("off", "消す"),
    ("on", "点ける"),
];

/// ライブでよく指定される色。白と UO (オレンジ) が多く、あとは色相環を一周。
const PRESETS: [(u32, &str); 9] = [
    (0xFFFFFF, "白"),
    (0xFF6A00, "オレンジ"),
    (0xE60012, "赤"),
    (0xFF4FA0, "ピンク"),
    (0xFFE100, "黄"),
    (0x2DBE3C, "緑"),
    (0x00C8E6, "水色"),
    (0x1E50FF, "青"),
    (0x9B3CE6, "紫"),
];

/// 色の指示を読む。書き方が違えば `None`。
pub fn parse_color(spec: &str) -> Option<PenlightColor> {
    if spec == "oshi" {
        return Some(PenlightColor { kind: PenlightColorKind::Oshi, idol_id: None, rgb: None });
    }
    if let Some(id) = spec.strip_prefix("idol:") {
        let ok = !id.is_empty()
            && id.len() <= 64
            && id.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'));
        return ok.then(|| PenlightColor { kind: PenlightColorKind::Idol, idol_id: Some(id.to_string()), rgb: None });
    }
    let hex = spec.strip_prefix('#')?;
    if hex.len() != 6 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let rgb = u32::from_str_radix(hex, 16).ok()?;
    Some(PenlightColor { kind: PenlightColorKind::Fixed, idol_id: None, rgb: Some(rgb) })
}

/// 色を保存する値に書く (`#RRGGBB` は大文字)。
pub fn fixed_color_value(rgb: u32) -> String {
    format!("#{:06X}", rgb & 0xFF_FFFF)
}

/// 決まった色の名前 (選択肢にある色だけ)。
pub fn preset_name(rgb: u32) -> Option<&'static str> {
    PRESETS.iter().find(|(v, _)| *v == rgb).map(|(_, n)| *n)
}

pub fn moves() -> Vec<PenlightMoveInfo> {
    MOVES.iter().map(|(k, l)| PenlightMoveInfo { key: (*k).into(), label: (*l).into() }).collect()
}

pub fn move_label(key: &str) -> Option<&'static str> {
    MOVES.iter().find(|(k, _)| *k == key).map(|(_, l)| *l)
}

pub fn presets() -> Vec<PenlightPreset> {
    PRESETS
        .iter()
        .map(|(rgb, name)| PenlightPreset { value: fixed_color_value(*rgb), rgb: *rgb, name: (*name).into() })
        .collect()
}

/// 色の名前 (`color_name`。アイドルの色ならアプリが「春香の色」のように渡す)。
/// 渡されなければ担当色・選択肢の色は自前で名付ける。
pub fn color_name(spec: Option<&str>, given: Option<&str>) -> Option<String> {
    if let Some(g) = given.map(str::trim).filter(|g| !g.is_empty()) {
        return Some(g.to_string());
    }
    let color = parse_color(spec?)?;
    match color.kind {
        PenlightColorKind::Oshi => Some("担当色".into()),
        PenlightColorKind::Idol => None,
        PenlightColorKind::Fixed => preset_name(color.rgb?).map(Into::into),
    }
}

/// 古いアプリ向けの代わりの文言 (「ペンライト: 青・左右に振る・2本持ち」)。
/// Worker の `penlightFallbackText` と同じ並び (色・動き・メモ)。
pub fn fallback_text(color_spec: Option<&str>, color_given_name: Option<&str>, move_key: Option<&str>, note: Option<&str>) -> String {
    let parts: Vec<String> = [
        color_name(color_spec, color_given_name),
        move_key.and_then(move_label).map(Into::into),
        note.map(str::trim).filter(|n| !n.is_empty()).map(Into::into),
    ]
    .into_iter()
    .flatten()
    .collect();
    if parts.is_empty() {
        "ペンライト".into()
    } else {
        format!("ペンライト: {}", parts.join("・"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_color_specs() {
        assert_eq!(parse_color("oshi").unwrap().kind, PenlightColorKind::Oshi);
        let idol = parse_color("idol:haruka_amami").unwrap();
        assert_eq!((idol.kind, idol.idol_id.as_deref()), (PenlightColorKind::Idol, Some("haruka_amami")));
        assert_eq!(parse_color("#ff8800").unwrap().rgb, Some(0xFF8800));
        for bad in ["", "blue", "#12345", "#GGGGGG", "idol:", "idol:a b"] {
            assert_eq!(parse_color(bad), None, "{bad}");
        }
    }

    #[test]
    fn fallback_text_matches_worker() {
        assert_eq!(fallback_text(Some("oshi"), None, Some("raise"), None), "ペンライト: 担当色・掲げる");
        assert_eq!(fallback_text(Some("#1E50FF"), None, Some("sway"), Some(" 2本持ち ")), "ペンライト: 青・左右に振る・2本持ち");
        assert_eq!(fallback_text(Some("idol:x"), Some("春香の色"), None, None), "ペンライト: 春香の色");
        // アイドルの色で名前が渡されなければ色は書かない (id を人に見せない)。
        assert_eq!(fallback_text(Some("idol:x"), None, None, None), "ペンライト");
        assert_eq!(fallback_text(Some("#123456"), None, Some("off"), None), "ペンライト: 消す");
    }

    #[test]
    fn presets_round_trip() {
        for p in presets() {
            assert_eq!(parse_color(&p.value).unwrap().rgb, Some(p.rgb));
            assert_eq!(preset_name(p.rgb), Some(p.name.as_str()));
        }
        assert_eq!(moves().len(), 7);
    }
}
