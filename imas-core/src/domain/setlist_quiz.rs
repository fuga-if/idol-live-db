//! セトリ当てクイズ: 公演のセトリの 1 曲を伏せ、そこに入る曲を 4 択で当てる。
//!
//! ## 出題
//!
//! - 公演はセトリが [`MIN_SETLIST_SONGS`] 曲以上あるものだけ (前後が読めないと当てようがない)。
//!   出題ブランドはライブ (event) のブランドで絞る。空 = 全ブランド。
//! - 伏せる曲は、その公演で 1 回しか歌われていない曲だけ (同じ曲が別の位置に見えていると答えが割れる)。
//! - 誤答は「その公演では歌われていない、同じブランドのライブで歌われたことのある曲」から引く
//!   (どこかのライブでは歌われた曲なので、それらしく見える)。足りなければ全ブランドから補う。
//! - 1 セッションで同じ公演は出さない (候補が尽きるまで)。
//!
//! ## 見せ方とヒント (採点はほかのクイズと同じ加点式: ノーヒント 10pt、コストを引いて最低 1pt)
//!
//! - 最初は伏せた曲の前後 [`CONTEXT_WINDOW`] 曲ずつだけ見せる。
//! - 歌唱メンバー: 伏せた曲を歌ったメンバー (記録がある公演だけ)。
//! - 前後をもっと見る: セトリを全部見せる。
//! - 2択にする: 誤答を 2 つ消す。

use std::collections::HashSet;

use crate::domain::prng::SplitMix64;
use crate::domain::quiz_generation::{quiz_answer, QuizAnswerOutcome, QuizTally};
use crate::domain::snapshot::Snapshot;

/// ノーヒント正解の素点。
pub const SETLIST_QUIZ_BASE_POINTS: u32 = 10;
/// 出題できる公演のセトリの最低曲数。
pub const MIN_SETLIST_SONGS: usize = 6;
/// 最初に見せる、伏せた曲の前後の曲数。
pub const CONTEXT_WINDOW: usize = 2;
/// 1 問の選択肢の数。
const CHOICES: usize = 4;

/// セトリの 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistQuizLine {
    /// セトリ内の曲順 (1 始まり)。
    pub number: u32,
    pub song_title: String,
    /// 区切りの見出し (本編 / アンコール など、原文)。
    pub section: Option<String>,
    /// 伏せた曲か。
    pub is_blank: bool,
}

/// 選択肢 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistQuizChoice {
    pub song_id: String,
    pub title: String,
}

/// 伏せた曲を歌ったメンバー。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistQuizPerformer {
    pub name: String,
    pub color: Option<String>,
}

/// 1 問ぶんの出題。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistQuizQuestion {
    pub show_id: String,
    pub event_name: String,
    pub show_name: String,
    pub date: String,
    pub venue: Option<String>,
    pub brand_id: Option<String>,
    /// セトリ全体 (伏せた曲の行は `is_blank`、曲名は入っているが画面には出さない)。
    pub lines: Vec<SetlistQuizLine>,
    /// `lines` の中の伏せた行の位置 (0 始まり)。
    pub blank_index: u32,
    pub answer: SetlistQuizChoice,
    pub answer_artwork_url: Option<String>,
    /// 選択肢 (表示順)。答えを 1 つ含む。
    pub choices: Vec<SetlistQuizChoice>,
    pub performers: Vec<SetlistQuizPerformer>,
}

/// ヒントの種類 (並び順がそのままタイルの並び)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SetlistQuizHintKind {
    /// 前後をもっと見る (セトリを全部見せる)。
    Wider,
    /// 歌唱メンバー。
    Performers,
    /// 2択にする。
    FiftyFifty,
}

impl SetlistQuizHintKind {
    pub const ALL: [SetlistQuizHintKind; 3] = [Self::Wider, Self::Performers, Self::FiftyFifty];

