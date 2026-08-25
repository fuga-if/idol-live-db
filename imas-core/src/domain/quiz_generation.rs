//! 4 択クイズ (アイドル当てクイズ / ソロ曲クイズ) の出題・採点規則。
//!
//! ## なぜ 1 か所に置くか
//!
//! iOS `Views/Games/IdolQuiz{View,SetupView}.swift` / `SongSingerQuiz{View,SetupView}.swift` /
//! `QuizComponents.swift` と Android `ui/games/*.kt` が file-for-file の写経で、規則の実体が
//! 2 つある。突き合わせた時点で実際に次の乖離が出ていた (すべて **iOS を正**として集約):
//!
//! - 出題対象の除外: iOS `!idol.isExternal` / Android `brandId != "other"`
//!   (現行データは `is_external` が全件 0 なので、iOS はブランド `other` のゲスト
//!   キャラも出題する。Android は出さない = 出題母集団そのものが違う)
//! - Android の出題設定画面だけ「事実 3 件以上」を見ておらず、開始できるのに
//!   ゲーム側で候補不足になる (iOS が一度直したバグの Android 未反映)
//! - CV ヒントは iOS のみ (Android は `Idol.voiceActors` を持つのに facts に入れていない)
//! - 身長/誕生日の表示: iOS `160.5cm` / `4月3日`、Android `160cm` / `04月03日`
//!
//! ## FFI 境界の形
//!
//! - **1 ゲーム分の出題をまとめて 1 回**で生成する ([`idol_quiz_session`] /
//!   [`song_singer_quiz_session`])。問題ごとに FFI を呼ぶ形は禁止 (README の境界規約)。
//! - エンティティは渡さず、出題に要る列だけの射影を受け、**入力配列の index** を返す
//!   (呼び出し側が自国の `Idol` 配列を index で引く)。
//! - 乱数は OS から取らず、シード注入の [`SplitMix64`] に一本化する。シードの調達
//!   (実行時はシステム乱数、テストは固定値) は各プラットフォームの薄いラッパの責務。
//!
//! ## ここに置かないもの
//!
//! - 進捗/自己ベストの永続化と「デイリー達成・連続日数」= `domain::game_progress`
//!   (連続日数は**端末ローカル日**が単位。公演日の JST 固定日 `jst_day` とは意味が違う)。
//!   本モジュールは日付を一切扱わない。
//! - **自己ベストの更新規則そのもの** (更新したか / 更新後の自己ベスト率) も
//!   `domain::game_progress` だけが持つ。ここに写すと同じ規則の 2 実装になり、
//!   片方だけ直した瞬間にリザルトの表示がずれる。[`quiz_session_result`] は自己ベストを
//!   引数に取らず、リザルト画面は次の順で組む (原本 iOS `QuizResultView` と同じ順序):
//!   1. [`quiz_session_result`] で今回の点・率・グレードと、記録用の分母 `out_of` を得る
//!   2. `game_progress::apply_result(score = points, out_of = out_of, ...)` で保存する
//!   3. 「自己ベスト更新！」バッジは 2 の `is_new_best`、表示する自己ベスト率は 2 が返した
//!      **記録後**の `GameRecord::best_rate_percent()` (記録が無ければ今回の率で代用)
//! - リザルトの講評文・進捗バーの割合・履歴行の組み立てなど、計算を伴わない表示は各 OS。

use std::borrow::Cow;
use std::collections::{HashMap, HashSet};

use unicode_normalization::{is_nfc_quick, IsNormalized, UnicodeNormalization};

use crate::domain::prng::SplitMix64;

// ---------------------------------------------------------------------------
// 規則の定数
// ---------------------------------------------------------------------------

/// 1 セッションの出題数 (両クイズ共通: iOS `sessionLength` / Android `SESSION_LENGTH`)。
pub const SESSION_LENGTH: u32 = 10;

/// アイドル当てクイズのノーヒント正解の素点 (iOS `basePoints`)。
pub const IDOL_QUIZ_BASE_POINTS: u32 = 10;

/// ソロ曲クイズのノーヒント正解の素点 (iOS `QuizScoring.maxPoints`)。
pub const SONG_QUIZ_MAX_POINTS: u32 = 3;

/// 4 択の誤答候補数 (iOS `quizDistractors` の prefix(3))。
pub const DISTRACTOR_COUNT: u32 = 3;

/// 4 択を成立させるために必要な最低候補数 (出題設定画面の `minimumPool`)。
pub const MINIMUM_POOL: u32 = 4;

/// 4 択を組めるだけの候補があるか。
///
/// 出題設定画面の見積りとゲーム本体は**必ずこの判定を共有する**。別条件にすると
/// 「設定画面は不足と言うのにゲームは始まり、しかも選択肢が 4 つ未満」になる。
fn has_enough_candidates(count: usize) -> bool {
    count >= MINIMUM_POOL as usize
}

/// 出題に使うのに必要なプロフィール事実の最低数 (`isIdolQuizEligible` の facts >= 3)。
const MINIMUM_FACTS: usize = 3;

/// CV 未発表キャラのヒント値。枠自体は常に出す (下の [`idol_quiz_facts`] 参照)。
const VOICE_ACTOR_UNANNOUNCED: &str = "声優未発表";

// ---------------------------------------------------------------------------
// 文字列比較 (Swift の String == 互換)
// ---------------------------------------------------------------------------

/// Swift の `String ==` / `Set<String>` に合わせた比較キー。Swift は Unicode 正準等価
/// (NFC の「ガ」と NFD の「カ + ﾞ」を同一視) なので、バイト同値の Rust でそのまま比較すると
/// 表現違いの同一 id を別物と見なし、**正解と同じアイドルが誤答候補にも並ぶ**
/// (「正解を選んだのに不正解」) 事故になる。アイドル id は `cg_大石泉` のように日本語を
/// 含むので実害があり得る。
///
/// `domain::intro_quiz_choices` にも同じ private ヘルパがあるが、あちらは今回の担当外
/// ファイルなので共有化はせず同じ流儀で持つ (将来どちらかへ集約する)。
fn canonical(s: &str) -> Cow<'_, str> {
    match is_nfc_quick(s.chars()) {
        IsNormalized::Yes => Cow::Borrowed(s),
        IsNormalized::No | IsNormalized::Maybe => Cow::Owned(s.nfc().collect()),
    }
}

/// 出題ブランド絞り込み。空 = 全ブランド対象 (両 OS とも「空集合 = 全て」)。
struct BrandFilter {
    keys: HashSet<String>,
}

impl BrandFilter {
    fn new(selected_brand_ids: &[String]) -> Self {
        Self { keys: selected_brand_ids.iter().map(|b| canonical(b).into_owned()).collect() }
    }

    fn matches(&self, brand_id: &str) -> bool {
        self.keys.is_empty() || self.keys.contains(canonical(brand_id).as_ref())
    }
}

// ---------------------------------------------------------------------------
// 射影 (FFI で受け取る最小の入力)
// ---------------------------------------------------------------------------

/// アイドル当てクイズが要るアイドルの射影。
///
/// `voice_actor` は現任 CV 名 (iOS `VoiceActorDirectory.current(for:)` /
/// Android `Idol.currentVoiceActor`)。未発表は `None` で渡す。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct IdolQuizIdolRef {
    pub id: String,
    pub brand_id: String,
    /// 外部ゲスト演者。出題対象から外す。
    pub is_external: bool,
    /// メンバーカラー (HEX)。空/未設定は出題対象外。
    pub color: Option<String>,
    pub blood_type: Option<String>,
    pub constellation: Option<String>,
    pub birth_place: Option<String>,
    pub height: Option<f64>,
    pub age: Option<i32>,
    pub hobbies: Option<String>,
    pub talents: Option<String>,
    /// 生の `--MM-DD` (整形は [`idol_quiz_facts`] 側で行う)。
    pub birthday: Option<String>,
    pub voice_actor: Option<String>,
}

/// ソロ曲クイズの選択肢に使うアイドルの射影 (歌手当てなのでプロフィールは要らない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SongQuizSingerRef {
    pub id: String,
    pub brand_id: String,
    pub is_external: bool,
}

/// `song_artists(role='original')` の 1 行。ソロ曲 (`song_type='solo'`) 分だけ渡す。
/// 原唱が 1 人の曲だけが出題対象になる規則は [`song_singer_quiz_pool`] が持つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SongQuizOriginalArtistRow {
    pub song_id: String,
    pub idol_id: String,
}

/// 選択肢抽選だけに要る最小情報 (両クイズ共通の内部表現)。
struct ChoiceRef {
    id: String,
    brand_id: String,
}

impl ChoiceRef {
    fn from_idol(idol: &IdolQuizIdolRef) -> Self {
        Self { id: canonical(&idol.id).into_owned(), brand_id: canonical(&idol.brand_id).into_owned() }
    }

    fn from_singer(singer: &SongQuizSingerRef) -> Self {
        Self { id: canonical(&singer.id).into_owned(), brand_id: canonical(&singer.brand_id).into_owned() }
    }
}

// ---------------------------------------------------------------------------
// プロフィール事実 (アイドル当てクイズの出題文 + ヒント)
// ---------------------------------------------------------------------------

/// プロフィール事実の種別。
///
/// 原本は表示ラベルの文字列一致 (`f.label == "メンバーカラー"`) で色チップに分岐していたが、
/// 文字列比較は文言を直した瞬間に壊れるので種別を持たせる (`label` は現行文言のまま返す)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum IdolQuizFactKind {
    BloodType,
    Constellation,
    BirthPlace,
    Height,
    Age,
    Hobbies,
    Talents,
    Birthday,
    MemberColor,
    VoiceActor,
}

impl IdolQuizFactKind {
    /// 表示ラベル (原本の文言)。
    fn label(self) -> &'static str {
        match self {
            Self::BloodType => "血液型",
            Self::Constellation => "星座",
            Self::BirthPlace => "出身",
            Self::Height => "身長",
            Self::Age => "年齢",
            Self::Hobbies => "趣味",
            Self::Talents => "特技",
            Self::Birthday => "誕生日",
            Self::MemberColor => "メンバーカラー",
            Self::VoiceActor => "CV",
        }
    }

    /// 開封コスト。メンバーカラーと CV は一気に正体が割れるので重い (-2pt)。
    fn cost(self) -> u32 {
        match self {
            Self::MemberColor | Self::VoiceActor => 2,
            _ => 1,
        }
    }
}

