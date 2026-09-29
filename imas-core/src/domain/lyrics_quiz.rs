//! 歌詞クイズ (曲名当て / 続きはどれ) の出題・採点規則。
//!
//! ## 2 つの形式
//!
//! - **曲名当て** ([`LyricsQuizMode::Title`]): 歌詞 1 行を見せて曲名を 4 択で当てる。
//!   ヒント 1 = 続きの 1 行 / ヒント 2 = 歌唱 (名義)。
//! - **続きはどれ** ([`LyricsQuizMode::NextLine`]): 曲名と歌詞 1 行を見せて、次の行を 4 択で当てる。
//!   誤答は**同じ曲の別の行**から取る。ヒント 1 = 前の行 / ヒント 2 = 選択肢を 2 つに絞る。
//!
//! 採点はソロ曲クイズと同じ段階式 (ノーヒント 3pt / ヒント 1 つ 2pt / 2 つ 1pt)。
//!
//! ## 歌詞の扱い (JASRAC 許諾の条件)
//!
//! 歌詞本文は `GET /songs/:id/lyrics` で**出題のたびに 1 曲ずつ**取る。母集団 (公開済みの曲 id)
//! は本文を含まない `GET /lyrics/published` から得る。ここの型は歌詞の断片を持つが、
//! 呼び出し側は**画面に出している間だけ**メモリに置き、保存・共有に使わないこと
//! (リザルト・振り返り・シェア文言は曲名だけで組む)。
//!
//! ## FFI 境界の形
//!
//! - 曲の並び (どの曲を何問目に出すか・曲名当ての 4 択) は [`lyrics_quiz_session`] で
//!   1 ゲーム分をまとめて返す。歌詞が取れない曲に備えて**予備を含めた長さ**で返すので、
//!   呼び出し側は使えない曲を飛ばして次へ進む (解答数が出題数に達したら終わり)。
//! - 歌詞のどこを出すかは、1 曲の歌詞が届いた時点で [`lyrics_quiz_excerpt`] が決める。
//! - 乱数は [`SplitMix64`] のシード注入 (調達はラッパ)。

use std::collections::HashSet;

use unicode_normalization::UnicodeNormalization;

use crate::domain::prng::SplitMix64;
use crate::domain::quiz_generation::{
    canonical, has_enough_candidates, quiz_answer, song_quiz_points, BrandFilter,
    QuizAnswerOutcome, QuizTally, SequentialDraw, DISTRACTOR_COUNT, MINIMUM_POOL,
};

/// 歌詞が取れない・出題に向かない曲に備えて、出題数に上乗せして並べる曲数。
pub const LYRICS_QUIZ_SPARE_SONGS: u32 = 10;

/// 曲名当てで出題行に使う最小の文字数 (空白を除く)。短い行 (「Yeah!」等) は手がかりにならない。
const TITLE_PROMPT_MIN_CHARS: usize = 6;

/// 出題形式。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum LyricsQuizMode {
    /// 歌詞 1 行から曲名を当てる。
    Title,
    /// 歌詞 1 行の続きを当てる。
    NextLine,
}

/// 出題対象になりうる曲の射影。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct LyricsQuizSongRef {
    pub id: String,
    pub brand_id: String,
}

/// 歌詞 1 行の射影。`is_lyric` が偽の行 (空行・イントロ等の構成マーカー) は
/// 出題に使わず、ブロックの区切りとしてだけ扱う。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct LyricsQuizLine {
    pub text: String,
    pub is_lyric: bool,
}

/// 出題設定画面の候補数。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricsQuizPoolEstimate {
    pub song_count: u32,
    pub is_sufficient: bool,
}

/// 出題順の 1 曲。`song` / `choices` は入力 `songs` の index。
/// `choices` は曲名当ての 4 択 (続きはどれでは使わない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct LyricsQuizQuestion {
    pub song: u32,
    pub choices: Vec<u32>,
}

/// ヒントの種類。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum LyricsQuizHintKind {
    /// 曲名当て: 続きの 1 行を見る。
    NextLine,
    /// 曲名当て: 歌唱 (名義) を見る。
    Singer,
    /// 続きはどれ: 前の 1 行を見る。
    PreviousLine,
    /// 続きはどれ: 誤答を 2 つ消す。
    FiftyFifty,
}

