//! 公演群のセトリの「型」と、曲ごとの「どこで歌われるか」。
//!
//! # これは予想ではない
//!
//! ここが出すのは**過去がどうだったか**だけ。「この曲が来そう」の判定も、
//! 枠ごとの重みづけも書かない。当たらなかったときに直しようがないし、
//! DB が予想を持っているように見えると、根拠の無い数字が「データベースの答え」
//! として流通してしまう。予想は、この事実を読んだ呼び手 (LLM) が組み立てる。
//!
//! # なぜコアに置くか
//!
//! 「1 曲目に何が来やすいか」「アンコールは何曲か」「ソロ枠が何本あるか」は、
//! どれも *OS SDK に触らずに書ける判断*。Swift / Kotlin / ツール面のどこかに書くと、
//! 同じ問いに別の答えが出る土壌になる。曲順は [`crate::domain::setlist_sections`]、
//! 原唱者の濾しは [`crate::domain::snapshot::Snapshot::song_artists`]、
//! 派生曲の扱いは [`crate::domain::song_list_queries::is_hidden_variant`] が正本で、
//! **このファイルはそれらを組み合わせて数えるだけ**にする。

use crate::domain::setlist_sections::{numbered_setlist, section_label, track_number, ENCORE_LABEL};
use crate::domain::snapshot::Snapshot;
use std::collections::{HashMap, HashSet};

/// 数の散らばり。平均を出さないのは、公演数が一桁の集合で平均を見せると
/// 「23.17 曲」のような、根拠の回数より精度が高く見える数字になるため。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Spread {
    /// 標本数 (この数から出した値か、を呼び手が判断できるように必ず添える)。
    pub samples: u32,
    pub min: u32,
    /// 中央値。標本が偶数のときは上側 (`sorted[n/2]`) を採る。
    /// 2 つの中間を取ると整数でなくなり、「曲数」として読めない値になる。
    pub median: u32,
    pub max: u32,
}

impl Spread {
    /// 標本が 1 つも無ければ `None`。0 を返すと「0 曲の公演があった」と読めてしまう。
    pub fn of(mut values: Vec<u32>) -> Option<Self> {
        if values.is_empty() {
            return None;
        }
        values.sort_unstable();
        Some(Self {
            samples: values.len() as u32,
            min: values[0],
            median: values[values.len() / 2],
            max: values[values.len() - 1],
        })
    }
}

/// 「その枠によく来る曲」1 行。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SlotTally {
    pub song_id: String,
    /// その枠に入った公演数。
    pub times: u32,
}

/// 区切り (section) ごとの曲数の傾向。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SectionShape {
    /// 見出し。`None` は区切り無し = 本編。綴りの畳み込みは
    /// [`section_label`] が正本 (`encore` / `ENCORE` / `アンコール` は 1 つになる)。
    pub label: Option<String>,
    /// その区切りの曲数の散らばり (**その区切りがあった公演だけ**が標本なので、
    /// `songs.samples` がそのまま「この区切りがあった公演数」)。
    pub songs: Spread,
}

impl SectionShape {
    /// この区切りがあった公演数。標本数と同じものなので欄は持たない
    /// (持つと片方だけ書き換わる導出フィールドになる)。
    pub fn shows(&self) -> u32 {
        self.songs.samples
    }
}

