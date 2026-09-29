// routes/app_links.ts — Universal Links (共有リンク) の入口。
//
//   GET /.well-known/apple-app-site-association — アプリで開くパスの定義 (AASA)
//   GET /app/{events,shows,polls}/:id           — アプリが無い端末向けの着地ページ (HTML)
//
// 着地ページには IP の枠を掛けない (アプリ証明の口の枠は routes/app_attest.ts)。
// 名前は CloudKit (公演・イベント) と D1 (お題) から引き、引けなければ 404 の誘導ページを返す。

import { APP_ID } from "../appattest";
import { cloudKitLookup } from "../cloudkit";
import type { RouteContext } from "./context";

/** アイドルライブDB の App Store ページ (未インストールユーザーの誘導先)。 */
const APP_STORE_URL = "https://apps.apple.com/jp/app/id6763342297";
const APP_STORE_NUMERIC_ID = "6763342297";

/** HTML テキスト/属性値に埋め込む動的文字列のエスケープ (XSS 防止)。 */
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Universal Links のブラウザフォールバックページ。
 * アプリ未インストール (またはデスクトップ) でリンクを開いた人向けに、
 * イベント/公演名 + アプリ紹介 + App Store 誘導を返す。
 * title が null (未知 ID) でも安全に静的文言へフォールバックする。
 */
function renderAppFallbackPage(opts: {
  kind: "events" | "shows" | "polls";
  id: string;
  title: string | null;
  subtitle: string | null;
}): string {
  const { title } = opts;
  let heading: string;
  let description: string;
  if (title !== null) {
    heading = escapeHtml(title);
    description = opts.kind === "polls"
      ? `「${heading}」の投票にアプリから参加しよう`
      : `「${heading}」のセットリスト・出演情報をアプリでチェック`;
  } else {
    heading = {
      events: "イベントが見つかりません",
      shows: "公演が見つかりません",
      polls: "お題が見つかりません",
    }[opts.kind];
    description = "アイマス全ブランドのライブ・セットリストデータベース";
  }
  const subtitleHtml = opts.subtitle
    ? `<p class="sub">${escapeHtml(opts.subtitle)}</p>`
    : "";
  // アプリインストール済みで Universal Links が発火しなかった場合の救済リンク (custom scheme)。
  const schemeUrl = escapeHtml(
    `imaslivedb://${opts.kind}/${encodeURIComponent(opts.id)}`
  );
  return `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="apple-itunes-app" content="app-id=${APP_STORE_NUMERIC_ID}">
<meta property="og:title" content="${heading} | アイドルライブDB">
<meta property="og:description" content="${description}">
<meta property="og:type" content="website">
<title>${heading} | アイドルライブDB</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", sans-serif;
    margin: 0; padding: 32px 20px; text-align: center;
    background: #fafafa; color: #1a1a1a;
  }
  @media (prefers-color-scheme: dark) {
    body { background: #111; color: #eee; }
    .card { background: #1d1d1f !important; }
  }
  .card {
    max-width: 480px; margin: 0 auto; background: #fff;
    border-radius: 20px; padding: 32px 24px;
    box-shadow: 0 2px 16px rgba(0,0,0,.08);
  }
  h1 { font-size: 20px; line-height: 1.4; margin: 0 0 8px; }
  .sub { color: #888; font-size: 14px; margin: 0 0 4px; }
  .app { color: #888; font-size: 13px; margin: 20px 0 12px; }
  .btn {
    display: block; margin: 12px auto 0; max-width: 320px;
    padding: 14px 24px; border-radius: 14px; text-decoration: none;
    font-weight: 600; font-size: 16px;
  }
  .primary { background: #e91e63; color: #fff; }
  .secondary { color: #e91e63; }
</style>
</head>
<body>
  <div class="card">
    <h1>${heading}</h1>
    ${subtitleHtml}
    <p class="app">アイドルライブDB — アイマス全ブランドのライブ・セットリストデータベース</p>
    <a class="btn primary" href="${APP_STORE_URL}">App Store でダウンロード</a>
    <a class="btn secondary" href="${schemeUrl}">アプリで開く</a>
  </div>
</body>
</html>`;
}

