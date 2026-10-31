//! 歌詞の 1 行を「画面に置く字のひと続き」に割る (Web 出面用)。
//!
//! アプリ (iOS/Android) は [`super::lyric_sync`] の部品 (`ruby_spans` / `aside_spans` /
//! `part_segments` / `call_echoes_line`) を自分で組み合わせて描いている。Web の歌詞は押されたときに
//! 1 曲ぶんだけ取りに行くので静的な JSON に落とせず、ブラウザの wasm がこの関数を呼ぶ。
//! 組み合わせ方をここに 1 つにまとめ、TS には「ひと続きを要素に置く」ことだけを残す。
//!
//! 規則はアプリと同じ:
//! - 振り仮名 (`親字《よみ》` / `｜親字《よみ》`) は記号を外し、読みを親字の上に乗せる。
//! - 括弧で書いた脇の字 (被せ・コーラス) は一段小さく薄く出す (`aside`)。
//! - 歌う人 (パート分け) は原唱者 (`cast`) にいる人だけ。`cast` が空 (ソロ曲など
//!   [`super::lyric_sync::parts_applicable`] が偽) なら出さない。
//! - 歌詞と同じ文字のコール ([`super::lyric_sync::call_echoes_line`]) は行として並べず、歌詞の側に印を付ける。

use super::lyric_sync::{aside_spans, call_echoes_line, part_segments, ruby_spans, LyricPartBreak};

/// 行に掛かるコール 1 つ (位置は行の本文のスカラー位置、`end` は排他)。
#[derive(Clone, Debug, PartialEq, Eq, serde::Deserialize)]
pub struct LyricDisplayCall {
    pub start: u32,
    pub end: u32,
    pub text: String,
    /// `over` (同時) / `after` (追っかけ)。無ければ `after` (旧サーバは返さない。アプリと同じ)。
    #[serde(default)]
    pub timing: Option<String>,
}

/// 画面に置く字のひと続き。`start..end` は元の本文のスカラー位置で、行の全体を隙間なく敷き詰める
/// (振り仮名の記号・読みも、それを持つひと続きの範囲に入る)。
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LyricRun {
    pub start: u32,
    pub end: u32,
    /// 出す字 (振り仮名の記号と読みは外してある)。
    pub text: String,
    /// 親字の上に乗せる読み。このひと続きが振り仮名の親字のときだけ。
    pub ruby: Option<String>,
    /// 括弧で書いた脇の字 (被せ・コーラス)。一段小さく薄く出す。
    pub aside: bool,
    /// この字を歌う人 (原唱者の id、原唱者の並び)。空なら色を付けない。
    pub singers: Vec<String>,
}

/// 1 行ぶんの置き方。
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LyricLineDisplay {
    pub runs: Vec<LyricRun>,
    /// コールごと (入力と同じ順)。true は歌詞と同じ文字 = 行に並べず、歌詞のその部分を濃く敷く。
    pub echoes: Vec<bool>,
    /// 行の下に添える歌う人の名前のまとまり (行の途中で歌う人が変わるところで分ける)。
    /// id のまま (名前は出面が原唱者の表から引く)。歌う人がいなければ空。
    pub part_groups: Vec<Vec<String>>,
}