/// 1 曲の歌詞から切り出した出題。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct LyricsQuizExcerpt {
    /// 出題行。
    pub prompt: String,
    /// ヒントで開く行 (曲名当て = 続きの行 / 続きはどれ = 前の行)。無ければ `None`。
    pub context_line: Option<String>,
    /// 続きはどれの 4 択 (表示順)。曲名当てでは空。
    pub choices: Vec<String>,
    /// 続きはどれの正解 (`choices` の位置)。曲名当てでは 0。
    pub answer: u32,
    /// 50:50 で消す誤答 (`choices` の位置)。曲名当てでは空。
    pub fifty_fifty_hidden: Vec<u32>,
    /// 開ける順のヒント (最大 2 つ)。
    pub hints: Vec<LyricsQuizHintKind>,
}

/// 次に開けるヒント。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricsQuizHintOption {
    pub kind: LyricsQuizHintKind,
    pub next_value: u32,
}

/// 出題カードの開示状態。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricsQuizHintState {
    pub current_value: u32,
    /// 開示済みのヒント (解答後は全部)。
    pub shown: Vec<LyricsQuizHintKind>,
    pub next_hint: Option<LyricsQuizHintOption>,
}

// ---------------------------------------------------------------------------
// 母集団と出題順
// ---------------------------------------------------------------------------

/// 公開済みかつブランド一致の曲 (`songs` の index)。同じ曲 id の重複は初出だけ残す。
fn pool_indices(
    songs: &[LyricsQuizSongRef],
    published_song_ids: &[String],
    selected_brand_ids: &[String],
) -> Vec<usize> {
    let published: HashSet<String> = published_song_ids
        .iter()
        .map(|id| canonical(id).into_owned())
        .collect();
    let brands = BrandFilter::new(selected_brand_ids);
    let mut seen: HashSet<String> = HashSet::new();
    (0..songs.len())
        .filter(|&i| {
            let id = canonical(&songs[i].id).into_owned();
            published.contains(&id) && brands.matches(&songs[i].brand_id) && seen.insert(id)
        })
        .collect()
}

/// 出題設定画面の候補数。ゲーム本体と同じ母集団条件で数える。
pub fn lyrics_quiz_pool_estimate(
    songs: &[LyricsQuizSongRef],
    published_song_ids: &[String],
    selected_brand_ids: &[String],
) -> LyricsQuizPoolEstimate {
    let count = pool_indices(songs, published_song_ids, selected_brand_ids).len();
    LyricsQuizPoolEstimate {
        song_count: count as u32,
        is_sufficient: has_enough_candidates(count),
    }
}

/// 1 ゲーム分の出題順 (予備込み)。候補不足なら空。
///
/// 母集団が尽きるまで同じ曲は出さない。曲名当ての誤答は同ブランドを優先する
/// (ブランドを跨ぐと曲調で消去法が効きすぎる)。
pub fn lyrics_quiz_session(
    songs: &[LyricsQuizSongRef],
    published_song_ids: &[String],
    selected_brand_ids: &[String],
    length: u32,
    rng: &mut SplitMix64,
) -> Vec<LyricsQuizQuestion> {
    let pool = pool_indices(songs, published_song_ids, selected_brand_ids);
    if !has_enough_candidates(pool.len()) {
        return Vec::new();
    }
    let count = (length as usize).min(pool.len());
    let mut draw = SequentialDraw::new(pool.len());
    (0..count)
        .filter_map(|_| {
            let position = draw.next(rng)?;
            let answer = &songs[pool[position]];
            let others: Vec<usize> = pool
                .iter()
                .copied()
                .filter(|&i| canonical(&songs[i].id) != canonical(&answer.id))
                .collect();
            let brand = canonical(&answer.brand_id).into_owned();
            let (mut same, mut cross): (Vec<usize>, Vec<usize>) = others
                .into_iter()
                .partition(|&i| canonical(&songs[i].brand_id) == brand.as_str());
            rng.shuffle(&mut same);
            rng.shuffle(&mut cross);
            same.extend(cross);
            same.truncate(DISTRACTOR_COUNT as usize);
            same.push(pool[position]);
            rng.shuffle(&mut same);
            Some(LyricsQuizQuestion {
                song: pool[position] as u32,
                choices: same.into_iter().map(|i| i as u32).collect(),
            })
        })
        .collect()
}

