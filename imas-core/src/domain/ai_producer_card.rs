//! チャットから自分の P名刺を作る・直す操作 (`set_producer_card`)。
//!
//! 「この写真とこのロゴで名刺を作って。名前は○○、X は @…」のように、素材 (画像・リンク・文面) を
//! 渡して頼む。モデルは項目に振り分けるだけで、ここが 1 項目ずつ検査する。
//!
//! # 決めていること
//!
//! - **渡された項目だけを変える。** 省いた項目は今の名刺のまま (全部を言い直させない)。
//! - 画像は**番号**で指す (この番の発言に添えた 1 枚目 = 1)。画像そのものはモデルから受け取らず、
//!   端末が手元の元の画像を使う (モデルが作り替えた画像を名刺に入れない)。
//! - 担当は、アプリの担当の印が付いている人だけ (名刺の編集画面と同じ)。
//! - 今の名刺の中身を置き換える頼みは、一覧で初めは選ばない。素材を足すだけ・初めて作る、は選んでおく。
//! - QR に収まるか (リンクが長すぎないか) は記録の数にもよるので、実行のときに端末が
//!   `validate_producer_card` を通す。ここでは項目ごとの上限だけを見る。
//!
//! 保存そのものは各 OS (名刺の行と、写真・素材のファイル)。

use crate::domain::ai_actions::{string, ActionSpec, AiAction, AiActionReach, AiPlannedAction, PlanContext, Refusal};
use crate::domain::card_stickers::MAX_CARD_STICKERS;
use crate::domain::producer_card::{
    card_design_from_key, card_design_info, card_designs, card_ink_key, card_link_from_url, card_link_kind_from_key,
    card_link_kind_key, card_link_view, normalize_link, producer_card_limits, CardDesign, CardInk, CardLink, CardLinkKind,
};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

pub const NAME: &str = "set_producer_card";

/// P 歴の始まりとして受ける、いちばん古い年。
const MIN_SINCE_YEAR: i64 = 1990;

/// いまの自分の名刺 (検査と、モデルが `my_records` で読むのに要るところだけ)。各 OS が射影して渡す。
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct AiProducerCardRef {
    pub name: String,
    pub message: String,
    pub since_year: Option<u16>,
    pub links: Vec<CardLink>,
    pub design: CardDesign,
    /// 名刺に載せる担当 (本人が選んでいれば、その並び。選んでいなければ空)。
    pub oshi_idol_ids: Vec<String>,
    pub has_photo: bool,
    /// いま表に置いている素材の数。
    pub sticker_count: u32,
}

/// 名刺の直し 1 回ぶん。None の項目は変えない。
#[derive(uniffi::Record, Debug, Clone, Default, PartialEq, Eq)]
pub struct AiProducerCardEdit {
    pub name: Option<String>,
    /// 空文字は「ひとことを消す」。
    pub message: Option<String>,
    pub since_year: Option<u16>,
    /// リンクの並び (渡されたら丸ごと置き換える)。
    pub links: Option<Vec<CardLink>>,
    pub design: Option<CardDesign>,
    /// 刷る色の保存のキー (`card_ink_key`)。空文字は先頭の担当の色に戻す。
    pub ink_key: Option<String>,
    /// 名刺に載せる担当 (載せる順)。
    pub oshi_idol_ids: Option<Vec<String>>,
    /// 名刺の写真にする画像の番号 (この番に添えた 1 枚目 = 1)。
    pub photo_image: Option<u32>,
    /// 名刺の写真を X のアイコンにする (この ハンドルの公開のアイコンを端末が取る)。
    pub photo_x_handle: Option<String>,
    /// 自作の名刺の画像 (表) にする画像の番号。デザインは「自作の画像」になる。
    pub face_image: Option<u32>,
    /// 表に置く素材として足す画像の番号。
    pub sticker_images: Vec<u32>,
    /// 素材の背景を切り抜いてから置く。
    pub sticker_cutout: bool,
    /// 名刺から外していたら載せ直す項目 (名刺の項目の保存のキー: message / since / links / oshi)。
    /// 中身を渡されたのに外したままだと、直しても名刺に出ない。
    pub show_fields: Vec<String>,
}

