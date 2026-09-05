//! コミュニティ集計 (タグ・お気に入り・ペンライト・お題) の読み取り。
//!
//! 出所は D1 で、`tools/export_community_snapshot.py` が「誰が」を含まない集計だけを
//! `db/community.sql` に落としてある。Web 出面はそれを**焼き込んで**配る。
//!
//! なぜ焼き込むか:
//! - コミュニティの読み取りは App Attest / Play Integrity で守られており、
//!   ブラウザはそのトークンを持てない (出面から D1 を直接叩く道が無い)。
//! - 仮に叩けても、閲覧のたびに D1 を読むと無料枠 (2026-09 時点で 96% 消費) を
//!   確実に超える。出面のランニングコストはゼロという絶対制約に反する。
//!
//! **出面は読むだけ。** 投稿・投票はログインが要るのでアプリへ誘導する。

use std::collections::HashMap;

/// タグの語彙 1 件 (曲・アイドル・ユニットで同じ形)。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TagRow {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub category: Option<String>,
    /// タグ自身の色 (hex)。無ければ受け手がテーマ色に落とす。
    pub color: Option<String>,
    pub is_official: bool,
}

/// 何かに付いたタグ 1 件と、その付与数。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TaggedRow {
    pub entity_id: String,
    pub tag_id: String,
    pub vote_count: i64,
}

/// ペンライトの色セット 1 件の得票。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PenlightVoteRow {
    pub song_id: String,
    /// 色セットの鍵 (アプリが色に解決する)。
    pub color_set_key: String,
    pub count: i64,
}

/// お題 1 件。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PollRow {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    /// 何を選ぶお題か (`song` / `idol` / `unit` 等)。
    pub target_type: String,
    pub created_at: Option<String>,
    pub ends_at: Option<String>,
    pub status: String,
}

/// お題の得票 1 行。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PollEntryRow {
    pub poll_id: String,
    pub entity_id: String,
    pub vote_count: i64,
}

/// 読み込んだ集計一式と、引きやすくした索引。
///
/// `Snapshot` と同じ流儀で、**索引はここで 1 回だけ組む**。ページごとに
/// 全行を走査すると 7,000 ページ分の線形探索になる。
#[derive(Debug, Default)]
pub struct CommunitySnapshot {
    pub song_tag_vocab: HashMap<String, TagRow>,
    pub idol_tag_vocab: HashMap<String, TagRow>,
    pub unit_tag_vocab: HashMap<String, TagRow>,
    song_tags: HashMap<String, Vec<TaggedRow>>,
    idol_tags: HashMap<String, Vec<TaggedRow>>,
    unit_tags: HashMap<String, Vec<TaggedRow>>,
    favorites: HashMap<String, i64>,
    penlight: HashMap<String, Vec<PenlightVoteRow>>,
    pub polls: Vec<PollRow>,
    poll_entries: HashMap<String, Vec<PollEntryRow>>,
}

/// 読み込んだ生の行。ローダ (`outbound::community_loader`) が渡す。
pub struct CommunityRows {
    pub song_tag_vocab: Vec<TagRow>,
    pub idol_tag_vocab: Vec<TagRow>,
    pub unit_tag_vocab: Vec<TagRow>,
    pub song_tags: Vec<TaggedRow>,
    pub idol_tags: Vec<TaggedRow>,
    pub unit_tags: Vec<TaggedRow>,
    pub favorites: Vec<(String, i64)>,
    pub penlight: Vec<PenlightVoteRow>,
    pub polls: Vec<PollRow>,
    pub poll_entries: Vec<PollEntryRow>,
}

/// 付与数の多い順、同数はタグ id 順 (毎回同じ順に並ぶ = 出力が byte 一致する)。
fn group_tags(rows: Vec<TaggedRow>) -> HashMap<String, Vec<TaggedRow>> {
    let mut map: HashMap<String, Vec<TaggedRow>> = HashMap::new();
    for row in rows {
        map.entry(row.entity_id.clone()).or_default().push(row);
    }
    for list in map.values_mut() {
        list.sort_by(|a, b| b.vote_count.cmp(&a.vote_count).then_with(|| a.tag_id.cmp(&b.tag_id)));
    }
    map
}

