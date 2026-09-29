//! データ投入ドラフトの組み立て規則。
//!
//! 新規登録は **`data/` に JSON を置くところまで**で止める。反映 (`--apply --push`) は
//! オーナーの手元にしかない鍵が要る操作で、CloudKit が source of truth なので、
//! ここから本番へ直接書く経路は作らない (`docs/DATA_PIPELINE.md`)。
//!
//! ## 出典を必須にする
//!
//! LLM は自信ありげに事実でないことを書く。`source` (一次ソースの URL) と
//! `source_quote` (その URL のどこにその事実が書いてあるかの逐語引用) を
//! **構造として必須**にし、無ければドラフトを組まない。
//!
//! `tools/apply_data.py --check` も投稿の出典を必須にしている (`a3527aac`。ファイルの先頭か
//! 全項目に `source` があること)。`source`/`source_quote` はドラフトの **トップレベル 1 箇所**
//! (`title` / `author` と同じ層) に置くので、ファイル単位の出典としてそのまま通り、
//! 各種別ごとの「未知の列」判定 (songs は許すが idols/events は許さない、等) も気にしなくて済む。
//!
//! ただし機械に確かめられるのは「出典が書いてあるか」までで、URL の中身が本当にその事実を
//! 裏付けているか (`source_quote` が捏造でないか) は確かめようがない。LLM 発の提案には
//! 人間が書く PR 説明欄が無く、ドラフト JSON 自体が提案の全てなので、`--check` に
//! レビューの責任を移さない。**「人間が最短時間で裏取りできる材料をドラフトに残す」
//! ところまでがこの関数の仕事**で、正しさの判定はあくまで人間のレビューに委ねる。

use crate::agent::tools::{args, tool_schema};
pub use crate::agent::tools::{ToolError, ToolSpec};
use serde_json::{json, Value};

/// `data/` 配下、どの種別のドラフトか。ディレクトリとファイル名の両方をここから決める
/// (`ProposalDraft::file_name` 参照)。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProposalKind {
    Song,
    Event,
    Setlist,
    Idol,
    Fix,
}

impl ProposalKind {
    /// `data/` 配下のディレクトリ名。
    pub fn dir(self) -> &'static str {
        match self {
            ProposalKind::Song => "songs",
            ProposalKind::Event => "events",
            ProposalKind::Setlist => "setlists",
            ProposalKind::Idol => "idols",
            ProposalKind::Fix => "fixes",
        }
    }

    /// ファイル名に埋め込む短いタグ。異なる種別が同じ日付・同じ slug でも
    /// ファイル名として衝突しないようにする (下記 `build_file_name` の注記参照)。
    fn tag(self) -> &'static str {
        match self {
            ProposalKind::Song => "song",
            ProposalKind::Event => "event",
            ProposalKind::Setlist => "setlist",
            ProposalKind::Idol => "idol",
            ProposalKind::Fix => "fix",
        }
    }
}

/// 組み上がったドラフト 1 件。ファイルには書かない (書くのはアダプタ)。
///
/// パスを `String` (`rel_path`) 1 本で持たせない。`kind` (固定の enum) と `file_name`
/// (このモジュール内で検証済みの安全な値) に分けているのは、LLM 由来の値が
/// パス区切りを含んだまま `data/../../etc/passwd` のような経路を組めてしまう型を
/// そもそも作らないため。ディレクトリとの結合はアダプタ (`agent::proposal_io`) 側で行い、
/// そこでも `canonicalize` して `data/<kind>/` の外に出ていないかを検算する
/// (型で保証していても、経路の組み立てそのものは最後の砦として検算する)。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProposalDraft {
    pub kind: ProposalKind,
    /// ファイル名 (拡張子込み・ディレクトリ無し)。`build_file_name` を通っているので
    /// パス区切り・`.`/`..` 単体・制御文字は含まない。
    pub file_name: String,
    /// そのまま書き出す JSON 本文 (整形済み・末尾改行あり)。
    pub contents: String,
    /// 人間とLLMに見せる要約。**ファイル名/パスを一切含めない** (QA 実測バグ)。
    ///
    /// ここで `display_path()` を埋め込んで文字列に焼き込むと、書き込み直前に
    /// 連番衝突回避 (`agent::proposal_io::reserve_file_name`) でファイル名が変わった
    /// ときに、`summary` だけ存在しない古いファイル名を指したまま残る
    /// (`draft.path` は正しい実ファイルを指すのに、`draft.summary` は違う場所を
    /// 案内する、という食い違いが実際に QA で見つかった)。パスを知りたければ
    /// 呼び手は `path` (アダプタが書き込み後の実ファイル名で組む) を見ればよく、
    /// `summary` にパスを持たせる理由が無い。ファイル名の置き場所は 1 箇所に絞る。
    pub summary: String,
    /// 出典についての注意書き。**全ドラフトに常時付ける** (RedTeam M4)。
    ///
    /// 既知の一次ソースホストのときだけ無言にすると、「素朴な捏造 (個人ブログ) は
    /// 捕まるのに、上手な捏造 (`idolmaster-official.jp/news/<でっち上げ>` のような
    /// 既知ドメインっぽい URL) ほど無警告になる」という逆インセンティブが生まれる。
    /// 機械は `source_quote` が本当に URL の中身と一致するかを確認していない、という
    /// 事実は常に明示し、未知ホストのときだけ追加の注意を足す。拒否はしない
    /// (正当な一次ソースを機械的に弾く害の方が大きい) — あくまで人間のレビューへの申し送り。
    pub source_advisory: String,
}

impl ProposalDraft {
    /// 人間に見せる表示用パス (`data/songs/....json`)。書き込み先の決定には使わない
    /// (それはアダプタが `kind.dir()` から自分で組む)。
    pub fn display_path(&self) -> String {
        format!("data/{}/{}", self.kind.dir(), self.file_name)
    }
}

/// `data/README.md` に書かれている値の語彙。**判定には使わない** (それは `--check` の仕事)。
/// JSON Schema の `enum` に載せて LLM に案内するためだけの一覧。
const BRAND_IDS: &[&str] = &["765as", "cg", "ml", "sidem", "sc", "gakuen", "876", "961", "other"];
const SONG_TYPES: &[&str] = &["solo", "unit", "all", "tie_in", "cover"];
const EVENT_KINDS: &[&str] = &["live", "festival", "release_event", "radio", "stream", "other"];
const FIX_TABLES: &[&str] = &["idols", "songs", "events", "shows", "units", "brands"];

/// 既知の一次ソースのホスト (推奨一覧・実績ベース — このリポジトリの `data/**/*.json` と
/// コミット履歴で実際に一次ソースとして使われてきたドメイン)。**ここに無くても拒否はしない**
/// — 知らないドメインを機械的に弾くと、正当な一次ソース (新しい公式サイト等) まで
/// 弾いてしまう害の方が大きい。無いときは結果に注意書きを添えるだけに留める。
const KNOWN_SOURCE_HOSTS: &[&str] = &[
    "idolmaster-official.jp",
    "lantis.jp",
    "asobistore.jp",
    "music.apple.com",
    "itunes.apple.com",
    "columbia.jp",
    "bandainamcomusiclive.co.jp",
    "jasrac.or.jp",
];

