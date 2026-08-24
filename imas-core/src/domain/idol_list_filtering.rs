//! アイドル一覧の絞り込み・並べ替えと、並び順メタ情報。
//!
//! iOS `IdolListFiltering.swift` (filterIdols / sortIdols / IdolSortOrder) の一次実装。
//! DB にも UI にも依存しない純粋ロジック (マーク集合・キャスト名は呼び出し側が
//! UserMarkService 等から解決済みで渡す) なので単体テスト可能。
//!
//! FFI 境界はエンティティ全体を渡さず、判定に要るフィールドの射影 ([`IdolListEntry`])
//! を渡して「採用/整列した index の列」を返す形にしている (1 ユーザー操作 = 1 FFI 呼び出し。
//! 呼び出し側は自国の配列を index で引き直す)。並び順ごとの既定方向・ラベル等の
//! メタ情報も、ケースごとの FFI 呼び出しループにならないよう [`sort_order_table`] で
//! 一括して返す。

use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};

/// アイドル一覧の並び順の種別。
///
/// 名前を iOS の `IdolSortOrder` に揃えていないのは意図的: 生成バインディングが
/// アプリと同一モジュールに入るため、既存 Swift enum (rawValue が `@AppStorage` の
/// 保存値・UI の CaseIterable 列挙として残る) と衝突する。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum IdolSortKind {
    /// 公式順 (sort_order)。ブランド別セクションのまま = 既定。
    Official,
    NameKana,
    Age,
    Height,
    Weight,
    Birthday,
    Debut,
}

/// 全種別 (メタ表の列挙用)。iOS の `CaseIterable.allCases` と同順。
pub const ALL_SORT_KINDS: [IdolSortKind; 7] = [
    IdolSortKind::Official,
    IdolSortKind::NameKana,
    IdolSortKind::Age,
    IdolSortKind::Height,
    IdolSortKind::Weight,
    IdolSortKind::Birthday,
    IdolSortKind::Debut,
];

/// 並び順 1 種のメタ情報。UI が表示・既定値に使う静的な知識。
#[derive(uniffi::Record, Clone, Debug)]
pub struct IdolSortOrderMeta {
    pub kind: IdolSortKind,
    /// 並び順そのものの表示名 (例: "五十音順")。iOS では enum rawValue として
    /// Swift 側にも重複して残る (`@AppStorage` の保存値なので Swift の顔から消せない)。
    pub display_name: String,
    /// 未指定時の並び方向。数値系は「大きい順」の方が知りたい形 (背が高い順・年上順)。
    pub default_ascending: bool,
    /// ブランド別セクションを維持するか。
    ///
    /// 公式順以外を選ぶと **ブランドの区切りを外した通し並び** になる。
    /// 「誰がいちばん背が高いか」はブランドを跨いで初めて意味を持つ指標で、
    /// ブランド別セクションの中で身長順にしても知りたいことが分からないため。
    pub keeps_brand_grouping: bool,
    /// 昇順の言い回し。並び順で変える: 「年齢を昇順」より「年下から」の方が読んで分かる。
    pub ascending_label: String,
    /// 降順の言い回し。
    pub descending_label: String,
}

/// メタ表を全種別ぶん返す。並びは [`ALL_SORT_KINDS`] (= iOS の allCases) と同順。
pub fn sort_order_table() -> Vec<IdolSortOrderMeta> {
    ALL_SORT_KINDS.iter().map(|&kind| meta(kind)).collect()
}

fn meta(kind: IdolSortKind) -> IdolSortOrderMeta {
    // (表示名, 昇順ラベル, 降順ラベル)。文言は iOS / Android で共有する一次定義。
    let (display, asc_label, desc_label) = match kind {
        IdolSortKind::Official => ("公式順", "公式順", "逆順"),
        IdolSortKind::NameKana => ("五十音順", "あ→ん", "ん→あ"),
        IdolSortKind::Age => ("年齢", "年下から", "年上から"),
        IdolSortKind::Height => ("身長", "低い順", "高い順"),
        IdolSortKind::Weight => ("体重", "軽い順", "重い順"),
        IdolSortKind::Birthday => ("誕生日", "1月から", "12月から"),
        IdolSortKind::Debut => ("デビュー日", "古い順", "新しい順"),
    };
    IdolSortOrderMeta {
        kind,
        display_name: display.to_string(),
        default_ascending: default_ascending(kind),
        keeps_brand_grouping: kind == IdolSortKind::Official,
        ascending_label: asc_label.to_string(),
        descending_label: desc_label.to_string(),
    }
}

