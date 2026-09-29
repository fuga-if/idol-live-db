# ImasLiveDB を LLM から引く口 (`imas-mcp`) アーキテクチャ方針

> iOS は [`ARCHITECTURE.md`](ARCHITECTURE.md)、Android は [`ARCHITECTURE-android.md`](ARCHITECTURE-android.md)、
> Web 出面は [`ARCHITECTURE-web.md`](ARCHITECTURE-web.md)、バックエンド Worker は [`ARCHITECTURE-worker.md`](ARCHITECTURE-worker.md)。
> データ所在・投入の全体像は [`DATA_PIPELINE.md`](DATA_PIPELINE.md)。
> 規則を写経しない考え方は [`SHARED_CORE_STUDY.md`](SHARED_CORE_STUDY.md)。

> 状態: **実装済み** (2026-09-19 着手 / 2026-09-21 実測を §9 に記録)。Phase 2 (リモート公開) は未着手。

---

## 1. これは何か / 何をしないか

`imas-mcp` は、**LLM がアイドルマスターのライブ・楽曲データを自然言語で尋ねられるようにする口**。
中身は 2 つの顔を持つ 1 つのバイナリ:

- **MCP サーバ** — `--stdio` で JSON-RPC 2.0 を話す。Claude 等の MCP クライアントから繋ぐ。
- **CLI** — 同じツールを `imas-mcp <tool> --json '{...}'` で人の手からも叩ける。

データは**アプリと同じ `master.sqlite`** をそのまま読む。別の写しを持たない。

やらないこと:

- **歌詞本文を返さない。** JASRAC の許諾は「D1 に置き、一括ダウンロードさせない配信形式」に対して
  下りている (`JASRAC.md`)。ここから本文を出すとその前提を外れる。扱うのは作品コードと掲載有無まで。
- **`songs.lyrics_url` と `songs.preview_url` を返さない。** 本文だけの話ではない。`lyrics_url` は
  3,062 曲中 2,149 曲に歌詞サイトの URL が入っていて、返せば取り込み元サイト名を公開物に
  書いたことになる。`preview_url` はアプリの中でだけ鳴らすもの。Web 出面は同じ危険を認識して
  DTO 変換で明示的に落とし、テスト T12 (`imas-core/tests/web_export.rs`) で機械的に固定している。
  **MCP 側にも同等のテストを置く** (§4 の末尾)。`jasrac_code` と `apple_music_id` は返してよい。
- **本番データへ直接書かない。** 新規登録は `data/` に JSON ドラフトを置いて `--check` を通すところまで (§5)。
- **LLM を呼ばない。** これは LLM に**呼ばれる**側。アプリにチャット機能を作る計画ではない
  (推論コストが発生し「ランニングコスト 0」の制約に反する)。

## 2. 絶対制約

1. **ランニングコスト 0**。ローカル版はユーザーの手元で動くので当然 0。リモート公開版 (§8) も
   従量課金の経路を作らない。
2. **判断の唯一の正は imas-core (Rust)**。「どの語が当たるか」「どう並べるか」のように他の面と
   共有する規則は `domain` (`entity_resolution` / `text_search_index` / `setlist_shape` …) が持ち、
   ツールのカタログと「何を返すか」「何件で切るか」はツール面 (`agent::tools` / `agent::proposal`) が
   持つ。入出力 (`agent::mcp` / `stdio` / `cli` / `proposal_io`) は入力をほどいてツール面を呼び、
   返った JSON を書き出すだけ。**これを崩すと、アプリ・Web・LLM で「同じ質問に違う答え」が出る。**
3. **照合規則はコア一本**。検索の畳み込みは `imas-text-fold` / `domain::text_search_index` /
   `fuzzy_search` が唯一の実体。ツール面で `contains` や `to_lowercase` を書かない。
4. **FFI 面は不変**。新しい `#[uniffi::export]` を足さない (`tests/ffi_surface.rs` が固定している)。
   アダプタと bin は既定 off の `feature = "agent"` で、iOS/Android のビルドには一切入らない。
5. **出典なしの登録を構造で禁じる**。書き込みツールは `source` (一次ソースの URL) を必須引数にする。

## 3. 依存方向

