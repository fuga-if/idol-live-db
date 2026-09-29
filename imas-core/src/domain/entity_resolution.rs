//! 名前からエンティティを引き当てる規則 (曖昧解決)。
//!
//! LLM は id を知らない。「未来」「トラプリ」「ミリオン 10th」のような人の言葉で
//! 尋ねてくるので、**まずここで候補に落としてから**各ツールが id で引く。
//!
//! 照合の実体は `text_search_index` / `fuzzy_search` / `credit_names` が持っている。
//! ここに新しい照合規則を書かない — 畳み方が二重になると、画面の検索とこの入口で
//! 「当たる語」が食い違う。
//!
//! ## 並べ方 (なぜ単純な連結にしないか)
//!
//! 候補は **当たり方の強さ (完全一致 → 前方一致 → 部分一致) を第 1 キー**にし、
//! 同じ強さの中では種別を順ぐりに取る。種別ごとに固めて連結すると、曲が 3,062 件ある
//! せいで `limit` が曲だけで埋まり、「ミリオン 10th」のようにライブを訊いている語でも
//! ライブが 1 件も出てこない。訊いている種別を当てるのは LLM ではなくここの仕事なので、
//! 打ち切りの犠牲を種別間で均す。
//!
//! ## `hint` は「選ぶための一言」
//!
//! id と名前だけでは同名の別物を選び分けられない (「HOME」という曲は複数ある)。
//! ブランド・名義・開催日のように、**人がその 1 行だけ見て選べる情報**を入れる。
//! 文言の組み立ては `display_join` / `performer_label` の既存規則に乗せる。

use crate::domain::display_join::{join_parts, year_of};
use crate::domain::event_detail_queries::search_shows_with_event_name;
use crate::domain::performer_label::song_performer_label as credited_as;
use crate::domain::snapshot::Snapshot;
use crate::domain::text_search_index::{FoldedNeedle, MatchTier, TextSearchIndex};

/// 引き当てたエンティティの種別。
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum EntityKind {
    Idol,
    Song,
    Event,
    Show,
    Unit,
    Brand,
    Creator,
    Venue,
}

impl EntityKind {
    /// 種別を指定しないときに探す並び。ここの順が、同じ当たり方の候補を
    /// 順ぐりに取るときの巡回順になる。よく訊かれるものから。
    pub const ALL: [EntityKind; 8] = [
        Self::Idol,
        Self::Song,
        Self::Event,
        Self::Show,
        Self::Unit,
        Self::Brand,
        Self::Creator,
        Self::Venue,
    ];

    /// JSON / CLI に出す綴り。
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Idol => "idol",
            Self::Song => "song",
            Self::Event => "event",
            Self::Show => "show",
            Self::Unit => "unit",
            Self::Brand => "brand",
            Self::Creator => "creator",
            Self::Venue => "venue",
        }
    }

    /// 綴りから戻す。知らない語は `None` (呼び手が語彙エラーにする)。
    pub fn parse(text: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|k| k.as_str() == text.trim())
    }
}

/// 候補 1 件。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntityHit {
    pub kind: EntityKind,
    pub id: String,
    /// 表示名 (人が読む形)。
    pub name: String,
    /// どれを選ぶか LLM が判断するための一言 (ブランド名・開催日・原唱者など)。
    pub hint: String,
    /// 名前そのものと畳み込み後に一致したか。
    /// 「候補が複数あっても 1 件に決めてよい」の判断材料 ([`resolve_unique`])。
    pub exact: bool,
}

/// 打ち切り前の件数つきの答え。`total` は「この語に当たった全件」で、
/// `hits` は `limit` で切った先頭。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolveResult {
    pub hits: Vec<EntityHit>,
    pub total: u32,
    /// 種別ごとの当たり数 (0 件の種別は入れない)。並びは [`EntityKind::ALL`]。
    ///
    /// **打ち切りで種別ごと見えなくなることがある**ため添える。候補の並びは
    /// 当たり方の強さ順 (完全一致 → 前方一致 → 部分一致) なので、
    /// 「未来」のように曲名にも人名にもある語だと、曲の前方一致 (未来飛行) が
    /// 人名の部分一致 (春日未来) を押し出して、上位 5 件に人が 1 人も出ない。
    /// 件数だけでも見えていれば `kinds` で絞り直せる。
    pub by_kind: Vec<(EntityKind, u32)>,
}

