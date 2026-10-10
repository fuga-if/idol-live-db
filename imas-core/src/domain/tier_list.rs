//! ティアー表: 曲・アイドルを S / A / B / C / D の段に振り分ける。
//!
//! 振り分けそのものは利用者が手で行う (好みの判断を機械に任せない)。コアが持つのは
//! - 段の並び (名前と数) … iOS / Android で段が食い違わないように 1 か所に置く
//! - ソートメーカーの順位表からの「たたき台」… 順位を段へ割り当てる規則
//! - 段の中の左右の並びを 1 件動かす規則 … ドラッグで落とした位置の決め方
//! だけ。たたき台はあくまで初期値で、画面で自由に動かせる。
//!
//! ## 順位 → 段の割り当て
//!
//! 上から S 10% / A 20% / B 30% / C 25% / D 15% を目安に切る (上ほど狭い)。
//! - 同順位 (引き分け) は同じ段に入れる。境目にかかったら上の段へまとめる。
//! - S には必ず 1 件以上入れる。
//! - 件数が段数より少ないときは上から 1 件ずつ (空の段が下に残る)。

/// 最初に並ぶ段の名前 (上から)。
pub const TIER_LABELS: [&str; 5] = ["S", "A", "B", "C", "D"];

/// 段を足したときの既定名 (6 段目以降)。
const EXTRA_LABELS: [&str; 5] = ["E", "F", "G", "H", "I"];

/// 段の色の候補 (hex)。先頭 5 色が最初の S〜D (見慣れた 赤→橙→黄→緑→青)、
/// 残りは段を足したときと色を変えるときの候補。画面ではテーマエンジンに通して明暗に合わせる。
pub const TIER_PALETTE: [&str; 10] = [
    "#FF5A5F", "#FF9F43", "#F6C744", "#2BC48A", "#4C8DFF",
    "#9B6BFF", "#FF6FB5", "#2EC4D6", "#A3D651", "#8E8E93",
];

/// 最初の S〜D の色 (= 候補の先頭 5 色)。
pub const TIER_COLOR_SEEDS: [&str; 5] = [
    TIER_PALETTE[0], TIER_PALETTE[1], TIER_PALETTE[2], TIER_PALETTE[3], TIER_PALETTE[4],
];

/// 段の数の下限と上限。1 段では振り分けにならず、10 段を超えると 1 画面に収まらない。
pub const MIN_TIERS: usize = 2;
pub const MAX_TIERS: usize = 10;

/// `index` 番目 (0 始まり) に段を足すときの既定名。
pub fn default_label(index: usize) -> String {
    TIER_LABELS
        .iter()
        .chain(EXTRA_LABELS.iter())
        .nth(index)
        .map(|s| s.to_string())
        .unwrap_or_else(|| format!("{}", index + 1))
}

/// 段を足すときの色。今の段で使っていない候補を先頭から選ぶ (全部使っていれば段数で巡回)。
pub fn next_color_for_new_tier(existing: &[String]) -> String {
    TIER_PALETTE
        .iter()
        .find(|c| !existing.iter().any(|e| e.eq_ignore_ascii_case(c)))
        .unwrap_or(&TIER_PALETTE[existing.len() % TIER_PALETTE.len()])
        .to_string()
}

/// 色を変える操作 (タップごとに次の候補へ)。候補に無い色なら先頭へ。
pub fn cycle_color(current: &str) -> String {
    let i = TIER_PALETTE.iter().position(|c| c.eq_ignore_ascii_case(current));
    TIER_PALETTE[i.map_or(0, |i| (i + 1) % TIER_PALETTE.len())].to_string()
}

/// 各段の取り分の目安 (百分率、合計 100)。
const TIER_SHARES: [u32; 5] = [10, 20, 30, 25, 15];

/// ティアー表の名前 (「推しソロ曲ティアー」等) の上限文字数。共有画像の見出し 1 行に収まる長さ。
pub const TITLE_MAX_CHARS: usize = 24;

/// 段の名前 (「神」「沼」等) の上限文字数。段の札 (幅の狭い色の四角) に 2 行で収まる長さ。
pub const TIER_LABEL_MAX_CHARS: usize = 6;

