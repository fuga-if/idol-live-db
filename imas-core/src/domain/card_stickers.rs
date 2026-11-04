//! P名刺の表に置く素材 (好きな画像・背景を切り抜いた透過画像) の置き方。
//!
//! 2026-11 ユーザー「担当のアイコンの他にも名刺用に画像読み込ませたい。透過した素材とか作れたら良い」。
//! 素材は名刺の表の上に重ねる画像で、3 枚まで。置き方は名刺の紙に対する割合で持つ (画面・紙に刷る画像・
//! 相手の端末で同じ位置に出るように)。並びは重なりの順 (後ろほど上)。
//!
//! - 位置 `x` / `y` は素材の中心 (紙の幅・高さに対する割合)。紙から半分より外には出さない。
//! - 大きさ `width` は紙の幅に対する素材の幅の割合 (高さは画像の縦横比のまま)。
//! - 傾き `rotation_degrees` は -180〜180 度。
//!
//! 画像そのものは端末に置き (QR には入らない)、名刺ファイル・近くの端末で置き方と一緒に渡す
//! (`producer_card::encode_card_file` の素材の区画)。指で動かす計算は端末、結果を揃えるのはここ。

/// 名刺に置ける素材の数。
pub const MAX_CARD_STICKERS: usize = 3;
/// 大きさの下限・上限 (紙の幅に対する割合)。
const MIN_WIDTH: f64 = 0.08;
const MAX_WIDTH: f64 = 1.2;
/// 中心を紙の外に出せる幅 (紙の幅・高さに対する割合)。端に半分かかるくらいまで。
const OVERHANG: f64 = 0.1;

/// 素材 1 枚の置き方。
#[derive(uniffi::Record, Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CardSticker {
    /// 素材の id (端末の画像ファイルの名前に使う。英数字と `-`)。
    pub id: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub rotation_degrees: f64,
}

fn finite_or(v: f64, fallback: f64) -> f64 {
    if v.is_finite() {
        v
    } else {
        fallback
    }
}

/// 傾きを -180〜180 度に畳む。
fn wrap_degrees(d: f64) -> f64 {
    let d = finite_or(d, 0.0) % 360.0;
    if d > 180.0 {
        d - 360.0
    } else if d < -180.0 {
        d + 360.0
    } else {
        d
    }
}

fn is_sticker_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 40 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

/// 置き方を範囲に収める (指で動かした結果・受け取った置き方はここを通す)。
pub fn card_sticker_clamp(sticker: &CardSticker) -> CardSticker {
    CardSticker {
        id: sticker.id.clone(),
        x: finite_or(sticker.x, 0.5).clamp(-OVERHANG, 1.0 + OVERHANG),
        y: finite_or(sticker.y, 0.5).clamp(-OVERHANG, 1.0 + OVERHANG),
        width: finite_or(sticker.width, 0.3).clamp(MIN_WIDTH, MAX_WIDTH),
        rotation_degrees: wrap_degrees(sticker.rotation_degrees),
    }
}

/// 並びを揃える: 形の合わない id・同じ id を落とし、上限までにし、置き方を範囲に収める。
pub fn card_stickers_normalize(stickers: &[CardSticker]) -> Vec<CardSticker> {
    let mut seen: Vec<&str> = Vec::new();
    stickers
        .iter()
        .filter(|s| {
            if !is_sticker_id(&s.id) || seen.contains(&s.id.as_str()) {
                return false;
            }
            seen.push(&s.id);
            true
        })
        .take(MAX_CARD_STICKERS)
        .map(card_sticker_clamp)
        .collect()
}

/// 新しく足す素材の置き方。右下寄りに、すでにある素材と少しずつずらして置く。
pub fn card_sticker_new(id: &str, existing: u32) -> CardSticker {
    let step = f64::from(existing.min(MAX_CARD_STICKERS as u32));
    card_sticker_clamp(&CardSticker {
        id: id.to_string(),
        x: 0.72 - step * 0.08,
        y: 0.62 - step * 0.08,
        width: 0.32,
        rotation_degrees: 0.0,
    })
}

/// 素材を 1 枚足した並び (上限なら変えない)。
pub fn card_stickers_add(stickers: &[CardSticker], id: &str) -> Vec<CardSticker> {
    let mut out = card_stickers_normalize(stickers);
    if out.len() < MAX_CARD_STICKERS && is_sticker_id(id) && !out.iter().any(|s| s.id == id) {
        out.push(card_sticker_new(id, out.len() as u32));
    }
    out
}

/// 素材を 1 枚置き直した並び (同じ id のものを差し替える)。
pub fn card_stickers_update(stickers: &[CardSticker], sticker: &CardSticker) -> Vec<CardSticker> {
    let placed = card_sticker_clamp(sticker);
    card_stickers_normalize(stickers)
        .into_iter()
        .map(|s| if s.id == placed.id { placed.clone() } else { s })
        .collect()
}