/// 名前 1 つから 1 件に決められるか。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Resolution {
    /// ちょうど 1 件に決まった。
    One(EntityHit),
    /// 候補が複数あり、決め手が無い。呼び手は選び直させる。
    Many(Vec<EntityHit>),
    /// 1 件も当たらない。
    Nothing,
}

/// [`Resolution::Many`] に載せる候補の上限。これを超えると「候補を並べて選ばせる」より
/// 「語を変えさせる」ほうが早いので、並べるのはここまでにする。
pub const AMBIGUOUS_CANDIDATE_CAP: u32 = 20;

/// 語から候補を引く。`kinds` が空なら全種別。
pub fn resolve(snap: &Snapshot, query: &str, kinds: &[EntityKind], limit: u32) -> Vec<EntityHit> {
    resolve_with_total(snap, query, kinds, limit).hits
}

/// [`resolve`] に打ち切り前の件数を添えたもの。
pub fn resolve_with_total(
    snap: &Snapshot,
    query: &str,
    kinds: &[EntityKind],
    limit: u32,
) -> ResolveResult {
    let query = query.trim();
    let probe = Probe::new(query);
    if probe.is_empty() {
        return ResolveResult { hits: Vec::new(), total: 0, by_kind: Vec::new() };
    }

    // 指定順ではなく `EntityKind::ALL` の順で巡回する (巡回順が呼び出しごとに
    // 変わると、同じ語で同じ答えが返らなくなる)。
    let wanted: Vec<EntityKind> =
        EntityKind::ALL.into_iter().filter(|k| kinds.is_empty() || kinds.contains(k)).collect();

    let mut by_kind: Vec<Vec<(MatchTier, EntityHit)>> =
        wanted.iter().map(|&k| collect(snap, k, &probe)).collect();
    let total = by_kind.iter().map(Vec::len).sum::<usize>() as u32;
    let counts: Vec<(EntityKind, u32)> = wanted
        .iter()
        .zip(by_kind.iter())
        .filter(|(_, list)| !list.is_empty())
        .map(|(&kind, list)| (kind, list.len() as u32))
        .collect();
    for list in &mut by_kind {
        // 安定ソートなので、同じ当たり方の中は各種別の自然順 (添字順・新しい順) のまま。
        list.sort_by_key(|(tier, _)| *tier);
    }
    ResolveResult { hits: round_robin(by_kind, limit), total, by_kind: counts }
}

/// クエリを空白で分けた 1 語ぶんの当たり。1 件も当たらない語は `total == 0` で残す
/// (**当たらなかった語こそが手がかり**なので、落としてはいけない)。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TermHit {
    pub term: String,
    pub total: u32,
    /// 代表の候補 (先頭いくつか)。
    pub hits: Vec<EntityHit>,
}

/// 0 件だったクエリを語に分けて 1 語ずつ引き直す。
///
/// **複数語の照合は AND の部分一致なので、1 語でも外すと全体が 0 件になる。**
/// どの語が外したのかが分かれば、次の一手はたいてい決まる。
///
/// 実害の出ていた例: 「ミリオン 10th」は 0 件になる。実イベント名が
/// `THE IDOLM@STER MILLION LIVE! 10thLIVE TOUR ...` で日本語の「ミリオン」を含まず、
/// 畳み込みは大文字小文字と ひらがな/カタカナは吸収しても**日英の表記ゆれ
/// (「ミリオン」↔「MILLION LIVE」) は吸収しない**ため。語に分ければ
/// 「ミリオン」はブランド `ml` に当たり、「10th」はライブに当たると分かる。
///
/// 語が 1 つしか無いクエリは空を返す — 分けようがなく、全体が 0 件という事実以上の
/// ことを言えないため (定型の言葉だけを返せばよい)。
pub fn term_hits(snap: &Snapshot, query: &str, kinds: &[EntityKind]) -> Vec<TermHit> {
    /// 1 語につき並べる候補の数。次の一手を決められればよいので少なくてよい。
    const PER_TERM: u32 = 3;

    let terms: Vec<&str> = query.split_whitespace().collect();
    if terms.len() < 2 {
        return Vec::new();
    }
    terms
        .into_iter()
        .map(|term| {
            let found = resolve_with_total(snap, term, kinds, PER_TERM);
            TermHit { term: term.to_string(), total: found.total, hits: found.hits }
        })
        .collect()
}

