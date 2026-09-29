//! 「この曲は誰の曲か」を 1 行で出すときの名義。
//!
//! # なぜ切り出すか
//!
//! 同じ規則が **iOS の曲一覧 (`SongRowView.displayLabel`) とコアの
//! `mastery::group_key` の 2 か所に手写経されていて、しかも食い違っていた**。
//! 一覧は `singer_label` を見ずに括弧の前を抜き、群分けは括弧を見ずに
//! `singer_label` を見る。同じ曲が画面によって違う名義で出る。
//!
//! 名義の決め方は OS SDK に触らずに書ける = コアの持ち物
//! (docs/ARCHITECTURE.md)。ここへ寄せていく。
//!
//! **まだ移せていないもの**: `SongRowView.displayLabel` は `singer_label` の
//! 括弧の前を抜く段 (`"MILLIONSTARS（…）"` → `"MILLIONSTARS"`) を持っていて、
//! ここには無い。取り込むと `mastery` の Unit 群も括弧違いが 1 群に畳まれる
//! (群キーは永続化していないので移行は不要、見え方だけ変わる)。
//! どちらに揃えるか決めてから移す。それまでは規則が 2 つある。
//!
//! # 決め方
//!
//! `unit_name` → `singer_label` → 原唱者の連結、の順に落ちる。
//! 空文字は「値が無い」として扱う (DB には `''` と `NULL` が混在している)。

use crate::domain::display_join::non_empty;

/// 名義を組むのに要るぶんだけの射影。
///
/// 曲そのもの (`snapshot::Song`) を渡さないのは、原唱者名が曲の外
/// (`song_artists` → `idols`) にあるため。呼ぶ側で 1 回詰めて渡す。
#[derive(uniffi::Record, Clone, Debug)]
pub struct PerformerNaming {
    /// DB の `songs.unit_name`。ユニット名義ならここに入っている。
    pub unit_name: Option<String>,
    /// DB の `songs.singer_label`。個人名を併記する名義 (`天道輝、若里春名、…`)。
    pub singer_label: Option<String>,
    /// 原唱者 (`song_artists.role='original'`) の表示名。上 2 つが空のときだけ使う。
    pub performer_names: Vec<String>,
}

/// 原唱者を並べるときの区切り。
///
/// [`crate::domain::display_join::PARTS_SEPARATOR`] (` ・ `) と違って前後に空白を置かない。
/// あちらは種類の違う項目 (名義・年・シリーズ) を並べる区切りで、こちらは
/// **同じ種類のものの列挙**。iOS の既存表示 (`SongRowView`) も詰めた中黒なので揃える。
const PERFORMER_SEPARATOR: &str = "・";

/// 1 行で出す名義。出せるものが何も無ければ `None`。
///
/// `None` を返すのは、呼ぶ側に「行ごと出さない」を素直に書かせるため
/// ([`crate::domain::display_join::join_parts`] と同じ約束)。ここで「不明」のような
/// 文字を置くと、画面ごとに違う言い方が増える。
pub fn performer_label(naming: &PerformerNaming) -> Option<String> {
    if let Some(unit) = non_empty(&naming.unit_name) {
        return Some(unit.to_string());
    }
    if let Some(label) = non_empty(&naming.singer_label) {
        return Some(label.to_string());
    }
    let joined = join_names(&naming.performer_names, PERFORMER_SEPARATOR);
    (!joined.is_empty()).then_some(joined)
}

/// 空白だけの要素を落としてから繋ぐ。区切りだけが並ぶのを防ぐ 1 段で、
/// 曲一覧の中黒もセトリ行の全角スラッシュもここを通る。
fn join_names(names: &[String], separator: &str) -> String {
    let mut out = String::new();
    for name in names.iter().map(|n| n.trim()).filter(|n| !n.is_empty()) {
        if !out.is_empty() {
            out.push_str(separator);
        }
        out.push_str(name);
    }
    out
}

