//! アイマス関連の収支 (家計簿) の規則と集計。純粋ロジック。
//!
//! 「この趣味にいくら使ったか」を出すための帳簿。1 件の支出は
//! **日付・費目・金額**を必ず持ち、任意で公演に紐づく。紐づけると
//! 「この遠征でいくら使ったか」が出て、紐づけない支出 (ソシャゲの課金・
//! グッズの通販) も同じ帳簿に並ぶ。
//!
//! # ここに置くもの
//!
//! 費目の定義と並び・入力の検査・期間の括り (月/年)・費目別と公演別の集計・
//! 金額の表記。**どれも「判断」なので各 OS に書かない**。iOS と Android で
//! 費目の並びや丸め方が食い違うと、同じ帳簿が端末ごとに違う額を出す。
//!
//! # 金額は整数の円で持つ
//!
//! 小数を使わない。円に小数点以下が無いのに f64 で持つと、集計のたびに
//! 誤差が乗って「合計が 1 円合わない」が起きる。入力も整数だけ受ける。
//!
//! # FFI の粒度
//!
//! 帳簿ぜんぶ (数百〜数千件) を **1 回**で渡して、集計済みの箱を返す。

use std::collections::HashMap;

/// 費目。ユーザーが増やせる類のものではなく、**集計の軸**なので固定で持つ。
/// 足りないものは [`ExpenseCategory::Other`] + メモで受ける。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ExpenseCategory {
    /// チケット代 (公演・先行手数料込み)。
    Ticket,
    /// 交通費 (新幹線・飛行機・現地の移動)。
    Transport,
    /// 宿代。
    Lodging,
    /// グッズ代。
    Goods,
    /// ゲームの課金。
    InGame,
    /// UO・ペンライト・電池。依頼の言い方に合わせてラベルは「UO代」。
    Penlight,
    /// 打ち上げ代。
    Party,
    /// 飲食代 (打ち上げ以外)。
    Food,
    /// その他。
    Other,
}

/// 費目 1 つの見せ方。ラベルと並び順は**ここが唯一の出どころ**。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ExpenseCategoryInfo {
    pub category: ExpenseCategory,
    /// 保存値 (DB の `expenses.category`)。ラベルを変えても記録が迷子にならないよう、
    /// 保存には**この英字キー**を使う。
    pub key: String,
    pub label: String,
    /// 遠征の費用としてまとめて見たい費目か (チケット・交通・宿)。
    ///
    /// 「遠征 1 回にいくらかかったか」は交通と宿が支配的で、課金やグッズとは
    /// 性質が違う。同じ帳簿に入れたまま、集計だけ分けられるようにしておく。
    pub is_travel: bool,
}

/// 帳簿の 1 件。各 OS が DB から射影して渡す。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ExpenseEntry {
    pub id: String,
    /// `YYYY-MM-DD`。
    pub date: String,
    pub category: ExpenseCategory,
    /// 円。負数は入れない (入力の検査で弾く)。
    pub amount: i64,
    /// 紐づく公演 (`shows.id`)。無ければ単独の支出。
    pub show_id: Option<String>,
    /// 紐づく公演が属するイベント (`events.id`)。公演別の集計をイベントで束ねるのに使う。
    pub event_id: Option<String>,
    /// 画面に出す公演名 (「<イベント名> <公演名>」など)。表記は各 OS が組んで渡す。
    pub show_label: Option<String>,
    pub note: Option<String>,
}

/// 期間の括り。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum LedgerPeriod {
    Month,
    Year,
    /// 括らずに全期間で 1 つ。
    All,
}

/// 公演との紐づきで絞る。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum LedgerLinkage {
    All,
    /// 公演に紐づく支出だけ (遠征の費用)。
    LinkedOnly,
    /// 公演に紐づかない支出だけ (課金・通販)。
    UnlinkedOnly,
}

