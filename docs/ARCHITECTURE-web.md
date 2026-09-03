# ImasLiveDB Web 出面 (`web/`) アーキテクチャ方針

> iOS は [`ARCHITECTURE.md`](ARCHITECTURE.md)、Android は [`ARCHITECTURE-android.md`](ARCHITECTURE-android.md)、
> バックエンド Worker (`imas-live-api/`) は [`ARCHITECTURE-worker.md`](ARCHITECTURE-worker.md)。
> データ所在・同期の全体像は [`ARCHITECTURE.md` のデータ節](ARCHITECTURE.md#データの所在同期マイグレーション-ios--android-共通の思想) と
> [`DATA_PIPELINE.md`](DATA_PIPELINE.md)。表示ルールの写経禁止・単一の真実の源の考え方は [`SHARED_CORE_STUDY.md`](SHARED_CORE_STUDY.md)。

> 状態: **設計確定・実装中**。本書は `web/BRIEF.md`（リーダー方針）と Planner の詳細設計を、実装後の恒久ドキュメントとして固定したもの。数値 (ページ数・サイズ) のうち「見積り」と明記したものは実データでのビルド前の試算であり、§10 の実測値で随時更新する。

---

## 1. これは何か / 何をしないか

`web/` は ImasLiveDB (iOS/Android アプリ) の **Web 上の出面**。マスタ DB (ライブ・公演・セトリ・楽曲・アイドル・ユニット・会場・ブランド) を誰でもブラウザで閲覧・検索・共有できる、SEO と OGP 共有を主目的にした**静的サイト**。アプリと同じ無限色テーマエンジンを持つが、実装・技術スタックはアプリと独立している (Astro + TypeScript、Cloudflare Workers Static Assets)。

**Web は閲覧専用**。以下は一切 Web に作らない (すべてアプリ側に寄せる):

- 状態を持つ・書き込む機能全般 — 担当/お気に入り、回収記録、投票、タグ付け、ペンライト、出演者予想、コール、編集、ログイン。
- 歌詞の掲載 (§2 で詳述)。
- ブラウザ側 JS を使うインタラクション。唯一の例外は `/search/` のページ内検索 (フィルタ目的のナビゲーション補助)。テーマ切替 UI も作らず `prefers-color-scheme` 追従のみ。
- 一覧のクライアントサイドフィルタ (ブランド切替等)。フィルタ結果は必ず別 URL の静的ページにする。

各詳細ページには「アプリで開く」導線 (App Store リンク + `imaslivedb://` カスタムスキーム) を置き、参加記録・投票・歌詞・コールはアプリへ誘導する。

---

## 2. 絶対制約

1. **ランニングコスト 0**。従量課金・有料 SaaS・常駐サーバは禁止。→ 静的サイトを Cloudflare **Workers Static Assets** (assets-only Worker。`main` を持たない) にデプロイする。静的アセット配信は無料・リクエスト無制限・Worker 呼び出し 0 回。Pages は保守モードのため使わない。
2. **表示ルールの唯一の正は imas-core (Rust)**。TypeScript に SQL や業務ルール (何を出す/隠す・並び・年グルーピング・クレジット分割・披露回数・色導出・検索の畳み込み) を一切書かない。imas-core に Web 専用の export バイナリ (`web-export`) を足し、既存の `domain::*` を呼んで JSON を吐く。Astro は JSON を HTML に置くだけ。
3. **検索の照合規則もコア一本**。畳み込み (fold) 規則は `imas-text-fold` crate (imas-core から抽出した依存ゼロの独立 crate) が唯一の実体。ブラウザ側は wasm でその crate を直接呼ぶ (§8)。
4. **版権物ゼロ**。キャラ画像・公式ロゴ・歌詞は掲載しない。ジャケ画像は `songs.artwork_url` (Apple Music CDN) のみ。アイドルはモノグラム表示 (アプリと同じ)。
5. **歌詞は Web v1 の対象外**。JASRAC の許諾条件が「一括ダウンロードできない配信形式・ストリーム形式・認証必須・1曲/リクエスト」であり (`docs/JASRAC.md`)、静的サイトの配信モデルとは相容れない。歌詞本文・プレビュー音源 URL は **出力 JSON に一切含めない** (imas-core 側テスト `T12` で機械的に固定)。曲詳細ページには次の固定文を出す:

   > 歌詞はアプリ『アイドルライブDB』でご覧いただけます（アプリは JASRAC 許諾番号 J260943703 のもとで歌詞を配信しています）。本サイトでは歌詞を掲載していません。

   主語は「アプリ」。歌詞配信の許諾はアプリのストリーム形式に対して取得したものであり、Web には及ばない。
6. コミュニティ集計機能 (タグ/投票/ペンライト) も v1 対象外。Worker (`imas-live-api/`) の無料枠 (10万 req/日) のホットパスに Web を乗せない。
7. **既存 Worker `imas-live-api/` には一切触れない**。共有リンクの Worker 着地ページ (`/app/{events,shows,polls}/<id>`) を Web へ向けるのは後続タスク (§12 O1)。

---

## 3. 依存方向と不変条件

```
          ┌──────────────────────────── 唯一の正 (business rules) ────────────────────────────┐
          │                        imas-core (Rust) / imas-text-fold (Rust)                   │
          │   domain/*  … 何を出す・隠す / 並び / 年グループ / クレジット分割 / 披露回数 /      │
          │                色導出 / 検索の畳み込み / JST の今日                                │
          └───────────────▲───────────────────────────┬───────────────────────────────────────┘
                          │ 呼ぶだけ                   │ 呼ぶだけ
   ┌──────────────────────┴────────┐        ┌──────────┴──────────────┐        ┌───────────────┐
   │ inbound/ (#[uniffi::export])  │        │ bin: web-export         │        │ imas-fold-wasm│
   │  → iOS / Android              │        │  (driving adapter)      │        │ (wasm-bindgen)│
   └───────────────────────────────┘        └──────────┬──────────────┘        └───────┬───────┘
                                                        │ 書く                          │ 出す
                                                        ▼                               ▼
                                            web/data/**.json (ページ形)          web/src/lib/fold/*.wasm
                                                        │                               │
                                                        ▼                               ▼
                                            ┌───────────────────────────────────────────────┐
                                            │ Astro (TypeScript, 描画のみ)                   │
                                            │  ・JSON を読んで HTML にする以外の判断をしない  │
                                            │  ・ブラウザ JS は /search/ の island だけ       │
                                            └───────────────────┬───────────────────────────┘
                                                                ▼ dist/ (静的ファイル)
                                            ┌───────────────────────────────────────────────┐
                                            │ Cloudflare Workers Static Assets (assets-only) │
                                            └───────────────────────────────────────────────┘
```

**不変条件 (レビューの判定基準):**

- **INV-1** `web/src/**/*.ts|astro` に「どのレコードを出すか / どう並べるか / どう畳むか / どんな色にするか」を決める式が 1 つも無い。TS がやってよいのは *JSON のフィールドを HTML の要素に置く* ことだけ。
- **INV-2** `web-export` bin にもビジネスルールを書かない。bin がやってよいのは (a) domain 関数を呼ぶ / (b) 返り値を serde 構造体に詰め替える / (c) 文字列整形 (hex 化・URL セグメント化) の 3 つだけ。判断が要るものは domain に `pub fn` を足してから呼ぶ。
- **INV-3** 新しい `#[uniffi::export]` を追加しない (`imas-core/tests/ffi_surface.rs` の一覧は不変)。
- **INV-4** `imas-core/Cargo.toml` の rusqlite の `target cfg` 2 ブロック (Apple = system / それ以外 = bundled) は 1 文字も触らない。
- **INV-5** `imas-live-api/`, `ImasLiveDB/`, `ImasLiveDB-Android/` のファイルを変更しない (`imas-text-fold/**` を CI の `paths` に加える 3 ワークフローの 1 行だけが例外)。

---

## 4. データフロー

```
db/master.sql  (git の正・日次 bot 更新)
   │  ① sqlite3 restore (web-export bin が rusqlite で自前に行う)
   ▼
web/.cache/master-web.sqlite  (gitignore)
   │  ② load_snapshot()
   ▼
Snapshot (in-memory)
   │  ③ domain::* を呼び、ページ 1 枚 = JSON 1 個 に落とす
   ▼
web/data/**.json  (gitignore)  +  web/data/search/*.json
   │  ④ astro build (fs で読む。public/ には置かない = dist に出ない)
   ▼
web/dist/  (HTML + CSS/font/wasm/search JSON/sitemap)
   │  ⑤ wrangler deploy (assets-only)
   ▼
https://imas-live-web.tokata3011.workers.dev/
```

「今日」(JST) は **③ の時点で 1 回だけ**確定する (`jst_day::jst_today`)。Astro とブラウザは今日を知らず、`new Date()` を使わない。

### `web/data/` の内訳

| パス | 内容 |
|---|---|
| `meta.json` | サイト全体のメタ (schemaVersion / todayJst / dataVersion / counts / アプリリンク) |
| `themes.json` | テーマトークン表 (`idol:<id>` / `brand:<id>` / `neutral` → light/dark) |
| `routes.json` | 全ルート一覧 (`getStaticPaths` / sitemap / 到達性テストの入力) |
| `index/**.json` | 一覧ページ (トップ・ライブ一覧・楽曲一覧・アイドル一覧・ユニット・会場・ブランド・About) |
| `events/`, `shows/`, `songs/`, `idols/`, `units/`, `venues/`, `brands/` | 詳細ページ (1 レコード = 1 JSON) |
| `search/*.json` | 検索索引シャード (曲/アイドル/ライブ/会場)。`dist` に出る唯一の `data/` サブセット |
| `parity/fold.json` | 検索畳み込みのパリティフィクスチャ (Rust ↔ wasm/TS の一致を検証) |

`web/data-fixture/` はこれと同じ形の**手書き最小データ**で commit 対象。web-coder は `IMAS_WEB_DATA=./data-fixture` で実データ (cargo) を待たずに開発できる。

---

## 5. JSON スキーマの所在

- **正**: `imas-core/src/web_export/dto/**` の serde 構造体 (`imas-core/src/bin/web-export/main.rs` はごく薄い CLI 解析のみ)。
- **生成物**: `web/src/lib/schema/**` — `ts-rs` が `cargo test --features web-export` の実行時に生成する TypeScript 型。**commit 対象**であり、web-coder はこれを import するだけで自分では編集しない。
- **ドリフト検知**: CI (`web-deploy.yml`) が `cargo test --locked --features web-export` の後に `git add -A -- web/src/lib/schema && git diff --cached --exit-code -- web/src/lib/schema` を実行し、コミット済みの生成物と実際の生成結果がずれていれば落とす (`git diff --exit-code` 単体だと追跡済みファイルの変更しか見えず、新しい DTO が増えて *未追跡* の `.ts` が生えたケースを素通ししてしまうため、一旦 `add` してからステージ済み差分を見る)。
- **schemaVersion**: 現在 `1`。正は `imas-core/src/web_export/dto/common.rs` の `SiteMeta.schema_version`。Node 側の参照は `web/scripts/data-root.mjs` の `SCHEMA_VERSION` 定数 1 箇所に集約してあり、`web/src/lib/data.ts` / `web/scripts/require-data.mjs` / `web/wasm/imas-fold-wasm/check-parity.mjs` / テスト群はすべてそこから import する (Node 側で裸のリテラルを持たない)。破壊的にスキーマを変える場合は Rust 側の値と `data-root.mjs` の値を同時に上げる — 手動同期が要るのは Rust ⇄ Node の境界を跨ぐこの 1 箇所だけで、ずれれば `require-data.mjs` (prebuild) と `check-parity.mjs` の両方がビルドを止める。

---

## 6. URL 規約

| URL | 内容 |
|---|---|
| `/` | トップ (今後のライブ・最近の公演・検索入口・アプリ紹介) |
| `/events/` `/events/upcoming/` `/events/past/` `/events/past/<year>/` `/events/brand/<brandId>/` `/events/<eventId>/` | ライブ |
| `/shows/<showId>/` | 公演 (セトリ) |
| `/songs/` `/songs/brand/<brandId>/` `/songs/<songId>/` | 楽曲 |
| `/idols/` `/idols/brand/<brandId>/` `/idols/birth-month/<1..12>/` `/idols/<idolId>/` | アイドル |
| `/units/` `/units/brand/<brandId>/` `/units/<unitId>/` | ユニット |
| `/venues/` `/venues/pref/<prefecture>/` `/venues/<venueId>/` | 会場 |
| `/brands/` `/brands/<brandId>/` | ブランド |
| `/search/` | 検索 (唯一のクライアント island) |
| `/about/` | 非公式表記・権利・ライセンス・アプリ導線・データ貢献 |
| `/404.html` | 404 |

- `trailingSlash: "always"` (Astro) と `html_handling: "force-trailing-slash"` (`wrangler.jsonc`) を対にする。
- **id は生のまま (percent-encode のみ) を使う**。`domain/share_text.rs::escaped_id` は使わない — これは Swift の `URL(string:)` が「1 文字でも不正なら既存 `%` ごと再エンコードする」という癖を意図的に再現した関数で (`@` が `%2540` になる)、静的アセットのパス照合とは前提が異なる。
- 危険文字・長すぎる id (`MAX_SEGMENT_BYTES` = **240 バイト**超) だけ `<安全な先頭 N 文字>-<fnv1a64 の先頭 8 hex>` にフォールバックする部分適用。**現在値は 2 件** (venues の `/` を含む id のみ・`unsafe=2 tooLong=0`)。上限を 200 から 240 に上げたのは、実データ最長 206 バイトのライブ 3 本を読める URL に戻すため (206 バイトの id が Astro のビルドと Cloudflare の配信の両方を通ることは実測済み)。フォールバック件数は**理由別に** Rust テストで固定してあり、危険 id が増えたら CI が気付く。
- **`other` ブランド (ラブライブ等の合同ライブ楽曲・アイドル)** はページとしては掲載するが検索エンジンには載せない: `/brands/other/`・`/idols/brand/other/`・`other` 所属のアイドル/ユニット/曲の詳細ページは `<meta name="robots" content="noindex,follow">`。それ以外は `index,follow`。非公式ファンサイトが他フランチャイズ名で検索流入を取りに行かないための判断で、`SeoBlock.robots` として Rust 側が決め、Astro は `<meta>` と sitemap のフィルタに写すだけ (INV-1 のとおり判断は TS に置かない)。
- `/songs/brand/other/` の一覧ページ自体は作らない (`SongListFilter` の既定 `include_other_brand=false` と矛盾するため)。`other` の曲は検索と個別ページからのみ到達する。

### Universal Links (現状と今後)

現行 AASA (`imas-live-api/` が返す `apple-app-site-association`) は `/app/{events,shows,polls}/*` のみを対象にしており、iOS 側 `DeeplinkRouter.parse` はパスコンポーネント数 (`== 3`) と Worker ホスト固定を前提に判定している。Web の `/events/<id>/` `/shows/<id>/` は将来 Universal Links を受けられる URL 形にしてあるが、**実際に受けるには iOS 側の改修 (`DeeplinkRouter.parse` の拡張 + `associated-domains` エンタイトルメントへの Web ドメイン追加) が別途必要**であり、本タスクの対象外 (§12 O4)。

---

## 7. テーマの当て方

- Rust (`imas-core::web_export::theme`) が `color_engine::derive(seed, brand, dark)` と `theme_hex` を呼び、`web/public/themes.css` を単一ファイルとして出力する。キーは `idol:<idolId>` / `brand:<brandId>` / `neutral` の 3 種、計 404 件 (394 idols + 9 brands + neutral)。
- CSS は `[data-theme="idol:xxx"]{--accent:…}` を light と `@media (prefers-color-scheme: dark)` の 2 系統で出す。HTML 側は要素に `data-theme` 属性を 1 個持たせるだけで、インライン `style` 配布はしない。
- 優先順位 (アイドル色→ブランド色→ニュートラル) は `color_engine::first_valid_hex` が決める。**ブランド ID そのものを seed に渡してはいけない** (`"876"` が `#887766` として通ってしまう既知の罠)。渡すのは `brands.color` の値のみ — これは Rust 側の既存契約であり Web もそれに従う。
- **hex はどのファイルにも直書きしない。** ニュートラル (DS トークン) は `web/src/styles/tokens.css` 1 箇所、エンティティ色は `themes.css` 1 箇所のみが正。レビュー時 `grep -rnE "#[0-9a-fA-F]{6}" web/src --include=*.astro --include=*.ts` が 0 件であることを確認する。
- テーマ切替 UI は作らない。`color-scheme: light dark` を `:root` に設定し、`prefers-color-scheme` にのみ追従する。

---

## 8. 検索の照合規則

- **`imas-text-fold`** (リポジトリ直下、依存ゼロの独立 crate) が畳み込み規則 (`fold` / `fold_kana` / `contains` / `find` / `fold_with_offsets`) の唯一の実体。`imas-core` はこの crate を `use` するだけで、`text_search_index.rs` の公開シグネチャ (`TextSearchIndex` / `FoldedNeedle` / `prepare_needle` / `match_range` / `matching_indices`) は変えない。
- ブラウザ側は **`imas-text-fold` を `wasm-bindgen` で直接公開した `web/wasm/imas-fold-wasm/`** を `/search/` の island からのみ動的 import する。畳み込みロジックを TypeScript に手で移植する経路 (Plan F) は、wasm ビルドサイズやツールチェーンの都合で不成立になった場合の代替であり、採用可否は `imas-core` 側の spike ログと `web/tests/fold.parity.test.ts` の結果で確定する (実装後にどちらを採ったかをここに追記する — 実装完了時点で本節を更新すること)。
- 索引 JSON (`web/data/search/*.json`) の `f` フィールドは、`TextSearchIndex` が持つ畳み済みフィールドをそのまま `U+0001` 区切りで連結したもの。ブラウザ側の照合は **`r.f.includes(fold(query))` の 1 行だけ**であり、スコアリングや前方一致優先などの独自ロジックを足さない。
- 検索対象は v1 では **曲・アイドル・ライブ・会場の 4 種**。公演 (show) とユニット (unit) は対象外 (`Snapshot` に単独の検索索引が無いため。ユニット検索を足す場合は `Snapshot::unit_search` を imas-core に追加するのが筋であり、Web 都合の実装ではなく imas-core の改善として起票する — §12 O2)。
- パリティ検証: `web/data/parity/fold.json` (実 DB の代表テキスト + 境界ケース) を `web/tests/fold.parity.test.ts` が全件流し、Rust 側の畳み込みとブラウザ側の畳み込みが一致することを固定する。

---

## 9. ビルド / デプロイ手順

### ローカル

```bash
# 初回だけ
cd web && npm ci
cargo install wasm-pack     # wasm 経路を採る場合

# フルビルド (1 コマンド。cargo export → wasm → astro build)
cd web && npm run build:all

# データを再生成せず HTML だけ作り直す (cargo を呼ばない)
cd web && npm run build

# フィクスチャで UI 開発 (core-coder の出力を待たない)
cd web && npm run dev:fixture

# 本番と同じ配信 (assets-only Worker) で確認
cd web && npm run preview
```

**`npm run build` は cargo を呼ばない。** `prebuild` (`scripts/require-data.mjs`) が `web/data/meta.json` の存在と `schemaVersion` を検査するだけで、無ければ「`npm run export` を先に」と言って失敗する。npm から cargo を暗黙に走らせると「cargo を回すのは core-coder だけ・並列ビルド禁止」という運用ルールを壊しやすいため、cargo が走るのは明示の `npm run export` / `npm run build:all` のときだけにしてある。

### CI (`.github/workflows/web-deploy.yml`)

`develop` への push (`web/**` / `imas-core/**` / `imas-text-fold/**` / `db/master.sql` の変更)、PR (ビルド検証のみ)、毎日 20:00 UTC (= JST 05:00) の schedule、`workflow_dispatch` で起動する。手順:

1. `bash tools/build_db.sh` (同梱 `master.sqlite` を作る。imas-core の既存テスト流儀に合わせる)
2. `cargo test --locked --features web-export` (web-export の DTO・URL・テーマ・検索索引アクセサのテスト一式)
3. `web/src/lib/schema/*.ts` が存在することの確認 → `git diff --exit-code -- web/src/lib/schema` (スキーマのドリフト検査)
4. `cargo run --release --locked --features web-export --bin web-export -- --sql ../db/master.sql --out ../web/data` (JSON 生成)
5. `wasm-pack build` (`web/wasm/imas-fold-wasm/`)
6. `npm ci` → `npm run check` (型検査) → `npm test` (fold パリティ・フィクスチャ型検査) → `npm run build` (astro build + `check-limits.mjs`)
7. secrets (`CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID`) が両方登録されていれば `npx wrangler deploy`。無ければ `::notice::` を出してスキップする (PR では常にスキップ)。

`concurrency` で同一 ref の重複実行をキャンセルし、`timeout-minutes: 45` で長時間化を打ち切る。cargo キャッシュは `imas-core/target` と `web/wasm/imas-fold-wasm/target` の両方を対象にする。

既存の 3 ワークフロー (`core-guard.yml` / `ios-guard.yml` / `android-guard.yml`) は **`paths` に `imas-text-fold/**` を 1 行足しただけ**で、それ以外の変更は一切していない (`imas-text-fold` 抽出がアプリ側のビルドに波及していないかを既存 CI でも検知するため)。

### Cloudflare secret の登録手順 (オーナー作業)

1. Cloudflare ダッシュボード → **My Profile → API Tokens → Create Token**。
   - テンプレート **"Edit Cloudflare Workers"** を使うか、最小権限で **Account → Workers Scripts: Edit** のみを付与したカスタムトークンを作る。
2. 発行されたトークンをコピー。
3. GitHub リポジトリ → **Settings → Secrets and variables → Actions** → New repository secret を 2 つ登録:
   - `CLOUDFLARE_API_TOKEN` = 上記トークン
   - `CLOUDFLARE_ACCOUNT_ID` = `0baf14f22a0bffdbb33931ce7edebb20`
4. 登録後の次回 `web-deploy.yml` 実行 (push / schedule / workflow_dispatch) から自動で deploy step が有効になる。未登録の間はビルド検証のみ行われ、サイトは公開されない。

`imas-live-api/` の Worker とは別デプロイ・別 `wrangler.jsonc` (`web/wrangler.jsonc`)・別 Worker 名 (`imas-live-web`) であり、既存の secret やルート設定には影響しない。

---

## 10. Cloudflare 制限と現在値

Cloudflare Workers Static Assets の上限は **20,000 ファイル / 1 ファイル 25 MiB**。`web/scripts/check-limits.mjs` が `dist/` を毎ビルド走査し、ファイル数 18,000 超または単一ファイル 20 MiB 超で exit 1 する (総サイズは根拠となる公式上限が無いため警告のみ)。

| 指標 | 見積り (設計時点) | 実測 |
|---|---|---|
| ページ数 | 約 7,650 | **7,631** |
| ファイル数 (`dist/`) | 約 7,690 | **約 7,665** |
| 最大ファイルサイズ | 1 MiB 未満 | **957 KB** (`/songs/` の一覧 JSON。HTML は 1 MiB 未満) |
| 総サイズ | 130–160 MB | **約 166 MB** (`web/data` は 160 MB) |
| 検索索引 (brotli 後) | 約 250KB (4 シャード) | **141 KB** (raw 785 KB) |
| URL フォールバック slug | 2 件 (venues の `/`) | **2 件** (`unsafe=2 tooLong=0`) |
| 上限に対する余裕 | ファイル数で 38% 程度 | 20,000 に対して 38%。songs 5,000 / units 2,500 / shows 2,000 まで増えても半分以下 |

実測値は `web-export` の stderr 統計 (`pages=… files=… bytes=… fallbackSlugs=…`)、`npm run build` の `[check-limits]` ログ、`npx wrangler deploy --dry-run` から埋めてある。

---

## 11. やってはいけないこと集

- `web/src/**` に業務ルール (何を出す/隠す・並び・年グループ・クレジット分割・披露回数・色導出・検索の畳み込み) を書く。
- `web/src/**` で `new Date()` を使う。「今日」は imas-core がビルド時に 1 回だけ確定した `meta.todayJst` のみを使う。
- CSS 変数を経由せず hex カラーを直書きする。
- `web/data/` (JSON 全量) を丸ごと `public/` に置く。dist に出してよいのは `search/*.json` と `parity/fold.json` だけ。
- 一覧ページにクライアントサイドフィルタ (ブランド切替・年切替など) を足す。フィルタ結果は別 URL の静的ページにする。
- 歌詞本文・プレビュー音源 URL・キャラクター画像・公式ロゴを出力 JSON や HTML に含める。
- `imas-live-api/` の `wrangler.jsonc` / ルート / cron / secret を変更する。
- `/search/` 以外のページに `<script>` を置く。
- **データが行の集合や値を決める**文面 (何件出すか・どの順で並べるか・値によって出し分けるラベル、SEO 文・版権表記を含む) を `.astro` に直書きする。文言の正は imas-core の `SeoBlock` / 各 DTO のフィールドであり、Astro は受け取った文字列を置くだけ。
  - **例外 (レイアウト側の定型文として許容)**: レコードに依存しない見出し (「原唱者」「クレジット」「披露履歴」「よく歌うアイドル」等のセクション見出し) と空状態 (`EmptyState`) の文言。全ページ共通のテンプレート構造テキストであり、どのレコードを読んでも変わらないため。`/search/` と `/404` の案内文 (imas-core が持たない画面)、ヘッダ/フッタの固定ナビ表記と版権表記も同様に扱う。
  - 全部を Rust の DTO に持たせて見出しの入れ物にするのは割に合わないため、この例外は意図的な線引き。**データによって集合や値が変わるもの** (件数タイル・一覧行・プロフィール行など) は例外にせず Rust 側に置く。

---

## 12. 未決事項 (リーダー判断が必要)

| ID | 未決 | 選択肢 | 現時点の推し |
|---|---|---|---|
| O1 | Worker の `/app/{events,shows}/<id>` 着地ページを Web に向け替えるか | (a) 今回はやらない (b) 後続タスクで 302 (c) Worker が Web を fetch して返す | (a) → 後続で (b)。今回は `imas-live-api/` に触らない |
| O2 | ユニット検索 (1,539 件) を Web 検索に含めるか | (a) v1 は除外 (b) `Snapshot::unit_search` を imas-core に追加 | v1 は (a)。(b) は imas-core の改善として別起票 |
| O3 | venues の壊れ id 2 件 (`/` を含む) をデータ側で直すか | (a) フォールバック slug のまま (b) `db/master.sql` を直して CloudKit にも反映 | 別タスクで (b)。id 変更は CloudKit の PK 変更を伴うため慎重に。それまで (a) で正しく動く |
| O4 | songs/idols/units/venues への deeplink 対応 (iOS `DeeplinkRouter` 拡張) と Universal Links 化 | (a) やらない (b) アプリ側タスクとして起票 | (b)。本タスクでは iOS に触らない |
| O5 | TypeScript 7 (Go 実装) への追随 | (a) 5.x に pin (b) 7 を試す | (a)。`@astrojs/check` の対応が確認できるまで `~5.9` で固定 |
| O6 | 独自ドメイン | (a) `workers.dev` のまま (b) ドメイン取得 | (a)。「ランニングコスト 0」が絶対制約。将来ドメインを持つ場合は `astro.config.mjs` の `site` / `robots.txt` / 本書の 3 箇所だけを変える (JSON 側は相対パスなので影響なし) |
| O7 | `idol_profile_input` (iOS のプロフィール整形規則を imas-core に移送したもの) を iOS/Android 側にも適用し 3 プラットフォーム統一するか | (a) Web だけが使う (b) 3 プラットフォーム統一 | (b) を後続タスクで。(a) のままだと整形ロジックが 3 実装になる |

---

## 実装に最も重要なファイル

- `imas-core/src/domain/snapshot.rs` — 全 DTO の供給源。索引の並び順規約が各フィールドの doc に書かれており、`web_export::emit` はそれを写すだけでよい。
- `imas-core/src/domain/text_search_index.rs` / `imas-text-fold/src/lib.rs` — 検索の畳み込み規則の唯一の実体。
- `imas-core/Cargo.toml` — `[features] web-export` / `[[bin]] required-features` / `imas-text-fold` の path 依存を足す唯一の場所 (rusqlite の target cfg ブロックは不可触)。
- `imas-core/build.sh` — `cargo build --release --target … --lib` 無しで叩いているため、web-export bin を iOS/Android クロスビルドから外すには `required-features` が必須という制約の根拠。
- `imas-core/src/domain/color_engine.rs` — `derive(seed, brand, dark)` と `theme_hex`。Web のテーマ CSS 変数はすべてここから出る。
- `ImasLiveDB/DesignSystem/DesignTokens.swift` — `web/src/styles/tokens.css` に写すニュートラル・スペーシング・角丸・タイポの値の正。
- `web/src/lib/data.ts` — JSON 読み込みの唯一の入口 (`join`/`filter`/`sort` を書かない場所)。
- `web/wrangler.jsonc` / `.github/workflows/web-deploy.yml` — デプロイ設定の正。