    pub fn cost(self) -> u32 {
        match self {
            Self::Wider => 2,
            Self::Performers => 3,
            Self::FiftyFifty => 5,
        }
    }
}

/// まだ開いていないヒント 1 件。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistQuizHintOption {
    pub kind: SetlistQuizHintKind,
    pub cost: u32,
    pub next_value: u32,
}

/// 出題カードの開示状態。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistQuizHintState {
    pub current_value: u32,
    pub base_value: u32,
    /// 見せる行の範囲 (`lines` の位置、両端を含む)。
    pub visible_from: u32,
    pub visible_to: u32,
    /// 前に隠れている曲数 / 後ろに隠れている曲数 (「… ほか 3 曲」)。
    pub hidden_before: u32,
    pub hidden_after: u32,
    /// 歌唱メンバーを見せるか。
    pub show_performers: bool,
    /// 伏せた曲名を見せるか (解答後)。
    pub reveal_answer: bool,
    /// 2 択で消した選択肢の位置。
    pub eliminated: Vec<u32>,
    /// まだ開けるヒント (解答後は空)。
    pub hints: Vec<SetlistQuizHintOption>,
}

/// 出題設定画面の見積り。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistQuizPoolEstimate {
    /// 出題できる公演数。
    pub show_count: u32,
    pub is_sufficient: bool,
}

// ---------------------------------------------------------------------------
// 母集団
// ---------------------------------------------------------------------------

fn event_brand(snap: &Snapshot, show: u32) -> Option<&str> {
    snap.events[snap.shows[show as usize].event as usize].brand_id.as_deref()
}

/// 伏せてよい行 (その公演で 1 回しか歌われていない曲) の位置。
fn blankable_positions(snap: &Snapshot, show: u32) -> Vec<usize> {
    let items = &snap.setlist_items_by_show[show as usize];
    let songs: Vec<u32> = items.iter().map(|&i| snap.setlist_items[i as usize].song).collect();
    (0..songs.len())
        .filter(|&p| songs.iter().filter(|&&s| s == songs[p]).count() == 1)
        .collect()
}

/// 出題できる公演 (選択ブランドのライブで、セトリが十分あるもの)。並びは公演の添字順。
fn eligible_shows(snap: &Snapshot, brand_ids: &[String]) -> Vec<u32> {
    let brands: HashSet<&str> = brand_ids.iter().map(String::as_str).collect();
    (0..snap.shows.len() as u32)
        .filter(|&s| {
            brands.is_empty() || event_brand(snap, s).is_some_and(|b| brands.contains(b))
        })
        .filter(|&s| {
            snap.setlist_items_by_show[s as usize].len() >= MIN_SETLIST_SONGS
                && !blankable_positions(snap, s).is_empty()
        })
        .collect()
}

pub fn pool_estimate(snap: &Snapshot, brand_ids: &[String]) -> SetlistQuizPoolEstimate {
    let show_count = eligible_shows(snap, brand_ids).len() as u32;
    SetlistQuizPoolEstimate { show_count, is_sufficient: show_count >= 1 }
}

/// ライブで歌われたことのある曲 (ブランドは曲が歌われたライブのブランド)。重複なし・添字順。
fn performed_songs(snap: &Snapshot, brand: Option<&str>) -> Vec<u32> {
    let mut seen = vec![false; snap.songs.len()];
    for item in &snap.setlist_items {
        if brand.is_none() || event_brand(snap, item.show) == brand {
            seen[item.song as usize] = true;
        }
    }
    (0..snap.songs.len() as u32).filter(|&s| seen[s as usize]).collect()
}

// ---------------------------------------------------------------------------
// 出題
// ---------------------------------------------------------------------------

fn choice(snap: &Snapshot, song: u32) -> SetlistQuizChoice {
    let s = &snap.songs[song as usize];
    SetlistQuizChoice { song_id: s.id.clone(), title: s.title.clone() }
}