/// 公開できるプロフィール事実 1 件。`facts[0]` が無料公開、以降がヒント。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct IdolQuizFact {
    pub kind: IdolQuizFactKind,
    pub label: String,
    pub value: String,
    pub cost: u32,
}

impl IdolQuizFact {
    fn new(kind: IdolQuizFactKind, value: impl Into<String>) -> Self {
        Self { kind, label: kind.label().to_string(), value: value.into(), cost: kind.cost() }
    }
}

/// 空文字は「無い」と同じ扱い (原本の `!$0.isEmpty` ガード)。
fn text_fact(kind: IdolQuizFactKind, value: &Option<String>) -> Option<IdolQuizFact> {
    value.as_deref().filter(|v| !v.is_empty()).map(|v| IdolQuizFact::new(kind, v))
}

/// 身長表示 (iOS `Idol.heightDisplay`)。整数なら `160cm`、端数があれば `160.5cm`。
/// Android は `toInt()` で端数を落としていた (乖離、iOS を正とする)。
fn height_display(height: Option<f64>) -> Option<String> {
    let h = height?;
    Some(if h % 1.0 == 0.0 { format!("{}cm", h as i64) } else { format!("{h}cm") })
}

/// 誕生日表示 (iOS `Idol.birthdayDisplay`)。`--04-03` → `4月3日` (0 埋めは落とす)。
/// `--` 始まりでない・月日が解釈できない場合は原文をそのまま返す (原本の guard と同じ)。
/// Android は 0 埋めのまま `04月03日` にしていた (乖離、iOS を正とする)。
fn birthday_display(birthday: &Option<String>) -> Option<String> {
    let raw = birthday.as_deref()?;
    let Some(rest) = raw.strip_prefix("--") else { return Some(raw.to_string()) };
    // Swift の split(separator:) は空要素を捨てるので、フィルタして同じ挙動に揃える。
    let parts: Vec<&str> = rest.split('-').filter(|p| !p.is_empty()).collect();
    match parts.as_slice() {
        [m, d] => match (m.parse::<i32>(), d.parse::<i32>()) {
            (Ok(m), Ok(d)) => Some(format!("{m}月{d}日")),
            _ => Some(raw.to_string()),
        },
        _ => Some(raw.to_string()),
    }
}

/// プロフィール事実を「曖昧 (絞り込みにくい) → 特定 (バレやすい)」の順で返す。
/// 先頭が無料公開、後ろほど答えに近い。
///
/// CV は値の有無によらず**常にスロットを出す**。枠の有無で「声優未発表キャラだ」と
/// 無料でバレるのを防ぐためで、開封して初めて「声優未発表」と分かる。
pub fn idol_quiz_facts(idol: &IdolQuizIdolRef) -> Vec<IdolQuizFact> {
    use IdolQuizFactKind::*;
    let mut facts: Vec<IdolQuizFact> = Vec::with_capacity(10);
    // 曖昧グループ (該当者が多い)
    facts.extend(text_fact(BloodType, &idol.blood_type));
    facts.extend(text_fact(Constellation, &idol.constellation));
    facts.extend(text_fact(BirthPlace, &idol.birth_place));
    facts.extend(height_display(idol.height).map(|v| IdolQuizFact::new(Height, v)));
    facts.extend(idol.age.map(|a| IdolQuizFact::new(Age, format!("{a}歳"))));
    // 特定グループ (一気に絞れる)
    facts.extend(text_fact(Hobbies, &idol.hobbies));
    facts.extend(text_fact(Talents, &idol.talents));
    facts.extend(
        birthday_display(&idol.birthday)
            .filter(|v| !v.is_empty())
            .map(|v| IdolQuizFact::new(Birthday, v)),
    );
    facts.extend(text_fact(MemberColor, &idol.color));
    facts.push(IdolQuizFact::new(
        VoiceActor,
        idol.voice_actor.as_deref().filter(|v| !v.is_empty()).unwrap_or(VOICE_ACTOR_UNANNOUNCED),
    ));
    facts
}

/// アイドル当てクイズの出題対象として使えるか (iOS `isIdolQuizEligible`)。
///
/// 出題設定画面の見積りとゲーム本体が別条件になると「開始できるのに候補不足」になるので、
/// 母集団の条件はこの 1 関数だけが持つ。
fn is_idol_quiz_eligible(idol: &IdolQuizIdolRef, brands: &BrandFilter) -> bool {
    !idol.is_external
        && idol.color.as_deref().is_some_and(|c| !c.is_empty())
        && idol_quiz_facts(idol).len() >= MINIMUM_FACTS
        && brands.matches(&idol.brand_id)
}

/// 出題母集団の index 列 (`idols` の並びを保つ)。
pub fn idol_quiz_pool_indices(idols: &[IdolQuizIdolRef], selected_brand_ids: &[String]) -> Vec<u32> {
    let brands = BrandFilter::new(selected_brand_ids);
    idols
        .iter()
        .enumerate()
        .filter(|(_, idol)| is_idol_quiz_eligible(idol, &brands))
        .map(|(i, _)| i as u32)
        .collect()
}

/// 出題設定画面の候補数見積り。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct IdolQuizPoolEstimate {
    /// 出題候補アイドル数。
    pub count: u32,
    /// 4 択を組めるか (画面側は「推計中は暫定的に許可」と OR する)。
    pub is_sufficient: bool,
}

pub fn idol_quiz_pool_estimate(
    idols: &[IdolQuizIdolRef],
    selected_brand_ids: &[String],
) -> IdolQuizPoolEstimate {
    let pool = idol_quiz_pool_indices(idols, selected_brand_ids);
    IdolQuizPoolEstimate {
        count: pool.len() as u32,
        is_sufficient: has_enough_candidates(pool.len()),
    }
}

// ---------------------------------------------------------------------------
// 抽選 (既出を避ける + 4 択の誤答候補)
// ---------------------------------------------------------------------------

/// 「既出を除いて 1 件引く。尽きたら一巡してリセット」の抽選器 (原本 `makeQuestion` の規則)。
/// セッションが母集団より長いときだけ 2 周目に入るので、短いセッション中の重複は起きない。
struct SequentialDraw {
    seen: Vec<bool>,
    remaining: usize,
}

impl SequentialDraw {
    fn new(total: usize) -> Self {
        Self { seen: vec![false; total], remaining: total }
    }

    /// 未出のうち 1 件を一様に選び、既出に印を付ける。母集団が空なら `None`。
    fn next(&mut self, rng: &mut SplitMix64) -> Option<usize> {
        if self.seen.is_empty() {
            return None;
        }
        if self.remaining == 0 {
            self.seen.fill(false);
            self.remaining = self.seen.len();
        }
        // 「未出だけを詰めた配列から randomElement()」と同じ = 未出の中の nth 番目。
        let nth = rng.next_below(self.remaining as u64) as usize;
        let picked = self
            .seen
            .iter()
            .enumerate()
            .filter(|(_, &seen)| !seen)
            .map(|(i, _)| i)
            .nth(nth)
            .expect("remaining は未出の件数と一致する");
        self.seen[picked] = true;
        self.remaining -= 1;
        Some(picked)
    }
}

/// 誤答候補 (pool 内の位置) を `count` 件選ぶ。同ブランドを優先し、足りなければ他ブランドで補う。
/// 除外は**位置ではなく id** で行う (原本の `$0.id != answer.id`)。同じアイドルが母集団に
/// 二重に入っていても、正解と同じ人物が誤答に並ばない。
fn distractor_positions(
    pool: &[ChoiceRef],
    answer: &ChoiceRef,
    count: u32,
    rng: &mut SplitMix64,
) -> Vec<usize> {
    let others: Vec<usize> =
        (0..pool.len()).filter(|&i| pool[i].id != answer.id).collect();
    let mut same_brand: Vec<usize> =
        others.iter().copied().filter(|&i| pool[i].brand_id == answer.brand_id).collect();
    rng.shuffle(&mut same_brand);
    if same_brand.len() < count as usize {
        let mut cross_brand: Vec<usize> =
            others.into_iter().filter(|&i| pool[i].brand_id != answer.brand_id).collect();
        rng.shuffle(&mut cross_brand);
        same_brand.extend(cross_brand);
    }
    same_brand.truncate(count as usize);
    same_brand
}

/// 正解 + 誤答を混ぜた選択肢 (pool 内の位置) を返す。
fn choice_positions(
    pool: &[ChoiceRef],
    answer_position: usize,
    rng: &mut SplitMix64,
) -> Vec<usize> {
    let mut choices = distractor_positions(pool, &pool[answer_position], DISTRACTOR_COUNT, rng);
    choices.push(answer_position);
    // 正解が常に末尾だと位置で当てられるので混ぜる (原本の shuffled())。
    rng.shuffle(&mut choices);
    choices
}

// ---------------------------------------------------------------------------
// アイドル当てクイズ: 1 セッション分の出題
// ---------------------------------------------------------------------------

/// 出題 1 問。index はいずれも [`idol_quiz_session`] に渡した `idols` を指す。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct IdolQuizQuestion {
    pub answer: u32,
    /// 表示順の 4 択 (候補が足りなければ少なくなる。正解は必ず含む)。
    pub choices: Vec<u32>,
    /// `facts[0]` が無料公開、以降がヒント。
    pub facts: Vec<IdolQuizFact>,
}

