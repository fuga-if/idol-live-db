//! イベント一覧の絞り込み (ブランド / kind / 名前検索 / 参加状態 / お気に入り / メモ / 会場)。
//!
//! 原本: ImasLiveDB/Domain/UseCases/EventListFiltering.swift (`filterEvents`)。
//! 時系列分割・年度グルーピングはここではやらない (それは `event_grouping`)。
//!
//! DB にも UI にも依存しない: マーク集合 (参加済み / お気に入り / メモ) や
//! 「会場で公演があったイベント id」は、呼び出し側が UserMarkService / DB から
//! **解決済みの id 集合**として渡す。show 単位でしか持てない情報 (参加記録・会場) を
//! event 単位の絞り込みへ橋渡しする逆引きは呼び出し側の責務のまま変えていない。
//!
//! FFI 境界はエンティティ全体を渡さず「絞り込みに必要な射影 → index 列」の 1 呼び出し
//! (呼び出し側が自国の配列を index で引く)。条件の適用順は原本と同じだが、
//! すべて AND 条件なので結果集合は順序に依らない (index は入力順のまま安定)。

use std::collections::HashSet;

use crate::domain::text_search_index::FoldedNeedle;

/// イベント 1 件ぶんの、絞り込み判定に必要なフィールドだけの射影。
#[derive(uniffi::Record, Clone, Debug)]
pub struct EventFilterItem {
    pub id: String,
    /// primary の brand_id (None = ブランド未設定)。
    pub brand_id: Option<String>,
    /// 合同ライブの追加ブランド id をカンマ区切りで持つ生文字列 (例 "ml,cg")。
    /// None / 空 = 単一ブランド。分解は iOS `Event.jointBrandIdList` と同じく
    /// こちら側でやる (trim して空要素は捨てる)。
    pub joint_brand_ids: Option<String>,
    pub name: String,
    /// イベント種別の生文字列 ("live" / "festival" / "release_event" / "radio" / "stream")。
    /// 未知値は "live" として扱う (iOS `Event.eventKind` の `?? .live` フォールバック)。
    pub kind: String,
    /// `events.event_type` の生文字列 (`anniversary` / `orchestra` / `external_event` /
    /// `birthday` / `release_event` / `broadcast` / `live`、未分類は空)。
    /// 語彙と判定規則は docs/DATA_PIPELINE.md 「events の種別 (event_type)」。
    pub event_type: String,
}

/// イベント一覧の絞り込みに必要な、解決済みの条件・集合。
/// (iOS 側の `EventFilterContext` に対応。集合は FFI 都合で Vec で受け、内部で Set 化する)
#[derive(uniffi::Record, Clone, Debug)]
pub struct EventFilterCriteria {
    /// 選択ブランド (空 = 全ブランド)。primary / joint のいずれか該当で残す。
    pub selected_brand_ids: Vec<String>,
    /// 除外する kind (生文字列)。空 = 除外なし。
    pub excluded_kinds: Vec<String>,
    /// 名前部分一致の検索語 (空 = 検索なし)。大文字小文字と、
    /// 正準等価 (NFC/NFD) の表現差を無視して比較する。
    pub search_text: String,
    /// "all" / "attended" / "not_attended"。未知値は "all" と同じ (絞り込みなし)。
    pub attendance_filter: String,
    /// 参加済みイベント id 集合 (show 単位の参加記録から呼び出し側が逆引き済み)。
    pub attended_event_ids: Vec<String>,
    pub require_favorite: bool,
    pub favorite_ids: Vec<String>,
    pub require_note: bool,
    pub note_ids: Vec<String>,
    /// 会場名で絞り込む (空 = 絞り込みなし)。表示用に保持するだけで、
    /// 実際の判定は解決済みの `venue_event_ids` で行う。
    /// 「未選択 (venue 空)」と「その会場に該当なし (集合が空)」を区別するために
    /// 集合の空判定ではなくこの文字列で on/off を決める。
    pub venue: String,
    /// `venue` で公演があったイベントの id 集合 (呼び出し側が DB から解決して渡す)。
    /// 会場は show 単位・絞り込み対象は event 単位なので、ここで橋渡しする。
    pub venue_event_ids: Vec<String>,
    /// 「配信のみのイベントを隠す」= 公演として開かれていないものを落とす。
    /// 判定は [`is_broadcast_only`] (= `event_type == "broadcast"`)。
    pub exclude_broadcast: bool,
}

