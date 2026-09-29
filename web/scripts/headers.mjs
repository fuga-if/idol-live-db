// Cloudflare Workers Static Assets が読む `_headers` を、ビルドのたびに組む。
//
// 以前は public/_headers を手で書いていて、歌詞を閉じても connect-src に Worker が残っていた
// (開け閉めのたびに人が CSP を直す必要があった)。**ブラウザが自分以外のどこと通信してよいかは
// Rust が決める** (`meta.json` の `connectOrigins`。歌詞を出す間だけ歌詞 API の origin が入る)。
// ここは書式に流し込むだけ。
//
// CSP の方針 (docs/ARCHITECTURE-web.md):
//   - JS は探す / 絞るための島だけ。インラインの script / style は使わない
//     (astro.config の `inlineStylesheets: "never"`。`style=` 属性は本番でだけ黙って無視される)
//   - 外部から読み込むのはジャケ画像 (Apple Music の CDN) だけ。
//     実データでは is1-ssl.mzstatic.com だけだが、Apple 側のホスト名は is1〜is5 で変わりうるので
//     ワイルドカードにする
//   - form-action は 'self' — トップの検索窓は JS 無しの GET フォームで /search/?q= へ飛ぶ
//   - wasm (検索の畳み込み・一覧の絞り込み) のために 'wasm-unsafe-eval'

/**
 * @param {{ connectOrigins: readonly string[] }} meta `meta.json` (web-export の出力)
 * @returns {string} `_headers` の中身
 */
export function buildHeaders(meta) {
  const connectSrc = ["'self'", ...meta.connectOrigins].join(" ");
  const csp = [
    "default-src 'none'",
    "base-uri 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "img-src 'self' https://*.mzstatic.com",
    "style-src 'self'",
    "script-src 'self' 'wasm-unsafe-eval'",
    `connect-src ${connectSrc}`,
    "font-src 'self'",
    "manifest-src 'self'",
  ].join("; ");

  return `# このファイルはビルドで組む (web/scripts/headers.mjs)。手で直さない。
/*
  Content-Security-Policy: ${csp}
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin

# 検索索引と生テーブルは「当たるため / 組み直すためのデータ」であって記事ではない。
# 検索エンジンに直接インデックスされる意味が無いので除外する。
/search/*.json
  X-Robots-Tag: noindex
/snapshot/*
  X-Robots-Tag: noindex

# content-hash 付きアセットは中身が変われば必ずファイル名も変わるため immutable で安全。
# HTML (/*) は日次再ビルドで内容が変わるので既定のまま。
/_astro/*
  Cache-Control: public, max-age=31536000, immutable

# /fonts/* はファイル名が固定 (中身を差し替えても名前が変わらない) なので immutable にしない。
# 差し替えたときに古いキャッシュが 1 年残らないよう、30 日 (2,592,000 秒) に留める。
/fonts/*
  Cache-Control: public, max-age=2592000
`;
}
