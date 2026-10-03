//! **画面の構成をデータで返す層**。
//!
//! 「どの行が・どの順で・どんな見た目の指定で出るか」をコアが決め、
//! iOS/Android は返ってきた並びを自分の流儀で描くだけにする。
//!
//! # なぜ必要か
//!
//! 表示の判断 (この項目は値が無いとき出さない、この行はタップできる、等) は
//! これまで両OSに二重に書かれていた。同じ条件を 2 回書けば必ずいつかズレる。
//! 実際 Phase 6/8 では「Android だけ CV ヒントが 1 枠少ない」「Android だけ
//! 外部ゲストが混ざる」といったズレが見つかっている。
//!
//! ここが返すのは**構成**であって**見た目ではない**。色・字送り・余白・
//! アニメーションは各OSのデザインシステムが持つ。移すのは
//! 「何を出すか」「どの順で出すか」「押せるか」だけ。
//!
//! # 意図的に持たないもの
//!
//! - 文字色やフォント (DS/ImasTheme の担当)
//! - 画面遷移の実行 (`action` は「押されたら何をしたいか」の**種類**だけを返し、
//!   実際の遷移は各OSが自分の navigation で行う)

use crate::domain::collection_gap::{collection_interval_label, CollectionGap};
use crate::domain::performance_gap::{OriginalSingerOrdinal, OriginalSingers, PerformanceGap};

// =============================================================================
// セトリをどれだけ詳しく出すか
// =============================================================================

/// セトリの詳しさ。**「どのモードで何を出すか」の判断はこの enum が持つ。**
///
/// # なぜコアにあるか
///
/// 以前は `setlist_simple_mode` という Bool 1 つで、判断は
/// 「シンプルなら簡易行、そうでなければ詳細行」と各 OS の View に書いてあった。
/// 3 値になると「詳細表示のときだけ披露履歴の札を出す」という条件が増え、
/// これを Swift と Kotlin の両方に書けば必ずいつか片方だけ直る
/// (`performer_label` で実際に起きた)。出すものの決定は [`setlist_history_badges`]
/// に集約し、各 OS は返った札を並べるだけにする。
///
/// 並びは「情報が少ない順」。設定の選択肢もこの順で出す。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SetlistDisplayMode {
    /// 曲名と歌唱者だけ。20 曲超のセトリを 1 枚のスクショに収めるための形。
    Simple,
    /// 既定。ジャケ・歌唱者のアバター・カバーの札・👍。
    Normal,
    /// 普通表示に**披露の履歴**(初披露 / いつぶり / 通算何回目) を足したもの。
    Detailed,
}

/// モード 1 つぶんの選択肢。切替 UI はこれを並べるだけにする。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistDisplayModeOption {
    pub mode: SetlistDisplayMode,
    /// 保存に使う文字列。**序数で保存しない** (並べ替えた瞬間に化ける)。
    pub raw: String,
    pub label: String,
}

impl SetlistDisplayMode {
    /// 保存値。iOS の UserDefaults / Android の SharedPreferences で同じ文字列を使う。
    pub fn raw(self) -> &'static str {
        match self {
            Self::Simple => "simple",
            Self::Normal => "normal",
            Self::Detailed => "detailed",
        }
    }

    /// 切替 UI に出す文言。
    pub fn label(self) -> &'static str {
        match self {
            Self::Simple => "シンプル表示",
            Self::Normal => "普通表示",
            Self::Detailed => "詳細表示",
        }
    }

    /// 既定。**これまで Bool が false だった人の見え方と同じ**。
    pub fn default_mode() -> Self {
        Self::Normal
    }

    /// 切替 UI に出す順 (情報が少ない順)。
    pub fn all() -> Vec<Self> {
        vec![Self::Simple, Self::Normal, Self::Detailed]
    }

    /// 保存値からの復元。未知の値・未設定は既定。
    pub fn from_raw(raw: Option<&str>) -> Self {
        raw.and_then(|r| Self::all().into_iter().find(|m| m.raw() == r))
            .unwrap_or_else(Self::default_mode)
    }

    /// 曲名と歌唱者だけに絞る形か (行の作りそのものが変わる)。
    ///
    /// **これは「どちらの行を描くか」で、判断ではない。** 出す/出さないの判断は
    /// [`setlist_history_badges`] が持つ。
    pub fn is_compact(self) -> bool {
        self == Self::Simple
    }

    /// 披露の履歴 (初披露 / いつぶり / 通算何回目) を出すか。
    pub fn shows_performance_history(self) -> bool {
        self == Self::Detailed
    }

    /// 行に**自分の回収**(初回収 / 回収 N 回目 / 未回収) を重ねるか。
    ///
    /// 披露の履歴と同じ詳細表示に乗せる。「世の中で 4 回目」と「自分は 2 回目」は
    /// 同じ行の同じ種類の情報で、別の設定に分けると「詳しく出しているのに
    /// 自分の回収だけ出ない」状態が作れてしまう。
    pub fn shows_collection_history(self) -> bool {
        self.shows_performance_history()
    }

    /// 公演の頭に**自分の回収の要約**(この公演で N 曲回収 / 未回収 N 曲) を出すか。
    ///
    /// 行の札と違って**シンプル表示以外なら出す**。シンプル表示はセトリを 1 枚の
    /// スクショに収めるための形なので、自分にしか意味のない行を焼き込まない。
    pub fn shows_collection_summary(self) -> bool {
        !self.is_compact()
    }
}

/// 切替 UI に並べる選択肢一式 (順・保存値・文言)。
pub fn setlist_display_modes() -> Vec<SetlistDisplayModeOption> {
    SetlistDisplayMode::all()
        .into_iter()
        .map(|mode| SetlistDisplayModeOption {
            mode,
            raw: mode.raw().to_string(),
            label: mode.label().to_string(),
        })
        .collect()
}

