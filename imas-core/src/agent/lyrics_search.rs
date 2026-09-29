//! 歌詞に語を含む曲を探す。**本文は返さない。一致箇所まわりの短い断片だけ。**
//!
//! # 何をここに置くか
//!
//! 探すのは**サーバ** (`GET /lyrics/search`)。歌詞本文は D1 にしか無く、
//! JASRAC の許諾が「一括ダウンロードさせない配信形式」に対して下りている以上
//! (`JASRAC.md`)、本文をこちら側に持ってこない。サーバは song_id と断片しか返さず、
//! 曲名も歌手も返さない (端末が同梱 SQLite から引く前提のため)。
//!
//! ここに置くのは**その断片に曲の情報を添える規則**と、
//! **断片を出す上限**。HTTP を話すのはアダプタ (`agent::lyrics_api`) の仕事で、
//! アダプタに「何を返すか」を書かない。
//!
//! # 引用の範囲に収めるための上限
//!
//! サーバは 1 曲につき打った語の数だけ断片を返しうる。そのまま通すと、語を変えて
//! 何度も引けば曲が復元できてしまう。ここで **1 曲 [`MAX_SNIPPETS_PER_SONG`] 本**に
//! 切る。行番号も前後の行も持たないので、断片どうしのつながりは分からない。

use crate::agent::tools::{json::Obj, tool_schema, ToolSpec};
use crate::domain::snapshot::Snapshot;
use crate::domain::song_list_queries::is_hidden_variant;
use serde_json::{json, Value};
use std::collections::HashSet;

/// 1 曲につき返す断片の本数。AND で 2 語打ったとき「なぜ当たったか」が読める最小限。
pub const MAX_SNIPPETS_PER_SONG: usize = 2;

/// サーバの `/lyrics/search` が返す 1 曲ぶん (HTTP をほどくのはアダプタ)。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApiHit {
    pub song_id: String,
    pub snippets: Vec<String>,
}

/// ツールが返す 1 曲。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LyricHit {
    pub song_id: String,
    pub title: String,
    pub brand_id: Option<String>,
    /// 一致箇所まわりの断片。[`MAX_SNIPPETS_PER_SONG`] 本まで。
    pub snippets: Vec<String>,
    /// この曲の披露回数。「レア曲か」「定番か」をもう 1 回引かずに読めるようにする。
    pub show_count: u32,
}

/// 当たった曲を絞る条件。名前と意味は他のツールの同名の軸に合わせる
/// (`brand` が `list_songs` と違う意味になる、という壊れ方をさせない)。
///
/// **`scope` (公演 / ライブ / アイドル) は「母集団を決める」軸**で、これを指定すると
/// 応答に母集団の大きさが付く。「この公演の 23 曲のうち歌詞に『月』を含むのは 8 曲」
/// という読み方が 1 回で出る — これが無いと、サーバが返す全 200 件を呼び手が手で
/// 突き合わせることになる (実際に 13thLIVE の分析でそうなった)。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct LyricsFilter {
    pub brand: Option<String>,
    pub song_type: Option<String>,
    /// 母集団。曲の集合をここで決める。
    pub scope: Option<Scope>,
    /// 披露回数の下限 / 上限。0 を下限にすると「まだ歌われていない曲」が外れないので、
    /// 未披露だけを見たいときは `max_performances: 0` を使う。
    pub min_performances: Option<u32>,
    pub max_performances: Option<u32>,
}

/// 曲の母集団の決め方。添字は呼び手 (ツール面) が id から解決して渡す。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Scope {
    /// その公演のセットリストに入っている曲。
    Show(u32),
    /// そのライブ (全公演) のセットリストに入っている曲。
    Event(u32),
    /// そのアイドルが**原唱に入る**曲 (`list_songs --idol_id` と同じ意味)。
    Idol(u32),
}

impl Scope {
    /// 母集団の曲 (songs の添字)。派生曲は数えない ([`decorate`] と同じ物差しにする —
    /// 分母に派生を入れると「84 曲中 7 曲」の 84 だけが膨らむ)。
    pub fn song_indexes(&self, snap: &Snapshot) -> HashSet<u32> {
        self.raw_song_indexes(snap)
            .into_iter()
            .filter(|&i| !is_hidden_variant(&snap.songs[i as usize]))
            .collect()
    }