/// 名前 1 つを 1 件に決める。
///
/// **候補が複数あるときに勝手に 1 件へ丸めない**のが要点。ただし「完全一致がちょうど
/// 1 件」なら決め手があるので決めてよい — `get_song(title: "THE IDOLM@STER")` は
/// 部分一致で 20 件以上を連れてくるが、その表記そのものの曲は 1 曲しか無い。
/// ここで決めないと、正確な名前を渡しているのに毎回やり直しになる。
pub fn resolve_unique(snap: &Snapshot, query: &str, kind: EntityKind) -> Resolution {
    let found = resolve_with_total(snap, query, &[kind], AMBIGUOUS_CANDIDATE_CAP);
    if found.hits.is_empty() {
        return Resolution::Nothing;
    }
    if found.total == 1 {
        return Resolution::One(found.hits.into_iter().next().expect("1 件ある"));
    }
    let mut exact = found.hits.iter().filter(|h| h.exact);
    match (exact.next(), exact.next()) {
        (Some(only), None) => Resolution::One(only.clone()),
        _ => Resolution::Many(found.hits),
    }
}

// ---------------------------------------------------------------------------
// 照合
// ---------------------------------------------------------------------------

/// 検索語を 1 度だけ畳んだもの。畳み込みの実体は `text_search_index`
/// (ここで小文字化やかなの寄せを書くと、画面の検索と当たる語が割れる)。
struct Probe {
    /// 原文。`search_shows_with_event_name` のように「生の語」を取る既存関数へ
    /// そのまま渡すために持つ (畳み込みはあちらが自分で行う)。
    raw: String,
    needle: FoldedNeedle,
}

impl Probe {
    fn new(query: &str) -> Self {
        Self {
            raw: query.to_string(),
            needle: FoldedNeedle::new(query),
        }
    }

    fn needle_text(&self) -> &str {
        &self.raw
    }

    fn is_empty(&self) -> bool {
        self.needle.is_empty()
    }

    /// 読み込み時に畳んである索引に当たるか (全行を舐める経路はこちら)。
    fn hits_index(&self, index: &TextSearchIndex) -> bool {
        index.matches(self.needle.as_bytes())
    }

    /// 表記との関係。`spellings` は「その行の名前と言える綴り」だけを渡すこと
    /// (別名や CV 名まで入れると、別人の名前で完全一致が立つ)。
    fn tier(&self, spellings: &[Option<&str>]) -> MatchTier {
        self.needle.tier(spellings)
    }
}

/// 当たり方の強さごとに、種別を順ぐりに取る。
fn round_robin(by_kind: Vec<Vec<(MatchTier, EntityHit)>>, limit: u32) -> Vec<EntityHit> {
    let limit = limit as usize;
    let mut out: Vec<EntityHit> = Vec::new();
    let mut cursor = vec![0usize; by_kind.len()];
    for tier in [MatchTier::Exact, MatchTier::Prefix, MatchTier::Substring] {
        loop {
            let mut took = false;
            for (k, list) in by_kind.iter().enumerate() {
                if out.len() >= limit {
                    return out;
                }
                match list.get(cursor[k]) {
                    Some((t, hit)) if *t == tier => {
                        out.push(hit.clone());
                        cursor[k] += 1;
                        took = true;
                    }
                    _ => {}
                }
            }
            if !took {
                break;
            }
        }
    }
    out
}

fn collect(snap: &Snapshot, kind: EntityKind, probe: &Probe) -> Vec<(MatchTier, EntityHit)> {
    match kind {
        EntityKind::Idol => collect_idols(snap, probe),
        EntityKind::Song => collect_songs(snap, probe),
        EntityKind::Event => collect_events(snap, probe),
        EntityKind::Show => collect_shows(snap, probe),
        EntityKind::Unit => collect_units(snap, probe),
        EntityKind::Brand => collect_brands(snap, probe),
        EntityKind::Creator => collect_creators(snap, probe),
        EntityKind::Venue => collect_venues(snap, probe),
    }
}

