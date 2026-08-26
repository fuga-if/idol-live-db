//! メンバーカラー合わせ (色当てゲーム) の母集団決定・出題・採点規則。
//!
//! ## なぜ 1 か所に置くか
//!
//! iOS `ColorMatchGameView` (430 行) と Android `ColorMatchGameScreen` (472 行) は
//! 手で写経した file-for-file のコピーで、規則そのものが二重管理になっていた。
//! 実際に片方だけ書き換わった箇所が複数ある (末尾「両 OS の乖離」参照)。
//! View から剥がせる計算 (母集団・出題抽選・色距離・正誤判定・正答率) だけをここへ集め、
//! 描画とアニメーションだけを各 OS に残す。乖離はすべて **iOS を正** として畳んである。
//!
//! ## 出題の考え方
//!
//! 母集団は「メンバーカラーが一意なアイドル」。同じ色の 2 人が同じ問題に並ぶと、
//! どちらに割り当てても見た目は正解なのに片方が不正解になってしまうため、
//! 色で重複を落とす (`unique_by_color`)。難易度は「アンカー 1 人を引いて、
//! そこからどう仲間を選ぶか」の違いだけで表現する (`companions`):
//!
//! - むずい: アンカーに **色が近い順** に詰める (見分けが難しい)
//! - やさしい: 互いになるべく **離れた色** を選ぶ (farthest-point sampling)
//! - ふつう: 残りからランダム
//!
//! ## FFI 境界の形
//!
//! アイドルのエンティティ全体は渡さず、必要なフィールドだけの射影を受け渡す。
//! 呼び出し側は返ってきた id で自国の配列を引き直す。
//! **1 ユーザー操作 = 1 呼び出し**にするため、出題は問題ごとではなく
//! [`make_rounds`] で 1 ゲームぶんまとめて生成し、答え合わせの HEX 表示文字列も
//! 行ごとに呼ばせず [`judge_round`] の結果に同梱する。
//! 乱数はシード注入の [`SplitMix64`] のみ (OS 乱数は各 OS のラッパが調達する)。
//!
//! ## 両 OS の乖離 (iOS を正として畳んだもの)
//!
//! 1. **外部ゲスト演者の除外**: iOS は `!isExternal` で落としていたが、Android は
//!    落としていなかった (`fetchIdols()` は picker 用でゲストを含む)。→ 落とす。
//! 2. **答え合わせの HEX 表示**: 不正な hex のとき iOS は `—`、Android は `#??????`。→ `—`。
//! 3. **行の正誤表示**: Android の行だけ `idol.color ?: ""` で比較していたため、
//!    色未設定かつ割り当ても不正な hex のとき「行は正解・スコアは不正解」とねじれ得た。
//!    → iOS の `sameColor` (色が無ければ不正解) に統一。
//! 4. **同値の並び順**: Swift の `sorted` は非安定 (同値の順が不定)、Kotlin の
//!    `sortedBy` は安定。ここでは決定論を優先して安定ソートに揃える (Kotlin と同じ)。

use std::collections::{HashMap, HashSet};

use crate::domain::prng::SplitMix64;

/// 出題対象から外すブランド。ラブライブ / .KR 等の非アイマス・コラボ枠は
/// 「メンバーカラー」がアイマスの語彙で成立しないので母集団にも選択肢にも出さない。
pub const EXCLUDED_BRAND_ID: &str = "other";

/// 出題ブランドとして選べるようにする最小人数 (色が一意なメンバー)。
/// これを下回るブランドは 1 問ぶん (最大 6 人) すら組めないので出題母集団から外す。
pub const MIN_BRAND_POOL_SIZE: usize = 4;

/// ゲームを開始できる母集団の最小人数。1 人では「合わせる」が成立しない。
/// 呼び出し側は [`effective_pool`] の件数がこれ未満なら開始ボタンを塞ぐ。
pub const MIN_POOL_SIZE: usize = 2;

/// 色が読めなかったときに使う低彩度グレー (`ColorMath.neutralSeed` と同値)。
const NEUTRAL_HEX: &str = "8e8e93";

// ---------------------------------------------------------------------------
// hex ユーティリティ
// ---------------------------------------------------------------------------

/// Swift の `CharacterSet.whitespaces` と**実測で**同じ集合 (19 文字)。
///
/// Apple のドキュメントは「Unicode Zs + 水平タブ」(= 18 文字) と書いているが、実装は
/// **U+200B (ZERO WIDTH SPACE) も含む** (U+200B の General Category は Zs ではなく Cf)。
/// macOS の Foundation を 0..=0x10FFFF まで走査して数えると 19 文字ある。
/// ドキュメントではなく実装が原本の挙動なので、そちらに合わせる。
///
/// Rust の `char::is_whitespace` は Unicode の White_Space プロパティで、
/// 改行類 7 文字を余分に含み、逆に U+200B を含まない (18 文字)。そこで
/// 改行類を外し、U+200B を足して原本と同じ 19 文字にする。
///
/// 改行を落とさないのは原本が `.whitespacesAndNewlines` ではなく `.whitespaces` を
/// 使っているため (`"#e22b30\n"` は無効のまま)。この 2 点の実測オラクルとの突き合わせは
/// `color_engine::tests::hex_trim_matches_the_ios_whitespace_set_exactly`。
fn is_swift_whitespace(c: char) -> bool {
    // U+200B は White_Space プロパティを持たないので `is_whitespace` からは出てこない。
    c == '\u{200b}'
        || (c.is_whitespace()
            && !matches!(
                c,
                '\n' | '\u{b}' | '\u{c}' | '\r' | '\u{85}' | '\u{2028}' | '\u{2029}'
            ))
}

/// `#RGB` / `#RRGGBB` を 6 桁小文字 hex に正規化する。無効なら `None`。
///
/// 表記ゆれ (`#` の有無・大文字小文字・3 桁短縮) を吸収した「色の同一性の鍵」であり、
/// 母集団の重複排除と正誤判定の両方がこれに乗る。
///
/// 判定は ASCII 16 進数字のみ。原本 (Swift `Character.isHexDigit` / Kotlin
/// `Char.isDigit`) は全角数字なども「hex 桁」と認めてしまい、その先で iOS は黒 (0) に落ち、
/// Android は `toLong(16)` が例外を投げてクラッシュする。DB のカラーコードは常に
/// ASCII なので、両方の危うい経路をまとめて「無効」に倒す。
pub fn normalized_hex(hex: &str) -> Option<String> {
    let trimmed = hex.trim_matches(is_swift_whitespace);
    let body = trimmed.strip_prefix('#').unwrap_or(trimmed);
    // 3 桁短縮 (`#f0a`) は各桁を 2 回並べて 6 桁にする。
    let expanded: String = if body.chars().count() == 3 {
        body.chars().flat_map(|c| [c, c]).collect()
    } else {
        body.to_string()
    };
    if expanded.len() == 6 && expanded.bytes().all(|b| b.is_ascii_hexdigit()) {
        Some(expanded.to_ascii_lowercase())
    } else {
        None
    }
}

/// 0–255 の RGB 成分。距離計算を原本 (Swift / Kotlin の `Double`) と同じ演算にするため
/// 整数ではなく `f64` で持つ。
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgb {
    pub r: f64,
    pub g: f64,
    pub b: f64,
}

