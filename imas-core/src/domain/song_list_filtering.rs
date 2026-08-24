//! 楽曲一覧へのマイマーク/タグ絞り込みと、タグ票数ランキング並べ替え。
//!
//! DB にも UI にも依存しない純粋ロジック (id 集合は呼び出し側が UserMarkService 等から
//! 解決済みで渡す) なので単体テスト可能。iOS `applySongMarkFilters` の一次実装。
//! 適用順: 回収 → お気に入り → メモ → 担当 → タグ集合 → (任意で) タグ票数降順。
//!
//! FFI 境界はエンティティ全体を渡さず、判定に要る 3 フィールドの射影
//! ([`SongListFilterEntry`]) を渡して「採用した index の列」を返す形にしている
//! (1 ユーザー操作 = 1 FFI 呼び出し。呼び出し側は自国の配列を index で引き直す)。

use std::collections::{HashMap, HashSet};

/// 楽曲 1 件の射影。絞り込み判定 (`song_id`) と同票時の 50 音安定化
/// (`title_kana` → 無ければ `title`) に必要なフィールドだけを持つ。
#[derive(uniffi::Record, Clone, Debug)]
pub struct SongListFilterEntry {
    pub song_id: String,
    pub title: String,
    pub title_kana: Option<String>,
}

/// 楽曲一覧の「現地回収」軸での絞り込みモード (回収済のみ / 未回収のみ / 制限なし)。
///
/// 名前を iOS の `SongCollectFilter` に揃えていないのは意図的: 生成バインディングが
/// アプリと同一モジュールに入るため、既存 Swift enum (UI/AppStorage が使用) と衝突する。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SongCollectMode {
    All,
    Collected,
    Uncollected,
}

/// 絞り込みに必要な、解決済みの集合とフラグ一式。
///
/// FFI (uniffi::Record) 越しに渡すため集合は `Vec` で受け、内部で `HashSet` 化する。
/// iOS 既存 struct `SongMarkFilterContext` との名前衝突を避けて Criteria と呼ぶ。
#[derive(uniffi::Record, Clone, Debug)]
pub struct SongListFilterCriteria {
    pub collect_mode: SongCollectMode,
    /// 回収済み song_id (`collect_mode` が All の時は未使用)。
    pub collected_ids: Vec<String>,
    pub require_favorite: bool,
    pub favorite_ids: Vec<String>,
    pub require_note: bool,
    pub note_ids: Vec<String>,
    pub require_my_pick: bool,
    /// 担当アイドルが歌唱に関わる song_id 集合。
    pub my_pick_song_ids: Vec<String>,
    /// コミュニティタグ絞り込みの song_id 集合 (None = タグ絞り込みなし)。
    pub tag_song_ids: Option<Vec<String>>,
    /// 単一タグ絞り込み + デフォルト並びの時に「そのタグの票数」降順へ並べ替えるか。
    pub rank_by_tag_votes: bool,
    /// song_id → 票数。載っていない曲は 0 票扱い。
    pub tag_vote_counts: HashMap<String, i64>,
}

