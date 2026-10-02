// routes/music_token.ts — Apple Music のデベロッパトークンを Android へ配る (GET /music-token)。
//
// 認証は持たせない (端末に配る以上、正規アプリから取れるものは改造クライアントからも取れる)。
// 守るのは「取られたものが短命 (6 時間) で、鍵を回せば即座に止められる」ことの方。
// 濫用は IP 単位の枠で抑える。全員に同じトークンを返すので、エッジに短く載せる。

import { AppleMusicNotConfigured, signedAppleMusicToken } from "../apple_music_token";
import { commitIpRateLimit } from "../rate_limit";
import type { RouteContext } from "./context";
import { requireIpQuota } from "./guards";

export const MUSIC_TOKEN_IP_LIMITS = { perMinute: 20, perDay: 200 } as const;

export async function handleMusicToken(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error } = ctx;
  if (path !== "/music-token" || request.method !== "GET") return null;

  const quota = await requireIpQuota(ctx, "music_token", MUSIC_TOKEN_IP_LIMITS);
  if (quota instanceof Response) return quota;

  let signed: { token: string; expiresAt: number };
  try {
    signed = await signedAppleMusicToken(env);
  } catch (e) {
    // アプリは非 200 を「Apple Music に繋げない」と読む (試聴だけになる)。
    if (e instanceof AppleMusicNotConfigured) return error("apple music is not configured", 503);
    throw e;
  }
  await commitIpRateLimit(env.DB, quota);
  // 失効は秒で渡す (絶対時刻だと端末の時計のずれがそのまま誤差になる)。
  return json({ token: signed.token, expiresIn: signed.expiresAt - Math.floor(Date.now() / 1000) }, 200,
    { "Cache-Control": "public, max-age=60" });
}
