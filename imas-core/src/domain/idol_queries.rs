//! アイドル・ブランドマスタまわりのスナップショットクエリ (純粋ロジック)。
//!
//! SQL 時代の対応 (iOS の `IdolReading` / `BrandReading` ポート配下):
//! - [`idol_list`]                 ← fetchIdols(brandId:) (AppDatabase+IdolQueries)
//! - [`idol_records_by_ids`]       ← fetchIdols(ids:) / fetchIdol(id:) (AppDatabase+SongQueries)
//! - [`idols_by_birth_month`] / [`idols_by_constellation`] / [`idols_by_birth_place`] /
//!   [`idols_by_blood_type`] ← fetchIdols(criterion:) (AppDatabase+EventQueries)
//! - [`idol_cast_names`]           ← fetchIdolCastNames (AppDatabase+IdolQueries)
//! - [`idols_by_voice_actor`]      ← fetchIdolsByVoiceActor (AppDatabase+IdolQueries)
//! - [`search_idols`]              ← searchIdols(query:limit:) (AppDatabase+StatsQueries)
//! - [`all_idols_for_picker`]      ← fetchAllIdolsForPicker (AppDatabase+Sync)
//! - [`current_voice_actor_name`]  ← fetchCurrentVoiceActor (AppDatabase+IdolQueries)
//! - [`voice_actor_history`]       ← fetchVoiceActorHistory (AppDatabase+IdolQueries)
//! - [`idol_units`]                ← fetchIdolUnits (AppDatabase+IdolQueries)
//! - [`idol_shows`]                ← fetchIdolShows (AppDatabase+IdolQueries)
//! - [`brand_records`]             ← fetchBrands (AppDatabase+StatsQueries)
//!
//! アイドル→曲の逆引き (fetchIdolSongs / fetchIdolPerformedSongs / fetchIdolSongHistory)
//! は Phase 2 の idol_song_queries.rs が既に担っているのでここには置かない (二重 export しない)。
//!
//! SQL の暗黙挙動はここで明示コードに固定する (等価性はテストの照合で保証):
//! - `ORDER BY sort_order` はスナップショットの `idol_order` / `brand_order`
//!   (構築時に前計算・同値は添字で決定的) をそのまま流す。
//! - `SELECT DISTINCT` (idol_brands JOIN / CV 逆引き) は添字 HashSet / 前計算済み
//!   dedup で行単位の重複を消す。
//! - `IN (...)` の結果順は SQL では未規定 → 「入力 id 順・初出のみ・未知 id は
//!   読み飛ばし」で決定化 (song_detail_queries::song_records_by_ids と同じ規約)。
//! - `LIKE '%q%' ESCAPE '\'` (iOS likeEscaped 適用後) はワイルドカードを含まない
//!   リテラル部分一致 = 「ASCII だけ大文字小文字を無視した contains」(SQLite 既定の
//!   LIKE は ASCII のみ case-insensitive)。NULL 列は LIKE が NULL (偽) になるので不一致。
//! - `=` 比較 (星座・出身地・血液型) は BINARY 照合の完全一致。NULL は何とも等しくない。
//! - `ORDER BY date DESC` の同日 (SQL では未規定) は (sort_order ASC, 添字) で決定化
//!   (プラットフォーム間で同一結果を返すのが共有コアの目的なので、非決定性は残さない)。
//! - user_marks はスナップショットに無い (このスライスのクエリは元々マーク非依存)。

use crate::domain::snapshot::{Idol, Snapshot};
use std::collections::{HashMap, HashSet};
use crate::domain::screen_composition::IdolProfileInput;
use crate::domain::text_search_index::FoldedNeedle;

// =============================================================================
// FFI 射影 Record (uniffi は型 derive のみ / ロジックはこのファイルの関数側)
// =============================================================================

/// idols 1 行の射影。詳細プロフィール画面が全カラムを使うため全域射影になる
/// (GRDB `Idol` / Room Entity と同じ「Record = Entity 兼用」の現実的判断)。
/// height 等の REAL 列が f64 なので Eq は付かない (PartialEq のみ)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct IdolRecord {
    pub id: String,
    pub brand_id: Option<String>,
    pub name: String,
    pub name_kana: Option<String>,
    pub name_romaji: Option<String>,
    pub color: Option<String>,
    pub sort_order: Option<i64>,
    pub birthday: Option<String>,
    pub blood_type: Option<String>,
    pub height: Option<f64>,
    pub weight: Option<f64>,
    pub birth_place: Option<String>,
    pub age: Option<i64>,
    pub bust: Option<f64>,
    pub waist: Option<f64>,
    pub hip: Option<f64>,
    pub constellation: Option<String>,
    pub hobbies: Option<String>,
    pub talents: Option<String>,
    pub description: Option<String>,
    pub gender: Option<String>,
    pub handedness: Option<String>,
    pub family_name: Option<String>,
    pub given_name: Option<String>,
    pub nickname: Option<String>,
    pub debut_date: Option<String>,
    pub attribute: Option<String>,
    pub is_external: bool,
    pub aliases: Option<String>,
}

impl From<&Idol> for IdolRecord {
    fn from(i: &Idol) -> Self {
        Self {
            id: i.id.clone(),
            brand_id: i.brand_id.clone(),
            name: i.name.clone(),
            name_kana: i.name_kana.clone(),
            name_romaji: i.name_romaji.clone(),
            color: i.color.clone(),
            sort_order: i.sort_order,
            birthday: i.birthday.clone(),
            blood_type: i.blood_type.clone(),
            height: i.height,
            weight: i.weight,
            birth_place: i.birth_place.clone(),
            age: i.age,
            bust: i.bust,
            waist: i.waist,
            hip: i.hip,
            constellation: i.constellation.clone(),
            hobbies: i.hobbies.clone(),
            talents: i.talents.clone(),
            description: i.description.clone(),
            gender: i.gender.clone(),
            handedness: i.handedness.clone(),
            family_name: i.family_name.clone(),
            given_name: i.given_name.clone(),
            nickname: i.nickname.clone(),
            debut_date: i.debut_date.clone(),
            attribute: i.attribute.clone(),
            is_external: i.is_external,
            aliases: i.aliases.clone(),
        }
    }
}

/// brands 1 行の射影 (fetchBrands)。icon_url は Documents 専用列で Bundle DB では None。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BrandRecord {
    pub id: String,
    pub name: String,
    pub short_name: String,
    pub color: Option<String>,
    pub sort_order: i64,
    pub icon_url: Option<String>,
}

/// units 1 行の射影 (fetchIdolUnits の返す Unit 相当)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct IdolUnitRecord {
    pub id: String,
    pub brand_id: String,
    pub name: String,
    pub is_permanent: bool,
    pub name_alt: Option<String>,
}