/// hex を RGB 成分に開く。無効な hex はニュートラルグレーに落とす (原本と同じ)。
pub fn hex_to_rgb(hex: &str) -> Rgb {
    let s = normalized_hex(hex).unwrap_or_else(|| NEUTRAL_HEX.to_string());
    // 正規化済みなら必ず 6 桁 ASCII hex なので失敗しない。FFI 越しに panic させないため、
    // 原本の `?? 0` と同じく黒へ倒しておく。
    let n = u32::from_str_radix(&s, 16).unwrap_or(0);
    Rgb { r: ((n >> 16) & 255) as f64, g: ((n >> 8) & 255) as f64, b: (n & 255) as f64 }
}

/// 知覚的な色距離 (redmean 近似)。小さいほど似ている。
///
/// 単純な RGB ユークリッド距離だと見た目の近さとずれる (緑の差が過小評価される)。
/// 難易度の「近い色を集める / 離す」はプレイヤーの目で評価されるので、目に近い尺度を使う。
///
/// 色が無い / 読めないときは最大値 (= 最も遠い) を返す。むずいでは最後尾へ、
/// やさしいでは最優先で選ばれるが、母集団は色が有効な人だけなので実際には通らない。
pub fn color_distance(a: Option<&str>, b: Option<&str>) -> f64 {
    let (Some(a), Some(b)) = (a, b) else { return f64::MAX };
    if normalized_hex(a).is_none() || normalized_hex(b).is_none() {
        return f64::MAX;
    }
    let x = hex_to_rgb(a);
    let y = hex_to_rgb(b);
    let rmean = (x.r + y.r) / 2.0;
    let (dr, dg, db) = (x.r - y.r, x.g - y.g, x.b - y.b);
    ((2.0 + rmean / 256.0) * dr * dr) + (4.0 * dg * dg) + ((2.0 + (255.0 - rmean) / 256.0) * db * db)
}

/// 表記ゆれを無視した色の同値判定。どちらも読めない hex なら「同じ」とみなす
/// (原本 Swift の `normalizedHex(a) == normalizedHex(b)` が `nil == nil` になる形)。
/// 色そのものが無い (`None`) 相手は常に不一致。
fn same_color(assigned: &str, actual: Option<&str>) -> bool {
    match actual {
        Some(actual) => normalized_hex(assigned) == normalized_hex(actual),
        None => false,
    }
}

/// メンバーカラーを答え合わせで見せる `#F5C900` 形式に整える。読めなければ `—`。
pub fn hex_label(hex: Option<&str>) -> String {
    match hex.and_then(normalized_hex) {
        Some(norm) => format!("#{}", norm.to_ascii_uppercase()),
        None => "—".to_string(),
    }
}

// ---------------------------------------------------------------------------
// 射影・結果の型
// ---------------------------------------------------------------------------

/// 母集団を組むときに DB から読むアイドル 1 件の射影。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ColorMatchIdolSource {
    pub id: String,
    pub brand_id: String,
    /// メンバーカラー hex。マスタ未設定は `None`。
    pub color: Option<String>,
    /// 外部ゲスト演者 (アイマス側のメンバーカラーを持たない) か。
    pub is_external: bool,
    /// ブランド内の公式順。同じ色が重複したときにどちらを残すかを決める。
    pub sort_order: i32,
}

/// 母集団に残ったアイドル。出題と採点に要る id と色だけを持つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ColorMatchIdol {
    pub id: String,
    /// メンバーカラー hex (DB の原文のまま)。色チップの実体でもあるので正規化しない。
    pub color: Option<String>,
}

/// ブランドの射影 (母集団の並べ替えに要る分だけ)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ColorMatchBrandRef {
    pub id: String,
    pub sort_order: i32,
}

/// 1 ブランドぶんの出題母集団。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ColorMatchBrandPool {
    pub brand_id: String,
    /// 色が一意なメンバー (ブランド内の公式順)。
    pub members: Vec<ColorMatchIdol>,
}

/// 画面ロード時に 1 回だけ組む母集団一式。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Default)]
pub struct ColorMatchPools {
    /// ブランド未選択 (= 全ブランド) のときの母集団。色が一意。
    pub all_colored: Vec<ColorMatchIdol>,
    /// 出題可能なブランドごとの母集団。ブランドの `sort_order` 順。
    pub brand_pools: Vec<ColorMatchBrandPool>,
    /// 出題ブランド選択に並べるブランド id (入力順のまま、[`EXCLUDED_BRAND_ID`] を除く)。
    ///
    /// メンバーが 4 人未満で `brand_pools` に無いブランドもここには出る (原本と同じ)。
    /// 選ぶと母集団が空になり「はじめる」が押せないだけで、選択自体は妨げない。
    pub selectable_brand_ids: Vec<String>,
}

/// 難易度。UI のセグメント index 0 / 1 / 2 がそのままこの順に対応する。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ColorMatchDifficulty {
    /// やさしい: 互いになるべく離れた色を集める。
    Easy,
    /// ふつう: アンカー以外はランダム。
    Normal,
    /// むずい: アンカーに最も近い色を集め、人数も増やす。
    Hard,
}

impl ColorMatchDifficulty {
    /// 1 問に出すメンバー数 (原本の `levelCounts`)。難しいほど多い。
    pub fn members_per_round(self) -> usize {
        match self {
            Self::Easy => 4,
            Self::Normal => 5,
            Self::Hard => 6,
        }
    }
}

/// 1 問ぶんの出題。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Default)]
pub struct ColorMatchRound {
    /// 出題メンバー (表示順)。答え合わせ用に正解色も持つ。
    ///
    /// 判定前に色を画面へ出さないのは各 OS の描画側の責務 (中立アバターで隠す)。
    pub members: Vec<ColorMatchIdol>,
    /// 色チップの並び (メンバーカラーの原文、表示順)。
    /// `members` の色を並べ替えたものなので、メンバーと位置は対応しない。
    pub palette: Vec<String>,
}

/// 割り当て 1 件 (どのアイドルにどの色チップを置いたか)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ColorMatchAssignment {
    pub idol_id: String,
    /// パレットから割り当てた hex (原文)。
    pub hex: String,
}

/// 1 問の答え合わせ結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Default)]
pub struct ColorMatchJudgement {
    /// 出題メンバーと同順の正誤 (行の ✓ / ✗)。
    pub correct: Vec<bool>,
    /// 正解した人数。
    pub score: u32,
    /// 出題した人数 (正答率の分母に足す値)。
    pub out_of: u32,
    /// 答え合わせで見せる正解色の表示文字列 (メンバーと同順、`#F5C900` 形式)。
    /// 行ごとに FFI を呼ばせないためここに同梱する。
    pub correct_hex_labels: Vec<String>,
}

// ---------------------------------------------------------------------------
// 母集団の決定
// ---------------------------------------------------------------------------

/// 正規化した色で重複を除き、各色につき最初の 1 人だけ残す (色が読めない人は除外)。
///
/// 同じ色の 2 人が同じ問題に並ぶと、見た目が同じチップをどちらに置いても片方が
/// 不正解になり理不尽なので、母集団の段階で潰しておく。
fn unique_by_color(idols: impl IntoIterator<Item = ColorMatchIdol>) -> Vec<ColorMatchIdol> {
    let mut seen: HashSet<String> = HashSet::new();
    idols
        .into_iter()
        .filter(|idol| match normalized_hex(idol.color.as_deref().unwrap_or("")) {
            Some(hex) => seen.insert(hex),
            None => false,
        })
        .collect()
}