/// 「配信のみ」= 公演として開かれていないイベントか。
///
/// **`events.is_streaming` で判定しない。** あの列は初期移行の `Scripts/rebuild_db.py` が
/// イベント名の正規表現で機械生成した値がそのまま残っているだけで、誰も 1 件ずつ見ていない。
/// しかも意味が「配信があった」寄りで、幕張メッセや東京ガーデンシアターの現地公演
/// (CG 10th ANNIVERSARY / SHINY COLORS 3rdLIVE TOUR 等) を含む。これで一覧を隠すと
/// アリーナ公演が消える。`event_type='broadcast'` (番組・配信そのもの = 公演として
/// 開かれていない) が「配信のみ」を正確に持つので、そちらで判定する。
/// 経緯は docs/DATA_PIPELINE.md 「配信の軸 (stream_platform と is_streaming)」。
///
/// 未分類 (空文字) は broadcast ではない側に倒す。分類が行き渡っていないイベントを
/// 隠す向きに倒すと、データの欠けが「一覧から消える」という形で出るため。
pub fn is_broadcast_only(event_type: &str) -> bool {
    event_type == "broadcast"
}

/// 絞り込みを適用し、残すイベントの index 列 (入力順) を返す純粋ロジック。
pub fn filter_event_indices(items: &[EventFilterItem], c: &EventFilterCriteria) -> Vec<u32> {
    // Vec のままだと条件ごとに O(n) 探索になるので、判定前に一度だけ Set 化する。
    let selected: HashSet<&str> = c.selected_brand_ids.iter().map(String::as_str).collect();
    let excluded: HashSet<&str> = c.excluded_kinds.iter().map(String::as_str).collect();
    let attended: HashSet<&str> = c.attended_event_ids.iter().map(String::as_str).collect();
    let favorites: HashSet<&str> = c.favorite_ids.iter().map(String::as_str).collect();
    let notes: HashSet<&str> = c.note_ids.iter().map(String::as_str).collect();
    let venue_ids: HashSet<&str> = c.venue_event_ids.iter().map(String::as_str).collect();
    let search_needle = FoldedNeedle::new(&c.search_text);

    items
        .iter()
        .enumerate()
        .filter(|(_, item)| {
            let id = item.id.as_str();
            if !selected.is_empty() && !matches_brand_filter(item, &selected) {
                return false;
            }
            if !excluded.is_empty() && excluded.contains(normalize_kind(&item.kind)) {
                return false;
            }
            if !search_needle.is_empty() && !search_needle.matches(&item.name) {
                return false;
            }
            match c.attendance_filter.as_str() {
                "attended" if !attended.contains(id) => return false,
                "not_attended" if attended.contains(id) => return false,
                _ => {}
            }
            if c.require_favorite && !favorites.contains(id) {
                return false;
            }
            if c.require_note && !notes.contains(id) {
                return false;
            }
            // venue の on/off は名前 (venue) で決める。集合の空判定にすると
            // 「未選択」と「該当なし」を取り違えて全件消してしまう。
            if !c.venue.is_empty() && !venue_ids.contains(id) {
                return false;
            }
            if c.exclude_broadcast && is_broadcast_only(&item.event_type) {
                return false;
            }
            true
        })
        .map(|(i, _)| i as u32)
        .collect()
}