/// `pool` から `exclude` に無い曲を `take` 曲、重複なしで引く。
fn draw_songs(pool: &[u32], exclude: &HashSet<u32>, take: usize, rng: &mut SplitMix64) -> Vec<u32> {
    let mut candidates: Vec<u32> = pool.iter().copied().filter(|s| !exclude.contains(s)).collect();
    rng.shuffle(&mut candidates);
    candidates.truncate(take);
    candidates
}

fn make_question(snap: &Snapshot, show: u32, rng: &mut SplitMix64) -> Option<SetlistQuizQuestion> {
    let items = &snap.setlist_items_by_show[show as usize];
    let positions = blankable_positions(snap, show);
    let blank = *positions.get(rng.next_below(positions.len() as u64) as usize)?;
    let blank_item = &snap.setlist_items[items[blank] as usize];
    let answer_song = blank_item.song;

    // この公演のセトリに入っている曲は誤答にしない (見えている曲と被ると成り立たない)。
    let in_show: HashSet<u32> = items.iter().map(|&i| snap.setlist_items[i as usize].song).collect();
    let brand = event_brand(snap, show);
    let mut wrong = draw_songs(&performed_songs(snap, brand), &in_show, CHOICES - 1, rng);
    if wrong.len() < CHOICES - 1 {
        let mut exclude = in_show.clone();
        exclude.extend(wrong.iter().copied());
        let more = draw_songs(&performed_songs(snap, None), &exclude, CHOICES - 1 - wrong.len(), rng);
        wrong.extend(more);
    }
    if wrong.len() < CHOICES - 1 {
        return None;
    }
    let mut choices: Vec<u32> = std::iter::once(answer_song).chain(wrong).collect();
    rng.shuffle(&mut choices);

    let show_rec = &snap.shows[show as usize];
    let event = &snap.events[show_rec.event as usize];
    Some(SetlistQuizQuestion {
        show_id: show_rec.id.clone(),
        event_name: event.name.clone(),
        show_name: show_rec.name.clone(),
        date: show_rec.date.clone(),
        venue: show_rec.venue.clone(),
        brand_id: event.brand_id.clone(),
        lines: items
            .iter()
            .enumerate()
            .map(|(p, &i)| {
                let item = &snap.setlist_items[i as usize];
                SetlistQuizLine {
                    number: p as u32 + 1,
                    song_title: snap.songs[item.song as usize].title.clone(),
                    section: item.section.clone(),
                    is_blank: p == blank,
                }
            })
            .collect(),
        blank_index: blank as u32,
        answer: choice(snap, answer_song),
        answer_artwork_url: snap.songs[answer_song as usize].artwork_url.clone(),
        choices: choices.into_iter().map(|s| choice(snap, s)).collect(),
        performers: snap.performers_by_item[items[blank] as usize]
            .iter()
            .map(|&idol| {
                let rec = &snap.idols[idol as usize];
                SetlistQuizPerformer { name: rec.name.clone(), color: rec.color.clone() }
            })
            .collect(),
    })
}

/// 1 ゲームぶんの出題をまとめて作る。出題できる公演が無ければ空。
/// 公演はシャッフルした順に使い、一巡するまで同じ公演を出さない。
pub fn make_session(
    snap: &Snapshot,
    brand_ids: &[String],
    session_length: u32,
    rng: &mut SplitMix64,
) -> Vec<SetlistQuizQuestion> {
    let mut shows = eligible_shows(snap, brand_ids);
    if shows.is_empty() {
        return Vec::new();
    }
    rng.shuffle(&mut shows);
    (0..session_length as usize)
        .filter_map(|i| make_question(snap, shows[i % shows.len()], rng))
        .collect()
}

// ---------------------------------------------------------------------------
// ヒントと採点
// ---------------------------------------------------------------------------

fn available(question: &SetlistQuizQuestion) -> Vec<SetlistQuizHintKind> {
    let hidden = question.lines.len() > 2 * CONTEXT_WINDOW + 1;
    SetlistQuizHintKind::ALL
        .into_iter()
        .filter(|k| match k {
            SetlistQuizHintKind::Wider => hidden,
            SetlistQuizHintKind::Performers => !question.performers.is_empty(),
            SetlistQuizHintKind::FiftyFifty => true,
        })
        .collect()
}