fn to_idol(source: &ColorMatchIdolSource) -> ColorMatchIdol {
    ColorMatchIdol { id: source.id.clone(), color: source.color.clone() }
}

/// DB のアイドル / ブランド一覧から、画面ロード時に 1 回だけ組む母集団一式を作る。
///
/// - 外部ゲスト演者・[`EXCLUDED_BRAND_ID`]・色未設定は母集団から外す。
/// - ブランド別は公式順に並べてから色で一意化するので、色が重複したときは
///   「そのブランドで先に出てくる人」が残る (毎回同じ人が出る = 決定的)。
/// - メンバーが [`MIN_BRAND_POOL_SIZE`] 未満のブランド、ブランドマスタに無い
///   `brand_id` は `brand_pools` に出さない。
pub fn build_pools(
    idols: &[ColorMatchIdolSource],
    brands: &[ColorMatchBrandRef],
) -> ColorMatchPools {
    let brand_sort_order: HashMap<&str, i32> =
        brands.iter().map(|b| (b.id.as_str(), b.sort_order)).collect();

    let colored: Vec<&ColorMatchIdolSource> = idols
        .iter()
        .filter(|idol| {
            !idol.is_external
                && idol.brand_id != EXCLUDED_BRAND_ID
                && idol.color.as_deref().is_some_and(|c| !c.is_empty())
        })
        .collect();

    let all_colored = unique_by_color(colored.iter().copied().map(to_idol));

    // 初出のブランド順に束ねる。Swift の Dictionary は反復順が不定で、ブランドの
    // sort_order が同値のときに並びが実行ごとに変わり得たので、ここで順序を固定する。
    let mut order: Vec<&str> = Vec::new();
    let mut by_brand: HashMap<&str, Vec<&ColorMatchIdolSource>> = HashMap::new();
    for idol in colored.iter().copied() {
        by_brand
            .entry(idol.brand_id.as_str())
            .or_insert_with(|| {
                order.push(idol.brand_id.as_str());
                Vec::new()
            })
            .push(idol);
    }

    let mut ranked: Vec<(i32, ColorMatchBrandPool)> = order
        .into_iter()
        .filter_map(|brand_id| {
            let sort_order = *brand_sort_order.get(brand_id)?;
            let mut list = by_brand.remove(brand_id).unwrap_or_default();
            // 安定ソート: 公式順が同値なら DB から読んだ順を保つ。
            list.sort_by_key(|idol| idol.sort_order);
            let members = unique_by_color(list.into_iter().map(to_idol));
            (members.len() >= MIN_BRAND_POOL_SIZE)
                .then(|| (sort_order, ColorMatchBrandPool { brand_id: brand_id.to_string(), members }))
        })
        .collect();
    ranked.sort_by_key(|(sort_order, _)| *sort_order);

    ColorMatchPools {
        all_colored,
        brand_pools: ranked.into_iter().map(|(_, pool)| pool).collect(),
        selectable_brand_ids: brands
            .iter()
            .filter(|b| b.id != EXCLUDED_BRAND_ID)
            .map(|b| b.id.clone())
            .collect(),
    }
}

/// 選択されたブランドから実際の出題母集団を引く (未選択なら全ブランド)。
///
/// ブランドを跨ぐと同じ色の人が両方に現れ得るので、連結してからもう一度色で
/// 一意化する。残るのは `brand_pools` の並び (ブランドの公式順) で先に来た方。
pub fn effective_pool(
    pools: &ColorMatchPools,
    selected_brand_ids: &[String],
) -> Vec<ColorMatchIdol> {
    if selected_brand_ids.is_empty() {
        return pools.all_colored.clone();
    }
    let selected: HashSet<&str> = selected_brand_ids.iter().map(String::as_str).collect();
    unique_by_color(
        pools
            .brand_pools
            .iter()
            .filter(|pool| selected.contains(pool.brand_id.as_str()))
            .flat_map(|pool| pool.members.iter().cloned()),
    )
}

// ---------------------------------------------------------------------------
// 出題
// ---------------------------------------------------------------------------

/// `set` の中でいちばん近い色との距離。1 人でも色が近い人がいれば「近い」とみなす尺度。
fn min_distance(idol: &ColorMatchIdol, set: &[ColorMatchIdol]) -> f64 {
    set.iter()
        .map(|other| color_distance(idol.color.as_deref(), other.color.as_deref()))
        .fold(f64::MAX, f64::min)
}

/// 最大値をとる要素の index。同値なら **最初の** 1 件。
///
/// Swift `max(by:)` / Kotlin `maxByOrNull` は「厳密に大きいときだけ更新」なので
/// 最初の最大値が勝つ。Rust の `Iterator::max_by` は最後の最大値を返すため、
/// そのまま使うと同距離が並ぶ母集団で出題が変わる。
fn index_of_first_max(scores: &[f64]) -> Option<usize> {
    let mut best: Option<(usize, f64)> = None;
    for (i, &score) in scores.iter().enumerate() {
        match best {
            Some((_, top)) if top >= score => {}
            _ => best = Some((i, score)),
        }
    }
    best.map(|(i, _)| i)
}

/// アンカーと一緒に出す残りのメンバーを、難易度の規則で `take` 人選ぶ。
///
/// `rest` はアンカーを除いた母集団。むずい / やさしいは色の関係だけで決まり乱数を
/// 使わないので、規則そのものを単体で固定できる。候補が足りなければその分だけ
/// 少なく返す (落とさない)。
fn companions(
    anchor: &ColorMatchIdol,
    rest: Vec<ColorMatchIdol>,
    take: usize,
    difficulty: ColorMatchDifficulty,
    rng: &mut SplitMix64,
) -> Vec<ColorMatchIdol> {
    match difficulty {
        ColorMatchDifficulty::Hard => {
            // アンカーに色が近い順。安定ソートなので同距離は母集団の並び順で決まる。
            let mut ranked: Vec<(f64, ColorMatchIdol)> = rest
                .into_iter()
                .map(|idol| (color_distance(anchor.color.as_deref(), idol.color.as_deref()), idol))
                .collect();
            ranked.sort_by(|a, b| a.0.total_cmp(&b.0));
            ranked.into_iter().take(take).map(|(_, idol)| idol).collect()
        }
        ColorMatchDifficulty::Easy => {
            // farthest-point sampling: 既に選んだ誰から見ても遠い人を 1 人ずつ足す。
            let mut selected = vec![anchor.clone()];
            let mut left = rest;
            while selected.len() <= take && !left.is_empty() {
                let scores: Vec<f64> =
                    left.iter().map(|idol| min_distance(idol, &selected)).collect();
                let best = left[index_of_first_max(&scores).expect("left は空でない")].clone();
                left.retain(|idol| idol.id != best.id);
                selected.push(best);
            }
            selected.split_off(1)
        }
        ColorMatchDifficulty::Normal => {
            let mut rest = rest;
            rng.shuffle(&mut rest);
            rest.truncate(take);
            rest
        }
    }
}