/// 未指定時の並び方向。数値系 (年齢・身長・体重) だけ降順。
fn default_ascending(kind: IdolSortKind) -> bool {
    !matches!(kind, IdolSortKind::Age | IdolSortKind::Height | IdolSortKind::Weight)
}

/// アイドル 1 人の射影。絞り込み (id・ブランド・属性・検索対象の名前群) と
/// 並べ替え (公式順・数値キー・文字列キー) の判定に必要なフィールドだけを持つ。
#[derive(uniffi::Record, Clone, Debug)]
pub struct IdolListEntry {
    pub idol_id: String,
    pub brand_id: String,
    pub name: String,
    /// 読みがな。無ければ 50 音並び・検索とも `name` で代用する。
    pub name_kana: Option<String>,
    /// 愛称 (表示名と別に持つアイドルがいる)。検索対象。
    pub nickname: Option<String>,
    /// 別名 (フルネーム・旧名・ステージ名) のカンマ区切り生値。分割はこちらで行う。
    /// 表示名を短くしたアイドル (レトラ = サラ・レトラ・オリヴェイラ・ウタガワ) が
    /// フルネームで検索できなくなるのを防ぐため検索対象に含める。
    pub aliases: Option<String>,
    /// ブランド内サブ属性 (cute/cool/passion 等)。
    pub attribute: Option<String>,
    /// 公式順。同値時の安定化にも使う。
    pub sort_order: i64,
    pub age: Option<i64>,
    pub height: Option<f64>,
    pub weight: Option<f64>,
    /// 誕生日 `"--MM-DD"` (年なし)。文字列比較がそのまま月日順になる。
    pub birthday: Option<String>,
    /// 実装(初登場)日 `"yyyy-MM-dd"`。文字列比較がそのまま日付順になる。
    pub debut_date: Option<String>,
}

/// アイドル一覧の絞り込みに必要な、解決済みの条件・集合。
///
/// FFI (uniffi::Record) 越しに渡すため集合は `Vec` で受け、内部で `HashSet` 化する。
/// iOS 既存 struct `IdolFilterContext` との名前衝突を避けて Criteria と呼ぶ。
#[derive(uniffi::Record, Clone, Debug, Default)]
pub struct IdolListFilterCriteria {
    /// 選択ブランド (空 = 全ブランド)。
    pub selected_brand_ids: Vec<String>,
    /// ブランド内サブ属性 (cute/cool/passion 等)。None = 属性絞り込みなし。
    pub selected_attribute: Option<String>,
    pub require_my_pick: bool,
    pub my_pick_ids: Vec<String>,
    pub require_favorite: bool,
    pub favorite_ids: Vec<String>,
    pub require_note: bool,
    pub note_ids: Vec<String>,
    /// 名前/かな/キャスト名/別名/愛称の部分一致検索 (空 = 検索なし)。
    pub search_text: String,
    /// idol_id → キャスト(声優)名。検索対象に含める。
    pub cast_names: HashMap<String, String>,
}

/// ブランド/属性/マイマーク/テキスト検索の絞り込みを適用し、採用した index 列を返す。
///
/// index は `entries` の添字で、入力順を保持する (並べ替えは [`sort_idol_list`] が担う)。
/// マーク系条件は AND (すべて満たすものだけ残す)。
pub fn filter_idol_list(entries: &[IdolListEntry], criteria: &IdolListFilterCriteria) -> Vec<u32> {
    let brands: HashSet<&str> = criteria.selected_brand_ids.iter().map(String::as_str).collect();
    let my_picks: HashSet<&str> = criteria.my_pick_ids.iter().map(String::as_str).collect();
    let favorites: HashSet<&str> = criteria.favorite_ids.iter().map(String::as_str).collect();
    let notes: HashSet<&str> = criteria.note_ids.iter().map(String::as_str).collect();
    // 検索語は 1 回だけ小文字化して全行で使い回す (行ごとに畳み込まない)。
    // iOS 原本は query を trim しない (空白込みで一致を見る) のでここでも trim しない。
    let query_lower =
        (!criteria.search_text.is_empty()).then(|| criteria.search_text.to_lowercase());

    entries
        .iter()
        .enumerate()
        .filter(|(_, e)| {
            let id = e.idol_id.as_str();
            (brands.is_empty() || brands.contains(e.brand_id.as_str()))
                && criteria
                    .selected_attribute
                    .as_deref()
                    .is_none_or(|attr| e.attribute.as_deref() == Some(attr))
                && (!criteria.require_my_pick || my_picks.contains(id))
                && (!criteria.require_favorite || favorites.contains(id))
                && (!criteria.require_note || notes.contains(id))
                && query_lower
                    .as_deref()
                    .is_none_or(|q| matches_search(e, &criteria.cast_names, q))
        })
        .map(|(i, _)| i as u32)
        .collect()
}

