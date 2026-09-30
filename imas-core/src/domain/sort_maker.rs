//! ソートメーカー: 2 つずつ「どっちが好き？」を答えるだけで順位表を作る。
//!
//! 曲とアイドルの両方で使う。対象の並び (id 列) は各 OS が決めて渡し、ここは
//! **添字だけ**を扱う (何を比べているかは知らない)。
//!
//! ## 状態は「シード + 答えの列」だけ
//!
//! 途中の状態 (どこまで並んだか・次に何を出すか) は保存しない。毎回
//! `answers` を頭から再生して作り直す。これで
//! - 途中保存は答えの列を書くだけ (ソート途中の木を直列化しなくてよい)
//! - 「1 つ戻る」は答えの末尾を 1 つ落とすだけ
//! - iOS / Android で同じシードと答えなら同じ対戦が出る
//! が同時に成り立つ。再生は二分探索の比較回数ぶんしか回らないので、数千件でも軽い。
//!
//! ## 並べ方: 引き分けありの二分挿入
//!
//! 順位表は「同順位のかたまり」の列 (上位が先頭)。新しい 1 件を、かたまりの
//! 代表と二分探索で比べて差し込む。引き分けならそのかたまりに入って終わるので、
//! 「どっちも好き」が多いほど対戦が減る。比較回数は約 n log₂ n で、
//! 対話型の並べ替えとしてはほぼ最小 (マージソートと同程度で、実装が単純)。
//!
//! ## 上位 K 位だけ決める
//!
//! 全順位は n が大きいと数千戦になる。`top_k > 0` なら順位表を K 件に保ち、
//! 埋まった後の新顔はまず「いまの K 位」と比べる。負けたらその場で圏外
//! (1 戦で済む)。勝ったときだけ中を二分探索する。n 件なら概ね n + K log₂ K 戦。
//!
//! ## 左右の出し方
//!
//! 新顔がいつも同じ側に出ると位置の癖 (右ばかり押す) が結果に混ざるので、
//! 何戦目かとシードから左右を決める。答えは「左/右/引き分け」で受け、
//! 再生時に同じ規則で「新顔の勝ち/負け」へ読み替える。

use crate::domain::prng::SplitMix64;

/// 1 戦の答え。画面に出した左右で答える。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SortMakerChoice {
    Left,
    Right,
    /// 引き分け (どっちも同じくらい)。
    Tie,
}

/// 次に出す対戦。値は対象列の添字。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct SortMakerPair {
    pub left: u32,
    pub right: u32,
}

/// 順位表の 1 行。同順位 (引き分け) は同じ `rank` になる。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct SortMakerRankEntry {
    pub item: u32,
    /// 1 始まり。同順位の次は飛ぶ (1, 1, 3)。
    pub rank: u32,
}

/// 答えを再生した結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SortMakerState {
    /// 次の対戦。終わっていれば `None`。
    pub pair: Option<SortMakerPair>,
    /// 実際に使った答えの数 (`answers` が長すぎた分は数えない)。
    pub answered: u32,
    /// 残りの対戦数の見積り (終わっていれば 0)。
    pub estimated_remaining: u32,
    /// 進み具合 0–100。終わるまで 100 にはしない。
    pub progress_percent: u32,
    /// いまの順位表 (上位から)。途中なら「ここまでに並べた分」の暫定順位。
    /// 上位 K 位モードでは圏外になったものは載らない。
    pub ranking: Vec<SortMakerRankEntry>,
    pub is_finished: bool,
}

/// 並べ替えの設定。対象数・上位何位まで決めるか・シード。
#[derive(Clone, Copy, Debug)]
pub struct SortMakerConfig {
    pub item_count: u32,
    /// 0 = 全順位を決める。
    pub top_k: u32,
    pub seed: u64,
}

impl SortMakerConfig {
    /// 実際に使う K (全順位なら対象数)。
    fn cap(&self) -> usize {
        if self.top_k == 0 || self.top_k >= self.item_count {
            self.item_count as usize
        } else {
            self.top_k as usize
        }
    }
}

/// 新顔が今の比較相手に対してどうだったか。
#[derive(Clone, Copy, PartialEq, Eq)]
enum Outcome {
    Better,
    Worse,
    Same,
}

/// 1 件を差し込んでいる最中の探索範囲 (かたまりの添字で半開区間)。
struct Insertion {
    item: u32,
    lo: usize,
    hi: usize,
    /// 上位 K 位モードで、まず K 位と比べる段階か。
    boundary_check: bool,
}

struct Sorter {
    config: SortMakerConfig,
    order: Vec<u32>,
    /// 同順位のかたまりの列 (上位が先頭)。
    groups: Vec<Vec<u32>>,
    /// 次に差し込む `order` の位置。
    next: usize,
    current: Option<Insertion>,
    answered: u32,
}

