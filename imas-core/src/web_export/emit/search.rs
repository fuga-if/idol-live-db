//! 検索索引 (`search/*.json`) と、畳み込みパリティ (`parity/fold.json`)。
//!
//! ## 配るのは「コアが組んだ索引の写し」
//!
//! `Snapshot` が読み込み時に組んだ [`TextSearchIndex`] の畳み済みフィールドを、
//! そのまま JSON に載せる。web が `title` / `title_kana` を選び直したり畳み直したり
//! しないので、**どのフィールドが検索対象かという判断がコアの外に漏れない**。
//!
//! ブラウザ側の照合は `row.f.includes(fold(query))` の 1 行だけ。それが
//! `TextSearchIndex::matches` と等価になるのは、フィールドを `U+0001` で区切って
//! あるから (検索語にこの文字は入らないので、境界をまたぐ偽陽性が起きない)。
//!
//! [`TextSearchIndex`]: crate::domain::text_search_index::TextSearchIndex

use super::context::Ctx;
use crate::domain::text_search_index::{prepare_needle, TextSearchIndex};
use crate::web_export::dto::*;

/// フィールドの区切り。**JSON に明示して配る** (JS 側に定数をハードコードさせない)。
pub const SEP: &str = "\u{0001}";

/// 実データから取るパリティケースの件数。
const PARITY_SAMPLE: usize = 2_000;

/// 1 シャードぶんの出力。
pub struct Shard {
    pub file: &'static str,
    pub meta: SearchShardMeta,
    pub shard: SearchShard,
}

fn folded(index: &TextSearchIndex) -> String {
    index.folded_str_fields().join(SEP)
}

fn build(
    ctx: &Ctx,
    kind: RefKind,
    label: &'static str,
    file: &'static str,
    rows: Vec<SearchRow>,
) -> Shard {
    let prefix = format!("/{}/", kind.collection());
    let shard = SearchShard {
        schema_version: SCHEMA_VERSION,
        kind,
        sep: SEP.to_string(),
        path_prefix: prefix,
        rows,
    };
    let bytes = serde_json::to_string(&shard).map(|s| s.len()).unwrap_or(0) as u32;
    let _ = ctx;
    Shard {
        file,
        meta: SearchShardMeta {
            kind,
            url: format!("/search/{file}.json"),
            label: label.to_string(),
            count: shard.rows.len() as u32,
            bytes,
        },
        shard,
    }
}

/// 4 シャードを組む。並びは各索引の元の並び (= コアが決めた順) をそのまま保つ。
pub fn shards(ctx: &Ctx) -> Vec<Shard> {
    let songs = ctx
        .snap
        .songs
        .iter()
        .enumerate()
        .map(|(i, s)| SearchRow {
            n: s.title.clone(),
            s: s
                .unit_id
                .as_deref()
                .and_then(|u| ctx.snap.unit(u))
                .map(|u| u.name.clone())
                .or_else(|| s.unit_name.clone()),
            k: ctx.key("songs", &s.id),
            f: folded(&ctx.snap.song_search[i]),
        })
        .collect();

    let idols = ctx
        .snap
        .idols
        .iter()
        .enumerate()
        .map(|(i, idol)| SearchRow {
            n: idol.name.clone(),
            s: idol.brand_id.as_deref().and_then(|b| ctx.brand(b)).map(|b| b.short_name.clone()),
            k: ctx.key("idols", &idol.id),
            // CV 込みの `idol_picker_search` は使わない。横断検索に CV を混ぜると
            // 「佳村はるか」で別人が並ぶ (Snapshot の doc に明記されている)。
            f: folded(&ctx.snap.idol_search[i]),
        })
        .collect();

    let events = ctx
        .snap
        .events
        .iter()
        .enumerate()
        .map(|(i, e)| SearchRow {
            n: e.name.clone(),
            s: ctx.event_dates[i].0.as_deref().map(|d| d[..4.min(d.len())].to_string()),
            k: ctx.key("events", &e.id),
            f: folded(&ctx.snap.event_search[i]),
        })
        .collect();

    let venues = ctx
        .snap
        .venues
        .iter()
        .enumerate()
        .map(|(i, v)| SearchRow {
            n: v.name.clone(),
            s: v.prefecture.clone(),
            k: ctx.key("venues", &v.id),
            f: folded(&ctx.snap.venue_search[i]),
        })
        .collect();

    vec![
        build(ctx, RefKind::Song, "楽曲", "songs", songs),
        build(ctx, RefKind::Idol, "アイドル", "idols", idols),
        build(ctx, RefKind::Event, "ライブ", "events", events),
        build(ctx, RefKind::Venue, "会場", "venues", venues),
    ]
    // 公演とユニットは v1 の検索対象外。show_venue_search は「会場文字列のみ」を見る
    // ライブ検索専用の索引で、単独スコープにすると当たり方が説明できない。
    // units にはそもそも Snapshot に索引が無い (足すならコア側の改善として起票する)。
}

