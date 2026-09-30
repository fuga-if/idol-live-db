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
    /// 品目の小計の和が商品金額合計と合わない (読み取れなかった品目がある)。
    /// 額は `adjustment` に入るので合計は合うが、品名と費目が抜けている。
    pub has_unread_items: bool,
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

    let mut orders: Vec<StoreOrder> = starts
        .iter()
        .enumerate()
        .filter_map(|(n, &start)| {
            let end = starts.get(n + 1).copied().unwrap_or(lines.len());
            parse_one(&lines[start..end], today, candidates, existing_notes)
        })
        .collect();
    // AI にまとめさせた JSON (取り込み用の形式) も同じ箱で受ける。
    orders.extend(parse_ai_json(text, today, candidates, existing_notes));
    // マイページの購入履歴一覧。明細 (メール・JSON) で読めた注文は、品名のある方を採る。
    for order in parse_order_history(&normalized, existing_notes) {
        if !orders.iter().any(|o| o.order_number == order.order_number) {
            orders.push(order);
        }
    }
    orders
}

// ---------------------------------------------------------------------------
// マイページの購入履歴一覧
// ---------------------------------------------------------------------------
//
// `https://shop.asobistore.jp/mypage/orderhistory/` の表をコピーしたもの:
//
//   ご注文番号  注文日  合計金額  状態  お問合せ番号  お支払方法  詳細
//   A10232026092201582  2026/09/22  13,200円  出荷完了  366559599195  クレジットカード  詳 細
//
// 列はタブ区切りのことも、端末によっては 1 セル 1 行のこともあるので、
// **セルを順に並べて「注文番号 → 日付 → 金額 → 状態」の並びを探す**。
// 品名は一覧に無いので、状態から費目を推す (発送のある注文 = グッズ、
// 発送の無い「購入済」= 視聴チケットなどのデジタル商品)。

/// 購入履歴一覧から注文を読む。キャンセルした注文は入れない。
fn parse_order_history(text: &str, existing_notes: &[String]) -> Vec<StoreOrder> {
    let cells: Vec<&str> = text
        .split(['\t', '\n'])
        .map(str::trim)
        .filter(|c| !c.is_empty())
        .collect();
    let mut orders = Vec::new();
    let mut i = 0;
    while i + 3 < cells.len() {
        let (number, date, amount, status) = (cells[i], cells[i + 1], cells[i + 2], cells[i + 3]);
        let parsed = is_order_number(number)
            .then(|| Some((parse_date(date)?, parse_yen(amount).filter(|a| *a > 0)?)))
            .flatten();
        let Some((date, total)) = parsed else {
            i += 1;
            continue;
        };
        i += 4;
        if status.contains("キャンセル") {
            continue;
        }
        let digital = status.contains("購入済");
        let item = StoreOrderItem {
            name: if digital { "デジタル商品の注文 (明細なし)" } else { "グッズの注文 (明細なし)" }.into(),
            quantity: 1,
            unit_price: total,
            subtotal: total,
            category: if digital { ExpenseCategory::Ticket } else { ExpenseCategory::Goods },
            included: true,
        };
        orders.push(finish_order(
            STORE_ASOBI.to_string(),
            number.to_string(),
            date,
            vec![item],
            total,
            total,
            &[],
            existing_notes,
        ));
    }
    orders
}