impl Sorter {
    fn new(config: SortMakerConfig) -> Self {
        let mut order: Vec<u32> = (0..config.item_count).collect();
        SplitMix64(config.seed).shuffle(&mut order);
        let mut s = Sorter { config, order, groups: Vec::new(), next: 0, current: None, answered: 0 };
        if let Some(&first) = s.order.first() {
            s.groups.push(vec![first]);
            s.next = 1;
        }
        s.advance();
        s
    }

    fn kept_count(&self) -> usize {
        self.groups.iter().map(Vec::len).sum()
    }

    /// 比較が要らない限り先へ進め、次の比較を `current` に置く。
    fn advance(&mut self) {
        while self.current.is_none() && self.next < self.order.len() {
            let item = self.order[self.next];
            self.next += 1;
            let full = self.kept_count() >= self.config.cap();
            self.current = Some(Insertion {
                item,
                lo: 0,
                hi: self.groups.len(),
                boundary_check: full,
            });
        }
    }

    /// 今の比較で新顔と比べる相手のかたまり。
    fn pivot_group(&self) -> Option<usize> {
        let ins = self.current.as_ref()?;
        Some(if ins.boundary_check { self.groups.len() - 1 } else { (ins.lo + ins.hi) / 2 })
    }

    fn pair(&self) -> Option<SortMakerPair> {
        let ins = self.current.as_ref()?;
        let pivot = self.groups[self.pivot_group()?][0];
        // 何戦目かとシードで左右を決める (新顔が同じ側に偏らないように)。
        let new_on_left = SplitMix64(self.config.seed ^ (self.answered as u64 + 1).wrapping_mul(0xA24BAED4963EE407))
            .next_u64()
            & 1
            == 0;
        Some(if new_on_left {
            SortMakerPair { left: ins.item, right: pivot }
        } else {
            SortMakerPair { left: pivot, right: ins.item }
        })
    }

    fn apply(&mut self, choice: SortMakerChoice) {
        let Some(pair) = self.pair() else { return };
        let Some(pivot_index) = self.pivot_group() else { return };
        let Some(mut ins) = self.current.take() else { return };
        let new_is_left = pair.left == ins.item;
        let outcome = match (choice, new_is_left) {
            (SortMakerChoice::Tie, _) => Outcome::Same,
            (SortMakerChoice::Left, true) | (SortMakerChoice::Right, false) => Outcome::Better,
            _ => Outcome::Worse,
        };
        self.answered += 1;

        if ins.boundary_check {
            match outcome {
                // K 位に負けた → 圏外。
                Outcome::Worse => {}
                Outcome::Same => {
                    self.groups[pivot_index].push(ins.item);
                    self.trim();
                }
                // K 位より上 → 最後のかたまりより上のどこか。
                Outcome::Better => {
                    ins.boundary_check = false;
                    ins.hi = pivot_index;
                    self.resume_or_insert(ins);
                }
            }
        } else {
            match outcome {
                Outcome::Same => {
                    self.groups[pivot_index].push(ins.item);
                    self.trim();
                }
                Outcome::Better => {
                    ins.hi = pivot_index;
                    self.resume_or_insert(ins);
                }
                Outcome::Worse => {
                    ins.lo = pivot_index + 1;
                    self.resume_or_insert(ins);
                }
            }
        }
        self.advance();
    }

    /// 範囲が閉じたら差し込み、まだなら次の比較へ。
    fn resume_or_insert(&mut self, ins: Insertion) {
        if ins.lo < ins.hi {
            self.current = Some(ins);
        } else {
            self.groups.insert(ins.lo, vec![ins.item]);
            self.trim();
        }
    }

    /// 上位 K 位モードで、K 位より下に押し出されたかたまりを落とす。
    /// かたまりの先頭順位が K 以内なら残す (同順位で K を少し超えるのは許す)。
    fn trim(&mut self) {
        let cap = self.config.cap();
        let mut seen = 0;
        let mut keep = self.groups.len();
        for (i, g) in self.groups.iter().enumerate() {
            if seen >= cap {
                keep = i;
                break;
            }
            seen += g.len();
        }
        self.groups.truncate(keep);
    }

    fn ranking(&self) -> Vec<SortMakerRankEntry> {
        let mut out = Vec::with_capacity(self.kept_count());
        let mut rank = 1;
        for g in &self.groups {
            for &item in g {
                out.push(SortMakerRankEntry { item, rank });
            }
            rank += g.len() as u32;
        }
        out
    }