/// 1 ゲーム分 (`session_length` 問) の出題をまとめて生成する。
///
/// 母集団が 4 人未満なら空を返す (画面は「出題できる候補が不足しています」)。
/// 出題ごとに FFI を呼ぶ形を避けるため、境界を跨ぐのはこの 1 回だけにする。
pub fn idol_quiz_session(
    idols: &[IdolQuizIdolRef],
    selected_brand_ids: &[String],
    session_length: u32,
    rng: &mut SplitMix64,
) -> Vec<IdolQuizQuestion> {
    let pool = idol_quiz_pool_indices(idols, selected_brand_ids);
    if !has_enough_candidates(pool.len()) {
        return Vec::new();
    }
    let choice_pool: Vec<ChoiceRef> =
        pool.iter().map(|&i| ChoiceRef::from_idol(&idols[i as usize])).collect();
    let mut draw = SequentialDraw::new(pool.len());
    (0..session_length)
        .filter_map(|_| {
            let answer_position = draw.next(rng)?;
            let answer = pool[answer_position];
            Some(IdolQuizQuestion {
                answer,
                choices: choice_positions(&choice_pool, answer_position, rng)
                    .into_iter()
                    .map(|p| pool[p])
                    .collect(),
                facts: idol_quiz_facts(&idols[answer as usize]),
            })
        })
        .collect()
}

// ---------------------------------------------------------------------------
// ソロ曲クイズ: 母集団と 1 セッション分の出題
// ---------------------------------------------------------------------------

/// 出題対象の (ソロ曲, 原唱歌手) 1 組。`singer` は入力 `singers` の index。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SongQuizPair {
    pub song_id: String,
    pub singer: u32,
}

/// ソロ曲クイズの母集団。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SongSingerQuizPool {
    /// 出題候補の (曲, 歌手)。`rows` の並びを保つ。
    pub pairs: Vec<SongQuizPair>,
    /// 4 択に使う歌手 (`singers` の index、初出順・重複なし)。
    pub singer_pool: Vec<u32>,
}

impl SongSingerQuizPool {
    /// 出題できる母集団か。曲数と歌手数の**両方**が 4 以上必要
    /// (曲が 4 曲あっても歌手が 3 人なら 4 択が組めない)。
    ///
    /// アイドル当てクイズの [`is_idol_quiz_eligible`] と同じく、見積り画面とゲーム本体は
    /// この 1 か所だけを見る。
    fn is_sufficient(&self) -> bool {
        has_enough_candidates(self.pairs.len()) && has_enough_candidates(self.singer_pool.len())
    }
}

/// 原唱が**単独**のソロ曲だけを母集団にする。
///
/// 複数人が原唱の曲は「歌うのは誰？」の答えが一意にならないので落とす。歌手が
/// 外部ゲスト・対象外ブランドの場合も落とす。`rows` は呼び出し側の出題順
/// (iOS は曲名かな順) で渡す。並びはそのまま母集団の並びになる。
pub fn song_singer_quiz_pool(
    rows: &[SongQuizOriginalArtistRow],
    singers: &[SongQuizSingerRef],
    selected_brand_ids: &[String],
) -> SongSingerQuizPool {
    let brands = BrandFilter::new(selected_brand_ids);
    let singer_index: HashMap<Cow<'_, str>, u32> = singers
        .iter()
        .enumerate()
        // 同 id が複数あれば先勝ち (Swift の Dictionary(uniqueKeysWithValues:) は
        // 一意前提だが、id は主キーなので実データでは衝突しない)。
        .fold(HashMap::new(), |mut acc, (i, s)| {
            acc.entry(canonical(&s.id)).or_insert(i as u32);
            acc
        });

    // 曲ごとの原唱行数を数え、ちょうど 1 行の曲だけを残す (原本の `ids.count == 1`)。
    let mut row_count: HashMap<Cow<'_, str>, u32> = HashMap::new();
    for row in rows {
        *row_count.entry(canonical(&row.song_id)).or_insert(0) += 1;
    }

    let mut pairs: Vec<SongQuizPair> = Vec::new();
    let mut singer_pool: Vec<u32> = Vec::new();
    let mut pooled: HashSet<u32> = HashSet::new();
    for row in rows {
        if row_count.get(canonical(&row.song_id).as_ref()) != Some(&1) {
            continue;
        }
        let Some(&singer) = singer_index.get(canonical(&row.idol_id).as_ref()) else { continue };
        let s = &singers[singer as usize];
        if s.is_external || !brands.matches(&s.brand_id) {
            continue;
        }
        pairs.push(SongQuizPair { song_id: row.song_id.clone(), singer });
        if pooled.insert(singer) {
            singer_pool.push(singer);
        }
    }
    SongSingerQuizPool { pairs, singer_pool }
}

/// 出題設定画面の候補数見積り。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongSingerQuizPoolEstimate {
    pub song_count: u32,
    pub singer_count: u32,
    /// 4 択を組めるか。曲数と歌手数の**両方**が 4 以上必要 (選択肢の基準は歌手数)。
    pub is_sufficient: bool,
}

pub fn song_singer_quiz_pool_estimate(
    rows: &[SongQuizOriginalArtistRow],
    singers: &[SongQuizSingerRef],
    selected_brand_ids: &[String],
) -> SongSingerQuizPoolEstimate {
    let pool = song_singer_quiz_pool(rows, singers, selected_brand_ids);
    SongSingerQuizPoolEstimate {
        song_count: pool.pairs.len() as u32,
        singer_count: pool.singer_pool.len() as u32,
        is_sufficient: pool.is_sufficient(),
    }
}

/// 出題 1 問。`answer` / `choices` は入力 `singers` の index。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SongSingerQuizQuestion {
    pub song_id: String,
    pub answer: u32,
    pub choices: Vec<u32>,
}

/// 1 ゲーム分 (`session_length` 問) の出題をまとめて生成する。
///
/// 母集団が [`SongSingerQuizPool::is_sufficient`] を満たさなければ空を返す
/// (画面は「出題できる候補が不足しています」)。
///
/// 原本 (iOS `SongSingerQuizView.makeQuestion`) は曲数 `pool.count >= 4` しか見ておらず、
/// 歌手が 3 人以下でも 10 問出していた。設定画面の `canStart` は曲数と歌手数の両方を見るので
/// 条件が食い違っており、`master.sqlite` のブランド 961 (ソロ曲 4 曲 / 原唱歌手 2 名) を選ぶと
/// 「不足表示なのに始まり、全問 2 択」が実際に起きる (`canStart` は `isEstimating || (...)` で
/// 推計中の開始を許すため到達経路もある)。原本に揃えるより見積りと一致させる方を採る
/// — このモジュールが掲げる「母集団の条件は 1 か所だけが持つ」の原則が優先。
pub fn song_singer_quiz_session(
    rows: &[SongQuizOriginalArtistRow],
    singers: &[SongQuizSingerRef],
    selected_brand_ids: &[String],
    session_length: u32,
    rng: &mut SplitMix64,
) -> Vec<SongSingerQuizQuestion> {
    let pool = song_singer_quiz_pool(rows, singers, selected_brand_ids);
    if !pool.is_sufficient() {
        return Vec::new();
    }
    let choice_pool: Vec<ChoiceRef> = pool
        .singer_pool
        .iter()
        .map(|&i| ChoiceRef::from_singer(&singers[i as usize]))
        .collect();
    let position_in_pool: HashMap<u32, usize> =
        pool.singer_pool.iter().enumerate().map(|(pos, &i)| (i, pos)).collect();
    let mut draw = SequentialDraw::new(pool.pairs.len());
    (0..session_length)
        .filter_map(|_| {
            let pair = &pool.pairs[draw.next(rng)?];
            let answer_position = position_in_pool[&pair.singer];
            Some(SongSingerQuizQuestion {
                song_id: pair.song_id.clone(),
                answer: pair.singer,
                choices: choice_positions(&choice_pool, answer_position, rng)
                    .into_iter()
                    .map(|p| pool.singer_pool[p])
                    .collect(),
            })
        })
        .collect()
}

// ---------------------------------------------------------------------------
// 採点 (ヒントを開くほど獲得点が下がる)
// ---------------------------------------------------------------------------

/// 開封済みヒントの合計コスト。範囲外 index は 0 点扱い、重複は 1 回だけ数える
/// (原本の `opened` は Set なので、Vec で受けても同じ意味になるように畳む)。
fn opened_cost(facts: &[IdolQuizFact], opened_fact_indices: &[u32]) -> u32 {
    opened_fact_indices
        .iter()
        .copied()
        .collect::<HashSet<u32>>()
        .into_iter()
        .filter_map(|i| facts.get(i as usize))
        .map(|f| f.cost)
        .sum()
}

/// いま正解した場合の獲得点 (素点 − 開封コスト、最低 1pt)。
pub fn idol_quiz_current_value(
    facts: &[IdolQuizFact],
    opened_fact_indices: &[u32],
    base_points: u32,
) -> u32 {
    base_points.saturating_sub(opened_cost(facts, opened_fact_indices)).max(1)
}

/// ソロ曲クイズの獲得点 (iOS `QuizScoring.points(revealed:)`)。
pub fn song_quiz_points(revealed: u32) -> u32 {
    SONG_QUIZ_MAX_POINTS.saturating_sub(revealed).max(1)
}

/// 1 セッションの満点 (iOS `QuizScoring.sessionMax(questions:)`)。
pub fn quiz_session_max(questions: u32, per_question_max: u32) -> u32 {
    questions * per_question_max
}

/// まだ開けるヒント 1 件。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct IdolQuizHintOption {
    /// `facts` 内の位置 (開封時にそのまま `opened` へ入れる)。
    pub fact_index: u32,
    pub kind: IdolQuizFactKind,
    pub label: String,
    /// このヒントを開いた後に正解した場合の獲得点。
    pub next_value: u32,
}

/// 出題カードの開示状態。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct IdolQuizHintState {
    /// いま正解した場合の獲得点。
    pub current_value: u32,
    /// 公開済み事実の index (無料の `facts[0]` + 開封済み。解答後は全件)。
    pub shown_fact_indices: Vec<u32>,
    /// 未開封ヒント (解答後は空)。
    pub hints: Vec<IdolQuizHintOption>,
}