/// 公演群のセトリの型。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetlistShape {
    /// 標本にした公演 (セトリが入っているものだけ)。渡された並びを保つ。
    ///
    /// 公演数ではなく**添字そのもの**を返すのは、呼び手が「どの公演から出た数字か」を
    /// 応答に載せられるようにするため。以前はツール面が同じ「セトリがあるか」の
    /// 判定をもう一度回していて、判定が片方だけ変わると標本と内訳が食い違った。
    pub sampled: Vec<u32>,
    /// 条件には当たるがセトリが未入力の公演数。**0 でも必ず持つ** —
    /// 「まだセトリが無い公演」を標本から落とした事実を隠すと、
    /// 少ない標本から出した型を全公演の型と取り違える。
    pub shows_without_setlist: u32,
    /// 1 公演の曲数。
    pub song_count: Option<Spread>,
    /// 区切りごとの曲数。並びは公演数の多い順、同数は見出し順。
    pub sections: Vec<SectionShape>,
    /// 1 曲目に来た曲。
    pub openers: Vec<SlotTally>,
    /// アンコール (畳んだ見出しが [`ENCORE_LABEL`] の区切り) に来た曲。
    pub encore: Vec<SlotTally>,
    /// 最後の曲 (締め)。アンコールがあればその最後の曲になる。
    pub closers: Vec<SlotTally>,
    /// 1 公演あたりのソロ枠 (**その披露を 1 人で歌った曲**) の本数。
    ///
    /// 原唱者が 1 人かどうかでは数えない。14thLIVE DAY2 は原唱者ベースだと 15 本に
    /// なるが、実際のソロ枠は 7 本しかない — 差の 8 曲は `To...` を 3 人、
    /// `Be My Boy` を 2 人、のように**ソロ曲を複数人で歌った**回だから。
    /// 「ソロ枠」と名乗る以上、数えるのはその日 1 人で立った曲。
    /// 曲そのものの性質 (原唱者が 1 人か) は [`crate::domain::song_list_queries::is_solo_song`]。
    pub solo_slots: Option<Spread>,
    /// ソロ枠のうち、主演が歌った本数。主演が立っている公演だけを標本にする。
    ///
    /// 実データでは 8 公演すべてで [`Self::solo_slots`] と一致する
    /// (主演公演でソロを歌うのは主演だけ)。一致は規則ではなく今のところの事実なので、
    /// 2 本の数として返して呼び手に見せる。
    pub lead_solo_slots: Option<Spread>,
    /// 主演 (`cast_role` が `lead`) 1 人が歌った曲数。主演が 2 人いる公演なら値も 2 つ入る。
    ///
    /// 主演が立っていない公演は標本に入らないので、`samples` は [`Self::shows`] と一致しない。
    /// 一致しない事実こそが「主演の記録がどれだけあるか」なので、埋めも丸めもしない。
    pub lead_songs: Option<Spread>,
    /// 主演以外の出演者 (`cast_role` が `member`) 1 人が歌った曲数。
    ///
    /// `lead_songs` だけでは「19 曲」が多いのか並なのか読めない。比較対象を同じ標本から
    /// 出して必ず添える (呼び手が別ツールで数え直すと、数え方がそこで枝分かれする)。
    pub member_songs: Option<Spread>,
    /// 主演 1 人が歌った曲が、その公演の全曲の何 % か。
    ///
    /// 曲数だけでは公演をまたいで比べられない。同じ「主演公演」でも全 23 曲の回と
    /// 全 39 曲の回があり、23 曲中 14 曲と 39 曲中 17 曲では後者のほうが数は多いのに
    /// 割合は小さい。**規模の違う公演を 1 つの Spread に混ぜた瞬間に絶対値は嘘になる**。
    pub lead_share_percent: Option<Spread>,
    /// 主演以外 1 人が歌った曲の割合 (%)。[`Self::lead_share_percent`] の比較対象。
    pub member_share_percent: Option<Spread>,
}

impl SetlistShape {
    /// 標本にした公演数。
    pub fn shows(&self) -> u32 {
        self.sampled.len() as u32
    }
}