/// 保存されている値からモードを決める。**移行の判断もここ 1 箇所。**
///
/// 3 値にする前は `setlist_simple_mode` という Bool だけを保存していた。
/// 新しい鍵がまだ書かれていない端末では、その Bool を読んで
/// `true` → シンプル表示 / `false` → 普通表示 に落とす。
/// 一度でもモードを選んだ端末は新しい鍵が正で、Bool は見ない。
///
/// これを各 OS に書くと「Android だけ移行しそこねて全員が普通表示に戻る」類の
/// ズレになる。判断は 1 本。
pub fn setlist_display_mode_from_stored(
    raw: Option<&str>,
    legacy_simple_mode: bool,
) -> SetlistDisplayMode {
    match raw.filter(|r| !r.is_empty()) {
        Some(r) => SetlistDisplayMode::from_raw(Some(r)),
        None if legacy_simple_mode => SetlistDisplayMode::Simple,
        None => SetlistDisplayMode::default_mode(),
    }
}

/// セトリ 1 行に添える事実を、**軸ごとにまとめた**もの。詳細表示以外では必ず空。
///
/// ```text
/// 披露   3 回目   2 年 6 か月ぶり
/// 回収   初回収
/// ```
///
/// 軸は「披露」(世の中から見た事実) と「回収」(自分の参加記録から見た事実) の 2 つ。
/// 中身が無い軸は返さない。
///
/// # なぜ「札」をやめて軸にしたか
///
/// 以前はこれらを 1 つずつ丸い札 (chip) で返していて、カバーの札・ユニット名と
/// 合わせて**1 行に丸が 5 つ**並んだ。全部同じ形・同じ大きさなので、どれが珍しくて
/// どれが当たり前なのか読めなかった。「・」で繋いだ 1 行にしても、並列に並ぶだけで
/// **構造にはならない**。
///
/// 軸の名前を左に固定して値を右に置くと、どの行も同じ位置に同じ軸が来るので、
/// 39 曲のセトリを縦に流し読みできる。だから**軸の分け方とラベルもここで決める** —
/// 各 OS が tone を見て「これは自分の事実だから回収の段」と振り分けると、
/// 同じ対応表が Swift と Kotlin に増える。
///
/// 値の中の主従 ([`RowNoteTone`]) も決める: 回数が主 (`Value`)、間隔は補足 (`Detail`)。
/// 文言そのものは [`crate::domain::performance_gap`] と
/// [`crate::domain::collection_gap`] が持つ。
///
/// `public` は世の中から見た軸 ([`setlist_public_note_groups`])。上映会の行
/// (披露ではない) では空で渡す。
pub fn setlist_row_note_groups(
    mode: SetlistDisplayMode,
    is_real_live: bool,
    public: Vec<SetlistRowNoteGroupRecord>,
    mine: &CollectionGap,
) -> Vec<SetlistRowNoteGroupRecord> {
    if !mode.shows_performance_history() {
        return Vec::new();
    }
    let mut groups = public;
    let mine_notes = collection_notes(is_real_live, mine);
    if !mine_notes.is_empty() {
        groups.push(SetlistRowNoteGroupRecord {
            label: COLLECTION_AXIS.to_string(),
            notes: mine_notes,
            opens_performers: false,
        });
    }
    groups
}

/// 世の中から見た軸 (`披露` と、あれば `歌唱`)。**参加記録を持たない出面 (Web) はこれだけを出す。**
pub fn setlist_public_note_groups(
    performance: &PerformanceGap,
    singers: &OriginalSingers,
) -> Vec<SetlistRowNoteGroupRecord> {
    let mut groups = vec![setlist_performance_note_group(performance)];
    groups.extend(setlist_singer_note_group(performance, singers));
    groups
}

/// 「原唱」の軸: **本来のオリメンは誰か** (この行で歌ったかを問わない)。押すと歌唱者の一覧を開き、
/// その下に歌っていないオリメンが並ぶ ([`SetlistRowMetaRecord::absent_originals`])。
///
/// ```text
/// 原唱   春香・千早・美希
/// 歌唱   翼・静香 初歌唱
/// ```
///
/// `オリメン不在` / `オリメン 1/3` の札は数しか言わず、「歌唱」の段は歌った人しか言わないので、
/// **オリメンが欠けている行** (歌った原唱者が原唱者より少ない) だけに、原唱者全員の名前を出す。
/// 全員揃っている行は「歌唱」の段と札で足りるので出さない。
///
/// 全体曲のように原唱者が [`ORIGINALS_NAMED_MAX`] 人を超える曲は、名前を並べても読めないので出さない
/// (その曲の原唱はブランドの全員で、欠けているのは当たり前)。
pub fn setlist_original_note_group(singers: &OriginalSingers) -> Option<SetlistRowNoteGroupRecord> {
    let names = &singers.original_names;
    if names.is_empty() || singers.sung.len() >= names.len() || names.len() > ORIGINALS_NAMED_MAX {
        return None;
    }
    // 誰が歌っていないかは行に書かず、押して開く歌唱者の一覧で見せる (一覧の下に「歌っていないオリメン」)。
    Some(SetlistRowNoteGroupRecord {
        label: ORIGINAL_AXIS.to_string(),
        notes: vec![SetlistRowNoteRecord::new(&names.join("・"), RowNoteTone::Value)],
        opens_performers: true,
    })
}

/// 歌唱者の一覧の下に並べる「この行で歌っていないオリメン」の見出し。
pub const ABSENT_ORIGINALS_HEADING: &str = "歌っていないオリメン";

/// 「原唱」の段で名前を並べる上限 (ユニット曲の人数まで)。これを超える曲 (全体曲) は段ごと出さない。
pub const ORIGINALS_NAMED_MAX: usize = 6;