/// アイドルは `idol_picker_search` (名前・読み・ローマ字・別名 + CV 名) で引く。
/// 横断検索用の `idol_search` は名前と読みしか見ないので、「山崎はるか」で
/// 担当アイドルに辿り着けない — 人の言葉をほどくのがこの入口の役目なので広いほうを取る。
fn collect_idols(snap: &Snapshot, probe: &Probe) -> Vec<(MatchTier, EntityHit)> {
    snap.idols
        .iter()
        .enumerate()
        .filter(|(i, _)| probe.hits_index(&snap.idol_picker_search[*i]))
        .map(|(i, idol)| {
            let tier = probe.tier(&[Some(&idol.name), idol.name_kana.as_deref()]);
            let voice = snap.current_voice_actor(i as u32).map(|va| format!("CV {}", va.name));
            let hint =
                join_parts([brand_short(snap, idol.brand_id.as_deref()).map(str::to_string), voice]);
            (tier, hit(EntityKind::Idol, &idol.id, &idol.name, hint, tier))
        })
        .collect()
}

fn collect_songs(snap: &Snapshot, probe: &Probe) -> Vec<(MatchTier, EntityHit)> {
    snap.songs
        .iter()
        .enumerate()
        .filter(|(i, _)| probe.hits_index(&snap.song_search[*i]))
        .map(|(i, song)| {
            let tier = probe.tier(&[Some(&song.title), song.title_kana.as_deref()]);
            let hint = join_parts([
                brand_short(snap, song.brand_id.as_deref()).map(str::to_string),
                credited_as(snap, i as u32),
                song.release_date.as_deref().map(year_of),
            ]);
            (tier, hit(EntityKind::Song, &song.id, &song.title, hint, tier))
        })
        .collect()
}

fn collect_events(snap: &Snapshot, probe: &Probe) -> Vec<(MatchTier, EntityHit)> {
    snap.events
        .iter()
        .enumerate()
        .filter(|(i, _)| probe.hits_index(&snap.event_search[*i]))
        .map(|(i, event)| {
            let tier = probe.tier(&[Some(&event.name), event.name_kana.as_deref()]);
            let hint = join_parts([
                brand_short(snap, event.brand_id.as_deref()).map(str::to_string),
                event_date_range(snap, i as u32).map(|(first, last)| {
                    if first == last { first } else { format!("{first}〜{last}") }
                }),
                Some(event.kind.clone()),
            ]);
            (tier, hit(EntityKind::Event, &event.id, &event.name, hint, tier))
        })
        .collect()
}

/// 公演は「公演名 または ライブ名」で引く。その照合はピッカーの
/// [`search_shows_with_event_name`] が持っているので、ここでは呼ぶだけにする。
/// 打ち切らずに全件受けるのは、`total` を正しく数えるため (公演は 1,217 件で全走査は誤差)。
fn collect_shows(snap: &Snapshot, probe: &Probe) -> Vec<(MatchTier, EntityHit)> {
    search_shows_with_event_name(snap, probe.needle_text(), u32::MAX)
        .into_iter()
        .map(|show| {
            let tier = probe.tier(&[Some(&show.name), Some(&show.event_name)]);
            let hint =
                join_parts([Some(show.date.clone()), show.venue.clone(), Some(show.event_name)]);
            (tier, hit(EntityKind::Show, &show.id, &show.name, hint, tier))
        })
        .collect()
}

fn collect_units(snap: &Snapshot, probe: &Probe) -> Vec<(MatchTier, EntityHit)> {
    snap.units
        .iter()
        .enumerate()
        .filter(|(i, _)| probe.hits_index(&snap.unit_search[*i]))
        .map(|(i, unit)| {
            let tier =
                probe.tier(&[Some(&unit.name), unit.name_kana.as_deref(), unit.name_alt.as_deref()]);
            let members = snap.members_by_unit[i].len();
            let hint = join_parts([
                brand_short(snap, Some(&unit.brand_id)).map(str::to_string),
                (members > 0).then(|| format!("{members} 人")),
            ]);
            (tier, hit(EntityKind::Unit, &unit.id, &unit.name, hint, tier))
        })
        .collect()
}