/// 1 問ぶんのメンバーとパレットを組む。
fn make_round(
    pool: &[ColorMatchIdol],
    difficulty: ColorMatchDifficulty,
    rng: &mut SplitMix64,
) -> ColorMatchRound {
    let n = difficulty.members_per_round().min(pool.len());
    // 2 人未満では「合わせる」が成立しないので空の問題にする (呼び出し側で開始を止める前提)。
    if n < MIN_POOL_SIZE {
        return ColorMatchRound::default();
    }

    // アンカー: 難易度の「近い / 遠い」を測る基準になる 1 人。ここだけは常にランダム。
    let anchor = pool[rng.next_below(pool.len() as u64) as usize].clone();
    let rest: Vec<ColorMatchIdol> =
        pool.iter().filter(|idol| idol.id != anchor.id).cloned().collect();

    let mut members = vec![anchor.clone()];
    members.extend(companions(&anchor, rest, n - 1, difficulty, rng));
    // アンカーが常に先頭だと「1 番目が基準」と読めてしまうので混ぜる。
    rng.shuffle(&mut members);

    let mut palette: Vec<String> =
        members.iter().map(|idol| idol.color.clone().unwrap_or_default()).collect();
    // チップの並びも行の並びと対応しないよう、独立にシャッフルする。
    rng.shuffle(&mut palette);

    ColorMatchRound { members, palette }
}

/// 1 ゲーム (全 `question_count` 問) の出題をまとめて作る。
///
/// 問題ごとに FFI を呼ぶ形を避けるため、開始操作 1 回でここまで引き切る。
/// 各問は独立に母集団全体から引くので、同じアイドルが別の問に再登場することはある
/// (原本も問ごとに母集団全体から引き直している)。
pub fn make_rounds(
    pool: &[ColorMatchIdol],
    difficulty: ColorMatchDifficulty,
    question_count: u32,
    rng: &mut SplitMix64,
) -> Vec<ColorMatchRound> {
    (0..question_count).map(|_| make_round(pool, difficulty, rng)).collect()
}

// ---------------------------------------------------------------------------
// 採点
// ---------------------------------------------------------------------------

/// 1 問の答え合わせ。割り当てが無いメンバーは不正解として数える。
///
/// `assignments` に同じ `idol_id` が複数あれば最初の 1 件を採る
/// (原本の辞書は 1 アイドル 1 色なので実際には起きない)。
pub fn judge_round(
    members: &[ColorMatchIdol],
    assignments: &[ColorMatchAssignment],
) -> ColorMatchJudgement {
    let correct: Vec<bool> = members
        .iter()
        .map(|member| {
            assignments
                .iter()
                .find(|a| a.idol_id == member.id)
                .is_some_and(|a| same_color(&a.hex, member.color.as_deref()))
        })
        .collect();
    ColorMatchJudgement {
        score: correct.iter().filter(|&&ok| ok).count() as u32,
        out_of: members.len() as u32,
        correct_hex_labels: members
            .iter()
            .map(|member| hex_label(member.color.as_deref()))
            .collect(),
        correct,
    }
}

