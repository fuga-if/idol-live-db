//! 通販の購入明細 (アソビストアの「購入完了のご連絡」メール) を読んで、
//! 収支に入れる支出の下書きにする。純粋ロジック。
//!
//! # 読むもの
//!
//! メール本文をそのまま貼り付けたテキスト。1 通ぶんの形はこう:
//!
//! ```text
//! 【注文番号】113892000000000000-0
//! 【ご注文日時】2025/08/03 15:21:54
//!
//! 【商品明細】
//! 0-0-0-4077
//! <商品名>：1×6,500円=6,500円
//!
//! 【お買上金額】
//! 商品金額合計(税込)：6,500円
//! お支払金額(税込)：6,500円
//! ```
//!
//! 何通ぶんを続けて貼ってもよい (`【注文番号】` で区切る)。前後の挨拶文や
//! 署名は読み飛ばす。
//!
//! # 金額は「払った額」
//!
//! 帳簿に入れるのは**お支払金額**。送料・手数料 (支払額 > 商品合計) も、
//! ポイント・クーポンの値引き (支払額 < 商品合計) も、その差を
//! 一番大きい費目に寄せて、帳簿の合計がカードの請求と一致するようにする。
//!
//! # 1 注文 = 費目ごとに 1 件
//!
//! 同じ注文のグッズ 10 点を 10 行にすると帳簿が品目表になって読めない。
//! 費目ごとにまとめ、品名はメモに残す。メモの頭には注文番号を入れ、
//! 同じ明細を 2 度貼ったときに「記録済み」と分かるようにする。

use crate::domain::ledger::ExpenseCategory;
use crate::domain::text_search_index::FoldedNeedle;

/// 明細の 1 品目。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StoreOrderItem {
    pub name: String,
    pub quantity: u32,
    pub unit_price: i64,
    /// 数量 × 単価 (明細に書いてある額)。
    pub subtotal: i64,
    /// 入れる費目。既定は品名から推す (視聴チケット → チケット代 など)。画面で変えてよい。
    pub category: ExpenseCategory,
    /// 帳簿に入れるか。友人の代理購入などを外せるように。既定は true。
    pub included: bool,
}

/// 注文 1 件。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StoreOrder {
    /// 店の名前 (メモの頭に入れる)。
    pub store: String,
    pub order_number: String,
    /// `YYYY-MM-DD`。明細に日時が無ければ呼び手が渡した今日。
    pub date: String,
    pub items: Vec<StoreOrderItem>,
    /// 商品金額合計。
    pub items_total: i64,
    /// お支払金額。
    pub paid_total: i64,
    /// `paid_total - items_total`。正なら送料・手数料、負ならポイント・クーポンの値引き。
    pub adjustment: i64,
    /// 同じ注文番号の支出がもう帳簿にある。
    pub already_recorded: bool,
    /// 品名から推した紐づけ先の公演 (参加を付けた公演の中から)。
    pub suggested_show_id: Option<String>,
    pub suggested_event_id: Option<String>,
}

/// 紐づけ先の候補 (参加を付けた公演)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StoreShowCandidate {
    pub show_id: String,
    pub event_id: String,
    pub event_name: String,
    /// `YYYY-MM-DD`。
    pub date: String,
}

/// 帳簿に入れる 1 件の下書き。id と更新時刻は各 OS が振る。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StoreExpenseDraft {
    pub date: String,
    pub category: ExpenseCategory,
    pub amount: i64,
    pub show_id: Option<String>,
    pub event_id: Option<String>,
    pub note: String,
}

const STORE_ASOBI: &str = "アソビストア";