/// primary brand_id または joint_brand_ids のいずれかが selected に含まれるか。
/// (iOS `Event.matchesBrandFilter` の移植。selected が空のときは常に true = フィルタ無し)
fn matches_brand_filter(item: &EventFilterItem, selected: &HashSet<&str>) -> bool {
    if selected.is_empty() {
        return true;
    }
    if let Some(primary) = item.brand_id.as_deref() {
        if selected.contains(primary) {
            return true;
        }
    }
    // joint_brand_ids はカンマ区切りの生文字列 (例 "ml, cg")。割り方は 1 つ
    // (trim して空要素を捨てる。末尾カンマ等の耐性)。
    crate::domain::snapshot::split_csv(item.joint_brand_ids.as_deref())
        .any(|s| selected.contains(s))
}

/// kind の生文字列を語彙の値へ寄せる。**知らない値は `other` (その他)** (Q-08l)。
/// 以前は `live` 扱いで、「ライブを除外」すると知らない種別も一緒に消えていた。
/// 寄せ方は語彙 ([`crate::domain::vocabulary::event_kind`]) が正本。
fn normalize_kind(raw: &str) -> &'static str {
    crate::domain::vocabulary::event_kind(raw).value
}

#[cfg(test)]
mod tests {
    use super::*;

    /// id だけ違うイベント射影 (名前は "E<id>"、kind は live、ブランドなし)。
    /// iOS テストの `makeEW` に対応。
    fn item(id: &str) -> EventFilterItem {
        EventFilterItem {
            id: id.to_string(),
            brand_id: None,
            joint_brand_ids: None,
            name: format!("E{id}"),
            kind: "live".to_string(),
            event_type: "live".to_string(),
        }
    }

    fn item_brand(id: &str, brand: &str) -> EventFilterItem {
        EventFilterItem { brand_id: Some(brand.to_string()), ..item(id) }
    }

    fn item_named(id: &str, name: &str) -> EventFilterItem {
        EventFilterItem { name: name.to_string(), ..item(id) }
    }

    /// 何も絞り込まない条件 (iOS の `EventFilterContext()` 既定値に対応)。
    fn criteria() -> EventFilterCriteria {
        EventFilterCriteria {
            selected_brand_ids: vec![],
            excluded_kinds: vec![],
            search_text: String::new(),
            attendance_filter: "all".to_string(),
            attended_event_ids: vec![],
            require_favorite: false,
            favorite_ids: vec![],
            require_note: false,
            note_ids: vec![],
            venue: String::new(),
            venue_event_ids: vec![],
            exclude_broadcast: false,
        }
    }

    fn vs(strs: &[&str]) -> Vec<String> {
        strs.iter().map(|s| s.to_string()).collect()
    }

    /// index 列を id 列へ引き直す (呼び出し側がやることのテスト内再現)。
    fn filtered_ids(items: &[EventFilterItem], c: &EventFilterCriteria) -> Vec<String> {
        filter_event_indices(items, c)
            .into_iter()
            .map(|i| items[i as usize].id.clone())
            .collect()
    }

    /// iOS testEmptyContextPassesThrough: 既定条件は全件素通し (入力順のまま)。
    #[test]
    fn empty_criteria_passes_through() {
        let items = [item("a"), item("b")];
        assert_eq!(filtered_ids(&items, &criteria()), vs(&["a", "b"]));
        // 返るのは id ではなく index (入力順)。
        assert_eq!(filter_event_indices(&items, &criteria()), vec![0, 1]);
    }

    // ---- 会場 ----

    /// iOS testEmptyVenueDoesNotFilter: 会場名が空なら、解決済み集合が空でも
    /// 絞り込みは効かない (「未選択」と「その会場に該当なし」を取り違えて全件消さないこと)。
    #[test]
    fn empty_venue_does_not_filter() {
        let items = [item("a"), item("b")];
        let mut c = criteria();
        c.venue = String::new();
        c.venue_event_ids = vec![];
        assert_eq!(filtered_ids(&items, &c), vs(&["a", "b"]));
    }

    /// iOS testVenueCombinesWithBrandAsAnd: 会場とブランドは AND。
    #[test]
    fn venue_combines_with_brand_as_and() {
        let items = [item_brand("a", "cg"), item_brand("b", "ml"), item_brand("c", "cg")];
        let mut c = criteria();
        c.selected_brand_ids = vs(&["cg"]);
        c.venue = "東京・日本武道館".to_string();
        c.venue_event_ids = vs(&["b", "c"]);
        assert_eq!(filtered_ids(&items, &c), vs(&["c"]));
    }

