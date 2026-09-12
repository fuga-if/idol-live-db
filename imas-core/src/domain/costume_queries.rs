//! 衣装の引き当てと、その表示規則。
//!
//! # 何を答える表か
//!
//! 2 つの問いに答えるために作った:
//! 1. **この公演ではどんな衣装が着られたか** ([`show_costumes`])
//! 2. **この曲のとき何を着ていたか** ([`setlist_item_costumes`])
//!
//! 「曲の衣装」は**その披露で着ていたもの**であって、曲そのものの属性ではない。
//! 同じ曲でも公演が違えば衣装は違う。だから衣装は曲ではなくセトリ行に紐づく。
//!
//! # 記録の粗さをそのまま扱う
//!
//! 衣装は曲単位まで分かることの方が少ない。「この公演で 3 着使われた」までしか
//! 分からない記録を捨てないために、[`CostumeWear::setlist_item`] は `None` を許す。
//! ここはその粗さを畳まず、**どこまで分かっているか**を呼び出し側に見せる
//! ([`ShowCostumeRecord::songs`] が空で [`ShowCostumeRecord::somewhere_in_show`] が立つ)。
//!
//! # 画像は持たない
//!
//! 版権物を配らない方針なので、衣装は名前と出典だけで見分ける。
//! ここが返すのも名前・帰属・出典までで、画像の入る余地は作らない。
//!
//! [`CostumeWear::setlist_item`]: crate::domain::snapshot::CostumeWear::setlist_item

use crate::domain::display_join::join_capped;
use crate::domain::snapshot::{Costume, CostumeWear, Snapshot};

/// 衣装 1 着の見出し。一覧・詳細の双方で使う。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CostumeRecord {
    pub id: String,
    pub name: String,
    pub name_kana: Option<String>,
    pub brand_id: Option<String>,
    /// 誰のための衣装か (ユニット名・アイドル名)。共通衣装なら `None`。
    pub attribution: Option<String>,
    /// 帰属先の id (テーマ色や遷移先に使う)。`attribution` と対で出る。
    pub unit_id: Option<String>,
    pub idol_id: Option<String>,
    pub description: Option<String>,
    pub source_url: Option<String>,
    /// 着用が記録されている公演数 (同じ公演で何度着替えても 1)。
    pub show_count: u32,
    /// 最初に着られた公演日 (`YYYY-MM-DD`)。記録が無ければ `None`。
    pub first_worn_on: Option<String>,
    /// 最後に着られた公演日。
    pub last_worn_on: Option<String>,
}

/// ある公演で着られた衣装 1 着ぶん。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ShowCostumeRecord {
    pub costume: CostumeRecord,
    /// この衣装で歌われた曲 (分かっているものだけ、セトリ順)。
    pub songs: Vec<CostumeSongRecord>,
    /// 曲までは特定できていない着用記録があるか。
    /// `songs` が空でこれが立つときは「使われたのは確かだが、どの曲かは不明」。
    pub somewhere_in_show: bool,
    /// 着ていた人 (人単位で記録されている場合だけ)。共通衣装なら空。
    pub idol_names: Vec<String>,
    /// 「誰が着たか」の 1 行。共通衣装は `None` (わざわざ「全員」とは書かない)。
    pub wearers_label: Option<String>,
}

/// 衣装が出てきた曲 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CostumeSongRecord {
    pub setlist_item_id: String,
    pub song_id: String,
    pub title: String,
    pub position: i64,
}

/// セトリ行に添える衣装。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistCostumeRecord {
    pub costume: CostumeRecord,
    /// その曲でこの衣装を着ていた人。共通衣装なら空。
    pub idol_names: Vec<String>,
    pub wearers_label: Option<String>,
    /// セトリ行に出す 1 行 (`衣装名` / `衣装名（着ていた人）`)。
    ///
    /// **括弧の付け方を決めるのはここ。** 名前と着用者を受け手側で繋ぎ直すと、
    /// iOS / Android / Web で括弧も並びも割れる。
    pub chip_label: String,
}

/// 衣装が着られた公演 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CostumeShowRecord {
    pub show_id: String,
    pub event_id: String,
    pub event_name: String,
    pub show_name: String,
    pub date: String,
    pub venue: Option<String>,
    /// その公演でこの衣装が出た曲 (分かっているものだけ)。
    pub songs: Vec<CostumeSongRecord>,
    pub somewhere_in_show: bool,
}