/// 「歌唱」の軸: **誰がオリメンか**、オリメンにとって何回目か、**誰が初めて歌ったか**。
///
/// ```text
/// 披露   11 回目
/// 歌唱   オリメン 未来・静香 4 回目   翼 初歌唱
/// ```
///
/// 曲の通算回数はカバーや別ユニットの歌唱でも増えるので、「オリメンとしては何回目か」を
/// 別の段で添える。
///
/// **オリメンの名前を出す行** — 歌唱者にオリメンでない人が混ざる・オリメンの一部だけが歌う行
/// (札が `オリメン+α` / `オリメン 4/5` の行)。札は数しか言わないので、顔ぶれのうち誰が
/// オリメンかは名前で示す。最初の値の頭に `オリメン` と添える (`オリメン 未来・静香 4 回目`)。
/// 曲が初披露なら回数は言わない (`オリメン 未来・静香`。初披露は「披露」の段が言う)。
///
/// **それ以外の行** (歌唱者が全員オリメン) は、通算と同じ数しか言えないなら出さない
/// (全部オリメンが歌ってきた曲で毎行 2 段になると、珍しくない行まで重くなる)。
///
/// - 原唱者全員が歌い、全員が同じ回数 … `オリメン 4 回目` (ソロ曲は `本人 4 回目`)
/// - 歌った原唱者が [`NAMED_SINGERS_MAX`] 人まで … 回数ごとに名前をまとめる
///   (`フレデリカ・愛海 4 回目` `雫 3 回目`)。初めてなら `初歌唱` (初披露と同じ強さ)
/// - それより多い (全体曲など) … 名前を並べると 1 行に収まらないので幅で言う
///   (`オリメン 5〜8 回目`)
///
/// **オリメンでない人の初歌唱** (新メンバーが受け継いだ・カバーで初めて歌った) は、
/// 曲が初披露でなければ最後に添える (`翼・美希 初歌唱`、多ければ `5 人 初歌唱`)。
/// 初披露の曲では全員が初めてなので言わない。
pub fn setlist_singer_note_group(
    performance: &PerformanceGap,
    singers: &OriginalSingers,
) -> Option<SetlistRowNoteGroupRecord> {
    let sung = &singers.sung;
    let names_originals = !sung.is_empty()
        && sung.len() <= NAMED_SINGERS_MAX
        && (singers.others_count > 0 || sung.len() < singers.original_count);
    let mut notes = if names_originals {
        named_original_notes(performance, sung)
    } else {
        original_count_notes(performance, singers)
    };
    if !performance.is_first {
        notes.extend(first_time_others_note(&singers.first_time_others));
    }
    // 「13 人 初歌唱」だけでは誰か分からないので、この段は押すと歌唱者の一覧を開く。
    (!notes.is_empty()).then(|| SetlistRowNoteGroupRecord {
        label: SINGER_AXIS.to_string(),
        notes,
        opens_performers: true,
    })
}

/// 回数 1 つぶんの値。1 回目は `初歌唱` (初披露と同じ強さ)。
fn singer_ordinal_note(subject: &str, ordinal: u32) -> SetlistRowNoteRecord {
    if ordinal <= 1 {
        SetlistRowNoteRecord::new(&format!("{subject} {FIRST_SINGING_NOTE}"), RowNoteTone::Debut)
    } else {
        SetlistRowNoteRecord::new(&format!("{subject} {ordinal} 回目"), RowNoteTone::Value)
    }
}

/// 回数ごとに名前をまとめる。並びは原唱者の並び (最初に出てきた回数から)。
fn ordinal_buckets(sung: &[OriginalSingerOrdinal]) -> Vec<(u32, Vec<&str>)> {
    let mut buckets: Vec<(u32, Vec<&str>)> = Vec::new();
    for s in sung {
        match buckets.iter_mut().find(|(o, _)| *o == s.ordinal) {
            Some((_, names)) => names.push(&s.name),
            None => buckets.push((s.ordinal, vec![&s.name])),
        }
    }
    buckets
}

/// オリメンの名前を出す行の値。最初の値の頭に `オリメン` を添える。
fn named_original_notes(
    performance: &PerformanceGap,
    sung: &[OriginalSingerOrdinal],
) -> Vec<SetlistRowNoteRecord> {
    if performance.is_first {
        let names: Vec<&str> = sung.iter().map(|s| s.name.as_str()).collect();
        return vec![SetlistRowNoteRecord::new(
            &format!("{ALL_ORIGINALS} {}", names.join("・")),
            RowNoteTone::Value,
        )];
    }
    ordinal_buckets(sung)
        .iter()
        .enumerate()
        .map(|(i, (o, names))| {
            let names = names.join("・");
            let subject = if i == 0 { format!("{ALL_ORIGINALS} {names}") } else { names };
            singer_ordinal_note(&subject, *o)
        })
        .collect()
}

/// 歌唱者が全員オリメンの行 (と、名前を並べきれない行) の値。
/// 通算と同じ数しか言えないなら何も言わない。
fn original_count_notes(
    performance: &PerformanceGap,
    singers: &OriginalSingers,
) -> Vec<SetlistRowNoteRecord> {
    let sung = &singers.sung;
    if sung.is_empty() || sung.iter().all(|s| s.ordinal == performance.ordinal) {
        return Vec::new();
    }
    let min = sung.iter().map(|s| s.ordinal).min().unwrap_or(0);
    let max = sung.iter().map(|s| s.ordinal).max().unwrap_or(0);
    if sung.len() == singers.original_count && min == max {
        let subject = if singers.original_count == 1 { SOLO_ORIGINAL } else { ALL_ORIGINALS };
        vec![singer_ordinal_note(subject, min)]
    } else if sung.len() <= NAMED_SINGERS_MAX {
        ordinal_buckets(sung)
            .iter()
            .map(|(o, names)| singer_ordinal_note(&names.join("・"), *o))
            .collect()
    } else if min == max {
        vec![singer_ordinal_note(ALL_ORIGINALS, min)]
    } else {
        vec![SetlistRowNoteRecord::new(
            &format!("{ALL_ORIGINALS} {min}〜{max} 回目"),
            RowNoteTone::Value,
        )]
    }
}

/// オリメンでない人の初歌唱。名前が多ければ人数で言う。
fn first_time_others_note(names: &[String]) -> Option<SetlistRowNoteRecord> {
    if names.is_empty() {
        return None;
    }
    let subject = if names.len() <= NAMED_SINGERS_MAX {
        names.join("・")
    } else {
        format!("{} 人", names.len())
    };
    Some(SetlistRowNoteRecord::new(&format!("{subject} {FIRST_SINGING_NOTE}"), RowNoteTone::Debut))
}

