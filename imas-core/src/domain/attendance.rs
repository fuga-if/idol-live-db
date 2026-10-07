//! 参加形態 (現地 / 配信 / LV) の保存値の読み書き。純粋ロジック。
//!
//! 1 公演に**複数の形態**を付けられる (現地で見て、あとから配信のアーカイブも買った)。
//! 保存先は `user_marks` の attended 行の `text_value` で、形態の保存値を語彙の順に
//! `,` でつないで持つ (`live,stream`)。
//!
//! # 既存データはそのまま読める
//!
//! 複数を持てるようにする前の行は `live` / `stream` / `live_viewing` の 1 語か NULL で、
//! これは「1 つだけ付いている」の表記そのもの。書き換える移行は要らない。
//! NULL (形態を選べるようにする前のマーク) と空は**現地**として読む
//! ([`crate::domain::collection_gap`] の回収・券の形態と同じ約束)。
//!
//! # ここに置くもの
//!
//! 読み (`text_value` → 形態の並び)・書き (並び → `text_value`)・付け外し・SQL の条件。
//! 区切り文字や並び順を各 OS に書くと、片方だけ並びが変わって同じ記録が別の文字列になる。

use crate::domain::vocabulary::ATTENDANCE_TYPES;

/// 形態を持たない古いマークの読み方。**現地**。
pub const LOCAL_ATTENDANCE: &str = "live";

/// 保存値の区切り。
const SEPARATOR: char = ',';

/// `text_value` → 付いている形態 (語彙の順・重複なし)。
///
/// NULL・空・知らない語だけのときは `["live"]` (現地)。参加マークが付いている行に対して
/// 呼ぶ前提で、参加の有無 (`bool_value`) はここでは見ない。
pub fn attendance_types(text_value: Option<&str>) -> Vec<String> {
    let tokens: Vec<&str> = text_value
        .unwrap_or("")
        .split(SEPARATOR)
        .map(str::trim)
        .collect();
    let known: Vec<String> = ATTENDANCE_TYPES
        .iter()
        .filter(|t| tokens.contains(&t.value))
        .map(|t| t.value.to_string())
        .collect();
    if known.is_empty() {
        vec![LOCAL_ATTENDANCE.to_string()]
    } else {
        known
    }
}

/// 形態の並び → `text_value`。語彙の順に並べ直し、知らない語と重複は落とす。
/// 1 つも残らなければ `None` (= 参加の取り消し)。
pub fn attendance_text(types: &[String]) -> Option<String> {
    let kept: Vec<&str> = ATTENDANCE_TYPES
        .iter()
        .map(|t| t.value)
        .filter(|v| types.iter().any(|t| t == v))
        .collect();
    (!kept.is_empty()).then(|| kept.join(&SEPARATOR.to_string()))
}

/// 1 つの形態を付ける / 外したあとの `text_value`。`None` なら参加マークごと外す。
///
/// - `attended`: いま参加マークが付いているか。付いていなければ形態は空から始める
///   (外したマークに残った古い `text_value` を拾わない)。
/// - `on`: 付けるなら真、外すなら偽。
pub fn attendance_set_type(
    current: Option<&str>,
    attended: bool,
    attendance_type: &str,
    on: bool,
) -> Option<String> {
    let mut types = if attended { attendance_types(current) } else { Vec::new() };
    types.retain(|t| t != attendance_type);
    if on {
        types.push(attendance_type.to_string());
    }
    attendance_text(&types)
}

/// その行に `attendance_type` が付いているか (読み方は [`attendance_types`])。
pub fn has_attendance_type(text_value: Option<&str>, attendance_type: &str) -> bool {
    attendance_types(text_value).iter().any(|t| t == attendance_type)
}

