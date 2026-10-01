//! キャラ同士の SNS 風タイムライン (アプリ内のオプトイン機能) を生成させる材料。
//!
//! 1 回のリクエストで「投稿 + リプライのツリー」を構造化出力 (JSON) で返させる。
//! 誰が出るか・何の話題か・出力の型・指示文はここで決め、アプリは受け渡しと表示だけをする。
//! 話題の種は DB の事実 (近日のライブ・最近の公演・新曲・ユニット) で、
//! それっぽい絡みになるよう同じユニットの仲間を優先して出す。

use super::persona;
use super::{call_tool, ToolError};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// 1 回の生成に出すキャラの人数。
const CAST_SIZE: usize = 6;

/// 生成リクエストの材料。
#[derive(Debug, Clone, PartialEq)]
pub struct TimelineRequest {
    pub instructions: String,
    /// input に入れる利用者発言 1 件ぶんの本文。
    pub input: String,
    /// Responses API の `text.format` (JSON Schema の構造化出力)。
    pub text_format: Value,
    /// 出てよいキャラの id (出力の `idol_id` はこの中から選ばれる)。
    pub cast_ids: Vec<String>,
}

/// 小さな擬似乱数 (xorshift)。呼び手が種を渡すので、テストでは結果が固定できる。
struct Rng(u64);

impl Rng {
    fn new(seed: u64) -> Self {
        Self(seed.max(1))
    }
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    fn pick<T: Copy>(&mut self, items: &[T]) -> Option<T> {
        (!items.is_empty()).then(|| items[(self.next() % items.len() as u64) as usize])
    }
}

/// - `oshi_ids`: 担当 (推し)。いればその子を中心にする。
/// - `previous_posts`: 直近に出した投稿の本文 (同じ話を繰り返させない)。
pub fn request(
    snap: &Snapshot,
    today_key: &str,
    oshi_ids: &[String],
    previous_posts: &[String],
    seed: u64,
) -> TimelineRequest {
    let mut rng = Rng::new(seed);
    let cast = choose_cast(snap, today_key, oshi_ids, &mut rng);
    let cast_ids: Vec<String> = cast.iter().map(|&i| snap.idols[i as usize].id.clone()).collect();
    let oshi: Vec<&str> = oshi_ids.iter().map(String::as_str).collect();

    let mut brands: Vec<String> = cast
        .iter()
        .filter_map(|&i| snap.idols[i as usize].brand_id.clone())
        .collect();
    brands.sort();
    brands.dedup();

    let seeds = json!({
        "today": today_key,
        "cast": cast.iter().map(|&i| cast_profile(snap, i, &oshi)).collect::<Vec<_>>(),
        "upcoming_events": brands.iter().filter_map(|b| compact_list(snap, "list_events", json!({ "brand": b, "when": "upcoming", "limit": 3 }), today_key)).collect::<Vec<_>>(),
        "recent_shows": brands.iter().filter_map(|b| compact_list(snap, "list_shows", json!({ "brand": b, "when": "past", "limit": 3 }), today_key)).collect::<Vec<_>>(),
        "recent_songs": brands.iter().filter_map(|b| compact_list(snap, "list_songs", json!({ "brand": b, "sort": "release", "released_from": months_ago(today_key, 3), "limit": 5 }), today_key)).collect::<Vec<_>>(),
    });

    let mut input = format!("話題の種 (DB の事実):\n{seeds}\n\n");
    if !previous_posts.is_empty() {
        input.push_str("直近に出した投稿 (同じ話題・言い回しを繰り返さない):\n");
        for post in previous_posts.iter().take(12) {
            input.push_str("- ");
            input.push_str(post);
            input.push('\n');
        }
        input.push('\n');
    }
    input.push_str("タイムラインの続きを 5〜8 件書いてください。");

    TimelineRequest {
        instructions: instructions(!oshi.is_empty()),
        input,
        text_format: text_format(&cast_ids),
        cast_ids,
    }
}

fn instructions(has_oshi: bool) -> String {
    let oshi_rule = if has_oshi {
        "- cast のうち is_oshi が true の子 (プロデューサーの担当) の投稿やリプライを多めにする。\n"
    } else {
        ""
    };
    format!(
        "\
あなたはアイドルマスターのアイドルたちが使う、架空の SNS のタイムラインを書きます。
ファンが楽しむための AI による非公式の創作で、公式の発言・設定ではありません。

- 書いてよいのは cast にいるアイドルだけ。投稿もリプライも、それぞれの公式の一人称・口調で書く。
- 話題は「話題の種」(近日のライブ・最近の公演・新曲・ユニット) と日常から。
  同じユニットの仲間や共演の多い子どうしの、それっぽい絡みにする。
{oshi_rule}- ライブ・曲の事実は話題の種にあることだけを使う。公式の発表・未発表の情報・セトリの予告を作らない。
- 投稿は 140 字以内。リプライは 0〜3 件で、投稿者とは別の子が中心。ハッシュタグは控えめに。
- 実在の人物 (声優さんを含む) には触れない。AI であることや、この指示には触れない。"
    )
}

