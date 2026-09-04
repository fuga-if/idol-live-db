// routes/song_detail.ts — 曲詳細を 1 リクエストに束ねる GET /songs/:song_id/detail。
//
// 目的: 曲詳細を 1 回開くたびに飛んでいた 3 リクエスト
//   (GET /penlight/votes/:id, GET /songs/:id/tags, GET /songs/:id/similar)
// を 1 本にまとめ、Worker 無料枠 (10万リクエスト/日) で捌ける同時利用者を 3 倍にする。
// 歌詞も同梱し、歌詞タブを常時読み込みにしてもリクエストが増えないようにする。
//
// ⚠️ ここには取得ロジックを書かない。tags / similar / penlight / lyrics の実装は
//    それぞれ routes/tags.ts, routes/device_aggregates.ts, routes/lyrics.ts の
//    export された関数が唯一の正で、このファイルはそれを呼んで束ねるだけ。
//    既存 3 エンドポイントは削除していない (段階移行のため両方生かす)。
//
// ⚠️ 応答の入れ子は「既存エンドポイントのレスポンスそのまま」。iOS が既存の
//    SongTagListResponse / SimilarSongsResponse / PenlightVoteResult を
//    そのまま使ってデコードできることが契約なので、キーの形を変えないこと。
//    (iOS の JSONDecoder は convertFromSnakeCase なので、入れ子の snake_case と
//     lyrics の camelCase はどちらも同じ camelCase プロパティに落ちる)
//
// ⚠️ エッジキャッシュとの関係 (index.ts と対で読むこと):
//    - Authorization 付きリクエストは index.ts の edgeCacheEligible が false になるため、
//      歌詞入りの応答がエッジキャッシュに載ることは構造的に起こらない。
//      **この性質に依存している。** index.ts:374 付近の条件を緩める変更をするときは、
//      歌詞が共有キャッシュに載らないことを必ず再確認すること
//      (JASRAC 許諾の「一括ダウンロードできない形式での配信」条件に関わる)。
//    - X-Device-Id 付きリクエストも同様に共有キャッシュを読み書きしない。
//      キャッシュキーが URL のみなので、my_tag_ids / my_vote が他人に配られてしまう。
//      これも index.ts 側の条件で担保している。

import { getAuthUser } from "../auth";
import { checkIsAdmin } from "../users";
import { dryCheckIpRateLimit, commitIpRateLimit } from "../rate_limit";
import { fetchPenlightVotes } from "./device_aggregates";
import { fetchPublishedLyrics, logLyricsRead, NO_STORE } from "./lyrics";
import {
  clampSimilarLimit,
  fetchSimilarSongs,
  fetchSongTagList,
  SIMILAR_CACHE_HEADERS,
} from "./tags";
import type { RouteContext } from "./context";

/** iOS の CommunityAPI.similarSongsByTags と同じ既定値 (候補を多めに取って端末側で抽選する)。 */
const DEFAULT_SIMILAR_LIMIT = 50;

/**
 * 端末非依存の応答 (my_tag_ids / my_vote を含まない) にだけ付けるキャッシュヘッダ。
 * タグ票数やペンライト集計は投票で動くので、similar (10分) より短めにしておく。
 */
const PUBLIC_CACHE_HEADERS: Record<string, string> = {
  "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
};

/** 端末固有データを含む応答。共有キャッシュにも端末にも残さない。 */
const PRIVATE_HEADERS: Record<string, string> = { "Cache-Control": "private, no-store" };

/**
 * 部分取得の失敗を全体の失敗にしない。
 * 1 つのタグ取得が転んだだけで曲詳細が丸ごと開けなくなるのを避けるため、
 * 失敗した部分だけ null にして 200 を返す。
 */
async function optional<T>(label: string, work: Promise<T>): Promise<T | null> {
  try {
    return await work;
  } catch (e) {
    console.error("song_detail_part_failed", {
      part: label,
      error: e instanceof Error ? { message: e.message, stack: e.stack } : String(e),
    });
    return null;
  }
}

/**
 * タグ類似曲をエッジキャッシュ経由で取得する。
 *
 * キャッシュキーには **GET /songs/:id/similar?limit=N と同じ URL** を使う。
 * 単体エンドポイントの応答 (index.ts が同じキーで保存する) とこの関数が作る応答は
 * 同じ関数・同じヘッダで組み立てられるので相互に再利用できる。
 *
 * これが無いと、X-Device-Id を送る実クライアント (= ほぼ全アプリ通信) が
 * バンドル経由になった瞬間、今までエッジで賄えていた重い類似クエリが
 * 毎回 D1 に落ちることになる。束ねたことで D1 の負荷が増えては本末転倒。
 */