    fn raw_song_indexes(&self, snap: &Snapshot) -> HashSet<u32> {
        match *self {
            Scope::Show(show) => snap.setlist_items_by_show[show as usize]
                .iter()
                .map(|&i| snap.setlist_items[i as usize].song)
                .collect(),
            Scope::Event(event) => snap.shows_by_event[event as usize]
                .iter()
                .flat_map(|&s| snap.setlist_items_by_show[s as usize].iter())
                .map(|&i| snap.setlist_items[i as usize].song)
                .collect(),
            Scope::Idol(idol) => snap.songs_by_idol[idol as usize]
                .iter()
                .filter(|l| l.role == "original")
                .map(|l| l.song)
                .collect(),
        }
    }
}

/// サーバの結果に曲の情報を添え、条件で絞る。
///
/// **この DB に無い song_id は落とす。** サーバの歌詞は master より新しいことがあり
/// (歌詞だけ先に入る)、曲名を引けないものを id だけで返すと呼び手が扱えない。
pub fn decorate(
    snap: &Snapshot,
    hits: &[ApiHit],
    filter: &LyricsFilter,
    limit: usize,
) -> Vec<LyricHit> {
    let scope_songs = filter.scope.as_ref().map(|s| s.song_indexes(snap));
    let mut rows: Vec<LyricHit> = hits
        .iter()
        .filter_map(|hit| {
            let &idx = snap.song_index_by_id.get(&hit.song_id)?;
            let song = &snap.songs[idx as usize];
            // 派生曲 ((◯◯ Ver.) 等) は親と歌詞が同じなので、同じ断片で一覧が埋まる。
            // list_songs が既定で隠すのと同じ扱いにそろえる。親の側で当たる。
            if is_hidden_variant(song) {
                return None;
            }
            if filter.brand.as_deref().is_some_and(|b| song.brand_id.as_deref() != Some(b)) {
                return None;
            }
            if filter.song_type.as_deref().is_some_and(|t| song.song_type.as_deref() != Some(t)) {
                return None;
            }
            if scope_songs.as_ref().is_some_and(|s| !s.contains(&idx)) {
                return None;
            }
            let plays = snap.performance_counts[idx as usize];
            if filter.min_performances.is_some_and(|m| plays < m)
                || filter.max_performances.is_some_and(|m| plays > m)
            {
                return None;
            }
            let mut snippets: Vec<String> = hit.snippets.clone();
            snippets.truncate(MAX_SNIPPETS_PER_SONG);
            Some(LyricHit {
                song_id: song.id.clone(),
                title: song.title.clone(),
                brand_id: song.brand_id.clone(),
                snippets,
                show_count: snap.performance_counts[idx as usize],
            })
        })
        .collect();
    // サーバは song_id 順で返す。そのまま切ると id の若いブランドだけが並ぶので、
    // **披露回数の多い順**に直してから切る。定番曲かレア曲かが上から読める並びにする。
    rows.sort_by(|a, b| b.show_count.cmp(&a.show_count).then(a.song_id.cmp(&b.song_id)));
    rows.truncate(limit);
    rows
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    fn hit(id: &str, n: usize) -> ApiHit {
        ApiHit {
            song_id: id.into(),
            snippets: (0..n).map(|i| format!("だみー断片{i}")).collect(),
        }
    }

    #[test]
    fn 曲名と披露回数が添う() {
        let out = decorate(bundle_snapshot(), &[hit("ml_ロケットスター", 1)], &LyricsFilter::default(), 10);
        assert_eq!(out.len(), 1, "{out:?}");
        assert_eq!(out[0].title, "ロケットスター☆");
        assert_eq!(out[0].brand_id.as_deref(), Some("ml"));
        assert!(out[0].show_count >= 1, "{out:?}");
    }

    #[test]
    fn 断片は_1_曲_2_本までに切る() {
        // サーバが 5 本返しても 2 本しか通さない。語を変えて集めても曲は復元できない。
        let out = decorate(bundle_snapshot(), &[hit("ml_ロケットスター", 5)], &LyricsFilter::default(), 10);
        assert_eq!(out[0].snippets.len(), MAX_SNIPPETS_PER_SONG);
    }

    #[test]
    fn 披露回数の多い順に並ぶ() {
        // サーバは song_id 順で返すので、並べ替えていないとここが落ちる。
        let hits: Vec<ApiHit> =
            ["765as_continue", "ml_アイル", "765as_masterpiece"].iter().map(|id| hit(id, 1)).collect();
        let out = decorate(bundle_snapshot(), &hits, &LyricsFilter::default(), 10);
        let counts: Vec<u32> = out.iter().map(|h| h.show_count).collect();
        let mut sorted = counts.clone();
        sorted.sort_by(|a, b| b.cmp(a));
        assert_eq!(counts, sorted, "{out:?}");
    }

    #[test]
    fn ブランドで絞れる() {
        let hits: Vec<ApiHit> =
            ["765as_continue", "ml_アイル"].iter().map(|id| hit(id, 1)).collect();
        let f = LyricsFilter { brand: Some("ml".into()), ..Default::default() };
        let out = decorate(bundle_snapshot(), &hits, &f, 10);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].brand_id.as_deref(), Some("ml"));
    }

    #[test]
    fn 公演の中だけで探すと母集団が分かる() {
        let s = bundle_snapshot();
        let show = s.show_index_by_id["sh_the_idolm@ster_million_live_13thlive_2"];
        let in_show: Vec<&str> = Scope::Show(show)
            .song_indexes(s)
            .iter()
            .map(|&i| s.songs[i as usize].id.as_str())
            .collect();
        assert_eq!(in_show.len(), 23, "13th DAY2 は 23 曲");

        // セトリの 1 曲と、セトリに無い 1 曲を混ぜて投げる。
        let hits = vec![hit(in_show[0], 1), hit("ml_ロケットスター", 1)];
        let f = LyricsFilter { scope: Some(Scope::Show(show)), ..Default::default() };
        let out = decorate(s, &hits, &f, 10);
        assert_eq!(out.len(), 1, "セトリ外の曲が残っている: {out:?}");

        let v = response(s, "月", &hits, &f, 2, 10);
        assert_eq!(v["scope"]["kind"], "show");
        assert_eq!(v["scope"]["songs"], 23, "母集団の大きさが付かない");
        assert_eq!(v["matched"], 1);
        assert_eq!(v["total"], 2, "サーバの生の件数は残す");
    }

    #[test]
    fn 持ち歌の中だけで探せる() {
        let s = bundle_snapshot();
        let idol = s.idol_index_by_id["ml_伊吹翼"];
        let f = LyricsFilter { scope: Some(Scope::Idol(idol)), ..Default::default() };
        // ロケットスター☆ は翼の持ち歌、Dreaming! も。ハミングバードは桜守歌織。
        let hits = vec![hit("ml_ロケットスター", 1), hit("ml_ハミングバード", 1)];
        let out = decorate(s, &hits, &f, 10);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].song_id, "ml_ロケットスター");
    }

    #[test]
    fn 披露回数で絞れて_0_なら未披露だけ() {
        let s = bundle_snapshot();
        let hits: Vec<ApiHit> =
            ["ml_ロケットスター", "ml_アイル", "765as_continue"].iter().map(|id| hit(id, 1)).collect();
        let hot = LyricsFilter { min_performances: Some(5), ..Default::default() };
        for h in decorate(s, &hits, &hot, 10) {
            assert!(h.show_count >= 5, "{h:?}");
        }
        let cold = LyricsFilter { max_performances: Some(0), ..Default::default() };
        for h in decorate(s, &hits, &cold, 10) {
            assert_eq!(h.show_count, 0, "未披露だけのはず: {h:?}");
        }
    }

    #[test]
    fn 絞った件数は_limit_で切る前に数える() {
        let s = bundle_snapshot();
        let hits: Vec<ApiHit> =
            ["ml_ロケットスター", "ml_アイル", "ml_泣き空のち"].iter().map(|id| hit(id, 1)).collect();
        // サーバは 10 件返したが、この DB に曲名があるのは 3 件、という状況。
        let v = response(s, "翼", &hits, &LyricsFilter::default(), 10, 1);
        // limit 1 でも matched は 3 のまま。ここが limit に化けると
        // 「23 曲中 8 曲」の 8 が壊れる。
        assert_eq!(v["matched"], 3, "{v}");
        assert_eq!(v["shown"], 1, "{v}");
    }

    #[test]
    fn 派生曲は親と歌詞が同じなので返さない() {
        let s = bundle_snapshot();
        // アイル(Harmonized ver.) は ml_アイル の派生。
        let hits = vec![hit("ml_アイル", 1), hit("ml_アイルharmonized_ver", 1)];
        let out = decorate(s, &hits, &LyricsFilter::default(), 10);
        assert_eq!(out.len(), 1, "派生が残っている: {out:?}");
        assert_eq!(out[0].song_id, "ml_アイル");
    }
}