/// 帳簿の絞り込み。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LedgerFilter {
    /// `YYYY` で年を絞る。空なら絞らない。
    pub year: String,
    /// 空なら全費目。
    pub categories: Vec<ExpenseCategory>,
    pub linkage: LedgerLinkage,
    /// イベント (`events.id`) で絞る。空なら絞らない。
    pub event_id: String,
}

/// 費目ごとの小計。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CategoryTotal {
    pub category: ExpenseCategory,
    pub label: String,
    pub total: i64,
    pub count: u32,
    /// 全体に対する割合 (%)。帯グラフの長さに使う。四捨五入した整数。
    pub percent: u32,
}

/// 期間 1 つぶん。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LedgerBucket {
    /// 並べ替え用のキー (`2026-09` / `2026` / `all`)。
    pub key: String,
    /// 画面に出す見出し (`2026年9月` / `2026年` / `全期間`)。
    pub label: String,
    pub total: i64,
    pub count: u32,
    pub by_category: Vec<CategoryTotal>,
    /// この箱に入る明細の id (絞り込み後・元の並び順のまま)。
    ///
    /// 「どの明細がどの箱に入るか」はここに出た規則 (絞り込み + 日付の頭で括る) が
    /// 唯一の出どころ。各 OS はこの id 列で元の配列を引くだけにして、
    /// 同じ規則を画面側で書き直さない (書き直すと iOS と Android で必ず食い違う)。
    pub entry_ids: Vec<String>,
}

/// 公演 1 つぶんの合計 (「この遠征でいくら使ったか」)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ShowTotal {
    pub show_id: String,
    pub label: String,
    /// その公演に紐づく支出のうち、一番早い日付 (並べ替えに使う)。
    pub date: String,
    pub total: i64,
    pub count: u32,
    pub by_category: Vec<CategoryTotal>,
}

/// 帳簿の集計結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LedgerSummary {
    pub total: i64,
    pub count: u32,
    /// 遠征の費用 (チケット・交通・宿) の合計。
    pub travel_total: i64,
    /// 公演に紐づく支出の合計。
    pub linked_total: i64,
    /// 紐づいた公演の数。「1 公演あたり」を出す分母。
    pub show_count: u32,
    /// 1 公演あたりの平均 (紐づく支出のみ / 公演数)。公演が 0 なら 0。
    pub average_per_show: i64,
    pub buckets: Vec<LedgerBucket>,
    pub by_category: Vec<CategoryTotal>,
}

/// 入力の弾き方。画面に出す文言は各 OS が決める。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExpenseInputError {
    /// 日付が `YYYY-MM-DD` でない。
    BadDate,
    /// 金額が 0 以下。
    NotPositive,
    /// 金額が桁あふれしている (1 件 1 億円以上は打ち間違い)。
    TooLarge,
}

/// 1 件で受け付ける上限。これを超える入力は桁の打ち間違いとして弾く。
const MAX_AMOUNT: i64 = 100_000_000;

/// 費目の一覧。**並び順もここで決める** (画面の並びが端末で食い違わないように)。
pub fn expense_categories() -> Vec<ExpenseCategoryInfo> {
    use ExpenseCategory::*;
    [
        (Ticket, "ticket", "チケット代", true),
        (Transport, "transport", "交通費", true),
        (Lodging, "lodging", "宿代", true),
        (Goods, "goods", "グッズ代", false),
        (InGame, "ingame", "課金代", false),
        (Penlight, "penlight", "UO代", false),
        (Party, "party", "打ち上げ代", false),
        (Food, "food", "飲食代", false),
        (Other, "other", "その他", false),
    ]
    .into_iter()
    .map(|(category, key, label, is_travel)| ExpenseCategoryInfo {
        category,
        key: key.to_string(),
        label: label.to_string(),
        is_travel,
    })
    .collect()
}