/// 着用者の列を 1 行に畳むときの上限。セトリ行に添える想定なので短く切る。
const WEARERS_SHOWN: usize = 3;

/// 全衣装を表示順で返す。`brand_id` を渡すとそのブランドの衣装だけ。
///
/// ブランド無指定の衣装 (合同ライブの共通衣装など) は、絞り込むと落ちる。
/// 「どのブランドでもない」を「すべてに出す」にしてしまうと合同衣装が
/// 各ブランドの一覧に紛れるため、あえて落とす側に倒している。
pub fn costume_list(snap: &Snapshot, brand_id: Option<String>) -> Vec<CostumeRecord> {
    snap.costume_order
        .iter()
        .map(|&i| &snap.costumes[i as usize])
        .filter(|c| brand_id.as_deref().is_none_or(|b| c.brand_id.as_deref() == Some(b)))
        .map(|c| costume_record(snap, c))
        .collect()
}

/// 1 着ぶんの見出し。
pub fn costume_record_by_id(snap: &Snapshot, costume_id: &str) -> Option<CostumeRecord> {
    snap.costume(costume_id).map(|c| costume_record(snap, c))
}

/// その公演で着られた衣装。**公演の進行順** (記録した順) に並ぶ。
///
/// 同じ衣装が複数の曲に出ても 1 件に畳む (着替えの回数ではなく「何を着たか」の一覧)。
pub fn show_costumes(snap: &Snapshot, show_id: &str) -> Vec<ShowCostumeRecord> {
    let Some(&si) = snap.show_index_by_id.get(show_id) else { return vec![] };
    let mut out: Vec<ShowCostumeRecord> = Vec::new();
    for &wi in &snap.wears_by_show[si as usize] {
        let wear = &snap.costume_wears[wi as usize];
        let costume = &snap.costumes[wear.costume as usize];
        let entry = fold_by_key(&mut out, &costume.id, |e| &e.costume.id, || ShowCostumeRecord {
            costume: costume_record(snap, costume),
            songs: Vec::new(),
            somewhere_in_show: false,
            idol_names: Vec::new(),
            wearers_label: None,
        });
        match wear.setlist_item {
            Some(item) => entry.songs.push(song_record(snap, item)),
            None => entry.somewhere_in_show = true,
        }
        push_wearer(snap, wear, &mut entry.idol_names);
    }
    for e in &mut out {
        e.songs.sort_by_key(|s| s.position);
        e.wearers_label = wearers_label(&e.idol_names);
    }
    out
}

/// その披露 (セトリ 1 行) で着ていた衣装。
pub fn setlist_item_costumes(snap: &Snapshot, setlist_item_id: &str) -> Vec<SetlistCostumeRecord> {
    let Some(&index) = snap.setlist_item_index_by_id.get(setlist_item_id) else { return vec![] };
    let mut out: Vec<SetlistCostumeRecord> = Vec::new();
    for &wi in &snap.wears_by_setlist_item[index as usize] {
        let wear = &snap.costume_wears[wi as usize];
        let costume = &snap.costumes[wear.costume as usize];
        let entry =
            fold_by_key(&mut out, &costume.id, |e| &e.costume.id, || SetlistCostumeRecord {
                costume: costume_record(snap, costume),
                idol_names: Vec::new(),
                wearers_label: None,
                chip_label: String::new(),
            });
        push_wearer(snap, wear, &mut entry.idol_names);
    }
    for e in &mut out {
        e.wearers_label = wearers_label(&e.idol_names);
        e.chip_label = match &e.wearers_label {
            Some(w) => format!("{}（{w}）", e.costume.name),
            None => e.costume.name.clone(),
        };
    }
    out
}