/// 注文番号らしいか (`A10232026092201582` / `175107202163693924-0`)。
/// 数字を 10 桁以上含み、英数字とハイフンだけ。お問合せ番号 (数字だけ) と
/// 取り違えないよう、呼び手は「次のセルが日付」まで見る。
fn is_order_number(cell: &str) -> bool {
    cell.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
        && cell.chars().filter(|c| c.is_ascii_digit()).count() >= 10
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

    // 差を寄せる先: 大きい費目から順 (同額なら費目一覧で先のもの)。
    // 値引きが 1 つの費目より大きければ、0 で止めて残りを次の費目へ繰り越す
    // (マイナスの残りを捨てると、記録の合計が支払額より多くなる)。
    let mut by_size: Vec<usize> = (0..groups.len()).collect();
    by_size.sort_by(|&a, &b| groups[b].1.cmp(&groups[a].1).then(a.cmp(&b)));
    let mut rest = order.adjustment;
    for &i in &by_size {
        if rest >= 0 {
            groups[i].1 += rest;
            break;
        }
        let taken = rest.max(-groups[i].1);
        groups[i].1 += taken;
        rest -= taken;
        if rest == 0 {
            break;
        }
    }

    groups
        .into_iter()
        .filter(|g| g.1 > 0)
        .map(|(category, amount, names)| StoreExpenseDraft {
            date: order.date.clone(),
            category,
            amount,
            show_id: show_id.clone(),
            event_id: event_id.clone(),
            note: if order.order_number.is_empty() {
                format!("{}\n{}", order.store, names.join("、"))
            } else {
                format!("{} {}\n{}", order.store, order_marker(&order.order_number), names.join("、"))
            },
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
        // 品名が【受注生産】のように【】で始まることがあるので、明細の中では品目の形を先に見る。
        if section == Section::Items {
            if let Some((name, quantity, unit_price, subtotal)) = parse_item_line(line) {
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
                continue;
            }
        }
        if is_heading(line) {
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
                } else {
                    pending_name.push_str(line);
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
    Some(finish_order(
        STORE_ASOBI.to_string(),
        order_number,
        date.unwrap_or_else(|| today.to_string()),
        items,
        items_total,
        paid_total,
        candidates,
        existing_notes,
    ))
}

/// 読み取った注文に、記録済みの判定と紐づけ先の推しを足して仕上げる。
#[allow(clippy::too_many_arguments)]
fn finish_order(
    store: String,
    order_number: String,
    date: String,
    items: Vec<StoreOrderItem>,
    items_total: i64,
    paid_total: i64,
    candidates: &[StoreShowCandidate],
    existing_notes: &[String],
) -> StoreOrder {
    let marker = order_marker(&order_number);
    // 行末で合わせる (「注文番号 X-1」が「注文番号 X-10」に当たらないように)。
    let already_recorded = !order_number.is_empty()
        && existing_notes
            .iter()
            .any(|n| n.lines().any(|l| l.trim_end().ends_with(&marker)));
    let read_total: i64 = items.iter().map(|i| i.subtotal).sum();
    let suggestion = suggest_show(&items, candidates);

    StoreOrder {
        store,
        order_number,
        date,
        items,
        items_total,
        paid_total,
        adjustment: paid_total - items_total,
        already_recorded,
        has_unread_items: read_total != items_total,
        suggested_show_id: suggestion.map(|c| c.show_id.clone()),
        suggested_event_id: suggestion.map(|c| c.event_id.clone()),
    }
}

// ---------------------------------------------------------------------------
// AI にまとめさせる経路
// ---------------------------------------------------------------------------
//
// メールの形は店ごと・時期ごとに違い、マイページの注文履歴はスクリーンショットでしか
// 持ち出せない。そこは読み取りの得意な AI (利用者が自分で使っているもの) に任せ、
// アプリは**決まった形の JSON だけ**を読む。アプリから AI を呼ぶことはしない
// (利用者が自分で開いて、結果を貼り戻す)。

/// 取り込み用 JSON の形の版。形を変えたら上げる。
const AI_FORMAT: &str = "imas-live-db/expenses@1";

/// AI に渡す指示文。費目の英字キーは費目一覧から組む (一覧が唯一の出どころ)。
pub fn store_order_ai_prompt() -> String {
    let keys = crate::domain::ledger::expense_categories()
        .into_iter()
        .map(|c| format!("{}={}", c.key, c.label))
        .collect::<Vec<_>>()
        .join(" / ");
    format!(
        "アイマス関連の支出を家計簿アプリ「アイマスライブDB」に取り込みたいので、購入明細をまとめてください。\n\
         \n\
         材料: 私のメール (読めるなら「アソビストア」「アソビチケット」「アソビステージ」などの購入完了・決済完了のメール) と、私がこのあと貼る注文履歴のテキストやスクリーンショット。期間の指定が無ければ、始める前に聞いてください。\n\
         \n\
         決まり:\n\
         - 明細に書いてある事実だけを使う。金額や品名を推測で作らない。読めない注文は入れない\n\
         - 金額は税込の整数の円。paid_total は実際に払った額 (送料・手数料を足し、ポイント・クーポンを引いた額)\n\
         - 抽選に外れた申込・キャンセルした注文は入れない\n\
         - category は次のどれか: {keys}\n\
         - date は注文日 (YYYY-MM-DD)。order_number は明細の注文番号で、無ければ空文字\n\
         \n\
         出力は次の形の JSON を 1 つのコードブロックにして、ほかの文は付けない:\n\
         {{\"format\":\"{AI_FORMAT}\",\"orders\":[{{\"store\":\"アソビストア\",\"order_number\":\"113892000000000000-0\",\"date\":\"2025-08-03\",\"paid_total\":12700,\"items\":[{{\"name\":\"品名\",\"quantity\":1,\"unit_price\":3000,\"subtotal\":3000,\"category\":\"goods\"}}]}}]}}"
    )
}

/// 指示文を入れて AI を開くリンク。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct AiPromptLink {
    pub label: String,
    pub url: String,
    /// URL で指示文を入れられないチャット (Gemini)。開く前に指示文をクリップボードへ入れ、
    /// 利用者に貼ってもらう。
    pub needs_paste: bool,
}

/// 指示文を入れて開けるチャット。どれも「開いた時点では送らない」
/// (利用者が中身を見てから送る)。
pub fn store_order_ai_links() -> Vec<AiPromptLink> {
    let q = encode_strict(&store_order_ai_prompt());
    vec![
        AiPromptLink { label: "Claude".into(), url: format!("https://claude.ai/new?q={q}"), needs_paste: false },
        AiPromptLink { label: "ChatGPT".into(), url: format!("https://chatgpt.com/?q={q}"), needs_paste: false },
        // Gemini は URL で入力欄を埋める口が公開されていない。
        AiPromptLink { label: "Gemini".into(), url: "https://gemini.google.com/app".into(), needs_paste: true },
    ]
}

/// クエリ値の percent-encoding。英数字と `-_.~` だけ素通し (`+` を空白と読む受け手がある)。
fn encode_strict(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 3);
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// 貼られたテキストから取り込み用 JSON を探して読む。コードブロックや前後の文が
/// 付いていてもよい (`"format"` を含む一番外の `{…}` を探す)。
fn parse_ai_json(
    text: &str,
    today: &str,
    candidates: &[StoreShowCandidate],
    existing_notes: &[String],
) -> Vec<StoreOrder> {
    let Some(value) = find_format_json(text) else { return vec![] };
    let Some(orders) = value.get("orders").and_then(|o| o.as_array()) else { return vec![] };

    orders
        .iter()
        .filter_map(|o| {
            let items: Vec<StoreOrderItem> = o
                .get("items")?
                .as_array()?
                .iter()
                .filter_map(|i| {
                    let name = str_of(i, "name")?.trim().to_string();
                    if name.is_empty() {
                        return None;
                    }
                    let quantity = int_of(i, "quantity").filter(|q| *q > 0).unwrap_or(1);
                    let unit_price = int_of(i, "unit_price");
                    let subtotal = int_of(i, "subtotal")
                        .or_else(|| unit_price.map(|u| u * quantity))?;
                    if subtotal < 0 {
                        return None;
                    }
                    let category = match str_of(i, "category") {
                        Some(key) if crate::domain::ledger::expense_categories()
                            .iter()
                            .any(|c| c.key == key) =>
                        {
                            crate::domain::ledger::expense_category_from_key(key)
                        }
                        _ => guess_category(&name),
                    };
                    Some(StoreOrderItem {
                        name,
                        quantity: u32::try_from(quantity).unwrap_or(1),
                        unit_price: unit_price.unwrap_or(subtotal / quantity.max(1)),
                        subtotal,
                        category,
                        included: true,
                    })
                })
                .collect();
            if items.is_empty() {
                return None;
            }
            let items_total: i64 = items.iter().map(|i| i.subtotal).sum();
            let paid_total = int_of(o, "paid_total").filter(|p| *p >= 0).unwrap_or(items_total);
            let date = str_of(o, "date")
                .and_then(parse_date)
                .unwrap_or_else(|| today.to_string());
            let store = str_of(o, "store")
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .unwrap_or("通販")
                .to_string();
            let order_number = str_of(o, "order_number").unwrap_or("").trim().to_string();
            Some(finish_order(
                store,
                order_number,
                date,
                items,
                items_total,
                paid_total,
                candidates,
                existing_notes,
            ))
        })
        .collect()
}

fn find_format_json(text: &str) -> Option<serde_json::Value> {
    let marker = text.find(AI_FORMAT)?;
    // 印より前の `{` から順に、閉じ括弧までを JSON として試す。
    let opens: Vec<usize> = text[..marker].match_indices('{').map(|(i, _)| i).collect();
    for &start in &opens {
        let mut stream = serde_json::Deserializer::from_str(&text[start..]).into_iter::<serde_json::Value>();
        if let Some(Ok(value)) = stream.next() {
            if value.get("format").and_then(|f| f.as_str()) == Some(AI_FORMAT) {
                return Some(value);
            }
        }
    }
    None
}

fn str_of<'a>(v: &'a serde_json::Value, key: &str) -> Option<&'a str> {
    v.get(key)?.as_str()
}