/// 略称 (「ミリオン」) と id ("ml") も `brand_search` の綴りに入っている。
/// 人はブランドを正式名で呼ばないので、正式名だけ見ると 1 件も当たらない。
fn collect_brands(snap: &Snapshot, probe: &Probe) -> Vec<(MatchTier, EntityHit)> {
    snap.brand_order
        .iter()
        .map(|&b| (b as usize, &snap.brands[b as usize]))
        .filter(|(i, _)| probe.hits_index(&snap.brand_search[*i]))
        .map(|(i, brand)| {
            let tier = probe.tier(&[Some(&brand.id), Some(&brand.name), Some(&brand.short_name)]);
            let members = snap.idols_by_brand[i].len();
            let hint = join_parts([Some(brand.short_name.clone()), Some(format!("{members} 人"))]);
            (tier, hit(EntityKind::Brand, &brand.id, &brand.name, hint, tier))
        })
        .collect()
}

/// 作家は読み込み時に組んである綴り列 (名前・読み・別表記) で引く。
/// 曲の作詞作曲欄は自由文字列で読みが書かれていないので、この綴り列が唯一の導線。
fn collect_creators(snap: &Snapshot, probe: &Probe) -> Vec<(MatchTier, EntityHit)> {
    snap.creator_spellings
        .iter()
        .enumerate()
        .filter(|(_, spellings)| spellings.iter().any(|sp| probe.needle.matches(sp)))
        .map(|(i, _)| {
            let creator = &snap.creators[i];
            let tier = probe.tier(&[Some(&creator.name), Some(&creator.name_kana)]);
            let hint = join_parts([
                Some(creator.name_kana.clone()),
                creator.aliases.as_ref().map(|a| a.replace('\n', " / ")),
            ]);
            (tier, hit(EntityKind::Creator, &creator.id, &creator.name, hint, tier))
        })
        .collect()
}

fn collect_venues(snap: &Snapshot, probe: &Probe) -> Vec<(MatchTier, EntityHit)> {
    snap.venues
        .iter()
        .enumerate()
        .filter(|(i, _)| probe.hits_index(&snap.venue_search[*i]))
        .map(|(_, venue)| {
            let tier = probe.tier(&[Some(&venue.name), venue.name_kana.as_deref()]);
            let shows = snap.shows_by_venue_id.get(&venue.id).map_or(0, Vec::len);
            let hint = join_parts([
                venue.prefecture.clone(),
                venue.city.clone(),
                (shows > 0).then(|| format!("公演 {shows} 本")),
            ]);
            (tier, hit(EntityKind::Venue, &venue.id, &venue.name, hint, tier))
        })
        .collect()
}

fn hit(kind: EntityKind, id: &str, name: &str, hint: Option<String>, tier: MatchTier) -> EntityHit {
    EntityHit {
        kind,
        id: id.to_string(),
        name: name.to_string(),
        hint: hint.unwrap_or_default(),
        exact: tier == MatchTier::Exact,
    }
}

/// ブランドの略称 (「ミリオン」)。正式名は長くて 1 行の手掛かりには向かない。
/// 解決は `Snapshot::brand_short_name` が正本。
fn brand_short<'a>(snap: &'a Snapshot, brand_id: Option<&str>) -> Option<&'a str> {
    snap.brand_short_name(brand_id)
}