pub fn current_value(opened: &[SetlistQuizHintKind]) -> u32 {
    let cost: u32 = opened.iter().copied().collect::<HashSet<_>>().into_iter().map(|k| k.cost()).sum();
    SETLIST_QUIZ_BASE_POINTS.saturating_sub(cost).max(1)
}

/// 2 択で消す選択肢: 答え以外の先頭 2 つ (出題時にシャッフル済みなので偏らない)。
fn eliminated(question: &SetlistQuizQuestion) -> Vec<u32> {
    question
        .choices
        .iter()
        .enumerate()
        .filter(|(_, c)| c.song_id != question.answer.song_id)
        .take(CHOICES / 2)
        .map(|(i, _)| i as u32)
        .collect()
}

pub fn hint_state(
    question: &SetlistQuizQuestion,
    opened: &[SetlistQuizHintKind],
    answered: bool,
) -> SetlistQuizHintState {
    let usable = available(question);
    let opened: HashSet<SetlistQuizHintKind> =
        opened.iter().copied().filter(|k| usable.contains(k)).collect();
    let opened_list: Vec<SetlistQuizHintKind> = opened.iter().copied().collect();
    let value = current_value(&opened_list);
    let last = question.lines.len().saturating_sub(1);
    let blank = question.blank_index as usize;
    let (from, to) = if answered || opened.contains(&SetlistQuizHintKind::Wider) {
        (0, last)
    } else {
        (blank.saturating_sub(CONTEXT_WINDOW), (blank + CONTEXT_WINDOW).min(last))
    };
    SetlistQuizHintState {
        current_value: value,
        base_value: SETLIST_QUIZ_BASE_POINTS,
        visible_from: from as u32,
        visible_to: to as u32,
        hidden_before: from as u32,
        hidden_after: (last - to) as u32,
        show_performers: answered || opened.contains(&SetlistQuizHintKind::Performers),
        reveal_answer: answered,
        eliminated: if !answered && opened.contains(&SetlistQuizHintKind::FiftyFifty) {
            eliminated(question)
        } else {
            Vec::new()
        },
        hints: if answered {
            Vec::new()
        } else {
            usable
                .into_iter()
                .filter(|k| !opened.contains(k))
                .map(|kind| SetlistQuizHintOption {
                    kind,
                    cost: kind.cost(),
                    next_value: value.saturating_sub(kind.cost()).max(1),
                })
                .collect()
        },
    }
}