```
   MCP クライアント (Claude 等)        人の手 (デバッグ)
            │ JSON-RPC 2.0 / stdio            │ argv
            ▼                                 ▼
   ┌──────────────────────────────────────────────────┐
   │ imas-core/src/agent/   (driving adapter)          │  feature = "agent" (既定 off)
   │   mcp.rs   … initialize / tools/list / tools/call │
   │   stdio.rs … 行区切り JSON-RPC の入出力            │
   │   cli.rs   … argv → 同じツール                     │
   │   proposal_io.rs … ドラフトを書く / --check を起動 │
   │       │ 呼ぶだけ (判断を書かない)                   │
   │   ツール面 (カタログと応答の組み立て・テスト付)     │
   │   tools/lookup.rs  … resolve / search / get_* / vocabulary
   │   tools/browse.rs  … list_* / idol_songs / song_performances / setlist_diff / stats
   │   tools/predict.rs … list_shows / setlist_shape / song_position_profile / co_performed_songs
   │   tools/scope.rs   … 公演を絞る引数のほどき方 (公演を扱う全ツール共通)
   │   tools/vocab.rs   … 取りうる値と、語彙外を候補つきで突き返す作法
   │   proposal.rs      … 投入ドラフトの組み立て
   └───────────────┬──────────────────────────────────┘
                   │ 共有の規則を呼ぶ
   ┌───────────────▼──────────────────────────────────┐
   │ imas-core/src/domain/   (唯一の正・純粋・テスト付) │  feature に関係なく常時コンパイル
   │   entity_resolution.rs   … 人の言葉 → エンティティ候補
   │   (以下は既存) search_queries / idol_queries / song_detail_queries / …
   └───────────────┬──────────────────────────────────┘
                   │ Snapshot
   ┌───────────────▼──────────────────────────────────┐
   │ outbound::sqlite_loader → ImasLiveDB/Resources/master.sqlite (READ ONLY)
   └──────────────────────────────────────────────────┘
```

ツール面も入出力と同じ feature = "agent" に入れてある。JSON の組み立て (応答の形・JSON Schema) は
LLM 向けの面の事情で、アプリ (iOS/Android) にも Web にも要らないため。テストは
`cargo test --features agent` で走る (core-guard が既定の `cargo test` と並べて流す)。

**読む DB はアプリと同じ `ImasLiveDB/Resources/master.sqlite`** で、Web 出面が読む
`db/master.sql` 由来の写しとは**別物**。両者は双方向に乖離することが既知なので、
「判断コードが同じだから答えも同じ」とは言えない (入力が違う)。この DB は gitignore の
生成物で clone 直後は存在しないため、**無ければ stderr に `bash tools/build_db.sh` を
案内して exit 2** にする (黙って落ちない)。

## 4. 返す形の方針 (UI 向けの射影と違う)

アプリ向けの FFI は「添字列を返して呼び手が自国の store で実体化する」形だが、**ここでは使わない**。
読み手は LLM なので、規約はこうする:

- **1 回の呼び出しで、追加の往復なしに文章が書ける形**まで名前を解決して返す。
- 各レコードに必ず `id` を添える (次の呼び出しの手がかり)。
- `null` のフィールドは省く (トークンを食うだけ)。
- 打ち切ったら `truncated: true` と `total: N`。**総数は必ず返す** (「何件ありますか」に答えるため)。
- 語彙外の値は黙って 0 件にせず、取りうる値を並べた `BadArgs` を返す。
  **LLM が空振りに気づけない形にしない。**
- 名前で引いて 2 件以上当たったら勝手に 1 件に決めず、候補を返して選ばせる。
- 応答のバイト数にも上限を持つ。`limit` を絞っても 1 レコードが厚ければ 1 回の応答で
  LLM の文脈を焼く。超えたら件数を減らし、`truncated_reason: "size"` を立てる。

**禁止フィールドのテスト (T12 相当)**: `domain::agent_tools` に、全ツールを代表引数で 1 巡し、
返った JSON の文字列に `lyrics_url` / `preview_url` / 歌詞サイトのホスト名が 1 度も現れないことを
確かめるテストを置く。同時に「`tool_catalog()` の全ツール名がその代表引数の表に載っている」ことも
確かめ、**ツールを足したらテストが落ちる**ようにする。`serde_json::to_value(song)` と 1 行書けば
漏れる形なので、人の注意ではなく機械で止める。

## 4.5 「予想」は返さない (返すのは過去の事実だけ)

「伊吹翼の主演公演が決まったらどんなセトリになる?」のような問いに、**DB が予想を答えては
いけない**。スコアリングや重みづけを Rust に書くと、外れたときに直す先が無く、根拠の無い
数字が「データベースの答え」として流通する。ここが出すのは *過去がどうだったか* だけで、
予想は呼び手 (LLM) が組み立てる。そのための材料が `agent_tools/predict.rs` の 4 本:

| ツール | 返す事実 |
|---|---|
| `list_shows` | 公演 (1 日ぶん) の一覧。`idol_id` × `cast_role=lead` で「その人が主演だった公演」 |
| `setlist_shape` | 公演群のセトリの型 (曲数・区切り・1 曲目 / アンコール / 締めの常連・ソロ枠の本数) |
| `song_position_profile` | ある曲が公演の「どこで」歌われるか (1 曲目 / 締め / アンコール / 序中終盤) |
| `co_performed_songs` | 同じ公演で一緒に歌われやすい曲 (`performance_stats::co_occurring_songs`) |

