# 引き継ぎ: Web 出面の UI/UX 全面改修

宛先: この後 Web 出面 (`web/`) の UI/UX をがっつり直す担当。
作成: 2026-09-06 / 対象ブランチ `claude/mac-layout-design-55b2a3` / 公開先 https://idollivedb.fugalabs.uk

---

## 対応状況 (2026-09-06、ブランチ `claude/web-page-high-quality-bfa367`)

§2 の指摘はすべて対応した。§4 の 5 本の線は踏んでいない。

| 指摘 | どう直したか |
|---|---|
| 「最近の公演」の主従が逆 | 行の見出しをライブ名、公演名 (`DAY1`) を副題に。Rust が `ShowSummary.show_label` (ライブ名との重なりを落とした公演名) を出す |
| サイト名が 3 回 | eyebrow を廃止。上部バーのブランドとトップの `<h1>` の 2 箇所だけ |
| 左サイドバー 208px | **上部バー 1 本**に置き換え (`base.css`)。本文の最大幅を 1120 / 1320px に広げた。並びは `meta.primaryNav` (Rust) |
| 行が全部同じ | `DatedRow` (日付ブロック + 見出し + メタ + 末尾) を共通骨格に。トップの先頭 1 件は `FeatureEvent` で大きく |
| 副題が長い 1 本 | 日付は `DateBadge` (月日・曜日・年、Rust の `DateBadge` DTO)、ブランドは色付きの札、会場は `venue_display`、公演数は数、に分解 |
| 詳細ページも同じ問題 | ヒーローに `Facts` (日程・会場・開演 …) と数の帯。公演ページは `short_name` (`Day2`) を見出しに、同じライブの公演はセグメントで切替 |

Rust に足した形 (`cargo test --features web-export` で TS 型を再生成済み):
`DateBadge` / `EventListItem.{date_badge,end_display,brand_mark,venue_display,show_count_display}`
(繋いだ `subtitle` は廃止) / `ShowSummary.{title,show_label,date_badge,start_time_display}`
(文脈は `emit::events::ShowContext` が決める。`subtitle` 廃止) / `PerformanceRow.date_badge` /
`IdolShowRow.date_badge` / `EventPage.{date_display,stat_tiles}` / `ShowPage.{short_name,fact_rows}` /
`BrandPage.stat_tiles` / `SongPage.song_type_label` / `SiteMeta.{primary_nav,utility_nav}`。
曜日と期間の畳み方は `domain::date_display` (chrono)、主要な一覧の記号・名前・入口は
`emit::lists::SiteList` が 1 本で持つ。TS 側は `DatedRow` / `Count strong` / `BrandMark` /
`Facts` (= `ProfileRow`) / `StatStrip` (= `StatTile`) を置くだけ。

トップの検索窓は JS 無しの GET フォームで `/search/?q=` へ飛ぶ (CSP の `form-action` を `'self'` に)。

**残っているもの (UI では直せない)**: §2-2 のデータ側のうち `shows.performer_type` が全件 `cast`
(入力漏れの疑い、判断待ち)。SideM 11th STAGE の重複は 2026-09-06 に master.sql 側で除去済み
(CloudKit の削除はオーナー操作待ち、`tools/pending_push_20260906/README.md`)。

---

## 0. 3 行で

- **見た目と体験がまだ全然ダメ。** 情報は揃っているが、階層・密度・視線誘導が設計されていない。
- **中身 (何を出すか) は触らなくていい。** データも規則も Rust が出しており、直す対象はほぼ `web/src/**` の HTML/CSS と、必要なら Rust 側の DTO の「形」。
- **踏んではいけない線が 5 本ある** (§4)。ここだけ守れば、あとは大きく変えてよい。

---

## 1. これは何か

アイドルマスターのライブ・セトリスト・楽曲・アイドルのデータベース。iOS / Android アプリが本体で、
`web/` はその**公開出面**。Astro の静的サイトで、Cloudflare Workers の assets-only Worker が配る。