/// 1 回の検索で返す曲数の上限。
pub const MAX_SONGS: usize = 40;

/// 歌詞検索ツールの札。実行は HTTP を話すアダプタ (`agent::lyrics_api`) の仕事で、
/// `proposal_*` と同じ振り分け方 (`agent::dispatch`) になる。
pub fn lyrics_catalog() -> Vec<ToolSpec> {
    vec![ToolSpec {
        name: "search_lyrics".to_string(),
        description: "歌詞に語を含む曲を探す。空白で AND、| で OR、() でまとめる             (例: 空 翼 / つばさ|ツバサ / (空|海) 夏)。ひらがな/カタカナと大文字小文字は畳む。            **歌詞本文は返らない。**返るのは曲と、一致箇所まわりの短い断片 (1 曲 2 本まで) と             披露回数だけ。断片に行番号も前後の行も付かないので、集めても歌詞は組み直せない。            「名前が歌詞に出てくる曲」「季節や情景で曲を選ぶ」といった、            曲名や原唱者からは引けない探し方に使う。"
            .to_string(),
        input_schema: tool_schema(
            json!({
                "query": { "type": "string", "description": "探す語。空白=AND / |=OR / ()=grouping。2 文字以上。" },
                "brand": { "type": "string", "description": "ブランド id で絞る (例 ml / cg)。歌詞は全ブランド横断なので、1 ブランドの中で探すときに付ける。" },
                "song_type": { "type": "string", "description": "曲種別で絞る (vocabulary の song_type)。" },
                "show_id": { "type": "string", "description": "**その公演のセットリストの中だけ**で探す。応答に scope.songs (その公演の曲数) が付くので「23 曲中 8 曲」と読める。" },
                "event_id": { "type": "string", "description": "**そのライブ (全公演) のセットリストの中だけ**で探す。" },
                "idol_id": { "type": "string", "description": "**そのアイドルが原唱に入る曲の中だけ**で探す (list_songs の idol_id と同じ意味)。" },
                "min_performances": { "type": "integer", "description": "披露回数の下限。定番曲だけ見たいときに。" },
                "max_performances": { "type": "integer", "description": "披露回数の上限。0 にすると**まだ一度も歌われていない曲**だけになる。" },
                "limit": { "type": "integer", "description": "曲数の上限。既定 20・最大 40。並びは披露回数の多い順。" }
            }),
            &["query"],
        ),
    }]
}

