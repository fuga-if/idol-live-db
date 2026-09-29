//! LLM 向けツール面の規則 (カタログと実行)。
//!
//! MCP サーバも CLI も、入口の形が違うだけで **答えの中身はここで決まる**。
//! 「どの語がどのレコードに当たるか」「何を返すか」「何件で切るか」「どう並べるか」は
//! 全部この層の判断で、アダプタ (`agent::mcp` / `stdio` / `cli`) は JSON-RPC の封を開けて
//! ここへ渡し、返った `serde_json::Value` をそのまま書き出すだけにする。
//!
//! ## 返す形の方針
//!
//! 読み手は人間ではなく LLM なので、UI 用の射影 (添字列を返して呼び手が実体化する
//! FFI の作法) は使わない。**1 回の呼び出しで、追加の往復なしに文章が書ける形**まで
//! 名前を解決して返す。id も必ず添える (次の呼び出しの手がかりになる)。
//!
//! ## 歌詞は載せない
//!
//! 歌詞本文は JASRAC の許諾が「D1 に置き、ダウンロードさせない」形で下りている。
//! ここから本文を返すとその前提を外れるので、扱うのは作品コードと掲載有無まで。

pub mod browse;
pub mod lookup;
pub mod predict;
pub mod scope;
pub mod vocab;

use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// ツール 1 件の定義。MCP の `tools/list` にも CLI の `--help` にもこれを使う。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolSpec {
    /// ツール名 (MCP の `name`)。スネークケース。
    pub name: String,
    /// LLM がこれを読んで選ぶ説明。いつ使うか・何が返るかを 1〜3 文で。
    pub description: String,
    /// 入力の JSON Schema (draft 2020-12)。`tool_schema` を通して組む
    /// (`serde_json::Value` で持つので、MCP 応答に埋め込むときにパースが要らず、
    /// 壊れた JSON がそもそも作れない — 以前は `lookup` だけ文字列テンプレートで
    /// 組んでいて、説明文に `"` や改行が 1 つ入ると不正な JSON になっていた)。
    pub input_schema: Value,
}

/// ツール実行の失敗。アダプタはこれを MCP のエラー応答 / CLI の終了コードに写す。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ToolError {
    /// 知らないツール名。
    UnknownTool(String),
    /// 引数が足りない / 型が違う / 値が語彙に無い。
    BadArgs(String),
    /// 指定された id のレコードが無い。
    NotFound(String),
    /// 実行時の失敗 (アダプタ側の I/O 等)。
    Failed(String),
}

impl std::fmt::Display for ToolError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnknownTool(s) => write!(f, "知らないツール: {s}"),
            Self::BadArgs(s) => write!(f, "引数エラー: {s}"),
            Self::NotFound(s) => write!(f, "見つからない: {s}"),
            Self::Failed(s) => write!(f, "実行失敗: {s}"),
        }
    }
}

impl std::error::Error for ToolError {}

/// MCP `initialize` 応答の `instructions`。クライアントはこれをシステムプロンプトに
/// 載せる — ツール一覧だけでは伝わらない「最初の 1 手」の作法を書く。文言も判断なので
/// アダプタ (`crate::agent::mcp`) には置かず、ここに置く。
pub fn server_instructions() -> &'static str {
    "\
このサーバはアイドルマスターのライブ / 楽曲データベースを読む MCP サーバです。

- id は必ず resolve か search で得てから使う。曲名やアイドル名から id を推測して
  組み立てない (表記ゆれで外れる)。
- 歌詞本文は返らない。JASRAC の許諾条件で歌詞本文は別経路 (Web) にしか置いておらず、
  ここでは作品コードと掲載の有無までしか扱わない。
- 新規登録・修正のツールは「提案 (ドラフト) を作る」ところまでで、実データへの反映は
  リポジトリのオーナーの手元の操作が要る。ツールが成功しても「登録した」「直した」とは
  言わず、「ドラフトを用意した、反映はオーナー側の操作が要る」と伝えること。
- セトリ予想を訊かれたら、この DB は予想を持たない。setlist_shape / song_position_profile /
  co_performed_songs / list_shows が返すのは**過去の実績**なので、それを材料に予想は
  自分で組み立て、根拠にした公演数・回数を必ず添えること。"
}

/// 読み取りツールの一覧。並びがそのまま LLM に見える順になる。
///
/// 「まず何を引けばいいか」の順に並べる: 語をほどく `resolve` / `search` を先頭に、
/// 個別の詳細、条件での一覧、集計、最後に語彙。
pub fn tool_catalog() -> Vec<ToolSpec> {
    let mut all = lookup::catalog();
    all.extend(browse::catalog());
    // 「過去はこうだった」を返す 4 本は最後。まず語をほどき、個別を見て、一覧で
    // 数え、そのうえで傾向を訊く、という順に並べる。
    all.extend(predict::catalog());
    all
}