/// `text_value` 列に対して「`types` のどれかが付いている」を表す SQL 条件。
/// `types` が空なら形態を問わない (`1=1`)。
///
/// NULL・空は現地として読むので、`live` が入っているときだけそれらも拾う。
/// 値は語彙の固定語に限る (知らない語は落とす。SQL に素通しにしない)。
pub fn attendance_sql_condition(column: &str, types: &[String]) -> String {
    let kept: Vec<&str> = ATTENDANCE_TYPES
        .iter()
        .map(|t| t.value)
        .filter(|v| types.iter().any(|t| t == v))
        .collect();
    if types.is_empty() {
        return "1=1".to_string();
    }
    if kept.is_empty() {
        return "1=0".to_string();
    }
    let mut parts: Vec<String> = Vec::new();
    if kept.contains(&LOCAL_ATTENDANCE) {
        parts.push(format!("{column} IS NULL"));
        parts.push(format!("TRIM({column}) = ''"));
    }
    for v in kept {
        parts.push(format!("(',' || REPLACE({column}, ' ', '') || ',') LIKE '%,{v},%'"));
    }
    format!("({})", parts.join(" OR "))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn 複数を持てるようにする前の値はそのまま読める() {
        assert_eq!(attendance_types(None), v(&["live"]));
        assert_eq!(attendance_types(Some("")), v(&["live"]));
        assert_eq!(attendance_types(Some("live")), v(&["live"]));
        assert_eq!(attendance_types(Some("stream")), v(&["stream"]));
        assert_eq!(attendance_types(Some("live_viewing")), v(&["live_viewing"]));
        assert_eq!(attendance_types(Some("unknown")), v(&["live"]), "知らない語だけなら現地");
    }

    #[test]
    fn 並びは語彙の順で重複しない() {
        assert_eq!(attendance_types(Some("stream,live")), v(&["live", "stream"]));
        assert_eq!(attendance_types(Some("live, stream,live,x")), v(&["live", "stream"]));
        assert_eq!(attendance_text(&v(&["live_viewing", "live", "live"])), Some("live,live_viewing".into()));
        assert_eq!(attendance_text(&v(&["x"])), None);
        assert_eq!(attendance_text(&[]), None);
    }

    #[test]
    fn 付け外し() {
        // 付いていない公演に配信を付ける。
        assert_eq!(attendance_set_type(None, false, "stream", true), Some("stream".into()));
        // 外したマークに残った古い値は拾わない。
        assert_eq!(attendance_set_type(Some("live"), false, "stream", true), Some("stream".into()));
        // 現地 (旧データの NULL) に配信を足す。
        assert_eq!(attendance_set_type(None, true, "stream", true), Some("live,stream".into()));
        // 2 つから 1 つ外す。
        assert_eq!(attendance_set_type(Some("live,stream"), true, "live", false), Some("stream".into()));
        // 最後の 1 つを外すと参加ごと外れる。
        assert_eq!(attendance_set_type(Some("stream"), true, "stream", false), None);
        // 付いているものをもう一度付けても変わらない。
        assert_eq!(attendance_set_type(Some("live"), true, "live", true), Some("live".into()));
    }

    #[test]
    fn sql_条件は読み方と同じ行を選ぶ() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch("CREATE TABLE m (id INTEGER, text_value TEXT);").unwrap();
        let rows: [Option<&str>; 7] =
            [None, Some(""), Some("live"), Some("stream"), Some("live,stream"), Some("live_viewing"), Some("stream,live_viewing")];
        for (i, t) in rows.iter().enumerate() {
            conn.execute("INSERT INTO m VALUES (?1, ?2)", rusqlite::params![i as i64, t]).unwrap();
        }
        for types in [v(&["live"]), v(&["stream"]), v(&["live", "live_viewing"]), v(&[])] {
            let sql = format!("SELECT id FROM m WHERE {} ORDER BY id", attendance_sql_condition("text_value", &types));
            let mut stmt = conn.prepare(&sql).unwrap();
            let got: Vec<i64> = stmt.query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
            let expected: Vec<i64> = rows
                .iter()
                .enumerate()
                .filter(|(_, t)| types.is_empty() || types.iter().any(|ty| has_attendance_type(**t, ty)))
                .map(|(i, _)| i as i64)
                .collect();
            assert_eq!(got, expected, "{types:?}");
        }
        assert_eq!(attendance_sql_condition("text_value", &v(&["x"])), "1=0");
    }
}