/// 整数。AI が `"3,000"` や `3000.0` で返しても読む。
fn int_of(v: &serde_json::Value, key: &str) -> Option<i64> {
    let x = v.get(key)?;
    if let Some(n) = x.as_i64() {
        return Some(n);
    }
    if let Some(f) = x.as_f64() {
        return (f.fract() == 0.0).then_some(f as i64);
    }
    x.as_str().and_then(parse_yen)
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

/// 見出しの行 (`【商品明細】` だけの行、または知っている見出しで始まる行)。
/// `【受注生産】アクリルスタンド` のような品名の頭を見出しと取り違えないため、
/// 知らない【】は行が【】だけで終わるときに限る。
fn is_heading(line: &str) -> bool {
    const KNOWN: [&str; 8] = [
        "【商品明細】",
        "【お買上金額】",
        "【お支払い方法】",
        "【お支払方法】",
        "【お届け先】",
        "【配送方法】",
        "【お届け予定",
        "【ご注文者",
    ];
    line.starts_with('【')
        && (line.ends_with('】') && line.matches('【').count() == 1
            || KNOWN.iter().any(|k| line.starts_with(k)))
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
    if name.contains("チケット") && !["ホルダー", "ケース", "ファイル"].iter().any(|k| name.contains(k)) {
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
    fn reads_items_whose_name_starts_with_brackets() {
        let text = "【注文番号】9-0\n【商品明細】\n0-0-0-1\n【受注生産】アクリルスタンド：1×1,500円=1,500円\n0-0-0-2\n【アソビストア限定】チケットホルダー：1×1,000円=1,000円\n【お買上金額】\n商品金額合計(税込)：2,500円\nお支払金額(税込)：2,500円\n";
        let o = parse_store_orders(text, "2026-09-30", &[], &[]).remove(0);
        assert_eq!(o.items.len(), 2);
        assert_eq!(o.items[0].name, "【受注生産】アクリルスタンド");
        assert_eq!(o.items[1].category, ExpenseCategory::Goods);
        assert_eq!(o.adjustment, 0);
        assert!(!o.has_unread_items);
    }

    #[test]
    fn flags_unread_items() {
        let text = GOODS_MAIL.replace("商品金額合計(税込)：11,900円", "商品金額合計(税込)：13,900円");
        let o = parse_store_orders(&text, "2026-01-01", &[], &[]).remove(0);
        assert!(o.has_unread_items);
    }

    #[test]
    fn big_discount_carries_over_to_next_category() {
        // チケット 6,500 + グッズ 3,000、ポイント 7,000 で支払 2,500。
        let text = "【注文番号】8-0\n【商品明細】\n配信チケット：1×6,500円=6,500円\nパンフレット：1×3,000円=3,000円\n【お買上金額】\n商品金額合計(税込)：9,500円\nお支払金額(税込)：2,500円\n";
        let mut o = parse_store_orders(text, "2026-01-01", &[], &[]).remove(0);
        let drafts = store_order_expenses(&o, None, None);
        assert_eq!(drafts.iter().map(|d| d.amount).sum::<i64>(), 2_500);
        assert_eq!(drafts.len(), 1);
        assert_eq!(drafts[0].category, ExpenseCategory::Goods);

        // 値引きが含めた品目より大きければ何も入らない (マイナスは入れない)。
        o.items[0].included = false;
        o.adjustment = -3_500;
        assert!(store_order_expenses(&o, None, None).is_empty());
    }

    #[test]
    fn recorded_check_does_not_match_longer_numbers() {
        let notes = vec!["アソビストア 注文番号 100000000000000002-00\nx".to_string()];
        let o = parse_store_orders(GOODS_MAIL, "2026-01-01", &[], &notes).remove(0);
        assert!(!o.already_recorded);
    }

    #[test]
    fn reads_ai_json_inside_code_block() {
        let text = r#"まとめました。
```json
{"format":"imas-live-db/expenses@1","orders":[
 {"store":"アソビストア","order_number":"A-1","date":"2025-10-01","paid_total":12700,
  "items":[{"name":"THE IDOLM@STER SHINY COLORS 7thLIVE パンフレット","quantity":1,"unit_price":3000,"subtotal":3000,"category":"goods"},
           {"name":"アクリルスタンド","quantity":3,"unit_price":"1,500","category":"goods"},
           {"name":"ペンライト","quantity":1,"subtotal":4400}]},
 {"store":"","date":"2025/11/02","items":[{"name":"配信チケット","subtotal":5000,"category":"ticket"}]},
 {"store":"x","items":[]}
]}
```"#;
        let c = vec![cand("a", "sc7", "THE IDOLM@STER SHINY COLORS 7thLIVE", "2025-11-01")];
        let orders = parse_store_orders(text, "2026-09-30", &c, &[]);
        assert_eq!(orders.len(), 2);
        let o = &orders[0];
        assert_eq!(o.items.len(), 3);
        assert_eq!(o.items[1].subtotal, 4_500);
        assert_eq!(o.items[2].category, ExpenseCategory::Penlight);
        assert_eq!(o.adjustment, 800);
        assert_eq!(o.suggested_show_id.as_deref(), Some("a"));
        let second = &orders[1];
        assert_eq!(second.store, "通販");
        assert_eq!(second.date, "2025-11-02");
        assert_eq!(second.paid_total, 5_000);
        let d = store_order_expenses(second, None, None);
        assert_eq!(d[0].note, "通販\n配信チケット");
        assert_eq!(d[0].category, ExpenseCategory::Ticket);
    }

    #[test]
    fn prompt_links_carry_the_format() {
        assert!(store_order_ai_prompt().contains(AI_FORMAT));
        assert!(store_order_ai_prompt().contains("penlight=UO代"));
        for link in store_order_ai_links() {
            assert!(link.url.starts_with("https://"));
            assert!(!link.url.contains(' ') && !link.url.contains('+'));
            assert_eq!(link.needs_paste, !link.url.contains("?q="));
        }
    }

    const HISTORY: &str = "購入履歴一覧
ご注文番号\t注文日\t合計金額\t状態\tお問合せ番号\tお支払方法\t詳細
A10232026092702209\t2026/09/27\t4,260円\t商品準備中\t\tクレジットカード\t詳 細
175107202163693924-0\t2026/09/23\t11,000円\t購入済\t\tクレジットカード\t詳 細
A10232026092201582\t2026/09/22\t13,200円\t出荷完了\t366559599195\tクレジットカード\t詳 細
A10232025080308352\t2025/08/03\t16,500円\tキャンセル\t\tクレジットカード\t詳 細
";

    #[test]
    fn reads_order_history_table() {
        let notes = vec!["アソビストア 注文番号 A10232026092201582\nx".to_string()];
        let orders = parse_store_orders(HISTORY, "2026-09-30", &[], &notes);
        assert_eq!(orders.len(), 3, "キャンセルは入れない");
        assert_eq!(orders[0].order_number, "A10232026092702209");
        assert_eq!(orders[0].date, "2026-09-27");
        assert_eq!(orders[0].paid_total, 4_260);
        assert_eq!(orders[0].items[0].category, ExpenseCategory::Goods);
        assert_eq!(orders[1].items[0].category, ExpenseCategory::Ticket);
        assert!(orders[2].already_recorded);
        let d = store_order_expenses(&orders[0], None, None);
        assert_eq!(d[0].amount, 4_260);
        assert_eq!(d[0].note, "アソビストア 注文番号 A10232026092702209\nグッズの注文 (明細なし)");
    }

    #[test]
    fn reads_order_history_one_cell_per_line() {
        let text = HISTORY.replace('\t', "\n");
        assert_eq!(parse_store_orders(&text, "2026-09-30", &[], &[]).len(), 3);
    }

    #[test]
    fn mail_wins_over_history_for_the_same_order() {
        let mail = TICKET_MAIL.replace("100000000000000001-0", "175107202163693924-0");
        let orders = parse_store_orders(&format!("{mail}\n{HISTORY}"), "2026-09-30", &[], &[]);
        let same: Vec<_> = orders.iter().filter(|o| o.order_number == "175107202163693924-0").collect();
        assert_eq!(same.len(), 1);
        assert!(same[0].items[0].name.contains("視聴チケット"));
    }

    #[test]
    fn ignores_text_without_orders() {
        assert!(parse_store_orders("こんにちは", "2026-09-30", &[], &[]).is_empty());
        assert!(parse_store_orders("【注文番号】1-0\n【商品明細】\n", "2026-09-30", &[], &[]).is_empty());
    }
}