/// 読み取りツールを 1 件実行する。
///
/// `today_key` は JST の「今日」(`YYYY-MM-DD`)。今後/過去の切り分けに使う。
/// 呼び手が渡すのは、テストで日付を固定できるようにするため。
pub fn call_tool(
    snap: &Snapshot,
    name: &str,
    args: &Value,
    today_key: &str,
) -> Result<Value, ToolError> {
    if let Some(r) = lookup::call(snap, name, args, today_key) {
        return r;
    }
    if let Some(r) = browse::call(snap, name, args, today_key) {
        return r;
    }
    if let Some(r) = predict::call(snap, name, args, today_key) {
        return r;
    }
    Err(ToolError::UnknownTool(name.to_string()))
}

/// ツール入力スキーマの封を組む。**`lookup` / `browse` / `predict` / `proposal` の全 24 本がここを通る。**
///
/// 以前は `browse` の `spec()` だけがここを自前で組んでいて (`$schema` +
/// `additionalProperties: false` 付き)、`lookup` は生の JSON 文字列 (`additionalProperties`
/// 無し、しかも `format!` によるテンプレート組み立て)、`proposal` も `additionalProperties`
/// 無しだった。同じサーバのツールなのに、引数を打ち間違えたときの挙動が違っていた
/// (`additionalProperties: false` の 7 本はクライアントのスキーマ検証で弾かれ、
/// 残り 13 本は黙って無視される)。封の決め事をここ 1 箇所に寄せて、全ツールで揃える。
///
/// `required` は「この鍵とこの鍵は必須」という通常のツール向け。id/name のどちらか
/// (排他必須) が要るツール (`lookup::id_or_name_schema`) は `required: &[]` を渡した後、
/// 呼び手が `anyOf` を自分で足す — 空の `required: []` と `anyOf` は共存できる
/// (前者は自明に満たされ、実際の制約は `anyOf` が持つ)。
pub fn tool_schema(properties: Value, required: &[&str]) -> Value {
    json!({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": false,
    })
}

/// 応答 (JSON) を組む道具。**`lookup` も `browse` もここを通す。**
///
/// 「どう書くか」はツールごとの都合ではなく、読む側 (LLM) にとっての一貫性の問題。
/// 各ファイルに小さな組み立て道具を置くと、同じ概念が鍵の名前も型も違う形で出る
/// (実際に `brand` が片方で文字列・片方でオブジェクト、「全員」が `all_cast` と
/// `full_cast` に割れていた)。決め事はここに 1 つずつ置く。
pub mod json {
    use crate::domain::snapshot::Snapshot;
    use serde_json::{Map, Value};

    /// 1 つの列に載せてよい大きさの目安 (バイト)。
    ///
    /// **件数の上限 (`limit`) だけでは守れない。** 1 行の大きさが可変だから —
    /// 歌唱者 30 人ぶんを並べる披露履歴の行は、曲一覧の行の 20 倍になる。
    /// 実測で `song_performances` の 1 回が 31KB (≒8k トークン)、上限指定だと
    /// 100KB に達していた。読む側の予算はバイトで消えるので、バイトで測って切る。
    ///
    /// **これは歯止めであって、主たる制御ではない。** 各ツールの既定件数は
    /// 「ふつうの問いなら 1 回で足りる」大きさに選んであり、そこではここに当たらない。
    /// ここが効くのは LLM が `limit=1000` のような大きな数を書いたとき
    /// (実測: `stats --kind song_play_ranking --limit 1000` が 167KB、
    /// `list_songs --limit 200` が 132KB)。
    ///
    /// 列ごとの目安なので、列が 3 本ある応答はその 3 倍まで伸びうる。
    /// 「1 応答ぶんの予算」にしないのは、列をまたいで配分を決める判断
    /// (どの列を削るか) が列の意味に依存していて、ここでは決められないため。
    pub const MAX_LIST_BYTES: usize = 32 * 1024;

    /// 1 件も当たらなかったときに添える言葉。
    ///
    /// 0 件をそのまま返すと、LLM は「その語は DB に無い」と結論して書いてしまう。
    /// 実際には照合の畳み込み (`text_search_index`) が吸収するのは表記ゆれまでで、
    /// **略称・愛称は吸収しない** (「トラプリ」は `units.name_alt` に入っていない)。
    /// 語彙外の値を候補つきで突き返すのと同じ趣旨で、空振りの理由と次の一手を
    /// 応答自身に持たせる。
    pub const NO_HITS_MESSAGE: &str = "この語では 1 件も当たらない。照合は表記ゆれ (大文字小文字・ひらがな/カタカナ) を吸収するが、略称・愛称は吸収しない。正式名称かその一部で引き直すか、vocabulary で語彙を確かめること。";