/// 貼り付けたテキストから注文を読む。読めた注文だけを貼った順で返す
/// (品目が 1 つも読めない注文は出さない)。
///
/// - `today`: 明細に日時が無いときの日付 (`YYYY-MM-DD`)。
/// - `candidates`: 紐づけ先の候補。
/// - `existing_notes`: 帳簿にある支出のメモ (記録済みの判定に使う)。
pub fn parse_store_orders(
    text: &str,
    today: &str,
    candidates: &[StoreShowCandidate],
    existing_notes: &[String],
) -> Vec<StoreOrder> {
    let normalized = normalize(text);
    let lines: Vec<&str> = normalized.lines().map(str::trim).collect();

    // 【注文番号】の行で区切る。
    let starts: Vec<usize> = lines
        .iter()
        .enumerate()
        .filter(|(_, l)| l.starts_with("【注文番号】"))
        .map(|(i, _)| i)
        .collect();

    starts
        .iter()
        .enumerate()
        .filter_map(|(n, &start)| {
            let end = starts.get(n + 1).copied().unwrap_or(lines.len());
            parse_one(&lines[start..end], today, candidates, existing_notes)
        })
        .collect()
}

/// 注文 1 件を帳簿の下書きにする。含める品目を費目ごとにまとめ、
/// 送料・値引きの差は一番大きい費目に寄せる。含める品目が無ければ空。
pub fn store_order_expenses(
    order: &StoreOrder,
    show_id: Option<String>,
    event_id: Option<String>,
) -> Vec<StoreExpenseDraft> {
    let order_cats: Vec<ExpenseCategory> = crate::domain::ledger::expense_categories()
        .into_iter()
        .map(|c| c.category)
        .collect();

    // 費目 → (合計, 品名)。並びは費目一覧の順。
    let mut groups: Vec<(ExpenseCategory, i64, Vec<String>)> = Vec::new();
    for item in order.items.iter().filter(|i| i.included) {
        let label = if item.quantity > 1 {
            format!("{}×{}", item.name, item.quantity)
        } else {
            item.name.clone()
        };
        match groups.iter_mut().find(|g| g.0 == item.category) {
            Some(g) => {
                g.1 += item.subtotal;
                g.2.push(label);
            }
            None => groups.push((item.category, item.subtotal, vec![label])),
        }
    }
    if groups.is_empty() {
        return vec![];
    }
    groups.sort_by_key(|g| order_cats.iter().position(|c| *c == g.0).unwrap_or(usize::MAX));

    // 差を寄せる先: 一番大きい費目 (同額なら費目一覧で先のもの)。
    let target = groups
        .iter()
        .enumerate()
        .max_by(|(ia, a), (ib, b)| a.1.cmp(&b.1).then(ib.cmp(ia)))
        .map(|(i, _)| i)
        .unwrap_or(0);
    groups[target].1 += order.adjustment;

    groups
        .into_iter()
        .filter(|g| g.1 > 0)
        .map(|(category, amount, names)| StoreExpenseDraft {
            date: order.date.clone(),
            category,
            amount,
            show_id: show_id.clone(),
            event_id: event_id.clone(),
            note: format!("{} {}\n{}", order.store, order_marker(&order.order_number), names.join("、")),
        })
        .collect()
}

/// メモに入れる注文番号の印。記録済みの判定もこれで引く。
fn order_marker(order_number: &str) -> String {
    format!("注文番号 {order_number}")
}