/// 利用者が付けた名前を保存できる形に整える。前後の空白を落とし、改行・タブは空白 1 つに、
/// 上限を超えた分は切る。空になったら `None` (= 既定の名前に戻す)。
pub fn normalize_name(input: &str, max_chars: usize) -> Option<String> {
    let mut out = String::new();
    let mut pending_space = false;
    for c in input.trim().chars() {
        if c.is_whitespace() {
            pending_space = true;
            continue;
        }
        if pending_space && !out.is_empty() {
            out.push(' ');
        }
        pending_space = false;
        out.push(c);
    }
    let cut: String = out.chars().take(max_chars).collect();
    let cut = cut.trim_end().to_string();
    if cut.is_empty() { None } else { Some(cut) }
}

/// 上位から並んだ順位列 (`ranks[i]` は i 番目の順位。同順位は同じ値) を段の添字列にする。
/// 戻り値は `ranks` と同じ長さで、0 = S。
pub fn assign_from_ranking(ranks: &[u32]) -> Vec<u32> {
    let n = ranks.len();
    if n == 0 {
        return Vec::new();
    }
    // 各段の下端 (累積件数)。最低でも「その段までで 段番号+1 件」を確保する。
    let mut bounds = Vec::with_capacity(TIER_SHARES.len());
    let mut acc = 0u32;
    for (t, share) in TIER_SHARES.iter().enumerate() {
        acc += share;
        let by_share = ((n as u64 * acc as u64 + 50) / 100) as usize;
        bounds.push(by_share.max(t + 1).min(n));
    }
    let mut out = Vec::with_capacity(n);
    let mut tier = 0usize;
    for i in 0..n {
        // 同順位の続きは前と同じ段 (境目を越えていても上の段にまとめる)。
        if i > 0 && ranks[i] == ranks[i - 1] {
            out.push(out[i - 1]);
            continue;
        }
        while tier + 1 < bounds.len() && i >= bounds[tier] {
            tier += 1;
        }
        out.push(tier as u32);
    }
    out
}

/// 表全体の並び (`order`) を対象の id 列 (`item_ids`) に揃える。対象に無い id と重複は落とし、
/// 並びに無い対象は元の順で末尾へ足す。`order` が空なら `item_ids` のまま。
/// 段の中の並びは「この並びのうちその段にいるもの」なので、段をまたいで 1 本で持てば足りる。
pub fn normalize_order(item_ids: &[String], order: &[String]) -> Vec<String> {
    use std::collections::HashSet;
    let valid: HashSet<&str> = item_ids.iter().map(String::as_str).collect();
    let mut seen: HashSet<&str> = HashSet::with_capacity(item_ids.len());
    let mut out = Vec::with_capacity(item_ids.len());
    for id in order.iter().chain(item_ids.iter()) {
        if valid.contains(id.as_str()) && seen.insert(id.as_str()) {
            out.push(id.clone());
        }
    }
    out
}