    // ---- ブランド ----

    /// 合同ライブ: joint_brand_ids のいずれか該当で残す (ハッチポッチ等の合同公演対応)。
    /// カンマ区切りの空白 trim・空要素スキップも iOS `jointBrandIdList` と同じ。
    #[test]
    fn brand_filter_matches_joint_brands() {
        let mut joint = item_brand("a", "cg");
        joint.joint_brand_ids = Some(" ml , sc ,".to_string());
        let items = [joint, item_brand("b", "as")];
        let mut c = criteria();
        c.selected_brand_ids = vs(&["ml"]);
        assert_eq!(filtered_ids(&items, &c), vs(&["a"]));
    }

    /// brand_id が None のイベントは、ブランド選択中は落ちる (joint も無ければ該当しようがない)。
    #[test]
    fn brand_filter_drops_events_without_brand() {
        let items = [item("a"), item_brand("b", "cg")];
        let mut c = criteria();
        c.selected_brand_ids = vs(&["cg"]);
        assert_eq!(filtered_ids(&items, &c), vs(&["b"]));
    }

    // ---- kind ----

    /// 未知の kind は `other` (その他) として扱う (Q-08l): 「ライブを除外」しても消えず、
    /// 「その他を除外」で落ちる。
    #[test]
    fn unknown_kind_is_other() {
        let mut unknown = item("a");
        unknown.kind = "hologram_live".to_string();
        let mut festival = item("b");
        festival.kind = "festival".to_string();
        let items = [unknown, festival];
        let mut c = criteria();
        c.excluded_kinds = vs(&["live"]);
        assert_eq!(filtered_ids(&items, &c), vs(&["a", "b"]));
        c.excluded_kinds = vs(&["other"]);
        assert_eq!(filtered_ids(&items, &c), vs(&["b"]));
    }

    // ---- 検索 ----

    /// 回帰: 正準等価 (NFC/NFD) の表現差を同一視する (Swift `String.contains` の挙動)。
    /// 指摘の机上実行ケース: NFC "パーティー" / NFD "パーティー" の 2 件に対し、
    /// NFD の検索語 "パ" でも NFC の検索語 "パ" でも両方ヒットすること
    /// (修正前は NFD 検索語 → NFD 名のみ、NFC 検索語 → NFC 名のみだった)。
    #[test]
    fn search_text_matches_across_canonical_equivalence() {
        let items = [
            item_named("a", "パーティー"),         // NFC (U+30D1)
            item_named("b", "ハ\u{309A}ーティー"), // NFD (U+30CF + 半濁点 U+309A)
        ];
        let mut c = criteria();
        c.search_text = "ハ\u{309A}".to_string(); // NFD の「パ」
        assert_eq!(filtered_ids(&items, &c), vs(&["a", "b"]));
        c.search_text = "パ".to_string(); // NFC の「パ」
        assert_eq!(filtered_ids(&items, &c), vs(&["a", "b"]));
    }

    /// 正準等価と大文字小文字無視の組み合わせ: NFD の大文字検索語 "CAFE"+結合アクセント
    /// が NFC 小文字 "é" を含む名前にヒットする。一方、素の "e" は "é" にヒットしない
    /// (Swift の書記素単位の照合と同じ非マッチが NFC 合成で保たれる)。
    #[test]
    fn search_text_canonical_equivalence_with_case_folding() {
        let items = [item_named("a", "Café"), item_named("b", "MILLION")];
        let mut c = criteria();
        c.search_text = "CAFE\u{301}".to_string(); // NFD の "CAFÉ"
        assert_eq!(filtered_ids(&items, &c), vs(&["a"]));
        c.search_text = "e".to_string(); // "é" とは別文字扱い (Swift と同じ)
        assert!(filter_event_indices(&items, &c).is_empty());
    }

    // ---- 参加状態 ----