/// 歌唱者 1 人ぶんの札 (歌唱者の一覧で名前の横に並べる)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistPerformerNoteRecord {
    pub idol_id: String,
    /// `オリメン` (`Value`) と `初歌唱` (`Debut`)。どちらでもなければ空。
    pub notes: Vec<SetlistRowNoteRecord>,
}

/// 歌唱者 1 人ぶんの札。**「歌唱」の段と同じ言葉・同じ強さ**で、オリメンか・初めて歌ったか。
/// 曲が初披露なら全員が初めてなので `初歌唱` は付けない (「披露」の段が言う)。
pub fn setlist_performer_notes(
    is_original: bool,
    ordinal: u32,
    performance: &PerformanceGap,
) -> Vec<SetlistRowNoteRecord> {
    let mut notes = Vec::new();
    if is_original {
        notes.push(SetlistRowNoteRecord::new(ALL_ORIGINALS, RowNoteTone::Value));
    }
    if ordinal <= 1 && !performance.is_first {
        notes.push(SetlistRowNoteRecord::new(FIRST_SINGING_NOTE, RowNoteTone::Debut));
    }
    notes
}

/// 「歌唱」の軸で名前を並べる上限。これを超えると回数の幅で言う。
pub const NAMED_SINGERS_MAX: usize = 3;

/// 「披露」の軸 1 本だけ。**自分の参加記録を持たない出面 (Web) はこれだけを出す。**
///
/// 回収の軸を空で渡して [`setlist_row_note_groups`] を通すと、「参加記録が無い」と
/// 「回収対象でない催し」の区別を呼び手が偽装することになるので、軸を分けて出す。
pub fn setlist_performance_note_group(performance: &PerformanceGap) -> SetlistRowNoteGroupRecord {
    SetlistRowNoteGroupRecord {
        label: PERFORMANCE_AXIS.to_string(),
        notes: performance_notes(performance),
        opens_performers: false,
    }
}

/// 世の中から見た事実。初披露なら 1 つだけ (「1 回目」は言わない)。
fn performance_notes(performance: &PerformanceGap) -> Vec<SetlistRowNoteRecord> {
    if performance.is_first {
        return vec![SetlistRowNoteRecord::new(&performance.ordinal_label, RowNoteTone::Debut)];
    }
    let mut notes = vec![SetlistRowNoteRecord::new(&performance.ordinal_label, RowNoteTone::Value)];
    // 間隔は回数の補足。1 年に満たなければ言わない。
    if let Some(since) = &performance.since_label {
        notes.push(SetlistRowNoteRecord::new(since, RowNoteTone::Detail));
    }
    notes
}

/// 自分の参加記録から見た事実。出ないこともある (そのときは軸ごと出さない)。
///
/// 「回収済みです」とは言わない — 参加していない公演のセトリで目に留めたいのは
/// **まだ持っていない曲**で、既に持っている曲にも印を付けると全行が埋まる。
///
/// `is_real_live` が偽 (リリイベ・配信番組など回収の対象でない催し) では必ず空。
/// ここを通さないと、**自分で参加記録を付けた公演で全行が「未回収」になる**
/// (参加した公演の集合はリアルライブだけに絞られているので、参加した行が
/// 「未参加 かつ 未回収」に化ける)。セトリを持つ公演の 2 割強はリリイベ。
fn collection_notes(is_real_live: bool, mine: &CollectionGap) -> Vec<SetlistRowNoteRecord> {
    if !is_real_live {
        return Vec::new();
    }
    if !mine.attended {
        return if mine.collected_count == 0 {
            vec![SetlistRowNoteRecord::new(UNCOLLECTED_NOTE, RowNoteTone::Missing)]
        } else {
            Vec::new()
        };
    }
    let Some(ordinal) = mine.ordinal_label.as_deref() else { return Vec::new() };
    let mut notes = vec![SetlistRowNoteRecord::new(ordinal, RowNoteTone::Mine)];
    // 自分の間隔も、披露と同じく回数の補足として添える。
    if let Some(since) = collection_interval_label(mine) {
        notes.push(SetlistRowNoteRecord::new(&since, RowNoteTone::Detail));
    }
    notes
}

/// 軸のラベル。**行の左に固定幅で並ぶ**ので、2 文字で揃えてある。
pub const PERFORMANCE_AXIS: &str = "披露";
pub const COLLECTION_AXIS: &str = "回収";
pub const SINGER_AXIS: &str = "歌唱";
/// 本来のオリメン (原唱者) の段。
pub const ORIGINAL_AXIS: &str = "原唱";

/// 「歌唱」の軸の主語。原唱者全員が揃って同じ回数のとき。
pub const ALL_ORIGINALS: &str = "オリメン";
/// 同じく、原唱者が 1 人 (ソロ曲) のとき。
pub const SOLO_ORIGINAL: &str = "本人";
/// 原唱者が初めてその曲を歌った披露。
pub const FIRST_SINGING_NOTE: &str = "初歌唱";

/// まだ一度も回収していない曲の文言。
pub const UNCOLLECTED_NOTE: &str = "未回収";

/// 事実 1 つをどれだけ強く出すか。**色や太さの出し分けはこれで行う。**
///
/// 文字列を見て強調を決めると (`text == "未回収"` 等)、同じ条件が Swift と Kotlin に
/// 増える。文が増えたときに片方だけ地味なまま、という壊れ方もする。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum RowNoteTone {
    /// その軸の主な値 (`4 回目`)。本文の色で出す。
    Value,
    /// 主な値の補足 (`3 年ぶり`)。沈める。
    Detail,
    /// 初披露。この行でいちばん珍しい。
    Debut,
    /// 自分が回収した (`初回収` `3 回目`)。
    Mine,
    /// 自分がまだ持っていない (`未回収`)。
    Missing,
}