fn parse_one(
    lines: &[&str],
    today: &str,
    candidates: &[StoreShowCandidate],
    existing_notes: &[String],
) -> Option<StoreOrder> {
    let order_number = lines
        .first()?
        .trim_start_matches("【注文番号】")
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_string();

    let mut date = None;
    let mut items = Vec::new();
    let mut items_total = None;
    let mut paid_total = None;

    #[derive(PartialEq)]
    enum Section {
        Head,
        Items,
        Amounts,
        Other,
    }
    let mut section = Section::Head;
    // 品名が折り返されて複数行になったときの頭の部分。
    let mut pending_name = String::new();

    for line in &lines[1..] {
        if line.starts_with("【ご注文日時】") {
            date = parse_date(line.trim_start_matches("【ご注文日時】"));
            continue;
        }
        if line.starts_with('【') {
            section = match *line {
                l if l.starts_with("【商品明細】") => Section::Items,
                l if l.starts_with("【お買上金額】") => Section::Amounts,
                _ => Section::Other,
            };
            pending_name.clear();
            continue;
        }
        // 区切り線 (-----) で明細の枠が閉じる。
        if line.starts_with("---") || line.starts_with("===") {
            section = Section::Other;
            continue;
        }
        match section {
            Section::Items => {
                if line.is_empty() || is_item_code(line) {
                    pending_name.clear();
                    continue;
                }
                match parse_item_line(line) {
                    Some((name, quantity, unit_price, subtotal)) => {
                        let full = format!("{pending_name}{name}").trim().to_string();
                        pending_name.clear();
                        items.push(StoreOrderItem {
                            category: guess_category(&full),
                            name: full,
                            quantity,
                            unit_price,
                            subtotal,
                            included: true,
                        });
                    }
                    None => pending_name.push_str(line),
                }
            }
            Section::Amounts => {
                if let Some((label, amount)) = parse_amount_line(line) {
                    if label.starts_with("商品金額合計") {
                        items_total = Some(amount);
                    } else if label.starts_with("お支払金額") || label.starts_with("ご請求金額") {
                        paid_total = Some(amount);
                    }
                }
            }
            Section::Head | Section::Other => {}
        }
    }

    if items.is_empty() {
        return None;
    }
    let items_total = items_total.unwrap_or_else(|| items.iter().map(|i| i.subtotal).sum());
    let paid_total = paid_total.unwrap_or(items_total);

    let marker = order_marker(&order_number);
    let already_recorded = !order_number.is_empty() && existing_notes.iter().any(|n| n.contains(&marker));
    let suggestion = suggest_show(&items, candidates);

    Some(StoreOrder {
        store: STORE_ASOBI.to_string(),
        order_number,
        date: date.unwrap_or_else(|| today.to_string()),
        items,
        items_total,
        paid_total,
        adjustment: paid_total - items_total,
        already_recorded,
        suggested_show_id: suggestion.map(|c| c.show_id.clone()),
        suggested_event_id: suggestion.map(|c| c.event_id.clone()),
    })
}

/// 全角の数字・記号を半角へ寄せる (転送や端末のコピーで全角になることがある)。
fn normalize(text: &str) -> String {
    text.chars()
        .map(|c| match c {
            '０'..='９' => char::from_u32(c as u32 - '０' as u32 + '0' as u32).unwrap_or(c),
            '，' => ',',
            '／' => '/',
            '＝' => '=',
            '\u{00A0}' | '\u{3000}' => ' ',
            _ => c,
        })
        .collect()
}

/// `2025/08/03 15:21:54` → `2025-08-03`。
fn parse_date(text: &str) -> Option<String> {
    let head = text.trim().split_whitespace().next()?;
    let parts: Vec<&str> = head.split(['/', '-']).collect();
    if parts.len() != 3 {
        return None;
    }
    let y: u32 = parts[0].parse().ok()?;
    let m: u32 = parts[1].parse().ok()?;
    let d: u32 = parts[2].parse().ok()?;
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) || parts[0].len() != 4 {
        return None;
    }
    Some(format!("{y:04}-{m:02}-{d:02}"))
}

/// 商品コードの行 (`0-0-0-4077`)。数字とハイフンだけ。
fn is_item_code(line: &str) -> bool {
    line.contains('-') && line.chars().all(|c| c.is_ascii_digit() || c == '-')
}

/// `<品名>：1×6,500円=6,500円` → (品名, 数量, 単価, 小計)。
///
/// 品名にも `：` が入りうるので、**最後の** `：` から後ろが金額の形かで見る。
fn parse_item_line(line: &str) -> Option<(String, u32, i64, i64)> {
    let (name, rest) = split_last_colon(line)?;
    let (qty, rest) = rest.split_once(['×', 'x', 'X', '✕', '*', '＊'])?;
    let (unit, subtotal) = rest.split_once('=')?;
    let quantity: u32 = qty.trim().parse().ok()?;
    let unit_price = parse_yen(unit)?;
    let subtotal = parse_yen(subtotal)?;
    Some((name.trim().to_string(), quantity, unit_price, subtotal))
}

