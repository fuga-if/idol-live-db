//! 引数の**取りうる値**と、語彙外を突き返す作法。
//!
//! 「語彙外の値は黙って 0 件にしない」は ARCHITECTURE-mcp §4 の規約で、ツールごとの
//! 都合ではない。以前はこの一式が `browse.rs` の私物として置かれていて、ツールが
//! 増えるたびに `pub(super)` で穴を開けるか、同じ形の `BTreeSet` 集めを書き直すかに
//! なっていた (実際に `cast_role` の語彙作りが `distinct` の写経になっていた)。
//!
//! **語彙はデータそのものから作る。**定数で持つと、ブランドや属性が増えた日に
//! 黙って古いままになる。

use super::ToolError;
use crate::domain::snapshot::{Idol, Snapshot};
use std::collections::BTreeSet;

/// 空でない値を重複なく昇順で。
pub fn distinct<'a>(values: impl Iterator<Item = Option<&'a str>>) -> Vec<String> {
    let set: BTreeSet<&str> = values.flatten().filter(|v| !v.is_empty()).collect();
    set.into_iter().map(str::to_string).collect()
}

/// ブランド id。並びは公式順 (前計算済み)。
pub fn brand_vocab(snap: &Snapshot) -> Vec<String> {
    snap.brand_order.iter().map(|&i| snap.brands[i as usize].id.clone()).collect()
}

pub fn song_type_vocab(snap: &Snapshot) -> Vec<String> {
    distinct(snap.songs.iter().map(|s| s.song_type.as_deref()))
}

pub fn event_kind_vocab(snap: &Snapshot) -> Vec<String> {
    distinct(snap.events.iter().map(|e| Some(e.kind.as_str())))
}

/// 催しの種別 (`anniversary` / `orchestra` / `external_event` / `birthday` /
/// `release_event` / `broadcast` / `live`)。
/// 意味は docs/DATA_PIPELINE.md 「events の種別 (event_type)」。
///
/// 未分類のイベントは空文字なので `distinct` が落とす。つまり**語彙に「未分類」は
/// 出ない**: 絞り込みの選択肢として出しても 1 件も意味のある答えにならないため。
pub fn event_type_vocab(snap: &Snapshot) -> Vec<String> {
    distinct(snap.events.iter().map(|e| Some(e.event_type.as_str())))
}

/// 出演の役割 (`member` / `lead` …)。`show_cast.cast_role` の実在値。
pub fn cast_role_vocab(snap: &Snapshot) -> Vec<String> {
    distinct(snap.cast_by_show.iter().flat_map(|links| {
        links.iter().map(|l| Some(l.cast_role.as_str()))
    }))
}

/// アイドルの列そのものが語彙。`idols_by_constellation` 等が完全一致で引くので、
/// **その列の実在値**が取りうる値のすべて。
pub fn idol_vocab(snap: &Snapshot, column: fn(&Idol) -> Option<&str>) -> Vec<String> {
    distinct(snap.idols.iter().map(column))
}

/// 語彙に無い値を、候補つきで突き返す。
pub fn checked(arg: &str, value: String, allowed: &[String]) -> Result<String, ToolError> {
    if allowed.contains(&value) {
        return Ok(value);
    }
    Err(ToolError::BadArgs(format!("{arg} に「{value}」は無い。取りうる値: {}", sample(allowed))))
}

/// 候補の並べ方。全部並べると CD シリーズのように 100 件を超えるものがあるので頭だけ。
pub fn sample(allowed: &[String]) -> String {
    const SHOWN: usize = 40;
    let head = allowed.iter().take(SHOWN).cloned().collect::<Vec<_>>().join(" / ");
    if allowed.len() > SHOWN {
        format!("{head} … 他 {} 件", allowed.len() - SHOWN)
    } else if head.is_empty() {
        "(該当なし)".to_string()
    } else {
        head
    }
}

/// `YYYY` / `YYYY-MM` / `YYYY-MM-DD` のいずれか。
/// 粗い指定を許すのは「2020 年以降」を 1 語で書けるようにするため。
pub fn checked_date_bound(arg: &str, value: String) -> Result<String, ToolError> {
    let ok = matches!(value.len(), 4 | 7 | 10)
        && value
            .char_indices()
            .all(|(i, c)| if i == 4 || i == 7 { c == '-' } else { c.is_ascii_digit() });
    if ok {
        Ok(value)
    } else {
        Err(ToolError::BadArgs(format!(
            "{arg} は YYYY / YYYY-MM / YYYY-MM-DD で書く (与えられた値: {value})"
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    #[test]
    fn 語彙は実データから出る() {
        let s = bundle_snapshot();
        assert!(brand_vocab(s).contains(&"ml".to_string()));
        assert!(event_kind_vocab(s).contains(&"live".to_string()));
        // 種別は定数表でなく実データから。未分類 (空文字) は語彙に出ない。
        let types = event_type_vocab(s);
        assert!(!types.iter().any(String::is_empty), "{types:?}");
        // 役割は member が必ずあり、主演が入っている DB なら lead も。
        let roles = cast_role_vocab(s);
        assert!(roles.contains(&"member".to_string()), "{roles:?}");
        assert!(roles.contains(&"lead".to_string()), "{roles:?}");
        // 昇順・重複なし。
        let mut sorted = roles.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(roles, sorted);
    }

    #[test]
    fn 語彙外は候補つきで突き返す() {
        let allowed = vec!["a".to_string(), "b".to_string()];
        assert_eq!(checked("x", "a".into(), &allowed).unwrap(), "a");
        let err = checked("x", "z".into(), &allowed).unwrap_err();
        assert!(matches!(err, ToolError::BadArgs(m) if m.contains("a / b")));
        // 候補が空でも文面が壊れない。
        assert!(sample(&[]).contains("該当なし"));
    }
}
