//! 出力の共通文脈。`Ref` / テーマキー / URL / SEO ブロックの作り方はここに 1 つだけ置く。
//!
//! 各 emit がそれぞれ `format!("/songs/{}/", ...)` を書き始めると、URL 規約が
//! 散らばって必ずどこかがずれる。**リンクは必ず [`Ctx`] のメソッドから作ること。**

use crate::domain::display_join::year_of;
use crate::domain::idol_queries::{self, BrandRecord};
use crate::domain::performance_stats::CoOccurIndex;
use crate::domain::snapshot::Snapshot;
use crate::web_export::content::{self, absolute};
use crate::web_export::dto::*;
use crate::web_export::theme;
use crate::web_export::url::{detail_path, fallback_reason, path_key, reserved_for, url_segment, FallbackReason};
use std::collections::{BTreeMap, HashMap};

/// 他フランチャイズの合同ライブ楽曲などを入れているブランド。
///
/// 掲載はするが検索エンジンには拾わせない (非公式ファンサイトが他フランチャイズ名で
/// 検索流入を取りにいかないため)。判断はここで済ませ、Astro は写すだけにする。
pub const OTHER_BRAND_ID: &str = "other";

/// テーマ表を作る材料: (アイドル id, アイドル色, 主ブランドの色)。
pub type IdolThemeInput = (String, Option<String>, Option<String>);
/// テーマ表を作る材料: (ブランド id, ブランド色)。
pub type BrandThemeInput = (String, Option<String>);

/// 出力全体で共有する読み取り専用の文脈。
pub struct Ctx<'a> {
    pub snap: &'a Snapshot,
    /// JST の「今日」。upcoming / past の分割はすべてこの 1 個から決まる。
    pub today: String,
    pub generated_at: String,
    pub data_version: Option<String>,
    pub content_hash: Option<String>,

    /// コレクション名 → (id → URL セグメント)。危険な id はフォールバック slug に落ちている。
    keys: HashMap<&'static str, HashMap<String, String>>,
    /// フォールバック slug に落ちた件数 (stderr とテストで見る)。
    pub fallback_slugs: usize,
    /// 危険な文字・予約語のせいで落ちた件数 (データ側を直すべきもの)。
    pub fallback_unsafe: usize,
    /// 長すぎて落ちた件数 (壊れてはいないが URL が読めない)。
    pub fallback_too_long: usize,

    brands: BTreeMap<String, BrandRecord>,
    /// アイドル id → 主ブランドの色 (テーマの落とし先)。
    idol_brand_color: HashMap<String, Option<String>>,
    /// イベント index → (最初の公演日, 最後の公演日)。
    pub event_dates: Vec<(Option<String>, Option<String>)>,
    /// 「一緒に来る曲」の前計算。全 3,153 曲ぶん出すので 1 度だけ作って使い回す。
    pub co_occur: CoOccurIndex,
    /// ブランドごとの件数 (1 パスで数えたもの)。
    brand_counts: BTreeMap<String, super::places::BrandCounts>,
}

impl<'a> Ctx<'a> {
    pub fn new(
        snap: &'a Snapshot,
        today: String,
        generated_at: String,
        content_hash: Option<String>,
    ) -> Self {
        let brands: BTreeMap<String, BrandRecord> =
            idol_queries::brand_records(snap).into_iter().map(|b| (b.id.clone(), b)).collect();

        let mut keys = HashMap::new();
        let (mut fallback_unsafe, mut fallback_too_long) = (0, 0);
        let mut add = |collection: &'static str, ids: Vec<String>| {
            let mut map = HashMap::with_capacity(ids.len());
            for id in ids {
                match fallback_reason(&id, reserved_for(collection)) {
                    Some(FallbackReason::Unsafe) => fallback_unsafe += 1,
                    Some(FallbackReason::TooLong) => fallback_too_long += 1,
                    None => {}
                }
                let key = path_key(&id, reserved_for(collection), collection);
                map.insert(id, key);
            }
            keys.insert(collection, map);
        };
        add("events", snap.events.iter().map(|e| e.id.clone()).collect());
        add("shows", snap.shows.iter().map(|s| s.id.clone()).collect());
        add("songs", snap.songs.iter().map(|s| s.id.clone()).collect());
        add("idols", snap.idols.iter().map(|i| i.id.clone()).collect());
        add("units", snap.units.iter().map(|u| u.id.clone()).collect());
        add("venues", snap.venues.iter().map(|v| v.id.clone()).collect());
        add("brands", snap.brands.iter().map(|b| b.id.clone()).collect());