/// 素材を外した並び。
pub fn card_stickers_remove(stickers: &[CardSticker], id: &str) -> Vec<CardSticker> {
    card_stickers_normalize(stickers)
        .into_iter()
        .filter(|s| s.id != id)
        .collect()
}

/// 素材をいちばん上に重ねた並び。
pub fn card_stickers_bring_to_front(stickers: &[CardSticker], id: &str) -> Vec<CardSticker> {
    let mut out = card_stickers_normalize(stickers);
    if let Some(i) = out.iter().position(|s| s.id == id) {
        let s = out.remove(i);
        out.push(s);
    }
    out
}

/// 保存の形 (JSON の配列)。
pub fn card_stickers_to_json(stickers: &[CardSticker]) -> String {
    serde_json::to_string(&card_stickers_normalize(stickers)).unwrap_or_else(|_| "[]".into())
}

/// 保存の形から戻す。空・壊れた JSON は素材なし。
pub fn card_stickers_from_json(json: &str) -> Vec<CardSticker> {
    serde_json::from_str::<Vec<CardSticker>>(json)
        .map(|v| card_stickers_normalize(&v))
        .unwrap_or_default()
}

/// 名刺ファイルの素材の区画に書く置き方 (16 バイト: x, y, width, 傾きの f32 LE)。
pub(crate) fn sticker_placement_bytes(s: &CardSticker) -> [u8; 16] {
    let s = card_sticker_clamp(s);
    let mut out = [0u8; 16];
    for (i, v) in [s.x, s.y, s.width, s.rotation_degrees]
        .into_iter()
        .enumerate()
    {
        out[i * 4..i * 4 + 4].copy_from_slice(&(v as f32).to_le_bytes());
    }
    out
}

/// 区画の置き方を読む。
pub(crate) fn sticker_from_placement(id: String, bytes: &[u8]) -> Option<CardSticker> {
    if bytes.len() != 16 {
        return None;
    }
    let f = |i: usize| {
        f64::from(f32::from_le_bytes([
            bytes[i],
            bytes[i + 1],
            bytes[i + 2],
            bytes[i + 3],
        ]))
    };
    Some(card_sticker_clamp(&CardSticker {
        id,
        x: f(0),
        y: f(4),
        width: f(8),
        rotation_degrees: f(12),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(id: &str, x: f64) -> CardSticker {
        CardSticker {
            id: id.into(),
            x,
            y: 0.5,
            width: 0.3,
            rotation_degrees: 0.0,
        }
    }

    #[test]
    fn clamp_keeps_stickers_on_the_paper() {
        let c = card_sticker_clamp(&CardSticker {
            id: "a".into(),
            x: 5.0,
            y: f64::NAN,
            width: 9.0,
            rotation_degrees: 540.0,
        });
        assert_eq!(
            (c.x, c.y, c.width, c.rotation_degrees),
            (1.1, 0.5, 1.2, 180.0)
        );
        assert_eq!(
            card_sticker_clamp(&CardSticker {
                rotation_degrees: -200.0,
                ..s("a", 0.5)
            })
            .rotation_degrees,
            160.0
        );
        assert_eq!(
            card_sticker_clamp(&CardSticker {
                width: 0.0,
                ..s("a", 0.5)
            })
            .width,
            MIN_WIDTH
        );
    }

    #[test]
    fn add_update_remove_and_order() {
        let list = card_stickers_add(&[], "a");
        let list = card_stickers_add(&list, "b");
        let list = card_stickers_add(&list, "c");
        assert_eq!(card_stickers_add(&list, "d").len(), MAX_CARD_STICKERS);
        // 足すたびにずらして置く。
        assert_ne!(list[0].x, list[1].x);
        let list = card_stickers_update(&list, &s("b", 0.2));
        assert_eq!(list[1].x, 0.2);
        let list = card_stickers_bring_to_front(&list, "a");
        let ids: Vec<&str> = list.iter().map(|s| s.id.as_str()).collect();
        assert_eq!(ids, vec!["b", "c", "a"]);
        let list = card_stickers_remove(&list, "c");
        assert_eq!(list.len(), 2);
        // 形の合わない id・重複は落とす。
        assert!(card_stickers_add(&list, "../x").len() == 2);
        assert_eq!(
            card_stickers_normalize(&[s("a", 0.1), s("a", 0.2)]).len(),
            1
        );
    }

    #[test]
    fn json_and_placement_round_trip() {
        let list = vec![
            s("a", 0.25),
            CardSticker {
                rotation_degrees: -30.0,
                ..s("b", 0.75)
            },
        ];
        assert_eq!(card_stickers_from_json(&card_stickers_to_json(&list)), list);
        assert!(card_stickers_from_json("壊れた").is_empty());
        let back = sticker_from_placement("b".into(), &sticker_placement_bytes(&list[1])).unwrap();
        assert!((back.x - 0.75).abs() < 1e-6 && (back.rotation_degrees + 30.0).abs() < 1e-4);
        assert_eq!(sticker_from_placement("x".into(), &[0; 3]), None);
    }
}
