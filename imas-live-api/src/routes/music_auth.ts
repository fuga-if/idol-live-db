// routes/music_auth.ts — Android で Apple Music にブラウザでサインインし、トークンを端末へ渡す。
//
//   POST /music-auth/start    … 端末が合言葉をもらう (X-Device-Id 必須)
//   GET  /music-auth?code=…   … ブラウザで開くサインインの面 (MusicKit JS)
//   POST /music-auth/deposit  … 面が取れたユーザートークンを預ける
//   GET  /music-auth/take     … 始めた端末だけが一度だけ取りに来る (渡したら消す)
//
// なぜブラウザか: Android の MusicKit SDK の認証は端末の Apple Music アプリのサインイン状態を
// 見るので、サインイン済みだと結果が返らない (FB24754184)。MusicKit JS ならそれに依存しない。
// 埋め込み WebView は Apple が弾くので、アプリは Custom Tabs (本物のブラウザ) で開く。
//
// トークンを URL で返さない (ブラウザの履歴・リファラに残る)。ここへ一度だけ預け、
// 始めた端末の ID と一致したときだけ一度だけ渡す。置いておくのは 10 分まで。
// イントロドンの intro-server/src/routes/music_auth.ts と同じ作り。

import { commitIpRateLimit } from "../rate_limit";
import type { RouteContext } from "./context";
import { requireIpQuota } from "./guards";

/** 受け渡しの寿命。取りに来なければ消える。 */
export const MUSIC_AUTH_TTL_MS = 10 * 60 * 1000;
/** 終わったあとアプリへ帰る合図 (トークンは載せない)。AndroidManifest の intent-filter と対。 */
const RETURN_URL = "imaslivedb://music-auth";
/** 預けてよいトークンの長さの蓋 (実測 200 文字前後)。 */
const MAX_TOKEN_LEN = 4096;
const MUSIC_AUTH_IP_LIMITS = { perMinute: 30, perDay: 300 } as const;

const isCode = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f-]{36}$/.test(v);
const isDevice = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= 200;

export async function handleMusicAuth(ctx: RouteContext): Promise<Response | null> {
  const { request, env, url, path, json, error } = ctx;
  if (!path.startsWith("/music-auth")) return null;

  if (path === "/music-auth" && request.method === "GET") {
    const code = url.searchParams.get("code");
    if (!isCode(code)) return error("code is required");
    return new Response(page(code), {
      headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
    });
  }

  const route = `${request.method} ${path}`;
  if (route !== "POST /music-auth/start" && route !== "POST /music-auth/deposit" && route !== "GET /music-auth/take") {
    return null;
  }
  const quota = await requireIpQuota(ctx, "music_auth", MUSIC_AUTH_IP_LIMITS);
  if (quota instanceof Response) return quota;

  if (route === "POST /music-auth/start") {
    const deviceId = request.headers.get("X-Device-Id");
    if (!isDevice(deviceId)) return error("X-Device-Id header is required");
    const code = crypto.randomUUID();
    await env.DB.prepare("INSERT INTO music_auth (code, device_id, token, created_at) VALUES (?, ?, NULL, ?)")
      .bind(code, deviceId, Date.now())
      .run();
    await commitIpRateLimit(env.DB, quota);
    return json({ code }, 200, { "Cache-Control": "no-store" });
  }

  if (route === "POST /music-auth/deposit") {
    // ブラウザから来る (端末 ID は付かない)。縛りは取る側に掛けてある。
    const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
    if (!body || !isCode(body.code)) return error("code is required");
    const token = body.token;
    if (typeof token !== "string" || !token || token.length > MAX_TOKEN_LEN) return error("token is invalid");
    const row = await env.DB.prepare("SELECT created_at FROM music_auth WHERE code = ?")
      .bind(body.code).first<{ created_at: number }>();
    // 無い合言葉には預けさせない (置き場を誰でも書ける場所にしない)。
    if (!row) return error("unknown code", 404);
    if (Date.now() - row.created_at > MUSIC_AUTH_TTL_MS) return error("code has expired", 410);
    // 同じトークンの預け直しは通す (応答の取りこぼし)。別のトークンでの上書きは拒む
    // (合言葉は URL に出るので、上書きできると他人のアカウントを掴ませられる)。
    const stored = await env.DB.prepare(
      "UPDATE music_auth SET token = ? WHERE code = ? AND (token IS NULL OR token = ?)"
    ).bind(token, body.code, token).run();
    if (stored.meta.changes === 0) return error("code already has a token", 409);
    await commitIpRateLimit(env.DB, quota);
    return json({ ok: true }, 200, { "Cache-Control": "no-store" });
  }

  // GET /music-auth/take
  const deviceId = request.headers.get("X-Device-Id");
  if (!isDevice(deviceId)) return error("X-Device-Id header is required");
  const code = url.searchParams.get("code");
  if (!isCode(code)) return error("code is required");
  const row = await env.DB.prepare("SELECT device_id, token, created_at FROM music_auth WHERE code = ?")
    .bind(code).first<{ device_id: string; token: string | null; created_at: number }>();
  // 始めた端末だけに渡す。
  if (!row || row.device_id !== deviceId) return error("unknown code", 404);
  if (Date.now() - row.created_at > MUSIC_AUTH_TTL_MS) {
    await env.DB.prepare("DELETE FROM music_auth WHERE code = ?").bind(code).run();
    return error("code has expired", 410);
  }
  await commitIpRateLimit(env.DB, quota);
  if (!row.token) return json({ ready: false }, 200, { "Cache-Control": "no-store" });
  await env.DB.prepare("DELETE FROM music_auth WHERE code = ?").bind(code).run();
  return json({ ready: true, token: row.token }, 200, { "Cache-Control": "no-store" });
}