```
imas-core/ (Rust)          … 唯一の頭脳。判断も規則も文言もここ
  domain/                  … 純粋ロジック (アプリと Web で共有)
  web_export/              … 出面用に JSON を吐く。dto/ が Rust↔TS の境界
web/                       … Astro。**描くだけ**
  src/lib/schema/*.ts      … ts-rs が imas-core から自動生成。手で書かない
  wasm/imas-query-wasm/    … domain を wasm 化。絞り込みをブラウザで回す
ImasLiveDB/ (iOS)  ImasLiveDB-Android/  imas-live-api/ (Cloudflare Worker + D1)
```

### 動かし方

```bash
cd web
npm run export      # imas-core が web/data/**.json を再生成 (Rust をビルドする)
npm run wasm        # 絞り込み wasm を再生成 (imas-core を変えたときだけ)
npm run build       # Astro → web/dist
npm run check       # astro check + tsc。**0 errors を維持すること**
npx astro preview --port 4321   # 確認したら必ず落とす (§5)
npx wrangler deploy # 本番へ
```

`npm run build:all` = export + wasm + build。

---

## 2. いま実際に何がダメか (実測つき)

ここは「直してほしいことリスト」ではなく、**私が測って確かめた事実**。
直し方は任せる。もっと良い形があるならそちらでよい。

### 2-1. トップページ

| 症状 | 実測・根拠 |
|---|---|
| 「最近の公演」の見出しが `DAY1` / `DAY2` / `夜公演` | 大きい文字が公演名 (`DAY1`)、小さい文字がライブ名。**階層が逆**。`DAY1` だけ見ても何も分からない |
| ヒーローとサイドバーでサイト名が 2 回出る | `.site-nav__brand` と hero の `<h1>` が同じ「アイドルライブDB」。さらに eyebrow に `idol Live DB` |
| 左サイドバー 208px が常時固定 | 1029px の表示領域のうち 20%。中身はリンク 7 本と検索ボタンだけ |
| 行が全部同じ見た目 | 「今後のライブ」も「最近の公演」も `LeadRow` の羅列。強弱が無い |
| 副題が長い 1 本の文字列 | `2026-09-12 〜 2026-09-13 ・ THE IDOLM@STER SideM ・ 2 公演 ・ TOYOTA ARENA TOKYO`。読点で切れるが、視線の止まりどころが無い |

**直したばかりのもの** (`e750027`。同じ轍を踏まないように):
ブランドカードのバッジは 44px 角に最長 5 文字を押し込んでいて 9 枚中 7 枚が溢れていた
(枠 44px に対し内容 66〜99px)。錠剤に変えた。件数が `アイ / ドル` と語中で折れていたのも直した。

### 2-2. データ側の既知バグ (UI では直せない)

- **ライブが 1 件重複している。** `THE IDOLM@STER SideM 11th STAGE ～EVER EVER＠FTER～` が
  `ev_2bd4cd37-...` (UUID) と `ev_the_idolmster_sidem_11th_stage_ever_everfter` (slug) の 2 レコード。
  トップの「今後のライブ」に同じ行が 2 つ並ぶ。master データの統合が要る
  (CloudKit の削除も要るので §4-2 を読むこと)。重複はこの 1 件だけ (実測)。
  → 2026-09-06: 無日付の別綴り 2 件も含めて master.sql から除去済み。CloudKit の物理削除は
  `tools/pending_cloudkit_deletions_sidem_11th_dup_20260906.tsv` (オーナー操作待ち)。
- `shows.performer_type` が**全 1198 公演 `cast`**。`character` が 0 件なので、
  歌唱者表示の「公演に合わせる」モードが実質 CV 名固定になっている。入力漏れの疑い。

### 2-3. まだ手を付けていない画面

曲詳細・アイドル詳細・ユニット詳細・会場・検索・お題 (`/polls/`) は、
トップと同じ `Section` + `LeadRow` の積み重ねで、密度も強弱もトップと同じ問題を抱えている。