impl CommunitySnapshot {
    pub fn build(rows: CommunityRows) -> Self {
        let vocab = |v: Vec<TagRow>| -> HashMap<String, TagRow> {
            v.into_iter().map(|t| (t.id.clone(), t)).collect()
        };

        let mut penlight: HashMap<String, Vec<PenlightVoteRow>> = HashMap::new();
        for row in rows.penlight {
            penlight.entry(row.song_id.clone()).or_default().push(row);
        }
        for list in penlight.values_mut() {
            list.sort_by(|a, b| {
                b.count.cmp(&a.count).then_with(|| a.color_set_key.cmp(&b.color_set_key))
            });
        }

        let mut poll_entries: HashMap<String, Vec<PollEntryRow>> = HashMap::new();
        for row in rows.poll_entries {
            poll_entries.entry(row.poll_id.clone()).or_default().push(row);
        }
        for list in poll_entries.values_mut() {
            list.sort_by(|a, b| {
                b.vote_count.cmp(&a.vote_count).then_with(|| a.entity_id.cmp(&b.entity_id))
            });
        }

        let mut polls = rows.polls;
        // 新しい順。`created_at` が無い行は末尾へ (id で安定させる)。
        polls.sort_by(|a, b| {
            b.created_at.cmp(&a.created_at).then_with(|| a.id.cmp(&b.id))
        });

        Self {
            song_tag_vocab: vocab(rows.song_tag_vocab),
            idol_tag_vocab: vocab(rows.idol_tag_vocab),
            unit_tag_vocab: vocab(rows.unit_tag_vocab),
            song_tags: group_tags(rows.song_tags),
            idol_tags: group_tags(rows.idol_tags),
            unit_tags: group_tags(rows.unit_tags),
            favorites: rows.favorites.into_iter().collect(),
            penlight,
            polls,
            poll_entries,
        }
    }

    /// 曲に付いたタグ (多い順)。語彙に無いタグ id は落とす (消されたタグ)。
    pub fn song_tags(&self, song_id: &str) -> Vec<(&TagRow, i64)> {
        resolve(&self.song_tags, &self.song_tag_vocab, song_id)
    }

    pub fn idol_tags(&self, idol_id: &str) -> Vec<(&TagRow, i64)> {
        resolve(&self.idol_tags, &self.idol_tag_vocab, idol_id)
    }

    pub fn unit_tags(&self, unit_id: &str) -> Vec<(&TagRow, i64)> {
        resolve(&self.unit_tags, &self.unit_tag_vocab, unit_id)
    }

    /// お気に入りに入れている人の数。
    pub fn favorites(&self, song_id: &str) -> i64 {
        self.favorites.get(song_id).copied().unwrap_or(0)
    }

    /// ペンライトの色セット (得票の多い順)。
    pub fn penlight(&self, song_id: &str) -> &[PenlightVoteRow] {
        self.penlight.get(song_id).map(Vec::as_slice).unwrap_or(&[])
    }

    /// お題の得票 (多い順)。
    pub fn poll_entries(&self, poll_id: &str) -> &[PollEntryRow] {
        self.poll_entries.get(poll_id).map(Vec::as_slice).unwrap_or(&[])
    }
}

fn resolve<'a>(
    tagged: &'a HashMap<String, Vec<TaggedRow>>,
    vocab: &'a HashMap<String, TagRow>,
    id: &str,
) -> Vec<(&'a TagRow, i64)> {
    tagged
        .get(id)
        .map(|rows| {
            rows.iter().filter_map(|r| Some((vocab.get(&r.tag_id)?, r.vote_count))).collect()
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tag(id: &str) -> TagRow {
        TagRow {
            id: id.to_string(),
            name: id.to_uppercase(),
            description: None,
            category: None,
            color: None,
            is_official: false,
        }
    }
    fn tagged(entity: &str, tag_id: &str, n: i64) -> TaggedRow {
        TaggedRow { entity_id: entity.into(), tag_id: tag_id.into(), vote_count: n }
    }

    fn snap() -> CommunitySnapshot {
        CommunitySnapshot::build(CommunityRows {
            song_tag_vocab: vec![tag("a"), tag("b")],
            idol_tag_vocab: vec![],
            unit_tag_vocab: vec![],
            // 語彙に無い "消えた" も混ぜる。
            song_tags: vec![tagged("s1", "a", 3), tagged("s1", "消えた", 99), tagged("s1", "b", 3)],
            idol_tags: vec![],
            unit_tags: vec![],
            favorites: vec![("s1".into(), 12)],
            penlight: vec![],
            polls: vec![],
            poll_entries: vec![],
        })
    }

    #[test]
    fn 付与数の多い順で同数はタグid順() {
        let s = snap();
        let got: Vec<(&str, i64)> =
            s.song_tags("s1").into_iter().map(|(t, n)| (t.id.as_str(), n)).collect();
        assert_eq!(got, vec![("a", 3), ("b", 3)]);
    }

    #[test]
    fn 語彙から消えたタグは出さない() {
        let s = snap();
        assert!(s.song_tags("s1").iter().all(|(t, _)| t.id != "消えた"));
    }

    #[test]
    fn 集計の無い相手は空とゼロ() {
        let s = snap();
        assert!(s.song_tags("居ない").is_empty());
        assert_eq!(s.favorites("居ない"), 0);
        assert!(s.penlight("居ない").is_empty());
    }
}