/** サインインの面。MusicKit JS を読むだけの 1 枚。トークンは /music-token から取る。 */
function page(code: string): string {
  return `<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Apple Music に接続</title>
<style>
  :root { color-scheme: light dark; --bg: #F4F0E8; --ink: #1B1822; --ink2: #6B6478; --on: #F6F1E7; }
  @media (prefers-color-scheme: dark) { :root { --bg: #15131C; --ink: #F6F1E7; --ink2: #A7A1B5; --on: #1B1822; } }
  body { margin: 0; background: var(--bg); color: var(--ink);
         font-family: -apple-system, "Hiragino Kaku Gothic ProN", "Noto Sans JP", system-ui, sans-serif;
         display: grid; place-items: center; min-height: 100dvh; padding: 24px; box-sizing: border-box; }
  main { max-width: 22rem; width: 100%; }
  h1 { font-size: 1.25rem; margin: 0 0 0.75rem; }
  p { margin: 0 0 1.25rem; line-height: 1.7; color: var(--ink2); font-size: 0.95rem; }
  button { font: inherit; font-weight: 700; padding: 0.9rem 1.5rem; width: 100%;
           border: 0; border-radius: 12px; background: var(--ink); color: var(--on); }
  button[disabled] { opacity: 0.5; }
  a { color: var(--ink); }
</style>
</head>
<body>
<main>
  <h1>Apple Music に接続</h1>
  <p id="lead">サインインすると、アイドルライブDB で曲をフル尺で鳴らし、歌詞を再生に合わせて追いかけられます。</p>
  <button id="go">サインインする</button>
  <p id="note"></p>
  <p><a id="back" href="${RETURN_URL}" hidden>アプリに戻る</a></p>
</main>
<script src="https://js-cdn.music.apple.com/musickit/v3/musickit.js" data-web-components async></script>
<script>
  const code = ${JSON.stringify(code)};
  const lead = document.getElementById("lead"), note = document.getElementById("note");
  const go = document.getElementById("go"), back = document.getElementById("back");
  const fail = (m) => { go.disabled = false; note.textContent = m; };
  go.addEventListener("click", async () => {
    go.disabled = true; note.textContent = "";
    try {
      if (typeof MusicKit === "undefined") return fail("読み込み中です。少し待ってからお試しください。");
      const res = await fetch("/music-token");
      if (!res.ok) return fail("いま接続できません。しばらくしてからお試しください。");
      const { token } = await res.json();
      await MusicKit.configure({ developerToken: token, app: { name: "アイドルライブDB", build: "1" } });
      const userToken = await MusicKit.getInstance().authorize();
      if (!userToken) throw new Error("no user token");
      const put = await fetch("/music-auth/deposit", { method: "POST",
        headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code, token: userToken }) });
      if (!put.ok) throw new Error("deposit");
    } catch (e) {
      return fail("接続できませんでした。もう一度お試しください。");
    }
    // 預けたあとは失敗させない (合言葉は使用済み)。押せる場所を出してから自動で帰す。
    lead.textContent = "接続しました。アプリに戻ります。";
    go.remove(); back.hidden = false;
    location.replace(${JSON.stringify(RETURN_URL)});
  });
</script>
</body>
</html>`;
}