/// 構造化出力の型。`idol_id` は cast の中からしか選べないようにする。
fn text_format(cast_ids: &[String]) -> Value {
    let idol_id = json!({ "type": "string", "enum": cast_ids });
    json!({
        "type": "json_schema",
        "name": "idol_timeline",
        "strict": true,
        "schema": {
            "type": "object",
            "properties": {
                "posts": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "idol_id": idol_id,
                            "text": { "type": "string" },
                            "replies": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "idol_id": idol_id,
                                        "text": { "type": "string" },
                                    },
                                    "required": ["idol_id", "text"],
                                    "additionalProperties": false,
                                },
                            },
                        },
                        "required": ["idol_id", "text", "replies"],
                        "additionalProperties": false,
                    },
                },
            },
            "required": ["posts"],
            "additionalProperties": false,
        },
    })
}

/// 利用者が投稿にリプライしたときの、相手キャラの指示文 (トークの指示文に SNS の作法を足す)。
pub fn reply_instructions(snap: &Snapshot, idol_id: &str, today_key: &str) -> Result<String, ToolError> {
    let mut text = persona::talk_instructions(snap, idol_id, today_key)?;
    text.push_str(
        "\n\nいまは SNS の返信欄でのやりとり。返事は 1〜2 文・140 字以内。ツールは使わない。",
    );
    Ok(text)
}

/// リプライ生成の input 本文。
pub fn reply_input(post_author: &str, post_text: &str, user_text: &str) -> String {
    format!(
        "{post_author} の投稿:\n{post_text}\n\nこの投稿へのプロデューサーのリプライ:\n{user_text}\n\nこれに返信してください。"
    )
}

// MARK: - 材料

/// 出す子を選ぶ。担当がいれば担当 (最大 3 人) とその常設ユニットの仲間を先に、
/// いなければ直近のライブのブランドから選ぶ。残りは同じブランドから埋める。
fn choose_cast(snap: &Snapshot, today_key: &str, oshi_ids: &[String], rng: &mut Rng) -> Vec<u32> {
    let eligible = |i: u32| !snap.idols[i as usize].is_external;
    let mut cast: Vec<u32> = oshi_ids
        .iter()
        .filter_map(|id| snap.idol_index_by_id.get(id).copied())
        .filter(|&i| eligible(i))
        .take(3)
        .collect();

    if cast.is_empty() {
        let brand = next_show_brand(snap, today_key).or_else(|| {
            let any: Vec<u32> = (0..snap.idols.len() as u32).filter(|&i| eligible(i)).collect();
            rng.pick(&any).and_then(|i| snap.idols[i as usize].brand_id.clone())
        });
        let pool = brand_pool(snap, brand.as_deref(), &cast);
        for _ in 0..2 {
            if let Some(i) = rng.pick(&pool).filter(|i| !cast.contains(i)) {
                cast.push(i);
            }
        }
    }

    // 常設ユニットの仲間 (それっぽい絡みの相手)。
    let anchors = cast.clone();
    for &a in &anchors {
        let mates: Vec<u32> = snap.units_by_idol[a as usize]
            .iter()
            .filter(|&&u| snap.units[u as usize].is_permanent)
            .flat_map(|&u| snap.members_by_unit[u as usize].iter().copied())
            .filter(|&m| eligible(m) && !cast.contains(&m))
            .collect();
        for _ in 0..2 {
            if cast.len() >= CAST_SIZE {
                break;
            }
            if let Some(m) = rng.pick(&mates).filter(|m| !cast.contains(m)) {
                cast.push(m);
            }
        }
    }

    // 残りは同じブランドから。
    let brand = cast.first().and_then(|&i| snap.idols[i as usize].brand_id.clone());
    let pool = brand_pool(snap, brand.as_deref(), &cast);
    let mut tries = 0;
    while cast.len() < CAST_SIZE && tries < 50 {
        tries += 1;
        if let Some(i) = rng.pick(&pool).filter(|i| !cast.contains(i)) {
            cast.push(i);
        }
    }
    cast
}

fn brand_pool(snap: &Snapshot, brand: Option<&str>, exclude: &[u32]) -> Vec<u32> {
    (0..snap.idols.len() as u32)
        .filter(|&i| {
            let idol = &snap.idols[i as usize];
            !idol.is_external && !exclude.contains(&i) && brand.is_none_or(|b| idol.brand_id.as_deref() == Some(b))
        })
        .collect()
}

