# web/e2e — Web の E2E とシナリオ台帳

**ローカルで回すもの。CI では回さない。** 大きく変えたときは全部、ふだんは変えたところに
関係するシナリオだけを回す。

考え方は「主要な流れだけ守る」ではなく、**ソースから機械的に拾った画面・操作すべてに
シナリオを当てる**こと。拾い漏れは人の記憶ではなく突き合わせが見つける。

## 使い方 (`web/` で)

```bash
npm ci
npm run e2e:install      # 初回だけ。Playwright の Chromium を入れる
npm run e2e              # 台帳の突き合わせ → フィクスチャでビルド → 全シナリオ (pc / mobile)
npm run e2e:changed      # origin/develop から変えたところに関係するシナリオだけ
npm run e2e:ledger       # 台帳の突き合わせだけ (ブラウザ無し・数秒)
npm run e2e:inventory    # 画面・操作の一覧 (inventory.generated.json) を作り直す
```

- 対象は `data-fixture/` でビルドした `dist/` を `wrangler dev` (本番と同じ CSP・trailing slash・404)
  で出したもの。実データも `npm run export` も要らない。ビルドには wasm (`npm run wasm`) が要る。
- 外への通信 (歌詞 API・ジャケ画像) はテストがすべて止めるか差し替える (`support/test.ts`)。
- 失敗したテストは trace が残る: `npx playwright show-trace test-results/…/trace.zip`
- `e2e:changed` は `-- --headed` のように後ろへ Playwright の引数を渡せる。`--base <ref>` で基点を変えられる。

## 3 つのもの

| | 置き場所 | 誰が書く |
|---|---|---|
| 母集団 (画面・操作の一覧) | `ledger/inventory.generated.json` | `tools/inventory.mjs` が src/ から作る。手で書かない |
| シナリオ台帳 | `ledger/scenarios/<area>.json` | 人 / AI。**何を確かめるかの正** |
| テスト | `tests/<area>/*.spec.ts` | 人 / AI。`tag: "@AREA-001"` で台帳の id を指す |

母集団のキーは 3 種類:

- `route:/songs/[songId]/` — `src/pages/**` の 1 ファイル = 1 URL 種別
- `island:src/components/SongLyrics.astro` — ブラウザで動く `<script>` を持つ .astro
- `op:src/lib/search/island.ts#init/input:input` — `addEventListener` 1 つ (`<関数>/<受け手>:<イベント>`)

## シナリオの書き方

```json
{
  "id": "SEARCH-004",
  "title": "歌詞モードに切り替えると、打ち終わってから歌詞 API に 1 回だけ問い合わせ…",
  "status": "implemented",
  "pendingReason": null,
  "covers": ["op:src/lib/search/island.ts#init/m:change", "op:src/lib/search/island.ts#init/input:input"]
}
```

- `title` は**仕様として**どうなるべきかを書く (今の実装がたまたまそう動くこと、ではない)。
- `status` は `implemented` (テストがある) か `pending` (まだ無い。`pendingReason` 必須)。
  `implemented` は「テストがある」の意味で、通ったかどうかは `npm run e2e` が見る。
- `covers` はこのシナリオが確かめる母集団のキー。1 つのキーを複数のシナリオが持ってよい。

## `npm run e2e:ledger` が落とすもの

1. `inventory.generated.json` がソースと違う → `npm run e2e:inventory` してコミット
2. 母集団を読めない箇所 (イベント名が文字列リテラルでない等。黙って捨てない)
3. **どのシナリオにも入っていない画面・操作** (= 足したのにシナリオが無い)
4. covers が母集団に無いキーを指す (消した・名前が変わった)
5. id の重複・書式違い、pending の理由が空
6. implemented なのにテストが無い / pending なのにテストがある
7. テストのタグが台帳に無い id を指す
8. **pending が `pending-baseline.json` より増えた**、または済んだのに baseline に残っている

pending を増やすのは、理由を書いてレビューに出すときだけ:
`npm run e2e:ledger -- --accept-pending` で baseline を書き換え、その差分ごとコミットする。

## 新しいページ・操作を足したとき (AI もこの順で)

1. `npm run e2e:inventory` → 増えたキーを見る
2. `ledger/scenarios/` に、そのキーを covers に持つシナリオを足す (既存のを広げてもよい)
3. `tests/<area>/` にテストを書き、`tag: "@<id>"` を付ける
4. `npm run e2e:changed` で通す

## できないこと (分かっている穴)

- covers に当たっているかは見るが、**アサーションが十分か**は見ない (レビューで見る)。
- 母集団は route / island / addEventListener だけ。CSS だけで動くもの (`<details>` の開閉など) や
  ただのリンクは個別のキーにならない (ページ単位の PAGE-001 で開けることだけ見る)。
- フィクスチャに無いデータの画面は確かめられない (今の pending はほぼこれ)。
