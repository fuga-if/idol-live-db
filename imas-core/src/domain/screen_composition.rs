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

    /// 値が無い項目は行ごと出さない (空欄の行を並べない)。
    #[test]
    fn absent_values_produce_no_row() {
        let rows = idol_profile_rows(&IdolProfileInput {
            name_kana: Some("あ".into()),
            ..Default::default()
        });
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].label, "よみ");
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

    /// 月が分からない誕生日 (「??月3日」等) は押せない行にする。
    #[test]
    fn birthday_without_month_is_not_tappable() {
        let rows = idol_profile_rows(&IdolProfileInput {
            birthday_display: Some("3日".into()),
            birth_month: None,
            ..Default::default()
        });
        assert_eq!(rows[0].action, RowAction::None);
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

    #[test]
    fn monospaced_and_swatch_styles_are_assigned() {
        let rows = idol_profile_rows(&full());
        let by = |l: &str| rows.iter().find(|r| r.label == l).unwrap().style;
        assert_eq!(by("ローマ字"), RowStyle::Monospaced);
        assert_eq!(by("スリーサイズ"), RowStyle::Monospaced);
        assert_eq!(by("カラー"), RowStyle::ColorSwatch);
        assert_eq!(by("よみ"), RowStyle::Plain);
    }

    #[test]
    fn color_row_can_be_copied() {
        let rows = idol_profile_rows(&full());
        let c = rows.iter().find(|r| r.label == "カラー").unwrap();
        assert_eq!(c.action, RowAction::CopyValue);
        assert_eq!(c.value, "#EE7F9C");
    }

    /// 何も無ければ行ゼロ (画面側は空状態を出せばよい)。
    #[test]
    fn nothing_in_nothing_out() {
        assert!(idol_profile_rows(&IdolProfileInput::default()).is_empty());
    }

    #[test]
    fn results_are_deterministic() {
        assert_eq!(idol_profile_rows(&full()), idol_profile_rows(&full()));
    }
}
