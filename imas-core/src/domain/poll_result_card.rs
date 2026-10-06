//! みんなの投票の結果を 1 枚の画像 (表彰台のポスター) にするときの中身。
//!
//! 画像の組み (表彰台・2 列) と描画は各 OS。ここが決めるのは「何を載せるか」:
//! 見出しの文言、締切前か後かの言い分け、順位の付け方 (同票は同順位)、
//! 表彰台に上げる数と下に並べる数。iOS と Android で同じ画像になるように一本化する。

use chrono::{DateTime, Datelike, FixedOffset};

/// 表彰台に上げる数 (1〜3 位の 3 つ)。
const PODIUM_COUNT: usize = 3;
/// 画像に載せる上限 (表彰台 + 下の 2 列で 10)。
const CARD_LIMIT: usize = 10;

/// お題の対象。助数詞 (曲 / 人 / 組) を決めるのに使う。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PollCardTarget {
    Song,
    Idol,
    Unit,
}

impl PollCardTarget {
    fn counter(self) -> &'static str {
        match self {
            PollCardTarget::Song => "曲",
            PollCardTarget::Idol => "人",
            PollCardTarget::Unit => "組",
        }
    }
}

/// サーバから来たランキングの 1 行 (票の多い順)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PollCardEntryInput {
    pub entity_id: String,
    pub vote_count: u32,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PollResultCardInput {
    pub title: String,
    pub target: PollCardTarget,
    /// 締切前 (投票受付中) か。締切前は「途中経過」としてその時点の日付を刷る。
    pub is_active: bool,
    pub ends_at_epoch_ms: i64,
    /// 画像を作った時刻 (締切前の「時点」に使う)。
    pub now_epoch_ms: i64,
    /// 端末の時刻帯の UTC からのずれ (秒)。日付を端末の暦で読む。
    pub tz_offset_seconds: i32,
    /// サーバの総票数。古いサーバで無いときは各行の票を足す。
    pub total_votes: Option<u32>,
    /// 票の多い順。
    pub entries: Vec<PollCardEntryInput>,
}

/// 画像に載せる 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PollCardRow {
    /// 同票は同じ順位 (1, 2, 2, 4)。
    pub rank: u32,
    pub entity_id: String,
    pub vote_count: u32,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PollResultCard {
    /// 見出しの前の印字 (「みんなの投票」)。
    pub kicker: String,
    /// 見出しの右の英字の印字 (`FINAL RESULT` / `INTERIM RESULT`)。
    pub imprint: String,
    /// 大見出し (お題)。
    pub title: String,
    /// 見出しの下の 1 行 (「18曲に412票 ・ 2026.10.06 締切」)。
    pub subtitle: String,
    /// 表彰台 (1〜3 位)。並べる順 (2 位・1 位・3 位) は描く側が決める。
    pub podium: Vec<PollCardRow>,
    /// 表彰台の下に並べる行 (4 位以降、合わせて 10 件まで)。
    pub rest: Vec<PollCardRow>,
}

/// 票の多い順の票数から順位を付ける (同票は同順位、次は飛ぶ: 1, 2, 2, 4)。
pub fn competition_ranks(votes: &[u32]) -> Vec<u32> {
    let mut ranks = Vec::with_capacity(votes.len());
    for (i, v) in votes.iter().enumerate() {
        let rank = if i > 0 && votes[i - 1] == *v { ranks[i - 1] } else { i as u32 + 1 };
        ranks.push(rank);
    }
    ranks
}

/// epoch ミリ秒を端末の暦で `YYYY.MM.DD` にする (印刷物の日付の書き方)。
fn dotted_date(epoch_ms: i64, tz_offset_seconds: i32) -> String {
    let utc = DateTime::from_timestamp_millis(epoch_ms).unwrap_or(DateTime::UNIX_EPOCH);
    let Some(offset) = FixedOffset::east_opt(tz_offset_seconds) else {
        return String::new();
    };
    let d = utc.with_timezone(&offset);
    format!("{}.{:02}.{:02}", d.year(), d.month(), d.day())
}