/// 行に添える事実 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistRowNoteRecord {
    pub text: String,
    pub tone: RowNoteTone,
}

/// 軸 1 つぶん (ラベルと、その軸の値の並び)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistRowNoteGroupRecord {
    /// 行の左に出す軸の名前 (`披露` / `回収`)。
    pub label: String,
    pub notes: Vec<SetlistRowNoteRecord>,
    /// 押すと歌唱者の一覧 (1 人ずつのオリメン・初歌唱の札つき) を開く段か。
    /// `歌唱` (「13 人 初歌唱」の 13 人が誰か) と `原唱` (誰が歌っていないか) の段。
    pub opens_performers: bool,
}

impl SetlistRowNoteRecord {
    fn new(text: &str, tone: RowNoteTone) -> Self {
        Self { text: text.to_string(), tone }
    }
}

#[cfg(test)]
mod setlist_row_note_tests {
    use super::*;
    use crate::domain::collection_gap::collection_ordinal_label;

    fn gap(is_first: bool, ordinal: &str, since: Option<&str>) -> PerformanceGap {
        PerformanceGap {
            ordinal: if is_first { 1 } else { 4 },
            ordinal_label: ordinal.to_string(),
            is_first,
            previous_date: None,
            months_since: None,
            since_label: since.map(str::to_string),
        }
    }

    fn mine(attended: bool, ordinal: u32, collected: u32, months: Option<u32>) -> CollectionGap {
        CollectionGap {
            attended,
            ordinal,
            ordinal_label: attended.then(|| collection_ordinal_label(ordinal)),
            is_first: attended && ordinal == 1,
            previous_date: None,
            months_since: months,
            since_label: months.and_then(crate::domain::performance_gap::interval_label),
            collected_count: collected,
        }
    }

    /// 軸ごとに (ラベル, 値の並び, 調子の並び) へ畳む。
    fn axes(
        groups: &[SetlistRowNoteGroupRecord],
    ) -> Vec<(&str, Vec<&str>, Vec<RowNoteTone>)> {
        groups
            .iter()
            .map(|g| {
                (
                    g.label.as_str(),
                    g.notes.iter().map(|n| n.text.as_str()).collect(),
                    g.notes.iter().map(|n| n.tone).collect(),
                )
            })
            .collect()
    }

    fn groups(
        is_real_live: bool,
        performance: &PerformanceGap,
        mine: &CollectionGap,
    ) -> Vec<SetlistRowNoteGroupRecord> {
        setlist_row_note_groups(
            SetlistDisplayMode::Detailed,
            is_real_live,
            setlist_public_note_groups(performance, &OriginalSingers::default()),
            mine,
        )
    }

    /// 軸は「披露 → 回収」の順。回数が主で、間隔はその補足。
    #[test]
    fn 披露の軸のあとに回収の軸を置く() {
        let g = groups(
            true,
            &gap(false, "4 回目", Some("3 年 10 か月ぶり")),
            &mine(true, 3, 3, Some(24)),
        );
        assert_eq!(
            axes(&g),
            vec![
                (
                    "披露",
                    vec!["4 回目", "3 年 10 か月ぶり"],
                    vec![RowNoteTone::Value, RowNoteTone::Detail]
                ),
                ("回収", vec!["3 回目", "2 年ぶり"], vec![RowNoteTone::Mine, RowNoteTone::Detail]),
            ]
        );
    }

    /// 初披露は 1 つだけ (「1 回目」を並べない)。強調は Debut。
    #[test]
    fn 初披露は_1_つだけで強く出す() {
        let g = groups(true, &gap(true, "初披露", None), &mine(false, 0, 2, None));
        assert_eq!(
            axes(&g),
            vec![("披露", vec!["初披露"], vec![RowNoteTone::Debut])],
            "回収済みの曲には回収の軸を出さない"
        );
    }

    /// 短い間隔でも「いつぶり」を言う (直近の披露も知りたい)。
    #[test]
    fn 短い間隔も言う() {
        let g = groups(true, &gap(false, "9 回目", Some("3 か月ぶり")), &mine(true, 2, 2, Some(3)));
        assert_eq!(
            axes(&g),
            vec![
                ("披露", vec!["9 回目", "3 か月ぶり"], vec![RowNoteTone::Value, RowNoteTone::Detail]),
                ("回収", vec!["2 回目", "3 か月ぶり"], vec![RowNoteTone::Mine, RowNoteTone::Detail]),
            ]
        );
    }

    /// 参加していない公演では、まだ持っていない曲にだけ「未回収」。
    #[test]
    fn 参加していない行は未回収だけを出す() {
        let g = groups(true, &gap(false, "4 回目", None), &mine(false, 0, 0, None));
        assert_eq!(
            axes(&g),
            vec![
                ("披露", vec!["4 回目"], vec![RowNoteTone::Value]),
                ("回収", vec!["未回収"], vec![RowNoteTone::Missing]),
            ]
        );
    }

    /// 回収の対象でない催し (リリイベ等) では、回収の軸ごと出さない。
    /// **参加した公演で「未回収」と言わないための門。**
    #[test]
    fn 回収の対象でない催しでは回収の軸を出さない() {
        for m in [mine(false, 0, 0, None), mine(true, 1, 1, None)] {
            let g = groups(false, &gap(false, "4 回目", None), &m);
            assert_eq!(g.len(), 1, "披露の軸だけが残る");
            assert_eq!(g[0].label, "披露");
        }
    }

    // ---- 歌唱 (オリメンにとって何回目か) ----



    fn singers(original_count: usize, sung: &[(&str, u32)]) -> OriginalSingers {
        OriginalSingers {
            original_count,
            sung: sung
                .iter()
                .map(|&(name, ordinal)| OriginalSingerOrdinal { name: name.to_string(), ordinal })
                .collect(),
            others_count: 0,
            first_time_others: Vec::new(),
            original_names: (0..original_count).map(|i| format!("o{i}")).collect(),
        }
    }