/// その衣装が着られた公演 (新しい順)。
pub fn costume_shows(snap: &Snapshot, costume_id: &str) -> Vec<CostumeShowRecord> {
    let Some(&ci) = snap.costume_index_by_id.get(costume_id) else { return vec![] };
    let mut out: Vec<CostumeShowRecord> = Vec::new();
    for &wi in &snap.wears_by_costume[ci as usize] {
        let wear = &snap.costume_wears[wi as usize];
        let show = &snap.shows[wear.show as usize];
        let entry = fold_by_key(&mut out, &show.id, |e| &e.show_id, || {
            let event = &snap.events[show.event as usize];
            CostumeShowRecord {
                show_id: show.id.clone(),
                event_id: event.id.clone(),
                event_name: event.name.clone(),
                show_name: show.name.clone(),
                date: show.date.clone(),
                venue: show.venue.clone(),
                songs: Vec::new(),
                somewhere_in_show: false,
            }
        });
        match wear.setlist_item {
            Some(item) => entry.songs.push(song_record(snap, item)),
            None => entry.somewhere_in_show = true,
        }
    }
    for e in &mut out {
        e.songs.sort_by_key(|s| s.position);
    }
    out
}

/// 既にある行を鍵で探し、無ければ作って返す。
///
/// 着用記録は同じ衣装 (同じ公演) を何度も指す — 曲ごと・人ごとに 1 行あるため。
/// 「何を着たか」の一覧に畳むのはどの問いでも同じ手順なので、ここ 1 箇所に持つ。
/// 件数は 1 公演ぶん (せいぜい数着) なので線形探索で足りる。
fn fold_by_key<'a, T>(
    out: &'a mut Vec<T>,
    key: &str,
    key_of: impl Fn(&T) -> &String,
    make: impl FnOnce() -> T,
) -> &'a mut T {
    let at = match out.iter().position(|e| key_of(e) == key) {
        Some(i) => i,
        None => {
            out.push(make());
            out.len() - 1
        }
    };
    &mut out[at]
}

fn costume_record(snap: &Snapshot, costume: &Costume) -> CostumeRecord {
    // 帰属はユニットが先。ユニット衣装をソロ扱いにすると「誰の衣装か」がぶれる。
    let attribution = costume
        .unit_id
        .as_deref()
        .and_then(|id| snap.unit(id))
        .map(|u| u.name.clone())
        .or_else(|| {
            costume.idol_id.as_deref().and_then(|id| snap.idol(id)).map(|i| i.name.clone())
        });
    let wears = snap
        .costume_index_by_id
        .get(&costume.id)
        .map(|&i| snap.wears_by_costume[i as usize].as_slice())
        .unwrap_or_default();
    // wears_by_costume は公演日の降順。端を取れば最初と最後になる。
    let date_of = |wi: u32| snap.shows[snap.costume_wears[wi as usize].show as usize].date.clone();
    let mut show_ids: Vec<&str> = wears
        .iter()
        .map(|&wi| snap.shows[snap.costume_wears[wi as usize].show as usize].id.as_str())
        .collect();
    show_ids.sort_unstable();
    show_ids.dedup();
    CostumeRecord {
        id: costume.id.clone(),
        name: costume.name.clone(),
        name_kana: costume.name_kana.clone(),
        brand_id: costume.brand_id.clone(),
        attribution,
        unit_id: costume.unit_id.clone(),
        idol_id: costume.idol_id.clone(),
        description: costume.description.clone(),
        source_url: costume.source_url.clone(),
        show_count: show_ids.len() as u32,
        first_worn_on: wears.last().copied().map(date_of),
        last_worn_on: wears.first().copied().map(date_of),
    }
}

fn song_record(snap: &Snapshot, setlist_item: u32) -> CostumeSongRecord {
    let item = &snap.setlist_items[setlist_item as usize];
    let song = &snap.songs[item.song as usize];
    CostumeSongRecord {
        setlist_item_id: item.id.clone(),
        song_id: song.id.clone(),
        title: song.title.clone(),
        position: item.position,
    }
}

/// 着用者を積む。`idol` が `None` の行は「その場の全員」なので誰も積まない。
fn push_wearer(snap: &Snapshot, wear: &CostumeWear, names: &mut Vec<String>) {
    let Some(idol) = wear.idol else { return };
    let name = &snap.idols[idol as usize].name;
    if !names.iter().any(|n| n == name) {
        names.push(name.clone());
    }
}