/** AASA と着地ページ。どちらでもなければ null。 */
export async function handleAppLinks(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, requestId } = ctx;

  // ----------------------------------------------------------------
  // GET /.well-known/apple-app-site-association — Universal Links 定義
  //   Apple CDN 要件: リダイレクトなし・Content-Type: application/json。
  // ----------------------------------------------------------------
  if (path === "/.well-known/apple-app-site-association" && request.method === "GET") {
    return new Response(
      JSON.stringify({
        applinks: {
          details: [
            {
              appIDs: [APP_ID],
              // アプリが実際に処理できるパスだけに絞る (それ以外は素直にブラウザで開かせる)。
              components: [
                { "/": "/app/events/*" },
                { "/": "/app/shows/*" },
                { "/": "/app/polls/*" },
              ],
            },
          ],
        },
      }),
      {
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "public, max-age=3600",
          "X-Request-Id": requestId,
        },
      }
    );
  }

  // ----------------------------------------------------------------
  // GET /app/events/:id, /app/shows/:id, /app/polls/:id — Universal Links フォールバック
  //   アプリ未インストールのブラウザアクセスに App Store 誘導 HTML を返す。
  //   (インストール済み端末では iOS がアプリを直接開くため通常表示されない)
  // ----------------------------------------------------------------
  const appLinkMatch = path.match(/^\/app\/(events|shows|polls)\/([^/]+)$/);
  if (appLinkMatch && request.method === "GET") {
    const kind = appLinkMatch[1] as "events" | "shows" | "polls";
    let id: string;
    try {
      id = decodeURIComponent(appLinkMatch[2]);
    } catch {
      // 不正な percent-encoding (%G0 等) は URIError → 500 にせず 404 ページを返す。
      return new Response(
        renderAppFallbackPage({ kind, id: appLinkMatch[2], title: null, subtitle: null }),
        {
          status: 404,
          headers: {
            "Content-Type": "text/html; charset=utf-8",
            "X-Request-Id": requestId,
          },
        }
      );
    }
    // 名前は CloudKit (唯一の正) を S2S lookup で直読みする。recordName = id。
    // 旧実装は Worker D1 の master ミラーを読んでいたが、ミラーは CloudKit と
    // 同期されず古くなるため廃止。lookup 失敗時は title=null の graceful degrade。
    let title: string | null = null;
    let subtitle: string | null = null;
    try {
      if (kind === "polls") {
        // お題は CloudKit ではなく D1 (polls テーブル) が正。
        const poll = await env.DB.prepare(
          "SELECT title, description, ends_at FROM polls WHERE id = ? AND status = 'active'"
        )
          .bind(id)
          .first<{ title: string; description: string | null; ends_at: string }>();
        if (poll) {
          title = poll.title;
          subtitle = poll.description || null;
        }
      } else if (kind === "events") {
        const res = await cloudKitLookup([id], env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
        const fields = res.records?.get(id)?.fields;
        title = (fields?.name?.value as string | undefined) ?? null;
      } else {
        const res = await cloudKitLookup([id], env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
        const show = res.records?.get(id)?.fields;
        if (show) {
          const showName = (show.name?.value as string | undefined) ?? "";
          const date = (show.date?.value as string | undefined) ?? null;
          const venue = (show.venue?.value as string | undefined) ?? null;
          const eventId = show.eventId?.value as string | undefined;
          let eventName: string | null = null;
          if (eventId) {
            const evRes = await cloudKitLookup([eventId], env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
            eventName = (evRes.records?.get(eventId)?.fields?.name?.value as string | undefined) ?? null;
          }
          title = eventName && !showName.includes(eventName)
            ? `${eventName} ${showName}`
            : showName || null;
          subtitle = [date, venue].filter(Boolean).join(" ・ ") || null;
        }
      }
    } catch {
      // CloudKit 到達不可等 → title=null のまま誘導ページのみ返す。
      title = null;
    }
    return new Response(renderAppFallbackPage({ kind, id, title, subtitle }), {
      status: title !== null ? 200 : 404,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "X-Request-Id": requestId,
      },
    });
  }

  return null;
}