pub fn spec() -> ActionSpec {
    let limits = producer_card_limits();
    let designs: Vec<String> = card_designs().into_iter().map(|d| d.key).collect();
    let link_kinds: Vec<String> = [
        CardLinkKind::X,
        CardLinkKind::Bluesky,
        CardLinkKind::Misskey,
        CardLinkKind::YouTube,
        CardLinkKind::Instagram,
        CardLinkKind::TikTok,
        CardLinkKind::Web,
    ]
    .into_iter()
    .map(card_link_kind_key)
    .collect();
    let image_no = |what: &str| json!({ "type": "integer", "description": format!("{what}にする画像の番号 (この発言に添えられた 1 枚目 = 1)。") });
    ActionSpec {
        name: NAME,
        description: "利用者の P名刺 (会場で交換する自分の名刺) を作る・直す。渡した項目だけが変わり、省いた項目は今のまま。添えられた画像を、名刺の写真・自作の名刺の画像・表に置く素材に使える (番号で指す)。いまの名刺と選べるデザインの名前は my_records の producer_card にある。端末の中だけの記録で、交換するまで相手には渡らない。",
        properties: json!({
            "name": string(&format!("名刺に刷る名前 (P 名)。{} 字まで。利用者が言ったとおり。", limits.max_name_chars)),
            "message": string(&format!("ひとこと。{} 字まで。空文字で消す。", limits.max_message_chars)),
            "since_year": { "type": "integer", "description": "P 歴の始まり (西暦)。" },
            "links": {
                "type": "array",
                "description": format!("名刺に載せるリンク ({} 本まで)。渡すと並びごと置き換わるので、残すものも入れる。", limits.max_links),
                "items": {
                    "type": "object",
                    "properties": {
                        "kind": { "type": "string", "enum": link_kinds, "description": "url を渡すなら省いてよい。" },
                        "value": string("ハンドル (@ は付けても付けなくてもよい)。Misskey は user@host、web は URL。"),
                        "url": string("プロフィールの URL。SNS の種類は URL から決まる。"),
                    },
                },
            },
            "design": { "type": "string", "enum": designs, "description": "名刺のデザイン。custom (自作の画像) は face_image と一緒に。" },
            "ink": string("刷る色。default = 先頭の担当の色、sumi = 墨一色、アイドルの id = 名刺に載せたその担当の色。"),
            "oshi_idol_ids": { "type": "array", "items": { "type": "string" },
                               "description": format!("名刺に載せる担当 ({} 人まで、載せる順)。利用者の担当 (my_records の my_picks) の中から。", limits.max_oshi) },
            "photo_image": image_no("名前の横の写真 (顔写真・アイコン)"),
            "photo_x_icon": { "type": "boolean", "description": "true で、名刺の X のリンクのアイコンを写真にする。" },
            "face_image": image_no("自作の名刺の画像 (名刺の表そのものの絵)"),
            "sticker_images": { "type": "array", "items": { "type": "integer" },
                                "description": format!("表に置く素材 (ロゴ・スタンプ・イラスト) として足す画像の番号。素材は合わせて {MAX_CARD_STICKERS} 枚まで。") },
            "sticker_cutout": { "type": "boolean", "description": "true で、素材の背景を切り抜いてから置く (写真から人や物だけを抜く)。" },
        }),
        required: &[],
    }
}

fn text<'a>(args: &'a Value, key: &str) -> Option<&'a str> {
    args.get(key).and_then(Value::as_str).map(str::trim)
}

fn chars_within(value: &str, max: u32, what: &str) -> Result<(), Refusal> {
    if value.chars().count() > max as usize {
        return Err(format!("{what}は {max} 字までです").into());
    }
    Ok(())
}

/// 画像の番号 (1 始まり) を検査する。
fn image_no(args: &Value, key: &str, attached: u32) -> Result<Option<u32>, Refusal> {
    match args.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(v) => checked_image_no(v, key, attached).map(Some),
    }
}