/// 絞り込み (+ 任意でタグ票数ランキング) を適用し、採用した要素の index 列を返す。
///
/// index は `entries` の添字 (入力順を保持。ランキング適用時のみ並べ替え)。
/// 同票の並びは 50 音 (title_kana → 無ければ title) で安定化する。文字列比較は
/// コードポイント順 (DB の title_kana は NFC のひらがな想定なので 50 音順に一致)。
pub fn filter_song_list(entries: &[SongListFilterEntry], criteria: &SongListFilterCriteria) -> Vec<u32> {
    let collected: HashSet<&str> = criteria.collected_ids.iter().map(String::as_str).collect();
    let favorites: HashSet<&str> = criteria.favorite_ids.iter().map(String::as_str).collect();
    let notes: HashSet<&str> = criteria.note_ids.iter().map(String::as_str).collect();
    let my_picks: HashSet<&str> = criteria.my_pick_song_ids.iter().map(String::as_str).collect();
    let tag_ids: Option<HashSet<&str>> = criteria
        .tag_song_ids
        .as_ref()
        .map(|ids| ids.iter().map(String::as_str).collect());

    let mut results: Vec<u32> = entries
        .iter()
        .enumerate()
        .filter(|(_, e)| {
            let id = e.song_id.as_str();
            let collect_ok = match criteria.collect_mode {
                SongCollectMode::All => true,
                SongCollectMode::Collected => collected.contains(id),
                SongCollectMode::Uncollected => !collected.contains(id),
            };
            collect_ok
                && (!criteria.require_favorite || favorites.contains(id))
                && (!criteria.require_note || notes.contains(id))
                && (!criteria.require_my_pick || my_picks.contains(id))
                && tag_ids.as_ref().is_none_or(|t| t.contains(id))
        })
        .map(|(i, _)| i as u32)
        .collect();

    // ランキングはタグ絞り込み中のみ (iOS 実装の入れ子構造を踏襲)。
    if tag_ids.is_some() && criteria.rank_by_tag_votes {
        // 安定ソート: 票数もかなも同じなら絞り込み後の順序 (= 入力順) を保つ。
        results.sort_by(|&l, &r| {
            let (le, re) = (&entries[l as usize], &entries[r as usize]);
            let lv = criteria.tag_vote_counts.get(&le.song_id).copied().unwrap_or(0);
            let rv = criteria.tag_vote_counts.get(&re.song_id).copied().unwrap_or(0);
            rv.cmp(&lv).then_with(|| sort_key(le).cmp(sort_key(re)))
        });
    }

    results
}