/// 結果画面の正答率 (%)。1 問も出ていなければ 0。
///
/// 四捨五入は 0.5 を絶対値の大きい側へ (Swift `Double.rounded()` と同じ)。
pub fn accuracy_percent(total_correct: u32, total_answered: u32) -> u32 {
    if total_answered == 0 {
        return 0;
    }
    (f64::from(total_correct) / f64::from(total_answered) * 100.0).round() as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- テスト用のヘルパ (色は実マスタの値を使う) ---

    fn idol(id: &str, color: Option<&str>) -> ColorMatchIdol {
        ColorMatchIdol { id: id.into(), color: color.map(str::to_string) }
    }

    fn source(id: &str, brand: &str, color: Option<&str>, sort_order: i32) -> ColorMatchIdolSource {
        ColorMatchIdolSource {
            id: id.into(),
            brand_id: brand.into(),
            color: color.map(str::to_string),
            is_external: false,
            sort_order,
        }
    }

    fn brand(id: &str, sort_order: i32) -> ColorMatchBrandRef {
        ColorMatchBrandRef { id: id.into(), sort_order }
    }

    fn assign(idol_id: &str, hex: &str) -> ColorMatchAssignment {
        ColorMatchAssignment { idol_id: idol_id.into(), hex: hex.into() }
    }

    fn ids(idols: &[ColorMatchIdol]) -> Vec<&str> {
        idols.iter().map(|i| i.id.as_str()).collect()
    }

    fn strs(values: &[String]) -> Vec<&str> {
        values.iter().map(String::as_str).collect()
    }

    fn brand_ids(pools: &ColorMatchPools) -> Vec<&str> {
        pools.brand_pools.iter().map(|p| p.brand_id.as_str()).collect()
    }

    /// 765AS 相当の 6 色母集団。
    fn pool6() -> Vec<ColorMatchIdol> {
        vec![
            idol("haruka", Some("#e22b30")),
            idol("chihaya", Some("#2743d2")),
            idol("miki", Some("#b4e04b")),
            idol("yukiho", Some("#d9c8b7")),
            idol("yayoi", Some("#f39939")),
            idol("makoto", Some("#5674b9")),
        ]
    }

    /// 色相をずらした大きめの母集団 (難易度の効き方を見るため)。
    fn spread_pool(count: i32) -> Vec<ColorMatchIdol> {
        (0..count)
            .map(|i| {
                let h = (i * 10) % 256;
                idol(
                    &format!("i{i}"),
                    Some(&format!("#{:02x}{:02x}{:02x}", h, 255 - h, (h * 3) % 256)),
                )
            })
            .collect()
    }

    // --- normalized_hex ---

    #[test]
    fn normalizes_hash_case_and_short_form() {
        assert_eq!(normalized_hex("#E22B30").as_deref(), Some("e22b30"));
        assert_eq!(normalized_hex("e22b30").as_deref(), Some("e22b30"));
        assert_eq!(normalized_hex("#F0A").as_deref(), Some("ff00aa"));
        assert_eq!(normalized_hex("f0a").as_deref(), Some("ff00aa"));
    }

    /// 前後の空白は落とす (Swift `.whitespaces` と同じ集合)。
    #[test]
    fn trims_horizontal_whitespace() {
        assert_eq!(normalized_hex("  #e22b30\t").as_deref(), Some("e22b30"));
        assert_eq!(normalized_hex("\u{3000}e22b30").as_deref(), Some("e22b30"));
    }

    /// 原本は改行をトリムしない (`.whitespacesAndNewlines` ではない) ので無効のまま。
    #[test]
    fn does_not_trim_newlines() {
        assert_eq!(normalized_hex("#e22b30\n"), None);
    }

    #[test]
    fn rejects_invalid_hex() {
        for bad in ["", "#", "#12345", "#1234567", "#gggggg", "#12 34 56", "＃ＦＦ００ＡＡ"] {
            assert_eq!(normalized_hex(bad), None, "{bad:?} を有効と誤判定した");
        }
    }

    // --- hex_to_rgb / color_distance ---

    #[test]
    fn converts_hex_to_rgb_components() {
        assert_eq!(hex_to_rgb("#e22b30"), Rgb { r: 226.0, g: 43.0, b: 48.0 });
        assert_eq!(hex_to_rgb("#000000"), Rgb { r: 0.0, g: 0.0, b: 0.0 });
        assert_eq!(hex_to_rgb("#ffffff"), Rgb { r: 255.0, g: 255.0, b: 255.0 });
    }

    /// 読めない hex はニュートラルグレーに落とす (原本の `?? "8e8e93"`)。
    #[test]
    fn invalid_hex_falls_back_to_neutral_gray() {
        assert_eq!(hex_to_rgb("nope"), hex_to_rgb("#8e8e93"));
    }

    #[test]
    fn distance_is_zero_for_same_color_and_symmetric() {
        assert_eq!(color_distance(Some("#e22b30"), Some("#E22B30")), 0.0);
        let ab = color_distance(Some("#e22b30"), Some("#2743d2"));
        assert_eq!(ab, color_distance(Some("#2743d2"), Some("#e22b30")));
        assert!(ab > 0.0);
    }

    /// 似た色ほど距離が小さい (難易度の「近い / 遠い」が意味を持つ根拠)。
    #[test]
    fn similar_colors_are_closer_than_opposite_ones() {
        let near = color_distance(Some("#e22b30"), Some("#e0392f")); // 赤 と 赤
        let far = color_distance(Some("#e22b30"), Some("#2743d2")); // 赤 と 青
        assert!(near < far, "near={near} far={far}");
    }

    /// 色が無い / 読めないときは最大値 (最も遠い)。
    #[test]
    fn distance_is_max_for_missing_or_invalid_color() {
        assert_eq!(color_distance(None, Some("#e22b30")), f64::MAX);
        assert_eq!(color_distance(Some("#e22b30"), None), f64::MAX);
        assert_eq!(color_distance(Some("nope"), Some("#e22b30")), f64::MAX);
        assert_eq!(color_distance(None, None), f64::MAX);
    }

    // --- hex_label ---

    #[test]
    fn hex_label_is_uppercase_with_hash() {
        assert_eq!(hex_label(Some("#e22b30")), "#E22B30");
        assert_eq!(hex_label(Some("f0a")), "#FF00AA");
    }

    /// 読めない色は Android の `#??????` ではなく iOS の `—` に揃える。
    #[test]
    fn hex_label_falls_back_to_em_dash() {
        assert_eq!(hex_label(None), "—");
        assert_eq!(hex_label(Some("")), "—");
        assert_eq!(hex_label(Some("nope")), "—");
    }

    // --- build_pools ---

    /// 実データを模した 2 ブランド (765AS 5 人 / シンデレラ 4 人)。
    fn sources() -> Vec<ColorMatchIdolSource> {
        vec![
            source("haruka", "765as", Some("#e22b30"), 1),
            source("chihaya", "765as", Some("#2743d2"), 2),
            source("miki", "765as", Some("#b4e04b"), 3),
            source("yukiho", "765as", Some("#d9c8b7"), 4),
            source("yayoi", "765as", Some("#f39939"), 5),
            source("uzuki", "cinderella", Some("#e75f8e"), 1),
            source("rin", "cinderella", Some("#2e93d0"), 2),
            source("mio", "cinderella", Some("#f8b301"), 3),
            source("mika", "cinderella", Some("#a5487e"), 4),
        ]
    }

    fn brands2() -> Vec<ColorMatchBrandRef> {
        vec![brand("765as", 1), brand("cinderella", 2), brand(EXCLUDED_BRAND_ID, 99)]
    }

    #[test]
    fn builds_pools_per_brand_in_brand_order() {
        let pools = build_pools(&sources(), &brands2());
        assert_eq!(pools.all_colored.len(), 9);
        assert_eq!(brand_ids(&pools), vec!["765as", "cinderella"]);
        assert_eq!(ids(&pools.brand_pools[1].members), vec!["uzuki", "rin", "mio", "mika"]);
    }

    /// ブランドの公式順が入力順と逆でも `sort_order` で並ぶ。
    #[test]
    fn brand_pools_follow_brand_sort_order() {
        let brands = vec![brand("765as", 20), brand("cinderella", 10)];
        let pools = build_pools(&sources(), &brands);
        assert_eq!(brand_ids(&pools), vec!["cinderella", "765as"]);
    }

    /// 外部ゲスト演者は母集団に入れない (Android だけ落としていなかった箇所)。
    #[test]
    fn excludes_external_guests() {
        let mut src = sources();
        src.push(ColorMatchIdolSource {
            is_external: true,
            ..source("guest", "765as", Some("#123456"), 6)
        });
        let pools = build_pools(&src, &brands2());
        assert!(!ids(&pools.all_colored).contains(&"guest"));
        assert!(!ids(&pools.brand_pools[0].members).contains(&"guest"));
    }

    /// コラボ枠 'other' はブランド母集団にも選択肢にも出さない。
    #[test]
    fn excludes_other_brand() {
        let mut src = sources();
        for i in 0..4 {
            src.push(source(
                &format!("collab{i}"),
                EXCLUDED_BRAND_ID,
                Some(&format!("#00000{i}")),
                i,
            ));
        }
        let pools = build_pools(&src, &brands2());
        assert!(ids(&pools.all_colored).iter().all(|id| !id.starts_with("collab")));
        assert!(!brand_ids(&pools).contains(&EXCLUDED_BRAND_ID));
        assert_eq!(strs(&pools.selectable_brand_ids), vec!["765as", "cinderella"]);
    }

    /// 色が無い / 空文字 / 読めない人は母集団から外れる。
    #[test]
    fn excludes_idols_without_usable_color() {
        let src = vec![
            source("none", "765as", None, 1),
            source("empty", "765as", Some(""), 2),
            source("broken", "765as", Some("not-a-color"), 3),
            source("ok", "765as", Some("#e22b30"), 4),
        ];
        assert_eq!(ids(&build_pools(&src, &brands2()).all_colored), vec!["ok"]);
    }

    /// 全体プールは DB から読んだ順で先の人を残す (色の重複は後発を落とす)。
    #[test]
    fn all_colored_keeps_the_first_of_duplicate_colors() {
        let src = vec![
            source("first", "765as", Some("#E22B30"), 9),
            source("second", "cinderella", Some("#e22b30"), 1),
            source("other_color", "765as", Some("#2743d2"), 2),
        ];
        let pools = build_pools(&src, &brands2());
        assert_eq!(ids(&pools.all_colored), vec!["first", "other_color"]);
    }

    /// ブランド別は「公式順に並べてから」一意化する (公式順で先の人が残る)。
    #[test]
    fn brand_pool_dedupes_after_official_sort() {
        let src = vec![
            source("later", "765as", Some("#E22B30"), 9),
            source("earlier", "765as", Some("#e22b30"), 1),
            source("c", "765as", Some("#2743d2"), 2),
            source("d", "765as", Some("#b4e04b"), 3),
            source("e", "765as", Some("#d9c8b7"), 4),
        ];
        let pools = build_pools(&src, &[brand("765as", 1)]);
        assert_eq!(ids(&pools.brand_pools[0].members), vec!["earlier", "c", "d", "e"]);
    }

    /// 公式順が同値なら DB から読んだ順を保つ (安定ソート)。
    #[test]
    fn brand_pool_keeps_input_order_for_equal_sort_order() {
        let src = vec![
            source("a", "765as", Some("#111111"), 5),
            source("b", "765as", Some("#222222"), 5),
            source("c", "765as", Some("#333333"), 5),
            source("d", "765as", Some("#444444"), 5),
        ];
        let pools = build_pools(&src, &[brand("765as", 1)]);
        assert_eq!(ids(&pools.brand_pools[0].members), vec!["a", "b", "c", "d"]);
    }

    /// 色が一意なメンバーが 4 人未満のブランドは出題母集団にしない。
    #[test]
    fn brand_with_too_few_colors_is_not_offered() {
        let src = vec![
            source("a", "tiny", Some("#111111"), 1),
            source("b", "tiny", Some("#222222"), 2),
            source("c", "tiny", Some("#333333"), 3),
        ];
        let pools = build_pools(&src, &[brand("tiny", 1)]);
        assert!(pools.brand_pools.is_empty());
        // 選択肢には出る (選ぶと開始できないだけ、という原本の挙動)。
        assert_eq!(strs(&pools.selectable_brand_ids), vec!["tiny"]);
    }

    /// 4 人ちょうどは出題できる (閾値の境界)。
    #[test]
    fn brand_with_exactly_the_minimum_is_offered() {
        let src: Vec<_> = (0..4)
            .map(|i| source(&format!("m{i}"), "tiny", Some(&format!("#11111{i}")), i))
            .collect();
        let pools = build_pools(&src, &[brand("tiny", 1)]);
        assert_eq!(pools.brand_pools.len(), 1);
        assert_eq!(pools.brand_pools[0].members.len(), MIN_BRAND_POOL_SIZE);
    }

    /// ブランドマスタに無い brand_id は brand_pools から落ちる (全体プールには残る)。
    #[test]
    fn unknown_brand_is_dropped_from_brand_pools() {
        let src: Vec<_> = (0..4)
            .map(|i| source(&format!("x{i}"), "ghost", Some(&format!("#11111{i}")), i))
            .collect();
        let pools = build_pools(&src, &[brand("765as", 1)]);
        assert!(pools.brand_pools.is_empty());
        assert_eq!(pools.all_colored.len(), 4);
    }

    #[test]
    fn build_pools_with_empty_inputs() {
        assert_eq!(build_pools(&[], &[]), ColorMatchPools::default());
    }

    // --- effective_pool ---

    #[test]
    fn no_selection_uses_all_brands() {
        let pools = build_pools(&sources(), &brands2());
        assert_eq!(effective_pool(&pools, &[]), pools.all_colored);
    }

    #[test]
    fn selection_narrows_to_that_brand() {
        let pools = build_pools(&sources(), &brands2());
        let picked = effective_pool(&pools, &["cinderella".to_string()]);
        assert_eq!(ids(&picked), vec!["uzuki", "rin", "mio", "mika"]);
    }

    /// ブランドを跨いだ同色は、ブランドの公式順で先に来る方だけ残る。
    #[test]
    fn cross_brand_duplicate_colors_are_deduped() {
        let mut src = sources();
        // シンデレラ側に 765AS の春香と同じ色の人を足す。
        src.push(source("twin", "cinderella", Some("#E22B30"), 5));
        let pools = build_pools(&src, &brands2());
        let picked = effective_pool(&pools, &["765as".to_string(), "cinderella".to_string()]);
        assert!(ids(&picked).contains(&"haruka"));
        assert!(!ids(&picked).contains(&"twin"), "同色の後発が残っている: {:?}", ids(&picked));
    }

    /// 4 人未満のブランドだけを選ぶと母集団が空になり、開始できない。
    #[test]
    fn selecting_only_an_unofferable_brand_yields_empty_pool() {
        let src = vec![
            source("a", "tiny", Some("#111111"), 1),
            source("b", "tiny", Some("#222222"), 2),
        ];
        let pools = build_pools(&src, &[brand("tiny", 1)]);
        let picked = effective_pool(&pools, &["tiny".to_string()]);
        assert!(picked.is_empty());
        assert!(picked.len() < MIN_POOL_SIZE);
    }

    #[test]
    fn unknown_selection_yields_empty_pool() {
        let pools = build_pools(&sources(), &brands2());
        assert!(effective_pool(&pools, &["nope".to_string()]).is_empty());
    }

    // --- companions: 難易度の規則そのもの ---

    /// アンカー (#808080) から等距離になる 2 人を含む候補。
    fn tie_candidates() -> (ColorMatchIdol, Vec<ColorMatchIdol>) {
        let anchor = idol("anchor", Some("#808080"));
        let rest = vec![
            idol("far", Some("#000000")),
            idol("tie_a", Some("#80a080")), // 緑 +32
            idol("near", Some("#808580")),  // 緑 +5
            idol("tie_b", Some("#806080")), // 緑 -32
        ];
        (anchor, rest)
    }

    #[test]
    fn tie_candidates_are_really_equidistant() {
        let (anchor, rest) = tie_candidates();
        assert_eq!(
            color_distance(anchor.color.as_deref(), rest[1].color.as_deref()),
            color_distance(anchor.color.as_deref(), rest[3].color.as_deref())
        );
    }

    /// むずい: アンカーに近い順。同距離は母集団の並び順で決まる (安定・決定的)。
    #[test]
    fn hard_ranks_by_distance_and_breaks_ties_by_pool_order() {
        let (anchor, rest) = tie_candidates();
        let picked =
            companions(&anchor, rest, 3, ColorMatchDifficulty::Hard, &mut SplitMix64(0));
        assert_eq!(ids(&picked), vec!["near", "tie_a", "tie_b"]);
    }

    /// やさしい: 最も遠い人から採る。同距離は最初の 1 件 (Swift `max(by:)` と同じ勝ち方)。
    #[test]
    fn easy_takes_the_farthest_and_breaks_ties_by_first_occurrence() {
        let (anchor, rest) = tie_candidates();
        let picked =
            companions(&anchor, rest.clone(), 1, ColorMatchDifficulty::Easy, &mut SplitMix64(0));
        assert_eq!(ids(&picked), vec!["far"]);

        // 2 人目以降は「既に選んだ全員から遠い」で選ぶ (アンカーからの距離だけではない)。
        let picked =
            companions(&anchor, rest, 3, ColorMatchDifficulty::Easy, &mut SplitMix64(0));
        assert_eq!(ids(&picked), vec!["far", "tie_a", "tie_b"]);
    }

    /// やさしいの結果は互いに離れている (むずいで同じ候補から採るより最小距離が大きい)。
    #[test]
    fn easy_spreads_colors_further_than_hard() {
        let pool = spread_pool(24);
        let anchor = pool[0].clone();
        let rest: Vec<_> = pool[1..].to_vec();
        let closest = |mut members: Vec<ColorMatchIdol>| {
            members.insert(0, anchor.clone());
            let mut min = f64::MAX;
            for (i, a) in members.iter().enumerate() {
                for b in &members[i + 1..] {
                    min = min.min(color_distance(a.color.as_deref(), b.color.as_deref()));
                }
            }
            min
        };
        let easy =
            companions(&anchor, rest.clone(), 3, ColorMatchDifficulty::Easy, &mut SplitMix64(0));
        let hard = companions(&anchor, rest, 5, ColorMatchDifficulty::Hard, &mut SplitMix64(0));
        assert!(
            closest(easy.clone()) > closest(hard.clone()),
            "easy={} hard={}",
            closest(easy),
            closest(hard)
        );
    }

    /// ふつう: 候補からランダム。引き直せば顔ぶれが変わる。
    #[test]
    fn normal_picks_a_random_subset() {
        let (anchor, _) = tie_candidates();
        let rest = spread_pool(10);
        let mut seen: HashSet<Vec<String>> = HashSet::new();
        for seed in 0..40 {
            let picked = companions(
                &anchor,
                rest.clone(),
                3,
                ColorMatchDifficulty::Normal,
                &mut SplitMix64(seed),
            );
            assert_eq!(picked.len(), 3);
            let unique: HashSet<&String> = picked.iter().map(|i| &i.id).collect();
            assert_eq!(unique.len(), 3, "同じ人が 2 回入った: {:?}", ids(&picked));
            seen.insert(picked.iter().map(|i| i.id.clone()).collect());
        }
        assert!(seen.len() > 1, "毎回同じ顔ぶれしか出ていない");
    }

    /// 候補が足りなければその分だけ少なく返す (どの難易度でも落ちない)。
    #[test]
    fn companions_with_too_few_candidates_returns_everything() {
        let anchor = idol("anchor", Some("#808080"));
        let rest = vec![idol("a", Some("#111111")), idol("b", Some("#222222"))];
        for difficulty in
            [ColorMatchDifficulty::Easy, ColorMatchDifficulty::Normal, ColorMatchDifficulty::Hard]
        {
            let picked = companions(&anchor, rest.clone(), 5, difficulty, &mut SplitMix64(1));
            let mut got = ids(&picked);
            got.sort();
            assert_eq!(got, vec!["a", "b"], "{difficulty:?}");
        }
    }

    #[test]
    fn companions_with_no_candidates_is_empty() {
        let anchor = idol("anchor", Some("#808080"));
        for difficulty in
            [ColorMatchDifficulty::Easy, ColorMatchDifficulty::Normal, ColorMatchDifficulty::Hard]
        {
            assert!(companions(&anchor, vec![], 3, difficulty, &mut SplitMix64(1)).is_empty());
        }
    }

    // --- index_of_first_max ---

    #[test]
    fn first_max_wins_on_ties() {
        assert_eq!(index_of_first_max(&[1.0, 3.0, 3.0, 2.0]), Some(1));
        assert_eq!(index_of_first_max(&[5.0]), Some(0));
        assert_eq!(index_of_first_max(&[f64::MAX, f64::MAX]), Some(0));
        assert_eq!(index_of_first_max(&[]), None);
    }

    // --- make_rounds: 形 ---

    #[test]
    fn generates_one_round_per_question() {
        let rounds = make_rounds(&pool6(), ColorMatchDifficulty::Normal, 10, &mut SplitMix64(1));
        assert_eq!(rounds.len(), 10);
    }

    #[test]
    fn zero_questions_yields_no_rounds() {
        assert!(make_rounds(&pool6(), ColorMatchDifficulty::Normal, 0, &mut SplitMix64(1))
            .is_empty());
    }

    /// 難易度ごとの出題人数 (母集団が十分なとき)。
    #[test]
    fn round_size_follows_difficulty() {
        let pool = spread_pool(20);
        for difficulty in
            [ColorMatchDifficulty::Easy, ColorMatchDifficulty::Normal, ColorMatchDifficulty::Hard]
        {
            for seed in 0..10 {
                let round = &make_rounds(&pool, difficulty, 1, &mut SplitMix64(seed))[0];
                assert_eq!(
                    round.members.len(),
                    difficulty.members_per_round(),
                    "{difficulty:?} seed={seed}"
                );
                assert_eq!(round.palette.len(), difficulty.members_per_round());
            }
        }
    }

    /// 母集団が難易度の人数に満たなければ全員で出題する (落ちない)。
    #[test]
    fn round_shrinks_to_pool_size() {
        let pool = vec![idol("a", Some("#111111")), idol("b", Some("#222222"))];
        let round = &make_rounds(&pool, ColorMatchDifficulty::Hard, 1, &mut SplitMix64(3))[0];
        assert_eq!(round.members.len(), 2);
        assert_eq!(round.palette.len(), 2);
    }

    /// 同じ人が 1 問の中で 2 回出ない。
    #[test]
    fn round_members_are_unique() {
        for seed in 0..40 {
            for difficulty in [
                ColorMatchDifficulty::Easy,
                ColorMatchDifficulty::Normal,
                ColorMatchDifficulty::Hard,
            ] {
                let round = &make_rounds(&pool6(), difficulty, 1, &mut SplitMix64(seed))[0];
                let unique: HashSet<&String> = round.members.iter().map(|m| &m.id).collect();
                assert_eq!(unique.len(), round.members.len(), "{difficulty:?} seed={seed}");
            }
        }
    }

    /// パレットは出題メンバーの色 (原文) の並べ替え。
    /// ここがずれると「正解の色がパレットに無い」問題ができてしまう。
    #[test]
    fn palette_is_a_permutation_of_member_colors() {
        for seed in 0..40 {
            let round =
                &make_rounds(&pool6(), ColorMatchDifficulty::Normal, 1, &mut SplitMix64(seed))[0];
            let mut from_members: Vec<String> =
                round.members.iter().map(|m| m.color.clone().unwrap_or_default()).collect();
            let mut palette = round.palette.clone();
            from_members.sort();
            palette.sort();
            assert_eq!(from_members, palette, "seed={seed}");
        }
    }

    /// 母集団が 2 人未満なら空の問題を問題数ぶん返す (呼び出し側で開始を止める前提)。
    #[test]
    fn pool_below_minimum_yields_empty_rounds() {
        for pool in [Vec::new(), vec![idol("only", Some("#111111"))]] {
            let rounds = make_rounds(&pool, ColorMatchDifficulty::Normal, 5, &mut SplitMix64(1));
            assert_eq!(rounds.len(), 5);
            assert!(rounds.iter().all(|r| *r == ColorMatchRound::default()));
        }
    }

    /// 色未設定の人しかいない母集団でも落ちない (防御。実際は母集団に入らない)。
    #[test]
    fn round_with_colorless_pool_does_not_panic() {
        let pool = vec![idol("a", None), idol("b", None), idol("c", None), idol("d", None)];
        for difficulty in [
            ColorMatchDifficulty::Easy,
            ColorMatchDifficulty::Normal,
            ColorMatchDifficulty::Hard,
        ] {
            let round = &make_rounds(&pool, difficulty, 1, &mut SplitMix64(9))[0];
            assert_eq!(round.members.len(), 4);
            assert_eq!(round.palette, vec!["", "", "", ""]);
        }
    }

    // --- make_rounds: 乱数の性質 ---

    /// 同じシードなら (プラットフォームによらず) 同じ出題になる。
    #[test]
    fn same_seed_gives_same_game() {
        let pool = pool6();
        assert_eq!(
            make_rounds(&pool, ColorMatchDifficulty::Normal, 5, &mut SplitMix64(42)),
            make_rounds(&pool, ColorMatchDifficulty::Normal, 5, &mut SplitMix64(42))
        );
    }

    /// 引き直せば違うゲームになる (毎回同じ出題ではない)。
    #[test]
    fn different_seeds_give_different_games() {
        let pool = pool6();
        let games: HashSet<Vec<Vec<String>>> = (0..40)
            .map(|seed| {
                make_rounds(&pool, ColorMatchDifficulty::Normal, 5, &mut SplitMix64(seed))
                    .iter()
                    .map(|r| r.members.iter().map(|m| m.id.clone()).collect())
                    .collect()
            })
            .collect();
        assert!(games.len() > 1, "毎回同じ出題しか出ていない");
    }

    /// 1 ゲームの中で全問が同一にならない (rng を通しで使う)。
    #[test]
    fn rounds_within_a_game_vary() {
        let rounds =
            make_rounds(&spread_pool(20), ColorMatchDifficulty::Normal, 10, &mut SplitMix64(7));
        let unique: HashSet<Vec<&str>> = rounds.iter().map(|r| ids(&r.members)).collect();
        assert!(unique.len() > 1, "全問同じメンバーが出ている");
    }

    /// 特定の人がアンカー固定にならない (母集団全員に出番がある)。
    #[test]
    fn every_pool_member_can_appear() {
        let pool = pool6();
        let mut seen: HashSet<String> = HashSet::new();
        for seed in 0..80 {
            for round in make_rounds(&pool, ColorMatchDifficulty::Easy, 5, &mut SplitMix64(seed)) {
                seen.extend(round.members.iter().map(|m| m.id.clone()));
            }
        }
        assert_eq!(seen.len(), pool.len(), "出番のないメンバーがいる: {seen:?}");
    }

    /// パレットの並びが行の並びと一致し続けない (位置で当てられない)。
    #[test]
    fn palette_order_is_not_locked_to_member_order() {
        let pool = pool6();
        let mismatched = (0..40).any(|seed| {
            let round =
                &make_rounds(&pool, ColorMatchDifficulty::Normal, 1, &mut SplitMix64(seed))[0];
            let member_colors: Vec<String> =
                round.members.iter().map(|m| m.color.clone().unwrap_or_default()).collect();
            member_colors != round.palette
        });
        assert!(mismatched, "パレットが常にメンバーと同順になっている");
    }

    // --- judge_round ---

    fn three_members() -> Vec<ColorMatchIdol> {
        vec![
            idol("haruka", Some("#e22b30")),
            idol("chihaya", Some("#2743d2")),
            idol("miki", Some("#b4e04b")),
        ]
    }

    #[test]
    fn all_correct() {
        let assignments = vec![
            assign("haruka", "#e22b30"),
            assign("chihaya", "#2743d2"),
            assign("miki", "#b4e04b"),
        ];
        let judged = judge_round(&three_members(), &assignments);
        assert_eq!(judged.correct, vec![true, true, true]);
        assert_eq!(judged.score, 3);
        assert_eq!(judged.out_of, 3);
        assert_eq!(strs(&judged.correct_hex_labels), vec!["#E22B30", "#2743D2", "#B4E04B"]);
    }

    #[test]
    fn all_wrong() {
        let assignments = vec![
            assign("haruka", "#2743d2"),
            assign("chihaya", "#b4e04b"),
            assign("miki", "#e22b30"),
        ];
        let judged = judge_round(&three_members(), &assignments);
        assert_eq!(judged.correct, vec![false, false, false]);
        assert_eq!(judged.score, 0);
        assert_eq!(judged.out_of, 3);
    }

    #[test]
    fn partially_correct() {
        let assignments = vec![assign("haruka", "#e22b30"), assign("chihaya", "#b4e04b")];
        let judged = judge_round(&three_members(), &assignments);
        // 3 人目は未割当 = 不正解。
        assert_eq!(judged.correct, vec![true, false, false]);
        assert_eq!(judged.score, 1);
        assert_eq!(judged.out_of, 3);
    }

    /// 表記ゆれ (大文字 / 3 桁短縮 / 前後空白) でも同じ色なら正解。
    #[test]
    fn judging_ignores_hex_notation_differences() {
        let members = vec![idol("a", Some("#ff00aa")), idol("b", Some("#E22B30"))];
        let assignments = vec![assign("a", "F0A"), assign("b", " #e22b30 ")];
        assert_eq!(judge_round(&members, &assignments).score, 2);
    }

    /// 色が無いメンバーは何を置いても不正解 (Android の行表示だけずれていた箇所)。
    #[test]
    fn member_without_color_is_never_correct() {
        let members = vec![idol("nocolor", None)];
        for hex in ["#e22b30", "", "nope"] {
            let judged = judge_round(&members, &[assign("nocolor", hex)]);
            assert_eq!(judged.correct, vec![false], "hex={hex:?}");
            assert_eq!(strs(&judged.correct_hex_labels), vec!["—"]);
        }
    }

    #[test]
    fn no_assignments_scores_zero() {
        let judged = judge_round(&three_members(), &[]);
        assert_eq!(judged.score, 0);
        assert_eq!(judged.out_of, 3);
        assert_eq!(judged.correct, vec![false, false, false]);
    }

    #[test]
    fn empty_round_judges_to_zero() {
        assert_eq!(judge_round(&[], &[]), ColorMatchJudgement::default());
    }

    /// 他人あての割り当ては効かない (id で引く)。
    #[test]
    fn assignment_for_another_member_is_ignored() {
        let judged = judge_round(&three_members(), &[assign("chihaya", "#e22b30")]);
        assert_eq!(judged.correct, vec![false, false, false]);
    }

    /// 同じ id が複数あれば最初の 1 件を採る (原本の辞書と同じ「1 人 1 色」)。
    #[test]
    fn duplicate_assignment_takes_the_first() {
        let members = vec![idol("a", Some("#e22b30"))];
        let assignments = vec![assign("a", "#e22b30"), assign("a", "#000000")];
        assert_eq!(judge_round(&members, &assignments).score, 1);
    }

    /// 出題 → 全問正解の一貫性: 生成された色を本人へ配れば必ず満点になる。
    #[test]
    fn generated_round_can_be_answered_perfectly() {
        let pool = pool6();
        for seed in 0..40 {
            let round = &make_rounds(&pool, ColorMatchDifficulty::Hard, 1, &mut SplitMix64(seed))[0];
            let assignments: Vec<_> = round
                .members
                .iter()
                .map(|m| assign(&m.id, m.color.as_deref().unwrap_or("")))
                .collect();
            let judged = judge_round(&round.members, &assignments);
            assert_eq!(judged.score, judged.out_of, "seed={seed}");
            assert!(judged.correct.iter().all(|&ok| ok));
        }
    }

    // --- accuracy_percent ---

    #[test]
    fn accuracy_of_no_answers_is_zero() {
        assert_eq!(accuracy_percent(0, 0), 0);
        // 分子だけ立っている壊れた入力でも 0 (0 除算しない)。
        assert_eq!(accuracy_percent(5, 0), 0);
    }

    #[test]
    fn accuracy_extremes() {
        assert_eq!(accuracy_percent(25, 25), 100);
        assert_eq!(accuracy_percent(0, 25), 0);
    }

    #[test]
    fn accuracy_rounds_to_nearest() {
        assert_eq!(accuracy_percent(1, 3), 33); // 33.33…
        assert_eq!(accuracy_percent(2, 3), 67); // 66.66…
        assert_eq!(accuracy_percent(1, 2), 50);
    }

    /// ちょうど 0.5 は大きい側へ (Swift `rounded()` = away from zero)。
    #[test]
    fn accuracy_rounds_half_up() {
        assert_eq!(accuracy_percent(1, 8), 13); // 12.5
        assert_eq!(accuracy_percent(3, 8), 38); // 37.5
    }

    /// 1 ゲームぶんの積み上げ (判定 → 加算 → 正答率) が噛み合う。
    #[test]
    fn session_totals_feed_accuracy() {
        let rounds = make_rounds(&pool6(), ColorMatchDifficulty::Easy, 5, &mut SplitMix64(11));
        let (mut correct, mut answered) = (0u32, 0u32);
        for round in &rounds {
            // 1 人目だけ正解、残りは未割当。
            let assignments: Vec<_> = round
                .members
                .first()
                .map(|m| vec![assign(&m.id, m.color.as_deref().unwrap_or(""))])
                .unwrap_or_default();
            let judged = judge_round(&round.members, &assignments);
            correct += judged.score;
            answered += judged.out_of;
        }
        assert_eq!(correct, 5);
        assert_eq!(answered, 20);
        assert_eq!(accuracy_percent(correct, answered), 25);
    }
}