// ---------------------------------------------------------------------------
// 歌詞の切り出し
// ---------------------------------------------------------------------------

/// 比較用の畳み込み (NFKC + 小文字 + 空白・記号除去)。曲名が行に含まれるかの判定に使う。
fn fold(s: &str) -> String {
    s.nfkc()
        .flat_map(char::to_lowercase)
        .filter(|c| c.is_alphanumeric())
        .collect()
}

/// 曲名の芯。副題 (「～…～」「(…)」) を落とした部分。
fn title_core(title: &str) -> String {
    let cut = title
        .find(['(', '（', '～', '〜', '~', '-', '－'])
        .filter(|&i| i > 0)
        .unwrap_or(title.len());
    fold(&title[..cut])
}

fn visible_len(s: &str) -> usize {
    s.chars().filter(|c| !c.is_whitespace()).count()
}

/// 歌詞の行。`block` は空行・マーカーで区切られたまとまりの番号。
struct Lyric<'a> {
    text: &'a str,
    block: usize,
}

fn lyric_lines(lines: &[LyricsQuizLine]) -> Vec<Lyric<'_>> {
    let mut block = 0;
    let mut out = Vec::new();
    for line in lines {
        let text = line.text.trim();
        if line.is_lyric && !text.is_empty() {
            out.push(Lyric { text, block });
        } else {
            block += 1;
        }
    }
    out
}

/// 1 曲の歌詞から出題を切り出す。出題に向かない歌詞 (行が足りない等) は `None`
/// — 呼び出し側はその曲を飛ばして次の曲へ進む。
///
/// `has_singer` は歌唱ヒントを出せるか (名義が空の曲では出さない)。
pub fn lyrics_quiz_excerpt(
    lines: &[LyricsQuizLine],
    song_title: &str,
    has_singer: bool,
    mode: LyricsQuizMode,
    rng: &mut SplitMix64,
) -> Option<LyricsQuizExcerpt> {
    let lyrics = lyric_lines(lines);
    match mode {
        LyricsQuizMode::Title => title_excerpt(&lyrics, song_title, has_singer, rng),
        LyricsQuizMode::NextLine => next_line_excerpt(&lyrics, rng),
    }
}

fn pick<T: Copy>(candidates: &[T], rng: &mut SplitMix64) -> Option<T> {
    if candidates.is_empty() {
        None
    } else {
        Some(candidates[rng.next_below(candidates.len() as u64) as usize])
    }
}