    /// オリメンでない歌唱者を足す (`first` はそのうち初めて歌った人)。
    fn with_others(mut s: OriginalSingers, count: usize, first: &[&str]) -> OriginalSingers {
        s.others_count = count;
        s.first_time_others = first.iter().map(|n| n.to_string()).collect();
        s
    }

    fn singer_axis(total: u32, s: &OriginalSingers) -> Option<(Vec<String>, Vec<RowNoteTone>)> {
        let mut performance = gap(total == 1, "", None);
        performance.ordinal = total;
        setlist_singer_note_group(&performance, s).map(|g| {
            assert_eq!(g.label, "歌唱");
            (g.notes.iter().map(|n| n.text.clone()).collect(), g.notes.iter().map(|n| n.tone).collect())
        })
    }

    /// 通算と同じ数しか言えないなら出さない (ずっとオリメンが歌ってきた曲)。
    /// オリメンが歌っていない行 (カバー) でも出さない — それは `オリメン不在` の札が言う。
    #[test]
    fn 通算と同じか_オリメンがいなければ歌唱の段は出さない() {
        assert_eq!(singer_axis(4, &singers(2, &[("千早", 4), ("美希", 4)])), None);
        assert_eq!(singer_axis(11, &singers(5, &[])), None);
    }

    /// 全員揃って同じ回数なら名前を並べない。ソロ曲は「本人」。
    #[test]
    fn 全員揃えばオリメン_ソロは本人() {
        assert_eq!(
            singer_axis(11, &singers(5, &[("a", 4), ("b", 4), ("c", 4), ("d", 4), ("e", 4)])),
            Some((vec!["オリメン 4 回目".to_string()], vec![RowNoteTone::Value]))
        );
        assert_eq!(
            singer_axis(3, &singers(1, &[("咲季", 1)])),
            Some((vec!["本人 初歌唱".to_string()], vec![RowNoteTone::Debut]))
        );
    }

    /// 一部だけなら、誰がオリメンかを名前で言い、回数ごとにまとめる (原唱者の並びのまま)。
    #[test]
    fn 一部なら回数ごとに名前をまとめる() {
        assert_eq!(
            singer_axis(6, &singers(5, &[("友紀", 3), ("愛海", 3)])),
            Some((vec!["オリメン 友紀・愛海 3 回目".to_string()], vec![RowNoteTone::Value]))
        );
        assert_eq!(
            singer_axis(9, &singers(5, &[("フレデリカ", 4), ("雫", 1), ("愛海", 4)])),
            Some((
                vec!["オリメン フレデリカ・愛海 4 回目".to_string(), "雫 初歌唱".to_string()],
                vec![RowNoteTone::Value, RowNoteTone::Debut]
            ))
        );
    }

    /// オリメン+α の行は、通算と同じ回数でも誰がオリメンかを言う (札は数しか言わない)。
    #[test]
    fn オリメン以外が混ざる行はオリメンの名前を出す() {
        let s = with_others(singers(2, &[("千早", 4), ("美希", 4)]), 1, &[]);
        assert_eq!(
            singer_axis(4, &s),
            Some((vec!["オリメン 千早・美希 4 回目".to_string()], vec![RowNoteTone::Value]))
        );
        // 曲が初披露なら回数は言わず、名前だけ。
        assert_eq!(
            singer_axis(1, &s),
            Some((vec!["オリメン 千早・美希".to_string()], vec![RowNoteTone::Value]))
        );
    }

    /// オリメンでない人の初歌唱は最後に添える。初披露の曲では全員初めてなので言わない。
    #[test]
    fn オリメンでない人の初歌唱を添える() {
        let s = with_others(singers(2, &[("千早", 4), ("美希", 4)]), 2, &["翼", "静香"]);
        assert_eq!(
            singer_axis(4, &s),
            Some((
                vec!["オリメン 千早・美希 4 回目".to_string(), "翼・静香 初歌唱".to_string()],
                vec![RowNoteTone::Value, RowNoteTone::Debut]
            ))
        );
        // カバー (オリメン不在) でも初歌唱は言う。
        let cover = with_others(singers(5, &[]), 2, &["翼", "静香"]);
        assert_eq!(
            singer_axis(11, &cover),
            Some((vec!["翼・静香 初歌唱".to_string()], vec![RowNoteTone::Debut]))
        );
        // 多ければ人数で。
        let many = with_others(singers(5, &[]), 5, &["a", "b", "c", "d", "e"]);
        assert_eq!(
            singer_axis(11, &many),
            Some((vec!["5 人 初歌唱".to_string()], vec![RowNoteTone::Debut]))
        );
        let first = with_others(singers(5, &[]), 2, &["翼", "静香"]);
        assert_eq!(singer_axis(1, &first), None, "初披露の曲では言わない");
    }

    /// 原唱の段: オリメンが欠けている行だけ、原唱者全員の名前。揃っている行と全体曲は出さない。
    #[test]
    fn 欠けている行だけ本来のオリメンを出す() {
        let named = |n: usize, sung: &[(&str, u32)]| {
            let mut s = singers(n, sung);
            s.original_names = ["春香", "千早", "美希", "雪歩", "やよい", "真", "伊織"][..n]
                .iter()
                .map(|x| x.to_string())
                .collect();
            setlist_original_note_group(&s).map(|g| {
                assert_eq!(g.label, "原唱");
                g.notes.iter().map(|n| n.text.clone()).collect::<Vec<_>>()
            })
        };
        assert_eq!(named(3, &[]), Some(vec!["春香・千早・美希".to_string()]), "カバー");
        assert_eq!(
            named(3, &[("千早", 4)]),
            Some(vec!["春香・千早・美希".to_string()]),
            "一部でも名前だけ (歌っていない人は一覧で見せる)"
        );
        assert_eq!(named(1, &[]), Some(vec!["春香".to_string()]), "ソロ曲のカバー");
        assert_eq!(named(2, &[("春香", 4), ("千早", 4)]), None, "揃っている");
        assert_eq!(named(7, &[("春香", 4)]), None, "全体曲は並べない");
    }