pub fn poll_result_card(input: &PollResultCardInput) -> PollResultCard {
    let votes: Vec<u32> = input.entries.iter().map(|e| e.vote_count).collect();
    let ranks = competition_ranks(&votes);
    let rows: Vec<PollCardRow> = input
        .entries
        .iter()
        .zip(ranks)
        .take(CARD_LIMIT)
        .map(|(e, rank)| PollCardRow { rank, entity_id: e.entity_id.clone(), vote_count: e.vote_count })
        .collect();
    let (podium, rest) = rows.split_at(rows.len().min(PODIUM_COUNT));

    let total = input.total_votes.unwrap_or_else(|| votes.iter().sum());
    let counts = format!("{}{}に{}票", input.entries.len(), input.target.counter(), total);
    let (imprint, when) = if input.is_active {
        ("INTERIM RESULT", format!("{} 時点の途中経過", dotted_date(input.now_epoch_ms, input.tz_offset_seconds)))
    } else {
        ("FINAL RESULT", format!("{} 締切", dotted_date(input.ends_at_epoch_ms, input.tz_offset_seconds)))
    };

    PollResultCard {
        kicker: "みんなの投票".to_string(),
        imprint: imprint.to_string(),
        title: input.title.clone(),
        subtitle: format!("{counts} ・ {when}"),
        podium: podium.to_vec(),
        rest: rest.to_vec(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const JST: i32 = 9 * 3600;
    // 2026-10-06 00:00 JST (= 10-05 15:00 UTC)
    const OCT6_JST: i64 = 1_791_212_400_000;

    fn input(votes: &[u32], is_active: bool) -> PollResultCardInput {
        PollResultCardInput {
            title: "秋の夜に聴きたい曲".into(),
            target: PollCardTarget::Song,
            is_active,
            ends_at_epoch_ms: OCT6_JST,
            now_epoch_ms: OCT6_JST - 86_400_000,
            tz_offset_seconds: JST,
            total_votes: None,
            entries: votes
                .iter()
                .enumerate()
                .map(|(i, v)| PollCardEntryInput { entity_id: format!("s{i}"), vote_count: *v })
                .collect(),
        }
    }

    #[test]
    fn ties_share_a_rank_and_the_next_rank_skips() {
        assert_eq!(competition_ranks(&[9, 7, 7, 5, 5, 5, 1]), vec![1, 2, 2, 4, 4, 4, 7]);
        assert_eq!(competition_ranks(&[]), Vec::<u32>::new());
    }

    #[test]
    fn podium_takes_three_and_rest_fills_up_to_ten() {
        let card = poll_result_card(&input(&[12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1], false));
        assert_eq!(card.podium.iter().map(|r| r.rank).collect::<Vec<_>>(), vec![1, 2, 3]);
        assert_eq!(card.rest.len(), 7);
        assert_eq!(card.rest.last().unwrap().rank, 10);
    }

    #[test]
    fn fewer_than_three_entries_have_no_rest() {
        let card = poll_result_card(&input(&[3, 1], false));
        assert_eq!(card.podium.len(), 2);
        assert!(card.rest.is_empty());
    }

    #[test]
    fn ended_poll_prints_deadline() {
        let card = poll_result_card(&input(&[3, 2, 1], false));
        assert_eq!(card.imprint, "FINAL RESULT");
        assert_eq!(card.subtitle, "3曲に6票 ・ 2026.10.06 締切");
    }

    #[test]
    fn active_poll_prints_as_of_today() {
        let mut i = input(&[3, 2, 1], true);
        i.target = PollCardTarget::Idol;
        i.total_votes = Some(40);
        let card = poll_result_card(&i);
        assert_eq!(card.imprint, "INTERIM RESULT");
        assert_eq!(card.subtitle, "3人に40票 ・ 2026.10.05 時点の途中経過");
    }
}