---

## 3. 直す対象がどこにあるか

```
web/src/
  layouts/    BaseLayout / ListLayout / DetailLayout   … 枠。サイドバーもここ
  components/ SiteHeader・Section・LeadRow・EntryCard・Chip・TagChip・
              Artwork・ColorDot・SetlistRow・SongTable・ListFilterBar …
  styles/     tokens.css (色・間隔・書体の変数) / components.css (全部の見た目)
  pages/      ルーティング。中身は components に渡すだけ
```

- **CSS は `components.css` 1 枚**。約 1,200 行。コンポーネントごとにブロックが並ぶ。
- **テーマは `themes.css`** (Rust が生成)。`data-theme="idol:xxx"` を要素に置くと
  `--accent` / `--tint` / `--ring` / `--on-accent` が降ってくる。**hex を TS/CSS に書かない**。
- **レスポンシブはコンテナクエリ**を使っている (`@container songtable` 等)。
  サイドバーが幅を食うので、ビューポート幅で判断すると外れる。

---

## 4. 踏んではいけない線 (5 本)

### 4-1. 判断・規則・文言は `imas-core` に置く

Astro/TS に業務規則を書かない。具体的には **`new Date()` を書かない・hex 色を書かない・
表示ラベルの一覧を持たない・並び順を決めない**。これらは全部 Rust が JSON に載せてくる。

このセッションだけで、写経が原因の食い違いが 5 つ見つかっている
(モードのラベルが 3 面にコピー、並べ替えの既定方向が Rust と TS に二重、
選択肢の並びがアプリと Web で別、条件の型が 4 重定義、`is_character_live` が 3 実装)。
**見た目を変えるために規則を TS へ持ってこないこと。** 必要なら Rust の DTO に形を足す。

DTO を足したら `cargo test --features web-export` が `web/src/lib/schema/*.ts` を再生成する。
生成物と `index.ts` の一致はテストが見ている (`the_generated_schema_files_and_the_barrel_agree`)。

### 4-2. データの削除・CloudKit

`db/master.sql` が正本。`ImasLiveDB/Resources/master.sqlite` は `tools/build_db.sh` の生成物。
**master.sql から消しただけでは日次 cron で復活する。** CloudKit 側も
`tools/seed_cloudkit.py --delete-file <TSV>` で消す必要がある (手順は
`docs/JASRAC.md` ではなく memory / 過去コミット `196ebb6` を参照)。
同じ理由で、**列を NULL に直した修正も既定の push では戻る** (NULL 列は送られず、forceUpdate は
送らなかった列を残す)。`seed_cloudkit.py --replace` (forceReplace、`--ids/--ids-file` 必須) で送る。

### 4-3. ランニングコストはゼロ

assets-only Worker (`main` を書かない) なので静的配信は無料。
**閲覧のたびに D1 や API を叩く設計にしないこと。** D1 無料枠は 2026-09 時点で 96% 消費。
コミュニティのタグ・お気に入り・お題は、そのためにビルド時へ焼き込んである
(`db/community.sql` → `imas-core` → JSON)。

### 4-4. 歌詞は既定で出さない

`imas-core/src/web_export/content.rs` の `LYRICS_ON_WEB = false`。
**勝手に `true` にしないこと。** 4 つの前提 (JASRAC への確認 / 本番 API の匿名 GET /
CORS / D1 枠) が `docs/JASRAC.md` §6.5 に書いてある。UI は実装済みなので、
見た目を整える分には触ってよいが、既定値は変えない。

### 4-5. 版権物を載せない

画像はジャケ写 (Apple Music CDN) だけ。アイドルの絵は持てないので、
色 (`ColorDot`) と名前で見分ける設計になっている。**イラストや公式ロゴを足さないこと。**

---

## 5. 作業環境の注意 (重要)

**16GB の Mac で、他の Claude セッションが同時に動いていることがある。**
このセッションでは iOS シミュレータと Xcode ビルドを並行させてスワップを
19GB 使い切り、マシンが実用不能になった。