/// `商品金額合計(税込)：6,500円` → (ラベル, 金額)。値引きの行は `-500円` のように負で読む。
fn parse_amount_line(line: &str) -> Option<(String, i64)> {
    let (label, value) = split_last_colon(line)?;
    Some((label.trim().to_string(), parse_yen(value)?))
}

fn split_last_colon(line: &str) -> Option<(&str, &str)> {
    let idx = line.rfind(['：', ':'])?;
    let colon_len = line[idx..].chars().next()?.len_utf8();
    Some((&line[..idx], &line[idx + colon_len..]))
}

/// `6,500円` / `¥6,500` / `-500円` → 円。数字が無ければ None。
fn parse_yen(text: &str) -> Option<i64> {
    let t = text.trim().trim_end_matches('円').trim_start_matches(['¥', '￥']).trim();
    let (negative, digits) = match t.strip_prefix(['-', '−', '▲']) {
        Some(rest) => (true, rest.trim_start_matches(['¥', '￥'])),
        None => (false, t),
    };
    let digits: String = digits.chars().filter(|c| *c != ',').collect();
    if digits.is_empty() || !digits.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let value: i64 = digits.parse().ok()?;
    Some(if negative { -value } else { value })
}

/// 品名から費目を推す。迷うものはグッズ代 (この取り込みの主目的)。
fn guess_category(name: &str) -> ExpenseCategory {
    // 視聴チケット・配信チケット・現地チケットはチケット代。
    if name.contains("チケット") {
        return ExpenseCategory::Ticket;
    }
    // ペンライト・ブレード・電池は「UO代」の箱 (費目の定義がそう)。
    if ["ペンライト", "ブレード", "電池"].iter().any(|k| name.contains(k)) {
        return ExpenseCategory::Penlight;
    }
    ExpenseCategory::Goods
}

/// 品名にイベント名が入っていれば、その公演を推す。
///
/// 複数のイベント名が当たるときは**長い名前**を採る (「〜 LIVE」より「〜 LIVE TOUR 〜」)。
/// 同じイベントの公演が複数あれば、品名の `8/3` のような日付に合う公演、
/// 無ければ一番早い公演。
fn suggest_show<'a>(
    items: &[StoreOrderItem],
    candidates: &'a [StoreShowCandidate],
) -> Option<&'a StoreShowCandidate> {
    let names: Vec<&str> = items.iter().map(|i| i.name.as_str()).collect();
    let event = candidates
        .iter()
        .filter(|c| c.event_name.chars().count() >= 4)
        .filter(|c| {
            let needle = FoldedNeedle::new(&c.event_name);
            names.iter().any(|n| needle.matches(n))
        })
        .max_by_key(|c| c.event_name.chars().count())?;

    let mut shows: Vec<&StoreShowCandidate> =
        candidates.iter().filter(|c| c.event_id == event.event_id).collect();
    shows.sort_by(|a, b| a.date.cmp(&b.date));

    let dated = shows.iter().find(|s| {
        let Some(md) = month_day(&s.date) else { return false };
        names.iter().any(|n| n.contains(&md))
    });
    dated.or(shows.first()).copied()
}