fn checked_image_no(value: &Value, key: &str, attached: u32) -> Result<u32, Refusal> {
    if attached == 0 {
        return Err(format!("{key}: この発言には画像が添えられていません。画像を添えて頼み直してもらう").into());
    }
    match value.as_u64() {
        Some(n) if n >= 1 && n <= u64::from(attached) => Ok(n as u32),
        _ => Err(format!("{key} は 1 から {attached} まで (添えられた画像の番号)").into()),
    }
}

fn links(args: &Value, max: u32) -> Result<Option<Vec<CardLink>>, Refusal> {
    let Some(list) = args.get("links").and_then(Value::as_array) else { return Ok(None) };
    let mut out: Vec<CardLink> = Vec::new();
    for item in list {
        let url = text(item, "url").unwrap_or("");
        let value = text(item, "value").unwrap_or("");
        let link = if !url.is_empty() {
            card_link_from_url(url)
        } else {
            let kind = text(item, "kind").unwrap_or("");
            let kind = card_link_kind_from_key(kind).ok_or_else(|| Refusal::from(format!("links の kind が語彙にありません: {kind}")))?;
            normalize_link(&CardLink { kind, value: value.to_string() })
        };
        let link = link.ok_or_else(|| Refusal::from(format!("リンクの形が合いません: {}{}", url, value)))?;
        if !out.contains(&link) {
            out.push(link);
        }
    }
    if out.len() > max as usize {
        return Err(format!("リンクは {max} 本までです").into());
    }
    Ok(Some(out))
}

/// 担当の id 列を検査する。DB に無い id・アプリの担当でない人は Err。
fn oshi(snap: &Snapshot, args: &Value, ctx: PlanContext<'_>, max: u32) -> Result<Option<Vec<String>>, Refusal> {
    let Some(list) = args.get("oshi_idol_ids").and_then(Value::as_array) else { return Ok(None) };
    let mut out: Vec<String> = Vec::new();
    for id in list.iter().filter_map(Value::as_str) {
        let idol = snap.idol(id.trim()).ok_or_else(|| Refusal::from(format!("アイドルの id が DB にありません: {id}")))?;
        if !ctx.records.my_pick_idol_ids.contains(&idol.id) {
            return Err(format!(
                "{} は利用者の担当に入っていないので、名刺に載せられません。担当にするなら set_my_pick を積んで実行してもらい、そのあとで名刺に載せる",
                idol.name
            )
            .into());
        }
        if !out.contains(&idol.id) {
            out.push(idol.id.clone());
        }
    }
    if out.is_empty() {
        return Err("oshi_idol_ids が空です (担当を載せない名刺は、編集画面で項目を外す)".into());
    }
    if out.len() > max as usize {
        return Err(format!("名刺に載せる担当は {max} 人までです").into());
    }
    Ok(Some(out))
}