- **UI/UX 改修に iOS/Android のビルドは要らない。** 走らせないこと。
- `astro preview` は確認が済んだら `pkill -f "astro preview"` で落とす。
- `cargo` は `imas-core` のビルドで数分かかる。並列で走らせない。
- 現状の空き: 作業前に `sysctl vm.swapusage` と `top -l 1 | grep PhysMem` を見ること。

---

## 6. 直近のセッションで入れたもの (6 コミット + 4 本)

| コミット | 内容 |
|---|---|
| `60b64b0` | 絞り込みを wasm 実行に置き換え / 歌唱者の表示名モード |
| `b5f83c8` | アイドルアイコン (モノグラム) を削除 |
| `59fb5f0` `f0b97b4` | iOS / Android へ歌唱者表示設定を展開 |
| `196ebb6` `db62db3` | 配信・ラジオ系イベント 107 件と、それ由来のカバー曲 100 曲を削除 |
| `e372c38` `baf8d76` `74dabf2` | Simplifier の指摘反映 (規則をコアへ寄せる) |
| `2b687a7` | アイドル一覧にアプリと同じ絞り込み |
| `0cdab5c` `ec4038d` | コミュニティ集計の焼き込み / `/polls/` |
| `7194a43` | 歌詞・コールガイド (既定 off) |
| `e750027` | ブランドカードの崩れ修正 |

### 触ると壊れやすい仕掛け

- **絞り込みの島** (`web/src/lib/listfilter/`)。曲とアイドルで実装は 1 本。
  軸は `FieldSpec` の 1 行で決まる (型・初期値・URL の鍵・描画・重ね方・判定が全部そこから導出)。
  **軸を足すときも 1 行で済むはず。** 6 箇所に散らし直さないこと。
- 一覧の行は `data-song-id` / `data-entity-id` で島が引く。**マークアップを変えるときこの属性を消さない。**
- `snapshot/tables.json` (9.3MB) は絞り込みを開いたときだけ取りに行く。
  一覧を読むだけの人には配らない設計なので、初期表示で読み込ませないこと。

---

## 7. 最初にやるとよさそうなこと (提案・拘束しない)

1. **情報階層を決め直す。** いま全部が同じ強さで並んでいる。
   「最近の公演」の `DAY1` とライブ名の主従を入れ替えるのが分かりやすい入口。
2. **サイドバーの是非。** 208px 固定が本当に要るか。上部ナビに寄せると本文が広く使える。
3. **行の情報設計。** 副題の 1 本長文をやめ、日付・ブランド・会場を別の位置に置く。
4. **密度とリズム。** `Section` が等間隔に積まれているだけなので、
   トップだけでも「見せる塊」と「並べる塊」を分ける。
5. そのあと詳細ページ (曲・アイドル・公演) へ同じ言語を展開する。

---

## 8. レビューの回し方 (2026-09-06 に 1 巡)

UI/UX は**批判的レビューを 4 観点で並列に回して**から直す: IA/導線・ビジュアル・
アクセシビリティ・文言/ドメイン適合。各観点は「重要度・ページ・証拠 (スクリーンショット)・
なぜ困るか・直し方 (Rust か Astro/CSS か)」の 10 件以内で返す。1 巡目の指摘と反映は
`docs/ARCHITECTURE-web.md` の「批判的レビュー 1 巡目の反映」。データ起因の指摘 (重複レコード・
原唱者ロールの欠け) は Web で直さず、同じ節に宿題として書く。

## 9. 参照

- `docs/ARCHITECTURE-web.md` … 出面の設計 (表示専用・assets-only の理由)
- `docs/JASRAC.md` §6.5 … 歌詞を出すときの前提 4 つ
- `docs/DATA_PIPELINE.md` … master.sql / CloudKit / 日次 cron
- `CLAUDE.md` … コード作成後に Code Simplifier を回す運用