/// `2025-08-03` → `8/3`。
fn month_day(date: &str) -> Option<String> {
    let m: u32 = date.get(5..7)?.parse().ok()?;
    let d: u32 = date.get(8..10)?.parse().ok()?;
    Some(format!("{m}/{d}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 実際のメールの形 (番号・品名は差し替え)。
    const TICKET_MAIL: &str = "\
平素は格別のご高配を賜りお礼申し上げます。
アソビストア でございます。

■ご注文明細
------------------------------------------------------------------------

【注文番号】100000000000000001-0
【ご注文日時】2025/08/03 15:21:54

【商品明細】
0-0-0-4077
THE IDOLM@STER 765PRO ALLSTARS LIVE ～NEVER END IDOL!!!!!!!!!!!!!～ DAY2視聴チケット【8/3(日)】：1×6,500円=6,500円

【お買上金額】
商品金額合計(税込)：6,500円
お支払金額(税込)：6,500円

【お支払い方法】
クレジットカード

------------------------------------------------------------------------
ご不明な点などは、お気軽にお問い合わせくださいませ。
";

    const GOODS_MAIL: &str = "\
【注文番号】100000000000000002-0
【ご注文日時】2025/10/01 21:00:00

【商品明細】
0-0-0-5001
THE IDOLM@STER SHINY COLORS 7thLIVE パンフレット：1×3,000円=3,000円
0-0-0-5002
THE IDOLM@STER SHINY COLORS 7thLIVE アクリルスタンド：3×1,500円=4,500円
0-0-0-5003
THE IDOLM@STER SHINY COLORS 7thLIVE ペンライト：1×4,400円=4,400円

【お買上金額】
商品金額合計(税込)：11,900円
送料(税込)：800円
お支払金額(税込)：12,700円
";

    fn cand(show: &str, event: &str, name: &str, date: &str) -> StoreShowCandidate {
        StoreShowCandidate {
            show_id: show.into(),
            event_id: event.into(),
            event_name: name.into(),
            date: date.into(),
        }
    }

    #[test]
    fn reads_ticket_mail() {
        let orders = parse_store_orders(TICKET_MAIL, "2026-01-01", &[], &[]);
        assert_eq!(orders.len(), 1);
        let o = &orders[0];
        assert_eq!(o.order_number, "100000000000000001-0");
        assert_eq!(o.date, "2025-08-03");
        assert_eq!(o.items.len(), 1);
        assert_eq!(o.items[0].quantity, 1);
        assert_eq!(o.items[0].unit_price, 6_500);
        assert_eq!(o.items[0].category, ExpenseCategory::Ticket);
        assert_eq!(o.paid_total, 6_500);
        assert_eq!(o.adjustment, 0);
        assert!(!o.already_recorded);
    }

    #[test]
    fn reads_several_orders_and_shipping() {
        let text = format!("{TICKET_MAIL}\n\n{GOODS_MAIL}");
        let orders = parse_store_orders(&text, "2026-01-01", &[], &[]);
        assert_eq!(orders.len(), 2);
        let g = &orders[1];
        assert_eq!(g.items.len(), 3);
        assert_eq!(g.items[1].quantity, 3);
        assert_eq!(g.items[1].subtotal, 4_500);
        assert_eq!(g.items[2].category, ExpenseCategory::Penlight);
        assert_eq!(g.adjustment, 800);
    }

    #[test]
    fn groups_by_category_and_folds_shipping_into_largest() {
        let order = parse_store_orders(GOODS_MAIL, "2026-01-01", &[], &[]).remove(0);
        let drafts = store_order_expenses(&order, None, None);
        assert_eq!(drafts.len(), 2);
        // グッズ 7,500 + 送料 800、UO 4,400。合計は支払額と一致する。
        assert_eq!(drafts[0].category, ExpenseCategory::Goods);
        assert_eq!(drafts[0].amount, 8_300);
        assert_eq!(drafts[1].category, ExpenseCategory::Penlight);
        assert_eq!(drafts.iter().map(|d| d.amount).sum::<i64>(), order.paid_total);
        assert!(drafts[0].note.starts_with("アソビストア 注文番号 100000000000000002-0\n"));
        assert!(drafts[0].note.contains("アクリルスタンド×3"));
        assert_eq!(drafts[0].date, "2025-10-01");
    }

    #[test]
    fn excluded_items_and_category_change() {
        let mut order = parse_store_orders(GOODS_MAIL, "2026-01-01", &[], &[]).remove(0);
        order.items[2].category = ExpenseCategory::Goods;
        order.items[1].included = false;
        let drafts = store_order_expenses(&order, Some("s".into()), Some("e".into()));
        assert_eq!(drafts.len(), 1);
        assert_eq!(drafts[0].amount, 3_000 + 4_400 + 800);
        assert_eq!(drafts[0].show_id.as_deref(), Some("s"));

        for item in &mut order.items {
            item.included = false;
        }
        assert!(store_order_expenses(&order, None, None).is_empty());
    }

    #[test]
    fn discount_lowers_the_amount() {
        let text = GOODS_MAIL.replace("送料(税込)：800円\nお支払金額(税込)：12,700円", "ポイント利用：-900円\nお支払金額(税込)：11,000円");
        let order = parse_store_orders(&text, "2026-01-01", &[], &[]).remove(0);
        assert_eq!(order.adjustment, -900);
        let drafts = store_order_expenses(&order, None, None);
        assert_eq!(drafts.iter().map(|d| d.amount).sum::<i64>(), 11_000);
    }

    #[test]
    fn marks_already_recorded() {
        let notes = vec!["アソビストア 注文番号 100000000000000002-0\nパンフレット".to_string()];
        let orders = parse_store_orders(&format!("{TICKET_MAIL}{GOODS_MAIL}"), "2026-01-01", &[], &notes);
        assert!(!orders[0].already_recorded);
        assert!(orders[1].already_recorded);
    }

    #[test]
    fn suggests_show_by_event_name_and_date() {
        let candidates = vec![
            cand("d1", "ev", "THE IDOLM@STER 765PRO ALLSTARS LIVE ～NEVER END IDOL!!!!!!!!!!!!!～", "2025-08-02"),
            cand("d2", "ev", "THE IDOLM@STER 765PRO ALLSTARS LIVE ～NEVER END IDOL!!!!!!!!!!!!!～", "2025-08-03"),
            cand("x", "other", "THE IDOLM@STER", "2020-01-01"),
        ];
        let o = parse_store_orders(TICKET_MAIL, "2026-01-01", &candidates, &[]).remove(0);
        assert_eq!(o.suggested_show_id.as_deref(), Some("d2"));
        assert_eq!(o.suggested_event_id.as_deref(), Some("ev"));

        // 日付が品名に無ければ一番早い公演。
        let c2 = vec![
            cand("b", "sc7", "THE IDOLM@STER SHINY COLORS 7thLIVE", "2025-11-02"),
            cand("a", "sc7", "THE IDOLM@STER SHINY COLORS 7thLIVE", "2025-11-01"),
        ];
        let g = parse_store_orders(GOODS_MAIL, "2026-01-01", &c2, &[]).remove(0);
        assert_eq!(g.suggested_show_id.as_deref(), Some("a"));
    }

    #[test]
    fn tolerates_fullwidth_digits_wrapped_names_and_missing_date() {
        let text = "【注文番号】１２３-0\n【商品明細】\n0-0-0-1\nとても長い品名の\n前半と後半：２×１，０００円＝２，０００円\n";
        let o = parse_store_orders(text, "2026-09-30", &[], &[]).remove(0);
        assert_eq!(o.order_number, "123-0");
        assert_eq!(o.date, "2026-09-30");
        assert_eq!(o.items[0].name, "とても長い品名の前半と後半");
        assert_eq!(o.items[0].subtotal, 2_000);
        assert_eq!(o.paid_total, 2_000);
    }

    #[test]
    fn ignores_text_without_orders() {
        assert!(parse_store_orders("こんにちは", "2026-09-30", &[], &[]).is_empty());
        assert!(parse_store_orders("【注文番号】1-0\n【商品明細】\n", "2026-09-30", &[], &[]).is_empty());
    }
}