        // アイドルの主ブランド色。アイドル自身の色が無いときの落とし先で、
        // 優先順位の判断は color_engine::first_valid_hex が持つ。
        let idol_brand_color = snap
            .idols
            .iter()
            .map(|i| {
                let color = i
                    .brand_id
                    .as_deref()
                    .and_then(|b| brands.get(b))
                    .and_then(|b| b.color.clone());
                (i.id.clone(), color)
            })
            .collect();

        // 公演日の最小・最大。イベントの期間表示と年グループの材料。
        let event_dates = snap
            .shows_by_event
            .iter()
            .map(|shows| {
                let mut dates: Vec<&str> =
                    shows.iter().map(|&s| snap.shows[s as usize].date.as_str()).collect();
                dates.sort_unstable();
                (dates.first().map(|d| d.to_string()), dates.last().map(|d| d.to_string()))
            })
            .collect();

        Self {
            snap,
            today,
            generated_at,
            data_version: snap.meta_value("data_version").map(str::to_string),
            content_hash,
            keys,
            fallback_slugs: fallback_unsafe + fallback_too_long,
            fallback_unsafe,
            fallback_too_long,
            brands,
            idol_brand_color,
            event_dates,
            co_occur: CoOccurIndex::build(snap),
            brand_counts: super::places::brand_counts_table(snap),
        }
    }

    /// ブランドの件数。未知のブランドは 0。
    pub fn brand_counts(&self, brand_id: &str) -> super::places::BrandCounts {
        self.brand_counts.get(brand_id).copied().unwrap_or_default()
    }

    // -----------------------------------------------------------------------
    // URL
    // -----------------------------------------------------------------------

    /// 詳細ページの id → URL セグメント (フォールバック slug 込み)。
    ///
    /// **未知の id は `None`。**以前は黙って計算し直していたが、それだと
    /// 「そのコレクションに無い値」を渡しても動いてしまい、実際に都道府県名を
    /// 会場の keyspace に通してファイル名を作っていた (予約語や衝突の検査が
    /// 別の集合に対して行われる)。任意の値を安全化したいときは [`Self::param_key`]。
    pub fn key(&self, collection: &str, id: &str) -> Option<&str> {
        self.keys.get(collection)?.get(id).map(String::as_str)
    }

    /// 一覧ページの params (年 / 月 / ブランド id / 都道府県名) をファイル名と URL に
    /// 使える形へ。
    ///
    /// 詳細ページの id とは**別の keyspace**。予約語も衝突検査も詳細ページのものとは
    /// 無関係なので、[`Self::key`] とは分けてある。
    pub fn param_key(value: &str) -> String {
        path_key(value, &[], "param")
    }

    /// 詳細ページの完成形 URL。id はスナップショットに在るものだけを渡すこと。
    pub fn path(&self, kind: RefKind, id: &str) -> String {
        detail_path(kind.collection(), self.expect_key(kind, id))
    }

    /// 出力する JSON の相対パス。
    pub fn data_path(&self, kind: RefKind, id: &str) -> String {
        format!("{}/{}.json", kind.collection(), self.expect_key(kind, id))
    }

    /// 詳細ページの URL セグメント。
    ///
    /// 呼ぶのはスナップショットから取り出した id を持っているときだけなので、
    /// 見つからないのは**組み立ての誤り** (別のコレクションの id を渡した等)。
    /// 黙って計算し直すと、予約語や衝突の検査を通っていない値が URL に出る。
    pub fn expect_key(&self, kind: RefKind, id: &str) -> &str {
        self.key(kind.collection(), id).unwrap_or_else(|| {
            panic!("{} に無い id を URL にしようとした: {id:?}", kind.collection())
        })
    }

    // -----------------------------------------------------------------------
    // テーマ
    // -----------------------------------------------------------------------

    /// アイドルのテーマキー。
    pub fn idol_theme(&self, idol_id: &str) -> String {
        theme::idol_key(idol_id)
    }

    /// ブランド由来のテーマキー。ブランドが決まらないものはニュートラル。
    ///
    /// 曲・ライブ・公演・ユニット・会場はすべてこれ。アイドル色を持たないものに
    /// アイドル色を当てないのは、アプリの見え方に合わせるため。
    pub fn brand_theme(&self, brand_id: Option<&str>) -> String {
        match brand_id {
            Some(b) if self.brands.contains_key(b) => theme::brand_key(b),
            _ => theme::NEUTRAL_KEY.to_string(),
        }
    }

    /// `themes.css` / `themes.json` に載せるテーマ表の材料。
    pub fn theme_inputs(&self) -> (Vec<IdolThemeInput>, Vec<BrandThemeInput>) {
        let idols = self
            .snap
            .idols
            .iter()
            .map(|i| {
                (
                    i.id.clone(),
                    i.color.clone(),
                    self.idol_brand_color.get(&i.id).cloned().flatten(),
                )
            })
            .collect();
        let brands = self.brands.values().map(|b| (b.id.clone(), b.color.clone())).collect();
        (idols, brands)
    }

    // -----------------------------------------------------------------------
    // Ref
    // -----------------------------------------------------------------------

    pub fn brand(&self, id: &str) -> Option<&BrandRecord> {
        self.brands.get(id)
    }

    /// ブランドが `other` か。SEO の noindex 判断に使う。
    pub fn is_other_brand(&self, brand_id: Option<&str>) -> bool {
        brand_id == Some(OTHER_BRAND_ID)
    }

    /// ブランド別一覧の URL。**その一覧を作っていない組み合わせでは `None`。**
    ///
    /// `other` (他フランチャイズの合同ライブ曲) はアイドル一覧しか作らない。既定フィルタが
    /// `other` を含めないというコアの規則と、一覧の入口が存在するという事実が食い違うため
    /// (到達は検索と個別ページから)。この判断がかつて 6 箇所に散っていて、パンくずだけ
    /// 判断を持たずに存在しないページへリンクしていた。
    ///
    /// id を URL に埋めるときは必ず [`url_segment`] を通す。ブランド id は今のところ
    /// すべて ASCII だが、規則を 1 箇所に保たないと将来の id で静かに壊れる。
    pub fn brand_list_path(&self, collection: &str, brand_id: &str) -> Option<String> {
        if !self.brands.contains_key(brand_id) {
            return None;
        }
        if self.is_other_brand(Some(brand_id)) && collection != "idols" {
            return None;
        }
        Some(format!("/{collection}/brand/{}/", url_segment(brand_id)))
    }

    pub fn robots(&self, brand_id: Option<&str>) -> Robots {
        if self.is_other_brand(brand_id) {
            Robots::NoindexFollow
        } else {
            Robots::IndexFollow
        }
    }

    fn make_ref(
        &self,
        kind: RefKind,
        id: &str,
        name: &str,
        sub: Option<String>,
        theme_key: String,
    ) -> Ref {
        let monogram = monogram_of(kind, name, sub.as_deref());
        Ref {
            kind,
            id: id.to_string(),
            name: name.to_string(),
            sub,
            path: self.path(kind, id),
            theme_key,
            artwork_url: None,
            // アプリの ImasAvatar と同じ 1 文字。画像を載せないのでこれが唯一の「顔」。
            // ブランドだけは表示名ではなく短縮名から取る (正式名は長すぎて先頭 1 文字が
            // 「ア」ばかりになり、見分けが付かない)。
            monogram,
        }
    }

    pub fn brand_ref(&self, id: &str) -> Option<Ref> {
        let b = self.brands.get(id)?;
        Some(self.make_ref(
            RefKind::Brand,
            &b.id,
            &b.name,
            Some(b.short_name.clone()),
            theme::brand_key(&b.id),
        ))
    }

    /// カンマ区切りの `joint_brand_ids` を Ref に開く。
    pub fn joint_brand_refs(&self, joint: Option<&str>) -> Vec<Ref> {
        crate::web_export::url::split_csv(joint).filter_map(|id| self.brand_ref(id)).collect()
    }

    pub fn idol_ref(&self, id: &str) -> Option<Ref> {
        let idol = self.snap.idol(id)?;
        let sub = idol.brand_id.as_deref().and_then(|b| self.brands.get(b)).map(|b| b.name.clone());
        Some(self.make_ref(RefKind::Idol, &idol.id, &idol.name, sub, self.idol_theme(&idol.id)))
    }

    pub fn song_ref(&self, id: &str) -> Option<Ref> {
        let song = self.snap.song(id)?;
        // 補助表記はユニット名。マスタに無いユニットは songs.unit_name の自由記述で出す。
        let sub = song
            .unit_id
            .as_deref()
            .and_then(|u| self.snap.unit(u))
            .map(|u| u.name.clone())
            .or_else(|| song.unit_name.clone());
        let mut r = self.make_ref(
            RefKind::Song,
            &song.id,
            &song.title,
            sub,
            self.brand_theme(song.brand_id.as_deref()),
        );
        // サイト唯一の外部画像。無ければソリッド面にフォールバックする前提。
        r.artwork_url = song.artwork_url.clone();
        Some(r)
    }

    pub fn event_ref(&self, id: &str) -> Option<Ref> {
        let &i = self.snap.event_index_by_id.get(id)?;
        let event = &self.snap.events[i as usize];
        // 補助表記は開催年 (同名ツアーが並ぶので年が無いと見分けられない)。
        let sub = self.event_dates[i as usize].0.as_deref().map(year_of);
        Some(self.make_ref(
            RefKind::Event,
            &event.id,
            &event.name,
            sub,
            self.brand_theme(event.brand_id.as_deref()),
        ))
    }

    pub fn show_ref(&self, id: &str) -> Option<Ref> {
        let &i = self.snap.show_index_by_id.get(id)?;
        let show = &self.snap.shows[i as usize];
        let brand_id = self.snap.events[show.event as usize].brand_id.clone();
        Some(self.make_ref(
            RefKind::Show,
            &show.id,
            &show.name,
            Some(show.date.clone()),
            self.brand_theme(brand_id.as_deref()),
        ))
    }

    pub fn unit_ref(&self, id: &str) -> Option<Ref> {
        let unit = self.snap.unit(id)?;
        let sub = self.brands.get(&unit.brand_id).map(|b| b.name.clone());
        Some(self.make_ref(
            RefKind::Unit,
            &unit.id,
            &unit.name,
            sub,
            self.brand_theme(Some(&unit.brand_id)),
        ))
    }

    pub fn venue_ref(&self, id: &str) -> Option<Ref> {
        let venue = self.snap.venue(id)?;
        Some(self.make_ref(
            RefKind::Venue,
            &venue.id,
            &venue.name,
            venue.prefecture.clone(),
            theme::NEUTRAL_KEY.to_string(),
        ))
    }

    /// 種別を問わない Ref。存在しない id (FK 孤児) は `None`。
    pub fn any_ref(&self, kind: RefKind, id: &str) -> Option<Ref> {
        match kind {
            RefKind::Event => self.event_ref(id),
            RefKind::Show => self.show_ref(id),
            RefKind::Song => self.song_ref(id),
            RefKind::Idol => self.idol_ref(id),
            RefKind::Unit => self.unit_ref(id),
            RefKind::Venue => self.venue_ref(id),
            RefKind::Brand => self.brand_ref(id),
        }
    }

    /// その公演のセトリの本数。
    ///
    /// `setlist()` を呼ぶと `SetlistEntryRecord` を全件組み立ててから捨てることになる。
    /// 数えるだけなら前計算済みの索引の長さで足りる。
    pub fn setlist_len(&self, show_id: &str) -> u32 {
        self.snap
            .show_index_by_id
            .get(show_id)
            .map_or(0, |&s| self.snap.setlist_items_by_show[s as usize].len() as u32)
    }

    /// その公演で何曲目か (1 始まり)。分からなければ 0。
    ///
    /// `setlist_items.position` は全体を通した連番なので、公演内での番号は
    /// 「その公演のセトリを並べたときの何番目か」で決まる
    /// (`setlist_items_by_show` は position 昇順で前計算済み)。
    pub fn setlist_number(&self, show_id: &str, position: i64) -> u32 {
        let Some(&show) = self.snap.show_index_by_id.get(show_id) else { return 0 };
        let items = &self.snap.setlist_items_by_show[show as usize];
        // `setlist_items_by_show` は position 昇順で前計算済みなので二分探索できる。
        items
            .binary_search_by_key(&position, |&i| self.snap.setlist_items[i as usize].position)
            .map_or(0, |i| i as u32 + 1)
    }

    // -----------------------------------------------------------------------
    // SEO
    // -----------------------------------------------------------------------

    /// OGP 画像。ブランドが決まるページはブランド別の絵にする。
    pub fn og_image(&self, brand_id: Option<&str>) -> String {
        match brand_id {
            Some(b) if self.brands.contains_key(b) => absolute(&format!("/og/{}.png", url_segment(b))),
            _ => absolute(content::DEFAULT_OG_IMAGE),
        }
    }

    /// `<head>` に入れるものとパンくず。
    ///
    /// パンくずは**末尾に自分自身を含める** (`<nav>` と JSON-LD の `BreadcrumbList` の
    /// 両方に同じ配列を使うので、自分が入っていないと構造化データとして意味を成さない)。
    ///
    /// `entity` は `@context` を持たないノード 1 個を渡す。ここで
    /// `{"@context": …, "@graph": [entity, BreadcrumbList]}` に組み直すので、
    /// **`<script type="application/ld+json">` は 1 ページに 1 個で済む**
    /// (複数書くと同じページの記述が別々の文書として読まれる)。
    pub fn seo(
        &self,
        title: &str,
        description: &str,
        path: &str,
        brand_id: Option<&str>,
        entity: serde_json::Value,
        breadcrumbs: Vec<Crumb>,
    ) -> SeoBlock {
        SeoBlock {
            title: page_title(title),
            description: description.to_string(),
            canonical: absolute(path),
            og_image: self.og_image(brand_id),
            robots: self.robots(brand_id),
            json_ld: json_ld_graph(entity, &breadcrumbs),
            breadcrumbs,
        }
    }

    pub fn crumb(name: &str, path: &str) -> Crumb {
        Crumb { name: name.to_string(), path: path.to_string() }
    }
}