    /// 歌唱者の一覧の札: オリメンと初歌唱。初披露の曲では初歌唱を付けない。
    #[test]
    fn 歌唱者の札はオリメンと初歌唱() {
        let texts = |is_original, ordinal, total: u32| {
            let mut performance = gap(total == 1, "", None);
            performance.ordinal = total;
            setlist_performer_notes(is_original, ordinal, &performance)
                .into_iter()
                .map(|n| (n.text, n.tone))
                .collect::<Vec<_>>()
        };
        assert_eq!(texts(true, 4, 6), vec![("オリメン".to_string(), RowNoteTone::Value)]);
        assert_eq!(
            texts(true, 1, 6),
            vec![
                ("オリメン".to_string(), RowNoteTone::Value),
                ("初歌唱".to_string(), RowNoteTone::Debut)
            ]
        );
        assert_eq!(texts(false, 1, 6), vec![("初歌唱".to_string(), RowNoteTone::Debut)]);
        assert_eq!(texts(false, 3, 6), vec![]);
        assert_eq!(texts(false, 1, 1), vec![], "初披露の曲では初歌唱を付けない");
    }

    /// 名前が多すぎる (全体曲など) ときは幅で言う。1 行に収まらない名前の列は読めない。
    #[test]
    fn 大人数は回数の幅で言う() {
        let many = [("a", 5), ("b", 8), ("c", 6), ("d", 5)];
        assert_eq!(
            singer_axis(12, &singers(13, &many)),
            Some((vec!["オリメン 5〜8 回目".to_string()], vec![RowNoteTone::Value]))
        );
        let same = [("a", 2), ("b", 2), ("c", 2), ("d", 2)];
        assert_eq!(
            singer_axis(3, &singers(9, &same)),
            Some((vec!["オリメン 2 回目".to_string()], vec![RowNoteTone::Value]))
        );
    }
}

#[cfg(test)]
mod setlist_display_mode_tests {
    use super::*;

    /// Bool 1 つだった頃の設定が壊れない。
    #[test]
    fn the_old_boolean_setting_still_decides_until_a_mode_is_picked() {
        assert_eq!(
            setlist_display_mode_from_stored(None, true),
            SetlistDisplayMode::Simple
        );
        assert_eq!(
            setlist_display_mode_from_stored(None, false),
            SetlistDisplayMode::Normal,
            "札が見えていた人も普通表示に落ちる (今回の意図)"
        );
        // 新しい鍵があれば Bool は見ない。
        assert_eq!(
            setlist_display_mode_from_stored(Some("detailed"), true),
            SetlistDisplayMode::Detailed
        );
        // 空文字・未知の値は「まだ選んでいない」として扱う。
        assert_eq!(
            setlist_display_mode_from_stored(Some(""), true),
            SetlistDisplayMode::Simple
        );
        assert_eq!(
            setlist_display_mode_from_stored(Some("なにこれ"), false),
            SetlistDisplayMode::Normal
        );
    }

    /// 選択肢は情報が少ない順・保存値は序数でない。
    #[test]
    fn the_options_are_ordered_and_stored_by_name() {
        let options = setlist_display_modes();
        assert_eq!(
            options.iter().map(|o| o.raw.as_str()).collect::<Vec<_>>(),
            vec!["simple", "normal", "detailed"]
        );
        assert_eq!(
            options.iter().map(|o| o.label.as_str()).collect::<Vec<_>>(),
            vec!["シンプル表示", "普通表示", "詳細表示"]
        );
        for o in &options {
            assert_eq!(SetlistDisplayMode::from_raw(Some(&o.raw)), o.mode);
        }
    }
}

/// 行の値の見せ方。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum RowStyle {
    /// ふつうの本文。
    Plain,
    /// 等幅で出す (ローマ字・スリーサイズ・カラーコードなど、桁を揃えたいもの)。
    Monospaced,
    /// 値が色コードなので、色見本を添える。
    ColorSwatch,
}

/// 行を押したときにしたいこと。**遷移そのものは各OSが行う**。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum RowAction {
    /// 押せない。
    None,
    /// 同じ誕生月のアイドル一覧へ。
    FilterByBirthMonth { month: u32 },
    /// 値を写す。
    CopyValue,
    /// 長い値をその場で開く/畳む。
    ToggleExpansion,
}

/// 画面に出す 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ScreenRow {
    /// 左の見出し。
    pub label: String,
    /// 右の値。
    pub value: String,
    pub style: RowStyle,
    pub action: RowAction,
}

/// アイドル詳細のプロフィール欄に渡す値。
///
/// 表示用に整形済みの文字列を受け取る。整形 (「4月3日」「160cm」等) は
/// それぞれの担当モジュールが持つので、ここでは**並べる判断だけ**に集中する。
#[derive(uniffi::Record, Clone, Debug, Default)]
pub struct IdolProfileInput {
    pub name_kana: Option<String>,
    pub name_romaji: Option<String>,
    /// 「4月3日」等。無ければ行ごと出さない。
    pub birthday_display: Option<String>,
    /// 誕生月。あるとき誕生日の行から同じ月のアイドル一覧へ飛べる。
    pub birth_month: Option<u32>,
    /// 「17歳 / 160cm / 45kg」等。
    pub age_height_weight: Option<String>,
    pub three_size: Option<String>,
    pub blood_constellation: Option<String>,
    pub birthplace_handedness: Option<String>,
    pub hobby_talent: Option<String>,
    /// カラーコード (#RRGGBB)。
    pub color: Option<String>,
}