/// ライブの開催日の範囲 (配下公演の最初と最後)。公演が 1 本も無ければ None。
pub fn event_date_range(snap: &Snapshot, event: u32) -> Option<(String, String)> {
    let shows = &snap.shows_by_event[event as usize];
    let first = shows.iter().map(|&s| &snap.shows[s as usize].date).min()?;
    let last = shows.iter().map(|&s| &snap.shows[s as usize].date).max()?;
    Some((first.clone(), last.clone()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    fn find(hits: &[EntityHit], id: &str) -> Option<EntityHit> {
        hits.iter().find(|h| h.id == id).cloned()
    }

    #[test]
    fn アイドル名は完全一致が先頭に立ちヒントで選べる() {
        let hits = resolve(bundle_snapshot(), "春日未来", &[], 10);
        let top = &hits[0];
        assert_eq!(top.kind, EntityKind::Idol);
        assert_eq!(top.id, "ml_春日未来");
        assert!(top.exact, "表記そのものなので完全一致");
        // ヒントだけで「どのブランドの誰か」が書ける。
        assert!(top.hint.contains("ミリオン"), "hint={}", top.hint);
        assert!(top.hint.contains("CV "), "hint={}", top.hint);
    }

    #[test]
    fn 声優名でも担当アイドルに辿り着ける() {
        let hits = resolve(bundle_snapshot(), "山崎はるか", &[EntityKind::Idol], 10);
        assert!(find(&hits, "ml_春日未来").is_some(), "{hits:?}");
    }

    #[test]
    fn 曲名の完全一致は候補が多くても1件に決まる() {
        match resolve_unique(bundle_snapshot(), "THE IDOLM@STER", EntityKind::Song) {
            Resolution::One(hit) => assert_eq!(hit.id, "765as_the_idolmster"),
            other => panic!("完全一致 1 件なら決まるはず: {other:?}"),
        }
    }

    #[test]
    fn 決め手が無いときは候補を返して決めない() {
        // 「10th」はライブ名に何本も出てくる。勝手に 1 本へ丸めない。
        match resolve_unique(bundle_snapshot(), "10th", EntityKind::Event) {
            Resolution::Many(hits) => assert!(hits.len() > 1, "{hits:?}"),
            other => panic!("曖昧なままであるべき: {other:?}"),
        }
    }

    #[test]
    fn 当たらない語は空() {
        assert_eq!(resolve_unique(bundle_snapshot(), "存在しない名前ですよこれは", EntityKind::Idol), Resolution::Nothing);
        assert!(resolve(bundle_snapshot(), "   ", &[], 10).is_empty(), "空白だけの語は候補を出さない");
    }

    #[test]
    fn 種別をまたぐ語は種別が偏らない() {
        // 「ミリオン」は曲・ライブ・ユニットのどれにも当たる。曲だけで埋めない。
        let hits = resolve(bundle_snapshot(), "ミリオン", &[], 12);
        let kinds: std::collections::BTreeSet<_> = hits.iter().map(|h| h.kind).collect();
        assert!(kinds.len() >= 2, "1 種別で埋まっている: {hits:?}");
    }

    #[test]
    fn 打ち切り前の件数が分かる() {
        let all = resolve_with_total(bundle_snapshot(), "ライブ", &[EntityKind::Event], 3);
        assert_eq!(all.hits.len(), 3);
        assert!(all.total > 3, "total={}", all.total);
    }

    #[test]
    fn 公演は日付と会場で選び分けられる() {
        let hits = resolve(bundle_snapshot(), "MILLION LIVE", &[EntityKind::Show], 5);
        assert!(!hits.is_empty());
        let first = &hits[0];
        assert_eq!(first.kind, EntityKind::Show);
        // 「YYYY-MM-DD ・ 会場」が入っているので、同名公演でも日付で選べる。
        assert!(first.hint.len() >= 10, "hint={}", first.hint);
        assert!(first.hint.starts_with("20"), "hint={}", first.hint);
    }

    /// 人はブランドを正式名で呼ばない。略称と id で当たらないと、LLM は
    /// 「ミリオンのライブ」のような普通の言い方で空振りしたことにすら気づけない。
    #[test]
    fn ブランドは略称でも_id_でも引ける() {
        for (word, id) in [("デレマス", "cg"), ("ミリオン", "ml"), ("シャニマス", "sc"), ("ml", "ml")] {
            let hits = resolve(bundle_snapshot(), word, &[EntityKind::Brand], 5);
            assert_eq!(hits.first().map(|h| h.id.as_str()), Some(id), "{word} が引けない: {hits:?}");
        }
    }

    /// ユニットは畳み済み索引 (`unit_search`) を通る。かな・別表記でも当たること。
    #[test]
    fn ユニットは名前と別表記で引ける() {
        let hits = resolve(bundle_snapshot(), "トライスタービジョン", &[EntityKind::Unit], 5);
        assert_eq!(hits.first().map(|h| h.kind), Some(EntityKind::Unit), "{hits:?}");
        assert!(hits[0].exact, "表記そのものなので完全一致: {:?}", hits[0]);
        assert!(hits[0].hint.contains("ミリオン"), "hint={}", hits[0].hint);
    }
}