型の計算そのものは `domain/setlist_shape.rs` (純粋関数 + `#[test]`)。ツール面は呼んで
JSON にするだけ。`setlist_shape` の応答には**標本にした公演数と公演 id** が必ず付く —
6 公演から出た中央値を全公演の傾向と取り違えさせないため。

公演の絞り込みの正本は **`domain/show_list_filtering.rs`** (`filter_show_indexes`)。曲・イベント・
アイドルにはそれぞれ絞り込みの正本があるのに公演だけ無く、判断がツール面に直書きされていたので
足した。引数をほどいて条件型に詰めるのは `agent_tools/scope.rs` の 1 本で、`list_shows` /
`setlist_shape` / `stats --kind show_song_count_ranking` が**同じ軸の集合**を通る。
「翼が lead の公演の型」が「翼が lead の公演の一覧」と違う集合から出たら、材料として成立しない。

取りうる値 (`brand` / `event_kind` / `cast_role` …) は `agent_tools/vocab.rs` が実データから作る。
語彙外は候補つきの `BadArgs` で突き返す (§4)。

## 5. 新規データ登録 (どこで止めるか)

`DATA_PIPELINE.md` のとおり **CloudKit が source of truth** で、反映にはオーナーの手元にしかない
鍵が要る。LLM の誤りがそのまま全ユーザーへ配信される経路を作らないため、ここからできるのは:

```
LLM → propose_* ツール → data/<種類>/*.json を書く → tools/apply_data.py --check を走らせる
                                                      → 検証結果をそのまま LLM に返す
                     （ここまで。反映はオーナーが --apply --push）
```

- `source` (一次ソースの URL) が無ければドラフトを組まない。
- **`apply_data.py` の検証規則を Rust に写経しない。**写経すると二重管理になり、必ず片方だけ
  書き換わる。ドラフト側が持つのは「JSON の組み立て方」と「出典の必須」まで。値の妥当性は
  `--check` に任せる。
- 結果には必ず「これは提案であって、反映にはオーナーの操作が要る」旨を入れる。
  LLM が「登録できたつもり」になるのを防ぐ。

## 6. なぜ CLI と MCP を 1 つにするか

MCP サーバは stdout に JSON-RPC 以外を 1 バイトも書けないので、中で何が起きているか見えにくい。
同じ dispatch を argv からも叩ける口があれば、`imas-mcp get_song --id ml_xxx` で
**ツールの答えそのものを目で確かめられる**。テストも CLI 経由で書ける。分けて作る理由が無い。

## 7. 使い方

```bash
cd imas-core
cargo build --release --features agent --bin imas-mcp

# MCP クライアントから (例: Claude Code の設定)
#   command: <repo>/imas-core/target/release/imas-mcp
#   args: ["--stdio", "--repo-root", "<repo>"]

# 人の手から
./target/release/imas-mcp tools
./target/release/imas-mcp search --query 春日未来
```

`--read-only` を付けると書き込み (ドラフト作成) ツールを出さない。

## 8. リモート公開 (Phase 2・未着手 / 着手前に決めることがある)

手元に clone した人しか使えないのは惜しいので、誰でも繋げる MCP エンドポイントも出したい。
**判断は同じ `agent::tools` を通す** (feature = "agent" を付けて wasm で呼ぶ) ので、判断そのものがズレることはない
(ただし読む DB が違えば答えは違いうる。§3 の注記)。

**着手前に決めること (これが未決のうちは Phase 2 を始めない)**:

1. **どの Worker に載せるか。** `web/` は assets-only Worker (`main` を持たない) で、
   「静的アセット配信は無料・リクエスト無制限・Worker 呼び出し 0 回」が成立の前提。
   MCP は JSON-RPC を喋る以上 `main` が要り、足した瞬間にこの前提が壊れて全リクエストが
   Worker invocation (無料枠 10 万/日) を食う。**別 Worker を立てる**こと。既存の
   `imas-live-api/` への相乗りも不可 (不可触と定めてある)。
2. **流量制限と認証。** 無認証の MCP は 1 クライアントの暴走で無料枠を焼き切れる。
   D1 の無料枠を焼いた前例があるので、「超えたら止まるのか課金されるのか」まで決めること。
3. **データ源。** 下表。

| 案 | データ源 | 難点 |
|---|---|---|
| A: 生テーブル一括 | `web/data/snapshot/tables.json` (9.4MB) | Worker の CPU 時間内にパースしきれない |
| B: 分割済み JSON | `web/data/search/*.json` (732KB) + 個別 `songs/<slug>.json` 等 | **個別 JSON は dist に出ていない** (`search/*.json` が「dist に出る唯一の `data/` サブセット」で、全量を `public/` に置くのは禁止事項)。索引だけでは §4 の「1 回で文章が書ける形」を原理的に満たせない (索引は id と綴りしか持たない) |
| C: D1 | D1 に master を置き直す | 読み取り行数が課金対象。過去に無料枠を焼いた経緯がある |

