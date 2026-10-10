//! データを入れた人への手応え (公演の閲覧数) と、公演ページの奥付 (クレジット) の規則。
//!
//! 閲覧数はサーバが (公演, JST の週) の人数だけを積み、端末 ID の行を持たない。
//! そのため「同じ端末が同じ週に同じ公演を何度開いても 1 回」の畳み込みは端末側で行う。
//! その判定 (週の切り替わり・送るか・送ったあと何を覚えるか) をここに置く。
//! 週の数え方はサーバ (imas-live-api/src/contribution_feedback.ts の jstWeekStart) と同じ
//! JST の月曜始まり。ずれても境界の 1 回が多いか少ないかになるだけ。

use chrono::{DateTime, Datelike, Duration};

use super::jst_day::jst;

/// 1 週に覚えておく公演の数の上限 (これを超えたら古い方から忘れる)。
pub const MAX_REPORTED_SHOWS_PER_WEEK: usize = 300;

/// JST の月曜始まりの週の初日 (`"yyyy-MM-dd"`)。
pub fn jst_week_start(now_epoch_seconds: i64) -> String {
    let utc = DateTime::from_timestamp(now_epoch_seconds, 0).unwrap_or(DateTime::UNIX_EPOCH);
    let local = utc.with_timezone(&jst()).date_naive();
    let back = local.weekday().num_days_from_monday() as i64;
    (local - Duration::days(back)).format("%Y-%m-%d").to_string()
}

/// 公演ページを開いたときに、閲覧を送るかの判定。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ShowViewDecision {
    /// 送るか (今週まだ送っていない公演)。
    pub report: bool,
    /// 今の週 (`"yyyy-MM-dd"`)。端末はこれを保存する。
    pub week: String,
    /// 送るなら送り終えたあとに、送らないならそのまま保存する「今週送った公演」。
    pub reported_after: Vec<String>,
}

/// 開いた公演の閲覧を今送るか。週が変われば覚えていた分を捨てる。
///
/// 送信に失敗したら `reported_after` を保存しない (次に開いたときに送り直す)。
pub fn show_view_decision(
    stored_week: &str,
    reported: &[String],
    show_id: &str,
    now_epoch_seconds: i64,
) -> ShowViewDecision {
    let week = jst_week_start(now_epoch_seconds);
    let mut current: Vec<String> = if stored_week == week { reported.to_vec() } else { Vec::new() };
    if show_id.is_empty() || current.iter().any(|s| s == show_id) {
        return ShowViewDecision { report: false, week, reported_after: current };
    }
    current.push(show_id.to_string());
    if current.len() > MAX_REPORTED_SHOWS_PER_WEEK {
        let drop = current.len() - MAX_REPORTED_SHOWS_PER_WEEK;
        current.drain(..drop);
    }
    ShowViewDecision { report: true, week, reported_after: current }
}

/// 奥付の役割。並びはこの順 (セトリ → 歌唱者)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ShowCreditRole {
    /// セトリ (曲順) を入れた人。
    Setlist,
    /// 歌唱者 (誰が歌ったか) を入れた人。
    Performers,
    /// 曲の歌詞を投稿した人 (歌詞の末尾の奥付)。
    Lyrics,
}

/// サーバの 1 役割ぶん (GET /shows/:id/credits の setlist / performers)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ShowCreditInput {
    /// 名前を載せてよい人の表示名 (最初に入れた順)。
    pub names: Vec<String>,
    /// この役割に関わった人の総数 (名前を出さない人も含む)。
    pub total: u32,
}

/// 奥付の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ShowCreditLine {
    pub role: ShowCreditRole,
    /// 載せる名前 (重複なし・空の名前なし・最初に入れた順)。
    pub names: Vec<String>,
    /// 名前を出さない人の数 (「ほか N 人」)。
    pub unnamed_count: u32,
}

/// 奥付の行。誰も関わっていない役割の行は出さない。
pub fn show_credit_lines(setlist: &ShowCreditInput, performers: &ShowCreditInput) -> Vec<ShowCreditLine> {
    [(ShowCreditRole::Setlist, setlist), (ShowCreditRole::Performers, performers)]
        .into_iter()
        .filter_map(|(role, input)| credit_line(role, input))
        .collect()
}

/// 曲の歌詞の奥付 (歌詞入力)。投稿で公開された人がいなければ None。
pub fn lyrics_credit_line(input: &ShowCreditInput) -> Option<ShowCreditLine> {
    credit_line(ShowCreditRole::Lyrics, input)
}