/// 保存値 (英字キー) から費目へ。知らないキーは [`ExpenseCategory::Other`] に落とす
/// — 将来費目を増やした端末のバックアップを古い端末で開いても、金額が消えないように。
pub fn expense_category_from_key(key: &str) -> ExpenseCategory {
    expense_categories()
        .into_iter()
        .find(|c| c.key == key)
        .map(|c| c.category)
        .unwrap_or(ExpenseCategory::Other)
}

/// 費目から保存値へ。
pub fn expense_category_key(category: ExpenseCategory) -> String {
    info_of(category).key
}

/// 費目の表示名。
pub fn expense_category_label(category: ExpenseCategory) -> String {
    info_of(category).label
}

fn info_of(category: ExpenseCategory) -> ExpenseCategoryInfo {
    expense_categories()
        .into_iter()
        .find(|c| c.category == category)
        // 一覧に必ず居る (足したら一覧にも足す) ので、ここには来ない。
        .unwrap_or(ExpenseCategoryInfo {
            category,
            key: "other".into(),
            label: "その他".into(),
            is_travel: false,
        })
}

/// 金額の表記。`12345` → `¥12,345`。負数は頭に `-` を付ける。
pub fn format_yen(amount: i64) -> String {
    let sign = if amount < 0 { "-" } else { "" };
    let digits = amount.unsigned_abs().to_string();
    let mut grouped = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            grouped.push(',');
        }
        grouped.push(c);
    }
    format!("{sign}¥{grouped}")
}

/// 入力の検査。通れば `None`。
pub fn validate_expense(date: &str, amount: i64) -> Option<ExpenseInputError> {
    if !is_ymd(date) {
        return Some(ExpenseInputError::BadDate);
    }
    if amount <= 0 {
        return Some(ExpenseInputError::NotPositive);
    }
    if amount >= MAX_AMOUNT {
        return Some(ExpenseInputError::TooLarge);
    }
    None
}

/// `YYYY-MM-DD` か。月日の値域まで見る (`2026-13-40` を通さない)。
fn is_ymd(date: &str) -> bool {
    let parts: Vec<&str> = date.split('-').collect();
    if parts.len() != 3 {
        return false;
    }
    let lens = [4, 2, 2];
    for (part, len) in parts.iter().zip(lens) {
        if part.len() != len || !part.chars().all(|c| c.is_ascii_digit()) {
            return false;
        }
    }
    let month: u32 = parts[1].parse().unwrap_or(0);
    let day: u32 = parts[2].parse().unwrap_or(0);
    (1..=12).contains(&month) && (1..=31).contains(&day)
}

/// 帳簿を集計する。絞り込みも並びもここで完結させる
/// (各 OS は返ってきた配列をそのまま描くだけにする)。
///
/// 期間の箱は**新しい順**。費目の内訳は金額の多い順で、同額なら
/// [`expense_categories`] の並び順にそろえる (端末で並びが揺れないように)。
pub fn build_ledger_summary(
    entries: &[ExpenseEntry],
    period: LedgerPeriod,
    filter: &LedgerFilter,
) -> LedgerSummary {
    let kept: Vec<&ExpenseEntry> = entries.iter().filter(|e| keeps(e, filter)).collect();

    let total: i64 = kept.iter().map(|e| e.amount).sum();
    let travel_total: i64 = kept
        .iter()
        .filter(|e| info_of(e.category).is_travel)
        .map(|e| e.amount)
        .sum();
    let linked: Vec<&&ExpenseEntry> = kept.iter().filter(|e| linked_show(e).is_some()).collect();
    let linked_total: i64 = linked.iter().map(|e| e.amount).sum();
    let show_count = linked
        .iter()
        .filter_map(|e| linked_show(e))
        .collect::<std::collections::HashSet<_>>()
        .len() as u32;

    let mut by_bucket: HashMap<String, Vec<&ExpenseEntry>> = HashMap::new();
    for e in &kept {
        by_bucket.entry(bucket_key(&e.date, period)).or_default().push(e);
    }
    let mut buckets: Vec<LedgerBucket> = by_bucket
        .into_iter()
        .map(|(key, group)| LedgerBucket {
            label: bucket_label(&key),
            total: group.iter().map(|e| e.amount).sum(),
            count: group.len() as u32,
            by_category: category_totals(&group),
            entry_ids: group.iter().map(|e| e.id.clone()).collect(),
            key,
        })
        .collect();
    // 新しい順。キーは桁を揃えた文字列なので辞書順で時系列になる。
    buckets.sort_by(|a, b| b.key.cmp(&a.key));

    LedgerSummary {
        total,
        count: kept.len() as u32,
        travel_total,
        linked_total,
        show_count,
        average_per_show: if show_count == 0 {
            0
        } else {
            linked_total / i64::from(show_count)
        },
        buckets,
        by_category: category_totals(&kept),
    }
}