pub fn manifest(shards: &[Shard]) -> SearchManifest {
    SearchManifest {
        schema_version: SCHEMA_VERSION,
        shards: shards.iter().map(|s| s.meta.clone()).collect(),
    }
}

/// 畳み込みパリティのフィクスチャ。
///
/// 実データから採るのは、**現実の入力で割れないこと**を見たいから。手書きの境界ケースは
/// 「割れると分かっている場所」を明示的に押さえる (JS の `toLowerCase()` が語末 Σ を ς に
/// してしまう件など、実測で見つかった差はここに残す)。
pub fn fold_parity(ctx: &Ctx) -> FoldParity {
    let mut inputs: Vec<String> = Vec::with_capacity(PARITY_SAMPLE + 64);

    // 実データ: 曲名 → よみ → アイドル名 → ライブ名 の順に、重複を除いて集める。
    let mut seen = std::collections::HashSet::new();
    let push = |text: &str, inputs: &mut Vec<String>, seen: &mut std::collections::HashSet<String>| {
        if !text.is_empty() && inputs.len() < PARITY_SAMPLE && seen.insert(text.to_string()) {
            inputs.push(text.to_string());
        }
    };
    for s in &ctx.snap.songs {
        push(&s.title, &mut inputs, &mut seen);
        if let Some(k) = &s.title_kana {
            push(k, &mut inputs, &mut seen);
        }
    }
    for i in &ctx.snap.idols {
        push(&i.name, &mut inputs, &mut seen);
    }
    for e in &ctx.snap.events {
        push(&e.name, &mut inputs, &mut seen);
    }

    // 手書きの境界ケース。実データに出ないものも含めて必ず入れる。
    for case in BOUNDARY_CASES {
        if seen.insert(case.to_string()) {
            inputs.push(case.to_string());
        }
    }

    FoldParity {
        schema_version: SCHEMA_VERSION,
        cases: inputs
            .into_iter()
            .map(|input| {
                // 期待値はコアの畳み込みそのもの。ここで別の式を書かない。
                let output = String::from_utf8(prepare_needle(&input)).unwrap_or_default();
                FoldCase { input, output }
            })
            .collect(),
    }
}

/// 畳み込みが割れやすい場所。
const BOUNDARY_CASES: &[&str] = &[
    // 大文字小文字。語末 Σ は JS の toLowerCase() だと ς になる (実測で不一致を確認済み)。
    "ΑΣ",
    "ΣΣ",
    "Σ Desire",
    "ς",
    "İstanbul",
    "ẞ",
    "HARUKA",
    "MiXiNG",
    // かな。
    "オネガイ！シンデレラ",
    "ハーモニー",
    "ラ・ラ・ラ",
    "ヷヸヹヺ",
    "ヶ",
    "ァ",
    // 濁点・半濁点 (NFD)。
    "ムケ\u{3099}ンタ\u{3099}イ",
    "ハ\u{309A}ステル",
    "う\u{3099}",
    "あ\u{3099}",
    "カ\u{309A}",
    // 記号・空・絵文字・サロゲートペア。
    "",
    " ",
    "！？",
    "★",
    "\u{2764}\u{FE0F}DAY1",
    "\u{1F3A4}",
    "𠮷野家",
    // 全角半角 (畳まないことの確認)。
    "ＡＢＣ",
    "ｱｲﾄﾞﾙ",
    // 記号入りの実データ由来の形。
    "THE IDOLM@STER",
    "M@STERS OF IDOL WORLD!!",
    "9:02pm",
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn separator_never_appears_in_folded_text() {
        // U+0001 が索引本文に出てしまうと、境界をまたぐ偽陽性を防ぐ仕掛けが壊れる。
        let folded = String::from_utf8(prepare_needle("Thank You! ありがとう")).unwrap();
        assert!(!folded.contains(SEP));
    }
}