/// idol_voice_actors 1 行の射影 (fetchVoiceActorHistory の返す IdolVoiceActor 相当)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct IdolVoiceActorRecord {
    pub id: String,
    pub idol_id: String,
    pub name: String,
    pub valid_from: Option<String>,
    pub valid_to: Option<String>,
}

/// アイドルの出演公演 1 行の射影 (fetchIdolShows の CastShowRow 相当)。
///
/// idol_song_queries::IdolSongShowRecord と同形だが、あちらは「アイドル×曲」の
/// 披露履歴という別クエリの射影。名前が中身を表すよう別 Record にしてある
/// (FFI 上の型を跨いで共有すると、片方の画面都合の列変更がもう片方を壊す)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct IdolShowRecord {
    pub show_id: String,
    pub event_id: String,
    pub event_name: String,
    pub show_name: String,
    /// YYYY-MM-DD。
    pub date: String,
    pub venue: Option<String>,
    /// show_cast 上の役割。行が無い (セトリだけの出演) は SQL の
    /// `COALESCE(..., 'member')` と同じく 'member' に落とす (既存規約: 既定はクエリ層で補う)。
    pub cast_role: String,
}

// =============================================================================
// クエリ関数 (Snapshot を引数に取る純粋関数)
// =============================================================================

/// アイドル一覧 (外部ゲスト演者は除外)。fetchIdols(brandId:) 相当。
///
/// 元 SQL (brand_id あり):
/// ```sql
/// SELECT DISTINCT i.* FROM idols i JOIN idol_brands ib ON i.id = ib.idol_id
/// WHERE ib.brand_id = ? AND i.is_external = 0 ORDER BY i.sort_order
/// ```
/// brand_id なしは `WHERE is_external = 0 ORDER BY sort_order` の全件。
/// idols_by_brand は構築時に sort_order 順へ前計算済みなので、ここは
/// DISTINCT (添字 dedup) と is_external の絞り込みだけを担う。
/// 未知の brand_id は空 (SQL の 0 行と同じ)。
pub fn idol_list(snap: &Snapshot, brand_id: Option<&str>) -> Vec<IdolRecord> {
    match brand_id {
        None => snap
            .idol_order
            .iter()
            .map(|&i| &snap.idols[i as usize])
            .filter(|i| !i.is_external)
            .map(IdolRecord::from)
            .collect(),
        Some(bid) => {
            let Some(&bi) = snap.brand_index_by_id.get(bid) else { return vec![] };
            let mut seen: HashSet<u32> = HashSet::new();
            snap.idols_by_brand[bi as usize]
                .iter()
                .filter(|l| seen.insert(l.idol))
                .map(|l| &snap.idols[l.idol as usize])
                .filter(|i| !i.is_external)
                .map(IdolRecord::from)
                .collect()
        }
    }
}

/// アイドル id 群の一括取得 (fetchIdols(ids:) / fetchIdol(id:) の N+1 防止用)。
///
/// SQL の `IN` は結果順未規定・重複 id も 1 行だったので、「入力 id 順・初出のみ・
/// 未知 id は読み飛ばし」で決定化する (song_detail_queries と同じ規約)。
pub fn idol_records_by_ids(snap: &Snapshot, idol_ids: &[String]) -> Vec<IdolRecord> {
    let mut seen: HashSet<u32> = HashSet::new();
    idol_ids
        .iter()
        .filter_map(|id| snap.idol_index_by_id.get(id).copied())
        .filter(|&i| seen.insert(i))
        .map(|i| IdolRecord::from(&snap.idols[i as usize]))
        .collect()
}

/// 誕生月フィルタ (IdolFilterCriterion.birthMonth)。
///
/// 元 SQL: `birthday LIKE '--MM-%' ORDER BY sort_order`。birthday は '--MM-DD'
/// (年なし) 形式なので前方一致で月が取れる。パターンは数字とハイフンのみで
/// LIKE の ASCII case folding の影響を受けない → 素の starts_with で等価。
/// 一覧 (idol_list) と違い is_external を絞らないのは元 SQL のまま。
pub fn idols_by_birth_month(snap: &Snapshot, month: u32) -> Vec<IdolRecord> {
    let prefix = format!("--{month:02}-");
    official_order_filter(snap, |i| {
        i.birthday.as_deref().is_some_and(|b| b.starts_with(&prefix))
    })
}

/// 星座フィルタ (IdolFilterCriterion.constellation)。
/// 元 SQL: `constellation = ? ORDER BY sort_order`。`=` は BINARY 完全一致・NULL は不一致。
pub fn idols_by_constellation(snap: &Snapshot, constellation: &str) -> Vec<IdolRecord> {
    official_order_filter(snap, |i| i.constellation.as_deref() == Some(constellation))
}

/// 出身地フィルタ (IdolFilterCriterion.birthPlace)。
/// 元 SQL: `birth_place = ? ORDER BY sort_order`。
pub fn idols_by_birth_place(snap: &Snapshot, birth_place: &str) -> Vec<IdolRecord> {
    official_order_filter(snap, |i| i.birth_place.as_deref() == Some(birth_place))
}

/// 血液型フィルタ (IdolFilterCriterion.bloodType)。
/// 元 SQL: `blood_type = ? ORDER BY sort_order`。
pub fn idols_by_blood_type(snap: &Snapshot, blood_type: &str) -> Vec<IdolRecord> {
    official_order_filter(snap, |i| i.blood_type.as_deref() == Some(blood_type))
}

/// sort_order 順 (前計算済み idol_order) を保ったまま述語で絞る共通経路。
fn official_order_filter(snap: &Snapshot, pred: impl Fn(&Idol) -> bool) -> Vec<IdolRecord> {
    snap.idol_order
        .iter()
        .map(|&i| &snap.idols[i as usize])
        .filter(|i| pred(i))
        .map(IdolRecord::from)
        .collect()
}

/// アイドル全員の現任 CV 名マップ (fetchIdolCastNames)。
///
/// 元 SQL は現任行 (valid_to IS NULL) を `IFNULL(valid_from,'')` 昇順で流し
/// 辞書へ後勝ち代入していた = 各アイドルにつき valid_from が最大の現任が残る。
/// スナップショットの current_voice_actor() は同じ行を先頭一致で返す
/// (voice_actors_by_idol が IFNULL(valid_from,'') DESC で前計算済み) ので、
/// 全アイドルを回して詰め直すだけで等価になる。現任なしのアイドルはキー自体を作らない。
pub fn idol_cast_names(snap: &Snapshot) -> HashMap<String, String> {
    let mut names = HashMap::new();
    for (ii, idol) in snap.idols.iter().enumerate() {
        if let Some(va) = snap.current_voice_actor(ii as u32) {
            names.insert(idol.id.clone(), va.name.clone());
        }
    }
    names
}