/// 公演別の合計。**紐づく支出がある公演だけ**を、日付の新しい順で返す。
pub fn show_totals(entries: &[ExpenseEntry], filter: &LedgerFilter) -> Vec<ShowTotal> {
    let mut by_show: HashMap<String, Vec<&ExpenseEntry>> = HashMap::new();
    for e in entries.iter().filter(|e| keeps(e, filter)) {
        if let Some(show_id) = linked_show(&e) {
            by_show.entry(show_id.to_string()).or_default().push(e);
        }
    }

    let mut totals: Vec<ShowTotal> = by_show
        .into_iter()
        .map(|(show_id, group)| ShowTotal {
            label: group
                .iter()
                .find_map(|e| e.show_label.clone())
                .unwrap_or_else(|| show_id.clone()),
            date: group
                .iter()
                .map(|e| e.date.clone())
                .min()
                .unwrap_or_default(),
            total: group.iter().map(|e| e.amount).sum(),
            count: group.len() as u32,
            by_category: category_totals(&group),
            show_id,
        })
        .collect();
    totals.sort_by(|a, b| b.date.cmp(&a.date).then_with(|| a.show_id.cmp(&b.show_id)));
    totals
}

fn linked_show(entry: &ExpenseEntry) -> Option<&str> {
    entry.show_id.as_deref().filter(|s| !s.is_empty())
}

fn keeps(entry: &ExpenseEntry, filter: &LedgerFilter) -> bool {
    if !filter.year.is_empty() && !entry.date.starts_with(&filter.year) {
        return false;
    }
    if !filter.categories.is_empty() && !filter.categories.contains(&entry.category) {
        return false;
    }
    if !filter.event_id.is_empty() && entry.event_id.as_deref() != Some(filter.event_id.as_str()) {
        return false;
    }
    match filter.linkage {
        LedgerLinkage::All => true,
        LedgerLinkage::LinkedOnly => linked_show(entry).is_some(),
        LedgerLinkage::UnlinkedOnly => linked_show(entry).is_none(),
    }
}

/// 費目別の内訳。**金額が 0 の費目は出さない** (使っていない費目で画面を埋めない)。
fn category_totals<T: std::ops::Deref<Target = ExpenseEntry>>(entries: &[T]) -> Vec<CategoryTotal> {
    let total: i64 = entries.iter().map(|e| e.amount).sum();
    let order: Vec<ExpenseCategory> = expense_categories().into_iter().map(|c| c.category).collect();

    let mut sums: HashMap<ExpenseCategory, (i64, u32)> = HashMap::new();
    for e in entries {
        let slot = sums.entry(e.category).or_insert((0, 0));
        slot.0 += e.amount;
        slot.1 += 1;
    }

    let mut totals: Vec<CategoryTotal> = sums
        .into_iter()
        .map(|(category, (sum, count))| CategoryTotal {
            category,
            label: expense_category_label(category),
            total: sum,
            count,
            percent: percent_of(sum, total),
        })
        .collect();
    totals.sort_by(|a, b| {
        b.total.cmp(&a.total).then_with(|| {
            let ia = order.iter().position(|c| *c == a.category).unwrap_or(usize::MAX);
            let ib = order.iter().position(|c| *c == b.category).unwrap_or(usize::MAX);
            ia.cmp(&ib)
        })
    });
    totals
}