/// `item` を並びの中で動かした新しい並び。
/// - `before` が並びにある別の項目なら、その直前へ (札の上に落とした = その札の左に入る)。
/// - それ以外 (None・自分自身・並びに無い id) なら末尾へ (段の余白に落とした = その段の右端)。
///   ただし `before` が自分自身のときは動かさない (つかんで同じ場所に離しただけ)。
/// `item` が対象に無ければ揃えただけの並びを返す。どの段へ入るかは呼び出し側が振り分けで持つ。
pub fn move_item(item_ids: &[String], order: &[String], item: &str, before: Option<&str>) -> Vec<String> {
    let mut out = normalize_order(item_ids, order);
    if before == Some(item) {
        return out;
    }
    let Some(from) = out.iter().position(|id| id == item) else { return out };
    let moved = out.remove(from);
    let to = before.and_then(|b| out.iter().position(|id| id == b)).unwrap_or(out.len());
    out.insert(to, moved);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn distinct(n: u32) -> Vec<u32> {
        (1..=n).collect()
    }

    fn counts(tiers: &[u32]) -> Vec<usize> {
        (0..TIER_LABELS.len() as u32).map(|t| tiers.iter().filter(|&&x| x == t).count()).collect()
    }

    #[test]
    fn hundred_items_follow_the_shares() {
        assert_eq!(counts(&assign_from_ranking(&distinct(100))), vec![10, 20, 30, 25, 15]);
    }

    #[test]
    fn ten_items_keep_every_tier_and_top_is_narrow() {
        let c = counts(&assign_from_ranking(&distinct(10)));
        assert_eq!(c.iter().sum::<usize>(), 10);
        assert_eq!(c[0], 1);
        assert!(c.iter().all(|&x| x >= 1), "{c:?}");
    }

    #[test]
    fn fewer_items_than_tiers_go_one_per_tier_from_the_top() {
        assert_eq!(assign_from_ranking(&distinct(3)), vec![0, 1, 2]);
        assert_eq!(assign_from_ranking(&[1]), vec![0]);
        assert!(assign_from_ranking(&[]).is_empty());
    }

    #[test]
    fn ties_are_never_split_and_stay_in_the_upper_tier() {
        // 10 件: S の枠は 1 件だが 1 位が 3 件並んでいる → 3 件とも S。
        let ranks = vec![1, 1, 1, 4, 5, 6, 7, 8, 9, 10];
        let t = assign_from_ranking(&ranks);
        assert_eq!(&t[..3], &[0, 0, 0]);
        assert!(t[3] >= 1);
        // 単調 (下の順位が上の段に来ない)。
        assert!(t.windows(2).all(|w| w[0] <= w[1]));
    }

    #[test]
    fn names_are_trimmed_flattened_and_cut() {
        assert_eq!(normalize_name("  推し\nソロ曲  ", 24), Some("推し ソロ曲".to_string()));
        assert_eq!(normalize_name("   ", 24), None);
        assert_eq!(normalize_name("", 6), None);
        assert_eq!(normalize_name("かみかみかみかみ", 6), Some("かみかみかみ".to_string()));
        // 切った位置の直前が空白なら落とす。
        assert_eq!(normalize_name("abcde fgh", 6), Some("abcde".to_string()));
    }

    #[test]
    fn tier_defaults_and_colors() {
        assert_eq!(default_label(0), "S");
        assert_eq!(default_label(5), "E");
        assert_eq!(default_label(12), "13");
        let used: Vec<String> = TIER_COLOR_SEEDS.iter().map(|s| s.to_string()).collect();
        assert_eq!(next_color_for_new_tier(&used), TIER_PALETTE[5]);
        let all: Vec<String> = TIER_PALETTE.iter().map(|s| s.to_lowercase()).collect();
        assert_eq!(next_color_for_new_tier(&all), TIER_PALETTE[0]);
        assert_eq!(cycle_color("#ff5a5f"), TIER_PALETTE[1]);
        assert_eq!(cycle_color(TIER_PALETTE[9]), TIER_PALETTE[0]);
        assert_eq!(cycle_color("#123456"), TIER_PALETTE[0]);
    }

    fn ids(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn order_is_normalized_to_the_items() {
        let items = ids(&["a", "b", "c", "d"]);
        assert_eq!(normalize_order(&items, &[]), items);
        // 対象に無い id と重複は落とし、足りない対象は元の順で末尾へ。
        assert_eq!(normalize_order(&items, &ids(&["c", "x", "a", "c"])), ids(&["c", "a", "b", "d"]));
    }

    #[test]
    fn move_item_inserts_before_the_target_or_at_the_end() {
        let items = ids(&["a", "b", "c", "d"]);
        // 右へ: a を d の前へ。
        assert_eq!(move_item(&items, &items, "a", Some("d")), ids(&["b", "c", "a", "d"]));
        // 左へ: d を b の前へ。
        assert_eq!(move_item(&items, &items, "d", Some("b")), ids(&["a", "d", "b", "c"]));
        // 余白へ = 末尾。
        assert_eq!(move_item(&items, &items, "b", None), ids(&["a", "c", "d", "b"]));
        // 並びに無い先も末尾。
        assert_eq!(move_item(&items, &items, "b", Some("zz")), ids(&["a", "c", "d", "b"]));
        // 自分の上に離しただけなら動かない。
        assert_eq!(move_item(&items, &items, "c", Some("c")), items);
        // 対象に無い項目は揃えるだけ。
        assert_eq!(move_item(&items, &ids(&["d"]), "zz", Some("a")), ids(&["d", "a", "b", "c"]));
    }

    #[test]
    fn all_tied_is_all_s() {
        assert_eq!(assign_from_ranking(&[1, 1, 1, 1]), vec![0, 0, 0, 0]);
    }
}