/// 声優名 (完全一致) で担当アイドルを逆引き (fetchIdolsByVoiceActor)。
///
/// 元 SQL:
/// ```sql
/// SELECT DISTINCT i.* FROM idols i JOIN idol_voice_actors v ON v.idol_id = i.id
/// WHERE v.name = ? ORDER BY i.sort_order
/// ```
/// 歴代すべてを対象にする (前任者の名前で引いても辿り着ける方が用途に合う) のも
/// 元実装のまま。DISTINCT + ORDER BY は idols_by_voice_actor_name に前計算済み。
pub fn idols_by_voice_actor(snap: &Snapshot, name: &str) -> Vec<IdolRecord> {
    snap.idols_by_voice_actor_name
        .get(name)
        .map(|list| {
            list.iter()
                .map(|&i| IdolRecord::from(&snap.idols[i as usize]))
                .collect()
        })
        .unwrap_or_default()
}

/// 名前 / かな / ローマ字 / 別名 / CV 名 (歴代) の部分一致検索 (searchIdols)。
///
/// 元 SQL:
/// ```sql
/// SELECT * FROM idols
///  WHERE name LIKE :p ESCAPE '\' OR name_kana LIKE :p ESCAPE '\'
///     OR name_romaji LIKE :p ESCAPE '\' OR aliases LIKE :p ESCAPE '\'
///     OR EXISTS (SELECT 1 FROM idol_voice_actors v
///                 WHERE v.idol_id = idols.id AND v.name LIKE :p ESCAPE '\')
///  ORDER BY sort_order LIMIT :limit
/// ```
/// :p は likeEscaped 済みの `%query%` なのでワイルドカードを含まないリテラル部分一致。
/// 当たり方は一覧の索引 (`TextSearchCatalog`) と同じ `FoldedNeedle` に寄せてあり、
/// 大文字小文字に加えて**ひらがな↔カタカナも畳む**。元 SQL の LIKE (ASCII の大小のみ)
/// の真の上位集合。ただし `limit` で切る以上、**打ち切りで押し出される行はある**
/// (「ミ」で読みが「み」の 46 人が新たに入り、上位 50 件の顔ぶれが変わる)。
/// 絞り込みが甘い語ほど増えるが、そこは語を足して絞る局面なので許容する。
/// NULL 列は不一致 (`NULL LIKE ?` は NULL)。
/// is_external を絞らない (ピッカーはゲスト出演者も引けてよい) のも元 SQL のまま。
pub fn search_idols(snap: &Snapshot, query: &str, limit: u32) -> Vec<IdolRecord> {
    let needle = FoldedNeedle::new(query);
    snap.idol_order
        .iter()
        .filter(|&&i| snap.idol_picker_search[i as usize].matches(needle.as_bytes()))
        .take(limit as usize)
        .map(|&i| IdolRecord::from(&snap.idols[i as usize]))
        .collect()
}

/// 編集 UI のピッカー用: 全アイドル (fetchAllIdolsForPicker)。
/// 元 SQL は `ORDER BY sort_order` のみで is_external も絞らない全件
/// (外部ゲストも出演者として選べる必要がある)。
pub fn all_idols_for_picker(snap: &Snapshot) -> Vec<IdolRecord> {
    snap.idol_order
        .iter()
        .map(|&i| IdolRecord::from(&snap.idols[i as usize]))
        .collect()
}

/// 現任 CV 名 (fetchCurrentVoiceActor)。
///
/// 元 SQL: `WHERE idol_id = ? AND valid_to IS NULL ORDER BY IFNULL(valid_from,'') DESC
/// LIMIT 1`。交代発表後・後任未定の間は現任が居ないので None。
/// 未知の idol_id も None (SQL の 0 行と同じ)。
pub fn current_voice_actor_name(snap: &Snapshot, idol_id: &str) -> Option<String> {
    let &ii = snap.idol_index_by_id.get(idol_id)?;
    snap.current_voice_actor(ii).map(|va| va.name.clone())
}

/// 歴代 CV (新しい順・fetchVoiceActorHistory)。
///
/// 元 SQL: `WHERE idol_id = ? ORDER BY IFNULL(valid_from,'') DESC`。
/// 並びは voice_actors_by_idol に前計算済み (同値は添字で決定的)。
pub fn voice_actor_history(snap: &Snapshot, idol_id: &str) -> Vec<IdolVoiceActorRecord> {
    let Some(&ii) = snap.idol_index_by_id.get(idol_id) else { return vec![] };
    snap.voice_actors_by_idol[ii as usize]
        .iter()
        .map(|&v| {
            let va = &snap.idol_voice_actors[v as usize];
            IdolVoiceActorRecord {
                id: va.id.clone(),
                idol_id: snap.idols[va.idol as usize].id.clone(),
                name: va.name.clone(),
                valid_from: va.valid_from.clone(),
                valid_to: va.valid_to.clone(),
            }
        })
        .collect()
}

/// 所属ユニット一覧 (fetchIdolUnits)。
///
/// 元 SQL:
/// ```sql
/// SELECT u.* FROM units u JOIN unit_members um ON u.id = um.unit_id
/// WHERE um.idol_id = ? ORDER BY u.name
/// ```
/// ORDER BY u.name (BINARY = バイト列昇順) は units_by_idol に前計算済み。
pub fn idol_units(snap: &Snapshot, idol_id: &str) -> Vec<IdolUnitRecord> {
    let Some(&ii) = snap.idol_index_by_id.get(idol_id) else { return vec![] };
    snap.units_by_idol[ii as usize]
        .iter()
        .map(|&u| {
            let unit = &snap.units[u as usize];
            IdolUnitRecord {
                id: unit.id.clone(),
                brand_id: unit.brand_id.clone(),
                name: unit.name.clone(),
                is_permanent: unit.is_permanent,
                name_alt: unit.name_alt.clone(),
            }
        })
        .collect()
}

/// 出演公演一覧 (fetchIdolShows)。セトリ歌唱 (setlist_performers) と出演者表
/// (show_cast) の和集合 — セトリ未登録の公演でも出演履歴を拾う。
///
/// 元 SQL:
/// ```sql
/// SELECT sh.id, e.id, e.name, sh.name, sh.date, sh.venue,
///        COALESCE((SELECT cast_role FROM show_cast
///                   WHERE show_id = sh.id AND idol_id = ?), 'member')
/// FROM shows sh JOIN events e ON sh.event_id = e.id
/// WHERE sh.id IN (セトリ歌唱 show ∪ show_cast の show)
/// ORDER BY sh.date DESC
/// ```
/// 同日の並びは SQL では未規定 → (show.sort_order ASC, 添字) で決定化。
/// 未知の idol_id は空 (SQL の 0 行と同じ)。
pub fn idol_shows(snap: &Snapshot, idol_id: &str) -> Vec<IdolShowRecord> {
    let Some(&ii) = snap.idol_index_by_id.get(idol_id) else { return vec![] };
    let mut show_set: HashSet<u32> = snap.performed_items_by_idol[ii as usize]
        .iter()
        .map(|&item| snap.setlist_items[item as usize].show)
        .collect();
    show_set.extend(snap.cast_shows_by_idol[ii as usize].iter().copied());
    let mut show_indexes: Vec<u32> = show_set.into_iter().collect();
    show_indexes.sort_by(|&a, &b| {
        let (sa, sb) = (&snap.shows[a as usize], &snap.shows[b as usize]);
        sb.date
            .cmp(&sa.date)
            .then_with(|| sa.sort_order.cmp(&sb.sort_order))
            .then_with(|| a.cmp(&b))
    });
    show_indexes
        .into_iter()
        .map(|si| {
            let sh = &snap.shows[si as usize];
            let ev = &snap.events[sh.event as usize];
            IdolShowRecord {
                show_id: sh.id.clone(),
                event_id: ev.id.clone(),
                event_name: ev.name.clone(),
                show_name: sh.name.clone(),
                date: sh.date.clone(),
                venue: sh.venue.clone(),
                cast_role: snap.show_cast_role(si, ii).unwrap_or("member").to_string(),
            }
        })
        .collect()
}