/// ヒント一覧と開示範囲。`facts[0]` は無料公開なのでヒントには出さない。
pub fn idol_quiz_hint_state(
    facts: &[IdolQuizFact],
    opened_fact_indices: &[u32],
    answered: bool,
    base_points: u32,
) -> IdolQuizHintState {
    let current_value = idol_quiz_current_value(facts, opened_fact_indices, base_points);
    let opened: HashSet<u32> = opened_fact_indices.iter().copied().collect();
    let shown_fact_indices: Vec<u32> = if answered {
        (0..facts.len() as u32).collect()
    } else {
        let mut shown: Vec<u32> =
            opened.iter().copied().filter(|&i| i != 0 && (i as usize) < facts.len()).collect();
        shown.sort_unstable();
        // 先頭の無料公開ぶんは常に見えている。
        std::iter::once(0).filter(|_| !facts.is_empty()).chain(shown).collect()
    };
    let hints = if answered {
        Vec::new()
    } else {
        (1..facts.len() as u32)
            .filter(|i| !opened.contains(i))
            .map(|i| {
                let fact = &facts[i as usize];
                IdolQuizHintOption {
                    fact_index: i,
                    kind: fact.kind,
                    label: fact.label.clone(),
                    next_value: current_value.saturating_sub(fact.cost).max(1),
                }
            })
            .collect()
    };
    IdolQuizHintState { current_value, shown_fact_indices, hints }
}

/// ソロ曲クイズのヒント種別。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SongQuizHintKind {
    /// ジャケットを見る (初手で出すと歌手が割れるので段階開示する)。
    Artwork,
    /// プレビューを再生する。
    Preview,
}

/// 次に開けるヒント。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongQuizHintOption {
    pub kind: SongQuizHintKind,
    pub next_value: u32,
}

/// 出題カードの開示状態。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongSingerQuizHintState {
    pub current_value: u32,
    pub show_artwork: bool,
    pub can_preview: bool,
    /// まだ開けるヒント (無ければ `None`)。
    pub next_hint: Option<SongQuizHintOption>,
}

/// `revealed` は 0=曲名のみ / 1=ジャケット / 2=プレビュー。
/// プレビュー URL が無い曲では 2 段目のヒントを出さない (開いても何も起きないため)。
pub fn song_singer_quiz_hint_state(
    revealed: u32,
    has_preview: bool,
    answered: bool,
) -> SongSingerQuizHintState {
    SongSingerQuizHintState {
        current_value: song_quiz_points(revealed),
        show_artwork: answered || revealed >= 1,
        can_preview: answered || revealed >= 2,
        next_hint: if answered {
            None
        } else if revealed == 0 {
            Some(SongQuizHintOption {
                kind: SongQuizHintKind::Artwork,
                next_value: song_quiz_points(1),
            })
        } else if revealed == 1 && has_preview {
            Some(SongQuizHintOption {
                kind: SongQuizHintKind::Preview,
                next_value: song_quiz_points(2),
            })
        } else {
            None
        },
    }
}

// ---------------------------------------------------------------------------
// 正誤判定とセッション集計
// ---------------------------------------------------------------------------

/// セッションの積み上げ (解答済み問題数 / 正解数 / 累計ポイント)。
#[derive(uniffi::Record, Clone, Debug, Default, PartialEq, Eq)]
pub struct QuizTally {
    pub asked: u32,
    pub correct: u32,
    pub points: u32,
}

/// 1 問解答した結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct QuizAnswerOutcome {
    pub is_correct: bool,
    /// この問題で獲得した点 (不正解は 0)。
    pub earned_points: u32,
    /// 開封したヒント数 (振り返り表示用)。
    pub revealed_hints: u32,
    /// 解答後の積み上げ。
    pub tally: QuizTally,
    /// これが最終問か (真なら「結果を見る」、偽なら「次の問題」)。
    pub is_last_question: bool,
}

/// 正誤判定 + 加点 + 集計。加点式なので不正解でも減点しない。
fn quiz_answer(
    value_if_correct: u32,
    revealed_hints: u32,
    picked_idol_id: &str,
    answer_idol_id: &str,
    before: &QuizTally,
    session_length: u32,
) -> QuizAnswerOutcome {
    let is_correct = canonical(picked_idol_id) == canonical(answer_idol_id);
    let earned_points = if is_correct { value_if_correct } else { 0 };
    let tally = QuizTally {
        asked: before.asked + 1,
        correct: before.correct + u32::from(is_correct),
        points: before.points + earned_points,
    };
    let is_last_question = tally.asked >= session_length;
    QuizAnswerOutcome { is_correct, earned_points, revealed_hints, tally, is_last_question }
}

/// アイドル当てクイズの解答。獲得点は開封済みヒントのコストを引いた値。
pub fn idol_quiz_answer(
    facts: &[IdolQuizFact],
    opened_fact_indices: &[u32],
    picked_idol_id: &str,
    answer_idol_id: &str,
    before: &QuizTally,
    session_length: u32,
    base_points: u32,
) -> QuizAnswerOutcome {
    let revealed_hints =
        opened_fact_indices.iter().copied().collect::<HashSet<u32>>().len() as u32;
    quiz_answer(
        idol_quiz_current_value(facts, opened_fact_indices, base_points),
        revealed_hints,
        picked_idol_id,
        answer_idol_id,
        before,
        session_length,
    )
}

/// ソロ曲クイズの解答。獲得点は開示段階で決まる。
pub fn song_singer_quiz_answer(
    revealed: u32,
    picked_idol_id: &str,
    answer_idol_id: &str,
    before: &QuizTally,
    session_length: u32,
) -> QuizAnswerOutcome {
    quiz_answer(
        song_quiz_points(revealed),
        revealed,
        picked_idol_id,
        answer_idol_id,
        before,
        session_length,
    )
}

// ---------------------------------------------------------------------------
// リザルト (グレード・自己ベスト判定)
// ---------------------------------------------------------------------------

/// 正答率から決まるグレード。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum QuizGrade {
    S,
    A,
    B,
    C,
    D,
}

impl QuizGrade {
    pub fn from_rate(rate_percent: u32) -> Self {
        match rate_percent {
            95.. => Self::S,
            80..=94 => Self::A,
            60..=79 => Self::B,
            40..=59 => Self::C,
            _ => Self::D,
        }
    }
}

/// セッション終了時の結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct QuizSessionResult {
    pub points: u32,
    /// リザルト表示の分母。**出題数ではなくセッション長**で決まる (原本 iOS の指定)。
    pub max_points: u32,
    /// 進捗ストアに渡す分母 (`asked` × 1 問満点)。最後まで遊べば `max_points` と一致する。
    /// `points` と組で `game_progress::apply_result` に渡す (モジュールコメントの手順 2)。
    pub out_of: u32,
    pub correct: u32,
    pub questions: u32,
    pub rate_percent: u32,
    pub grade: QuizGrade,
}

/// 百分率 (四捨五入)。Swift `Double.rounded()` と同じ「0 から遠い側へ丸める」。
fn rate_percent(score: u32, out_of: u32) -> u32 {
    if out_of == 0 {
        return 0;
    }
    (score as f64 / out_of as f64 * 100.0).round() as u32
}

/// リザルトに出す値をまとめて出す。**自己ベストには一切触らない**。
///
/// 「自己ベストを更新したか」「更新後の自己ベスト率」は `domain::game_progress` だけが持つ
/// 規則なので、ここに写すと同じ規則の 2 実装になる (モジュールコメント「ここに置かないもの」)。
///
/// 以前はこの関数が `best` を受けて両方を導いていたが、「**記録前**の自己ベストを渡すこと」
/// というコメントだけの契約に依存していた。ラッパが自然に書く「保存 → 保存後の値でリザルトを
/// 組む」順で呼ぶと記録後の値が渡り、更新バッジが恒久的に出なくなる。引数から外して
/// 踏みようをなくす。
pub fn quiz_session_result(
    tally: &QuizTally,
    per_question_max: u32,
    session_length: u32,
) -> QuizSessionResult {
    let max_points = quiz_session_max(session_length, per_question_max);
    let rate = rate_percent(tally.points, max_points);
    QuizSessionResult {
        points: tally.points,
        max_points,
        out_of: quiz_session_max(tally.asked, per_question_max),
        correct: tally.correct,
        questions: tally.asked,
        rate_percent: rate,
        grade: QuizGrade::from_rate(rate),
    }
}

// ---------------------------------------------------------------------------
// 出題ブランド設定の保存形式 (値は各 OS のストアに置く。エンコード規則だけ共有)
// ---------------------------------------------------------------------------

/// 保存文字列 (カンマ区切り) → ブランド id 列。空要素は捨て、重複は初出のみ残す
/// (呼び出し側は集合として扱う)。空文字列 = 全ブランド対象。
pub fn quiz_brand_ids_decode(raw: &str) -> Vec<String> {
    let mut seen: HashSet<&str> = HashSet::new();
    raw.split(',')
        .filter(|s| !s.is_empty())
        .filter(|s| seen.insert(s))
        .map(str::to_string)
        .collect()
}