/// 同票時の並び順キー。50 音 (title_kana) を優先し、無ければ title で代用する。
fn sort_key(entry: &SongListFilterEntry) -> &str {
    entry.title_kana.as_deref().unwrap_or(&entry.title)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str, kana: Option<&str>) -> SongListFilterEntry {
        SongListFilterEntry {
            song_id: id.to_string(),
            title: format!("曲{id}"),
            title_kana: kana.map(str::to_string),
        }
    }

    fn songs() -> Vec<SongListFilterEntry> {
        ["a", "b", "c"].iter().map(|id| entry(id, None)).collect()
    }

    fn criteria(mode: SongCollectMode) -> SongListFilterCriteria {
        SongListFilterCriteria {
            collect_mode: mode,
            collected_ids: vec![],
            require_favorite: false,
            favorite_ids: vec![],
            require_note: false,
            note_ids: vec![],
            require_my_pick: false,
            my_pick_song_ids: vec![],
            tag_song_ids: None,
            rank_by_tag_votes: false,
            tag_vote_counts: HashMap::new(),
        }
    }

    fn vec_of(ids: &[&str]) -> Vec<String> {
        ids.iter().map(|s| s.to_string()).collect()
    }

    /// index 列を song_id 列へ引き直す (iOS テストの `.map(\.id)` 相当)。
    fn picked_ids(entries: &[SongListFilterEntry], indexes: &[u32]) -> Vec<String> {
        indexes.iter().map(|&i| entries[i as usize].song_id.clone()).collect()
    }

    #[test]
    fn all_passes_through() {
        let s = songs();
        let ctx = criteria(SongCollectMode::All);
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["a", "b", "c"]));
    }

    #[test]
    fn collected_keeps_only_collected() {
        let s = songs();
        let mut ctx = criteria(SongCollectMode::Collected);
        ctx.collected_ids = vec_of(&["a", "c"]);
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["a", "c"]));
    }

    #[test]
    fn uncollected_excludes_collected() {
        let s = songs();
        let mut ctx = criteria(SongCollectMode::Uncollected);
        ctx.collected_ids = vec_of(&["a", "c"]);
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["b"]));
    }

    #[test]
    fn favorite_and_note_are_and_conditions() {
        let s = songs();
        let mut ctx = criteria(SongCollectMode::All);
        ctx.require_favorite = true;
        ctx.favorite_ids = vec_of(&["a", "b"]);
        ctx.require_note = true;
        ctx.note_ids = vec_of(&["b", "c"]);
        // AND: fav={a,b} と note={b,c} の積 → b のみ
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["b"]));
    }

    #[test]
    fn my_pick_filter() {
        let s = songs();
        let mut ctx = criteria(SongCollectMode::All);
        ctx.require_my_pick = true;
        ctx.my_pick_song_ids = vec_of(&["c"]);
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["c"]));
    }

    #[test]
    fn tag_filter_restricts_to_tag_set() {
        let s = songs();
        let mut ctx = criteria(SongCollectMode::All);
        ctx.tag_song_ids = Some(vec_of(&["a", "c"]));
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["a", "c"]));
    }

    #[test]
    fn tag_ranking_sorts_by_votes_then_kana() {
        let s = vec![entry("a", Some("あ")), entry("b", Some("い")), entry("c", Some("う"))];
        let mut ctx = criteria(SongCollectMode::All);
        ctx.tag_song_ids = Some(vec_of(&["a", "b", "c"]));
        ctx.rank_by_tag_votes = true;
        ctx.tag_vote_counts = HashMap::from([("a".into(), 1), ("b".into(), 5), ("c".into(), 5)]);
        // 票数降順 (b,c=5 → a=1)、同票は 50 音 (b=い < c=う)。
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["b", "c", "a"]));
    }

    #[test]
    fn tag_ranking_not_applied_when_flag_false() {
        let s = vec![entry("a", None), entry("b", None)];
        let mut ctx = criteria(SongCollectMode::All);
        ctx.tag_song_ids = Some(vec_of(&["a", "b"]));
        ctx.rank_by_tag_votes = false;
        ctx.tag_vote_counts = HashMap::from([("a".into(), 1), ("b".into(), 99)]);
        // 並べ替えなし → 入力順維持。
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["a", "b"]));
    }

    // ---- 以下は Rust 移送で追加した境界ケース (iOS テストには無い) ----

    #[test]
    fn ranking_falls_back_to_title_when_kana_missing() {
        // かな無しは title で比較する (iOS `titleKana ?? title` 相当)。
        // title は "曲a" < "曲b" なので同票なら a が先。
        let s = vec![entry("b", None), entry("a", None)];
        let mut ctx = criteria(SongCollectMode::All);
        ctx.tag_song_ids = Some(vec_of(&["a", "b"]));
        ctx.rank_by_tag_votes = true;
        ctx.tag_vote_counts = HashMap::from([("a".into(), 3), ("b".into(), 3)]);
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["a", "b"]));
    }

    #[test]
    fn ranking_treats_missing_vote_count_as_zero() {
        let s = vec![entry("a", Some("あ")), entry("b", Some("い"))];
        let mut ctx = criteria(SongCollectMode::All);
        ctx.tag_song_ids = Some(vec_of(&["a", "b"]));
        ctx.rank_by_tag_votes = true;
        ctx.tag_vote_counts = HashMap::from([("b".into(), 1)]);
        // a は票数表に無い → 0 票扱いで後ろ。
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["b", "a"]));
    }

    #[test]
    fn empty_input_returns_empty() {
        let ctx = criteria(SongCollectMode::All);
        assert!(filter_song_list(&[], &ctx).is_empty());
    }

    #[test]
    fn filters_compose_before_ranking() {
        // 回収絞り込みで落ちた曲はタグランキングにも現れない (適用順の確認)。
        let s = vec![entry("a", Some("あ")), entry("b", Some("い")), entry("c", Some("う"))];
        let mut ctx = criteria(SongCollectMode::Collected);
        ctx.collected_ids = vec_of(&["a", "b"]);
        ctx.tag_song_ids = Some(vec_of(&["a", "b", "c"]));
        ctx.rank_by_tag_votes = true;
        ctx.tag_vote_counts = HashMap::from([("a".into(), 1), ("b".into(), 5), ("c".into(), 9)]);
        assert_eq!(picked_ids(&s, &filter_song_list(&s, &ctx)), vec_of(&["b", "a"]));
    }

    #[test]
    fn returned_indexes_point_into_input_array() {
        // 呼び出し側は index で自国の配列を引くので、値そのものを確認しておく。
        let s = songs();
        let mut ctx = criteria(SongCollectMode::All);
        ctx.tag_song_ids = Some(vec_of(&["a", "c"]));
        assert_eq!(filter_song_list(&s, &ctx), vec![0, 2]);
    }
}
