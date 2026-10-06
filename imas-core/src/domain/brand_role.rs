//! 担当ブランド (アプリ全体の設定)。ブランドごとに **なし / 担当 / メイン** の 3 段で持つ。メインは複数可。
//!
//! - 端末は設定に保存の形 ([`brand_roles_to_json`]) の文字列を 1 つ持ち、バックアップで運ぶ。
//!   空文字は「まだ決めていない」で、そのときは記録から組んだ既定 ([`brand_role_defaults`]) を使う。
//!   一度でも決めたら (全部「なし」でも) 既定には戻さない。
//! - 並べるブランドはブランドの並び順で、その他 (`other`) は並べない (「担当している」と言える範囲ではない)。
//! - 既定: 担当アイドルのいるブランドはメイン。担当がいなければ、いちばん多く参加したブランドをメイン。
//!   ほかに 2 公演以上参加したブランドは担当。
//! - 3 段の値は段の番号 (0 = なし・1 = 担当・2 = メイン) で端末のスライダーと受け渡す
//!   ([`brand_role_steps`] / [`brand_role_from_index`])。
//!
//! プロフィール帳の担当ブランドの丸 (担当 = 丸・メイン = 二重丸) はこの設定から描く。

use chrono::NaiveDate;
use std::collections::HashMap;

/// 担当ブランドの段。並びはスライダーの左から右。
#[derive(uniffi::Enum, Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum BrandRole {
    /// なし。
    #[default]
    None,
    /// 担当 (丸)。
    Oshi,
    /// メイン (二重丸)。複数のブランドをメインにできる。
    Main,
}

/// スライダーの段 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BrandRoleStep {
    pub role: BrandRole,
    /// 段の番号 (左から 0)。
    pub index: u32,
    /// 保存のキー (`none` / `oshi` / `main`)。
    pub key: String,
    /// 「なし」「担当」「メイン」。
    pub label: String,
}

/// ブランド 1 つ (端末のマスタのまま渡す。並べる順と並べないブランドはコアが決める)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BrandRoleBrand {
    pub id: String,
    /// 短い名前 (「ミリオン」)。
    pub label: String,
    /// ブランドの色 (hex)。
    pub color: Option<String>,
    pub sort_order: i64,
}

/// 参加した公演 1 つのブランド (予定が混ざってよい。今日より後は数えない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BrandRoleVisit {
    /// `YYYY-MM-DD`。
    pub date: String,
    pub brand_id: Option<String>,
}

/// 既定を組む材料 (アプリの記録)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BrandRoleRecord {
    /// 今日 (`YYYY-MM-DD`、JST)。
    pub today: String,
    pub brands: Vec<BrandRoleBrand>,
    /// 担当の所属ブランド (担当の順)。
    pub oshi_brand_ids: Vec<String>,
    pub visits: Vec<BrandRoleVisit>,
}

/// 設定の 1 行 (ブランド 1 つと段)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BrandRoleRow {
    pub brand_id: String,
    pub label: String,
    pub color: Option<String>,
    pub role: BrandRole,
}

/// 今の設定 (保存が無ければ既定)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BrandRoleSettings {
    /// 自分で決めたことがあるか (false なら `rows` は記録から組んだ既定)。
    pub configured: bool,
    /// ブランドの並び順、その他を除く。
    pub rows: Vec<BrandRoleRow>,
}

const ALL_ROLES: [BrandRole; 3] = [BrandRole::None, BrandRole::Oshi, BrandRole::Main];

/// 並べないブランド。
const BRANDS_NOT_LISTED: [&str; 1] = ["other"];

/// 担当と言える参加の数の下限 (1 公演だけの合同ライブで丸を付けない)。
const MIN_VISITS_FOR_OSHI: u32 = 2;

pub fn brand_role_step(role: BrandRole) -> BrandRoleStep {
    let (index, key, label) = match role {
        BrandRole::None => (0, "none", "なし"),
        BrandRole::Oshi => (1, "oshi", "担当"),
        BrandRole::Main => (2, "main", "メイン"),
    };
    BrandRoleStep {
        role,
        index,
        key: key.into(),
        label: label.into(),
    }
}