/// ブランド id 列 → 保存文字列。並びで差分が出ないよう昇順に揃える。
pub fn quiz_brand_ids_encode(brand_ids: &[String]) -> String {
    let mut sorted: Vec<&str> = brand_ids.iter().map(String::as_str).collect();
    sorted.sort_unstable();
    sorted.dedup();
    sorted.join(",")
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::domain::game_progress::{self, GameProgressUpdate, GameRecord, GameStreakState};

    /// 端末ローカル日 (連続達成の単位)。本モジュールは日付を扱わないので、
    /// 合成テストで `apply_result` に渡すためだけの固定値。
    const TODAY: &str = "2026-08-25";
    const YESTERDAY: &str = "2026-08-24";

    // ---- テスト用ビルダ ----

    fn idol(id: &str, brand: &str) -> IdolQuizIdolRef {
        IdolQuizIdolRef {
            id: id.into(),
            brand_id: brand.into(),
            is_external: false,
            color: Some("#FF0000".into()),
            blood_type: Some("A型".into()),
            constellation: Some("牡羊座".into()),
            birth_place: None,
            height: None,
            age: None,
            hobbies: None,
            talents: None,
            birthday: None,
            voice_actor: None,
        }
    }

    /// 事実 3 件 (血液型 + 星座 + CV) を満たす最小の出題可能アイドル。
    fn eligible(id: &str, brand: &str) -> IdolQuizIdolRef {
        idol(id, brand)
    }

    fn pool_of(count: usize, brand: &str) -> Vec<IdolQuizIdolRef> {
        (0..count).map(|i| eligible(&format!("i{i}"), brand)).collect()
    }

    fn singer(id: &str, brand: &str) -> SongQuizSingerRef {
        SongQuizSingerRef { id: id.into(), brand_id: brand.into(), is_external: false }
    }

    fn row(song: &str, idol: &str) -> SongQuizOriginalArtistRow {
        SongQuizOriginalArtistRow { song_id: song.into(), idol_id: idol.into() }
    }

    fn labels(facts: &[IdolQuizFact]) -> Vec<&str> {
        facts.iter().map(|f| f.label.as_str()).collect()
    }

    fn value_of(facts: &[IdolQuizFact], kind: IdolQuizFactKind) -> Option<String> {
        facts.iter().find(|f| f.kind == kind).map(|f| f.value.clone())
    }

    // =======================================================================
    // プロフィール事実
    // =======================================================================

    /// 曖昧 → 特定の順に並び、メンバーカラーと CV だけコストが重い。
    #[test]
    fn facts_are_ordered_from_vague_to_specific() {
        let mut i = idol("i1", "cg");
        i.birth_place = Some("東京".into());
        i.height = Some(160.0);
        i.age = Some(17);
        i.hobbies = Some("料理".into());
        i.talents = Some("暗算".into());
        i.birthday = Some("--04-03".into());
        i.voice_actor = Some("声優A".into());
        let facts = idol_quiz_facts(&i);
        assert_eq!(
            labels(&facts),
            vec![
                "血液型",
                "星座",
                "出身",
                "身長",
                "年齢",
                "趣味",
                "特技",
                "誕生日",
                "メンバーカラー",
                "CV"
            ]
        );
        let costs: Vec<u32> = facts.iter().map(|f| f.cost).collect();
        assert_eq!(costs, vec![1, 1, 1, 1, 1, 1, 1, 1, 2, 2]);
    }

    /// 空文字は「値なし」と同じ (原本の `!isEmpty` ガード)。
    #[test]
    fn facts_skip_empty_strings() {
        let mut i = idol("i1", "cg");
        i.blood_type = Some(String::new());
        i.constellation = Some(String::new());
        i.birth_place = Some(String::new());
        // 空文字の 3 つは消え、値のあるメンバーカラーと常設の CV だけが残る。
        assert_eq!(labels(&idol_quiz_facts(&i)), vec!["メンバーカラー", "CV"]);
    }

    #[test]
    fn height_is_displayed_without_trailing_zero() {
        let mut i = idol("i1", "cg");
        i.height = Some(160.0);
        assert_eq!(value_of(&idol_quiz_facts(&i), IdolQuizFactKind::Height).unwrap(), "160cm");
        i.height = Some(160.5);
        assert_eq!(value_of(&idol_quiz_facts(&i), IdolQuizFactKind::Height).unwrap(), "160.5cm");
    }

    /// `--MM-DD` は 0 埋めを落として和文にする。それ以外は原文のまま。
    #[test]
    fn birthday_is_formatted_or_passed_through() {
        let mut i = idol("i1", "cg");
        i.birthday = Some("--04-03".into());
        assert_eq!(value_of(&idol_quiz_facts(&i), IdolQuizFactKind::Birthday).unwrap(), "4月3日");
        i.birthday = Some("--11-11".into());
        assert_eq!(value_of(&idol_quiz_facts(&i), IdolQuizFactKind::Birthday).unwrap(), "11月11日");
        i.birthday = Some("2000-04-03".into());
        assert_eq!(
            value_of(&idol_quiz_facts(&i), IdolQuizFactKind::Birthday).unwrap(),
            "2000-04-03"
        );
        i.birthday = Some("--あ-3".into());
        assert_eq!(value_of(&idol_quiz_facts(&i), IdolQuizFactKind::Birthday).unwrap(), "--あ-3");
    }

    /// 空の誕生日は事実にしない (原本の `!b.isEmpty`)。
    #[test]
    fn empty_birthday_is_not_a_fact() {
        let mut i = idol("i1", "cg");
        i.birthday = Some(String::new());
        assert!(value_of(&idol_quiz_facts(&i), IdolQuizFactKind::Birthday).is_none());
    }

    #[test]
    fn age_has_japanese_suffix() {
        let mut i = idol("i1", "cg");
        i.age = Some(15);
        assert_eq!(value_of(&idol_quiz_facts(&i), IdolQuizFactKind::Age).unwrap(), "15歳");
    }

    /// CV 枠は常設。無い場合だけ「声優未発表」と分かる (枠の有無で無料でバレない)。
    #[test]
    fn voice_actor_slot_is_always_present() {
        let mut i = idol("i1", "cg");
        assert_eq!(
            value_of(&idol_quiz_facts(&i), IdolQuizFactKind::VoiceActor).unwrap(),
            "声優未発表"
        );
        i.voice_actor = Some(String::new());
        assert_eq!(
            value_of(&idol_quiz_facts(&i), IdolQuizFactKind::VoiceActor).unwrap(),
            "声優未発表"
        );
        i.voice_actor = Some("中村繪里子".into());
        assert_eq!(
            value_of(&idol_quiz_facts(&i), IdolQuizFactKind::VoiceActor).unwrap(),
            "中村繪里子"
        );
    }

    // =======================================================================
    // 母集団
    // =======================================================================

    /// 事実が 3 件に満たないと出題できない (ヒントが成立しない)。
    #[test]
    fn pool_requires_three_facts() {
        let mut thin = idol("thin", "cg");
        thin.blood_type = None;
        thin.constellation = None; // 残るのはメンバーカラーと CV の 2 件 = ヒントが足りない
        assert_eq!(idol_quiz_facts(&thin).len(), 2);
        let idols = vec![thin, eligible("a", "cg")];
        assert_eq!(idol_quiz_pool_indices(&idols, &[]), vec![1]);
    }

    #[test]
    fn pool_excludes_external_and_colorless() {
        let mut ext = eligible("ext", "cg");
        ext.is_external = true;
        let mut nocolor = eligible("nocolor", "cg");
        nocolor.color = None;
        let mut blank = eligible("blank", "cg");
        blank.color = Some(String::new());
        let idols = vec![ext, nocolor, blank, eligible("ok", "cg")];
        assert_eq!(idol_quiz_pool_indices(&idols, &[]), vec![3]);
    }

    /// 空の選択 = 全ブランド。選ぶとそのブランドだけ。
    #[test]
    fn pool_applies_brand_filter() {
        let idols = vec![eligible("a", "cg"), eligible("b", "ml"), eligible("c", "765as")];
        assert_eq!(idol_quiz_pool_indices(&idols, &[]), vec![0, 1, 2]);
        assert_eq!(idol_quiz_pool_indices(&idols, &["ml".into()]), vec![1]);
        assert_eq!(
            idol_quiz_pool_indices(&idols, &["ml".into(), "765as".into()]),
            vec![1, 2]
        );
    }

    #[test]
    fn pool_indices_keep_input_order() {
        let idols = pool_of(5, "cg");
        assert_eq!(idol_quiz_pool_indices(&idols, &[]), vec![0, 1, 2, 3, 4]);
    }

    /// 4 人ちょうどで開始可能、3 人では不可 (4 択の成立条件)。
    #[test]
    fn pool_estimate_needs_four_candidates() {
        let three = pool_of(3, "cg");
        assert_eq!(
            idol_quiz_pool_estimate(&three, &[]),
            IdolQuizPoolEstimate { count: 3, is_sufficient: false }
        );
        let four = pool_of(4, "cg");
        assert_eq!(
            idol_quiz_pool_estimate(&four, &[]),
            IdolQuizPoolEstimate { count: 4, is_sufficient: true }
        );
    }

    /// 見積りとゲーム本体が同じ条件を使う (ここがずれると「開始できるのに候補不足」)。
    #[test]
    fn estimate_matches_playable_pool() {
        let mut thin = idol("thin", "cg");
        thin.constellation = None;
        thin.blood_type = None;
        let mut idols = pool_of(4, "cg");
        idols.push(thin);
        assert_eq!(idol_quiz_pool_estimate(&idols, &[]).count, 4);
        assert_eq!(idol_quiz_session(&idols, &[], 3, &mut SplitMix64(1)).len(), 3);
    }

    // =======================================================================
    // アイドル当てクイズのセッション
    // =======================================================================

    #[test]
    fn session_generates_requested_number_of_questions() {
        let idols = pool_of(20, "cg");
        assert_eq!(idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(9)).len(), 10);
    }

    /// 候補 4 人未満は出題できない (画面は空状態へ)。
    #[test]
    fn session_is_empty_when_pool_is_too_small() {
        let idols = pool_of(3, "cg");
        assert!(idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(1)).is_empty());
    }

    /// 母集団が足りている限り、同じアイドルは 1 セッション中に 2 度出ない。
    #[test]
    fn session_never_repeats_answer_while_pool_lasts() {
        let idols = pool_of(12, "cg");
        for seed in 0..30 {
            let questions = idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(seed));
            let unique: HashSet<u32> = questions.iter().map(|q| q.answer).collect();
            assert_eq!(unique.len(), questions.len(), "重複出題: seed={seed}");
        }
    }

    /// 母集団がセッションより短いときは一巡してから再出題する
    /// (4 人 → 最初の 4 問で全員が 1 回ずつ出る)。
    #[test]
    fn session_wraps_after_pool_is_exhausted() {
        let idols = pool_of(4, "cg");
        for seed in 0..20 {
            let questions = idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(seed));
            assert_eq!(questions.len(), 10);
            for block in questions.chunks(4).take(2) {
                let unique: HashSet<u32> = block.iter().map(|q| q.answer).collect();
                assert_eq!(unique.len(), block.len(), "一巡内で重複: seed={seed}");
            }
        }
    }

    /// 4 択には必ず正解が入り、同じ人物が 2 度並ばない。
    #[test]
    fn session_choices_contain_answer_without_duplicates() {
        let idols = pool_of(12, "cg");
        for seed in 0..30 {
            for q in idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(seed)) {
                assert_eq!(q.choices.len(), 4);
                assert!(q.choices.contains(&q.answer), "正解が選択肢にない");
                let unique: HashSet<&u32> = q.choices.iter().collect();
                assert_eq!(unique.len(), 4, "選択肢が重複: {:?}", q.choices);
            }
        }
    }

    #[test]
    fn session_question_carries_answer_facts() {
        let mut idols = pool_of(4, "cg");
        idols[2].voice_actor = Some("声優X".into());
        for q in idol_quiz_session(&idols, &[], 4, &mut SplitMix64(3)) {
            assert_eq!(q.facts, idol_quiz_facts(&idols[q.answer as usize]));
        }
    }

    /// 同じシードなら iOS / Android / テストで同じ出題になる。
    #[test]
    fn session_is_deterministic_for_the_same_seed() {
        let idols = pool_of(12, "cg");
        assert_eq!(
            idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(42)),
            idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(42))
        );
    }

    /// 正解の位置が固定されない (位置で当てられてしまう)。
    #[test]
    fn answer_position_varies_between_questions() {
        let idols = pool_of(12, "cg");
        let positions: HashSet<usize> = (0..30)
            .flat_map(|seed| idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(seed)))
            .map(|q| q.choices.iter().position(|c| *c == q.answer).expect("正解が無い"))
            .collect();
        assert!(positions.len() > 1, "正解の位置が固定されている: {positions:?}");
    }

    /// 誤答は同ブランドを優先する (難易度が下がりすぎないように)。
    #[test]
    fn distractors_prefer_the_same_brand() {
        let mut idols = pool_of(4, "cg");
        idols.extend((0..6).map(|i| eligible(&format!("ml{i}"), "ml")));
        for seed in 0..30 {
            for q in idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(seed)) {
                let answer_brand = idols[q.answer as usize].brand_id.clone();
                assert!(
                    q.choices.iter().all(|&c| idols[c as usize].brand_id == answer_brand),
                    "同ブランドで 4 択が組めるのに他ブランドが混ざった"
                );
            }
        }
    }

    /// 同ブランドが足りなければ他ブランドで補う (4 択を成立させる)。
    #[test]
    fn distractors_fall_back_to_other_brands() {
        let mut idols = vec![eligible("solo", "961")];
        idols.extend(pool_of(6, "cg"));
        let questions = idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(5));
        let solo_questions: Vec<_> = questions.iter().filter(|q| q.answer == 0).collect();
        assert!(!solo_questions.is_empty(), "テスト前提: 単独ブランドも出題される");
        for q in solo_questions {
            assert_eq!(q.choices.len(), 4, "他ブランドで補って 4 択にする");
        }
    }

    /// 同一人物が母集団に二重にいても、正解と同じ id は誤答に出さない。
    #[test]
    fn distractors_exclude_every_entry_with_the_answer_id() {
        let mut idols = pool_of(5, "cg");
        idols.push(idols[0].clone()); // 同 id の重複エントリ
        for seed in 0..30 {
            for q in idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(seed)) {
                let answer_id = &idols[q.answer as usize].id;
                let same_id = q.choices.iter().filter(|&&c| idols[c as usize].id == *answer_id);
                assert_eq!(same_id.count(), 1, "正解と同じ人物が 2 つ並んだ");
            }
        }
    }

    /// 母集団がちょうど 4 人なら選択肢も 4 つ (境界)。
    #[test]
    fn session_with_exactly_four_candidates_still_has_four_choices() {
        let idols = pool_of(4, "cg");
        for q in idol_quiz_session(&idols, &[], SESSION_LENGTH, &mut SplitMix64(11)) {
            assert_eq!(q.choices.len(), 4);
        }
    }

    // =======================================================================
    // ソロ曲クイズの母集団
    // =======================================================================

    /// 原唱が複数いる曲は答えが一意にならないので落とす。
    #[test]
    fn song_pool_keeps_only_single_original_artist_songs() {
        let singers = vec![singer("a", "cg"), singer("b", "cg")];
        let rows = vec![row("s1", "a"), row("s2", "a"), row("s2", "b"), row("s3", "b")];
        let pool = song_singer_quiz_pool(&rows, &singers, &[]);
        assert_eq!(
            pool.pairs,
            vec![
                SongQuizPair { song_id: "s1".into(), singer: 0 },
                SongQuizPair { song_id: "s3".into(), singer: 1 },
            ]
        );
    }

    #[test]
    fn song_pool_excludes_external_and_unknown_singers() {
        let singers = vec![singer("a", "cg"), SongQuizSingerRef {
            id: "ext".into(),
            brand_id: "cg".into(),
            is_external: true,
        }];
        let rows = vec![row("s1", "a"), row("s2", "ext"), row("s3", "missing")];
        let pool = song_singer_quiz_pool(&rows, &singers, &[]);
        assert_eq!(pool.pairs, vec![SongQuizPair { song_id: "s1".into(), singer: 0 }]);
    }

    #[test]
    fn song_pool_applies_brand_filter() {
        let singers = vec![singer("a", "cg"), singer("b", "ml")];
        let rows = vec![row("s1", "a"), row("s2", "b")];
        assert_eq!(song_singer_quiz_pool(&rows, &singers, &[]).pairs.len(), 2);
        let filtered = song_singer_quiz_pool(&rows, &singers, &["ml".into()]);
        assert_eq!(filtered.pairs, vec![SongQuizPair { song_id: "s2".into(), singer: 1 }]);
        assert_eq!(filtered.singer_pool, vec![1]);
    }

    /// 歌手プールは初出順・重複なし (曲数と歌手数は別物)。
    #[test]
    fn song_pool_singers_are_unique_in_first_seen_order() {
        let singers = vec![singer("a", "cg"), singer("b", "cg"), singer("c", "cg")];
        let rows = vec![row("s1", "c"), row("s2", "a"), row("s3", "c"), row("s4", "b")];
        let pool = song_singer_quiz_pool(&rows, &singers, &[]);
        assert_eq!(pool.pairs.len(), 4);
        assert_eq!(pool.singer_pool, vec![2, 0, 1]);
    }

    /// 曲順は入力行の順を保つ (呼び出し側が並べた順がそのまま母集団の順)。
    #[test]
    fn song_pool_keeps_row_order() {
        let singers = vec![singer("a", "cg")];
        let rows = vec![row("s3", "a"), row("s1", "a"), row("s2", "a")];
        let ids: Vec<String> =
            song_singer_quiz_pool(&rows, &singers, &[]).pairs.into_iter().map(|p| p.song_id).collect();
        assert_eq!(ids, vec!["s3", "s1", "s2"]);
    }

    /// 開始可否は曲数と歌手数の両方が 4 以上のときだけ。
    #[test]
    fn song_pool_estimate_needs_four_songs_and_four_singers() {
        let singers: Vec<_> = (0..4).map(|i| singer(&format!("a{i}"), "cg")).collect();
        let rows: Vec<_> = (0..4).map(|i| row(&format!("s{i}"), &format!("a{i}"))).collect();
        assert_eq!(
            song_singer_quiz_pool_estimate(&rows, &singers, &[]),
            SongSingerQuizPoolEstimate { song_count: 4, singer_count: 4, is_sufficient: true }
        );

        // 4 曲あっても歌手が 3 人なら 4 択が組めない。
        let few_singers: Vec<_> = (0..3).map(|i| singer(&format!("a{i}"), "cg")).collect();
        let rows_same_singer: Vec<_> =
            (0..4).map(|i| row(&format!("s{i}"), &format!("a{}", i % 3))).collect();
        assert_eq!(
            song_singer_quiz_pool_estimate(&rows_same_singer, &few_singers, &[]),
            SongSingerQuizPoolEstimate { song_count: 4, singer_count: 3, is_sufficient: false }
        );
    }

    // =======================================================================
    // ソロ曲クイズのセッション
    // =======================================================================

    fn song_fixture(songs: usize, singers: usize) -> (Vec<SongQuizOriginalArtistRow>, Vec<SongQuizSingerRef>) {
        let singer_refs: Vec<_> = (0..singers).map(|i| singer(&format!("a{i}"), "cg")).collect();
        let rows: Vec<_> = (0..songs)
            .map(|i| row(&format!("s{i}"), &format!("a{}", i % singers)))
            .collect();
        (rows, singer_refs)
    }

    #[test]
    fn song_session_is_empty_when_too_few_songs() {
        let (rows, singers) = song_fixture(3, 3);
        assert!(song_singer_quiz_session(&rows, &singers, &[], SESSION_LENGTH, &mut SplitMix64(1))
            .is_empty());
    }

    #[test]
    fn song_session_never_repeats_a_song_while_pool_lasts() {
        let (rows, singers) = song_fixture(12, 12);
        for seed in 0..30 {
            let questions =
                song_singer_quiz_session(&rows, &singers, &[], SESSION_LENGTH, &mut SplitMix64(seed));
            assert_eq!(questions.len(), 10);
            let unique: HashSet<&String> = questions.iter().map(|q| &q.song_id).collect();
            assert_eq!(unique.len(), questions.len(), "同じ曲が 2 度出た: seed={seed}");
        }
    }

    #[test]
    fn song_session_choices_contain_the_singer() {
        let (rows, singers) = song_fixture(12, 8);
        for seed in 0..20 {
            for q in
                song_singer_quiz_session(&rows, &singers, &[], SESSION_LENGTH, &mut SplitMix64(seed))
            {
                assert_eq!(q.choices.len(), 4);
                assert!(q.choices.contains(&q.answer));
                let unique: HashSet<&u32> = q.choices.iter().collect();
                assert_eq!(unique.len(), 4);
            }
        }
    }

    /// 実データの再現 (`master.sqlite` のブランド 961: ソロ曲 4 曲 / 原唱歌手 2 名)。
    /// 設定画面が「不足」を出す母集団でゲーム本体だけが 10 問返し、全問 2 択になっていた。
    #[test]
    fn song_session_is_empty_when_singers_cannot_fill_four_choices() {
        let (rows, singers) = song_fixture(4, 2);
        assert_eq!(
            song_singer_quiz_pool_estimate(&rows, &singers, &[]),
            SongSingerQuizPoolEstimate { song_count: 4, singer_count: 2, is_sufficient: false }
        );
        assert!(
            song_singer_quiz_session(&rows, &singers, &[], SESSION_LENGTH, &mut SplitMix64(4))
                .is_empty(),
            "設定画面が不足と言う母集団でゲームだけが始まった"
        );
    }

    /// 見積りとゲーム本体が同じ条件を使う (アイドル当てクイズの
    /// `estimate_matches_playable_pool` と対になる不変条件)。曲数と歌手数を総当たりし、
    /// 「開始できるのに候補不足」も「不足表示なのに始まる」も出ないことを見る。
    #[test]
    fn song_estimate_matches_playable_pool() {
        for songs in 0..=6 {
            for singers in 1..=6 {
                let (rows, singer_refs) = song_fixture(songs, singers);
                let estimate = song_singer_quiz_pool_estimate(&rows, &singer_refs, &[]);
                let questions = song_singer_quiz_session(
                    &rows,
                    &singer_refs,
                    &[],
                    SESSION_LENGTH,
                    &mut SplitMix64(1),
                );
                assert_eq!(
                    estimate.is_sufficient,
                    !questions.is_empty(),
                    "曲 {songs} / 歌手 {singers} で見積りとゲーム本体がずれた"
                );
                // 始まった以上は必ず 4 択 (2 択のまま出題される事故を落とす)。
                for q in &questions {
                    assert_eq!(q.choices.len(), MINIMUM_POOL as usize);
                }
            }
        }
    }

    #[test]
    fn song_session_is_deterministic_for_the_same_seed() {
        let (rows, singers) = song_fixture(12, 9);
        assert_eq!(
            song_singer_quiz_session(&rows, &singers, &[], SESSION_LENGTH, &mut SplitMix64(7)),
            song_singer_quiz_session(&rows, &singers, &[], SESSION_LENGTH, &mut SplitMix64(7))
        );
    }

    /// 正解の歌手は必ずその曲の原唱 (曲と答えの対応がずれない)。
    #[test]
    fn song_session_answer_matches_the_song_original_singer() {
        let (rows, singers) = song_fixture(12, 6);
        let expected: HashMap<&str, u32> = rows
            .iter()
            .map(|r| {
                let idx = singers.iter().position(|s| s.id == r.idol_id).unwrap() as u32;
                (r.song_id.as_str(), idx)
            })
            .collect();
        for q in song_singer_quiz_session(&rows, &singers, &[], SESSION_LENGTH, &mut SplitMix64(2)) {
            assert_eq!(expected[q.song_id.as_str()], q.answer);
        }
    }

    // =======================================================================
    // 採点
    // =======================================================================

    fn facts_fixture() -> Vec<IdolQuizFact> {
        vec![
            IdolQuizFact::new(IdolQuizFactKind::BloodType, "A型"),
            IdolQuizFact::new(IdolQuizFactKind::Constellation, "牡羊座"),
            IdolQuizFact::new(IdolQuizFactKind::MemberColor, "#FF0000"),
            IdolQuizFact::new(IdolQuizFactKind::VoiceActor, "声優A"),
        ]
    }

    #[test]
    fn no_hint_means_full_points() {
        assert_eq!(
            idol_quiz_current_value(&facts_fixture(), &[], IDOL_QUIZ_BASE_POINTS),
            10
        );
    }

    #[test]
    fn each_opened_hint_subtracts_its_cost() {
        let facts = facts_fixture();
        assert_eq!(idol_quiz_current_value(&facts, &[1], IDOL_QUIZ_BASE_POINTS), 9);
        assert_eq!(idol_quiz_current_value(&facts, &[2], IDOL_QUIZ_BASE_POINTS), 8);
        assert_eq!(idol_quiz_current_value(&facts, &[1, 2, 3], IDOL_QUIZ_BASE_POINTS), 5);
    }

    /// 開けすぎても 0pt にはしない (加点式なので最低 1pt)。
    #[test]
    fn value_never_drops_below_one() {
        let facts: Vec<IdolQuizFact> = (0..8)
            .map(|_| IdolQuizFact::new(IdolQuizFactKind::MemberColor, "#000"))
            .collect();
        let opened: Vec<u32> = (0..8).collect();
        assert_eq!(idol_quiz_current_value(&facts, &opened, IDOL_QUIZ_BASE_POINTS), 1);
    }

    /// 範囲外 index は 0 点扱い、重複指定は 1 回だけ数える (原本の Set 相当)。
    #[test]
    fn value_ignores_out_of_range_and_duplicate_indices() {
        let facts = facts_fixture();
        assert_eq!(idol_quiz_current_value(&facts, &[99], IDOL_QUIZ_BASE_POINTS), 10);
        assert_eq!(idol_quiz_current_value(&facts, &[2, 2, 2], IDOL_QUIZ_BASE_POINTS), 8);
    }

    /// 未開封ヒントだけを並べ、開いた後の点も添える。無料の facts[0] は出さない。
    #[test]
    fn hint_state_lists_unopened_hints() {
        let state = idol_quiz_hint_state(&facts_fixture(), &[1], false, IDOL_QUIZ_BASE_POINTS);
        assert_eq!(state.current_value, 9);
        assert_eq!(state.shown_fact_indices, vec![0, 1]);
        assert_eq!(
            state.hints,
            vec![
                IdolQuizHintOption {
                    fact_index: 2,
                    kind: IdolQuizFactKind::MemberColor,
                    label: "メンバーカラー".into(),
                    next_value: 7,
                },
                IdolQuizHintOption {
                    fact_index: 3,
                    kind: IdolQuizFactKind::VoiceActor,
                    label: "CV".into(),
                    next_value: 7,
                },
            ]
        );
    }

    /// 解答後は全部見せ、ヒントは出さない。
    #[test]
    fn hint_state_reveals_everything_after_answering() {
        let state = idol_quiz_hint_state(&facts_fixture(), &[2], true, IDOL_QUIZ_BASE_POINTS);
        assert_eq!(state.shown_fact_indices, vec![0, 1, 2, 3]);
        assert!(state.hints.is_empty());
    }

    /// 事実が無いときも落ちない (空プール境界)。
    #[test]
    fn hint_state_handles_empty_facts() {
        let state = idol_quiz_hint_state(&[], &[], false, IDOL_QUIZ_BASE_POINTS);
        assert_eq!(state.current_value, 10);
        assert!(state.shown_fact_indices.is_empty());
        assert!(state.hints.is_empty());
    }

    #[test]
    fn song_points_decrease_with_each_reveal() {
        assert_eq!(song_quiz_points(0), 3);
        assert_eq!(song_quiz_points(1), 2);
        assert_eq!(song_quiz_points(2), 1);
        assert_eq!(song_quiz_points(3), 1, "下限は 1pt");
    }

    #[test]
    fn song_session_max_is_three_points_per_question() {
        assert_eq!(quiz_session_max(10, SONG_QUIZ_MAX_POINTS), 30);
        assert_eq!(quiz_session_max(0, SONG_QUIZ_MAX_POINTS), 0);
    }

    /// ジャケット → プレビューの順に開き、プレビューが無い曲は 2 段目を出さない。
    #[test]
    fn song_hints_are_revealed_in_stages() {
        let first = song_singer_quiz_hint_state(0, true, false);
        assert_eq!(first.current_value, 3);
        assert!(!first.show_artwork && !first.can_preview);
        assert_eq!(
            first.next_hint,
            Some(SongQuizHintOption { kind: SongQuizHintKind::Artwork, next_value: 2 })
        );

        let second = song_singer_quiz_hint_state(1, true, false);
        assert!(second.show_artwork && !second.can_preview);
        assert_eq!(
            second.next_hint,
            Some(SongQuizHintOption { kind: SongQuizHintKind::Preview, next_value: 1 })
        );

        assert_eq!(song_singer_quiz_hint_state(1, false, false).next_hint, None);
        assert_eq!(song_singer_quiz_hint_state(2, true, false).next_hint, None);

        let answered = song_singer_quiz_hint_state(0, true, true);
        assert!(answered.show_artwork && answered.can_preview, "解答後は全部見せる");
        assert_eq!(answered.next_hint, None);
    }

    // =======================================================================
    // 正誤判定と集計
    // =======================================================================

    #[test]
    fn correct_answer_adds_the_current_value() {
        let outcome = idol_quiz_answer(
            &facts_fixture(),
            &[2],
            "i1",
            "i1",
            &QuizTally { asked: 3, correct: 2, points: 20 },
            SESSION_LENGTH,
            IDOL_QUIZ_BASE_POINTS,
        );
        assert!(outcome.is_correct);
        assert_eq!(outcome.earned_points, 8);
        assert_eq!(outcome.revealed_hints, 1);
        assert_eq!(outcome.tally, QuizTally { asked: 4, correct: 3, points: 28 });
        assert!(!outcome.is_last_question);
    }

    /// 不正解でも減点しない (加点式)。解答数だけ進む。
    #[test]
    fn wrong_answer_earns_nothing_but_counts_as_asked() {
        let outcome = idol_quiz_answer(
            &facts_fixture(),
            &[],
            "other",
            "i1",
            &QuizTally { asked: 3, correct: 2, points: 20 },
            SESSION_LENGTH,
            IDOL_QUIZ_BASE_POINTS,
        );
        assert!(!outcome.is_correct);
        assert_eq!(outcome.earned_points, 0);
        assert_eq!(outcome.tally, QuizTally { asked: 4, correct: 2, points: 20 });
    }

    #[test]
    fn last_question_is_detected_by_session_length() {
        let before = QuizTally { asked: 9, correct: 9, points: 27 };
        let outcome = song_singer_quiz_answer(0, "a", "a", &before, SESSION_LENGTH);
        assert_eq!(outcome.tally.asked, 10);
        assert!(outcome.is_last_question);
    }

    #[test]
    fn song_answer_uses_reveal_stage_for_points() {
        let outcome =
            song_singer_quiz_answer(2, "a", "a", &QuizTally::default(), SESSION_LENGTH);
        assert_eq!(outcome.earned_points, 1);
        assert_eq!(outcome.revealed_hints, 2);
    }

    /// id の比較は Swift の `==` と同じ正準等価。表現違いで誤判定しない。
    #[test]
    fn answer_comparison_is_canonically_equivalent() {
        let outcome = song_singer_quiz_answer(
            0,
            "cg_ウ\u{3099}ェネツィア", // NFD
            "cg_ヴェネツィア",         // NFC
            &QuizTally::default(),
            SESSION_LENGTH,
        );
        assert!(outcome.is_correct, "同じアイドルを別人と判定した");
    }

    /// 全問正解 / 全問不正解の両端。
    #[test]
    fn tally_accumulates_over_a_full_session() {
        let mut perfect = QuizTally::default();
        let mut zero = QuizTally::default();
        for _ in 0..SESSION_LENGTH {
            perfect = song_singer_quiz_answer(0, "a", "a", &perfect, SESSION_LENGTH).tally;
            zero = song_singer_quiz_answer(0, "b", "a", &zero, SESSION_LENGTH).tally;
        }
        assert_eq!(perfect, QuizTally { asked: 10, correct: 10, points: 30 });
        assert_eq!(zero, QuizTally { asked: 10, correct: 0, points: 0 });
    }

    // =======================================================================
    // リザルト
    // =======================================================================

    fn result(points: u32, asked: u32) -> QuizSessionResult {
        quiz_session_result(
            &QuizTally { asked, correct: 0, points },
            SONG_QUIZ_MAX_POINTS,
            SESSION_LENGTH,
        )
    }

    /// 保存済みの自己ベスト (プレイ済み)。
    fn played(best_score: i32, best_out_of: i32) -> GameRecord {
        GameRecord { best_score, best_out_of, play_count: 1, ..GameRecord::default() }
    }

    /// リザルト画面が実際に踏む手順の再現。
    ///
    /// 1. [`quiz_session_result`] (呼び出し側で組む) → 2. `apply_result` で保存 →
    /// 3. 保存**後**の記録から自己ベスト率を読む。3 の順序は原本 iOS
    ///    `QuizResultView.bestRate` と同じで、記録が無ければ今回の率で代用する
    ///    (`guard rec.bestOutOf > 0 else { return rate }`)。
    ///
    /// 返り値は (保存結果, 表示する自己ベスト率)。
    fn finish_session(
        session: &QuizSessionResult,
        before: &GameRecord,
    ) -> (GameProgressUpdate, u32) {
        let update = game_progress::apply_result(
            before,
            &GameStreakState::default(),
            session.points as i32,
            session.out_of as i32,
            TODAY,
            YESTERDAY,
        );
        let best_rate =
            update.record.best_rate_percent().map_or(session.rate_percent, |p| p.max(0) as u32);
        (update, best_rate)
    }

    #[test]
    fn grade_boundaries_follow_the_rate() {
        assert_eq!(QuizGrade::from_rate(100), QuizGrade::S);
        assert_eq!(QuizGrade::from_rate(95), QuizGrade::S);
        assert_eq!(QuizGrade::from_rate(94), QuizGrade::A);
        assert_eq!(QuizGrade::from_rate(80), QuizGrade::A);
        assert_eq!(QuizGrade::from_rate(79), QuizGrade::B);
        assert_eq!(QuizGrade::from_rate(60), QuizGrade::B);
        assert_eq!(QuizGrade::from_rate(59), QuizGrade::C);
        assert_eq!(QuizGrade::from_rate(40), QuizGrade::C);
        assert_eq!(QuizGrade::from_rate(39), QuizGrade::D);
        assert_eq!(QuizGrade::from_rate(0), QuizGrade::D);
    }

    /// 正答率は四捨五入 (29/30 = 96.67% → 97%)。
    #[test]
    fn rate_is_rounded_to_the_nearest_percent() {
        let r = result(29, 10);
        assert_eq!(r.max_points, 30);
        assert_eq!(r.rate_percent, 97);
        assert_eq!(r.grade, QuizGrade::S);
    }

    /// 表示分母はセッション長基準、進捗ストア用の分母は解答数基準。
    #[test]
    fn max_points_is_session_based_and_out_of_is_asked_based() {
        let r = result(9, 5);
        assert_eq!(r.max_points, 30, "リザルト表示は 10 問ぶんの満点");
        assert_eq!(r.out_of, 15, "記録は解答した 5 問ぶん");
        assert_eq!(r.rate_percent, 30);
        assert_eq!(r.questions, 5);
    }

    /// 初プレイは「自己ベスト更新」を出さない (最初から更新演出が出ると意味が薄い)。
    #[test]
    fn first_play_is_not_a_new_best() {
        let (update, best_rate) = finish_session(&result(30, 10), &GameRecord::default());
        assert!(!update.is_new_best);
        assert_eq!(best_rate, 100, "表示は今回の記録を反映した値");
    }

    /// 同率では更新しない (真に上回ったときだけ)。
    #[test]
    fn tie_does_not_beat_the_best() {
        let (update, best_rate) = finish_session(&result(15, 10), &played(15, 30));
        assert!(!update.is_new_best);
        assert_eq!(best_rate, 50);
    }

    /// 出題数が違っても正答率で比べる (5 問満点 > 10 問半分)。
    #[test]
    fn best_is_compared_by_rate_not_raw_score() {
        // 15/15 = 100% で、旧ベスト 15/30 = 50% を上回る。
        let (update, best_rate) = finish_session(&result(15, 5), &played(15, 30));
        assert!(update.is_new_best);
        assert_eq!(best_rate, 100, "更新後の自己ベストを表示する");
    }

    #[test]
    fn lower_score_keeps_the_previous_best() {
        let (update, best_rate) = finish_session(&result(9, 10), &played(27, 30));
        assert!(!update.is_new_best);
        assert_eq!(best_rate, 90);
    }

    /// 1 問も解かずに終えた場合 (境界): 記録は動かさず、率は 0%。
    #[test]
    fn zero_questions_does_not_touch_the_record() {
        let r = result(0, 0);
        assert_eq!(r.out_of, 0);
        assert_eq!(r.rate_percent, 0);
        assert_eq!(r.grade, QuizGrade::D);
        let (update, best_rate) = finish_session(&r, &played(27, 30));
        assert!(!update.did_record, "0 問はプレイとして数えない");
        assert!(!update.is_new_best);
        assert_eq!(best_rate, 90, "自己ベストは据え置き");
    }

    /// 指摘の再現: ラッパが自然に書く「保存 → 保存後の値でリザルトを組む」順でも
    /// 自己ベスト更新バッジが消えないこと。
    ///
    /// 以前は `quiz_session_result` が「**記録前**の自己ベスト」を引数に取って更新判定まで
    /// 自前で持っていたため、保存後の記録を渡すと比較相手が今回の値そのものになり、
    /// バッジが恒久的に出なかった (旧ベスト 50/100 → 今回 90/100 でも更新扱いにならない)。
    /// 判定は `apply_result` だけが持つので、リザルトをいつ組んでも結果は変わらない。
    #[test]
    fn new_best_survives_building_the_result_after_saving() {
        let r = quiz_session_result(
            &QuizTally { asked: 10, correct: 9, points: 90 },
            IDOL_QUIZ_BASE_POINTS,
            SESSION_LENGTH,
        );
        assert_eq!(r.out_of, 100);

        let before =
            GameRecord { best_score: 50, best_out_of: 100, play_count: 3, ..GameRecord::default() };
        let (update, best_rate) = finish_session(&r, &before);
        assert!(update.is_new_best, "保存後にリザルトを組むと更新バッジが消えた");
        assert_eq!(best_rate, 90, "表示は更新後の自己ベスト率");

        // 保存後の記録で同じ点をもう一度出しても、同率なので更新にはならない。
        let (again, again_rate) = finish_session(&r, &update.record);
        assert!(!again.is_new_best);
        assert_eq!(again_rate, 90);
    }

    /// 壊れた保存値 (プレイ済みなのに分母 0) でも、リザルト表示は今回の率で代用する。
    /// `GameRecord::best_rate_percent` が `None` を返す唯一の経路。
    #[test]
    fn broken_record_falls_back_to_this_session_rate() {
        let broken = GameRecord { play_count: 2, ..GameRecord::default() };
        let session = result(0, 0);
        let (update, best_rate) = finish_session(&session, &broken);
        assert_eq!(update.record.best_rate_percent(), None, "記録は無いまま");
        assert_eq!(best_rate, session.rate_percent, "記録が無ければ今回の率で代用する");
        assert_eq!(session.rate_percent, 0);
    }

    /// アイドル当てクイズは 1 問 10pt (満点 100)。
    #[test]
    fn idol_quiz_session_max_is_ten_points_per_question() {
        let r = quiz_session_result(
            &QuizTally { asked: 10, correct: 10, points: 100 },
            IDOL_QUIZ_BASE_POINTS,
            SESSION_LENGTH,
        );
        assert_eq!(r.max_points, 100);
        assert_eq!(r.rate_percent, 100);
        assert_eq!(r.grade, QuizGrade::S);
    }

    // =======================================================================
    // ブランド設定の保存形式
    // =======================================================================

    #[test]
    fn brand_ids_round_trip_through_storage() {
        let decoded = quiz_brand_ids_decode("ml,cg");
        assert_eq!(decoded, vec!["ml", "cg"]);
        assert_eq!(quiz_brand_ids_encode(&decoded), "cg,ml", "保存は昇順に揃える");
    }

    #[test]
    fn empty_storage_means_all_brands() {
        assert!(quiz_brand_ids_decode("").is_empty());
        assert!(quiz_brand_ids_encode(&[]).is_empty());
        let all = pool_of(4, "cg");
        assert_eq!(idol_quiz_pool_indices(&all, &quiz_brand_ids_decode("")).len(), 4);
    }

    /// 壊れた保存値 (空要素・重複) でも素直に読める。
    #[test]
    fn brand_ids_decode_drops_empty_and_duplicate_entries() {
        assert_eq!(quiz_brand_ids_decode(",cg,,cg,ml,"), vec!["cg", "ml"]);
    }
}