/// `set_producer_card` の呼び出しを検査して、一覧の 1 行にする。
pub fn plan(snap: &Snapshot, args: &Value, ctx: PlanContext<'_>) -> Result<AiPlannedAction, Refusal> {
    let limits = producer_card_limits();
    let existing = ctx.records.producer_card.as_ref().filter(|c| !c.name.trim().is_empty());
    let mut edit = AiProducerCardEdit::default();
    // 一覧に出す「何を変えるか」。
    let mut parts: Vec<String> = Vec::new();

    if let Some(name) = text(args, "name") {
        if name.is_empty() {
            return Err("name が空です".into());
        }
        chars_within(name, limits.max_name_chars, "名前")?;
        edit.name = Some(name.to_string());
        parts.push(format!("名前「{name}」"));
    } else if existing.is_none() {
        return Err("まだ名刺が無いので、name (名刺に刷る名前) が要ります。利用者に名前を訊く".into());
    }
    if let Some(message) = text(args, "message") {
        chars_within(message, limits.max_message_chars, "ひとこと")?;
        edit.message = Some(message.to_string());
        if !message.is_empty() {
            edit.show_fields.push("message".into());
        }
        parts.push(if message.is_empty() { "ひとことを消す".into() } else { format!("ひとこと「{message}」") });
    }
    if let Some(year) = args.get("since_year").filter(|v| !v.is_null()) {
        let this_year: i64 = ctx.today_key.get(..4).and_then(|y| y.parse().ok()).unwrap_or(i64::MAX);
        match year.as_i64() {
            Some(y) if (MIN_SINCE_YEAR..=this_year).contains(&y) => {
                edit.since_year = Some(y as u16);
                edit.show_fields.push("since".into());
                parts.push(format!("P歴 {y}年から"));
            }
            _ => return Err(format!("since_year は {MIN_SINCE_YEAR} から今年までの西暦で").into()),
        }
    }
    if let Some(list) = links(args, limits.max_links)? {
        let shown: Vec<String> = list.iter().map(|l| card_link_view(l).label).collect();
        parts.push(if list.is_empty() { "リンクを全部外す".into() } else { format!("リンク ({})", shown.join("・")) });
        if !list.is_empty() {
            edit.show_fields.push("links".into());
        }
        edit.links = Some(list);
    }
    if let Some(ids) = oshi(snap, args, ctx, limits.max_oshi)? {
        let names: Vec<&str> = ids.iter().filter_map(|id| snap.idol(id)).map(|i| i.name.as_str()).collect();
        parts.push(format!("担当 ({})", names.join("・")));
        edit.show_fields.push("oshi".into());
        edit.oshi_idol_ids = Some(ids);
    }

    edit.face_image = image_no(args, "face_image", ctx.attached_images)?;
    if let Some(key) = text(args, "design").filter(|k| !k.is_empty()) {
        let design = card_design_from_key(key).ok_or_else(|| Refusal::from(format!("design が語彙にありません: {key}")))?;
        let already_custom = existing.is_some_and(|c| c.design == CardDesign::Custom);
        if card_design_info(design).uses_face_image && edit.face_image.is_none() && !already_custom {
            return Err("自作の画像のデザインは、名刺の表にする画像 (face_image) と一緒に頼む".into());
        }
        if edit.face_image.is_some() && !card_design_info(design).uses_face_image {
            return Err("face_image (自作の名刺の画像) を使うなら、design は custom にするか省く".into());
        }
        edit.design = Some(design);
    }
    if edit.face_image.is_some() {
        edit.design = Some(CardDesign::Custom);
        parts.push("自作の名刺の画像".into());
    } else if let Some(design) = edit.design {
        parts.push(format!("デザイン「{}」", card_design_info(design).label));
    }

    if let Some(ink) = text(args, "ink").filter(|k| !k.is_empty()) {
        let (key, label) = match ink {
            "default" => (String::new(), "先頭の担当の色".to_string()),
            "sumi" => (card_ink_key(Some(&CardInk::Sumi)), "墨".to_string()),
            id => {
                let idol = snap.idol(id).ok_or_else(|| Refusal::from(format!("ink は default / sumi / アイドルの id: {id}")))?;
                // 名刺に載る担当の色だけ (載らない人を指すと、組むときに既定の色へ戻ってしまう)。
                let on_card = match (&edit.oshi_idol_ids, existing) {
                    (Some(ids), _) => ids.contains(&idol.id),
                    (None, Some(card)) if !card.oshi_idol_ids.is_empty() => card.oshi_idol_ids.contains(&idol.id),
                    _ => ctx.records.my_pick_idol_ids.contains(&idol.id),
                };
                if !on_card {
                    return Err(format!("{} は名刺に載せる担当ではないので、その色では刷れません", idol.name).into());
                }
                (card_ink_key(Some(&CardInk::Oshi { idol_id: idol.id.clone() })), format!("{}の色", idol.name))
            }
        };
        edit.ink_key = Some(key);
        parts.push(format!("刷る色 ({label})"));
    }

    edit.photo_image = image_no(args, "photo_image", ctx.attached_images)?;
    if args.get("photo_x_icon").and_then(Value::as_bool) == Some(true) {
        if edit.photo_image.is_some() {
            return Err("写真は photo_image か photo_x_icon のどちらか 1 つ".into());
        }
        // X のリンクは、この頼みで渡したものが先。無ければ今の名刺のもの。
        let x = edit
            .links
            .as_deref()
            .or(existing.map(|c| c.links.as_slice()))
            .into_iter()
            .flatten()
            .find(|l| l.kind == CardLinkKind::X)
            .ok_or_else(|| Refusal::from("名刺に X のリンクが無いので、アイコンを取れません。links に X を入れるか、利用者に訊く"))?;
        edit.photo_x_handle = Some(x.value.clone());
        parts.push("写真 (X のアイコン)".into());
    } else if edit.photo_image.is_some() {
        parts.push("写真".into());
    }

    if let Some(list) = args.get("sticker_images").and_then(Value::as_array) {
        for value in list {
            let n = checked_image_no(value, "sticker_images", ctx.attached_images)?;
            if !edit.sticker_images.contains(&n) {
                edit.sticker_images.push(n);
            }
        }
        let have = existing.map(|c| c.sticker_count).unwrap_or(0) as usize;
        if have + edit.sticker_images.len() > MAX_CARD_STICKERS {
            return Err(format!(
                "素材は合わせて {MAX_CARD_STICKERS} 枚までです (いま {have} 枚)。減らすのは名刺の編集画面で"
            )
            .into());
        }
        if !edit.sticker_images.is_empty() {
            edit.sticker_cutout = args.get("sticker_cutout").and_then(Value::as_bool) == Some(true);
            let cut = if edit.sticker_cutout { "・背景を切り抜く" } else { "" };
            parts.push(format!("素材 {} 枚を足す{cut}", edit.sticker_images.len()));
        }
    }

    if parts.is_empty() {
        return Err("変える項目が 1 つもありません".into());
    }
    // 素材を足すだけなら今の名刺は何も失わない。ほかは前の中身を置き換える。
    let replaces = existing.is_some() && edit != AiProducerCardEdit {
        sticker_images: edit.sticker_images.clone(),
        sticker_cutout: edit.sticker_cutout,
        ..AiProducerCardEdit::default()
    };
    let title = match existing {
        None => format!("P名刺を作る: {}", parts.join("、")),
        Some(_) if replaces => format!("P名刺を直す: {} (前の中身は置き換わります)", parts.join("、")),
        Some(_) => format!("P名刺を直す: {}", parts.join("、")),
    };
    let target = edit.name.clone().or_else(|| existing.map(|c| c.name.clone())).unwrap_or_default();
    Ok(AiPlannedAction { action: AiAction::SetProducerCard { edit }, reach: AiActionReach::Device, title, target, preselected: !replaces })
}