/// `check_proposals` を `file` 省略で呼んだときに自動検証する上限件数 (RedTeam M5)。
///
/// `tools/apply_data.py --check --only <file>` は python の起動と DB オープンを
/// 毎回やり直すので 1 回あたり実測 0.29 秒かかる。MCP クライアントのツール呼び出し
/// タイムアウトは一般に 30〜60 秒なので、上限なく `data/` 全件 (実測 69 件 = 20 秒超) を
/// 回すとタイムアウトに触れる。20 件なら 0.29 秒 × 20 ≈ 5.8 秒で、遅い環境でも
/// 十分な余裕を残せる。値そのものは判断なのでここに置き、`agent::proposal_io` は
/// この定数を読むだけにする。
pub const MAX_AUTO_CHECK_FILES: usize = 20;

/// `propose_fix` の `fields` に含めてはいけない列 (RedTeam L1)。
///
/// `table: "songs"` に任意の `fields` を書ける以上、歌詞/試聴 URL をここ経由で
/// 混入させる経路が残ってしまう。歌詞本文そのものを返す訳ではないので「漏洩」では
/// ないが、読み取り側 (`agent::tools`) がこの 2 列を意図的に隠している以上、
/// 書き込み側でも同じ列は塞いでおく。
const FORBIDDEN_FIX_FIELDS: &[&str] = &["lyrics_url", "preview_url"];