/// 名前と URL だけの JSON-LD ノード。
///
/// 一覧・ブランド・会場・ユニット・アイドルは、出せる構造化データが「型・名前・URL」
/// だけで同じ形をしている。6 箇所で同じ 4 行を書くと、`@context` を 1 つだけ付け忘れる
/// といった差が出る (実際に `@graph` へ寄せるまで各所に散っていた)。
pub fn simple_json_ld(schema_type: &str, name: &str, path: &str) -> serde_json::Value {
    serde_json::json!({ "@type": schema_type, "name": name, "url": absolute(path) })
}

/// `@graph` にまとめた JSON-LD。
///
/// パンくずは `BreadcrumbList` として同じ文書に入れる。`position` は 1 始まり。
pub fn json_ld_graph(entity: serde_json::Value, breadcrumbs: &[Crumb]) -> serde_json::Value {
    let mut graph = vec![entity];
    if !breadcrumbs.is_empty() {
        graph.push(serde_json::json!({
            "@type": "BreadcrumbList",
            "itemListElement": breadcrumbs
                .iter()
                .enumerate()
                .map(|(i, c)| serde_json::json!({
                    "@type": "ListItem",
                    "position": i + 1,
                    "name": c.name,
                    "item": absolute(&c.path),
                }))
                .collect::<Vec<_>>(),
        }));
    }
    serde_json::json!({ "@context": "https://schema.org", "@graph": graph })
}