/// 公演群のセトリの型を出す。
///
/// `shows` は公演の添字 (絞り込みは呼び手の責務)。`top` は枠ごとのランキングの件数。
pub fn setlist_shape(snap: &Snapshot, shows: &[u32], top: usize) -> SetlistShape {
    let sampled: Vec<u32> = shows
        .iter()
        .copied()
        .filter(|&s| !snap.setlist_items_by_show[s as usize].is_empty())
        .collect();

    let mut song_counts: Vec<u32> = Vec::new();
    let mut solo_counts: Vec<u32> = Vec::new();
    let mut lead_solo_counts: Vec<u32> = Vec::new();
    let mut lead = RoleTally::default();
    let mut member = RoleTally::default();
    // 区切り → その区切りがあった公演ごとの曲数
    let mut sections: HashMap<Option<String>, Vec<u32>> = HashMap::new();
    let mut openers: HashMap<u32, u32> = HashMap::new();
    let mut encore: HashMap<u32, u32> = HashMap::new();
    let mut closers: HashMap<u32, u32> = HashMap::new();
    for &show in &sampled {
        // 公演内の並びは numbered_setlist が正本 (生の position は公演をまたぐ通し番号)。
        // 曲順そのものはここでは使わないので、Vec に集めずに 1 度だけ舐める。
        let (mut first, mut last, mut count) = (None, None, 0u32);
        let mut per_section: HashMap<Option<String>, u32> = HashMap::new();
        let (mut solos, mut lead_solos) = (0u32, 0u32);
        let mut sung_by_idol: HashMap<u32, u32> = HashMap::new();
        let leads: HashSet<u32> = snap.cast_by_show[show as usize]
            .iter()
            .filter(|l| l.cast_role == "lead")
            .map(|l| l.idol)
            .collect();

        for (_, item) in numbered_setlist(snap, show) {
            let it = &snap.setlist_items[item as usize];
            first.get_or_insert(it.song);
            last = Some(it.song);
            count += 1;

            let label = section_label(it.section.as_deref());
            if label.as_deref() == Some(ENCORE_LABEL) {
                *encore.entry(it.song).or_insert(0) += 1;
            }
            *per_section.entry(label).or_insert(0) += 1;

            let performers = &snap.performers_by_item[item as usize];
            // 歌唱者が未登録の行 (全 13,351 行中 142 行) は 0 人なのでソロに数えない。
            // 分からないものを数えると、古い公演ほどソロ枠が多いという嘘になる。
            if let [only] = performers[..] {
                solos += 1;
                if leads.contains(&only) {
                    lead_solos += 1;
                }
            }

            for &performer in performers {
                *sung_by_idol.entry(performer).or_insert(0) += 1;
            }
        }

        song_counts.push(count);
        solo_counts.push(solos);
        // 主演が立っていない公演の 0 本を混ぜない (lead_songs と同じ扱い)。
        if !leads.is_empty() {
            lead_solo_counts.push(lead_solos);
        }
        // 数えるのは出演者表に役割がある人だけ。セトリにしか出てこない人 (ゲスト等) は
        // 主演かどうかが決まらないので、どちらの標本にも入れない。歌っていない出演者は
        // 0 曲として数える — 落とすと「出たのに 1 曲も歌わなかった」が見えなくなる。
        for link in &snap.cast_by_show[show as usize] {
            let tally = match link.cast_role.as_str() {
                "lead" => &mut lead,
                "member" => &mut member,
                _ => continue,
            };
            tally.push(sung_by_idol.get(&link.idol).copied().unwrap_or(0), count);
        }
        for (label, n) in per_section {
            sections.entry(label).or_default().push(n);
        }
        if let Some(song) = first {
            *openers.entry(song).or_insert(0) += 1;
        }
        if let Some(song) = last {
            *closers.entry(song).or_insert(0) += 1;
        }
    }

    let mut section_rows: Vec<SectionShape> = sections
        .into_iter()
        .filter_map(|(label, counts)| Spread::of(counts).map(|songs| SectionShape { label, songs }))
        .collect();
    // 公演数の多い順。同数は見出し順 (区切り無し = 本編を先頭に)。
    section_rows.sort_by(|a, b| b.shows().cmp(&a.shows()).then(a.label.cmp(&b.label)));

    SetlistShape {
        shows_without_setlist: (shows.len() - sampled.len()) as u32,
        sampled,
        song_count: Spread::of(song_counts),
        sections: section_rows,
        openers: ranked(snap, openers, top),
        encore: ranked(snap, encore, top),
        closers: ranked(snap, closers, top),
        solo_slots: Spread::of(solo_counts),
        lead_solo_slots: Spread::of(lead_solo_counts),
        lead_songs: Spread::of(lead.songs),
        member_songs: Spread::of(member.songs),
        lead_share_percent: Spread::of(lead.shares),
        member_share_percent: Spread::of(member.shares),
    }
}

