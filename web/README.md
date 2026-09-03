# web/ — アイドルライブDB の Web 出面

アイマスのライブ・公演・セットリスト・楽曲・アイドルを **誰でもブラウザで閲覧・共有できる**
静的サイト。Astro でビルドし、Cloudflare Workers Static Assets (assets-only) に置く。

**このサイトは表示専用。** 担当・お気に入り・参加記録・投票・タグ・ペンライト・歌詞・コール・
編集・ログインといった「状態を持つ機能」は一切作らない。それらはすべて iOS/Android アプリ側にあり、
各詳細ページの「アプリで開く」導線から誘導する。ブラウザで動く JS は `/search/` の 1 本だけ。

設計の全体像・依存方向・不変条件・デプロイ手順は **[docs/ARCHITECTURE-web.md](../docs/ARCHITECTURE-web.md)** が正。

## 大原則 (これを破ると設計が崩れる)

1. **表示ルールの唯一の正は `imas-core` (Rust)。** 何を出す / 隠す・並び・年グルーピング・
   クレジット分割・披露回数・色の導出・検索の畳み込み・「今日」の判定は、すべて Rust が済ませて
   JSON に落としてある。`src/**` がやってよいのは **JSON のフィールドを HTML の要素に置くこと**だけ。
   `src/` に `new Date(` を書かない。href は Rust が出した `path` をそのまま入れる (encode しない)。
2. **hex を書いてよいのは `src/styles/tokens.css` だけ。** エンティティ色は `data-theme` 属性 +
   Rust 生成の `public/themes.css` が供給する。
3. **インライン `<style>` / `style=` 属性を書かない。** 配信時の CSP が `style-src 'self'`
   (unsafe-inline 無し) なので、書いた瞬間に見た目が死ぬ。同じ理由で `astro.config.mjs` の
   `build.inlineStylesheets` は `"never"` 固定。
4. **`src/pages/**` に `<script>` を置いてよいのは `search.astro` だけ。** JSON-LD は
   `components/JsonLd.astro` に閉じ込める。
5. **版権物ゼロ。** キャラクター画像・公式ロゴ・歌詞は載せない。アイドルはモノグラム表示、
   ジャケットは `songs.artwork_url` (Apple Music CDN) の直参照のみ。

## npm scripts

| コマンド | 何をするか | 生成物 |
|---|---|---|
| `npm run export` | **cargo を回す。** `db/master.sql` から全ページの JSON を出す | `data/` |
| `npm run wasm` | 検索語の畳み込み wasm を作る | `public/fold/` |
| `npm run build` | `data/` を検査 → `astro build` → `dist/` の上限検査 | `dist/` |
| `npm run build:all` | `export` + `wasm` + `build` を通しで | 上記すべて |
| `npm run dev` | 実データで開発サーバ | — |
| `npm run dev:fixture` | **フィクスチャで開発サーバ** (`IMAS_WEB_DATA=./data-fixture`) | — |
| `npm run build:fixture` | フィクスチャで全ページ種別をビルドして通るか見る | `dist/` |
| `npm run preview` | `wrangler dev` = 本番と同じ配信 (`_headers` の CSP・trailing slash・404 込み) | — |
| `npm run check` | `astro check` + `tsc --noEmit` | — |
| `npm test` | パリティ検査 + フィクスチャ / データの不変条件検査 | — |
| `npm run deploy` | `wrangler deploy` (通常は CI が行う) | — |

`npm run build` は **cargo を呼ばない**。データの再生成は明示的に `npm run export` / `build:all`
を叩いたときだけ起きる。

## ディレクトリ

```
src/
  pages/        ルート。1 ファイル = 1 URL 種別。getStaticPaths は routes.json を返すだけ
  layouts/      BaseLayout (全ページ) / DetailLayout / ListLayout
  components/   アプリの Imas* 部品を Web に移したもの (状態を持つ振る舞いは落としてある)
  styles/       tokens.css (DS の写し・hex はここだけ) / base.css / components.css
  lib/
    data.ts     data/**.json を読む唯一の入口。join / filter / sort をここに書かない
    ui-types.ts 葉の部品が読む値だけの構造的な型
    search/     /search/ の island と、畳み込み wasm への差し替え可能な import 面
    schema/     ★生成物★ ts-rs が Rust の DTO から出す TS 型。手で編集しない
    fold/       (未使用。wasm の出力先は public/fold/)
public/         そのまま配信されるもの (アイコン / OGP / フォント / robots.txt / _headers)
  fold/         ★生成物★ wasm-pack の出力
  themes.css    ★生成物★ Rust が出すテーマ変数
data/           ★生成物★ web-export が出すページ JSON (約 7,600 個)
data-fixture/   代表値のフィクスチャ (commit されている)。実データ無しで開発・テストできる
tests/          vitest
```

★生成物★ は `.gitignore` されているか、生成した担当がコミットする。**手で編集しない。**

## 実データが無いときの開発

```bash
npm ci
npm run dev:fixture          # http://localhost:4321
npm run build:fixture        # 全ページ種別がビルドできるか
IMAS_WEB_DATA=./data-fixture npx vitest run
```

`data-fixture/` には境界ケース (日本語と `@` を含む id / ジャケ無しの曲 / 空の一覧 /
`deeplink` の無いページ / フォールバック slug に落ちた会場) が 1 件ずつ入っている。

## 見た目の正

`ImasLiveDB/DesignSystem/` の `DesignTokens.swift` / `ImasComponents.swift` / `ImasTheme.swift`。
`tokens.css` はそこからの写しで、**1 か所だけ意図的にずらしている**: ライトの `--ds-ink2` を
`.62` → `.72` に濃くした。Web には Dynamic Type も OS のコントラスト設定も無く、`.62` のままだと
副次テキストが WCAG AA (4.5:1) を満たさないため。`--ds-ink3` はコントラストを満たさないので
**文字に使わない** (シェブロン・区切りなどの装飾専用)。