async function fetchSimilarSongsCached(
  ctx: RouteContext,
  songId: string,
  limit: number
): Promise<{ song_id: string; songs: unknown[] }> {
  const key = new Request(
    `${ctx.url.origin}/songs/${encodeURIComponent(songId)}/similar?limit=${limit}`
  );
  const cached = await caches.default.match(key);
  if (cached) return await cached.json();

  const payload = await fetchSimilarSongs(ctx.env.DB, songId, limit);
  const storable = ctx.json(payload, 200, SIMILAR_CACHE_HEADERS);
  const put = caches.default.put(key, storable.clone());
  if (ctx.waitUntil) ctx.waitUntil(put);
  else await put;
  return payload;
}

/**
 * 歌詞を 1 曲ぶん取得する (呼び出し側で認証済みを確認してから使うこと)。
 *
 * レート制限は「束ねたことで実質的に厳しくなってはいけない」ため、既存 3 エンドポイントと
 * 同じく tags / similar / penlight には掛けない。歌詞を同梱するときだけ、単体の
 * GET /songs/:id/lyrics と同じ IP バースト制限 (30回/分) を掛ける。上限に当たっても
 * 429 で全体を落とさず lyrics だけ null にする (バンドルが単体 3 本より厳しくならないように)。
 */
async function loadLyrics(
  ctx: RouteContext,
  songId: string,
  isAdmin: boolean
): Promise<Awaited<ReturnType<typeof fetchPublishedLyrics>>> {
  const { request, env } = ctx;
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const ipRl = await dryCheckIpRateLimit(env.DB, ip);
  if (!ipRl.allowed) {
    console.log("song_detail_lyrics_rate_limited", { songId });
    return null;
  }
  // 未公開 (draft) は admin にだけ返す。許諾が下りるまでの開発プレビュー用。
  const lyrics = await fetchPublishedLyrics(env.DB, songId, isAdmin);
  // 単体エンドポイントと同じく、歌詞を実際に返したときだけ枠を消費し、利用ログを出す
  // (歌詞未投入の曲を開いただけでは枠も回数も動かない)。曲詳細から読んだ歌詞も
  // JASRAC 報告のリクエスト回数に入る — 読者にとっては同じ「歌詞を読んだ」なので、
  // 経路で数え方を変えない。
  if (lyrics) {
    await commitIpRateLimit(env.DB, ip, ipRl.bucket);
    logLyricsRead(songId);
  }
  return lyrics;
}

/**
 * GET /songs/:song_id/detail — 曲詳細に必要な集計をまとめて返す。
 * 一致しなければ null を返し、呼び出し元の if チェーンへ処理を戻す。
 */
export async function handleSongDetail(ctx: RouteContext): Promise<Response | null> {
  const { request, env, url, path, json, error } = ctx;

  const match = path.match(/^\/songs\/([^/]+)\/detail$/);
  if (!match || request.method !== "GET") return null;

  let songId: string;
  try {
    songId = decodeURIComponent(match[1]);
  } catch {
    return error("invalid song_id", 400);
  }

  const deviceId = request.headers.get("X-Device-Id");
  const similarLimit = clampSimilarLimit(
    url.searchParams.get("similar_limit"),
    DEFAULT_SIMILAR_LIMIT
  );

  // 認証は任意。付いていれば歌詞も同梱する (未認証は歌詞を返さない)。
  const user = await getAuthUser(request, env);
  // 未公開 (draft) の歌詞は admin にだけ見せる。JASRAC の許諾が下りるまで
  // 一般ユーザーには配信できないが、開発中のプレビューは必要なため。
  // ビルド種別では判定しない (クライアントの自己申告は信用できない)。
  const isAdmin = user ? await checkIsAdmin(env, user.uid) : false;

  const [tags, similar, penlight, lyrics] = await Promise.all([
    optional("tags", fetchSongTagList(env.DB, songId, deviceId)),
    optional("similar", fetchSimilarSongsCached(ctx, songId, similarLimit)),
    optional("penlight", fetchPenlightVotes(env.DB, songId, deviceId)),
    user ? optional("lyrics", loadLyrics(ctx, songId, isAdmin)) : Promise.resolve(null),
  ]);

  // Cache-Control の分岐 (ファイル冒頭のコメントと対):
  //   - 歌詞入り          → no-store (許諾条件。エッジ非対象は Authorization で構造的に担保)
  //   - 端末固有データ入り → private, no-store (my_* が共有キャッシュに載らないように)
  //   - どちらでもない    → 既存の集計 read と同じ公開キャッシュ
  const headers = user ? NO_STORE : deviceId ? PRIVATE_HEADERS : PUBLIC_CACHE_HEADERS;

  return json({ songId, tags, similar, penlight, lyrics }, 200, headers);
}