/// この名前は歌詞検索ツールか。
pub fn is_lyrics_tool(name: &str) -> bool {
    name == "search_lyrics"
}

/// ツールの応答を組む。**「何を返すか」はここが正本**で、アダプタは HTTP をほどいて
/// [`ApiHit`] にするところまでしかやらない。
///
/// `server_total` はサーバが返した生の件数。この DB に無い曲を落とすので
/// (歌詞だけ先に入ることがある)、落とした事実が分かるように両方の数を返す。
pub fn response(
    snap: &Snapshot,
    query: &str,
    hits: &[ApiHit],
    filter: &LyricsFilter,
    server_total: usize,
    limit: usize,
) -> Value {
    // 絞り込んだ件数は limit で切る前に数える。切った後の数を返すと
    // 「23 曲中 8 曲」の 8 が limit に化ける。
    let matched = decorate(snap, hits, filter, usize::MAX).len();
    let rows = decorate(snap, hits, filter, limit);

    let mut o = Obj::new();
    o.put("query", query);
    // サーバが全曲から返した件数。絞り込みの分母ではない。
    o.put("total", server_total);
    if matched != server_total {
        o.put("matched", matched);
    }
    // 母集団を指定したときだけ、その大きさを添える。これが無いと
    // 「何曲中の何曲か」が言えない。
    if let Some(scope) = &filter.scope {
        let songs = scope.song_indexes(snap);
        let mut s = Obj::new();
        let (kind, id, name) = match *scope {
            Scope::Show(i) => ("show", snap.shows[i as usize].id.as_str(), snap.shows[i as usize].name.as_str()),
            Scope::Event(i) => ("event", snap.events[i as usize].id.as_str(), snap.events[i as usize].name.as_str()),
            Scope::Idol(i) => ("idol", snap.idols[i as usize].id.as_str(), snap.idols[i as usize].name.as_str()),
        };
        s.put("kind", kind);
        s.put("id", id);
        s.put("name", name);
        s.put("songs", songs.len());
        o.put("scope", s.value());
    }
    if rows.len() < matched {
        o.put("shown", rows.len());
    }
    o.list(
        "songs",
        rows.iter()
            .map(|h| {
                let mut r = Obj::new();
                r.put("song_id", h.song_id.as_str());
                r.put("title", h.title.as_str());
                r.opt("brand_id", h.brand_id.clone());
                r.put("show_count", h.show_count);
                r.list("snippets", h.snippets.iter().map(|s| json!(s)).collect());
                r.value()
            })
            .collect(),
    );
    o.value()
}