/// 検索語 (小文字化済み) が名前/かな/キャスト名/別名/愛称のどれかに部分一致するか。
///
/// iOS 原本の `localizedCaseInsensitiveContains` に相当する大文字小文字無視の部分一致。
/// こちらは Unicode 標準の小文字化 + 部分一致で、ロケール固有の照合規則
/// (合成済み/結合文字の正準等価など) は見ない。DB もキーボード入力も NFC の
/// 日本語/ASCII なので実用上の差は出ない。
fn matches_search(entry: &IdolListEntry, cast_names: &HashMap<String, String>, query_lower: &str) -> bool {
    contains_ci(&entry.name, query_lower)
        || entry.name_kana.as_deref().is_some_and(|s| contains_ci(s, query_lower))
        || cast_names.get(&entry.idol_id).is_some_and(|s| contains_ci(s, query_lower))
        || alias_list(entry.aliases.as_deref()).any(|alias| contains_ci(alias, query_lower))
        || entry.nickname.as_deref().is_some_and(|s| contains_ci(s, query_lower))
}

fn contains_ci(haystack: &str, needle_lower: &str) -> bool {
    haystack.to_lowercase().contains(needle_lower)
}

/// 別名カンマ区切りの分割規則 (iOS `Idol.aliasList` と同一): 前後空白 trim・空要素除外。
fn alias_list(aliases: Option<&str>) -> impl Iterator<Item = &str> {
    aliases
        .unwrap_or("")
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
}

/// 指定の並び順で整列した index 列を返す。`ascending` が None なら既定方向。
///
/// 固定する不変条件 (iOS `IdolListSortingTests` と共有):
/// - 値が無いアイドル (年齢・身長 未設定の外部ゲスト等) は **並び方向に関わらず必ず末尾**。
///   昇順で先頭に空欄が並ぶと「若い順」を見に来た人の視界を潰すため。
/// - 同値は公式順 (sort_order) で安定させる (再描画で順序が入れ替わらない)。
pub fn sort_idol_list(
    entries: &[IdolListEntry],
    kind: IdolSortKind,
    ascending: Option<bool>,
) -> Vec<u32> {
    let asc = ascending.unwrap_or_else(|| default_ascending(kind));
    let mut indices: Vec<u32> = (0..entries.len() as u32).collect();

    if kind == IdolSortKind::Official {
        indices.sort_by(|&l, &r| {
            let ord = entries[l as usize].sort_order.cmp(&entries[r as usize].sort_order);
            if asc { ord } else { ord.reverse() }
        });
        return indices;
    }

    indices.sort_by(|&l, &r| compare_entries(&entries[l as usize], &entries[r as usize], kind, asc));
    indices
}

/// 数値キー (年齢・身長・体重)。None = 値なし → 末尾送りの判定に使う。
fn numeric_key(entry: &IdolListEntry, kind: IdolSortKind) -> Option<f64> {
    match kind {
        IdolSortKind::Age => entry.age.map(|a| a as f64),
        IdolSortKind::Height => entry.height,
        IdolSortKind::Weight => entry.weight,
        _ => None,
    }
}

/// 文字列キー (五十音・誕生日・デビュー日)。空文字は「値なし」に倒す
/// (iOS 原本の `!l.isEmpty` ガードと `hasValue` の空文字判定を一本化)。
fn string_key(entry: &IdolListEntry, kind: IdolSortKind) -> Option<&str> {
    let key = match kind {
        // 読みがな未設定は表示名で代用 (空の読みがなは代用しない = 値なし扱い。iOS と同じ)。
        IdolSortKind::NameKana => Some(entry.name_kana.as_deref().unwrap_or(&entry.name)),
        IdolSortKind::Birthday => entry.birthday.as_deref(),
        IdolSortKind::Debut => entry.debut_date.as_deref(),
        _ => None,
    };
    key.filter(|s| !s.is_empty())
}