    /// 応答オブジェクト。鍵を足す作法 (`put` / `opt` / `list` / `capped`) をここに集める。
    #[derive(Default)]
    pub struct Obj(Map<String, Value>);

    impl Obj {
        pub fn new() -> Self {
            Self::default()
        }

        /// 常に載せる。件数・真偽のように「0 / false にも意味がある」欄はこちら。
        pub fn put(&mut self, key: &str, value: impl Into<Value>) {
            self.0.insert(key.to_string(), value.into());
        }

        /// 値があるときだけ載せる。`null` の羅列は読む量を増やすだけで何も言わない。
        pub fn opt<T: Into<Value>>(&mut self, key: &str, value: Option<T>) {
            if let Some(v) = value {
                self.put(key, v);
            }
        }

        /// 空でないときだけ載せる。空配列を出しても「無い」以上のことは言えない。
        pub fn list(&mut self, key: &str, items: Vec<Value>) {
            if !items.is_empty() {
                self.put(key, Value::Array(items));
            }
        }

        /// 打ち切った列。`<key>_total` を必ず、切ったときだけ `<key>_truncated` を、
        /// 件数ではなく**大きさ**で切ったときは `<key>_truncated_reason: "size"` も添える。
        ///
        /// 理由を分けるのは、次の一手が違うから: 件数で切れたなら `limit` を上げれば
        /// 続きが読めるが、大きさで切れたなら上げても無駄で、条件を絞るしかない。
        pub fn capped(&mut self, key: &str, mut items: Vec<Value>, total: usize) {
            let fits = rows_within_budget(&items, MAX_LIST_BYTES);
            let cut_by_size = fits < items.len();
            items.truncate(fits);
            let shown = items.len();
            self.put(key, Value::Array(items));
            self.put(&format!("{key}_total"), total);
            if total > shown {
                self.put(&format!("{key}_truncated"), true);
            }
            if cut_by_size {
                self.put(&format!("{key}_truncated_reason"), "size");
            }
        }

        /// 別のオブジェクトの鍵をそのまま取り込む。見出し (公演のヘッダなど) を
        /// 入れ子にせず平らに並べたいときに使う。入れ子にしないのは、同じ
        /// 「どの公演か」が一覧でも集計でも同じ鍵で読めるようにするため。
        pub fn merge(&mut self, value: Value) {
            if let Value::Object(map) = value {
                for (k, v) in map {
                    self.0.insert(k, v);
                }
            }
        }

        pub fn value(self) -> Value {
            Value::Object(self.0)
        }
    }

    /// 列が 1 本だけの応答の包み。最上位に `total` / `truncated` を置く
    /// (`resolve` と同じ流儀)。**総数は必ず返す** —「何件ありますか」に
    /// 答えられなくなるため、打ち切った件数だけを返すことはしない。
    pub fn listing(key: &str, total: usize, mut rows: Vec<Value>) -> Value {
        let fits = rows_within_budget(&rows, MAX_LIST_BYTES);
        let cut_by_size = fits < rows.len();
        rows.truncate(fits);
        let mut o = Obj::new();
        o.put("total", total);
        if total > rows.len() {
            o.put("truncated", true);
        }
        if cut_by_size {
            o.put("truncated_reason", "size");
        }
        o.put(key, Value::Array(rows));
        o.value()
    }

    /// 見出しがあって列は 1 本、という応答 (`song` + `performances`、`kind` + `items`)。
    /// [`listing`] の鍵を見出しの隣へ並べる。入れ子にしないのは、列が 1 本のときの
    /// 読み方を `resolve` と同じにそろえるため。
    pub fn listing_with(mut head: Obj, key: &str, total: usize, rows: Vec<Value>) -> Value {
        head.merge(listing(key, total, rows));
        head.value()
    }

    /// 予算 (バイト) に収まる行数。
    ///
    /// **1 行以上は必ず返す。** 0 行にすると「そんな公演は無かった」と読まれかねず、
    /// 予算を守るために嘘をつくことになる。1 行で予算を超える場合はその 1 行を返し、
    /// 切ったことは呼ぶ側が `truncated_reason` で伝える。
    pub fn rows_within_budget(rows: &[Value], budget: usize) -> usize {
        let mut used = 0usize;
        for (i, row) in rows.iter().enumerate() {
            // 区切りの 1 バイトを足して、配列としての実寸に近づける。
            used += serde_json::to_string(row).map_or(0, |s| s.len()) + 1;
            if used > budget {
                return i.max(1);
            }
        }
        rows.len()
    }