/// 着用者の 1 行。共通衣装 (人の記録が無い) は `None` — 「全員」と書くより
/// 行ごと出さない方が、衣装名だけが並んで読みやすい。
fn wearers_label(names: &[String]) -> Option<String> {
    let refs: Vec<&str> = names.iter().map(String::as_str).collect();
    join_capped(&refs, "・", WEARERS_SHOWN, "名")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::snapshot::{Costume, CostumeWear};
    use crate::domain::snapshot_build::{build, RawTables};
    use crate::domain::snapshot::{Event, Idol, SetlistItem, Show, Song};

    fn snapshot(costumes: Vec<Costume>, wears: Vec<CostumeWear>) -> Snapshot {
        let raw = RawTables {
            songs: vec![song("s1", "READY!!"), song("s2", "CHANGE!!!!")],
            idols: vec![idol("i1", "天海春香"), idol("i2", "如月千早")],
            events: vec![event("e1", "10th")],
            units: vec![],
            brands: vec![],
            creators: vec![],
            venues: vec![],
            staff: vec![],
            anniversaries: vec![],
            meta: Default::default(),
            shows: vec![show("sh1", "2024-01-01"), show("sh2", "2025-01-01")],
            setlist_items: vec![
                item("it1", 0, 0, 1),
                item("it2", 0, 1, 2),
                item("it3", 1, 0, 1),
            ],
            venue_names: vec![],
            venue_halls: vec![],
            idol_voice_actors: vec![],
            event_releases: vec![],
            costumes,
            costume_wears: wears,
            song_artists: vec![],
            setlist_performers: vec![],
            show_cast: vec![],
            unit_members: vec![],
            idol_brands: vec![],
        };
        build(raw)
    }

    fn song(id: &str, title: &str) -> Song {
        Song {
            id: id.into(),
            title: title.into(),
            title_kana: None,
            brand_id: None,
            song_type: None,
            release_date: None,
            duration_sec: None,
            composer: None,
            lyricist: None,
            arranger: None,
            cd_series: None,
            cd_title: None,
            artwork_url: None,
            preview_url: None,
            apple_music_id: None,
            apple_music_album_id: None,
            isrc: None,
            lyrics_url: None,
            parent_song_id: None,
            singer_label: None,
            unit_name: None,
            unit_id: None,
            series_group: None,
            jasrac_code: None,
            joint_brand_ids: None,
            is_collab: false,
        }
    }

    fn idol(id: &str, name: &str) -> Idol {
        Idol {
            id: id.into(),
            brand_id: None,
            name: name.into(),
            name_kana: None,
            name_romaji: None,
            color: None,
            sort_order: Some(0),
            birthday: None,
            blood_type: None,
            height: None,
            weight: None,
            birth_place: None,
            age: None,
            bust: None,
            waist: None,
            hip: None,
            constellation: None,
            hobbies: None,
            talents: None,
            description: None,
            gender: None,
            handedness: None,
            family_name: None,
            given_name: None,
            nickname: None,
            debut_date: None,
            attribute: None,
            is_external: false,
            aliases: None,
        }
    }

    fn event(id: &str, name: &str) -> Event {
        Event {
            id: id.into(),
            brand_id: None,
            name: name.into(),
            name_kana: None,
            event_type: "live".into(),
            is_streaming: false,
            is_solo: true,
            kind: "live".into(),
            ticket_open_date: None,
            ticket_deadline: None,
            ticket_lottery_date: None,
            ticket_url: None,
            joint_brand_ids: None,
            has_streaming: None,
            has_live_viewing: None,
        }
    }

    fn show(id: &str, date: &str) -> Show {
        Show {
            id: id.into(),
            event: 0,
            name: "DAY1".into(),
            date: date.into(),
            venue: None,
            venue_city: None,
            start_time: None,
            sort_order: 0,
            performer_type: None,
            venue_id: None,
            hall: None,
            stream_platform: None,
            has_streaming: None,
            has_live_viewing: None,
        }
    }

    fn item(id: &str, show: u32, song: u32, position: i64) -> SetlistItem {
        SetlistItem {
            id: id.into(),
            show,
            song,
            position,
            section: None,
            notes: None,
            unit_name: None,
        }
    }

    fn costume(id: &str, name: &str) -> Costume {
        Costume {
            id: id.into(),
            brand_id: None,
            name: name.into(),
            name_kana: None,
            unit_id: None,
            idol_id: None,
            description: None,
            source_url: None,
            sort_order: 0,
        }
    }

    fn wear(id: &str, costume: u32, show: u32, item: Option<u32>, idol: Option<u32>, order: i64) -> CostumeWear {
        CostumeWear { id: id.into(), costume, show, setlist_item: item, idol, sort_order: order }
    }

    /// 同じ衣装が複数の曲に出ても、公演の一覧では 1 件になること。
    #[test]
    fn one_costume_worn_for_two_songs_is_listed_once() {
        let snap = snapshot(
            vec![costume("c1", "10th 共通")],
            vec![wear("w1", 0, 0, Some(0), None, 0), wear("w2", 0, 0, Some(1), None, 1)],
        );
        let got = show_costumes(&snap, "sh1");
        assert_eq!(got.len(), 1);
        assert_eq!(
            got[0].songs.iter().map(|s| s.title.as_str()).collect::<Vec<_>>(),
            ["READY!!", "CHANGE!!!!"]
        );
        assert!(!got[0].somewhere_in_show);
    }

    /// 曲が分からない記録は捨てず、「公演のどこか」として残ること。
    #[test]
    fn a_wear_without_a_song_is_kept_as_somewhere_in_the_show() {
        let snap =
            snapshot(vec![costume("c1", "アンコール T")], vec![wear("w1", 0, 0, None, None, 0)]);
        let got = show_costumes(&snap, "sh1");
        assert_eq!(got.len(), 1);
        assert!(got[0].songs.is_empty());
        assert!(got[0].somewhere_in_show);
    }

    /// 同じ曲でも人によって衣装が違う記録ができること。
    #[test]
    fn different_idols_can_wear_different_costumes_in_one_song() {
        let snap = snapshot(
            vec![costume("c1", "春香ソロ"), costume("c2", "千早ソロ")],
            vec![wear("w1", 0, 0, Some(0), Some(0), 0), wear("w2", 1, 0, Some(0), Some(1), 1)],
        );
        let got = setlist_item_costumes(&snap, "it1");
        assert_eq!(got.len(), 2);
        assert_eq!(got[0].wearers_label.as_deref(), Some("天海春香"));
        assert_eq!(got[1].wearers_label.as_deref(), Some("如月千早"));
        // 括弧の付け方はここで決まる (出面で名前と着用者を繋ぎ直させない)。
        assert_eq!(got[0].chip_label, "春香ソロ（天海春香）");
    }

    /// 共通衣装は「全員」と書かず、着用者の行を出さないこと。
    #[test]
    fn a_shared_costume_has_no_wearers_line() {
        let snap = snapshot(vec![costume("c1", "共通")], vec![wear("w1", 0, 0, Some(0), None, 0)]);
        let got = setlist_item_costumes(&snap, "it1");
        assert_eq!(got[0].wearers_label, None);
        assert_eq!(got[0].chip_label, "共通", "着用者が無ければ括弧も付かない");
    }

    /// 着用公演数は公演単位で数えること (1 公演で 2 曲着ても 1)。
    #[test]
    fn show_count_counts_shows_not_wears() {
        let snap = snapshot(
            vec![costume("c1", "共通")],
            vec![
                wear("w1", 0, 0, Some(0), None, 0),
                wear("w2", 0, 0, Some(1), None, 1),
                wear("w3", 0, 1, Some(2), None, 0),
            ],
        );
        let rec = costume_record_by_id(&snap, "c1").unwrap();
        assert_eq!(rec.show_count, 2);
        assert_eq!(rec.first_worn_on.as_deref(), Some("2024-01-01"));
        assert_eq!(rec.last_worn_on.as_deref(), Some("2025-01-01"));
    }

    /// 着用公演は新しい順に並ぶこと。
    #[test]
    fn shows_of_a_costume_are_newest_first() {
        let snap = snapshot(
            vec![costume("c1", "共通")],
            vec![wear("w1", 0, 0, Some(0), None, 0), wear("w2", 0, 1, Some(2), None, 0)],
        );
        let got = costume_shows(&snap, "c1");
        assert_eq!(got.iter().map(|s| s.date.as_str()).collect::<Vec<_>>(), ["2025-01-01", "2024-01-01"]);
    }

    /// 未知の id では空を返すこと (落とさない)。
    #[test]
    fn unknown_ids_return_empty() {
        let snap = snapshot(vec![], vec![]);
        assert!(show_costumes(&snap, "nope").is_empty());
        assert!(setlist_item_costumes(&snap, "nope").is_empty());
        assert!(costume_shows(&snap, "nope").is_empty());
        assert!(costume_record_by_id(&snap, "nope").is_none());
    }
}