/// 役割ごとの標本。曲数と割合を必ず対で積む — 別々の Vec に積むと、片方だけ
/// 積み忘れても動いてしまい、同じ標本から出したはずの数字が食い違う。
#[derive(Default)]
struct RoleTally {
    songs: Vec<u32>,
    shares: Vec<u32>,
}

impl RoleTally {
    /// `sung` = その人が歌った曲数、`total` = その公演の全曲数。
    fn push(&mut self, sung: u32, total: u32) {
        self.songs.push(sung);
        self.shares.push(percent(sung, total));
    }
}

/// 割合 (%) を四捨五入で。`total` が 0 の公演は標本に入らないので 0 除算は起きないが、
/// 呼び違いで落ちるより 0 を返すほうがよい (割合 0 % は「歌っていない」と同じ意味)。
fn percent(part: u32, total: u32) -> u32 {
    if total == 0 {
        return 0;
    }
    (part * 100 + total / 2) / total
}

/// 回数の多い順。同数は曲 id 順で決定的に (`performance_stats` と同じ流儀)。
fn ranked(snap: &Snapshot, tally: HashMap<u32, u32>, top: usize) -> Vec<SlotTally> {
    let mut rows: Vec<SlotTally> = tally
        .into_iter()
        .map(|(song, times)| SlotTally { song_id: snap.songs[song as usize].id.clone(), times })
        .collect();
    rows.sort_by(|a, b| b.times.cmp(&a.times).then(a.song_id.cmp(&b.song_id)));
    rows.truncate(top);
    rows
}

// ---------------------------------------------------------------------------
// 曲ごとの位置
// ---------------------------------------------------------------------------

/// 公演内の大まかな位置。曲順を公演の曲数で正規化して 3 つに割る。
///
/// 曲数が公演ごとに違う (実データで 1〜34 曲) ので、「7 曲目」のような生の順番では
/// 公演をまたいで比べられない。`(順番-1) * 3 / 曲数` で割ると、23 曲の公演でも
/// 12 曲の公演でも同じ「3 等分のどこか」になる。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(usize)]
pub enum Phase {
    Early = 0,
    Middle = 1,
    Late = 2,
}

impl Phase {
    /// 並びは [`SongPositionProfile::phases`] の添字と同じ。
    pub const ALL: [Self; 3] = [Self::Early, Self::Middle, Self::Late];

    pub fn of(rank: usize, total: usize) -> Self {
        if total == 0 {
            return Self::Early;
        }
        match (rank.saturating_sub(1) * 3) / total {
            0 => Self::Early,
            1 => Self::Middle,
            _ => Self::Late,
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            Self::Early => "early",
            Self::Middle => "middle",
            Self::Late => "late",
        }
    }
}

/// ある曲が「どこで」歌われたか。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SongPositionProfile {
    /// 披露回数 (セトリ行の数)。
    pub performances: u32,
    /// 1 曲目だった回数。
    pub opener: u32,
    /// その公演の最後の曲だった回数。
    pub closer: u32,
    /// アンコール枠だった回数。
    pub encore: u32,
    /// 区切りごとの回数。並びは回数の多い順、同数は見出し順。
    pub sections: Vec<(Option<String>, u32)>,
    /// 序盤 / 中盤 / 終盤の回数。添字は [`Phase`] の順 (`Early` / `Middle` / `Late`)。
    /// 3 本の平行フィールドにしないのは、鍵の名前 (`early` / …) を呼び手が手書きすると
    /// [`Phase::key`] と二重管理になるため。
    pub phases: [u32; 3],
}