/// スライダーの段 (左から なし・担当・メイン)。
pub fn brand_role_steps() -> Vec<BrandRoleStep> {
    ALL_ROLES.into_iter().map(brand_role_step).collect()
}

/// 段の番号から段 (範囲の外は端に寄せる)。
pub fn brand_role_from_index(index: i64) -> BrandRole {
    ALL_ROLES[index.clamp(0, ALL_ROLES.len() as i64 - 1) as usize]
}

/// 並べるブランド (ブランドの並び順、その他を除く)。
pub fn listed_brands(brands: &[BrandRoleBrand]) -> Vec<&BrandRoleBrand> {
    let mut out: Vec<&BrandRoleBrand> = brands
        .iter()
        .filter(|b| !BRANDS_NOT_LISTED.contains(&b.id.as_str()))
        .collect();
    out.sort_by(|a, b| {
        a.sort_order
            .cmp(&b.sort_order)
            .then_with(|| a.id.cmp(&b.id))
    });
    out
}

fn parse_date(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(s.get(..10)?, "%Y-%m-%d").ok()
}

/// 今日までに参加した公演の数 (ブランドごと)。
fn visit_counts(record: &BrandRoleRecord) -> HashMap<&str, u32> {
    let today = parse_date(&record.today);
    let mut counts: HashMap<&str, u32> = HashMap::new();
    for v in &record.visits {
        let past = matches!((parse_date(&v.date), today), (Some(d), Some(t)) if d <= t);
        if let (true, Some(b)) = (past, v.brand_id.as_deref()) {
            *counts.entry(b).or_default() += 1;
        }
    }
    counts
}

/// 記録から組んだ既定 (並べるブランドすべて、ブランドの並び順)。
///
/// - 担当アイドルのいるブランドはメイン。
/// - 担当がいなければ、いちばん多く参加したブランド (同数は並び順で先) をメイン。
/// - ほかに [`MIN_VISITS_FOR_OSHI`] 公演以上参加したブランドは担当。
pub fn brand_role_defaults(record: &BrandRoleRecord) -> Vec<BrandRoleRow> {
    let listed = listed_brands(&record.brands);
    let counts = visit_counts(record);
    let oshi_mains: Vec<&str> = record
        .oshi_brand_ids
        .iter()
        .map(String::as_str)
        .filter(|id| listed.iter().any(|b| b.id == *id))
        .collect();
    let top_visited = if oshi_mains.is_empty() {
        listed
            .iter()
            .filter_map(|b| counts.get(b.id.as_str()).map(|n| (b.id.as_str(), *n)))
            .fold(None::<(&str, u32)>, |best, (id, n)| match best {
                Some((_, m)) if m >= n => best,
                _ => Some((id, n)),
            })
            .map(|(id, _)| id)
    } else {
        None
    };
    listed
        .into_iter()
        .map(|b| {
            let id = b.id.as_str();
            let role = if oshi_mains.contains(&id) || top_visited == Some(id) {
                BrandRole::Main
            } else if counts.get(id).copied().unwrap_or(0) >= MIN_VISITS_FOR_OSHI {
                BrandRole::Oshi
            } else {
                BrandRole::None
            };
            BrandRoleRow {
                brand_id: b.id.clone(),
                label: b.label.clone(),
                color: b.color.clone(),
                role,
            }
        })
        .collect()
}

/// 保存の形 (`{"main":[…],"oshi":[…]}`)。なしのブランドは書かない。
#[derive(serde::Serialize, serde::Deserialize, Default)]
#[serde(default)]
struct RolesDto {
    main: Vec<String>,
    oshi: Vec<String>,
}

/// 保存の形から段を引く。空・壊れた JSON は None (まだ決めていない)。
fn saved_roles(json: &str) -> Option<HashMap<String, BrandRole>> {
    if json.trim().is_empty() {
        return None;
    }
    let dto = serde_json::from_str::<RolesDto>(json).ok()?;
    let mut out = HashMap::new();
    // 両方に書かれていたらメインを採る。
    for id in dto.oshi {
        out.insert(id, BrandRole::Oshi);
    }
    for id in dto.main {
        out.insert(id, BrandRole::Main);
    }
    Some(out)
}