/// 書き込み (ドラフト作成) ツールの一覧。
pub fn proposal_catalog() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            name: "propose_song".to_string(),
            description: "新曲を追加するドラフトを data/songs/ に作り、\
                tools/apply_data.py --check で検証する。source (一次ソースの URL) と \
                source_quote (その逐語引用) と original_singers (原唱者、idol id の配列) が \
                必須。apple_music_id を入れるなら artwork_url も入れること。\
                反映 (--apply --push) にはオーナーの操作が別途必要で、ここでは実行しない。"
                .to_string(),
            input_schema: tool_schema(
                json!({
                    "id": {
                        "type": "string",
                        "description": "曲の id。規則: {brand_id}_{タイトルのsnake_case} \
                            (例: ml_example_song)。既存の id と衝突すると --check で弾かれる。",
                    },
                    "title": { "type": "string", "description": "曲名" },
                    "title_kana": { "type": "string", "description": "曲名の読み仮名 (任意)" },
                    "brand_id": { "type": "string", "enum": BRAND_IDS },
                    "song_type": { "type": "string", "enum": SONG_TYPES },
                    "release_date": { "type": "string", "description": "YYYY-MM-DD (任意)" },
                    "unit_id": { "type": "string", "description": "歌唱ユニットの id (任意)" },
                    "unit_name": { "type": "string", "description": "ユニット表記名 (任意)" },
                    "composer": { "type": "string", "description": "作曲者。複数人は「、」区切り (任意)" },
                    "lyricist": { "type": "string", "description": "作詞者。複数人は「、」区切り (任意)" },
                    "arranger": { "type": "string", "description": "編曲者。複数人は「、」区切り (任意)" },
                    "apple_music_id": {
                        "type": "string",
                        "description": "入れる場合は artwork_url も一緒に入れること \
                            (一覧のジャケ写は artwork_url を直参照するため)。",
                    },
                    "artwork_url": { "type": "string", "description": "ジャケット画像の URL (Apple Music の mzstatic 等・任意)" },
                    "original_singers": {
                        "type": "array",
                        "items": { "type": "string" },
                        "minItems": 1,
                        "description": "原唱者の idol id 配列。必須 \
                            (一覧の performer アイコン表示に使う)。",
                    },
                    "note": { "type": "string", "description": "追加の根拠・補足 (任意)" },
                    "source": {
                        "type": "string",
                        "description": "一次ソースの URL。必須 — 無いとドラフトを作らない。",
                    },
                    "source_quote": {
                        "type": "string",
                        "description": "source の該当箇所の逐語引用。必須。\
                            URL だけでは人間が中身の裏付けを確認できないため。",
                    },
                }),
                &["id", "title", "brand_id", "song_type", "original_singers", "source", "source_quote"],
            ),
        },
        ToolSpec {
            name: "propose_event".to_string(),
            description: "ライブ/イベントを追加するドラフトを data/events/ に作り、\
                tools/apply_data.py --check で検証する。1 件のイベントに 1 件以上の \
                shows (公演) を添える。source/source_quote が必須。\
                反映にはオーナーの操作が別途必要で、ここでは実行しない。"
                .to_string(),
            input_schema: tool_schema(
                json!({
                    "id": { "type": "string", "description": "event id。規則: ev_{slug}" },
                    "brand_id": { "type": "string", "enum": BRAND_IDS },
                    "name": { "type": "string", "description": "イベント名" },
                    "event_type": {
                        "type": "string",
                        "description": "催しの性格 (任意)。anniversary / orchestra / external_event / \
                                        birthday / release_event / broadcast / live。\
                                        **名前から決められなければ \
                                        空のまま**にする (推測で埋めると「オケマスを除けば」\
                                        「周年では」の答えが変わる)。意味と優先順位は \
                                        docs/DATA_PIPELINE.md 「events の種別 (event_type)」",
                    },
                    "kind": { "type": "string", "enum": EVENT_KINDS },
                    "is_streaming": { "description": "0 か 1 (任意)" },
                    "is_solo": { "description": "0 か 1 (任意)" },
                    "shows": {
                        "type": "array",
                        "minItems": 1,
                        "description": "公演 (最低 1 件)。show id 規則: sh_{slug}_{連番}",
                        "items": {
                            "type": "object",
                            "properties": {
                                "id": { "type": "string" },
                                "name": { "type": "string", "description": "例: DAY1" },
                                "date": { "type": "string", "description": "YYYY-MM-DD" },
                                "venue": { "type": "string" },
                                "venue_city": { "type": "string" },
                                "start_time": { "type": "string" },
                                "sort_order": { "description": "整数 (任意)" },
                            },
                            "required": ["id", "name", "date"],
                        },
                    },
                    "note": { "type": "string", "description": "追加の根拠・補足 (任意)" },
                    "source": {
                        "type": "string",
                        "description": "一次ソースの URL。必須 — 無いとドラフトを作らない。",
                    },
                    "source_quote": {
                        "type": "string",
                        "description": "source の該当箇所の逐語引用。必須。",
                    },
                }),
                &["id", "brand_id", "name", "kind", "shows", "source", "source_quote"],
            ),
        },
        ToolSpec {
            name: "propose_setlist".to_string(),
            description: "1 公演ぶんのセットリストを追加するドラフトを data/setlists/ に作り、\
                tools/apply_data.py --check で検証する。曲は song_id (確実) か title \
                (brand 内一意なら解決できる) のどちらかで指定する。source/source_quote が \
                必須。反映にはオーナーの操作が別途必要で、ここでは実行しない。"
                .to_string(),
            input_schema: tool_schema(
                json!({
                    "show_id": { "type": "string", "description": "対象公演の shows.id" },
                    "all_performers": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "performers: \"all\" が指す全員の idol id (任意)",
                    },
                    "songs": {
                        "type": "array",
                        "minItems": 1,
                        "description": "公演の曲を 1 曲 1 要素で。曲は song_id か title のどちらかで指す。",
                        "items": {
                            "type": "object",
                            "properties": {
                                "position": { "type": "integer", "description": "セトリの位置 (1始まり)" },
                                "song_id": { "type": "string" },
                                "title": {
                                    "type": "string",
                                    "description": "song_id が無ければ brand 内で曲名一致解決を試みる",
                                },
                                "performers": {
                                    "description": "\"all\" か idol_id の配列。必須。",
                                },
                                "section": { "type": "string", "description": "例: アンコール" },
                                "notes": { "type": "string" },
                            },
                            "required": ["position", "performers"],
                        },
                    },
                    "note": { "type": "string", "description": "追加の根拠・補足 (任意)" },
                    "source": {
                        "type": "string",
                        "description": "一次ソースの URL (公式セットリスト画像等)。必須。",
                    },
                    "source_quote": {
                        "type": "string",
                        "description": "source の該当箇所の逐語引用。必須。",
                    },
                }),
                &["show_id", "songs", "source", "source_quote"],
            ),
        },
        ToolSpec {
            name: "propose_idol".to_string(),
            description: "アイドルを追加するドラフトを data/idols/ に作り、\
                tools/apply_data.py --check で検証する。source/source_quote が必須。\
                反映にはオーナーの操作が別途必要で、ここでは実行しない。"
                .to_string(),
            input_schema: tool_schema(
                json!({
                    "id": { "type": "string", "description": "idol id。規則: {brand_id}_{name}" },
                    "brand_id": { "type": "string", "enum": BRAND_IDS },
                    "name": { "type": "string" },
                    "name_kana": { "type": "string" },
                    "birthday": { "type": "string", "description": "MM-DD" },
                    "blood_type": { "type": "string", "description": "A / B / O / AB (任意)" },
                    "height": { "description": "cm (任意)" },
                    "birth_place": { "type": "string" },
                    "constellation": { "type": "string", "description": "例: 獅子座 (任意)" },
                    "description": { "type": "string" },
                    "brands": {
                        "type": "array",
                        "description": "所属ブランド (複数可)。省略すると \
                            brand_id 1 件・is_primary=1 で補う。",
                        "items": {
                            "type": "object",
                            "properties": {
                                "brand_id": { "type": "string", "enum": BRAND_IDS },
                                "is_primary": { "description": "0 か 1" },
                            },
                            "required": ["brand_id"],
                        },
                    },
                    "note": { "type": "string", "description": "追加の根拠・補足 (任意)" },
                    "source": {
                        "type": "string",
                        "description": "一次ソースの URL。必須 — 無いとドラフトを作らない。",
                    },
                    "source_quote": {
                        "type": "string",
                        "description": "source の該当箇所の逐語引用。必須。",
                    },
                }),
                &["id", "brand_id", "name", "source", "source_quote"],
            ),
        },
        ToolSpec {
            name: "propose_fix".to_string(),
            description: "既存レコード 1 件を修正するドラフトを data/fixes/ に作り、\
                tools/apply_data.py --check で検証する。table は \
                idols/songs/events/shows/units/brands のいずれか。source/source_quote が \
                必須。反映にはオーナーの操作が別途必要で、ここでは実行しない。"
                .to_string(),
            input_schema: tool_schema(
                json!({
                    "table": { "type": "string", "enum": FIX_TABLES, "description": "修正するレコードの表" },
                    "id": { "type": "string", "description": "対象レコードの id" },
                    "fields": {
                        "type": "object",
                        "minProperties": 1,
                        "description": "変更するフィールドの 列名 → 新しい値。id は変更不可。",
                    },
                    "note": { "type": "string", "description": "追加の根拠・補足 (任意)" },
                    "source": {
                        "type": "string",
                        "description": "一次ソースの URL。必須 — 無いとドラフトを作らない。",
                    },
                    "source_quote": {
                        "type": "string",
                        "description": "source の該当箇所の逐語引用。必須。",
                    },
                }),
                &["table", "id", "fields", "source", "source_quote"],
            ),
        },
        ToolSpec {
            name: "check_proposals".to_string(),
            description: "いま data/ にある未反映のドラフトを tools/apply_data.py --check で \
                検証し直す。file (ファイル名。パスではない) を渡すとそのファイル 1 件だけに \
                絞る。省略時は data/ 配下の各ファイルを 1 件ずつ個別に検証し、ファイルごとの結果を返す。\
                何も書き込まない読み取り専用ツール。"
                .to_string(),
            input_schema: tool_schema(
                json!({
                    "file": {
                        "type": "string",
                        "description": "検証対象を 1 ファイルに絞るときのファイル名 (省略時は全件を個別に検証)",
                    },
                }),
                &[],
            ),
        },
    ]
}

/// `name` が書き込み (ドラフト作成) ツールかどうか。`agent::mod::dispatch` が
/// 読み取り/書き込みを振り分けるために使う (所属の判断も domain の持ち物なので、
/// カタログを毎回組み直して線形探索するより、ここに直接持たせる方が置き場所としても
/// 実装としても正しい)。カタログの名前一覧との整合は `#[test]` で確かめる。
pub fn is_proposal_tool(name: &str) -> bool {
    matches!(
        name,
        "propose_song" | "propose_event" | "propose_setlist" | "propose_idol" | "propose_fix" | "check_proposals"
    )
}

/// ドラフトを組む。純粋関数 — ファイルにも DB にも触らない。
///
/// `today_key` は JST の「今日」(`YYYY-MM-DD`)。ファイル名の日付部分に使う。
/// ここで `SystemTime` 等を直接読まないのは、呼び手 (`agent::proposal_io`) が
/// `Ctx::today_key` を渡せば決定的にテストできるようにするため
/// (`tools::call_tool` が `today_key` を引数で受けるのと同じ理由)。
///
/// `check_proposals` はここに来ない (ドラフトを組まないので) — `agent::proposal_io::run`
/// が名前で先に分岐する。渡ってきた場合は `UnknownTool` として扱う。
pub fn build_proposal(name: &str, args: &Value, today_key: &str) -> Result<ProposalDraft, ToolError> {
    match name {
        "propose_song" => build_song(args, today_key),
        "propose_event" => build_event(args, today_key),
        "propose_setlist" => build_setlist(args, today_key),
        "propose_idol" => build_idol(args, today_key),
        "propose_fix" => build_fix(args, today_key),
        other => Err(ToolError::UnknownTool(other.to_string())),
    }
}