fn percent_of(part: i64, whole: i64) -> u32 {
    if whole <= 0 {
        return 0;
    }
    ((part as f64 / whole as f64) * 100.0).round().clamp(0.0, 100.0) as u32
}

/// 日付から期間のキーを作る。日付が壊れていても落とさず「不明」に寄せる
/// (帳簿から 1 件だけ消えるより、見出しで気づけるほうがいい)。
fn bucket_key(date: &str, period: LedgerPeriod) -> String {
    let ok = is_ymd(date);
    match period {
        LedgerPeriod::Month if ok => date[..7].to_string(),
        LedgerPeriod::Year if ok => date[..4].to_string(),
        LedgerPeriod::All => "all".to_string(),
        _ => "unknown".to_string(),
    }
}

fn bucket_label(key: &str) -> String {
    match key {
        "all" => "全期間".to_string(),
        "unknown" => "日付不明".to_string(),
        k if k.len() == 4 => format!("{k}年"),
        k if k.len() == 7 => {
            let month: u32 = k[5..].parse().unwrap_or(0);
            format!("{}年{}月", &k[..4], month)
        }
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str, date: &str, category: ExpenseCategory, amount: i64) -> ExpenseEntry {
        ExpenseEntry {
            id: id.into(),
            date: date.into(),
            category,
            amount,
            show_id: None,
            event_id: None,
            show_label: None,
            note: None,
        }
    }

    fn linked(
        id: &str,
        date: &str,
        category: ExpenseCategory,
        amount: i64,
        show_id: &str,
    ) -> ExpenseEntry {
        ExpenseEntry {
            show_id: Some(show_id.into()),
            event_id: Some("ev1".into()),
            show_label: Some(format!("公演 {show_id}")),
            ..entry(id, date, category, amount)
        }
    }

    fn all() -> LedgerFilter {
        LedgerFilter {
            year: String::new(),
            categories: vec![],
            linkage: LedgerLinkage::All,
            event_id: String::new(),
        }
    }

    /// 知らないキーで金額が消えない (将来費目を増やした端末のバックアップ対策)。
    #[test]
    fn unknown_category_key_falls_back_to_other() {
        assert_eq!(expense_category_from_key("ramen"), ExpenseCategory::Other);
        assert_eq!(expense_category_from_key(""), ExpenseCategory::Other);
    }

    #[test]
    fn yen_is_grouped_by_three() {
        assert_eq!(format_yen(0), "¥0");
        assert_eq!(format_yen(999), "¥999");
        assert_eq!(format_yen(1_000), "¥1,000");
        assert_eq!(format_yen(12_345), "¥12,345");
        assert_eq!(format_yen(1_234_567), "¥1,234,567");
        assert_eq!(format_yen(-8_800), "-¥8,800");
    }

    #[test]
    fn input_is_validated() {
        assert_eq!(validate_expense("2026-09-22", 8800), None);
        assert_eq!(validate_expense("2026-9-22", 8800), Some(ExpenseInputError::BadDate));
        assert_eq!(validate_expense("2026-13-01", 8800), Some(ExpenseInputError::BadDate));
        assert_eq!(validate_expense("2026-09-32", 8800), Some(ExpenseInputError::BadDate));
        assert_eq!(validate_expense("", 8800), Some(ExpenseInputError::BadDate));
        assert_eq!(validate_expense("2026-09-22", 0), Some(ExpenseInputError::NotPositive));
        assert_eq!(validate_expense("2026-09-22", -1), Some(ExpenseInputError::NotPositive));
        assert_eq!(
            validate_expense("2026-09-22", 100_000_000),
            Some(ExpenseInputError::TooLarge)
        );
    }

    #[test]
    fn totals_split_by_month_newest_first() {
        let entries = vec![
            entry("a", "2026-08-01", ExpenseCategory::Goods, 3_000),
            entry("b", "2026-09-19", ExpenseCategory::Ticket, 9_000),
            entry("c", "2026-09-20", ExpenseCategory::Transport, 14_000),
        ];
        let s = build_ledger_summary(&entries, LedgerPeriod::Month, &all());

        assert_eq!(s.total, 26_000);
        assert_eq!(s.count, 3);
        assert_eq!(s.buckets.len(), 2);
        assert_eq!(s.buckets[0].key, "2026-09");
        assert_eq!(s.buckets[0].label, "2026年9月");
        assert_eq!(s.buckets[0].total, 23_000);
        // entry_ids は元の並びのまま (各 OS がここで明細を引き直す)。
        assert_eq!(s.buckets[0].entry_ids, vec!["b", "c"]);
        assert_eq!(s.buckets[1].label, "2026年8月");
        assert_eq!(s.buckets[1].entry_ids, vec!["a"]);
        // 遠征の費用はチケット + 交通 (グッズは入らない)
        assert_eq!(s.travel_total, 23_000);
    }

    #[test]
    fn year_and_all_buckets() {
        let entries = vec![
            entry("a", "2025-12-31", ExpenseCategory::Goods, 1_000),
            entry("b", "2026-01-01", ExpenseCategory::Goods, 2_000),
        ];
        let by_year = build_ledger_summary(&entries, LedgerPeriod::Year, &all());
        assert_eq!(by_year.buckets.len(), 2);
        assert_eq!(by_year.buckets[0].label, "2026年");

        let whole = build_ledger_summary(&entries, LedgerPeriod::All, &all());
        assert_eq!(whole.buckets.len(), 1);
        assert_eq!(whole.buckets[0].label, "全期間");
        assert_eq!(whole.buckets[0].total, 3_000);
    }

    /// 日付が壊れていても 1 件も落とさない。
    #[test]
    fn broken_date_goes_to_unknown_bucket() {
        let entries = vec![entry("a", "いつか", ExpenseCategory::Goods, 500)];
        let s = build_ledger_summary(&entries, LedgerPeriod::Month, &all());
        assert_eq!(s.total, 500);
        assert_eq!(s.buckets[0].label, "日付不明");
    }

    #[test]
    fn category_breakdown_is_sorted_by_amount() {
        let entries = vec![
            entry("a", "2026-09-19", ExpenseCategory::Goods, 3_000),
            entry("b", "2026-09-19", ExpenseCategory::Ticket, 9_000),
            entry("c", "2026-09-19", ExpenseCategory::Goods, 1_000),
        ];
        let s = build_ledger_summary(&entries, LedgerPeriod::Month, &all());
        assert_eq!(s.by_category.len(), 2);
        assert_eq!(s.by_category[0].category, ExpenseCategory::Ticket);
        assert_eq!(s.by_category[0].percent, 69); // 9000 / 13000
        assert_eq!(s.by_category[1].category, ExpenseCategory::Goods);
        assert_eq!(s.by_category[1].total, 4_000);
        assert_eq!(s.by_category[1].count, 2);
    }

    /// 同額なら費目の並び順に倒す (端末で並びが揺れない)。
    #[test]
    fn ties_follow_category_order() {
        let entries = vec![
            entry("a", "2026-09-19", ExpenseCategory::Goods, 1_000),
            entry("b", "2026-09-19", ExpenseCategory::Ticket, 1_000),
        ];
        let s = build_ledger_summary(&entries, LedgerPeriod::Month, &all());
        assert_eq!(s.by_category[0].category, ExpenseCategory::Ticket);
    }

    #[test]
    fn linked_entries_feed_per_show_average() {
        let entries = vec![
            linked("a", "2026-09-19", ExpenseCategory::Ticket, 9_000, "s1"),
            linked("b", "2026-09-19", ExpenseCategory::Transport, 15_000, "s1"),
            linked("c", "2026-09-20", ExpenseCategory::Ticket, 9_000, "s2"),
            entry("d", "2026-09-21", ExpenseCategory::InGame, 3_000),
        ];
        let s = build_ledger_summary(&entries, LedgerPeriod::Month, &all());
        assert_eq!(s.total, 36_000);
        assert_eq!(s.linked_total, 33_000);
        assert_eq!(s.show_count, 2);
        assert_eq!(s.average_per_show, 16_500);
    }

    #[test]
    fn filters_by_year_category_and_linkage() {
        let entries = vec![
            linked("a", "2025-09-19", ExpenseCategory::Ticket, 9_000, "s1"),
            linked("b", "2026-09-19", ExpenseCategory::Ticket, 8_000, "s2"),
            entry("c", "2026-09-21", ExpenseCategory::InGame, 3_000),
        ];

        let mut f = all();
        f.year = "2026".into();
        assert_eq!(build_ledger_summary(&entries, LedgerPeriod::Year, &f).total, 11_000);

        f.categories = vec![ExpenseCategory::InGame];
        assert_eq!(build_ledger_summary(&entries, LedgerPeriod::Year, &f).total, 3_000);

        f.categories = vec![];
        f.linkage = LedgerLinkage::LinkedOnly;
        assert_eq!(build_ledger_summary(&entries, LedgerPeriod::Year, &f).total, 8_000);

        f.linkage = LedgerLinkage::UnlinkedOnly;
        assert_eq!(build_ledger_summary(&entries, LedgerPeriod::Year, &f).total, 3_000);
    }

    #[test]
    fn filters_by_event() {
        let mut other_event = linked("b", "2026-09-20", ExpenseCategory::Ticket, 7_000, "s2");
        other_event.event_id = Some("ev2".into());
        let entries = vec![
            linked("a", "2026-09-19", ExpenseCategory::Ticket, 9_000, "s1"),
            other_event,
        ];

        let mut f = all();
        f.event_id = "ev2".into();
        assert_eq!(build_ledger_summary(&entries, LedgerPeriod::All, &f).total, 7_000);
    }

    #[test]
    fn show_totals_are_newest_first_with_labels() {
        let entries = vec![
            linked("a", "2026-09-19", ExpenseCategory::Ticket, 9_000, "s1"),
            linked("b", "2026-09-19", ExpenseCategory::Lodging, 12_000, "s1"),
            linked("c", "2026-09-20", ExpenseCategory::Ticket, 9_000, "s2"),
            entry("d", "2026-09-21", ExpenseCategory::InGame, 3_000),
        ];
        let totals = show_totals(&entries, &all());

        assert_eq!(totals.len(), 2);
        assert_eq!(totals[0].show_id, "s2");
        assert_eq!(totals[1].show_id, "s1");
        assert_eq!(totals[1].total, 21_000);
        assert_eq!(totals[1].label, "公演 s1");
        assert_eq!(totals[1].date, "2026-09-19");
        assert_eq!(totals[1].by_category[0].category, ExpenseCategory::Lodging);
    }

    /// 公演名が 1 件も無ければ id で出す (名前が引けなくても行を消さない)。
    #[test]
    fn show_total_falls_back_to_id() {
        let mut e = linked("a", "2026-09-19", ExpenseCategory::Ticket, 9_000, "s1");
        e.show_label = None;
        assert_eq!(show_totals(&[e], &all())[0].label, "s1");
    }

    #[test]
    fn empty_ledger_is_all_zero() {
        let s = build_ledger_summary(&[], LedgerPeriod::Month, &all());
        assert_eq!(s.total, 0);
        assert_eq!(s.count, 0);
        assert!(s.buckets.is_empty());
        assert!(s.by_category.is_empty());
        assert!(show_totals(&[], &all()).is_empty());
    }
}