/// 公式順以外の比較。値あり同士はキー比較 (同値は公式順)、片方だけ値なしなら
/// 値ありを常に前へ、両方値なしなら公式順。
fn compare_entries(l: &IdolListEntry, r: &IdolListEntry, kind: IdolSortKind, asc: bool) -> Ordering {
    let official_tie = || l.sort_order.cmp(&r.sort_order);

    if let (Some(lk), Some(rk)) = (numeric_key(l, kind), numeric_key(r, kind)) {
        // total_cmp で全順序を保証する (NaN が紛れても比較器の契約を壊さない)。
        let ord = lk.total_cmp(&rk);
        if ord != Ordering::Equal {
            return if asc { ord } else { ord.reverse() };
        }
        return official_tie();
    }
    if let (Some(lk), Some(rk)) = (string_key(l, kind), string_key(r, kind)) {
        // コードポイント順。DB の読みがなは NFC のひらがな、誕生日/デビュー日は
        // ゼロ埋めの ISO 形式なので、これがそのまま 50 音順・日付順になる。
        let ord = lk.cmp(rk);
        if ord != Ordering::Equal {
            return if asc { ord } else { ord.reverse() };
        }
        return official_tie();
    }

    // 片方だけ値なし → 値ありを常に前に (並び方向に関わらず)。
    let l_has = numeric_key(l, kind).is_some() || string_key(l, kind).is_some();
    let r_has = numeric_key(r, kind).is_some() || string_key(r, kind).is_some();
    if l_has != r_has {
        return if l_has { Ordering::Less } else { Ordering::Greater };
    }
    official_tie()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 全フィールド既定値の射影 (iOS テストの `makeIdol` 相当)。
    fn entry(id: &str) -> IdolListEntry {
        IdolListEntry {
            idol_id: id.to_string(),
            brand_id: "cg".to_string(),
            name: id.to_string(),
            name_kana: None,
            nickname: None,
            aliases: None,
            attribute: None,
            sort_order: 0,
            age: None,
            height: None,
            weight: None,
            birthday: None,
            debut_date: None,
        }
    }

    fn vec_of(ids: &[&str]) -> Vec<String> {
        ids.iter().map(|s| s.to_string()).collect()
    }

    /// index 列を idol_id 列へ引き直す (iOS テストの `.map(\.id)` 相当)。
    fn picked_ids(entries: &[IdolListEntry], indices: &[u32]) -> Vec<String> {
        indices.iter().map(|&i| entries[i as usize].idol_id.clone()).collect()
    }

    fn sorted_ids(entries: &[IdolListEntry], kind: IdolSortKind, asc: Option<bool>) -> Vec<String> {
        picked_ids(entries, &sort_idol_list(entries, kind, asc))
    }

    // ---- 絞り込み (iOS IdolListFilteringTests の移植) ----

    #[test]
    fn brand_filter() {
        let mut a = entry("a");
        a.brand_id = "cg".to_string();
        let mut b = entry("b");
        b.brand_id = "ml".to_string();
        let idols = [a, b];
        let ctx = IdolListFilterCriteria {
            selected_brand_ids: vec_of(&["ml"]),
            ..Default::default()
        };
        assert_eq!(picked_ids(&idols, &filter_idol_list(&idols, &ctx)), vec_of(&["b"]));
    }

    #[test]
    fn attribute_filter() {
        let mut a = entry("a");
        a.attribute = Some("cute".to_string());
        let mut b = entry("b");
        b.attribute = Some("cool".to_string());
        // 属性未設定は属性絞り込みで残らない (== 比較なので None は不一致)。
        let c = entry("c");
        let idols = [a, b, c];
        let ctx = IdolListFilterCriteria {
            selected_attribute: Some("cool".to_string()),
            ..Default::default()
        };
        assert_eq!(picked_ids(&idols, &filter_idol_list(&idols, &ctx)), vec_of(&["b"]));
    }

    #[test]
    fn mark_filters_are_and_conditions() {
        let idols = [entry("a"), entry("b"), entry("c")];
        let ctx = IdolListFilterCriteria {
            require_favorite: true,
            favorite_ids: vec_of(&["a", "b"]),
            require_my_pick: true,
            my_pick_ids: vec_of(&["b", "c"]),
            ..Default::default()
        };
        // AND: fav={a,b} と pick={b,c} の積 → b のみ
        assert_eq!(picked_ids(&idols, &filter_idol_list(&idols, &ctx)), vec_of(&["b"]));
    }

    #[test]
    fn search_matches_cast_name() {
        let mut a = entry("a");
        a.name = "島村卯月".to_string();
        let mut b = entry("b");
        b.name = "渋谷凛".to_string();
        let idols = [a, b];

        // 名前には無いがキャスト名で一致させたい検索語。まずどちらのキャストにも無い → 0 件
        let mut ctx = IdolListFilterCriteria {
            search_text: "おおぬま".to_string(),
            cast_names: HashMap::from([
                ("a".to_string(), "大橋彩香".to_string()),
                ("b".to_string(), "福原綾香".to_string()),
            ]),
            ..Default::default()
        };
        assert!(filter_idol_list(&idols, &ctx).is_empty());

        ctx.cast_names.insert("a".to_string(), "おおぬま某".to_string());
        assert_eq!(picked_ids(&idols, &filter_idol_list(&idols, &ctx)), vec_of(&["a"]));
    }

    /// 表示名を短くしたアイドルを、別名 (フルネーム) でも引けること。
    /// レトラは表示名を「レトラ」に縮め、「サラ・レトラ・オリヴェイラ・ウタガワ」を
    /// aliases に退避した。検索が name しか見ていないとフルネームで辿れなくなる。
    #[test]
    fn search_matches_alias() {
        let mut retla = entry("retla");
        retla.name = "レトラ".to_string();
        retla.name_kana = Some("れとら".to_string());
        retla.aliases =
            Some("サラ・レトラ・オリヴェイラ・ウタガワ,さら・れとら・おりゔぇいら・うたがわ".to_string());
        let mut other = entry("other");
        other.name = "渋谷凛".to_string();
        let idols = [retla, other];

        let mut ctx = IdolListFilterCriteria::default();

        ctx.search_text = "オリヴェイラ".to_string();
        assert_eq!(
            picked_ids(&idols, &filter_idol_list(&idols, &ctx)),
            vec_of(&["retla"]),
            "別名の一部で引けること"
        );

        ctx.search_text = "おりゔぇいら".to_string();
        assert_eq!(
            picked_ids(&idols, &filter_idol_list(&idols, &ctx)),
            vec_of(&["retla"]),
            "別名のよみでも引けること"
        );

        ctx.search_text = "レトラ".to_string();
        assert_eq!(
            picked_ids(&idols, &filter_idol_list(&idols, &ctx)),
            vec_of(&["retla"]),
            "表示名でも従来どおり引けること"
        );
    }

    /// 愛称でも引けること (nickname は表示名と別に持つアイドルがいる)。
    #[test]
    fn search_matches_nickname() {
        let mut meg = entry("meg");
        meg.name = "ウィーン・マルガレーテ".to_string();
        meg.nickname = Some("メグ".to_string());
        let idols = [meg];
        let ctx = IdolListFilterCriteria {
            search_text: "メグ".to_string(),
            ..Default::default()
        };
        assert_eq!(picked_ids(&idols, &filter_idol_list(&idols, &ctx)), vec_of(&["meg"]));
    }

    /// 大文字小文字を無視して一致すること (iOS `localizedCaseInsensitiveContains` 相当)。
    #[test]
    fn search_is_case_insensitive() {
        let mut a = entry("a");
        a.name = "Juliet".to_string();
        let idols = [a];
        let ctx = IdolListFilterCriteria {
            search_text: "JULIET".to_string(),
            ..Default::default()
        };
        assert_eq!(picked_ids(&idols, &filter_idol_list(&idols, &ctx)), vec_of(&["a"]));
    }

    /// 別名分割は前後空白 trim・空要素除外 (iOS `Idol.aliasList` と同じ規則)。
    #[test]
    fn alias_split_trims_and_drops_empties() {
        let items: Vec<&str> = alias_list(Some(" ロコ , , 伴田路子 ,")).collect();
        assert_eq!(items, vec!["ロコ", "伴田路子"]);
        assert_eq!(alias_list(None).count(), 0);
        assert_eq!(alias_list(Some("")).count(), 0);
    }

    /// 条件が空なら全件が入力順のまま残る。
    #[test]
    fn empty_criteria_passes_through_in_order() {
        let idols = [entry("a"), entry("b"), entry("c")];
        assert_eq!(
            picked_ids(&idols, &filter_idol_list(&idols, &IdolListFilterCriteria::default())),
            vec_of(&["a", "b", "c"])
        );
    }

    // ---- 並べ替え (iOS IdolListSortingTests の移植) ----

    #[test]
    fn age_defaults_to_oldest_first() {
        let mut a = entry("a");
        a.age = Some(15);
        let mut b = entry("b");
        b.age = Some(32);
        let mut c = entry("c");
        c.age = Some(21);
        let idols = [a, b, c];
        assert_eq!(sorted_ids(&idols, IdolSortKind::Age, None), vec_of(&["b", "c", "a"]));
    }

    #[test]
    fn age_ascending_is_youngest_first() {
        let mut a = entry("a");
        a.age = Some(15);
        let mut b = entry("b");
        b.age = Some(32);
        let mut c = entry("c");
        c.age = Some(21);
        let idols = [a, b, c];
        assert_eq!(sorted_ids(&idols, IdolSortKind::Age, Some(true)), vec_of(&["a", "c", "b"]));
    }

    #[test]
    fn age_missing_values_go_last_regardless_of_direction() {
        let none1 = entry("none1");
        let mut young = entry("young");
        young.age = Some(12);
        let none2 = entry("none2");
        let mut old = entry("old");
        old.age = Some(30);
        let idols = [none1, young, none2, old];

        let desc = sorted_ids(&idols, IdolSortKind::Age, Some(false));
        assert_eq!(&desc[..2], &vec_of(&["old", "young"])[..]);
        let mut tail: Vec<_> = desc[2..].to_vec();
        tail.sort();
        assert_eq!(tail, vec_of(&["none1", "none2"]));

        let asc = sorted_ids(&idols, IdolSortKind::Age, Some(true));
        assert_eq!(&asc[..2], &vec_of(&["young", "old"])[..], "昇順でも値なしが先頭に来てはいけない");
        let mut tail: Vec<_> = asc[2..].to_vec();
        tail.sort();
        assert_eq!(tail, vec_of(&["none1", "none2"]));
    }

    #[test]
    fn height_defaults_to_tallest_first() {
        let mut s = entry("s");
        s.height = Some(140.0);
        let mut t = entry("t");
        t.height = Some(191.0);
        let mut m = entry("m");
        m.height = Some(158.0);
        let idols = [s, t, m];
        assert_eq!(sorted_ids(&idols, IdolSortKind::Height, None), vec_of(&["t", "m", "s"]));
    }

    #[test]
    fn weight_ascending_is_lightest_first() {
        let mut h = entry("h");
        h.weight = Some(52.0);
        let mut l = entry("l");
        l.weight = Some(30.0);
        let mut m = entry("m");
        m.weight = Some(41.0);
        let idols = [h, l, m];
        assert_eq!(sorted_ids(&idols, IdolSortKind::Weight, Some(true)), vec_of(&["l", "m", "h"]));
    }

    #[test]
    fn name_kana_ascending() {
        let mut c = entry("c");
        c.name_kana = Some("うえの".to_string());
        let mut a = entry("a");
        a.name_kana = Some("あまみ".to_string());
        let mut b = entry("b");
        b.name_kana = Some("いおり".to_string());
        let idols = [c, a, b];
        assert_eq!(sorted_ids(&idols, IdolSortKind::NameKana, None), vec_of(&["a", "b", "c"]));
    }

    /// 読みがな未設定は表示名で代用する。空文字の読みがなは代用せず末尾送り
    /// (iOS の `nameKana ?? name` + 空文字ガードと同じ振る舞い)。
    #[test]
    fn name_kana_falls_back_to_name_and_empty_goes_last() {
        let mut no_kana = entry("no_kana");
        no_kana.name = "あいうえお".to_string(); // name 代用で先頭に来るはず
        let mut empty_kana = entry("empty_kana");
        empty_kana.name_kana = Some(String::new());
        let mut normal = entry("normal");
        normal.name_kana = Some("かきくけこ".to_string());
        let idols = [empty_kana, normal, no_kana];
        assert_eq!(
            sorted_ids(&idols, IdolSortKind::NameKana, None),
            vec_of(&["no_kana", "normal", "empty_kana"])
        );
    }

    #[test]
    fn birthday_ascending_starts_from_january() {
        let mut dec = entry("dec");
        dec.birthday = Some("--12-01".to_string());
        let mut jan = entry("jan");
        jan.birthday = Some("--01-03".to_string());
        let mut jul = entry("jul");
        jul.birthday = Some("--07-17".to_string());
        let idols = [dec, jan, jul];
        assert_eq!(sorted_ids(&idols, IdolSortKind::Birthday, None), vec_of(&["jan", "jul", "dec"]));
    }

    #[test]
    fn debut_descending_is_newest_first() {
        let mut old = entry("old");
        old.debut_date = Some("2011-11-28".to_string());
        let mut new = entry("new");
        new.debut_date = Some("2019-01-10".to_string());
        let mut mid = entry("mid");
        mid.debut_date = Some("2014-02-19".to_string());
        let idols = [old, new, mid];
        assert_eq!(
            sorted_ids(&idols, IdolSortKind::Debut, Some(false)),
            vec_of(&["new", "mid", "old"])
        );
    }

    #[test]
    fn birthday_missing_values_go_last() {
        let none = entry("none");
        let mut jan = entry("jan");
        jan.birthday = Some("--01-03".to_string());
        let idols = [none, jan];
        assert_eq!(sorted_ids(&idols, IdolSortKind::Birthday, None), vec_of(&["jan", "none"]));
    }

    #[test]
    fn ties_fall_back_to_official_order() {
        let mut third = entry("third");
        third.sort_order = 30;
        third.age = Some(17);
        let mut first = entry("first");
        first.sort_order = 10;
        first.age = Some(17);
        let mut second = entry("second");
        second.sort_order = 20;
        second.age = Some(17);
        let idols = [third, first, second];
        // 全員同い年 → 公式順で安定させる (再描画で入れ替わらない)
        assert_eq!(
            sorted_ids(&idols, IdolSortKind::Age, None),
            vec_of(&["first", "second", "third"])
        );
    }

    #[test]
    fn official_order_uses_sort_order() {
        let mut b = entry("b");
        b.sort_order = 2;
        let mut a = entry("a");
        a.sort_order = 1;
        let mut c = entry("c");
        c.sort_order = 3;
        let idols = [b, a, c];
        assert_eq!(sorted_ids(&idols, IdolSortKind::Official, None), vec_of(&["a", "b", "c"]));
        // 逆順 (descendingLabel「逆順」) も公式順キーで反転するだけ。
        assert_eq!(
            sorted_ids(&idols, IdolSortKind::Official, Some(false)),
            vec_of(&["c", "b", "a"])
        );
    }

    // ---- メタ表 ----

    #[test]
    fn only_official_keeps_brand_grouping() {
        for meta in sort_order_table() {
            assert_eq!(
                meta.keeps_brand_grouping,
                meta.kind == IdolSortKind::Official,
                "{:?} は通し並びであるべき",
                meta.kind
            );
        }
    }

    /// 数値系 (年齢・身長・体重) だけ既定降順。「大きい順」の方が知りたい形のため。
    #[test]
    fn numeric_kinds_default_to_descending() {
        for meta in sort_order_table() {
            let expect_desc = matches!(
                meta.kind,
                IdolSortKind::Age | IdolSortKind::Height | IdolSortKind::Weight
            );
            assert_eq!(meta.default_ascending, !expect_desc, "{:?}", meta.kind);
        }
    }

    /// メタ表は全種別を 1 回ずつ・宣言順に含む (Swift 側はこの表から辞書を組む契約)。
    #[test]
    fn table_covers_every_kind_once_in_declaration_order() {
        let kinds: Vec<IdolSortKind> = sort_order_table().iter().map(|m| m.kind).collect();
        assert_eq!(kinds, ALL_SORT_KINDS.to_vec());
    }

    /// ラベル文言は iOS 原本 (`IdolSortOrder` の rawValue / ascendingLabel / descendingLabel)
    /// と一字一句同じであること。UI 文言の一次定義がこの表になる。
    #[test]
    fn labels_match_ios_wording() {
        let expected = [
            ("公式順", "公式順", "逆順"),
            ("五十音順", "あ→ん", "ん→あ"),
            ("年齢", "年下から", "年上から"),
            ("身長", "低い順", "高い順"),
            ("体重", "軽い順", "重い順"),
            ("誕生日", "1月から", "12月から"),
            ("デビュー日", "古い順", "新しい順"),
        ];
        for (meta, (display, asc, desc)) in sort_order_table().iter().zip(expected) {
            assert_eq!(meta.display_name, display);
            assert_eq!(meta.ascending_label, asc);
            assert_eq!(meta.descending_label, desc);
        }
    }
}