// ---- 組み立て本体 -----------------------------------------------------------

fn build_song(a: &Value, today_key: &str) -> Result<ProposalDraft, ToolError> {
    let id = args::str_req(a, "id")?;
    let title = args::str_req(a, "title")?;
    let brand_id = args::str_req(a, "brand_id")?;
    let song_type = args::str_req(a, "song_type")?;
    let original_singers = args::str_list(a, "original_singers");
    if original_singers.is_empty() {
        return Err(ToolError::BadArgs(
            "original_singers (原唱者) は必須です。1 件以上の idol id を指定してください。"
                .to_string(),
        ));
    }
    let source = require_source(a)?;

    let mut song: Vec<(&'static str, Field)> =
        vec![("id", Field::leaf(&id)), ("title", Field::leaf(&title))];
    push_opt(&mut song, a, "title_kana");
    song.push(("brand_id", Field::leaf(&brand_id)));
    song.push(("song_type", Field::leaf(&song_type)));
    push_opt(&mut song, a, "release_date");
    push_opt(&mut song, a, "unit_id");
    push_opt(&mut song, a, "unit_name");
    push_opt(&mut song, a, "composer");
    push_opt(&mut song, a, "lyricist");
    push_opt(&mut song, a, "arranger");
    push_opt(&mut song, a, "apple_music_id");
    push_opt(&mut song, a, "artwork_url");
    song.push(("original_singers", Field::Leaf(json!(original_singers))));

    let kind = ProposalKind::Song;
    let file_name = build_file_name(kind, today_key, &id)?;
    let title_text = format!("曲「{title}」({brand_id}) の追加");
    let top = doc_fields(&title_text, a, &source, "propose_song", vec![("songs", Field::Arr(vec![Field::Obj(song)]))]);
    let source_advisory = source_host_advisory(&source.url);
    Ok(ProposalDraft {
        kind,
        file_name,
        contents: render(top),
        summary: format!("曲「{title}」({brand_id}) を追加するドラフト"),
        source_advisory,
    })
}

fn build_event(a: &Value, today_key: &str) -> Result<ProposalDraft, ToolError> {
    let id = args::str_req(a, "id")?;
    let brand_id = args::str_req(a, "brand_id")?;
    let name = args::str_req(a, "name")?;
    let kind_val = args::str_req(a, "kind")?;
    let source = require_source(a)?;

    let shows_val = a
        .get("shows")
        .and_then(Value::as_array)
        .filter(|v| !v.is_empty())
        .ok_or_else(|| ToolError::BadArgs("shows は 1 件以上必須です。".to_string()))?;

    let mut shows = Vec::with_capacity(shows_val.len());
    for (i, sh) in shows_val.iter().enumerate() {
        let prefix = format!("shows[{i}]");
        let sid = args::str_req(sh, "id").map_err(|e| with_prefix(&prefix, e))?;
        let sname = args::str_req(sh, "name").map_err(|e| with_prefix(&prefix, e))?;
        let sdate = args::str_req(sh, "date").map_err(|e| with_prefix(&prefix, e))?;
        let mut show: Vec<(&'static str, Field)> = vec![
            ("id", Field::leaf(&sid)),
            ("name", Field::leaf(&sname)),
            ("date", Field::leaf(&sdate)),
        ];
        push_opt(&mut show, sh, "venue");
        push_opt(&mut show, sh, "venue_city");
        push_opt(&mut show, sh, "start_time");
        push_opt(&mut show, sh, "sort_order");
        shows.push(Field::Obj(show));
    }
    let show_count = shows.len();

    let mut event: Vec<(&'static str, Field)> = vec![
        ("id", Field::leaf(&id)),
        ("brand_id", Field::leaf(&brand_id)),
        ("name", Field::leaf(&name)),
    ];
    push_opt(&mut event, a, "event_type");
    event.push(("kind", Field::leaf(&kind_val)));
    push_opt(&mut event, a, "is_streaming");
    push_opt(&mut event, a, "is_solo");
    event.push(("shows", Field::Arr(shows)));

    let kind = ProposalKind::Event;
    let file_name = build_file_name(kind, today_key, &id)?;
    let title_text = format!("イベント「{name}」({brand_id}) の追加");
    let top = doc_fields(&title_text, a, &source, "propose_event", vec![("events", Field::Arr(vec![Field::Obj(event)]))]);
    let source_advisory = source_host_advisory(&source.url);
    Ok(ProposalDraft {
        kind,
        file_name,
        contents: render(top),
        summary: format!("イベント「{name}」({brand_id}) + 公演 {show_count} 件を追加するドラフト"),
        source_advisory,
    })
}

fn build_setlist(a: &Value, today_key: &str) -> Result<ProposalDraft, ToolError> {
    let show_id = args::str_req(a, "show_id")?;
    let source = require_source(a)?;

    let songs_val = a
        .get("songs")
        .and_then(Value::as_array)
        .filter(|v| !v.is_empty())
        .ok_or_else(|| ToolError::BadArgs("songs は 1 件以上必須です。".to_string()))?;

    let mut songs = Vec::with_capacity(songs_val.len());
    for (i, sg) in songs_val.iter().enumerate() {
        let prefix = format!("songs[{i}]");
        let position = args::u32_opt(sg, "position")
            .map_err(|e| with_prefix(&prefix, e))?
            .ok_or_else(|| ToolError::BadArgs(format!("{prefix}: position は必須です。")))?;

        let performers = sg.get("performers").cloned().ok_or_else(|| {
            ToolError::BadArgs(format!("{prefix}: performers は必須です (\"all\" か idol_id 配列)。"))
        })?;
        let performers_ok = performers.as_str() == Some("all") || performers.is_array();
        if !performers_ok {
            return Err(ToolError::BadArgs(format!(
                "{prefix}: performers は \"all\" か idol_id 配列で指定してください。"
            )));
        }

        let has_song_ref = args::str_opt(sg, "song_id").is_some() || args::str_opt(sg, "title").is_some();
        if !has_song_ref {
            return Err(ToolError::BadArgs(format!(
                "{prefix}: song_id か title のどちらかが必要です (曲を特定できません)。"
            )));
        }

        let mut song: Vec<(&'static str, Field)> = vec![("position", Field::Leaf(json!(position)))];
        push_opt(&mut song, sg, "song_id");
        push_opt(&mut song, sg, "title");
        song.push(("performers", Field::Leaf(performers)));
        push_opt(&mut song, sg, "section");
        push_opt(&mut song, sg, "notes");
        songs.push(Field::Obj(song));
    }
    let song_count = songs.len();

    let mut payload: Vec<(&'static str, Field)> = vec![("show_id", Field::leaf(&show_id))];
    let all_performers = args::str_list(a, "all_performers");
    if !all_performers.is_empty() {
        payload.push(("all_performers", Field::Leaf(json!(all_performers))));
    }
    payload.push(("songs", Field::Arr(songs)));

    let kind = ProposalKind::Setlist;
    let file_name = build_file_name(kind, today_key, &show_id)?;
    let title_text = format!("公演 {show_id} のセットリスト追加");
    let top = doc_fields(&title_text, a, &source, "propose_setlist", payload);
    let source_advisory = source_host_advisory(&source.url);
    Ok(ProposalDraft {
        kind,
        file_name,
        contents: render(top),
        summary: format!("公演 {show_id} のセットリスト {song_count} 曲を追加するドラフト"),
        source_advisory,
    })
}

fn build_idol(a: &Value, today_key: &str) -> Result<ProposalDraft, ToolError> {
    let id = args::str_req(a, "id")?;
    let brand_id = args::str_req(a, "brand_id")?;
    let name = args::str_req(a, "name")?;
    let source = require_source(a)?;

    let mut idol: Vec<(&'static str, Field)> = vec![
        ("id", Field::leaf(&id)),
        ("brand_id", Field::leaf(&brand_id)),
        ("name", Field::leaf(&name)),
    ];
    push_opt(&mut idol, a, "name_kana");
    push_opt(&mut idol, a, "birthday");
    push_opt(&mut idol, a, "blood_type");
    push_opt(&mut idol, a, "height");
    push_opt(&mut idol, a, "birth_place");
    push_opt(&mut idol, a, "constellation");
    push_opt(&mut idol, a, "description");

    let brands = match a.get("brands").and_then(Value::as_array) {
        Some(arr) if !arr.is_empty() => json!(arr),
        // 省略時は主ブランド 1 件だけの所属として補う (idol_brands が空にならないように)。
        _ => json!([{ "brand_id": brand_id, "is_primary": 1 }]),
    };
    idol.push(("brands", Field::Leaf(brands)));

    let kind = ProposalKind::Idol;
    let file_name = build_file_name(kind, today_key, &id)?;
    let title_text = format!("アイドル「{name}」({brand_id}) の追加");
    let top = doc_fields(&title_text, a, &source, "propose_idol", vec![("idols", Field::Arr(vec![Field::Obj(idol)]))]);
    let source_advisory = source_host_advisory(&source.url);
    Ok(ProposalDraft {
        kind,
        file_name,
        contents: render(top),
        summary: format!("アイドル「{name}」({brand_id}) を追加するドラフト"),
        source_advisory,
    })
}

fn build_fix(a: &Value, today_key: &str) -> Result<ProposalDraft, ToolError> {
    let table = args::str_req(a, "table")?;
    let id = args::str_req(a, "id")?;
    let fields_obj = a
        .get("fields")
        .and_then(Value::as_object)
        .filter(|m| !m.is_empty())
        .ok_or_else(|| ToolError::BadArgs("fields は 1 件以上のフィールドが必要です。".to_string()))?;
    // RedTeam L1: table: "songs" に任意の fields を書けるので、歌詞/試聴 URL を
    // ここ経由で混入させる経路をあらかじめ塞ぐ (どの table でも一律に禁止する —
    // songs 以外にこの列名が来ること自体が想定外の入力なので、table で場合分けしない)。
    if let Some(bad) = fields_obj.keys().find(|k| FORBIDDEN_FIX_FIELDS.contains(&k.as_str())) {
        return Err(ToolError::BadArgs(format!(
            "fields に '{bad}' は含められません (歌詞/試聴 URL は propose_fix の対象外です)。"
        )));
    }
    let field_count = fields_obj.len();
    let source = require_source(a)?;

    let fix: Vec<(&'static str, Field)> = vec![
        ("table", Field::leaf(&table)),
        ("id", Field::leaf(&id)),
        ("fields", Field::Leaf(Value::Object(fields_obj.clone()))),
    ];

    let kind = ProposalKind::Fix;
    let file_name = build_file_name(kind, today_key, &format!("{table}_{id}"))?;
    let title_text = format!("{table} の {id} を修正");
    let top = doc_fields(&title_text, a, &source, "propose_fix", vec![("fixes", Field::Arr(vec![Field::Obj(fix)]))]);
    let source_advisory = source_host_advisory(&source.url);
    Ok(ProposalDraft {
        kind,
        file_name,
        contents: render(top),
        summary: format!("{table} の {id} を修正するドラフト ({field_count} フィールド)"),
        source_advisory,
    })
}

// ---- 共通ヘルパ -------------------------------------------------------------

/// 出典 1 件 (URL + 逐語引用)。
struct Source {
    url: String,
    quote: String,
}

/// `source` / `source_quote` を取り出す。無ければドラフトを組まない
/// (このファイル冒頭の注記を参照)。
fn require_source(a: &Value) -> Result<Source, ToolError> {
    let url = args::str_opt(a, "source").ok_or_else(|| {
        ToolError::BadArgs("source (一次ソースの URL) は必須です。出典なしでは登録案を作れません。".to_string())
    })?;
    let quote = args::str_opt(a, "source_quote").ok_or_else(|| {
        ToolError::BadArgs(
            "source_quote (source の該当箇所の逐語引用) は必須です。URL だけでは、その中身が \
             本当に主張する事実を裏付けているか人間が確認できません。"
                .to_string(),
        )
    })?;
    Ok(Source { url, quote })
}

/// 出典の注意書きを組む。**常に何か返す** (RedTeam M4 — このファイルの
/// `ProposalDraft::source_advisory` の doc コメントを参照)。既知ホストかどうかで
/// 「出すか出さないか」を分けない。分けるのは追加の一文だけ。
fn source_host_advisory(source: &str) -> String {
    const BASE: &str = "この source は機械が取得・検証していません。反映前にオーナーが \
        URL を開き、source_quote の引用が実際の中身と一致するか確認してください。";
    match extract_host(source) {
        Some(host) => {
            let known = KNOWN_SOURCE_HOSTS
                .iter()
                .any(|d| host == *d || host.ends_with(&format!(".{d}")));
            if known {
                BASE.to_string()
            } else {
                format!(
                    "{BASE} さらに、source のホスト ({host}) は既知の一次ソース一覧 ({}) に \
                     無いので、特に注意して確認してください。",
                    KNOWN_SOURCE_HOSTS.join(" / ")
                )
            }
        }
        None => format!("{BASE} (source から URL のホストを取り出せませんでした: {source:?})"),
    }
}

/// URL からホスト部分だけを取り出す (小文字化・ポート番号/userinfo を除く)。
/// 専用の URL パーサは使わない (この crate に無く、ここではホスト名の比較にしか
/// 使わないので自前の軽い抽出で足りる)。
fn extract_host(source: &str) -> Option<String> {
    let without_scheme = source.split_once("://").map(|(_, rest)| rest).unwrap_or(source);
    let host_part = without_scheme.split(['/', '?', '#']).next().unwrap_or("");
    let host_part = host_part.rsplit('@').next().unwrap_or(host_part); // userinfo@host 対策
    let host_part = host_part.split(':').next().unwrap_or(host_part); // ポート番号を落とす
    let host = host_part.trim();
    if host.is_empty() {
        None
    } else {
        Some(host.to_lowercase())
    }
}

/// `data/<kind>/<today>_<kind タグ>_<slug>.json` を組み立てる。
///
/// **kind タグをファイル名に埋め込む理由 (RedTeam M8)**: `tools/apply_data.py` の
/// `--only` はファイル名の **basename 一致** でしか絞り込まない (`ONLY_FILE` は
/// `data/` 配下の全種別ディレクトリを横断して見る)。kind タグを挟まずに
/// `<today>_<slug>.json` だけだと、同じ日に別種別 (例: 曲と衣装) で偶然同じ slug の
/// ドラフトができたとき、`--only` が両方を拾ってしまい、無関係な問題が
/// 混ざって返る。kind タグで basename 自体を種別ごとに一意にしておけば、
/// この衝突は構造的に起こらない。
fn build_file_name(kind: ProposalKind, today_key: &str, raw_slug: &str) -> Result<String, ToolError> {
    let slug = slugify(raw_slug);
    if !is_valid_slug(&slug) {
        // 実運用では起こらない想定 (slugify がパス区切りを必ず潰すため) だが、
        // "." のような退化した入力に対する最後の防御として止める。
        return Err(ToolError::BadArgs(format!(
            "id (または table/show_id) から安全なファイル名を作れませんでした: {raw_slug:?}"
        )));
    }
    Ok(format!("{}_{}_{}.json", today_compact(today_key), kind.tag(), slug))
}

/// slug (ファイル名の中身) として安全かどうか。**パストラバーサル対策** (RedTeam M7)。
///
/// `^[a-z0-9_]+$` のように ASCII だけに絞ってはいない。この DB の id は
/// `sc_恋するクオリア` のように日本語をそのまま含むのが正規の形で、ASCII だけに
/// 絞ると、そういう正しい id から一切ドラフトを作れなくなってしまう。安全性は
/// 「使える文字の種類を絞る」のではなく「パス区切りになり得る文字・トラバーサルの
/// 部品になり得る値を確実に落とす」ことで担保する:
/// - `/` `\` を含むもの (別のディレクトリを指せてしまう)
/// - 制御文字を含むもの
/// - `.` / `..` そのもの (単体でパス上の意味を持つ)
/// - 空文字列 / 極端に長い値
fn is_valid_slug(s: &str) -> bool {
    if s.is_empty() || s.len() > 150 {
        return false;
    }
    if s == "." || s == ".." {
        return false;
    }
    !s.chars().any(|c| matches!(c, '/' | '\\') || c.is_control())
}

/// ドラフト共通のトップレベル (`title` / `author` / `source` / `note`) に、
/// 各ツール固有のペイロード (`songs` 配列など) を続ける。
///
/// `note` は「出典: <url> / 引用: "<引用>"」を必ず先頭に含む。LLM が追加で渡した
/// `note` はその後ろに続ける。**per-record には `source`/`note` を一切置かない**
/// (`apply_data.py` の「未知の列」判定は種別ごとに許すキーが違うので、レコードの
/// 中に何か追加すると種別ごとにその一覧を把握する必要が出てくる。トップレベルなら
/// `apply_data.py` は配列の外を一切見ないので常に安全)。
fn doc_fields(
    title_text: &str,
    a: &Value,
    source: &Source,
    tool_name: &str,
    payload: Vec<(&'static str, Field)>,
) -> Vec<(&'static str, Field)> {
    let mut composed_note = format!("出典: {}\n引用: \"{}\"", source.url, source.quote);
    if let Some(extra) = args::str_opt(a, "note") {
        composed_note.push('\n');
        composed_note.push_str(&extra);
    }

    let mut top: Vec<(&'static str, Field)> = vec![
        ("title", Field::leaf(title_text)),
        ("author", Field::leaf(&format!("LLM 提案 ({tool_name})"))),
        ("source", Field::leaf(&source.url)),
        ("note", Field::leaf(&composed_note)),
    ];
    top.extend(payload);
    top
}

/// エラーメッセージの先頭に位置情報を足す (`shows[0]: id は必須です` のように)。
fn with_prefix(prefix: &str, e: ToolError) -> ToolError {
    match e {
        ToolError::BadArgs(s) => ToolError::BadArgs(format!("{prefix}: {s}")),
        other => other,
    }
}

/// `today_key` (`YYYY-MM-DD`) をファイル名用に詰める (`YYYYMMDD`)。
fn today_compact(today_key: &str) -> String {
    today_key.replace('-', "")
}

/// ファイル名に使える形へ整える。パス区切り・制御文字・空白を `_` に潰すだけで、
/// 日本語はそのまま残す (この DB の id は `sc_恋するクオリア` のように生の日本語を
/// 含むのが普通なので、無理にローマ字化しない)。
fn slugify(raw: &str) -> String {
    let mut out = String::new();
    for c in raw.trim().chars() {
        match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => out.push('_'),
            c if c.is_control() || c.is_whitespace() => out.push('_'),
            c => out.push(c),
        }
    }
    let collapsed = out.split('_').filter(|s| !s.is_empty()).collect::<Vec<_>>().join("_");
    if collapsed.is_empty() {
        "draft".to_string()
    } else {
        truncate_utf8(&collapsed, 100)
    }
}

/// UTF-8 境界を壊さずにバイト数で切り詰める。
fn truncate_utf8(s: &str, max_bytes: usize) -> String {
    if s.len() <= max_bytes {
        return s.to_string();
    }
    let mut end = max_bytes;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    s[..end].to_string()
}

/// 値が空でなければ (文字列なら空でなければ) 積む。
fn push_opt(fields: &mut Vec<(&'static str, Field)>, a: &Value, key: &'static str) {
    let Some(v) = a.get(key) else { return };
    if v.is_null() {
        return;
    }
    if let Value::String(s) = v {
        if s.trim().is_empty() {
            return;
        }
    }
    fields.push((key, Field::Leaf(v.clone())));
}

// ---- 順序つき JSON レンダリング ----------------------------------------------

/// フィールド順を保ったまま組み立てるための最小限の表現。
///
/// この crate は `serde_json` の `preserve_order` 機能を有効化していない (Cargo.toml
/// を書き換えると、並行して走っている他エージェントのビルド/ロックと衝突するため触らない)。
/// 素の `serde_json::Value::Object` はキーをアルファベット順にしてしまう
/// (`preserve_order` 無しでは内部が `BTreeMap` になる)。既存の `data/**/_template.json` と
/// 同じ見た目 (id → title → brand_id → ... の論理順、1 スペースインデント) でドラフトを
/// 書き出すために、レコード直下のキー順だけはここで明示的に持ち、末端の値の
/// エスケープ/整形は `serde_json` に委ねる。
enum Field {
    Leaf(Value),
    Obj(Vec<(&'static str, Field)>),
    Arr(Vec<Field>),
}

impl Field {
    fn leaf(s: &str) -> Field {
        Field::Leaf(json!(s))
    }

    fn write(&self, out: &mut String, indent: usize) {
        match self {
            Field::Leaf(v) => write_value(out, v, indent),
            Field::Obj(fields) => write_pairs(out, fields, indent),
            Field::Arr(items) => write_items(out, items, indent),
        }
    }
}

fn pad(out: &mut String, indent: usize) {
    for _ in 0..indent {
        out.push(' ');
    }
}

fn write_pairs(out: &mut String, fields: &[(&'static str, Field)], indent: usize) {
    if fields.is_empty() {
        out.push_str("{}");
        return;
    }
    out.push_str("{\n");
    let n = fields.len();
    for (i, (k, f)) in fields.iter().enumerate() {
        pad(out, indent + 1);
        out.push_str(&serde_json::to_string(k).unwrap_or_default());
        out.push_str(": ");
        f.write(out, indent + 1);
        if i + 1 < n {
            out.push(',');
        }
        out.push('\n');
    }
    pad(out, indent);
    out.push('}');
}

fn write_items(out: &mut String, items: &[Field], indent: usize) {
    if items.is_empty() {
        out.push_str("[]");
        return;
    }
    out.push_str("[\n");
    let n = items.len();
    for (i, item) in items.iter().enumerate() {
        pad(out, indent + 1);
        item.write(out, indent + 1);
        if i + 1 < n {
            out.push(',');
        }
        out.push('\n');
    }
    pad(out, indent);
    out.push(']');
}

/// 素の `serde_json::Value` (LLM からそのまま渡ってきた値) を同じ 1 スペース
/// インデントで書く。ネストしたオブジェクトのキー順はここではアルファベット順になる
/// (`Value::Object` が持つ順序しか無いため) が、これは LLM がそのまま渡してきた
/// 付随データ (`fields` の中身など) に限られる — レコード直下のキー順は
/// `Field::Obj` 側で制御しているので影響しない。
fn write_value(out: &mut String, v: &Value, indent: usize) {
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => out.push_str(&n.to_string()),
        Value::String(s) => out.push_str(&serde_json::to_string(s).unwrap_or_default()),
        Value::Array(items) => {
            if items.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push_str("[\n");
            let n = items.len();
            for (i, item) in items.iter().enumerate() {
                pad(out, indent + 1);
                write_value(out, item, indent + 1);
                if i + 1 < n {
                    out.push(',');
                }
                out.push('\n');
            }
            pad(out, indent);
            out.push(']');
        }
        Value::Object(map) => {
            if map.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push_str("{\n");
            let n = map.len();
            for (i, (k, val)) in map.iter().enumerate() {
                pad(out, indent + 1);
                out.push_str(&serde_json::to_string(k).unwrap_or_default());
                out.push_str(": ");
                write_value(out, val, indent + 1);
                if i + 1 < n {
                    out.push(',');
                }
                out.push('\n');
            }
            pad(out, indent);
            out.push('}');
        }
    }
}

fn render(top: Vec<(&'static str, Field)>) -> String {
    let mut out = String::new();
    write_pairs(&mut out, &top, 0);
    out.push('\n');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(draft: &ProposalDraft) -> Value {
        serde_json::from_str(&draft.contents)
            .unwrap_or_else(|e| panic!("組み上げた JSON が壊れている: {e}\n{}", draft.contents))
    }

    fn with_source(mut a: Value) -> Value {
        a["source"] = json!("https://idolmaster-official.jp/news/123");
        a["source_quote"] = json!("2026年9月19日発売");
        a
    }

    #[test]
    fn source_quote_が無ければ_song_は_bad_args() {
        let a = json!({
            "id": "ml_test_song", "title": "テスト曲", "brand_id": "ml",
            "song_type": "unit", "original_singers": ["ml_idol_a"],
            "source": "https://idolmaster-official.jp/news/123",
        });
        let err = build_proposal("propose_song", &a, "2026-09-19").unwrap_err();
        assert!(matches!(err, ToolError::BadArgs(_)));
        assert!(err.to_string().contains("source_quote"));
    }

    #[test]
    fn original_singers_が空なら_song_は_bad_args() {
        let a = with_source(json!({
            "id": "ml_test_song", "title": "テスト曲", "brand_id": "ml", "song_type": "unit",
        }));
        let err = build_proposal("propose_song", &a, "2026-09-19").unwrap_err();
        assert!(matches!(err, ToolError::BadArgs(_)));
    }

    #[test]
    fn propose_song_は_data_songs_に置く_source_は_トップレベルのみ() {
        let mut a = with_source(json!({
            "id": "ml_new_song", "title": "新曲", "brand_id": "ml", "song_type": "unit",
            "original_singers": ["ml_idol_a", "ml_idol_b"],
        }));
        a["note"] = json!("追加の根拠メモ");
        let draft = build_proposal("propose_song", &a, "2026-09-19").unwrap();
        assert_eq!(draft.kind, ProposalKind::Song);
        assert_eq!(draft.file_name, "20260919_song_ml_new_song.json");
        assert_eq!(draft.display_path(), "data/songs/20260919_song_ml_new_song.json");
        let v = parse(&draft);
        assert_eq!(v["source"], "https://idolmaster-official.jp/news/123");
        assert!(v["note"].as_str().unwrap().contains("出典:"));
        assert!(v["note"].as_str().unwrap().contains("引用:"));
        assert!(v["note"].as_str().unwrap().contains("追加の根拠メモ"));
        assert_eq!(v["songs"][0]["id"], "ml_new_song");
        assert_eq!(v["songs"][0]["original_singers"][1], "ml_idol_b");
        // レコードの中には source/note を持ち込まない (idols 等の未知列判定を気にしないため)。
        assert!(v["songs"][0].get("source").is_none());
        assert!(v["songs"][0].get("note").is_none());
        assert!(draft.contents.ends_with('\n'));
        // 既知ホストでも注意書き自体は常に出る (RedTeam M4)。ただし未知ホスト向けの
        // 追加の一文までは付かない。
        assert!(draft.source_advisory.contains("機械が取得・検証していません"));
        assert!(!draft.source_advisory.contains("既知の一次ソース一覧"));
    }

    #[test]
    fn 未知ホストの_source_には追加の注意書きが付く_ただし拒否はしない() {
        let a = json!({
            "id": "ml_test_song", "title": "テスト曲", "brand_id": "ml", "song_type": "unit",
            "original_singers": ["ml_idol_a"],
            "source": "https://random-fan-blog.example.com/post/1",
            "source_quote": "何か書いてあった",
        });
        let draft = build_proposal("propose_song", &a, "2026-09-19").unwrap();
        assert!(draft.source_advisory.contains("random-fan-blog.example.com"));
        assert!(draft.source_advisory.contains("既知の一次ソース一覧"));
    }

    #[test]
    fn source_advisory_はホストを取り出せなくても何か返す() {
        // 極端な入力 (スキームだけでホスト部が空) でも空文字列を返して黙り込んだりしない。
        let advisory = source_host_advisory("https://");
        assert!(!advisory.is_empty());
        assert!(advisory.contains("機械が取得・検証していません"));
    }

    #[test]
    fn propose_fix_は_lyrics_url_や_preview_url_を弾く() {
        for key in ["lyrics_url", "preview_url"] {
            let a = with_source(json!({
                "table": "songs", "id": "ml_song",
                "fields": { key: "https://example.com/lyrics" },
            }));
            let err = build_proposal("propose_fix", &a, "2026-09-19").unwrap_err();
            assert!(matches!(err, ToolError::BadArgs(_)), "{key} を弾いていない");
        }
        // 無害な列は引き続き通る。
        let ok = with_source(json!({
            "table": "songs", "id": "ml_song", "fields": { "release_date": "2024-01-01" },
        }));
        assert!(build_proposal("propose_fix", &ok, "2026-09-19").is_ok());
    }

    #[test]
    fn propose_event_は_複数_shows_を数える() {
        let a = with_source(json!({
            "id": "ev_test", "brand_id": "ml", "name": "テストライブ", "kind": "live",
            "shows": [
                {"id": "sh_test_1", "name": "DAY1", "date": "2026-10-01"},
                {"id": "sh_test_2", "name": "DAY2", "date": "2026-10-02", "venue": "会場"},
            ],
        }));
        let draft = build_proposal("propose_event", &a, "2026-09-19").unwrap();
        assert_eq!(draft.kind, ProposalKind::Event);
        assert_eq!(draft.file_name, "20260919_event_ev_test.json");
        let v = parse(&draft);
        assert_eq!(v["events"][0]["shows"].as_array().unwrap().len(), 2);
        assert_eq!(v["events"][0]["shows"][1]["venue"], "会場");
        assert!(draft.summary.contains("2 件"));
    }

    #[test]
    fn 曲と同じ日付_同じslugのイベントでもファイル名は衝突しない() {
        // M8: kind タグがファイル名に入っているので、--only の basename 一致で
        // 別種別のファイルを巻き込まない。
        let song = build_proposal(
            "propose_song",
            &with_source(json!({
                "id": "shared_slug", "title": "曲", "brand_id": "ml", "song_type": "unit",
                "original_singers": ["ml_idol_a"],
            })),
            "2026-09-19",
        )
        .unwrap();
        let idol = build_proposal(
            "propose_idol",
            &with_source(json!({ "id": "shared_slug", "brand_id": "ml", "name": "名前" })),
            "2026-09-19",
        )
        .unwrap();
        assert_ne!(song.file_name, idol.file_name);
    }

    #[test]
    fn propose_setlist_は_performers_の形を確かめる() {
        let base = with_source(json!({
            "show_id": "sh_test_1",
            "songs": [{"position": 1, "song_id": "ml_song", "performers": "みんな"}],
        }));
        let err = build_proposal("propose_setlist", &base, "2026-09-19").unwrap_err();
        assert!(matches!(err, ToolError::BadArgs(_)));

        let ok = with_source(json!({
            "show_id": "sh_test_1",
            "songs": [{"position": 1, "song_id": "ml_song", "performers": "all"}],
        }));
        let draft = build_proposal("propose_setlist", &ok, "2026-09-19").unwrap();
        let v = parse(&draft);
        assert_eq!(v["songs"][0]["performers"], "all");
    }

    #[test]
    fn propose_setlist_は_曲を特定できないと_bad_args() {
        let a = with_source(json!({
            "show_id": "sh_test_1",
            "songs": [{"position": 1, "performers": "all"}],
        }));
        let err = build_proposal("propose_setlist", &a, "2026-09-19").unwrap_err();
        assert!(matches!(err, ToolError::BadArgs(_)));
    }

    #[test]
    fn propose_idol_は_brands_省略時に主ブランドを補う() {
        let a = with_source(json!({ "id": "ml_new_idol", "brand_id": "ml", "name": "テスト花子" }));
        let draft = build_proposal("propose_idol", &a, "2026-09-19").unwrap();
        let v = parse(&draft);
        assert_eq!(v["idols"][0]["brands"][0]["brand_id"], "ml");
        assert_eq!(v["idols"][0]["brands"][0]["is_primary"], 1);
    }

    #[test]
    fn propose_fix_の_file_name_は_table_と_id_を含む() {
        let a = with_source(json!({
            "table": "songs", "id": "ml_song", "fields": {"release_date": "2024-01-01"},
        }));
        let draft = build_proposal("propose_fix", &a, "2026-09-19").unwrap();
        assert_eq!(draft.kind, ProposalKind::Fix);
        assert_eq!(draft.file_name, "20260919_fix_songs_ml_song.json");
        let v = parse(&draft);
        assert_eq!(v["fixes"][0]["fields"]["release_date"], "2024-01-01");
    }

    #[test]
    fn check_proposals_は_build_proposal_には来ない() {
        let err = build_proposal("check_proposals", &json!({}), "2026-09-19").unwrap_err();
        assert_eq!(err, ToolError::UnknownTool("check_proposals".to_string()));
    }

    #[test]
    fn slugify_は_パス区切りと空白を潰し日本語は残す() {
        assert_eq!(slugify("sc_恋するクオリア"), "sc_恋するクオリア");
        assert_eq!(slugify("a/b c\\d"), "a_b_c_d");
        assert_eq!(slugify("  "), "draft");
    }

    #[test]
    fn is_valid_slug_はトラバーサルになり得る値を拒否する() {
        assert!(!is_valid_slug(""));
        assert!(!is_valid_slug("."));
        assert!(!is_valid_slug(".."));
        assert!(!is_valid_slug("a/b"));
        assert!(!is_valid_slug("a\\b"));
        assert!(!is_valid_slug("a\0b"));
        assert!(is_valid_slug("ml_normal_song"));
        assert!(is_valid_slug("sc_恋するクオリア"));
    }

    #[test]
    fn build_file_name_はslugifyを経由するのでパス区切りを含む_id_でも安全() {
        // slugify が / \ を _ に潰すので、build_file_name が BadArgs で止まることはない
        // (単一のファイル名コンポーネントに収まる)。念のため往復させて確認する。
        let name = build_file_name(ProposalKind::Song, "2026-09-19", "../../etc/passwd").unwrap();
        assert!(!name.contains('/'));
        assert!(!name.contains('\\'));
        assert_eq!(name, "20260919_song_.._.._etc_passwd.json");
    }

    #[test]
    fn extract_host_はスキームとポートを剥がす() {
        assert_eq!(
            extract_host("https://cmsapi-frontend.idolmaster-official.jp:443/api/x"),
            Some("cmsapi-frontend.idolmaster-official.jp".to_string())
        );
        assert_eq!(extract_host("not a url"), Some("not a url".to_string()).map(|s| s.to_lowercase()));
    }
}