/// 全ブランド (表示順・fetchBrands)。

/// アイドル詳細のプロフィール欄に渡す入力を組み立てる。
///
/// ## なぜコアに置くか
///
/// **値の整形が iOS の View にしか無かった。** 「4月3日」「160cm」「A型 ・ 牡羊座」を
/// どう作るかが `IdolDetailView` の private computed property に埋まっていて、
/// Android も Web も同じものを書き直すしかない状態だった (3 実装目が生えかけていた)。
/// [`screen_composition::idol_profile_rows`] が「並べる判断」だけを持っていたのに対し、
/// こちらは「値の作り方」を持つ。
///
/// ## 移送元
///
/// 規則は Swift 原本の逐語の写し:
/// * `ImasLiveDB/Models/Idol.swift` の `birthdayDisplay` / `heightDisplay` /
///   `threeSizeDisplay` / `birthMonth`
/// * `ImasLiveDB/Views/Idols/IdolDetailView.swift` の `ageHeightWeight` /
///   `bloodConstellation` / `birthplaceHand` / `hobbyTalent`
///
/// 区切りは全角スペース込みの `" ・ "` (原本の `joined(separator: " ・ ")`)。
/// 身長・体重・スリーサイズの整数化は Swift の `Int(_:)` と同じ**ゼロ方向への切り捨て**。
pub fn idol_profile_input(r: &IdolRecord) -> IdolProfileInput {
    IdolProfileInput {
        name_kana: r.name_kana.clone(),
        name_romaji: r.name_romaji.clone(),
        birthday_display: birthday_display(r.birthday.as_deref()),
        birth_month: birth_month(r.birthday.as_deref()),
        age_height_weight: join_parts(&[
            r.age.map(|a| format!("{a}歳")),
            height_display(r.height),
            r.weight.map(|w| format!("{}kg", w as i64)),
        ]),
        three_size: three_size(r.bust, r.waist, r.hip),
        blood_constellation: join_parts(&[
            r.blood_type.as_ref().map(|b| format!("{b}型")),
            r.constellation.clone(),
        ]),
        birthplace_handedness: join_parts(&[
            r.birth_place.clone(),
            r.handedness.as_deref().map(handedness_label),
        ]),
        hobby_talent: join_parts(&[r.hobbies.clone(), r.talents.clone()]),
        color: r.color.clone(),
    }
}

/// 原本 `joined(separator: " ・ ")`。実体は [`crate::domain::display_join::join_parts`]。
///
/// 区切り文字の判断を 1 箇所に保つための委譲。ここで `" ・ "` を書き直すと、
/// 同じ規則が Rust の中だけで複数に割れる (実際に 3 実装まで増えていた)。
fn join_parts(parts: &[Option<String>]) -> Option<String> {
    crate::domain::display_join::join_parts(parts.iter().map(|p| p.as_deref()))
}

/// `"--04-03"` → `"4月3日"` (前置ゼロを落とす)。`--` 始まりでなければそのまま返す。
fn birthday_display(birthday: Option<&str>) -> Option<String> {
    let birthday = birthday?;
    let Some(rest) = birthday.strip_prefix("--") else { return Some(birthday.to_string()) };
    let parts: Vec<&str> = rest.split('-').collect();
    match parts.as_slice() {
        [m, d] => match (m.parse::<i64>(), d.parse::<i64>()) {
            (Ok(m), Ok(d)) => Some(format!("{m}月{d}日")),
            // 数字として読めない形はそのまま出す (原本も同じ)。
            _ => Some(birthday.to_string()),
        },
        _ => Some(birthday.to_string()),
    }
}

/// `"--04-03"` → `4`。`--` 始まりでなければ月が決まらないので `None`。
fn birth_month(birthday: Option<&str>) -> Option<u32> {
    birthday?.strip_prefix("--")?.split('-').next()?.parse().ok()
}

/// 整数なら `"160cm"`、小数を含むなら `"160.5cm"`。
///
/// 原本は `"\(height)cm"` (Swift の `Double` 既定表記)。Rust の `{}` と一致することは
/// テストで固定してある。
fn height_display(height: Option<f64>) -> Option<String> {
    let h = height?;
    Some(if h.fract() == 0.0 { format!("{}cm", h as i64) } else { format!("{h}cm") })
}

/// 3 つ揃ったときだけ `"B83 W56 H84"`。1 つでも欠けたら行ごと出さない (原本と同じ)。
fn three_size(bust: Option<f64>, waist: Option<f64>, hip: Option<f64>) -> Option<String> {
    Some(format!("B{} W{} H{}", bust? as i64, waist? as i64, hip? as i64))
}

/// `right` / `left` だけ日本語にする。知らない値はそのまま出す (原本と同じ)。
fn handedness_label(handedness: &str) -> String {
    match handedness {
        "right" => "右".to_string(),
        "left" => "左".to_string(),
        other => other.to_string(),
    }
}

/// `ORDER BY sort_order` は brand_order に前計算済み (同値は添字で決定的)。
pub fn brand_records(snap: &Snapshot) -> Vec<BrandRecord> {
    snap.brand_order
        .iter()
        .map(|&b| {
            let brand = &snap.brands[b as usize];
            BrandRecord {
                id: brand.id.clone(),
                name: brand.name.clone(),
                short_name: brand.short_name.clone(),
                color: brand.color.clone(),
                sort_order: brand.sort_order,
                icon_url: brand.icon_url.clone(),
            }
        })
        .collect()
}