/// `my_records` の `producer_card` の答え (いまの名刺と、選べるもの)。
pub fn describe(snap: &Snapshot, card: Option<&AiProducerCardRef>) -> Value {
    let limits = producer_card_limits();
    let designs: Vec<Value> = card_designs().into_iter().map(|d| json!({ "key": d.key, "name": d.label })).collect();
    let card = card.filter(|c| !c.name.trim().is_empty()).map(|c| {
        let links: Vec<Value> = c
            .links
            .iter()
            .map(|l| json!({ "kind": card_link_kind_key(l.kind), "value": l.value, "url": card_link_view(l).url }))
            .collect();
        let oshi: Vec<Value> =
            c.oshi_idol_ids.iter().filter_map(|id| snap.idol(id)).map(|i| json!({ "idol_id": i.id, "name": i.name })).collect();
        json!({
            "name": c.name,
            "message": c.message,
            "since_year": c.since_year,
            "links": links,
            "design": card_design_info(c.design).key,
            "oshi": oshi,
            "has_photo": c.has_photo,
            "sticker_count": c.sticker_count,
        })
    });
    json!({
        "card": card,
        "designs": designs,
        "limits": { "name_chars": limits.max_name_chars, "message_chars": limits.max_message_chars,
                    "oshi": limits.max_oshi, "links": limits.max_links, "stickers": MAX_CARD_STICKERS },
        "note": "card が null なら、まだ名刺を作っていない。oshi が空なら、担当はアプリが自動で選んで載せている。",
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::ai_actions::{plan as plan_action, AiUserRecords};
    use crate::test_support::bundle_snapshot;

    fn ctx<'a>(records: &'a AiUserRecords, attached_images: u32) -> PlanContext<'a> {
        PlanContext { today_key: "2026-11-22", playlists: &[], mastery_labels: &[], records, attached_images }
    }

    fn edit_of(p: &AiPlannedAction) -> &AiProducerCardEdit {
        match &p.action {
            AiAction::SetProducerCard { edit } => edit,
            other => panic!("名刺の操作でない: {other:?}"),
        }
    }

    fn card(name: &str) -> AiProducerCardRef {
        AiProducerCardRef {
            name: name.into(),
            message: String::new(),
            since_year: None,
            links: vec![CardLink { kind: CardLinkKind::X, value: "idollivedb".into() }],
            design: CardDesign::Pass,
            oshi_idol_ids: Vec::new(),
            has_photo: false,
            sticker_count: 2,
        }
    }

    #[test]
    fn 素材を渡して初めての名刺を作る() {
        let snap = bundle_snapshot();
        let idol = snap.idols[0].id.clone();
        let records = AiUserRecords { my_pick_idol_ids: vec![idol.clone()], ..AiUserRecords::default() };
        let args = json!({
            "name": " ふがP ", "message": "現地でよろしく", "since_year": 2015,
            "links": [{ "url": "https://x.com/idollivedb" }, { "kind": "bluesky", "value": "@fuga.bsky.social" }],
            "design": "formal", "oshi_idol_ids": [idol], "ink": "sumi",
            "photo_image": 1, "sticker_images": [2, 2], "sticker_cutout": true,
        });
        let p = plan_action(&snap, NAME, &args, ctx(&records, 2)).unwrap();
        assert_eq!(p.reach, AiActionReach::Device);
        assert!(p.preselected, "初めて作る名刺は何も失わない");
        assert!(p.title.starts_with("P名刺を作る"), "{}", p.title);
        assert_eq!(p.target, "ふがP");
        let edit = edit_of(&p);
        assert_eq!(edit.name.as_deref(), Some("ふがP"));
        assert_eq!(edit.since_year, Some(2015));
        let links = edit.links.as_ref().unwrap();
        assert_eq!(links[0], CardLink { kind: CardLinkKind::X, value: "idollivedb".into() });
        assert_eq!(links[1].kind, CardLinkKind::Bluesky);
        assert_eq!(edit.design, Some(CardDesign::Formal));
        assert_eq!(edit.ink_key.as_deref(), Some("sumi"));
        assert_eq!((edit.photo_image, edit.sticker_images.clone(), edit.sticker_cutout), (Some(1), vec![2], true));
        assert_eq!(edit.show_fields, ["message", "since", "links", "oshi"]);
    }

    #[test]
    fn 名刺が無いのに名前が無ければ訊き返させる() {
        let snap = bundle_snapshot();
        let err = plan_action(&snap, NAME, &json!({ "message": "よろしく" }), ctx(&AiUserRecords::default(), 0)).unwrap_err();
        assert!(err.message.contains("name") && !err.already);
        assert!(plan_action(&snap, NAME, &json!({}), ctx(&AiUserRecords::default(), 0)).is_err());
    }

    #[test]
    fn 今の名刺を置き換える頼みは選ばないで出し_素材を足すだけなら選んでおく() {
        let snap = bundle_snapshot();
        let records = AiUserRecords { producer_card: Some(card("ふがP")), ..AiUserRecords::default() };
        let replace = plan_action(&snap, NAME, &json!({ "message": "新しいひとこと" }), ctx(&records, 0)).unwrap();
        assert!(!replace.preselected);
        assert!(replace.title.contains("置き換わります"));
        assert_eq!(replace.target, "ふがP");
        assert!(edit_of(&replace).name.is_none(), "省いた項目は変えない");

        let add = plan_action(&snap, NAME, &json!({ "sticker_images": [1] }), ctx(&records, 1)).unwrap();
        assert!(add.preselected);
        // 素材は合わせて 3 枚まで (いま 2 枚)。
        let over = plan_action(&snap, NAME, &json!({ "sticker_images": [1, 2] }), ctx(&records, 2)).unwrap_err();
        assert!(over.message.contains("いま 2 枚"));
    }

    #[test]
    fn 添えていない画像の番号と_上限を越えた項目は通さない() {
        let snap = bundle_snapshot();
        let records = AiUserRecords { producer_card: Some(card("ふがP")), ..AiUserRecords::default() };
        assert!(plan_action(&snap, NAME, &json!({ "photo_image": 1 }), ctx(&records, 0)).is_err());
        assert!(plan_action(&snap, NAME, &json!({ "photo_image": 3 }), ctx(&records, 2)).is_err());
        assert!(plan_action(&snap, NAME, &json!({ "photo_image": 0 }), ctx(&records, 2)).is_err());
        assert!(plan_action(&snap, NAME, &json!({ "name": "あ".repeat(25) }), ctx(&records, 0)).is_err());
        assert!(plan_action(&snap, NAME, &json!({ "message": "あ".repeat(61) }), ctx(&records, 0)).is_err());
        assert!(plan_action(&snap, NAME, &json!({ "since_year": 2999 }), ctx(&records, 0)).is_err());
        assert!(plan_action(&snap, NAME, &json!({ "links": [{ "kind": "x", "value": "" }] }), ctx(&records, 0)).is_err());
        assert!(plan_action(&snap, NAME, &json!({ "design": "rainbow" }), ctx(&records, 0)).is_err());
        // 自作の画像のデザインは、表の画像と一緒でなければ通さない。画像があればデザインは自作になる。
        assert!(plan_action(&snap, NAME, &json!({ "design": "custom" }), ctx(&records, 1)).is_err());
        let face = plan_action(&snap, NAME, &json!({ "face_image": 1 }), ctx(&records, 1)).unwrap();
        assert_eq!(edit_of(&face).design, Some(CardDesign::Custom));
    }

    #[test]
    fn 担当でない人は載せられず_x_のアイコンは名刺のリンクから取る() {
        let snap = bundle_snapshot();
        let idol = snap.idols[0].id.clone();
        let records = AiUserRecords { producer_card: Some(card("ふがP")), ..AiUserRecords::default() };
        let err = plan_action(&snap, NAME, &json!({ "oshi_idol_ids": [idol] }), ctx(&records, 0)).unwrap_err();
        assert!(err.message.contains("set_my_pick"));
        assert!(plan_action(&snap, NAME, &json!({ "ink": idol }), ctx(&records, 0)).is_err());

        let icon = plan_action(&snap, NAME, &json!({ "photo_x_icon": true }), ctx(&records, 0)).unwrap();
        assert_eq!(edit_of(&icon).photo_x_handle.as_deref(), Some("idollivedb"));
        // X のリンクを外す頼みと一緒なら、取る先が無い。
        assert!(plan_action(&snap, NAME, &json!({ "photo_x_icon": true, "links": [] }), ctx(&records, 0)).is_err());
    }

    #[test]
    fn いまの名刺と選べるデザインを返す() {
        let snap = bundle_snapshot();
        let none = describe(&snap, None);
        assert!(none["card"].is_null());
        assert!(none["designs"].as_array().unwrap().iter().any(|d| d["key"] == "formal"));
        let some = describe(&snap, Some(&card("ふがP")));
        assert_eq!(some["card"]["name"], "ふがP");
        assert_eq!(some["card"]["links"][0]["kind"], "x");
        assert_eq!(some["card"]["sticker_count"], 2);
    }
}