/// スナップショットの曲 1 行から名義を組む。
///
/// 射影 ([`PerformerNaming`]) を呼ぶ側で詰めると、**「原唱者は `role='original'` だけ」**
/// という一段が呼ぶ側の数だけ写される。実際に LLM 向けツールの 2 ファイルが
/// それぞれ `artists_by_song` を `role == "original"` で濾していた。
/// 詰め方ごとここに置いて、呼ぶ側は曲の添字を渡すだけにする。
pub fn song_performer_label(
    snap: &crate::domain::snapshot::Snapshot,
    song: u32,
) -> Option<String> {
    let s = &snap.songs[song as usize];
    performer_label(&PerformerNaming {
        unit_name: s.unit_name.clone(),
        singer_label: s.singer_label.clone(),
        performer_names: snap
            .song_artists(&s.id, Some("original"))
            .iter()
            .map(|idol| idol.name.clone())
            .collect(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn naming(unit: Option<&str>, singer: Option<&str>, performers: &[&str]) -> PerformerNaming {
        PerformerNaming {
            unit_name: unit.map(str::to_string),
            singer_label: singer.map(str::to_string),
            performer_names: performers.iter().map(|s| s.to_string()).collect(),
        }
    }

    #[test]
    fn unit_name_wins() {
        let n = naming(Some("Team.Sol"), Some("八宮めぐる、白瀬咲耶"), &["八宮めぐる"]);
        assert_eq!(performer_label(&n).as_deref(), Some("Team.Sol"));
    }

    #[test]
    fn falls_back_to_singer_label() {
        let n = naming(None, Some("天道輝、若里春名、水嶋咲"), &["天道輝"]);
        assert_eq!(performer_label(&n).as_deref(), Some("天道輝、若里春名、水嶋咲"));
    }

    /// DB には `NULL` と `''` が混ざっている。空文字で止まると
    /// 名義が空のまま出て、原唱者まで落ちない。
    #[test]
    fn empty_string_is_not_a_value() {
        let n = naming(Some(""), Some("   "), &["櫻木真乃"]);
        assert_eq!(performer_label(&n).as_deref(), Some("櫻木真乃"));
    }

    #[test]
    fn nothing_to_show_is_none() {
        assert_eq!(performer_label(&naming(None, None, &[])), None);
    }

    /// 原唱者の配列に空が混ざっても区切りだけが並ばない。
    #[test]
    fn blank_performers_are_dropped() {
        let n = naming(None, None, &["浅倉透", "", "  ", "市川雛菜"]);
        assert_eq!(performer_label(&n).as_deref(), Some("浅倉透・市川雛菜"));
    }
}

// =============================================================================
// セトリ 1 行の名義
// =============================================================================

/// セトリ行で名前を並べるときの区切り。**全角スラッシュ**。
///
/// 上の [`PERFORMER_SEPARATOR`] (中黒) と違えてあるのは気分ではなく、
/// 公式のセットリスト画像がセトリ行の併記に `／` を使っているから。曲一覧の名義
/// (中黒) と同じにすると、セトリのスクショが公式と並べたときだけ揃わなくなる。
pub const SETLIST_SEPARATOR: &str = "／";

/// セトリ 1 行の名義を組むのに要る射影。
///
/// **順番に意味がある** — フィールドの並びがそのまま [`setlist_performer_label`] の
/// 落ち方の順になっている。
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SetlistNaming {
    /// `setlist_items.unit_name`。**その披露限りの名義**で、曲の名義より強い
    /// (合同ライブの特別編成など、その日だけの名前)。
    pub item_unit_name: Option<String>,
    /// `songs.unit_name`。恒常ユニットの名義。
    pub song_unit_name: Option<String>,
    /// `songs.singer_label`。個人名を併記する名義 (`天道輝、若里春名、…`)。
    pub singer_label: Option<String>,
    /// 歌唱者の顔ぶれが「曲を持つユニット」1〜3 個の和集合とちょうど一致したときの、
    /// そのユニット名 (`crate::domain::unit_queries::exact_matching_unit_names`)。
    /// **これは推論**で、曲が名義を持っていれば出番はない。
    pub lineup_unit_names: Vec<String>,
    /// この曲に原唱者 (`song_artists.role='original'`) が記録されているか。
    /// 推論を止める根拠に使う (下の関数 docs 参照)。
    pub has_original_artists: bool,
    /// 公演の出演者全員で歌う行か (`crate::domain::setlist_lineup::is_full_cast`)。
    pub is_full_cast: bool,
    /// 歌唱者の表示名 (`performer_display_name` で解決済み・披露順)。
    pub performer_names: Vec<String>,
}

/// 名義がどこから来たか。**画面はこれを見て見せ方を変える** (ユニット名ならチップ、
/// 名前の列挙ならアバター) ので、決めた結果と一緒に返す。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SetlistLabelSource {
    /// `setlist_items.unit_name`。
    ItemUnitName,
    /// `songs.unit_name`。
    SongUnitName,
    /// `songs.singer_label`。
    SingerLabel,
    /// 歌唱者の顔ぶれ推論。
    LineupUnits,
    /// 出演者全員 (`全員`)。
    FullCast,
    /// 歌唱者の名前の列挙。
    PerformerNames,
}

/// セトリ 1 行に出す名義。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SetlistLabel {
    pub text: String,
    pub source: SetlistLabelSource,
    /// ユニット名のチップに出す名前。ユニット名義でない行・顔ぶれがユニットを
    /// 成していない行では空 (空なら画面は歌唱者のアバターを出す)。
    pub unit_names: Vec<String>,
}

/// セトリ 1 行の名義。出せるものが何も無ければ `None`。
///
/// # 落ちる順
///
/// 1. `setlist_items.unit_name` — その披露限りの名義
/// 2. `songs.unit_name`
/// 3. `songs.singer_label`
/// 4. 歌唱者の顔ぶれ推論 (ユニットと完全一致)
/// 5. `全員` / 歌唱者の名前の列挙
///
/// # なぜこの順か (回帰: 2026-09-19)
///
/// iOS は 4 を最初に見ていた。歌唱者がユニットのメンバー集合と完全一致しさえすれば、
/// **曲が持っている名義を無視して**ユニット名を出す。実データで 428 行が
/// これに当たり、`THE 虎牙道` が `THE虎牙道` に、`Legenders＆C.FIRST` が
/// `Legenders／C.FIRST` に、`315 STARS` が `315 ALLSTARS` に化けていた。
/// 名義は曲 (とその披露) が持っている事実で、顔ぶれは推論。**事実が推論に負けない。**
///
/// # 原唱者が記録されている曲では推論しない
///
/// 4 に `has_original_artists` の門を置いてある。`ml_パルティシオン` は
/// エミリー スチュアート と 徳川まつり の 2 人が歌うが、**Charlotte・Charlotte
/// (この 2 人のユニット) の曲ではなく、2 人へ贈られた曲**で、`unit_id` / `unit_name` は
/// 意図して空にしてある (同じ 2 人の『だってあなたはプリンセス』は `unit_id` を持つ)。
/// 名義が 1〜3 で何も出ないとき、**原唱者が分かっているなら 5 で本当の名前が出せる**ので、
/// ユニット名を推し当てる理由がない。推論が要るのは「原唱者すら記録がない」曲だけ。
/// 実データでこの門が効くのは 2 行 (`ml_パルティシオン` と `sidem_pleasureforever`)。
///
/// # `全員` の位置
///
/// `全員` は名義ではなく、**5 の「名前を並べる」の短縮**。だから 1〜4 の後、
/// 名前の列挙の直前に置く。ここを先頭に上げると、ユニット単独ライブで
/// 出演者 = ユニットのメンバーになり、ユニット名が出なくなる。
pub fn setlist_performer_label(naming: &SetlistNaming) -> Option<SetlistLabel> {
    let credited = |name: &str, source: SetlistLabelSource| SetlistLabel {
        text: name.to_string(),
        source,
        // チップにするのは「顔ぶれがそのユニットを成している」行だけ。ユニット曲を
        // 一部のメンバーで歌った行までチップにすると、誰が歌ったかが消える。
        unit_names: if naming.lineup_unit_names.is_empty() {
            Vec::new()
        } else {
            vec![name.to_string()]
        },
    };
    if let Some(name) = non_empty(&naming.item_unit_name) {
        return Some(credited(name, SetlistLabelSource::ItemUnitName));
    }
    if let Some(name) = non_empty(&naming.song_unit_name) {
        return Some(credited(name, SetlistLabelSource::SongUnitName));
    }
    if let Some(label) = non_empty(&naming.singer_label) {
        // 個人名の併記はユニット名ではないのでチップにしない。
        return Some(SetlistLabel {
            text: label.to_string(),
            source: SetlistLabelSource::SingerLabel,
            unit_names: Vec::new(),
        });
    }
    if !naming.has_original_artists && !naming.lineup_unit_names.is_empty() {
        return Some(SetlistLabel {
            text: naming.lineup_unit_names.join(SETLIST_SEPARATOR),
            source: SetlistLabelSource::LineupUnits,
            unit_names: naming.lineup_unit_names.clone(),
        });
    }
    if naming.is_full_cast {
        return Some(SetlistLabel {
            text: crate::domain::setlist_lineup::FULL_CAST_LABEL.to_string(),
            source: SetlistLabelSource::FullCast,
            unit_names: Vec::new(),
        });
    }
    let text = join_names(&naming.performer_names, SETLIST_SEPARATOR);
    (!text.is_empty()).then(|| SetlistLabel {
        text,
        source: SetlistLabelSource::PerformerNames,
        unit_names: Vec::new(),
    })
}

#[cfg(test)]
mod setlist_tests {
    use super::*;

    fn naming() -> SetlistNaming {
        SetlistNaming {
            performer_names: vec!["エミリースチュアート".into(), "徳川まつり".into()],
            ..Default::default()
        }
    }

    fn label(n: &SetlistNaming) -> Option<String> {
        setlist_performer_label(n).map(|l| l.text)
    }

    /// その披露限りの名義がいちばん強い。
    #[test]
    fn item_unit_name_wins_over_everything() {
        let n = SetlistNaming {
            item_unit_name: Some("スペシャルユニット".into()),
            song_unit_name: Some("Charlotte・Charlotte".into()),
            singer_label: Some("エミリー スチュアート、徳川まつり".into()),
            lineup_unit_names: vec!["Charlotte・Charlotte".into()],
            ..naming()
        };
        assert_eq!(label(&n).as_deref(), Some("スペシャルユニット"));
    }

    /// 回帰: 顔ぶれ推論が曲の名義を上書きしていた (`THE 虎牙道` → `THE虎牙道`)。
    #[test]
    fn song_unit_name_beats_the_lineup_guess() {
        let n = SetlistNaming {
            song_unit_name: Some("THE 虎牙道".into()),
            lineup_unit_names: vec!["THE虎牙道".into()],
            has_original_artists: true,
            ..naming()
        };
        let got = setlist_performer_label(&n).expect("名義は出る");
        assert_eq!(got.text, "THE 虎牙道");
        assert_eq!(got.source, SetlistLabelSource::SongUnitName);
        // チップも曲の名義の綴りで出る (顔ぶれ側の綴りを持ち込まない)。
        assert_eq!(got.unit_names, vec!["THE 虎牙道".to_string()]);
    }

    /// 個人名併記の名義も推論より強い。チップにはしない (ユニット名ではない)。
    #[test]
    fn singer_label_beats_the_lineup_guess_and_is_not_a_chip() {
        let n = SetlistNaming {
            singer_label: Some("天道輝、若里春名、水嶋咲".into()),
            lineup_unit_names: vec!["DRAMATIC STARS".into()],
            has_original_artists: true,
            ..naming()
        };
        let got = setlist_performer_label(&n).expect("名義は出る");
        assert_eq!(got.text, "天道輝、若里春名、水嶋咲");
        assert!(got.unit_names.is_empty());
    }

    /// 回帰の実例: パルティシオンは Charlotte・Charlotte の曲ではない。
    /// 名義が空でも、原唱者が分かっているなら推論せず名前を並べる。
    #[test]
    fn a_song_with_known_originals_never_borrows_a_unit_name() {
        let n = SetlistNaming {
            lineup_unit_names: vec!["Charlotte・Charlotte".into()],
            has_original_artists: true,
            ..naming()
        };
        let got = setlist_performer_label(&n).expect("名前は出る");
        assert_eq!(got.text, "エミリースチュアート／徳川まつり");
        assert_eq!(got.source, SetlistLabelSource::PerformerNames);
        assert!(got.unit_names.is_empty(), "推論のユニット名をチップにしない");
    }

    /// 原唱者すら記録が無い曲では、顔ぶれ推論が最後の手がかりになる。
    #[test]
    fn the_lineup_guess_survives_where_nothing_else_is_known() {
        let n = SetlistNaming {
            lineup_unit_names: vec!["#ヴイアラ".into()],
            has_original_artists: false,
            ..naming()
        };
        let got = setlist_performer_label(&n).expect("推論で出る");
        assert_eq!(got.text, "#ヴイアラ");
        assert_eq!(got.source, SetlistLabelSource::LineupUnits);
        assert_eq!(got.unit_names, vec!["#ヴイアラ".to_string()]);
    }

    /// 合同は 2〜3 ユニットの和集合。区切りは公式のセトリ画像に合わせた全角スラッシュ。
    #[test]
    fn joint_lineups_join_with_the_full_width_slash() {
        let n = SetlistNaming {
            lineup_unit_names: vec!["Legenders".into(), "C.FIRST".into()],
            ..naming()
        };
        assert_eq!(label(&n).as_deref(), Some("Legenders／C.FIRST"));
    }

    /// `全員` は名義ではなく名前の列挙の短縮なので、名義より後・列挙より前。
    #[test]
    fn full_cast_stands_in_for_the_name_list_only() {
        let all = SetlistNaming { is_full_cast: true, ..naming() };
        assert_eq!(label(&all).as_deref(), Some("全員"));
        // ユニット単独ライブ (出演者 = ユニットのメンバー) でユニット名が消えない。
        let unit_show = SetlistNaming {
            song_unit_name: Some("アンティーカ".into()),
            lineup_unit_names: vec!["アンティーカ".into()],
            is_full_cast: true,
            has_original_artists: true,
            ..naming()
        };
        assert_eq!(label(&unit_show).as_deref(), Some("アンティーカ"));
    }

    /// DB には `NULL` と `''` が混ざっている。空文字で止めない。
    #[test]
    fn blank_credits_fall_through() {
        let n = SetlistNaming {
            item_unit_name: Some("".into()),
            song_unit_name: Some("   ".into()),
            singer_label: Some("".into()),
            has_original_artists: true,
            ..naming()
        };
        assert_eq!(label(&n).as_deref(), Some("エミリースチュアート／徳川まつり"));
    }

    /// 歌唱者が 1 人も分からない行は、行ごと出さない側に倒す。
    #[test]
    fn nothing_to_show_is_none() {
        assert_eq!(setlist_performer_label(&SetlistNaming::default()), None);
    }
}