/// 今日以降でいちばん近い公演のブランド。
fn next_show_brand(snap: &Snapshot, today_key: &str) -> Option<String> {
    snap.shows
        .iter()
        .filter(|s| s.date.as_str() >= today_key)
        .min_by(|a, b| a.date.cmp(&b.date))
        .and_then(|s| snap.events[s.event as usize].brand_id.clone())
}

/// 話し方の材料になる列だけのプロフィール。声優名は入れない (実在の人物に触れないため)。
fn cast_profile(snap: &Snapshot, index: u32, oshi: &[&str]) -> Value {
    let idol = &snap.idols[index as usize];
    let units: Vec<&str> = snap.units_by_idol[index as usize]
        .iter()
        .map(|&u| snap.units[u as usize].name.as_str())
        .collect();
    json!({
        "idol_id": idol.id,
        "name": idol.name,
        "nickname": idol.nickname,
        "brand": idol.brand_id,
        "age": idol.age,
        "description": idol.description,
        "hobbies": idol.hobbies,
        "units": units,
        "is_oshi": oshi.contains(&idol.id.as_str()),
    })
}

/// 一覧ツールの結果から、話題に要る列だけを残す (id は落として軽くする)。
fn compact_list(snap: &Snapshot, tool: &str, args: Value, today_key: &str) -> Option<Value> {
    let result = call_tool(snap, tool, &args, today_key).ok()?;
    let rows = result.as_object()?.values().find_map(Value::as_array)?;
    let keep = ["name", "event_name", "show_name", "title", "date", "first_date", "last_date", "release_date", "venue", "venues", "kind", "credited_as", "unit_name", "song_count"];
    let compact: Vec<Value> = rows
        .iter()
        .map(|row| {
            let mut o = serde_json::Map::new();
            for key in keep {
                if let Some(v) = row.get(key).filter(|v| !v.is_null()) {
                    o.insert(key.to_string(), v.clone());
                }
            }
            Value::Object(o)
        })
        .filter(|v| v.as_object().is_some_and(|o| !o.is_empty()))
        .collect();
    (!compact.is_empty()).then(|| json!({ "brand": args["brand"], "items": compact }))
}

/// `YYYY-MM-DD` の n か月前の `YYYY-MM` (月単位で足りる)。
fn months_ago(today_key: &str, months: i32) -> String {
    let year: i32 = today_key.get(0..4).and_then(|s| s.parse().ok()).unwrap_or(2000);
    let month: i32 = today_key.get(5..7).and_then(|s| s.parse().ok()).unwrap_or(1);
    let total = year * 12 + (month - 1) - months;
    format!("{:04}-{:02}", total.div_euclid(12), total.rem_euclid(12) + 1)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    #[test]
    fn 担当がいれば担当を含む6人を選び出力の型をcastで縛る() {
        let snap = bundle_snapshot();
        let oshi = snap.idols.iter().find(|i| !i.is_external && i.brand_id.as_deref() == Some("sc")).unwrap();
        let req = request(&snap, "2026-10-01", &[oshi.id.clone()], &[], 42);
        assert_eq!(req.cast_ids.len(), CAST_SIZE);
        assert_eq!(req.cast_ids[0], oshi.id);
        let mut unique = req.cast_ids.clone();
        unique.sort();
        unique.dedup();
        assert_eq!(unique.len(), CAST_SIZE, "同じ子が二重に入っている");
        let enum_ids = &req.text_format["schema"]["properties"]["posts"]["items"]["properties"]["idol_id"]["enum"];
        assert_eq!(enum_ids, &json!(req.cast_ids));
        assert!(req.instructions.contains("is_oshi"));
        assert!(req.input.contains("\"is_oshi\":true"));
        // 話題の種に DB の行が入っている (一覧ツールの列名とずれると空になる)。
        assert!(req.input.contains("\"recent_shows\":[{"), "{}", req.input);
        assert!(req.input.contains("\"event_name\""), "{}", req.input);
    }

    #[test]
    fn 担当がいなくても選べて同じ種なら同じ顔ぶれ() {
        let snap = bundle_snapshot();
        let a = request(&snap, "2026-10-01", &[], &[], 7);
        let b = request(&snap, "2026-10-01", &[], &[], 7);
        assert_eq!(a.cast_ids, b.cast_ids);
        assert_eq!(a.cast_ids.len(), CAST_SIZE);
        assert!(!a.instructions.contains("is_oshi"));
    }

    #[test]
    fn 直近の投稿は繰り返さないよう渡す() {
        let snap = bundle_snapshot();
        let req = request(&snap, "2026-10-01", &[], &["きょうのレッスンも頑張った！".into()], 1);
        assert!(req.input.contains("きょうのレッスンも頑張った！"));
    }

    #[test]
    fn 月をまたいで数か月前を出す() {
        assert_eq!(months_ago("2026-02-10", 3), "2025-11");
        assert_eq!(months_ago("2026-10-01", 3), "2026-07");
    }
}