/// アイドル詳細のプロフィール行を組み立てる。
///
/// 値が無い項目は**行ごと出さない** (空欄の行が並ぶより情報が読みやすい)。
/// 並びは iOS の既存実装に合わせてある。
pub fn idol_profile_rows(input: &IdolProfileInput) -> Vec<ScreenRow> {
    let mut rows = Vec::new();
    // 値が空 (None または "") のときは行を作らない。
    fn push(
        rows: &mut Vec<ScreenRow>,
        label: &str,
        value: &Option<String>,
        style: RowStyle,
        action: RowAction,
    ) {
        if let Some(v) = value {
            if !v.is_empty() {
                rows.push(ScreenRow { label: label.to_string(), value: v.clone(), style, action });
            }
        }
    }

    push(&mut rows, "よみ", &input.name_kana, RowStyle::Plain, RowAction::ToggleExpansion);
    push(&mut rows, "ローマ字", &input.name_romaji, RowStyle::Monospaced, RowAction::None);

    // 誕生日だけは、月が分かるときに「同じ誕生月のアイドル」へ飛べる。
    if let Some(bday) = &input.birthday_display {
        if !bday.is_empty() {
            rows.push(ScreenRow {
                label: "誕生日".to_string(),
                value: bday.clone(),
                style: RowStyle::Plain,
                action: match input.birth_month {
                    Some(m) if (1..=12).contains(&m) => RowAction::FilterByBirthMonth { month: m },
                    _ => RowAction::None,
                },
            });
        }
    }

    push(&mut rows, "年齢 / 身長 / 体重", &input.age_height_weight, RowStyle::Plain, RowAction::None);
    push(&mut rows, "スリーサイズ", &input.three_size, RowStyle::Monospaced, RowAction::None);
    push(&mut rows, "血液型 / 星座", &input.blood_constellation, RowStyle::Plain, RowAction::None);
    push(&mut rows, "出身 / 利き手", &input.birthplace_handedness, RowStyle::Plain, RowAction::None);
    push(&mut rows, "趣味 / 特技", &input.hobby_talent, RowStyle::Plain, RowAction::ToggleExpansion);
    // カラーは押すと写せる (配信や実況で使う人が居る)。
    push(&mut rows, "カラー", &input.color, RowStyle::ColorSwatch, RowAction::CopyValue);

    rows
}

#[cfg(test)]
mod tests {
    use super::*;

    fn full() -> IdolProfileInput {
        IdolProfileInput {
            name_kana: Some("しまむら うづき".into()),
            name_romaji: Some("Uzuki Shimamura".into()),
            birthday_display: Some("4月17日".into()),
            birth_month: Some(4),
            age_height_weight: Some("17歳 / 159cm / 46kg".into()),
            three_size: Some("83/57/85".into()),
            blood_constellation: Some("O型 / 牡羊座".into()),
            birthplace_handedness: Some("東京都 / 右利き".into()),
            hobby_talent: Some("読書 / 早起き".into()),
            color: Some("#EE7F9C".into()),
        }
    }

    #[test]
    fn order_matches_the_existing_screens() {
        let rows = idol_profile_rows(&full());
        let labels: Vec<&str> = rows.iter().map(|r| r.label.as_str()).collect();
        assert_eq!(labels, vec![
            "よみ", "ローマ字", "誕生日", "年齢 / 身長 / 体重",
            "スリーサイズ", "血液型 / 星座", "出身 / 利き手", "趣味 / 特技", "カラー",
        ]);
    }

    /// 空文字も「無い」と同じ扱い。DB に空文字が入っていても空行を作らない。
    #[test]
    fn empty_string_is_treated_as_absent() {
        let rows = idol_profile_rows(&IdolProfileInput {
            name_kana: Some(String::new()),
            name_romaji: Some("  ".into()),
            ..Default::default()
        });
        assert_eq!(rows.iter().filter(|r| r.label == "よみ").count(), 0);
        // 空白だけの値は残す (意味のある空白かは判断できないため) — 挙動を明示しておく
        assert_eq!(rows.len(), 1);
    }

    #[test]
    fn birthday_links_to_the_month_list_when_month_is_known() {
        let rows = idol_profile_rows(&full());
        let b = rows.iter().find(|r| r.label == "誕生日").unwrap();
        assert_eq!(b.action, RowAction::FilterByBirthMonth { month: 4 });
    }

    /// 範囲外の月は押せない行にする (0 や 13 が来ても遷移させない)。
    #[test]
    fn out_of_range_month_is_not_tappable() {
        for m in [0u32, 13, 99] {
            let rows = idol_profile_rows(&IdolProfileInput {
                birthday_display: Some("x".into()),
                birth_month: Some(m),
                ..Default::default()
            });
            assert_eq!(rows[0].action, RowAction::None, "month={m}");
        }
    }
}

/// 進み具合 (0〜1) を、見せる % (0〜100 の整数) にする。両 OS の輪 (ImasProgressRing) の文字と読み上げに使う。
///
/// **四捨五入しない。** 2118/2128 (99.53%) を「100%」と出すと、まだ 10 曲残っているのに終わったように
/// 見える。切り捨てにして、100% は全部終わったときだけにする。浮動小数の誤差 (0.29 × 100 = 28.999…) で
/// 1 つ下に落ちないよう、ごく小さな幅を足してから切り捨てる。
pub fn progress_percent(fraction: f64) -> u32 {
    if !fraction.is_finite() || fraction <= 0.0 {
        return 0;
    }
    if fraction >= 1.0 {
        return 100;
    }
    ((fraction * 100.0 + 1e-9).floor() as u32).min(99)
}

#[cfg(test)]
mod progress_percent_tests {
    use super::progress_percent;

    #[test]
    fn never_rounds_up_to_complete() {
        assert_eq!(progress_percent(2118.0 / 2128.0), 99);
        assert_eq!(progress_percent(0.9999), 99);
        assert_eq!(progress_percent(1.0), 100);
    }

    #[test]
    fn float_error_does_not_drop_a_point() {
        assert_eq!(progress_percent(0.29), 29);
        assert_eq!(progress_percent(0.57), 57);
        assert_eq!(progress_percent(29.0 / 100.0), 29);
    }

    #[test]
    fn clamps_and_handles_odd_input() {
        assert_eq!(progress_percent(-0.5), 0);
        assert_eq!(progress_percent(0.0), 0);
        assert_eq!(progress_percent(1.5), 100);
        assert_eq!(progress_percent(f64::NAN), 0);
        assert_eq!(progress_percent(0.004), 0);
    }
}