fn title_excerpt(
    lyrics: &[Lyric<'_>],
    song_title: &str,
    has_singer: bool,
    rng: &mut SplitMix64,
) -> Option<LyricsQuizExcerpt> {
    let core = title_core(song_title);
    // 曲名そのものを含む行は答えが書いてあるので出さない (芯が 1 文字の曲名は判定しない)。
    let reveals_title =
        |text: &str| core.chars().count() >= 2 && fold(text).contains(core.as_str());
    let usable = |i: usize| {
        visible_len(lyrics[i].text) >= TITLE_PROMPT_MIN_CHARS && !reveals_title(lyrics[i].text)
    };
    // 続きの行 (同じブロック内) までヒントに出せる行を優先し、無ければ単独の行でもよい。
    let has_next = |i: usize| {
        lyrics
            .get(i + 1)
            .is_some_and(|n| n.block == lyrics[i].block && !reveals_title(n.text))
    };
    let with_next: Vec<usize> = (0..lyrics.len())
        .filter(|&i| usable(i) && has_next(i))
        .collect();
    let prompt = match pick(&with_next, rng) {
        Some(i) => i,
        None => pick(
            &(0..lyrics.len()).filter(|&i| usable(i)).collect::<Vec<_>>(),
            rng,
        )?,
    };
    let context_line = has_next(prompt).then(|| lyrics[prompt + 1].text.to_string());
    let mut hints = Vec::new();
    if context_line.is_some() {
        hints.push(LyricsQuizHintKind::NextLine);
    }
    if has_singer {
        hints.push(LyricsQuizHintKind::Singer);
    }
    Some(LyricsQuizExcerpt {
        prompt: lyrics[prompt].text.to_string(),
        context_line,
        choices: Vec::new(),
        answer: 0,
        fifty_fifty_hidden: Vec::new(),
        hints,
    })
}

fn next_line_excerpt(lyrics: &[Lyric<'_>], rng: &mut SplitMix64) -> Option<LyricsQuizExcerpt> {
    let key = |text: &str| fold(text);
    // 出題行 i と正解 i+1 は同じブロック内・別の文面であること。
    let candidates: Vec<usize> = (0..lyrics.len().saturating_sub(1))
        .filter(|&i| {
            lyrics[i + 1].block == lyrics[i].block && key(lyrics[i].text) != key(lyrics[i + 1].text)
        })
        .collect();
    // 前の行もヒントに出せる出題を優先する。
    let with_prev: Vec<usize> = candidates
        .iter()
        .copied()
        .filter(|&i| i > 0 && lyrics[i - 1].block == lyrics[i].block)
        .collect();

    // 出題行と同じ文面の行 (サビの繰り返し等) に続く行は、どれも正解になりうるので誤答に使わない。
    let build = |i: usize, rng: &mut SplitMix64| -> Option<LyricsQuizExcerpt> {
        let prompt_key = key(lyrics[i].text);
        let answer_key = key(lyrics[i + 1].text);
        let mut excluded: HashSet<String> = HashSet::from([prompt_key.clone(), answer_key]);
        for j in 0..lyrics.len().saturating_sub(1) {
            if key(lyrics[j].text) == prompt_key {
                excluded.insert(key(lyrics[j + 1].text));
            }
        }
        let mut distractors: Vec<&str> = Vec::new();
        let mut seen: HashSet<String> = HashSet::new();
        for l in lyrics {
            let k = key(l.text);
            if !k.is_empty() && !excluded.contains(&k) && seen.insert(k) {
                distractors.push(l.text);
            }
        }
        if distractors.len() < DISTRACTOR_COUNT as usize {
            return None;
        }
        rng.shuffle(&mut distractors);
        distractors.truncate(DISTRACTOR_COUNT as usize);
        let mut choices: Vec<String> = distractors.iter().map(|s| s.to_string()).collect();
        choices.push(lyrics[i + 1].text.to_string());
        rng.shuffle(&mut choices);
        let answer = choices.iter().position(|c| c == lyrics[i + 1].text)? as u32;
        let mut wrong: Vec<u32> = (0..choices.len() as u32).filter(|&p| p != answer).collect();
        rng.shuffle(&mut wrong);
        wrong.truncate(2);
        wrong.sort_unstable();
        let context_line = (i > 0 && lyrics[i - 1].block == lyrics[i].block)
            .then(|| lyrics[i - 1].text.to_string());
        let mut hints = Vec::new();
        if context_line.is_some() {
            hints.push(LyricsQuizHintKind::PreviousLine);
        }
        hints.push(LyricsQuizHintKind::FiftyFifty);
        Some(LyricsQuizExcerpt {
            prompt: lyrics[i].text.to_string(),
            context_line,
            choices,
            answer,
            fifty_fifty_hidden: wrong,
            hints,
        })
    };

    let first = if with_prev.is_empty() {
        &candidates
    } else {
        &with_prev
    };
    let i = pick(first, rng)?;
    build(i, rng)
}

// ---------------------------------------------------------------------------
// ヒントと採点
// ---------------------------------------------------------------------------

/// `revealed` は開けたヒントの数 (`hints` の先頭から)。
pub fn lyrics_quiz_hint_state(
    hints: &[LyricsQuizHintKind],
    revealed: u32,
    answered: bool,
) -> LyricsQuizHintState {
    let revealed = (revealed as usize).min(hints.len());
    LyricsQuizHintState {
        current_value: song_quiz_points(revealed as u32),
        shown: if answered {
            hints.to_vec()
        } else {
            hints[..revealed].to_vec()
        },
        next_hint: if answered {
            None
        } else {
            hints.get(revealed).map(|&kind| LyricsQuizHintOption {
                kind,
                next_value: song_quiz_points(revealed as u32 + 1),
            })
        },
    }
}

/// 解答。`picked` / `answer` は曲名当てなら曲 id、続きはどれなら選択肢の位置 (文字列化)。
pub fn lyrics_quiz_answer(
    revealed: u32,
    picked: &str,
    answer: &str,
    before: &QuizTally,
    session_length: u32,
) -> QuizAnswerOutcome {
    quiz_answer(
        song_quiz_points(revealed),
        revealed,
        picked,
        answer,
        before,
        session_length,
    )
}

/// 4 択が組める最低曲数 (設定画面の案内文用)。
pub fn lyrics_quiz_minimum_pool() -> u32 {
    MINIMUM_POOL
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(id: &str, brand: &str) -> LyricsQuizSongRef {
        LyricsQuizSongRef {
            id: id.into(),
            brand_id: brand.into(),
        }
    }

    fn lyric(text: &str) -> LyricsQuizLine {
        LyricsQuizLine {
            text: text.into(),
            is_lyric: true,
        }
    }

    fn blank() -> LyricsQuizLine {
        LyricsQuizLine {
            text: String::new(),
            is_lyric: false,
        }
    }

    fn ids(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn pool_is_published_songs_in_selected_brands() {
        let songs = vec![
            song("a", "ml"),
            song("b", "ml"),
            song("c", "cg"),
            song("d", "ml"),
        ];
        let est = lyrics_quiz_pool_estimate(&songs, &ids(&["a", "c", "d", "x"]), &ids(&["ml"]));
        assert_eq!(est.song_count, 2);
        assert!(!est.is_sufficient);
        let all = lyrics_quiz_pool_estimate(&songs, &ids(&["a", "b", "c", "d"]), &[]);
        assert_eq!(all.song_count, 4);
        assert!(all.is_sufficient);
    }

    #[test]
    fn session_draws_distinct_songs_with_four_title_choices() {
        let songs: Vec<_> = (0..30)
            .map(|i| song(&format!("s{i}"), if i % 2 == 0 { "ml" } else { "cg" }))
            .collect();
        let published: Vec<String> = songs.iter().map(|s| s.id.clone()).collect();
        let qs = lyrics_quiz_session(&songs, &published, &[], 20, &mut SplitMix64(9));
        assert_eq!(qs.len(), 20);
        let distinct: HashSet<u32> = qs.iter().map(|q| q.song).collect();
        assert_eq!(distinct.len(), 20, "母集団が尽きる前に同じ曲が出た");
        for q in &qs {
            assert_eq!(q.choices.len(), 4);
            assert!(q.choices.contains(&q.song));
            let brand = &songs[q.song as usize].brand_id;
            assert!(
                q.choices
                    .iter()
                    .all(|&c| &songs[c as usize].brand_id == brand),
                "同ブランドが足りているのに他ブランドが混ざった"
            );
        }
    }

    #[test]
    fn session_is_empty_when_pool_is_too_small() {
        let songs = vec![song("a", "ml"), song("b", "ml"), song("c", "ml")];
        assert!(
            lyrics_quiz_session(&songs, &ids(&["a", "b", "c"]), &[], 10, &mut SplitMix64(1))
                .is_empty()
        );
    }

    #[test]
    fn session_is_capped_by_pool_size() {
        let songs: Vec<_> = (0..5).map(|i| song(&format!("s{i}"), "ml")).collect();
        let published: Vec<String> = songs.iter().map(|s| s.id.clone()).collect();
        assert_eq!(
            lyrics_quiz_session(&songs, &published, &[], 20, &mut SplitMix64(1)).len(),
            5
        );
    }

    #[test]
    fn title_excerpt_skips_lines_that_contain_the_title() {
        let lines = vec![
            lyric("お願い！シンデレラ 夢は夢で終われない"),
            lyric("動き始めてる 輝く日のために"),
            lyric("エヴリデイ どんなときも"),
        ];
        for seed in 0..50 {
            let ex = lyrics_quiz_excerpt(
                &lines,
                "お願い！シンデレラ",
                true,
                LyricsQuizMode::Title,
                &mut SplitMix64(seed),
            )
            .unwrap();
            assert!(!ex.prompt.contains("シンデレラ"));
            if let Some(next) = &ex.context_line {
                assert!(!next.contains("シンデレラ"));
            }
        }
    }

    #[test]
    fn title_excerpt_prefers_a_line_with_a_next_line_in_the_same_block() {
        let lines = vec![
            lyric("ひとりだけの長い一行"),
            blank(),
            lyric("ここから二行のブロック"),
            lyric("続きの二行目もある"),
        ];
        for seed in 0..30 {
            let ex = lyrics_quiz_excerpt(
                &lines,
                "曲",
                true,
                LyricsQuizMode::Title,
                &mut SplitMix64(seed),
            )
            .unwrap();
            assert_eq!(ex.prompt, "ここから二行のブロック");
            assert_eq!(ex.context_line.as_deref(), Some("続きの二行目もある"));
            assert_eq!(
                ex.hints,
                vec![LyricsQuizHintKind::NextLine, LyricsQuizHintKind::Singer]
            );
        }
    }

    #[test]
    fn title_excerpt_is_none_without_usable_lines() {
        let lines = vec![lyric("Yeah!"), lyric("Hey")];
        assert!(lyrics_quiz_excerpt(
            &lines,
            "曲",
            true,
            LyricsQuizMode::Title,
            &mut SplitMix64(1)
        )
        .is_none());
    }

    #[test]
    fn next_line_excerpt_has_one_correct_continuation() {
        let lines = vec![
            lyric("サビの一行目"),
            lyric("答えその一"),
            blank(),
            lyric("Aメロ"),
            lyric("Bメロ"),
            blank(),
            lyric("サビの一行目"),
            lyric("答えその二"),
            lyric("締めの行"),
            lyric("最後の行"),
        ];
        for seed in 0..100 {
            let ex = lyrics_quiz_excerpt(
                &lines,
                "曲",
                false,
                LyricsQuizMode::NextLine,
                &mut SplitMix64(seed),
            )
            .unwrap();
            assert_eq!(ex.choices.len(), 4);
            let distinct: HashSet<&String> = ex.choices.iter().collect();
            assert_eq!(distinct.len(), 4);
            assert!(!ex.choices.contains(&ex.prompt));
            if ex.prompt == "サビの一行目" {
                let others: Vec<_> = ex
                    .choices
                    .iter()
                    .enumerate()
                    .filter(|(i, _)| *i as u32 != ex.answer)
                    .map(|(_, c)| c.as_str())
                    .collect();
                assert!(
                    !others.contains(&"答えその一") && !others.contains(&"答えその二"),
                    "繰り返しの行の別の続きが誤答に混ざった"
                );
            }
            assert_eq!(ex.fifty_fifty_hidden.len(), 2);
            assert!(!ex.fifty_fifty_hidden.contains(&ex.answer));
            assert_eq!(ex.hints.last(), Some(&LyricsQuizHintKind::FiftyFifty));
        }
    }

    #[test]
    fn next_line_excerpt_is_none_for_too_short_lyrics() {
        let lines = vec![lyric("一"), lyric("二"), lyric("三")];
        assert!(lyrics_quiz_excerpt(
            &lines,
            "曲",
            false,
            LyricsQuizMode::NextLine,
            &mut SplitMix64(1)
        )
        .is_none());
    }

    #[test]
    fn hint_state_steps_down_points() {
        let hints = [LyricsQuizHintKind::NextLine, LyricsQuizHintKind::Singer];
        let s0 = lyrics_quiz_hint_state(&hints, 0, false);
        assert_eq!(s0.current_value, 3);
        assert_eq!(
            s0.next_hint,
            Some(LyricsQuizHintOption {
                kind: LyricsQuizHintKind::NextLine,
                next_value: 2
            })
        );
        let s2 = lyrics_quiz_hint_state(&hints, 2, false);
        assert_eq!(s2.current_value, 1);
        assert_eq!(s2.next_hint, None);
        assert_eq!(s2.shown, hints.to_vec());
        let answered = lyrics_quiz_hint_state(&hints, 0, true);
        assert_eq!(answered.shown, hints.to_vec());
        assert_eq!(answered.next_hint, None);
    }

    #[test]
    fn answer_scores_by_revealed_hints() {
        let out = lyrics_quiz_answer(1, "2", "2", &QuizTally::default(), 10);
        assert!(out.is_correct);
        assert_eq!(out.earned_points, 2);
        let wrong = lyrics_quiz_answer(0, "a", "b", &out.tally, 2);
        assert!(!wrong.is_correct);
        assert_eq!(wrong.tally.points, 2);
        assert!(wrong.is_last_question);
    }
}