impl SongPositionProfile {
    /// その位置だった回数。
    pub fn phase(&self, phase: Phase) -> u32 {
        self.phases[phase as usize]
    }
}

/// 曲ごとの位置の傾向。未知の曲 id は全部 0 (呼び手が「無い」と判断する材料は
/// id の解決側が持つので、ここでは落ちないことだけを保証する)。
pub fn song_position_profile(snap: &Snapshot, song_id: &str) -> SongPositionProfile {
    let mut p = SongPositionProfile::default();
    let Some(&song) = snap.song_index_by_id.get(song_id) else { return p };
    // 披露回数は前計算済みの `performance_counts` が正本 (数え直さない、という
    // stats_queries の既存規約。数え直すと同じ応答に 2 つの回数が載る)。
    p.performances = snap.performance_counts[song as usize];

    let mut sections: HashMap<Option<String>, u32> = HashMap::new();
    for &item in snap.setlist_items_by_song.get(song as usize).map_or(&[][..], Vec::as_slice) {
        let show = snap.setlist_items[item as usize].show;
        let total = snap.setlist_items_by_show[show as usize].len();
        // 「その披露が何曲目か」は setlist_sections::track_number が正本。
        // 同じ数え方をここに書くと、曲順の規則が変わったとき片方だけ古くなる。
        let rank = track_number(snap, item);
        if rank == 0 {
            continue;
        }
        if rank == 1 {
            p.opener += 1;
        }
        if rank == total {
            p.closer += 1;
        }
        let label = section_label(snap.setlist_items[item as usize].section.as_deref());
        if label.as_deref() == Some(ENCORE_LABEL) {
            p.encore += 1;
        }
        *sections.entry(label).or_insert(0) += 1;
        p.phases[Phase::of(rank, total) as usize] += 1;
    }

    let mut rows: Vec<(Option<String>, u32)> = sections.into_iter().collect();
    rows.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    p.sections = rows;
    p
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;
    use crate::domain::song_list_queries::is_solo_song;

    /// 主演公演 (cast_role='lead' の行がある公演) の添字。
    fn lead_shows(snap: &Snapshot) -> Vec<u32> {
        (0..snap.shows.len() as u32)
            .filter(|&s| snap.cast_by_show[s as usize].iter().any(|l| l.cast_role == "lead"))
            .collect()
    }

    #[test]
    fn 主演は他の出演者よりはっきり多く歌う() {
        let snap = bundle_snapshot();
        let shape = setlist_shape(snap, &lead_shows(snap), 5);
        let lead = shape.lead_songs.clone().expect("主演公演を標本にしたので主演の標本がある");
        let member = shape.member_songs.clone().expect("同じ公演の他の出演者も標本になる");

        // 主演は「その公演の主役」なので、最も歌わなかった主演でも
        // 他の出演者の中央値を上回る。逆転していたら cast_role か歌唱者データが壊れている。
        assert!(
            lead.min > member.median,
            "主演の最小 {} が他の中央値 {} 以下: {lead:?} / {member:?}",
            lead.min,
            member.median
        );
        // 1 公演に主演が 2 人いる形式なので、標本は公演数より多くなる。
        assert!(lead.samples >= shape.shows(), "{lead:?} vs shows={}", shape.shows());
    }

    #[test]
    fn ソロ枠はその日_1_人で歌った曲だけを数える() {
        let snap = bundle_snapshot();
        // 14thLIVE DAY2。原唱者ベースなら 15 本になるが、実際のソロ枠は 7 本。
        let day2 = snap.show_index_by_id["sh_the_idolm@ster_million_live_14thlive_2"];
        let shape = setlist_shape(snap, &[day2], 5);
        assert_eq!(shape.solo_slots.as_ref().unwrap().max, 7, "{:?}", shape.solo_slots);

        // 原唱者ベースの本数 (= 以前の数え方) と食い違うことを明示的に固定する。
        // 一致してしまったら、この公演がテストの題材として役に立たなくなっている。
        let by_artist = snap.setlist_items_by_show[day2 as usize]
            .iter()
            .filter(|&&i| is_solo_song(snap, snap.setlist_items[i as usize].song))
            .count();
        assert!(by_artist > 7, "原唱者ベースは {by_artist} 本で、歌唱者ベースより多いはず");
    }

    #[test]
    fn 割合は四捨五入する() {
        // 23 曲中 14 曲 = 60.87 % → 61
        assert_eq!(percent(14, 23), 61);
        // 39 曲中 17 曲 = 43.59 % → 44
        assert_eq!(percent(17, 39), 44);
        assert_eq!(percent(0, 23), 0);
        assert_eq!(percent(23, 23), 100);
        assert_eq!(percent(1, 0), 0, "0 除算で落ちない");
    }

    #[test]
    fn 主演がいない公演を混ぜても主演の標本は増えない() {
        let snap = bundle_snapshot();
        let lead_only = lead_shows(snap);
        let mut mixed = lead_only.clone();
        // 主演が立っていない公演を適当に足す。lead_songs は増えず、member_songs だけ増える。
        mixed.extend(
            (0..snap.shows.len() as u32)
                .filter(|&s| {
                    !snap.cast_by_show[s as usize].iter().any(|l| l.cast_role == "lead")
                        && !snap.setlist_items_by_show[s as usize].is_empty()
                        && !snap.cast_by_show[s as usize].is_empty()
                })
                .take(20),
        );

        let a = setlist_shape(snap, &lead_only, 5);
        let b = setlist_shape(snap, &mixed, 5);
        assert_eq!(a.lead_songs, b.lead_songs, "主演のいない公演が主演の標本に混ざっている");
        assert!(
            b.member_songs.as_ref().unwrap().samples > a.member_songs.as_ref().unwrap().samples,
            "出演者側の標本は増えるはず"
        );
    }

    #[test]
    fn spread_は標本が無ければ_none_偶数なら上側の中央値() {
        assert_eq!(Spread::of(vec![]), None);
        assert_eq!(
            Spread::of(vec![3, 1, 2]),
            Some(Spread { samples: 3, min: 1, median: 2, max: 3 })
        );
        // 偶数は上側。1,2,3,4 → 3
        assert_eq!(Spread::of(vec![4, 1, 3, 2]).unwrap().median, 3);
    }

    #[test]
    fn 位置は曲数で正規化される() {
        // 3 曲なら 1 曲ずつ。
        assert_eq!(Phase::of(1, 3), Phase::Early);
        assert_eq!(Phase::of(2, 3), Phase::Middle);
        assert_eq!(Phase::of(3, 3), Phase::Late);
        // 23 曲でも同じ 3 等分になる (生の順番では公演をまたいで比べられない)。
        assert_eq!(Phase::of(1, 23), Phase::Early);
        assert_eq!(Phase::of(8, 23), Phase::Early);
        assert_eq!(Phase::of(9, 23), Phase::Middle);
        assert_eq!(Phase::of(16, 23), Phase::Middle);
        assert_eq!(Phase::of(17, 23), Phase::Late);
        assert_eq!(Phase::of(23, 23), Phase::Late);
        // 1 曲だけの公演は最初で最後。落ちないことだけ固定する。
        assert_eq!(Phase::of(1, 1), Phase::Early);
        assert_eq!(Phase::of(1, 0), Phase::Early);
    }

    #[test]
    fn 主演公演の型が実データで取れる() {
        let s = bundle_snapshot();
        let shows = lead_shows(s);
        assert!(shows.len() >= 6, "主演公演が少なすぎる: {}", shows.len());
        let shape = setlist_shape(s, &shows, 5);

        // セトリ未入力の公演は標本から外れるが、外した事実は残る。
        assert_eq!(shape.shows() + shape.shows_without_setlist, shows.len() as u32);
        assert!(shape.shows() >= 6, "セトリのある主演公演が少ない: {}", shape.shows());
        // 標本にした公演は必ずセトリを持つ。
        assert!(shape.sampled.iter().all(|&x| !s.setlist_items_by_show[x as usize].is_empty()));

        let count = shape.song_count.clone().expect("曲数の標本がある");
        assert_eq!(count.samples, shape.shows());
        assert!(count.min <= count.median && count.median <= count.max);
        assert!(count.min >= 10, "主演公演が 10 曲未満なのはおかしい: {count:?}");

        // 1 曲目・締めは公演ごとに 1 つずつしか立たないので、合計が公演数を超えない。
        assert!(shape.openers.iter().map(|t| t.times).sum::<u32>() <= shape.shows());
        assert!(shape.closers.iter().map(|t| t.times).sum::<u32>() <= shape.shows());
        // 降順に並んでいる。
        for w in shape.openers.windows(2) {
            assert!(w[0].times >= w[1].times);
        }
        // 区切りには必ず本編 (区切り無し) が含まれ、いちばん多い。
        assert_eq!(shape.sections[0].label, None, "{:?}", shape.sections);
        // ソロ枠は「原唱者 1 人の曲」なので 1 公演の曲数を超えない。
        let solo = shape.solo_slots.clone().expect("ソロ枠の標本がある");
        assert!(solo.max <= count.max);
    }

    #[test]
    fn アンコールの綴り違いは_1_つに畳まれる() {
        let s = bundle_snapshot();
        // 実データの主演公演には `encore` と `ENCORE` が混在している。
        let shape = setlist_shape(s, &lead_shows(s), 5);
        let labels: Vec<&str> =
            shape.sections.iter().filter_map(|x| x.label.as_deref()).collect();
        assert!(labels.contains(&ENCORE_LABEL), "{labels:?}");
        // その区切りがあった公演数は標本数そのもの (導出フィールドを持たない)。
        assert!(shape.sections.iter().all(|x| x.shows() == x.songs.samples));
        assert!(!labels.iter().any(|l| l.eq_ignore_ascii_case("encore")), "{labels:?}");
        assert!(!shape.encore.is_empty(), "アンコール枠の曲が拾えていない");
    }

    #[test]
    fn 曲の位置は披露回数に分かれて収まる() {
        let s = bundle_snapshot();
        // いちばん多く歌われている曲で見る。
        let (top, _) = bundle_snapshot()
            .performance_counts
            .iter()
            .enumerate()
            .max_by_key(|(_, &n)| n)
            .expect("曲がある");
        let id = s.songs[top].id.clone();
        let p = song_position_profile(s, &id);

        assert!(p.performances > 0);
        assert_eq!(p.phases.iter().sum::<u32>(), p.performances, "位置の合計が回数と合わない");
        // 添字と Phase が一致している (JSON の鍵名は Phase::key が正本)。
        assert_eq!(p.phase(Phase::Late), p.phases[2]);
        assert_eq!(
            p.sections.iter().map(|(_, n)| n).sum::<u32>(),
            p.performances,
            "区切りの合計が回数と合わない"
        );
        assert!(p.opener <= p.performances && p.closer <= p.performances);
        assert!(p.encore <= p.performances);
        // アンコールは終盤に含まれるので、終盤の回数以下になるはず。
        assert!(p.encore <= p.phase(Phase::Late), "アンコールが終盤より多い: {p:?}");
    }
}