/// アバター代わりの 1 文字。
///
/// ブランドだけは表示名ではなく短縮名から取る (正式名は「アイドルマスター …」で
/// 揃っていて、先頭 1 文字が全部「ア」になり見分けが付かない)。名前が空の行は
/// 実データに無いが、その場合だけ空文字になる。
pub fn monogram_of(kind: RefKind, name: &str, sub: Option<&str>) -> String {
    let source = match kind {
        RefKind::Brand => sub.filter(|s| !s.is_empty()).unwrap_or(name),
        _ => name,
    };
    source.chars().next().map(|c| c.to_string()).unwrap_or_default()
}

/// 区切り規則と公演名の重なり落としは domain が持つ。ここは呼び出し側のための再輸出で、
/// web_export に規則の複製を作らないための入口。
pub use crate::domain::display_join::{join_parts, PARTS_SEPARATOR};
pub use crate::domain::show_naming::distinguishing_show_name;

/// `<title>` の形。サイト名を 2 回出さない (トップは `home.rs` が別に組む)。
pub fn page_title(title: &str) -> String {
    if title == content::SITE_NAME {
        format!("{} — {}", content::SITE_NAME, "アイマス ライブ・セトリ データベース")
    } else {
        format!("{title} | {}", content::SITE_NAME)
    }
}

/// 秒 → `"4:32"`。
pub fn duration_display(sec: i64) -> String {
    format!("{}:{:02}", sec / 60, sec % 60)
}