/// 自分で決めたことがあるか (保存の形が読める)。
pub fn brand_roles_configured(json: &str) -> bool {
    saved_roles(json).is_some()
}

/// 今の設定。保存があればそれ (書かれていないブランドはなし)、無ければ記録から組んだ既定。
pub fn brand_role_settings(json: &str, record: &BrandRoleRecord) -> BrandRoleSettings {
    match saved_roles(json) {
        Some(saved) => BrandRoleSettings {
            configured: true,
            rows: listed_brands(&record.brands)
                .into_iter()
                .map(|b| BrandRoleRow {
                    brand_id: b.id.clone(),
                    label: b.label.clone(),
                    color: b.color.clone(),
                    role: saved.get(&b.id).copied().unwrap_or_default(),
                })
                .collect(),
        },
        None => BrandRoleSettings {
            configured: false,
            rows: brand_role_defaults(record),
        },
    }
}

/// 担当かメインのブランドが 1 つでもあるか (全部「なし」や未設定は false)。
/// バックアップの取り込みで、端末の設定が何も言っていないなら運んできた設定で埋めてよい、の判定に使う。
pub fn brand_roles_has_any(json: &str) -> bool {
    saved_roles(json).is_some_and(|m| m.values().any(|r| *r != BrandRole::None))
}

/// 行の段を 1 つ変えた行。
pub fn brand_role_set(rows: &[BrandRoleRow], brand_id: &str, role: BrandRole) -> Vec<BrandRoleRow> {
    rows.iter()
        .cloned()
        .map(|mut r| {
            if r.brand_id == brand_id {
                r.role = role;
            }
            r
        })
        .collect()
}

/// 行を保存の形にする (行の並びのまま。なしは書かない)。
pub fn brand_roles_to_json(rows: &[BrandRoleRow]) -> String {
    let pick = |role: BrandRole| -> Vec<String> {
        let mut ids: Vec<String> = Vec::new();
        for r in rows.iter().filter(|r| r.role == role) {
            if !ids.contains(&r.brand_id) {
                ids.push(r.brand_id.clone());
            }
        }
        ids
    };
    let dto = RolesDto {
        main: pick(BrandRole::Main),
        oshi: pick(BrandRole::Oshi),
    };
    serde_json::to_string(&dto).unwrap_or_default()
}