**案 B を採るなら、先に「`web-export` が MCP 用の配信 JSON も `dist/` に出す」と決める**こと
(ページ数 7,631 に対し Workers Static Assets の上限は 20,000 ファイルなので枠は足りる)。
それをやらないなら B は「検索はできるが答えが書けない」ので却下。

## 9. 実装の記録

### 9.1 規模 (2026-09-21 実測)

| | |
|---|---|
| ツール | **24 本** — 読み 18 / 書き (ドラフト) 6 |
| Snapshot ロード | **91〜170 ms** (曲 3,068 / アイドル 394 / イベント 747)。プロセス起動ごとに 1 度 |
| テスト | `agent_tools` 86 / `setlist_shape` 14 / `entity_resolution` + `proposal` 37。`cargo test --lib` 全体で 1,349 |

読み: `resolve` `search` `get_idol` `get_song` `get_event` `get_show` `vocabulary`
`list_idols` `list_songs` `list_events` `idol_songs` `song_performances` `setlist_diff`
`stats` `list_shows` `setlist_shape` `song_position_profile` `co_performed_songs`
書き: `propose_song` `propose_event` `propose_setlist` `propose_idol` `propose_fix` `check_proposals`

### 9.2 実例: 「翼の主演公演が決まったらどんなセトリになるか」

この問いに答えられるかがツール面の設計目標だった (§4.5 のとおり**予想そのものは返さない**。
返すのは過去の事実で、組み立てるのは呼び手)。実際の 2 手:

```
list_shows --idol_id ml_伊吹翼 --cast_role lead
→ {"no_hits": {"relax_one": [{"drop":"idol_id","total":8},
                             {"drop":"cast_role","total":96}]},
   "shows": [], "total": 0}
```

0 件だが、**主演公演は 8 本ある / 翼は 96 公演に出ている、その積が 0** と 1 回で分かる。
空配列だけを返していた頃は「翼に主演公演が無い」のか「主演というデータが無い」のかを
呼び手が区別できず、ここで会話が 1 往復むだになっていた (`scope::narrowing_hint`)。

```
setlist_shape --cast_role lead
→ song_count           23 / 23 / 39      (min / median / max、標本 8 公演)
  solo_slots            1 /  2 /  7
  lead_solo_slots       1 /  2 /  7      ← ソロ枠は全部主演のもの
  lead_songs           10 / 17 / 22      (標本 10 = 1 公演に主演 1〜2 人)
  lead_share_percent   43 / 51 / 74
  member_songs          6 /  8 / 10      (標本 103)
  member_share_percent 17 / 35 / 43
```

**割合を必ず対で返す**のは、主演公演の規模が全 23 曲 (11th〜13th) と全 35〜39 曲 (14th) で
割れているため。曲数だけを 1 つの Spread に混ぜると、23 曲中 14 曲 (61 %) と
39 曲中 17 曲 (44 %) が「14 < 17」と読めて min / max が嘘になる。

### 9.3 数え方で足をすくわれた所

- **「ソロ枠」を原唱者で数えていた。** 14thLIVE DAY2 は原唱者が 1 人の曲が 15 本あるが、
  実際にその日 1 人で立ったのは 7 本。差の 8 曲は `To...` を 3 人、`Be My Boy` を 2 人…と
  **ソロ曲を複数人で歌った**回。ライブの枠の話をしているときは歌唱者で数える
  (曲の性質は `song_list_queries::is_solo_song` が正本で、そちらは変えていない)。
- **主演の記録が 8 公演しか無いのは欠けではない。** 主演を立てる形式のライブが
  12th / 11th / 13th / 14th の 4 本だけで、9th や 10thLIVE TOUR Act-1〜4 はその形式ではない。
  なお 11th が 12th より後の日付なのは**延期公演**だから (振替で 2026-03 開催)。
  ナンバリングで時系列を推測しないこと。
- **`setlist_items.position` は公演をまたぐ通し番号。** 曲順は `setlist_sections` の
  `numbered_setlist` / `track_number` が正本。生の値を出すと「12852 曲目」になる。

### 9.4 運用上の罠

**バイナリを作り直しても、動いている MCP クライアントには反映されない。** `.mcp.json` の
サーバはクライアント起動時に 1 度立ち上がったプロセスに繋がったままなので、ツールを
足しても `tools/list` に出てこない (2026-09-21 に、サーバ側 24 本に対しクライアント側
20 本という状態が実際に起きた)。`imas-mcp tools` で出るのにクライアントから見えない、
という食い違いが起きたらこれを疑い、クライアント側で再接続する。