fn credit_line(role: ShowCreditRole, input: &ShowCreditInput) -> Option<ShowCreditLine> {
    if input.total == 0 {
        return None;
    }
    let mut names: Vec<String> = Vec::new();
    for n in &input.names {
        let n = n.trim();
        if !n.is_empty() && !names.iter().any(|x| x == n) {
            names.push(n.to_string());
        }
    }
    let unnamed_count = input.total.saturating_sub(names.len() as u32);
    Some(ShowCreditLine { role, names, unnamed_count })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 2026-10-04 (日) 23:59:59 JST
    const SUN_LATE: i64 = 1_791_125_999;
    /// 2026-10-05 (月) 00:00:00 JST
    const MON_START: i64 = 1_791_126_000;

    #[test]
    fn week_starts_on_monday_jst() {
        assert_eq!(jst_week_start(SUN_LATE), "2026-09-28");
        assert_eq!(jst_week_start(MON_START), "2026-10-05");
        assert_eq!(jst_week_start(MON_START + 6 * 86_400 + 86_399), "2026-10-05");
    }

    #[test]
    fn reports_once_per_show_per_week() {
        let first = show_view_decision("", &[], "sh_1", MON_START);
        assert!(first.report);
        assert_eq!(first.week, "2026-10-05");
        assert_eq!(first.reported_after, vec!["sh_1".to_string()]);

        let again = show_view_decision(&first.week, &first.reported_after, "sh_1", MON_START + 3600);
        assert!(!again.report);
        assert_eq!(again.reported_after, first.reported_after);

        let other = show_view_decision(&first.week, &first.reported_after, "sh_2", MON_START + 3600);
        assert!(other.report);
        assert_eq!(other.reported_after, vec!["sh_1".to_string(), "sh_2".to_string()]);
    }

    #[test]
    fn new_week_forgets_last_week() {
        let next = show_view_decision("2026-09-28", &["sh_1".to_string()], "sh_1", MON_START);
        assert!(next.report);
        assert_eq!(next.reported_after, vec!["sh_1".to_string()]);
        let stay = show_view_decision("2026-09-28", &["sh_1".to_string()], "", MON_START);
        assert!(!stay.report);
        assert!(stay.reported_after.is_empty());
    }

    #[test]
    fn remembered_shows_are_capped() {
        let many: Vec<String> = (0..MAX_REPORTED_SHOWS_PER_WEEK).map(|i| format!("sh_{i}")).collect();
        let d = show_view_decision("2026-10-05", &many, "sh_new", MON_START);
        assert!(d.report);
        assert_eq!(d.reported_after.len(), MAX_REPORTED_SHOWS_PER_WEEK);
        assert_eq!(d.reported_after.first().map(String::as_str), Some("sh_1"));
        assert_eq!(d.reported_after.last().map(String::as_str), Some("sh_new"));
    }

    #[test]
    fn credit_lines_keep_order_and_count_unnamed() {
        let lines = show_credit_lines(
            &ShowCreditInput { names: vec!["A".into(), " A ".into(), "".into(), "B".into()], total: 4 },
            &ShowCreditInput { names: vec![], total: 2 },
        );
        assert_eq!(
            lines,
            vec![
                ShowCreditLine { role: ShowCreditRole::Setlist, names: vec!["A".into(), "B".into()], unnamed_count: 2 },
                ShowCreditLine { role: ShowCreditRole::Performers, names: vec![], unnamed_count: 2 },
            ]
        );
    }

    #[test]
    fn lyrics_credit_is_one_line_or_none() {
        assert_eq!(lyrics_credit_line(&ShowCreditInput { names: vec![], total: 0 }), None);
        assert_eq!(
            lyrics_credit_line(&ShowCreditInput { names: vec!["A".into()], total: 3 }),
            Some(ShowCreditLine { role: ShowCreditRole::Lyrics, names: vec!["A".into()], unnamed_count: 2 })
        );
    }

    #[test]
    fn credit_lines_skip_roles_nobody_did() {
        let lines = show_credit_lines(
            &ShowCreditInput { names: vec![], total: 0 },
            &ShowCreditInput { names: vec!["C".into()], total: 1 },
        );
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].role, ShowCreditRole::Performers);
        assert_eq!(lines[0].unnamed_count, 0);
    }
}