/// 保存の形の段 (並べるブランドに限らない。バックアップの取り込み・プロフィール帳が読む)。
pub fn brand_role_of(json: &str, brand_id: &str) -> Option<BrandRole> {
    saved_roles(json).map(|m| m.get(brand_id).copied().unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn brand(id: &str, order: i64) -> BrandRoleBrand {
        BrandRoleBrand {
            id: id.into(),
            label: format!("B{id}"),
            color: None,
            sort_order: order,
        }
    }

    fn visit(date: &str, brand: &str) -> BrandRoleVisit {
        BrandRoleVisit {
            date: date.into(),
            brand_id: Some(brand.into()),
        }
    }

    fn record(oshi: &[&str], visits: Vec<BrandRoleVisit>) -> BrandRoleRecord {
        BrandRoleRecord {
            today: "2026-10-06".into(),
            brands: vec![
                brand("ml", 3),
                brand("765", 1),
                brand("other", 99),
                brand("cg", 2),
                brand("sc", 4),
            ],
            oshi_brand_ids: oshi.iter().map(|s| s.to_string()).collect(),
            visits,
        }
    }

    fn roles(rows: &[BrandRoleRow]) -> Vec<(&str, BrandRole)> {
        rows.iter().map(|r| (r.brand_id.as_str(), r.role)).collect()
    }

    #[test]
    fn steps_are_none_oshi_main_and_index_clamps() {
        let steps = brand_role_steps();
        assert_eq!(
            steps.iter().map(|s| s.label.as_str()).collect::<Vec<_>>(),
            ["なし", "担当", "メイン"]
        );
        assert_eq!(steps.iter().map(|s| s.index).collect::<Vec<_>>(), [0, 1, 2]);
        assert_eq!(brand_role_from_index(-3), BrandRole::None);
        assert_eq!(brand_role_from_index(1), BrandRole::Oshi);
        assert_eq!(brand_role_from_index(9), BrandRole::Main);
    }

    #[test]
    fn defaults_make_every_oshi_brand_main_and_frequent_brands_oshi() {
        let r = record(
            &["ml", "765", "ml"],
            vec![
                visit("2025-01-01", "cg"),
                visit("2025-02-01", "cg"),
                visit("2025-03-01", "sc"),
                // 今日より後 (予定) は数えない。
                visit("2027-01-01", "sc"),
            ],
        );
        assert_eq!(
            roles(&brand_role_defaults(&r)),
            [
                ("765", BrandRole::Main),
                ("cg", BrandRole::Oshi),
                ("ml", BrandRole::Main),
                ("sc", BrandRole::None),
            ]
        );
    }

    #[test]
    fn defaults_without_oshi_make_the_most_visited_brand_main() {
        let r = record(
            &[],
            vec![
                visit("2025-01-01", "sc"),
                visit("2025-02-01", "cg"),
                visit("2025-03-01", "cg"),
                visit("2025-04-01", "sc"),
            ],
        );
        // 同数は並び順で先 (cg が先)。
        assert_eq!(
            roles(&brand_role_defaults(&r)),
            [
                ("765", BrandRole::None),
                ("cg", BrandRole::Main),
                ("ml", BrandRole::None),
                ("sc", BrandRole::Oshi),
            ]
        );
        assert!(brand_role_defaults(&record(&[], vec![]))
            .iter()
            .all(|r| r.role == BrandRole::None));
    }

    #[test]
    fn settings_use_defaults_only_until_configured() {
        let r = record(&["ml"], vec![]);
        let unset = brand_role_settings("", &r);
        assert!(!unset.configured);
        assert_eq!(unset.rows[2].role, BrandRole::Main);
        // 壊れた JSON もまだ決めていない扱い。
        assert!(!brand_role_settings("{", &r).configured);

        // 全部なしで決めたら、既定には戻さない。
        let none = brand_roles_to_json(
            &unset
                .rows
                .iter()
                .map(|row| BrandRoleRow {
                    role: BrandRole::None,
                    ..row.clone()
                })
                .collect::<Vec<_>>(),
        );
        assert_eq!(none, r#"{"main":[],"oshi":[]}"#);
        let saved = brand_role_settings(&none, &r);
        assert!(saved.configured);
        assert!(saved.rows.iter().all(|row| row.role == BrandRole::None));
        assert!(brand_roles_configured(&none));
        assert!(!brand_roles_configured(""));
        assert!(!brand_roles_has_any(&none) && !brand_roles_has_any(""));
        assert!(brand_roles_has_any(r#"{"oshi":["ml"]}"#));
    }

    #[test]
    fn multiple_mains_round_trip_through_json() {
        let r = record(&[], vec![]);
        let rows = brand_role_settings("", &r).rows;
        let rows = brand_role_set(&rows, "765", BrandRole::Main);
        let rows = brand_role_set(&rows, "sc", BrandRole::Main);
        let rows = brand_role_set(&rows, "cg", BrandRole::Oshi);
        let json = brand_roles_to_json(&rows);
        assert_eq!(json, r#"{"main":["765","sc"],"oshi":["cg"]}"#);
        let back = brand_role_settings(&json, &r);
        assert_eq!(
            roles(&back.rows),
            [
                ("765", BrandRole::Main),
                ("cg", BrandRole::Oshi),
                ("ml", BrandRole::None),
                ("sc", BrandRole::Main),
            ]
        );
        assert_eq!(brand_role_of(&json, "sc"), Some(BrandRole::Main));
        assert_eq!(brand_role_of(&json, "ml"), Some(BrandRole::None));
        assert_eq!(brand_role_of("", "sc"), None);
    }

    #[test]
    fn json_with_a_brand_in_both_lists_reads_as_main_and_ignores_unknown_keys() {
        let r = record(&[], vec![]);
        let s = brand_role_settings(r#"{"oshi":["ml"],"main":["ml"],"future":1}"#, &r);
        assert_eq!(s.rows[2].role, BrandRole::Main);
    }
}