    /// 残り対戦数の見積り。引き分けが無い前提の上限寄りの値。
    fn estimated_remaining(&self) -> u32 {
        let Some(ins) = self.current.as_ref() else { return 0 };
        let cap = self.config.cap();
        let current = if ins.boundary_check {
            // K 位と 1 戦。勝てば中を探す (確率は後続と同じ見積りで)。
            1.0 + enter_chance(cap, self.next) * ceil_log2(self.groups.len()) as f64
        } else {
            ceil_log2(ins.hi - ins.lo + 1) as f64
        };
        let mut total = current;
        let mut kept = self.kept_count() + 1;
        for seen in self.next..self.order.len() {
            if kept < cap {
                total += ceil_log2(kept + 1) as f64;
                kept += 1;
            } else {
                total += 1.0 + enter_chance(cap, seen + 1) * ceil_log2(cap) as f64;
            }
        }
        total.round() as u32
    }

    fn state(&self) -> SortMakerState {
        let is_finished = self.current.is_none();
        let remaining = self.estimated_remaining();
        let progress_percent = if is_finished {
            100
        } else {
            let done = self.answered as f64;
            let pct = (done / (done + remaining.max(1) as f64) * 100.0).floor() as u32;
            pct.min(99)
        };
        SortMakerState {
            pair: self.pair(),
            answered: self.answered,
            estimated_remaining: remaining,
            progress_percent,
            ranking: self.ranking(),
            is_finished,
        }
    }
}

/// `seen` 件目までに見た中で、新顔が上位 `cap` に入る見込み (一様な好みの仮定)。
fn enter_chance(cap: usize, seen: usize) -> f64 {
    if seen == 0 { 1.0 } else { (cap as f64 / seen as f64).min(1.0) }
}

/// ⌈log₂ n⌉ (n 個の場所から 1 つを二分探索で決める比較回数)。n ≤ 1 は 0。
fn ceil_log2(n: usize) -> u32 {
    if n <= 1 { 0 } else { usize::BITS - (n - 1).leading_zeros() }
}

/// 答えを頭から再生して、いまの状態を返す。答えが多すぎた分は捨てる。
pub fn replay(config: SortMakerConfig, answers: &[SortMakerChoice]) -> SortMakerState {
    let mut sorter = Sorter::new(config);
    for &choice in answers {
        if sorter.current.is_none() {
            break;
        }
        sorter.apply(choice);
    }
    sorter.state()
}