    /// ブランドの返し方。**この形が全ツール共通**。
    ///
    /// 以前は詳細系が入れ子 (`{"id","name","short_name"}`)、一覧系が平ら
    /// (`"brand":"cg"` + `"brand_name":"デレマス"`) で、**同じ `brand` という鍵が
    /// 片方では文字列・片方ではオブジェクト**だった。読む側が鍵ごとに型で分岐する。
    ///
    /// オブジェクトに寄せたのは、合同ライブの参加ブランド (`joint_brands`) が
    /// 元からオブジェクトの配列で、そこだけ形を変えようがないから。
    /// ブランドを値型として 1 つに決めれば、単数でも複数でも同じ読み方になる。
    pub fn brand_ref(snap: &Snapshot, brand_id: Option<&str>) -> Option<Value> {
        let brand = snap.brand(brand_id?)?;
        let mut o = Obj::new();
        o.put("id", brand.id.as_str());
        o.put("name", brand.name.as_str());
        o.put("short_name", brand.short_name.as_str());
        Some(o.value())
    }

    /// 合同のときの参加ブランド。`joint_brand_ids` はカンマ区切りの生文字列 ("ml, cg")。
    pub fn joint_brand_refs(snap: &Snapshot, raw: Option<&str>) -> Vec<Value> {
        crate::domain::snapshot::split_csv(raw).filter_map(|bid| brand_ref(snap, Some(bid))).collect()
    }
}

/// 空振りしたときに何を返すか。
///
/// 「語彙外の値は黙って 0 件にしない」は `browse` の `brand` や `stats.kind` では
/// 守れている (候補つき `BadArgs`) のに、**自由文の検索だけが素通り**していた。
/// 0 件をそのまま返すと LLM は「その語は DB に無い」と結論して書いてしまう。
pub mod hints {
    use super::json::{Obj, NO_HITS_MESSAGE};
    use crate::domain::entity_resolution::{term_hits, EntityKind, TermHit};
    use crate::domain::snapshot::Snapshot;
    use serde_json::Value;

    /// 1 件も当たらなかったときに応答へ添える手がかり。
    ///
    /// 定型文だけでは足りない。ユーザーのいちばん自然な聞き方
    /// (「ミリオンライブ 10th」) が 0 件になるので、**どの語が外したのか**を
    /// 返さないと会話が一往復まるごと無駄になる。語ごとの当たりと、
    /// そこから決まる次の呼び出しまで応答に持たせる。
    pub fn no_hits(snap: &Snapshot, query: &str, kinds: &[EntityKind]) -> Value {
        let terms = term_hits(snap, query, kinds);
        let mut o = Obj::new();
        o.put("message", NO_HITS_MESSAGE);

        o.list(
            "terms",
            terms
                .iter()
                .filter(|t| t.total > 0)
                .map(|t| {
                    let mut x = Obj::new();
                    x.put("term", t.term.as_str());
                    x.put("total", t.total);
                    x.list(
                        "hits",
                        t.hits
                            .iter()
                            .map(|h| {
                                let mut y = Obj::new();
                                y.put("kind", h.kind.as_str());
                                y.put("id", h.id.as_str());
                                y.put("name", h.name.as_str());
                                y.value()
                            })
                            .collect(),
                    );
                    x.value()
                })
                .collect(),
        );
        // 当たらなかった語こそ直すべき語。名指しで返す。
        o.list(
            "unmatched_terms",
            terms
                .iter()
                .filter(|t| t.total == 0)
                .map(|t| Value::String(t.term.clone()))
                .collect(),
        );
        o.opt("next", suggested_call(snap, &terms));
        o.value()
    }

    /// 語の当たり方から次の 1 手を決める。
    ///
    /// 決められるのは「**その語が 1 つのブランドに揃う**語があり、他の語が残っている」
    /// 形のとき。ブランドは一覧ツールが直接受け取れる軸なので、残りの語を `query` に
    /// 回せば当たり方が「ブランド AND 語」に変わり、日英の表記ゆれをまたげる。
    /// それ以外の形では黙る (当てずっぽうの助言をしない)。
    fn suggested_call(snap: &Snapshot, terms: &[TermHit]) -> Option<String> {
        let (brand_term, brand_id) =
            terms.iter().find_map(|t| term_brand(snap, t).map(|b| (t.term.as_str(), b)))?;
        let rest: Vec<&TermHit> = terms.iter().filter(|t| t.term != brand_term).collect();
        if rest.is_empty() {
            return None;
        }
        let looks_like = rest
            .iter()
            .flat_map(|t| t.hits.iter())
            .map(|h| h.kind)
            .find(|k| matches!(k, EntityKind::Event | EntityKind::Show | EntityKind::Song));
        // ライブ名で聞かれることがいちばん多いので、手がかりが無いときはそちらに倒す。
        let tool = match looks_like {
            Some(EntityKind::Song) => "list_songs",
            _ => "list_events",
        };
        let query: Vec<&str> = rest.iter().map(|t| t.term.as_str()).collect();
        let brand_name = snap.brand(&brand_id).map_or(brand_id.clone(), |b| b.name.clone());
        Some(format!(
            "{tool} を brand=\"{brand_id}\"・query=\"{}\" で呼ぶとよい (「{brand_term}」は {brand_name} のこと)。",
            query.join(" ")
        ))
    }