/// 1 行を置き方に割る。`cut_points` は呼び出し側が要素の境目に使う位置 (コールの範囲の端など)。
/// 振り仮名の親字の途中に来る境目は無視する (親字と読みは 1 塊でないと組めない)。
pub fn lyric_line_display(
    text: &str,
    singers: &[String],
    breaks: &[LyricPartBreak],
    calls: &[LyricDisplayCall],
    cast: &[String],
) -> LyricLineDisplay {
    let chars: Vec<char> = text.chars().collect();
    let n = chars.len();

    // 字ごとの役割。ruby_group[k] は振り仮名の添字 (記号・読み・親字のどれでも)。
    let rubies = ruby_spans(text);
    let mut ruby_group: Vec<Option<usize>> = vec![None; n];
    let mut hidden = vec![false; n];
    for (index, r) in rubies.iter().enumerate() {
        let from = r.marker.unwrap_or(r.base_start) as usize;
        for g in ruby_group.iter_mut().take((r.close as usize).min(n)).skip(from) {
            *g = Some(index);
        }
        for h in hidden.iter_mut().take((r.close as usize).min(n)).skip(r.open as usize) {
            *h = true;
        }
        if let Some(m) = r.marker {
            if (m as usize) < n {
                hidden[m as usize] = true;
            }
        }
    }
    let mut aside = vec![false; n];
    for span in aside_spans(text) {
        for a in aside.iter_mut().take((span.end as usize).min(n)).skip(span.start as usize) {
            *a = true;
        }
    }
    // 歌う人。原唱者にいない人は落とす (曲の編成に無い人の色を作らない)。
    let in_cast = |ids: &[String]| -> Vec<String> {
        let mut out: Vec<String> = cast.iter().filter(|c| ids.contains(c)).cloned().collect();
        out.dedup();
        out
    };
    let mut who: Vec<Vec<String>> = vec![Vec::new(); n];
    let segments = if cast.is_empty() { Vec::new() } else { part_segments(n as u32, singers, breaks) };
    for seg in &segments {
        let ids = in_cast(&seg.singers);
        for w in who.iter_mut().take((seg.end as usize).min(n)).skip(seg.start as usize) {
            *w = ids.clone();
        }
    }
    let mut cuts = vec![false; n + 1];
    for c in calls {
        for p in [c.start as usize, c.end as usize] {
            if p <= n {
                cuts[p] = true;
            }
        }
    }

    let mut runs: Vec<LyricRun> = Vec::new();
    let mut k = 0usize;
    while k < n {
        let start = k;
        if let Some(g) = ruby_group[k] {
            // 振り仮名は 1 塊 (記号・読みを含む)。色と脇の字は親字の頭で決める。
            while k < n && ruby_group[k] == Some(g) {
                k += 1;
            }
            let r = &rubies[g];
            let base: String = chars[r.base_start as usize..r.base_end as usize].iter().collect();
            let reading: String = chars[r.open as usize + 1..r.close as usize - 1].iter().collect();
            let head = r.base_start as usize;
            runs.push(LyricRun {
                start: start as u32,
                end: k as u32,
                text: base,
                ruby: Some(reading),
                aside: aside[head],
                singers: who[head].clone(),
            });
            continue;
        }
        k += 1;
        while k < n && ruby_group[k].is_none() && !cuts[k] && aside[k] == aside[start] && who[k] == who[start] {
            k += 1;
        }
        let shown: String = (start..k).filter(|&i| !hidden[i]).map(|i| chars[i]).collect();
        runs.push(LyricRun {
            start: start as u32,
            end: k as u32,
            text: shown,
            ruby: None,
            aside: aside[start],
            singers: who[start].clone(),
        });
    }

    let echoes = calls
        .iter()
        .map(|c| {
            c.end > c.start
                && call_echoes_line(text, c.start, c.end, &c.text, c.timing.as_deref().unwrap_or("after"))
        })
        .collect();

    // 名前は「行まるごと 1 組」、途中で変わる行はひと続きごと (アプリの LyricPartCast.groups と同じ)。
    let part_groups: Vec<Vec<String>> = if cast.is_empty() {
        Vec::new()
    } else if breaks.is_empty() {
        vec![in_cast(singers)]
    } else {
        segments.iter().map(|s| in_cast(&s.singers)).collect()
    };
    let part_groups = if part_groups.iter().all(Vec::is_empty) { Vec::new() } else { part_groups };

    LyricLineDisplay { runs, echoes, part_groups }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    fn call(start: u32, end: u32, text: &str, timing: &str) -> LyricDisplayCall {
        LyricDisplayCall { start, end, text: text.into(), timing: Some(timing.into()) }
    }

    #[test]
    fn ruby_is_one_run_with_reading_and_markers_hidden() {
        let d = lyric_line_display("走る五輪咲《ごりん》駆動", &[], &[], &[], &[]);
        let texts: Vec<_> = d.runs.iter().map(|r| (r.text.as_str(), r.ruby.as_deref())).collect();
        assert_eq!(texts, vec![("走る", None), ("五輪咲", Some("ごりん")), ("駆動", None)]);
        // 範囲は本文を隙間なく敷き詰める。
        assert_eq!(d.runs[1].start, 2);
        assert_eq!(d.runs[1].end, 10);
        assert_eq!(d.runs[2].start, 10);
    }

    #[test]
    fn marker_ruby_hides_bar() {
        let d = lyric_line_display("あの｜ダミー《だみ》だ", &[], &[], &[], &[]);
        let texts: Vec<_> = d.runs.iter().map(|r| (r.text.as_str(), r.ruby.as_deref())).collect();
        assert_eq!(texts, vec![("あの", None), ("ダミー", Some("だみ")), ("だ", None)]);
        assert_eq!(d.runs[1].start, 2);
    }

    #[test]
    fn aside_runs_are_split() {
        let d = lyric_line_display("夢を（夢を）", &[], &[], &[], &[]);
        let runs: Vec<_> = d.runs.iter().map(|r| (r.text.as_str(), r.aside)).collect();
        assert_eq!(runs, vec![("夢を", false), ("（夢を）", true)]);
    }

    #[test]
    fn parts_only_for_cast_and_split_at_breaks() {
        let breaks = vec![LyricPartBreak { at: 2, singers: ids(&["b", "x"]) }];
        let d = lyric_line_display("あいうえ", &ids(&["a"]), &breaks, &[], &ids(&["a", "b"]));
        let runs: Vec<_> = d.runs.iter().map(|r| (r.text.as_str(), r.singers.clone())).collect();
        assert_eq!(runs, vec![("あい", ids(&["a"])), ("うえ", ids(&["b"]))]);
        assert_eq!(d.part_groups, vec![ids(&["a"]), ids(&["b"])]);
    }

    #[test]
    fn no_parts_without_cast() {
        let d = lyric_line_display("あいうえ", &ids(&["a"]), &[], &[], &[]);
        assert!(d.runs.iter().all(|r| r.singers.is_empty()));
        assert!(d.part_groups.is_empty());
    }

    #[test]
    fn calls_cut_runs_and_echoes_are_flagged() {
        let calls = vec![call(2, 4, "ハイ", "over"), call(4, 4, "オイ", "after"), call(0, 2, "ゆめ", "over")];
        let d = lyric_line_display("夢をはい", &[], &[], &calls, &[]);
        let texts: Vec<_> = d.runs.iter().map(|r| r.text.as_str()).collect();
        assert_eq!(texts, vec!["夢を", "はい"]);
        assert_eq!(d.echoes, vec![true, false, false]);
    }

    #[test]
    fn cut_inside_ruby_is_ignored() {
        let calls = vec![call(1, 2, "x", "over")];
        let d = lyric_line_display("五輪《ごりん》", &[], &[], &calls, &[]);
        assert_eq!(d.runs.len(), 1);
        assert_eq!(d.runs[0].ruby.as_deref(), Some("ごりん"));
    }
}