    /// iOS testNotAttendedFilter。
    #[test]
    fn not_attended_filter() {
        let items = [item("a"), item("b")];
        let mut c = criteria();
        c.attendance_filter = "not_attended".to_string();
        c.attended_event_ids = vs(&["b"]);
        assert_eq!(filtered_ids(&items, &c), vs(&["a"]));
    }

    /// 未知の attendance_filter 値は "all" と同じ (iOS の `default: break` を引き継ぐ)。
    #[test]
    fn unknown_attendance_filter_means_all() {
        let items = [item("a"), item("b")];
        let mut c = criteria();
        c.attendance_filter = "maybe".to_string();
        c.attended_event_ids = vs(&["b"]);
        assert_eq!(filtered_ids(&items, &c), vs(&["a", "b"]));
    }

    // ---- お気に入り / メモ ----

    /// iOS testFavoriteAndNoteAreAndConditions: 両方要求したら積集合。
    #[test]
    fn favorite_and_note_are_and_conditions() {
        let items = [item("a"), item("b"), item("c")];
        let mut c = criteria();
        c.require_favorite = true;
        c.favorite_ids = vs(&["a", "b"]);
        c.require_note = true;
        c.note_ids = vs(&["b", "c"]);
        assert_eq!(filtered_ids(&items, &c), vs(&["b"]));
    }

    /// require フラグが false なら、集合に値が入っていても絞り込まない
    /// (フラグと集合は独立: 集合はフラグが立ったときだけ意味を持つ)。
    #[test]
    fn require_flags_off_ignore_sets() {
        let items = [item("a"), item("b")];
        let mut c = criteria();
        c.favorite_ids = vs(&["a"]);
        c.note_ids = vs(&["b"]);
        assert_eq!(filtered_ids(&items, &c), vs(&["a", "b"]));
    }

    fn item_type(id: &str, event_type: &str) -> EventFilterItem {
        EventFilterItem { event_type: event_type.to_string(), ..item(id) }
    }

    /// 「配信のみ」は broadcast だけ。番組・配信そのもの以外は残る。
    #[test]
    fn broadcast_only_is_event_type_broadcast() {
        assert!(is_broadcast_only("broadcast"));
        for other in ["live", "anniversary", "orchestra", "external_event", "birthday",
                      "release_event", ""] {
            assert!(!is_broadcast_only(other), "{other} を配信のみに数えてはいけない");
        }
    }

    /// exclude_broadcast は broadcast だけを落とす。
    #[test]
    fn exclude_broadcast_drops_only_broadcast() {
        let items = [
            item_type("bc", "broadcast"),
            item_type("anniv", "anniversary"),
            item_type("orch", "orchestra"),
            item_type("unclassified", ""),
        ];
        let mut c = criteria();
        c.exclude_broadcast = true;
        assert_eq!(filtered_ids(&items, &c), vs(&["anniv", "orch", "unclassified"]));
    }

    /// 現地公演が「配信を除く」で消えないことの番人。
    ///
    /// 旧実装は `events.is_streaming` を読んでいて、この 3 件はいずれも
    /// `shows.stream_platform` 由来で is_streaming=1 が入る対象だった
    /// (幕張メッセ / 東京ガーデンシアターの現地公演)。event_type で判定する限り
    /// 隠れない、というのがこの移行の肝。
    #[test]
    fn exclude_broadcast_keeps_on_site_arena_shows() {
        let items = [
            item_type("cg10th", "anniversary"),   // CG 10th ANNIVERSARY (幕張メッセ)
            item_type("sc3rd_tokyo", "live"),     // SHINY COLORS 3rdLIVE TOUR / TOKYO
            item_type("sc_music_dawn", "live"),   // SHINY COLORS MUSIC DAWN (幕張メッセ)
            item_type("first_take", "broadcast"), // THE FIRST TAKE (公演ではない)
        ];
        let mut c = criteria();
        c.exclude_broadcast = true;
        assert_eq!(filtered_ids(&items, &c), vs(&["cg10th", "sc3rd_tokyo", "sc_music_dawn"]));
    }
}