    /// その語が指しているブランド。**当たったものが 1 つのブランドに揃うときだけ**返す。
    ///
    /// ブランドそのものに当たる語 (「ミリオン」) はもちろん、ブランドに当たらない語
    /// (「ミリオンライブ」= ライブ 3 件) でも、指している先が 1 ブランドに揃うなら
    /// 軸として使える。揃わない語 (「10th」= cg / ml / sidem) は軸にならない。
    fn term_brand(snap: &Snapshot, term: &TermHit) -> Option<String> {
        let mut found: Option<&str> = None;
        for hit in &term.hits {
            let brand = hit_brand(snap, hit)?;
            match found {
                Some(b) if b != brand => return None,
                _ => found = Some(brand),
            }
        }
        found.map(str::to_string)
    }

    /// 候補 1 件が属するブランド id。ブランドを持たない種別 (作家・会場) は None。
    fn hit_brand<'a>(snap: &'a Snapshot, hit: &'a crate::domain::entity_resolution::EntityHit) -> Option<&'a str> {
        let id = hit.id.as_str();
        match hit.kind {
            EntityKind::Brand => Some(id),
            EntityKind::Event => snap.event(id)?.brand_id.as_deref(),
            EntityKind::Show => {
                let show = snap.show(id)?;
                snap.events[show.event as usize].brand_id.as_deref()
            }
            EntityKind::Song => snap.song(id)?.brand_id.as_deref(),
            EntityKind::Idol => snap.idol(id)?.brand_id.as_deref(),
            EntityKind::Unit => snap.unit(id).map(|u| u.brand_id.as_str()),
            EntityKind::Creator | EntityKind::Venue => None,
        }
    }
}

/// 引数の取り出し。全ツールがここを通ることで、型違いのときの文言が揃う。
///
/// LLM は数値を文字列で寄こしたり、配列を 1 個の文字列で寄こしたりする。厳格に
/// 弾くと会話が 1 往復増えるだけなので、**意味が一意に決まる寄こし方は受ける**
/// (`"12"` → 12、`"cg"` → `["cg"]`)。曖昧なものだけ `BadArgs` で返す。
pub mod args {
    use super::{ToolError, Value};

    /// 文字列。数値・真偽値が来ても綴りに直して受ける。空文字は無いものとして扱う。
    pub fn str_opt(args: &Value, key: &str) -> Option<String> {
        match args.get(key) {
            Some(Value::String(s)) if !s.trim().is_empty() => Some(s.trim().to_string()),
            Some(Value::Number(n)) => Some(n.to_string()),
            Some(Value::Bool(b)) => Some(b.to_string()),
            _ => None,
        }
    }

    /// 必須の文字列。
    pub fn str_req(args: &Value, key: &str) -> Result<String, ToolError> {
        str_opt(args, key).ok_or_else(|| ToolError::BadArgs(format!("{key} は必須です")))
    }

    /// 文字列の配列。1 個だけ文字列で来ても 1 要素の配列として受ける。
    pub fn str_list(args: &Value, key: &str) -> Vec<String> {
        match args.get(key) {
            Some(Value::Array(items)) => items
                .iter()
                .filter_map(|v| v.as_str().map(|s| s.trim().to_string()))
                .filter(|s| !s.is_empty())
                .collect(),
            Some(Value::String(s)) if !s.trim().is_empty() => vec![s.trim().to_string()],
            _ => Vec::new(),
        }
    }

    /// 上限件数。`max` を超える指定は `max` に丸める (LLM が 10000 と書いても壊れない)。
    pub fn limit(args: &Value, default: u32, max: u32) -> Result<u32, ToolError> {
        capped(args, "limit", default, max)
    }

    /// `limit` と同じ丸め方を別の鍵で。件数ではない上限 (`top` = 枠ごとの上位いくつ) は
    /// 鍵を分ける — 同じ `limit` にすると「一覧の件数」と意味が混ざる。
    pub fn capped(args: &Value, key: &str, default: u32, max: u32) -> Result<u32, ToolError> {
        let Some(v) = args.get(key) else { return Ok(default) };
        let n = match v {
            Value::Number(n) => n.as_u64(),
            Value::String(s) => s.trim().parse::<u64>().ok(),
            Value::Null => return Ok(default),
            _ => None,
        }
        .ok_or_else(|| ToolError::BadArgs(format!("{key} は 0 以上の整数です")))?;
        // 先に u64 のまま丸める。`n as u32` を先にすると 4294967296 が 0 になり、
        // 「上限で丸める」つもりが 0 件になる (u32 の剰余)。
        Ok(if n == 0 { default } else { n.min(max as u64) as u32 })
    }