/// 始める前の対戦数の見積り (設定画面の「約 N 戦」)。
pub fn estimate_total(item_count: u32, top_k: u32) -> u32 {
    replay(SortMakerConfig { item_count, top_k, seed: 0 }, &[]).estimated_remaining
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(n: u32, k: u32, seed: u64) -> SortMakerConfig {
        SortMakerConfig { item_count: n, top_k: k, seed }
    }

    /// 「添字が小さいほど好き」という好みで最後まで答える。
    fn play(config: SortMakerConfig, prefer: impl Fn(u32, u32) -> SortMakerChoice) -> (SortMakerState, Vec<SortMakerChoice>) {
        let mut answers = Vec::new();
        loop {
            let s = replay(config, &answers);
            let Some(p) = s.pair else { return (s, answers) };
            answers.push(prefer(p.left, p.right));
            assert!(answers.len() < 100_000, "終わらない");
        }
    }

    fn smaller_wins(l: u32, r: u32) -> SortMakerChoice {
        if l < r { SortMakerChoice::Left } else { SortMakerChoice::Right }
    }

    #[test]
    fn full_sort_orders_by_preference() {
        let (s, answers) = play(config(40, 0, 7), smaller_wins);
        assert!(s.is_finished);
        assert_eq!(s.progress_percent, 100);
        assert_eq!(s.estimated_remaining, 0);
        let items: Vec<u32> = s.ranking.iter().map(|e| e.item).collect();
        assert_eq!(items, (0..40).collect::<Vec<_>>());
        let ranks: Vec<u32> = s.ranking.iter().map(|e| e.rank).collect();
        assert_eq!(ranks, (1..=40).collect::<Vec<_>>());
        // 二分挿入の上限 Σ⌈log₂(i+1)⌉ 以内で終わる。
        let bound: u32 = (1..40).map(|i| ceil_log2(i + 1)).sum();
        assert!(answers.len() as u32 <= bound, "{} > {}", answers.len(), bound);
    }

    #[test]
    fn ties_share_a_rank_and_skip_the_next() {
        // 0,1 は同じくらい好き、あとは添字順。
        let tier = |i: u32| if i <= 1 { 0 } else { i };
        let (s, _) = play(config(5, 0, 3), |l, r| match tier(l).cmp(&tier(r)) {
            std::cmp::Ordering::Less => SortMakerChoice::Left,
            std::cmp::Ordering::Greater => SortMakerChoice::Right,
            std::cmp::Ordering::Equal => SortMakerChoice::Tie,
        });
        let ranks: Vec<(u32, u32)> = s.ranking.iter().map(|e| (e.item, e.rank)).collect();
        assert_eq!(ranks[0].1, 1);
        assert_eq!(ranks[1].1, 1);
        let mut top: Vec<u32> = vec![ranks[0].0, ranks[1].0];
        top.sort();
        assert_eq!(top, vec![0, 1]);
        assert_eq!(&ranks[2..], &[(2, 3), (3, 4), (4, 5)]);
    }

    #[test]
    fn all_ties_finish_in_n_minus_one() {
        let (s, answers) = play(config(10, 0, 1), |_, _| SortMakerChoice::Tie);
        assert_eq!(answers.len(), 9);
        assert!(s.ranking.iter().all(|e| e.rank == 1));
        assert_eq!(s.ranking.len(), 10);
    }

    #[test]
    fn top_k_keeps_only_the_best_k_and_costs_less() {
        let (s, answers) = play(config(200, 10, 11), smaller_wins);
        let items: Vec<u32> = s.ranking.iter().map(|e| e.item).collect();
        assert_eq!(items, (0..10).collect::<Vec<_>>());
        let (_, full) = play(config(200, 0, 11), smaller_wins);
        assert!(answers.len() * 3 < full.len(), "top10 {} / full {}", answers.len(), full.len());
    }

    #[test]
    fn top_k_tie_at_the_boundary_keeps_both() {
        // 全部引き分けなら全員 1 位で残る (同順位で K を超えるのは許す)。
        let (s, _) = play(config(6, 3, 5), |_, _| SortMakerChoice::Tie);
        assert_eq!(s.ranking.len(), 6);
    }

    #[test]
    fn undo_is_dropping_the_last_answer() {
        let c = config(12, 0, 42);
        let (_, answers) = play(c, smaller_wins);
        let before = replay(c, &answers[..5]);
        let after_wrong = replay(c, &[&answers[..5], &[SortMakerChoice::Tie]].concat());
        assert_ne!(before, after_wrong);
        // 間違えた答えを落とせば元の対戦に戻る。
        assert_eq!(replay(c, &answers[..5]), before);
        assert_eq!(before.answered, 5);
    }

    #[test]
    fn extra_answers_are_ignored() {
        let c = config(4, 0, 9);
        let (done, answers) = play(c, smaller_wins);
        let mut more = answers.clone();
        more.extend([SortMakerChoice::Left; 5]);
        assert_eq!(replay(c, &more), done);
    }

    #[test]
    fn same_seed_same_pairs_and_both_sides_used() {
        let c = config(30, 0, 123);
        let (_, answers) = play(c, smaller_wins);
        let mut lefts = 0;
        for i in 0..answers.len() {
            let a = replay(c, &answers[..i]).pair.unwrap();
            let b = replay(c, &answers[..i]).pair.unwrap();
            assert_eq!(a, b);
            let s = replay(c, &answers[..i]);
            // 新顔 = まだ順位表に無い方。
            if !s.ranking.iter().any(|e| e.item == a.left) {
                lefts += 1;
            }
        }
        assert!(lefts > 0 && lefts < answers.len(), "新顔が片側に偏っている: {lefts}/{}", answers.len());
    }

    #[test]
    fn progress_is_monotone_enough_and_ends_at_100() {
        let c = config(50, 0, 2);
        let (_, answers) = play(c, smaller_wins);
        let first = replay(c, &[]);
        assert_eq!(first.progress_percent, 0);
        assert!(first.estimated_remaining as usize >= answers.len() / 2);
        let mid = replay(c, &answers[..answers.len() / 2]);
        assert!((30..=70).contains(&mid.progress_percent), "{}", mid.progress_percent);
        assert!(replay(c, &answers[..answers.len() - 1]).progress_percent < 100);
    }

    #[test]
    fn tiny_inputs() {
        let empty = replay(config(0, 0, 1), &[]);
        assert!(empty.is_finished && empty.ranking.is_empty() && empty.pair.is_none());
        let one = replay(config(1, 0, 1), &[]);
        assert!(one.is_finished);
        assert_eq!(one.ranking, vec![SortMakerRankEntry { item: 0, rank: 1 }]);
        assert_eq!(estimate_total(1, 0), 0);
    }

    #[test]
    fn estimate_is_in_the_right_ballpark() {
        let (_, full) = play(config(100, 0, 8), smaller_wins);
        let est = estimate_total(100, 0) as f64;
        assert!((est - full.len() as f64).abs() / full.len() as f64 <= 0.2, "{est} vs {}", full.len());
        let (_, top) = play(config(300, 10, 8), smaller_wins);
        let est_top = estimate_total(300, 10) as f64;
        assert!((est_top - top.len() as f64).abs() / top.len() as f64 <= 0.35, "{est_top} vs {}", top.len());
    }
}