// =============================================================================
// テスト: Bundle DB に対する元 SQL との照合 (rusqlite 直実行) + 契約の単体テスト
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    // -----------------------------------------------------------------------
    // idol_profile_input — Swift 原本 (Models/Idol.swift + IdolDetailView.swift) の逐語移送。
    //
    // ここが崩れると、iOS の画面と Web の画面で同じアイドルの表記が変わる。
    // 期待値は原本の式から手で起こしたもので、実装から起こしていない。
    // -----------------------------------------------------------------------

    fn blank_idol() -> IdolRecord {
        IdolRecord {
            id: "x".into(), brand_id: None, name: "テスト".into(), name_kana: None,
            name_romaji: None, color: None, sort_order: None, birthday: None, blood_type: None,
            height: None, weight: None, birth_place: None, age: None, bust: None, waist: None,
            hip: None, constellation: None, hobbies: None, talents: None, description: None,
            gender: None, handedness: None, family_name: None, given_name: None, nickname: None,
            debut_date: None, attribute: None, is_external: false, aliases: None,
        }
    }

    #[test]
    fn profile_input_formats_the_birthday_like_swift() {
        let mut idol = blank_idol();
        // "--MM-DD" は前置ゼロを落として「4月3日」。
        idol.birthday = Some("--04-03".into());
        let input = idol_profile_input(&idol);
        assert_eq!(input.birthday_display.as_deref(), Some("4月3日"));
        assert_eq!(input.birth_month, Some(4));

        // 2 桁の月日も同じ規則。
        idol.birthday = Some("--12-25".into());
        assert_eq!(idol_profile_input(&idol).birthday_display.as_deref(), Some("12月25日"));

        // "--" 始まりでなければ、原本はそのまま出す (月は決まらない)。
        idol.birthday = Some("1999-04-03".into());
        let input = idol_profile_input(&idol);
        assert_eq!(input.birthday_display.as_deref(), Some("1999-04-03"));
        assert_eq!(input.birth_month, None);

        // 数字として読めない形もそのまま (落とさない)。
        idol.birthday = Some("--??-??".into());
        assert_eq!(idol_profile_input(&idol).birthday_display.as_deref(), Some("--??-??"));

        idol.birthday = None;
        assert_eq!(idol_profile_input(&idol).birthday_display, None);
    }

    #[test]
    fn profile_input_joins_age_height_and_weight_with_the_swift_separator() {
        let mut idol = blank_idol();
        idol.age = Some(17);
        idol.height = Some(160.0);
        idol.weight = Some(45.0);
        // 区切りは全角スペース込みの " ・ " (原本 joined(separator: " ・ "))。
        assert_eq!(
            idol_profile_input(&idol).age_height_weight.as_deref(),
            Some("17歳 ・ 160cm ・ 45kg")
        );

        // 小数を持つ身長は小数のまま (Swift の "\(height)cm")。
        idol.height = Some(160.5);
        assert_eq!(
            idol_profile_input(&idol).age_height_weight.as_deref(),
            Some("17歳 ・ 160.5cm ・ 45kg")
        );

        // 体重は Int(_) 相当のゼロ方向切り捨て。
        idol.weight = Some(45.9);
        assert_eq!(
            idol_profile_input(&idol).age_height_weight.as_deref(),
            Some("17歳 ・ 160.5cm ・ 45kg")
        );

        // 欠けた項目は詰める。全部無ければ行ごと出さない。
        idol.height = None;
        idol.weight = None;
        assert_eq!(idol_profile_input(&idol).age_height_weight.as_deref(), Some("17歳"));
        idol.age = None;
        assert_eq!(idol_profile_input(&idol).age_height_weight, None);
    }

    #[test]
    fn profile_input_needs_all_three_sizes() {
        let mut idol = blank_idol();
        idol.bust = Some(83.0);
        idol.waist = Some(56.0);
        idol.hip = Some(84.0);
        assert_eq!(idol_profile_input(&idol).three_size.as_deref(), Some("B83 W56 H84"));
        // 1 つでも欠けたら行ごと出さない (原本と同じ)。
        idol.waist = None;
        assert_eq!(idol_profile_input(&idol).three_size, None);
    }

    #[test]
    fn profile_input_translates_handedness_but_keeps_unknown_values() {
        let mut idol = blank_idol();
        idol.birth_place = Some("東京都".into());
        idol.handedness = Some("right".into());
        assert_eq!(
            idol_profile_input(&idol).birthplace_handedness.as_deref(),
            Some("東京都 ・ 右")
        );
        idol.handedness = Some("left".into());
        assert_eq!(
            idol_profile_input(&idol).birthplace_handedness.as_deref(),
            Some("東京都 ・ 左")
        );
        // 知らない値はそのまま出す (原本の三項演算子の else 相当)。
        idol.handedness = Some("both".into());
        assert_eq!(
            idol_profile_input(&idol).birthplace_handedness.as_deref(),
            Some("東京都 ・ both")
        );
    }

    #[test]
    fn profile_input_joins_blood_type_and_hobbies() {
        let mut idol = blank_idol();
        idol.blood_type = Some("A".into());
        idol.constellation = Some("牡羊座".into());
        assert_eq!(
            idol_profile_input(&idol).blood_constellation.as_deref(),
            Some("A型 ・ 牡羊座")
        );
        idol.constellation = None;
        assert_eq!(idol_profile_input(&idol).blood_constellation.as_deref(), Some("A型"));

        idol.hobbies = Some("料理".into());
        idol.talents = Some("そろばん".into());
        assert_eq!(idol_profile_input(&idol).hobby_talent.as_deref(), Some("料理 ・ そろばん"));
    }

    #[test]
    fn profile_input_of_a_real_idol_produces_rows() {
        // 実データを 1 件通して、行が組み上がるところまで見る。
        let (snap, _conn) = load();
        let record = idol_list(&snap, None).into_iter().find(|i| i.birthday.is_some()).unwrap();
        let input = idol_profile_input(&record);
        let rows = crate::domain::screen_composition::idol_profile_rows(&input);
        assert!(!rows.is_empty(), "{} のプロフィール行が空", record.id);
        // 誕生日の行だけが「同じ誕生月の一覧へ」を持つ。
        let with_action = rows
            .iter()
            .filter(|r| matches!(r.action, crate::domain::screen_composition::RowAction::FilterByBirthMonth { .. }))
            .count();
        assert!(with_action <= 1, "誕生月へ飛べる行が複数ある");
    }

    fn db_path() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    fn load() -> (Snapshot, Connection) {
        let path = db_path();
        let snap =
            crate::outbound::sqlite_loader::load_snapshot(&path).expect("bundle DB はロードできる");
        let conn = Connection::open_with_flags(
            &path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .expect("bundle DB を開ける");
        (snap, conn)
    }

    /// iOS String.likeEscaped と同じエスケープ (\ → \\、% → \%、_ → \_)。
    fn like_escaped(q: &str) -> String {
        q.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_")
    }

    /// 照合 1: idol_list が元 SQL と全ブランド + 全件 (brand_id なし) で一致する。
    /// Bundle の idols.sort_order はユニークなので id 列の逐語一致で固定できる。
    #[test]
    fn idol_list_matches_sql_for_all_brands() {
        let (snap, conn) = load();
        let mut stmt = conn
            .prepare(
                "SELECT DISTINCT i.id FROM idols i JOIN idol_brands ib ON i.id = ib.idol_id
                 WHERE ib.brand_id = ?1 AND i.is_external = 0 ORDER BY i.sort_order",
            )
            .unwrap();
        let mut nonempty = 0usize;
        for brand in &snap.brands {
            let sql_ids: Vec<String> = stmt
                .query_map([&brand.id], |r| r.get(0))
                .unwrap()
                .map(Result::unwrap)
                .collect();
            let got_ids: Vec<String> =
                idol_list(&snap, Some(&brand.id)).into_iter().map(|r| r.id).collect();
            assert_eq!(sql_ids, got_ids, "brand={}", brand.id);
            if !got_ids.is_empty() {
                nonempty += 1;
            }
        }
        assert!(nonempty >= 5, "アイドルの居るブランドが少なすぎる: {nonempty}");

        let sql_all: Vec<String> = conn
            .prepare("SELECT id FROM idols WHERE is_external = 0 ORDER BY sort_order")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        let got_all: Vec<String> = idol_list(&snap, None).into_iter().map(|r| r.id).collect();
        assert_eq!(sql_all, got_all, "brand なし全件");
        assert!(got_all.len() > 100, "全アイドル数={}", got_all.len());
        // 未知ブランドは 0 行
        assert!(idol_list(&snap, Some("存在しないbrand")).is_empty());
    }

    /// 照合 2: 誕生月・星座・出身地・血液型フィルタが、DB に実在する全値域で元 SQL と一致する。
    #[test]
    fn criterion_filters_match_sql_over_observed_values() {
        let (snap, conn) = load();

        // 誕生月: 1..=12 全部 + 範囲外 (0 / 13) は 0 行
        let mut by_month = conn
            .prepare("SELECT id FROM idols WHERE birthday LIKE ?1 ORDER BY sort_order")
            .unwrap();
        let mut matched_months = 0usize;
        for month in 1u32..=12 {
            let sql_ids: Vec<String> = by_month
                .query_map([format!("--{month:02}-%")], |r| r.get(0))
                .unwrap()
                .map(Result::unwrap)
                .collect();
            let got_ids: Vec<String> =
                idols_by_birth_month(&snap, month).into_iter().map(|r| r.id).collect();
            assert_eq!(sql_ids, got_ids, "month={month}");
            if !got_ids.is_empty() {
                matched_months += 1;
            }
        }
        assert_eq!(matched_months, 12, "全ての月に誕生日アイドルが居るはず");
        assert!(idols_by_birth_month(&snap, 0).is_empty());
        assert!(idols_by_birth_month(&snap, 13).is_empty());

        // 星座・出身地・血液型: DB に出現する distinct 値すべてで照合
        for (column, query_fn) in [
            ("constellation", idols_by_constellation as fn(&Snapshot, &str) -> Vec<IdolRecord>),
            ("birth_place", idols_by_birth_place),
            ("blood_type", idols_by_blood_type),
        ] {
            let values: Vec<String> = conn
                .prepare(&format!(
                    "SELECT DISTINCT {column} FROM idols WHERE {column} IS NOT NULL"
                ))
                .unwrap()
                .query_map([], |r| r.get(0))
                .unwrap()
                .map(Result::unwrap)
                .collect();
            assert!(!values.is_empty(), "{column} の値域が空");
            let mut stmt = conn
                .prepare(&format!("SELECT id FROM idols WHERE {column} = ?1 ORDER BY sort_order"))
                .unwrap();
            for value in &values {
                let sql_ids: Vec<String> =
                    stmt.query_map([value], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
                let got_ids: Vec<String> =
                    query_fn(&snap, value).into_iter().map(|r| r.id).collect();
                assert_eq!(sql_ids, got_ids, "{column}={value}");
                assert!(!got_ids.is_empty(), "{column}={value} は distinct 由来なので 1 件以上");
            }
            // 存在しない値は 0 行
            assert!(query_fn(&snap, "そんな値はない").is_empty());
        }
    }

    /// 照合 3: idol_cast_names / current_voice_actor_name / voice_actor_history が
    /// 元 SQL と一致する。
    #[test]
    fn voice_actor_queries_match_sql() {
        let (snap, conn) = load();

        // fetchIdolCastNames: 昇順で流して後勝ち代入 (Swift 実装の再現)
        let mut sql_names: HashMap<String, String> = HashMap::new();
        conn.prepare(
            "SELECT idol_id, name FROM idol_voice_actors
              WHERE valid_to IS NULL ORDER BY IFNULL(valid_from, '')",
        )
        .unwrap()
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
        .unwrap()
        .map(Result::unwrap)
        .for_each(|(idol_id, name)| {
            sql_names.insert(idol_id, name);
        });
        let got_names = idol_cast_names(&snap);
        assert_eq!(sql_names, got_names, "現任 CV マップ");
        assert!(got_names.len() > 100, "現任 CV の居るアイドル数={}", got_names.len());

        // fetchCurrentVoiceActor + fetchVoiceActorHistory: 全アイドルで照合
        let mut current_stmt = conn
            .prepare(
                "SELECT name FROM idol_voice_actors
                  WHERE idol_id = ?1 AND valid_to IS NULL
                  ORDER BY IFNULL(valid_from, '') DESC LIMIT 1",
            )
            .unwrap();
        let mut history_stmt = conn
            .prepare(
                "SELECT id, idol_id, name, valid_from, valid_to FROM idol_voice_actors
                  WHERE idol_id = ?1 ORDER BY IFNULL(valid_from, '') DESC",
            )
            .unwrap();
        let mut with_history = 0usize;
        for idol in &snap.idols {
            let sql_current: Option<String> =
                current_stmt.query_map([&idol.id], |r| r.get(0)).unwrap().next().map(Result::unwrap);
            assert_eq!(
                sql_current,
                current_voice_actor_name(&snap, &idol.id),
                "idol={} の現任",
                idol.id
            );

            type Row = (String, String, String, Option<String>, Option<String>);
            let sql_rows: Vec<Row> = history_stmt
                .query_map([&idol.id], |r| {
                    Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))
                })
                .unwrap()
                .map(Result::unwrap)
                .collect();
            let got = voice_actor_history(&snap, &idol.id);
            // 並びキー (IFNULL(valid_from,'') DESC) の列一致 + 全行の集合一致で固定
            // (同値 valid_from の並びは SQL では未規定のため)。
            let sql_keys: Vec<String> =
                sql_rows.iter().map(|r| r.3.clone().unwrap_or_default()).collect();
            let got_keys: Vec<String> =
                got.iter().map(|r| r.valid_from.clone().unwrap_or_default()).collect();
            assert_eq!(sql_keys, got_keys, "idol={} の履歴並びキー", idol.id);
            let mut sql_set = sql_rows;
            sql_set.sort();
            let mut got_set: Vec<Row> = got
                .iter()
                .map(|r| {
                    (r.id.clone(), r.idol_id.clone(), r.name.clone(), r.valid_from.clone(),
                     r.valid_to.clone())
                })
                .collect();
            got_set.sort();
            assert_eq!(sql_set, got_set, "idol={} の履歴内容", idol.id);
            if !got.is_empty() {
                with_history += 1;
            }
        }
        assert!(with_history > 100, "CV 履歴のあるアイドル数={with_history}");
    }

    /// 照合 4: idols_by_voice_actor が DB に実在する全 CV 名で元 SQL と一致する。
    #[test]
    fn idols_by_voice_actor_matches_sql_for_all_names() {
        let (snap, conn) = load();
        let names: Vec<String> = conn
            .prepare("SELECT DISTINCT name FROM idol_voice_actors")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        assert!(names.len() > 100, "CV 名の異なり数={}", names.len());
        let mut stmt = conn
            .prepare(
                "SELECT DISTINCT i.id FROM idols i JOIN idol_voice_actors v ON v.idol_id = i.id
                 WHERE v.name = ?1 ORDER BY i.sort_order",
            )
            .unwrap();
        for name in &names {
            let sql_ids: Vec<String> =
                stmt.query_map([name], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
            let got_ids: Vec<String> =
                idols_by_voice_actor(&snap, name).into_iter().map(|r| r.id).collect();
            assert_eq!(sql_ids, got_ids, "va={name}");
            assert!(!got_ids.is_empty(), "va={name} は distinct 由来なので 1 件以上");
        }
        assert!(idols_by_voice_actor(&snap, "存在しない声優").is_empty());
    }

    /// 照合 5: search_idols が元 SQL (LIKE + EXISTS + LIMIT) と一致する。
    /// クエリは DB の実データ由来の断片 + ASCII 大小 + エスケープ対象文字で網羅する。
    #[test]
    fn search_idols_matches_sql() {
        let (snap, conn) = load();
        let mut queries: Vec<String> = vec![
            "美".into(),
            "み".into(),
            "ミ".into(),
            // ASCII の大小無視 (SQLite LIKE の既定) の両面
            "mi".into(),
            "MI".into(),
            "a".into(),
            // 0 件になる文字列・エスケープ対象文字 (リテラル扱いになること)
            "存在しないアイドル名".into(),
            "100%".into(),
            "_".into(),
            "\\".into(),
            // 空文字は '%%' = 全件 (LIMIT だけ効く)
            "".into(),
        ];
        // 実データ断片: 名前・かな・ローマ字・CV 名の先頭 2 文字ずつ
        for i in [0usize, snap.idols.len() / 2] {
            let idol = &snap.idols[i];
            queries.push(idol.name.chars().take(2).collect());
            if let Some(kana) = &idol.name_kana {
                queries.push(kana.chars().take(2).collect());
            }
            if let Some(romaji) = &idol.name_romaji {
                queries.push(romaji.chars().take(2).collect());
            }
        }
        if let Some(va) = snap.idol_voice_actors.first() {
            queries.push(va.name.clone());
            queries.push(va.name.chars().take(2).collect());
        }

        let mut stmt = conn
            .prepare(
                "SELECT id FROM idols
                  WHERE name        LIKE :p ESCAPE '\\'
                     OR name_kana   LIKE :p ESCAPE '\\'
                     OR name_romaji LIKE :p ESCAPE '\\'
                     OR aliases     LIKE :p ESCAPE '\\'
                     OR EXISTS (SELECT 1 FROM idol_voice_actors v
                                 WHERE v.idol_id = idols.id AND v.name LIKE :p ESCAPE '\\')
                  ORDER BY sort_order LIMIT :limit",
            )
            .unwrap();
        let mut nonempty = 0usize;
        for q in &queries {
            for limit in [50u32, 3] {
                let pattern = format!("%{}%", like_escaped(q));
                let sql_ids: Vec<String> = stmt
                    .query_map(
                        rusqlite::named_params! { ":p": pattern, ":limit": limit },
                        |r| r.get(0),
                    )
                    .unwrap()
                    .map(Result::unwrap)
                    .collect();
                let got_ids: Vec<String> =
                    search_idols(&snap, q, limit).into_iter().map(|r| r.id).collect();
                // **等価ではなく上位集合**。判定を `FoldedNeedle` (かなも畳む) に寄せた
                // ので、SQL の LIKE より広く当たる。`limit` で切るぶん、SQL のヒットが
                // 押し出されることはあるが、打ち切りに達していなければ全部残る。
                let sql_set: HashSet<&String> = sql_ids.iter().collect();
                let got_set: HashSet<&String> = got_ids.iter().collect();
                if got_ids.len() < limit as usize {
                    assert!(
                        sql_set.is_subset(&got_set),
                        "SQL のヒットが消えている: query={q:?} limit={limit}\n                         SQL={sql_ids:?}\nours={got_ids:?}"
                    );
                }
                // 並びは元 SQL と同じ (sort_order 昇順) であること。
                let order: Vec<u32> = got_ids
                    .iter()
                    .map(|id| snap.idol_index_by_id[id])
                    .map(|i| snap.idol_order.iter().position(|&x| x == i).unwrap() as u32)
                    .collect();
                assert!(order.windows(2).all(|w| w[0] < w[1]), "query={q:?} の並びが崩れた");
                if !got_ids.is_empty() {
                    nonempty += 1;
                }
            }
        }
        assert!(nonempty >= 10, "ヒットする検索語が少なすぎる: {nonempty}");
        assert!(search_idols(&snap, "", 0).is_empty(), "LIMIT 0 は 0 行");
    }

    /// 照合 6: all_idols_for_picker / idol_records_by_ids / brand_records が元 SQL と一致する。
    #[test]
    fn picker_ids_and_brands_match_sql() {
        let (snap, conn) = load();

        // fetchAllIdolsForPicker: is_external も含む全件 sort_order 順
        let sql_all: Vec<String> = conn
            .prepare("SELECT id FROM idols ORDER BY sort_order")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        let got_all: Vec<String> =
            all_idols_for_picker(&snap).into_iter().map(|r| r.id).collect();
        assert_eq!(sql_all, got_all);
        // ピッカーは外部ゲスト (is_external=1) も含む。現行 Bundle には外部ゲストが
        // 居ないので「一覧以上」で固定する (真の包含関係は id 列の逐語照合が担保済み)。
        assert!(
            got_all.len() >= idol_list(&snap, None).len(),
            "ピッカーは一覧の上位集合のはず"
        );

        // fetchIdols(ids:): IN の内容一致 (順序は SQL 未規定) + 入力順・重複/未知 id の契約
        let sample: Vec<String> = sql_all.iter().rev().take(5).cloned().collect();
        let mut input = sample.clone();
        input.push(sample[0].clone()); // 重複
        input.push("存在しないid".into()); // 未知
        let got = idol_records_by_ids(&snap, &input);
        let got_ids: Vec<String> = got.iter().map(|r| r.id.clone()).collect();
        assert_eq!(got_ids, sample, "入力 id 順・初出のみ・未知 id 読み飛ばし");
        let placeholders = vec!["?"; input.len()].join(",");
        let mut sql_in: Vec<String> = conn
            .prepare(&format!("SELECT id FROM idols WHERE id IN ({placeholders})"))
            .unwrap()
            .query_map(rusqlite::params_from_iter(input.iter()), |r| r.get(0))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        sql_in.sort();
        let mut got_sorted = got_ids.clone();
        got_sorted.sort();
        assert_eq!(sql_in, got_sorted, "IN の内容一致");

        // 全カラム射影の値が SQL と一致する (代表 1 件で全列を突き合わせ)
        let probe = &got[0];
        conn.query_row(
            "SELECT brand_id, name, name_kana, birthday, blood_type, height, weight,
                    birth_place, age, constellation, is_external, aliases
               FROM idols WHERE id = ?1",
            [&probe.id],
            |r| {
                assert_eq!(probe.brand_id, r.get::<_, Option<String>>(0)?);
                assert_eq!(probe.name, r.get::<_, String>(1)?);
                assert_eq!(probe.name_kana, r.get::<_, Option<String>>(2)?);
                assert_eq!(probe.birthday, r.get::<_, Option<String>>(3)?);
                assert_eq!(probe.blood_type, r.get::<_, Option<String>>(4)?);
                assert_eq!(probe.height, r.get::<_, Option<f64>>(5)?);
                assert_eq!(probe.weight, r.get::<_, Option<f64>>(6)?);
                assert_eq!(probe.birth_place, r.get::<_, Option<String>>(7)?);
                assert_eq!(probe.age, r.get::<_, Option<i64>>(8)?);
                assert_eq!(probe.constellation, r.get::<_, Option<String>>(9)?);
                assert_eq!(probe.is_external, r.get::<_, bool>(10)?);
                assert_eq!(probe.aliases, r.get::<_, Option<String>>(11)?);
                Ok(())
            },
        )
        .unwrap();

        // fetchBrands: sort_order はユニークなので逐語一致
        type BrandRow = (String, String, String, Option<String>, i64);
        let sql_brands: Vec<BrandRow> = conn
            .prepare("SELECT id, name, short_name, color, sort_order FROM brands ORDER BY sort_order")
            .unwrap()
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        let got_brands: Vec<BrandRow> = brand_records(&snap)
            .into_iter()
            .map(|b| (b.id, b.name, b.short_name, b.color, b.sort_order))
            .collect();
        assert_eq!(sql_brands, got_brands);
        assert!(got_brands.len() >= 5, "ブランド数={}", got_brands.len());
    }

    /// 照合 7: idol_units が元 SQL と全アイドルで一致する。
    /// ORDER BY u.name の同名 (SQL 未規定) に備え、並びキー列一致 + 内容の集合一致で固定。
    #[test]
    fn idol_units_matches_sql_for_all_idols() {
        let (snap, conn) = load();
        let mut stmt = conn
            .prepare(
                "SELECT u.id, u.name FROM units u JOIN unit_members um ON u.id = um.unit_id
                 WHERE um.idol_id = ?1 ORDER BY u.name",
            )
            .unwrap();
        let mut with_units = 0usize;
        for idol in &snap.idols {
            let sql_rows: Vec<(String, String)> = stmt
                .query_map([&idol.id], |r| Ok((r.get(0)?, r.get(1)?)))
                .unwrap()
                .map(Result::unwrap)
                .collect();
            let got = idol_units(&snap, &idol.id);
            let sql_names: Vec<&String> = sql_rows.iter().map(|r| &r.1).collect();
            let got_names: Vec<&String> = got.iter().map(|r| &r.name).collect();
            assert_eq!(sql_names, got_names, "idol={} の並びキー", idol.id);
            let mut sql_ids: Vec<&String> = sql_rows.iter().map(|r| &r.0).collect();
            let mut got_ids: Vec<&String> = got.iter().map(|r| &r.id).collect();
            sql_ids.sort();
            got_ids.sort();
            assert_eq!(sql_ids, got_ids, "idol={} の内容", idol.id);
            if !got.is_empty() {
                with_units += 1;
            }
        }
        assert!(with_units > 50, "ユニット所属アイドル数={with_units}");
    }

    /// 照合 8: idol_shows が元 SQL (UNION + COALESCE) と全アイドルで一致する。
    /// ORDER BY date DESC の同日 (SQL 未規定) に備え、date 列一致 + 全射影列の集合一致で固定。
    #[test]
    fn idol_shows_matches_sql_for_all_idols() {
        let (snap, conn) = load();
        let mut stmt = conn
            .prepare(
                "SELECT sh.id, e.id, e.name, sh.name, sh.date, sh.venue,
                        COALESCE((SELECT cast_role FROM show_cast
                                   WHERE show_id = sh.id AND idol_id = ?1), 'member')
                 FROM shows sh JOIN events e ON sh.event_id = e.id
                 WHERE sh.id IN (
                     SELECT DISTINCT si.show_id FROM setlist_performers sp
                       JOIN setlist_items si ON si.id = sp.setlist_item_id
                      WHERE sp.idol_id = ?1
                     UNION
                     SELECT show_id FROM show_cast WHERE idol_id = ?1
                 )
                 ORDER BY sh.date DESC",
            )
            .unwrap();
        type Row = (String, String, String, String, String, Option<String>, String);
        let mut with_shows = 0usize;
        for idol in &snap.idols {
            let sql_rows: Vec<Row> = stmt
                .query_map([&idol.id], |r| {
                    Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?,
                        r.get(6)?))
                })
                .unwrap()
                .map(Result::unwrap)
                .collect();
            let got = idol_shows(&snap, &idol.id);
            let sql_dates: Vec<&String> = sql_rows.iter().map(|r| &r.4).collect();
            let got_dates: Vec<&String> = got.iter().map(|r| &r.date).collect();
            assert_eq!(sql_dates, got_dates, "idol={} の date 列", idol.id);
            let mut sql_set = sql_rows;
            sql_set.sort();
            let mut got_set: Vec<Row> = got
                .iter()
                .map(|r| {
                    (r.show_id.clone(), r.event_id.clone(), r.event_name.clone(),
                     r.show_name.clone(), r.date.clone(), r.venue.clone(), r.cast_role.clone())
                })
                .collect();
            got_set.sort();
            assert_eq!(sql_set, got_set, "idol={} の内容", idol.id);
            if !got_set.is_empty() {
                with_shows += 1;
            }
        }
        assert!(with_shows > 100, "出演記録のあるアイドル数={with_shows}");
        assert!(idol_shows(&snap, "存在しないid").is_empty());
    }
}