pub fn answer(
    question: &SetlistQuizQuestion,
    opened: &[SetlistQuizHintKind],
    picked_song_id: &str,
    before: &QuizTally,
    session_length: u32,
) -> QuizAnswerOutcome {
    quiz_answer(
        current_value(opened),
        opened.iter().copied().collect::<HashSet<_>>().len() as u32,
        picked_song_id,
        &question.answer.song_id,
        before,
        session_length,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    fn session(seed: u64) -> Vec<SetlistQuizQuestion> {
        make_session(bundle_snapshot(), &[], 10, &mut SplitMix64(seed))
    }

    #[test]
    fn session_blanks_one_song_with_four_distinct_choices() {
        let qs = session(42);
        assert_eq!(qs.len(), 10);
        for q in &qs {
            assert!(q.lines.len() >= MIN_SETLIST_SONGS);
            assert_eq!(q.lines.iter().filter(|l| l.is_blank).count(), 1);
            assert!(q.lines[q.blank_index as usize].is_blank);
            assert_eq!(q.choices.len(), 4);
            let ids: HashSet<&str> = q.choices.iter().map(|c| c.song_id.as_str()).collect();
            assert_eq!(ids.len(), 4);
            assert!(ids.contains(q.answer.song_id.as_str()));
            // 誤答はこの公演で歌われていない。
            let titles: HashSet<&str> = q.lines.iter().map(|l| l.song_title.as_str()).collect();
            for c in q.choices.iter().filter(|c| c.song_id != q.answer.song_id) {
                assert!(!titles.contains(c.title.as_str()) || c.title == q.answer.title, "{}", c.title);
            }
        }
        let shows: HashSet<&str> = qs.iter().map(|q| q.show_id.as_str()).collect();
        assert_eq!(shows.len(), 10, "一巡するまで同じ公演を出さない");
    }

    #[test]
    fn session_is_deterministic_per_seed() {
        assert_eq!(session(7), session(7));
        assert_ne!(session(7), session(8));
    }

    #[test]
    fn brand_filter_limits_shows() {
        let snap = bundle_snapshot();
        let all = pool_estimate(snap, &[]).show_count;
        let ml = pool_estimate(snap, &["ml".to_string()]).show_count;
        assert!(ml > 0 && ml < all);
        for q in make_session(snap, &["ml".to_string()], 10, &mut SplitMix64(3)) {
            assert_eq!(q.brand_id.as_deref(), Some("ml"));
        }
        assert!(!pool_estimate(snap, &["no-such-brand".to_string()]).is_sufficient);
    }

    fn fixture() -> SetlistQuizQuestion {
        let line = |n: u32, blank: bool| SetlistQuizLine {
            number: n,
            song_title: format!("曲{n}"),
            section: None,
            is_blank: blank,
        };
        let c = |id: &str| SetlistQuizChoice { song_id: id.into(), title: id.into() };
        SetlistQuizQuestion {
            show_id: "s".into(),
            event_name: "e".into(),
            show_name: "Day1".into(),
            date: "2026-01-01".into(),
            venue: None,
            brand_id: None,
            lines: (1..=10).map(|n| line(n, n == 5)).collect(),
            blank_index: 4,
            answer: c("a"),
            answer_artwork_url: None,
            choices: vec![c("x"), c("a"), c("y"), c("z")],
            performers: vec![SetlistQuizPerformer { name: "春香".into(), color: None }],
        }
    }

    #[test]
    fn window_shows_two_songs_each_side_until_wider_is_opened() {
        let q = fixture();
        let s = hint_state(&q, &[], false);
        assert_eq!((s.visible_from, s.visible_to), (2, 6));
        assert_eq!((s.hidden_before, s.hidden_after), (2, 3));
        assert!(!s.show_performers && !s.reveal_answer);
        assert_eq!(s.hints.len(), 3);

        let wide = hint_state(&q, &[SetlistQuizHintKind::Wider], false);
        assert_eq!((wide.visible_from, wide.visible_to), (0, 9));
        assert_eq!(wide.current_value, 8);
    }

    #[test]
    fn fifty_fifty_keeps_the_answer_and_scores_subtract() {
        let q = fixture();
        use SetlistQuizHintKind::*;
        let s = hint_state(&q, &[FiftyFifty, Performers], false);
        assert_eq!(s.eliminated, vec![0, 2]);
        assert!(s.show_performers);
        assert_eq!(s.current_value, 2);
        let hit = answer(&q, &[FiftyFifty, Performers], "a", &QuizTally::default(), 10);
        assert!(hit.is_correct);
        assert_eq!(hit.earned_points, 2);
        assert!(!answer(&q, &[], "x", &QuizTally::default(), 10).is_correct);
    }

    #[test]
    fn hints_that_cannot_help_are_not_offered() {
        let mut q = fixture();
        q.performers.clear();
        q.lines.truncate(5);
        let s = hint_state(&q, &[], false);
        assert_eq!(s.hints.iter().map(|h| h.kind).collect::<Vec<_>>(), vec![SetlistQuizHintKind::FiftyFifty]);
        let answered = hint_state(&q, &[], true);
        assert!(answered.reveal_answer && answered.hints.is_empty());
    }
}
