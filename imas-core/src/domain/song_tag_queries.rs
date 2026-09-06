//! タグごとの曲一覧の規則 (Web 出面の `/tags/`)。
//!
//! 並びの判断はここ 1 箇所: タグは付いている曲の多い順 (同数は名前順 → id 順)、
//! 各タグの曲は付けた人の多い順 (同数はよみ順)。スナップショットに無い曲 (消えた曲) は
//! 数えない — その分だけのタグに空の一覧を作らない。

use super::community::{CommunitySnapshot, TagRow};
use super::kana_row::kana_sort_key;
use super::snapshot::Snapshot;
use std::cmp::Reverse;

/// タグ 1 つと、付いている曲。
pub struct TagRanking<'a> {
    pub tag: &'a TagRow,
    /// (曲の添字, 付けた人の数)。付けた人の多い順、同数はよみ順。空にはならない。
    pub songs: Vec<(u32, i64)>,
}

/// 曲の付いたタグを、曲の多い順に。
pub fn song_tag_ranking<'a>(community: &'a CommunitySnapshot, snap: &Snapshot) -> Vec<TagRanking<'a>> {
    let mut out: Vec<TagRanking<'a>> = community
        .song_tag_vocab
        .values()
        .filter_map(|tag| {
            let mut songs: Vec<(u32, i64)> = community
                .songs_with_song_tag(&tag.id)
                .iter()
                .filter_map(|row| Some((*snap.song_index_by_id.get(&row.entity_id)?, row.vote_count)))
                .collect();
            // よみの畳み込みは行ごとに 1 回 (比較のたびに畳まない)。
            songs.sort_by_cached_key(|&(i, votes)| (Reverse(votes), kana_sort_key(snap.songs[i as usize].reading())));
            (!songs.is_empty()).then_some(TagRanking { tag, songs })
        })
        .collect();
    out.sort_by(|a, b| {
        b.songs
            .len()
            .cmp(&a.songs.len())
            .then_with(|| a.tag.name.cmp(&b.tag.name))
            .then_with(|| a.tag.id.cmp(&b.tag.id))
    });
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::community::{CommunityRows, TaggedRow};
    use crate::outbound::sqlite_loader::load_snapshot;
    use std::sync::OnceLock;

    fn snap() -> &'static Snapshot {
        static SNAP: OnceLock<Snapshot> = OnceLock::new();
        SNAP.get_or_init(|| {
            load_snapshot(&format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR")))
                .expect("bundle DB はロードできる")
        })
    }

    fn tag(id: &str, name: &str) -> TagRow {
        TagRow {
            id: id.to_string(),
            name: name.to_string(),
            description: None,
            category: None,
            color: None,
            is_official: false,
        }
    }
    fn tagged(song: &str, tag_id: &str, n: i64) -> TaggedRow {
        TaggedRow { entity_id: song.into(), tag_id: tag_id.into(), vote_count: n }
    }

    #[test]
    fn 曲の多い順に並び_各タグは付けた人の多い順_消えた曲は数えない() {
        let s = snap();
        let (a, b) = (s.songs[0].id.clone(), s.songs[1].id.clone());
        let community = CommunitySnapshot::build(CommunityRows {
            song_tag_vocab: vec![tag("t1", "い"), tag("t2", "あ"), tag("t3", "う")],
            idol_tag_vocab: vec![],
            unit_tag_vocab: vec![],
            song_tags: vec![
                tagged(&a, "t1", 1),
                tagged(&b, "t1", 4),
                tagged(&a, "t2", 9),
                // 消えた曲にだけ付いたタグは一覧に出ない。
                tagged("居ない曲", "t3", 99),
                tagged("居ない曲", "t1", 99),
            ],
            idol_tags: vec![],
            unit_tags: vec![],
            favorites: vec![],
            penlight: vec![],
            polls: vec![],
            poll_entries: vec![],
        });
        let ranking = song_tag_ranking(&community, s);
        let ids: Vec<&str> = ranking.iter().map(|r| r.tag.id.as_str()).collect();
        assert_eq!(ids, vec!["t1", "t2"], "曲の多い順、t3 は消えた曲だけなので出ない");
        let t1: Vec<(u32, i64)> = ranking[0].songs.clone();
        assert_eq!(t1, vec![(1, 4), (0, 1)], "付けた人の多い順で、消えた曲の行は落ちる");
    }

    #[test]
    fn 同数のタグは名前順() {
        let s = snap();
        let a = s.songs[0].id.clone();
        let community = CommunitySnapshot::build(CommunityRows {
            song_tag_vocab: vec![tag("t1", "い"), tag("t2", "あ")],
            idol_tag_vocab: vec![],
            unit_tag_vocab: vec![],
            song_tags: vec![tagged(&a, "t1", 1), tagged(&a, "t2", 1)],
            idol_tags: vec![],
            unit_tags: vec![],
            favorites: vec![],
            penlight: vec![],
            polls: vec![],
            poll_entries: vec![],
        });
        let ids: Vec<&str> = song_tag_ranking(&community, s).iter().map(|r| r.tag.id.as_str()).collect();
        assert_eq!(ids, vec!["t2", "t1"]);
    }
}