    /// 整数。文字列で来ても受ける。
    pub fn u32_opt(args: &Value, key: &str) -> Result<Option<u32>, ToolError> {
        match args.get(key) {
            None | Some(Value::Null) => Ok(None),
            Some(Value::Number(n)) => n
                .as_u64()
                .and_then(|n| u32::try_from(n).ok())
                .map(Some)
                .ok_or_else(|| ToolError::BadArgs(format!("{key} は 0 以上の整数です"))),
            Some(Value::String(s)) => s
                .trim()
                .parse::<u32>()
                .map(Some)
                .map_err(|_| ToolError::BadArgs(format!("{key} は整数です"))),
            _ => Err(ToolError::BadArgs(format!("{key} は整数です"))),
        }
    }

    /// 真偽値。渡されていなければ `None` (「既定に倒す」のと「指定が無い」のは別物で、
    /// 3 値の軸 — 有り / 無し / 問わない — はこちらでないと書けない)。
    pub fn bool_opt(args: &Value, key: &str) -> Result<Option<bool>, ToolError> {
        match args.get(key) {
            None | Some(Value::Null) => Ok(None),
            _ => bool_or(args, key, false).map(Some),
        }
    }

    /// 真偽値。`"true"` / `"1"` のような寄こし方も受ける。
    ///
    /// **読めない綴りは既定に落とさず `BadArgs` にする。**黙って既定に倒すと、
    /// `"TRUE"` と書いた呼び手は自分の指定が無視されたことに気づけない。
    pub fn bool_or(args: &Value, key: &str, default: bool) -> Result<bool, ToolError> {
        match args.get(key) {
            None | Some(Value::Null) => Ok(default),
            Some(Value::Bool(b)) => Ok(*b),
            Some(Value::Number(n)) => n
                .as_u64()
                .map(|n| n != 0)
                .ok_or_else(|| ToolError::BadArgs(format!("{key} は true / false です"))),
            Some(Value::String(s)) => match s.trim().to_ascii_lowercase().as_str() {
                "true" | "1" | "yes" => Ok(true),
                "false" | "0" | "no" => Ok(false),
                other => Err(ToolError::BadArgs(format!(
                    "{key} は true / false です ({other} は読めません)"
                ))),
            },
            _ => Err(ToolError::BadArgs(format!("{key} は true / false です"))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;
    use serde_json::json;

    #[test]
    fn 数値を文字列で寄こしても受ける() {
        let a = json!({"limit": "25", "month": "7"});
        assert_eq!(args::limit(&a, 20, 100).unwrap(), 25);
        assert_eq!(args::u32_opt(&a, "month").unwrap(), Some(7));
    }

    #[test]
    fn 配列を1個の文字列で寄こしても受ける() {
        assert_eq!(args::str_list(&json!({"brands": "cg"}), "brands"), vec!["cg"]);
        assert_eq!(args::str_list(&json!({"brands": ["cg", " ml "]}), "brands"), vec!["cg", "ml"]);
        assert!(args::str_list(&json!({}), "brands").is_empty());
    }

    #[test]
    fn limit_の桁溢れで0件にならない() {
        // `n as u32` を先にすると 4294967296 → 0 になる。上限で丸まることを固定する。
        assert_eq!(args::limit(&json!({"limit": 4294967296u64}), 20, 100).unwrap(), 100);
        assert!(args::u32_opt(&json!({"year": 4294967296u64}), "year").is_err());
    }

    #[test]
    fn 読めない真偽値は既定に落とさず弾く() {
        assert!(args::bool_or(&json!({"exact": "TRUE"}), "exact", false).unwrap());
        assert!(!args::bool_or(&json!({"exact": "No"}), "exact", true).unwrap());
        assert!(!args::bool_or(&json!({}), "exact", false).unwrap());
        assert!(args::bool_or(&json!({"exact": "たぶん"}), "exact", false).is_err());
    }

    /// 全ツールを 1 巡させるための代表引数。**ツールを足したらここにも足す**
    /// (下の 2 つのテストが「カタログの全名がここに載っていること」を確かめる)。
    ///
    /// id は実データから取る。固定値を書くと、その行が消えた日にテストが
    /// 「通らない」ではなく「何も検査していない」状態に静かに変わる。
    fn 代表引数(snap: &Snapshot) -> Vec<(&'static str, Value)> {
        let idol = &snap.idols[0].id;
        let song = snap
            .songs
            .iter()
            .find(|s| !crate::domain::song_detail_queries::performance_item_indices(snap, &s.id).is_empty())
            .map(|s| s.id.clone())
            .unwrap_or_else(|| snap.songs[0].id.clone());
        let shows: Vec<&str> = snap
            .setlist_items
            .iter()
            .map(|it| snap.shows[it.show as usize].id.as_str())
            .collect();
        let (show_a, show_b) = (shows[0], shows[shows.len() - 1]);
        let event = &snap.events[0].id;
        let brand = &snap.brands[0].id;
        vec![
            ("resolve", json!({"query": "春日未来"})),
            ("search", json!({"query": "夢"})),
            ("get_idol", json!({"id": idol})),
            ("get_song", json!({"id": song})),
            ("get_event", json!({"id": event})),
            ("get_show", json!({"id": show_a})),
            ("vocabulary", json!({})),
            ("list_idols", json!({"brand": brand})),
            ("list_songs", json!({"brand": brand})),
            ("list_events", json!({"brand": brand})),
            ("idol_songs", json!({"idol_id": idol})),
            ("song_performances", json!({"song_id": song})),
            ("setlist_diff", json!({"show_id_a": show_a, "show_id_b": show_b})),
            ("stats", json!({"kind": "song_play_ranking"})),
            ("songs_for_cast", json!({"idol_ids": [idol], "max_missing": 1})),
            ("list_shows", json!({"cast_role": "lead"})),
            ("setlist_shape", json!({"cast_role": "lead"})),
            ("song_position_profile", json!({"song_id": song})),
            ("co_performed_songs", json!({"song_id": song})),
        ]
    }

    /// ツールを足したら代表引数にも足させる。これが無いと、下の禁止フィールド検査が
    /// 新しいツールを素通りして「緑だが守っていない」状態になる。
    #[test]
    fn 全ツールに代表引数がある() {
        let snap = crate::test_support::bundle_snapshot();
        let 表: Vec<&str> = 代表引数(snap).iter().map(|(n, _)| *n).collect();
        for spec in tool_catalog() {
            assert!(表.contains(&spec.name.as_str()), "{} の代表引数が無い", spec.name);
        }
        assert_eq!(表.len(), tool_catalog().len(), "代表引数に余分な名前がある");
    }

    /// 歌詞サイトの URL と試聴 URL はどのツールからも出さない。
    ///
    /// 歌詞本文だけの話ではない。`Song::lyrics_url` は大半の曲に歌詞サイトの URL が
    /// 入っていて、返せば取り込み元サイト名を配ったことになる。`preview_url` は
    /// アプリの中でだけ鳴らすもの。`serde_json::to_value(song)` と 1 行書けば漏れる形なので、
    /// 人の注意ではなく機械で止める (Web 出面の T12 と同じ役目)。
    ///
    /// 検査する URL は**実データから取る**。ホスト名をこのファイルに書くと、
    /// 公開リポジトリに取り込み元サイト名を書くことになって本末転倒になる。
    #[test]
    fn どのツールも歌詞サイトと試聴の_url_を返さない() {
        let snap = crate::test_support::bundle_snapshot();
        // or ではなく chain。両方を持つ曲から片方しか検査値に入らないと、
        // 欄名を変えられたときに二重の網が片方しか効かない。
        // 空文字は URL ではない (DB には NULL と '' が混ざる)。入れるとどの出力も
        // `contains("")` で引っかかり、検査にならない。
        let 禁止値: Vec<&str> = snap
            .songs
            .iter()
            .flat_map(|s| [s.lyrics_url.as_deref(), s.preview_url.as_deref()])
            .flatten()
            .filter(|v| !v.is_empty())
            .collect();
        assert!(!禁止値.is_empty(), "実データに検査対象が無い (テストが空振りしている)");

        for (name, args) in 代表引数(snap) {
            let out = match call_tool(snap, name, &args, "2026-09-19") {
                Ok(v) => v.to_string(),
                // 引数が実データに合わず引けなかった場合も、その事実を隠さない。
                Err(e) => panic!("{name} が代表引数で失敗した: {e}"),
            };
            assert!(!out.contains("lyrics_url"), "{name} が lyrics_url を返している");
            assert!(!out.contains("preview_url"), "{name} が preview_url を返している");
            for 値 in &禁止値 {
                assert!(!out.contains(値), "{name} が歌詞/試聴の URL を返している");
            }
        }
    }

    #[test]
    fn 大きさで切るときは理由を添える() {
        use json::{rows_within_budget, Obj, MAX_LIST_BYTES};
        let big = |n: usize| -> Vec<Value> {
            (0..n).map(|i| json!({ "i": i, "pad": "x".repeat(200) })).collect()
        };
        // 予算に収まるぶんだけ残る。
        assert_eq!(rows_within_budget(&big(1000), 1000), 4);
        assert_eq!(rows_within_budget(&[], 1000), 0);
        // 1 行で予算を超えても 0 行にはしない (0 件は「無かった」と読まれる)。
        assert_eq!(rows_within_budget(&big(3), 10), 1);

        // 件数で切れたときと、大きさで切れたときで理由が分かれる。
        let mut few = Obj::new();
        few.capped("rows", big(3), 10);
        assert_eq!(few.value()["rows_truncated_reason"], Value::Null);

        let mut many = Obj::new();
        many.capped("rows", big(MAX_LIST_BYTES), MAX_LIST_BYTES);
        let v = many.value();
        assert_eq!(v["rows_truncated"], json!(true));
        assert_eq!(v["rows_truncated_reason"], json!("size"));
        assert!(serde_json::to_string(&v["rows"]).unwrap().len() <= MAX_LIST_BYTES + 512);
    }

    #[test]
    fn ブランドはどこでも同じ形で返る() {
        let snap = bundle_snapshot();
        let brand = json::brand_ref(snap, Some("cg")).expect("cg はある");
        assert_eq!(brand["id"], "cg");
        assert_eq!(brand["short_name"], "デレマス");
        assert!(brand["name"].as_str().unwrap().contains("CINDERELLA"));
        assert!(json::brand_ref(snap, Some("無いブランド")).is_none());
        assert!(json::brand_ref(snap, None).is_none());

        // 合同は同じ形の配列。単数と複数で読み方が変わらない。
        let joint = json::joint_brand_refs(snap, Some("ml, cg"));
        assert_eq!(joint.len(), 2);
        assert_eq!(joint[0]["id"], "ml");
    }

    #[test]
    fn 当たらない語は分解して手がかりを返す() {
        let snap = bundle_snapshot();
        // QA 実測: ユーザーのいちばん自然な聞き方が 0 件になる。
        // 実イベント名が "THE IDOLM@STER MILLION LIVE! 10thLIVE TOUR ..." で
        // 日本語の「ミリオン」を含まないため。
        for query in ["ミリオンライブ 10th", "ミリオン 10th"] {
            let help = hints::no_hits(snap, query, &[]);
            assert!(help["message"].as_str().unwrap().contains("略称"), "{help}");

            let hit_terms: Vec<&str> = help["terms"]
                .as_array()
                .map(|a| a.iter().map(|t| t["term"].as_str().unwrap()).collect())
                .unwrap_or_default();
            assert!(
                hit_terms.contains(&"10th"),
                "どの語が当たるのかを返していない ({query}): {help}"
            );
        }

        // 「ミリオン」はブランドに決まるので、次に打つ呼び出しまで名指しできる。
        let help = hints::no_hits(snap, "ミリオン 10th", &[]);
        let next = help["next"].as_str().unwrap_or_default();
        assert!(next.contains("list_events"), "次の一手が無い: {help}");
        assert!(next.contains("brand=\"ml\""), "ブランドを解けていない: {help}");
        assert!(next.contains("query=\"10th\""), "残りの語を渡していない: {help}");

        // 「ミリオンライブ」自体はブランドに当たらない (当たるのはライブ 3 件) が、
        // その 3 件が全部 ml なので軸として使える。ここまで解けて初めて正解に届く。
        let help = hints::no_hits(snap, "ミリオンライブ 10th", &[]);
        let next = help["next"].as_str().unwrap_or_default();
        assert!(next.contains("brand=\"ml\"") && next.contains("query=\"10th\""), "{help}");

        // 語が 1 つだけなら分けようがない (定型の言葉だけを返す)。
        let single = hints::no_hits(snap, "トラプリ", &[]);
        assert!(single["terms"].is_null() && single["next"].is_null(), "{single}");
    }

    /// 読み取り 18 本 + 書き込み 6 本、計 24 本すべてで封 (`tool_schema` の出力) が
    /// 揃っていることを固定する。以前は `additionalProperties: false` が browse の
    /// 7 本にしか付いておらず、残り 13 本は引数を打ち間違えても黙って無視されていた
    /// (レビュー指摘)。ここで 1 本でも漏れたら壊れるようにする。
    #[test]
    fn 全25本のツールでスキーマの封が揃っている() {
        let mut all = tool_catalog();
        all.extend(crate::agent::proposal::proposal_catalog());
        assert_eq!(all.len(), 25, "ツール数が変わった (この数を変えたら意図的か確認すること)");

        let mut names: Vec<&str> = all.iter().map(|s| s.name.as_str()).collect();
        names.sort();
        names.dedup();
        assert_eq!(names.len(), all.len(), "ツール名が重複している");

        for spec in &all {
            assert!(!spec.description.is_empty(), "{} に説明が無い", spec.name);
            let schema = &spec.input_schema;
            assert_eq!(schema["type"], "object", "{} の type", spec.name);
            assert!(schema["properties"].is_object(), "{} の properties", spec.name);
            assert!(schema["$schema"].is_string(), "{} に $schema が無い", spec.name);
            assert_eq!(
                schema["additionalProperties"],
                Value::Bool(false),
                "{} に additionalProperties: false が無い",
                spec.name
            );
        }
    }
}
