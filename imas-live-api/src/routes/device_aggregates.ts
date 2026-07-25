// routes/device_aggregates.ts — device 単位の集計 API (お気に入り / ペンライト色)
//
// index.ts の巨大な if チェーンから最初に切り出したルート群。この 2 系統を選んだのは
//   - 認証不要 (X-Device-Id のみ)
//   - 他のルートと状態を共有しない
//   - CloudKit ではなく D1 で完結する
// ため、切り出しの影響範囲が閉じているから。
//
// ⚠️ ルート本文は index.ts から移動しただけで、SQL もレスポンス JSON のキーも
//    ステータスコードも変えていない。審査済みリリース版が本番のこの API を叩いている。

import { dryCheckIpRateLimit, commitIpRateLimit } from "../rate_limit";
import { parsePositiveInt, validateOpaqueKey } from "../validation";
import type { RouteContext } from "./context";


/**
 * 書き込み系の共通ガード: X-Device-Id 必須 → IP レート制限の dry check。
 *
 * 元は各ルートに同じ 8 行がコピーされており、1 箇所で書き忘れるとそのルートだけ
 * 無防備になる形だった。判定の順序・エラー文言・ステータスは元のまま。
 * 実際の +1 コミットは成功直前に commitIpRateLimit(env.DB, ip, bucket) を呼ぶ。
 */
async function guardWrite(
  ctx: RouteContext
): Promise<{ deviceId: string; ip: string; bucket: number } | Response> {
  const { request, env, error, rateLimitSimple } = ctx;

  const deviceId = request.headers.get("X-Device-Id");
  if (!deviceId) return error("X-Device-Id header is required");

  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const ipDry = await dryCheckIpRateLimit(env.DB, ip);
  if (!ipDry.allowed) {
    return rateLimitSimple();
  }

  return { deviceId, ip, bucket: ipDry.bucket };
}

/**
 * /favorites/* と /penlight/* を処理する。
 * どのルートにも一致しなければ `null` を返し、呼び出し元の if チェーンへ処理を戻す。
 */
export async function handleDeviceAggregates(ctx: RouteContext): Promise<Response | null> {
  const { request, env, url, path, json, error } = ctx;

    // ----------------------------------------------------------------
    // POST /favorites/toggle — お気に入り登録/解除
    // ----------------------------------------------------------------
    if (path === "/favorites/toggle" && request.method === "POST") {
      const guard = await guardWrite(ctx);
      if (guard instanceof Response) return guard;
      const { deviceId, ip, bucket } = guard;

      // 不正な JSON は catch-all に落として 500 にせず 400 で返す
      // (クライアントのバグがサーバ障害として観測されるのを防ぐ)。
      // JSON として妥当な非オブジェクト (数値・文字列) は従来どおり
      // 後段のフィールド検証に流し、エラー文言を変えない。
      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const { song_id, value } = body;
      const favSongIdErr = validateOpaqueKey(song_id, "song_id");
      if (favSongIdErr) return error(favSongIdErr);
      if (typeof value !== "boolean") return error("value must be boolean");

      if (value) {
        // お気に入り追加: device upsert + count++ を batch
        const insertDevice = env.DB.prepare(
          `INSERT OR IGNORE INTO device_song_favorite (device_id, song_id, created_at) VALUES (?, ?, ?)`
        ).bind(deviceId, song_id, Math.floor(Date.now() / 1000));
        const upsertCount = env.DB.prepare(
          `INSERT INTO song_favorites (song_id, count) VALUES (?, 1)
           ON CONFLICT(song_id) DO UPDATE SET count = count + 1`
        ).bind(song_id);
        await env.DB.batch([insertDevice, upsertCount]);
      } else {
        // お気に入り解除: device delete + count-- を batch (count は MAX(0,...) で防御)
        const deleteDevice = env.DB.prepare(
          "DELETE FROM device_song_favorite WHERE device_id = ? AND song_id = ?"
        ).bind(deviceId, song_id);
        const decrementCount = env.DB.prepare(
          `UPDATE song_favorites SET count = MAX(0, count - 1) WHERE song_id = ?`
        ).bind(song_id);
        await env.DB.batch([deleteDevice, decrementCount]);
      }

      const row = await env.DB.prepare(
        "SELECT count FROM song_favorites WHERE song_id = ?"
      )
        .bind(song_id)
        .first<{ count: number }>();

      await commitIpRateLimit(env.DB, ip, bucket);
      return json({ song_id, count: row?.count ?? 0 });
    }

    // ----------------------------------------------------------------
    // GET /favorites/ranking — お気に入りランキング
    // ----------------------------------------------------------------
    if (path === "/favorites/ranking" && request.method === "GET") {
      // コミュニティ集計 (song_id, count) のみ返す。曲名・ブランド・ジャケ写は返さない。
      // D1 の songs はコードから書かれない陳腐化ミラーで、新曲が JOIN で脱落する/
      // s.artist カラムが存在せずクエリ自体が壊れるため、ミラー依存を撤去した。
      // ブランド絞り込みと曲メタ解決は iOS local カタログ側で行う (予想機能と同方針)。
      const limit = parsePositiveInt(url.searchParams.get("limit"), 200, 1000);

      const { results } = await env.DB.prepare(
        `SELECT song_id, count FROM song_favorites
         ORDER BY count DESC LIMIT ?`
      )
        .bind(limit)
        .all();
      // ランキングはコミュニティ集計 (song_id, count) のみでユーザー非依存。
      // 画面を開くたびに叩かれるが順位変動は緩やかなので、エッジで全ユーザ共有
      // キャッシュ (max-age 60s + SWR 300s)。集計なので多少の鮮度落ちは許容。
      return json(results, 200, {
        "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
      });
    }

    // ----------------------------------------------------------------
    // GET /penlight/palette — パレット一覧
    // ----------------------------------------------------------------
    if (path === "/penlight/palette" && request.method === "GET") {
      const { results } = await env.DB.prepare(
        "SELECT * FROM penlight_palette ORDER BY sort_order"
      ).all();
      return json(results);
    }

    // ----------------------------------------------------------------
    // POST /penlight/vote — ペンライト色セット投票
    // ----------------------------------------------------------------
    if (path === "/penlight/vote" && request.method === "POST") {
      const guard = await guardWrite(ctx);
      if (guard instanceof Response) return guard;
      const { deviceId, ip, bucket } = guard;

      // 不正な JSON は catch-all に落として 500 にせず 400 で返す
      // (クライアントのバグがサーバ障害として観測されるのを防ぐ)。
      // JSON として妥当な非オブジェクト (数値・文字列) は従来どおり
      // 後段のフィールド検証に流し、エラー文言を変えない。
      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const { song_id, colors } = body;
      const penlightSongIdErr = validateOpaqueKey(song_id, "song_id");
      if (penlightSongIdErr) return error(penlightSongIdErr);
      if (!Array.isArray(colors) || colors.length === 0) return error("colors must be a non-empty array");

      const colorSetKey = [...colors].sort().join("-");

      // 既存投票を確認して差し替え
      const existing = await env.DB.prepare(
        "SELECT color_set_key FROM device_song_penlight WHERE device_id = ? AND song_id = ?"
      )
        .bind(deviceId, song_id)
        .first<{ color_set_key: string }>();

      const stmts: D1PreparedStatement[] = [];

      if (existing && existing.color_set_key !== colorSetKey) {
        // 旧セットを -1 (MAX(0,...) で防御) + 0以下なら削除
        stmts.push(
          env.DB.prepare(
            `UPDATE penlight_color_set_votes SET count = MAX(0, count - 1)
             WHERE song_id = ? AND color_set_key = ?`
          ).bind(song_id, existing.color_set_key),
          env.DB.prepare(
            `DELETE FROM penlight_color_set_votes WHERE song_id = ? AND color_set_key = ? AND count <= 0`
          ).bind(song_id, existing.color_set_key)
        );
      }

      if (!existing || existing.color_set_key !== colorSetKey) {
        // 新セットを +1
        stmts.push(
          env.DB.prepare(
            `INSERT INTO penlight_color_set_votes (song_id, color_set_key, count) VALUES (?, ?, 1)
             ON CONFLICT(song_id, color_set_key) DO UPDATE SET count = count + 1`
          ).bind(song_id, colorSetKey)
        );
      }

      // 端末投票レコードをupsert
      stmts.push(
        env.DB.prepare(
          `INSERT INTO device_song_penlight (device_id, song_id, color_set_key, created_at)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(device_id, song_id) DO UPDATE SET color_set_key = excluded.color_set_key, created_at = excluded.created_at`
        ).bind(deviceId, song_id, colorSetKey, Math.floor(Date.now() / 1000))
      );

      if (stmts.length > 0) await env.DB.batch(stmts);

      const row = await env.DB.prepare(
        "SELECT count FROM penlight_color_set_votes WHERE song_id = ? AND color_set_key = ?"
      )
        .bind(song_id, colorSetKey)
        .first<{ count: number }>();

      await commitIpRateLimit(env.DB, ip, bucket);
      return json({ song_id, color_set_key: colorSetKey, count: row?.count ?? 1 });
    }

    // ----------------------------------------------------------------
    // DELETE /penlight/vote — 投票取消
    // ----------------------------------------------------------------
    if (path === "/penlight/vote" && request.method === "DELETE") {
      const guard = await guardWrite(ctx);
      if (guard instanceof Response) return guard;
      const { deviceId, ip, bucket } = guard;

      const songId = url.searchParams.get("song_id");
      if (!songId) return error("song_id is required");

      const existing = await env.DB.prepare(
        "SELECT color_set_key FROM device_song_penlight WHERE device_id = ? AND song_id = ?"
      )
        .bind(deviceId, songId)
        .first<{ color_set_key: string }>();

      if (!existing) return json({ song_id: songId, cancelled: false });

      // count-1 / 0以下で DELETE / device削除 を batch で原子化
      await env.DB.batch([
        env.DB.prepare(
          `UPDATE penlight_color_set_votes SET count = MAX(0, count - 1)
           WHERE song_id = ? AND color_set_key = ?`
        ).bind(songId, existing.color_set_key),
        env.DB.prepare(
          `DELETE FROM penlight_color_set_votes WHERE song_id = ? AND color_set_key = ? AND count <= 0`
        ).bind(songId, existing.color_set_key),
        env.DB.prepare(
          "DELETE FROM device_song_penlight WHERE device_id = ? AND song_id = ?"
        ).bind(deviceId, songId),
      ]);

      await commitIpRateLimit(env.DB, ip, bucket);
      return json({ song_id: songId, cancelled: true });
    }

    // ----------------------------------------------------------------
    // GET /penlight/votes/:song_id — 投票結果
    // ----------------------------------------------------------------
    const penlightVotesMatch = path.match(/^\/penlight\/votes\/([^/]+)$/);
    if (penlightVotesMatch && request.method === "GET") {
      const songId = decodeURIComponent(penlightVotesMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");

      const { results: topSets } = await env.DB.prepare(
        `SELECT color_set_key, count FROM penlight_color_set_votes
         WHERE song_id = ? ORDER BY count DESC LIMIT 5`
      )
        .bind(songId)
        .all<{ color_set_key: string; count: number }>();

      const totalRow = await env.DB.prepare(
        `SELECT SUM(count) as total FROM penlight_color_set_votes WHERE song_id = ?`
      )
        .bind(songId)
        .first<{ total: number }>();

      let myVote: { color_set_key: string; colors: string[] } | null = null;
      if (deviceId) {
        const myRow = await env.DB.prepare(
          "SELECT color_set_key FROM device_song_penlight WHERE device_id = ? AND song_id = ?"
        )
          .bind(deviceId, songId)
          .first<{ color_set_key: string }>();
        if (myRow) {
          myVote = {
            color_set_key: myRow.color_set_key,
            colors: myRow.color_set_key.split("-"),
          };
        }
      }

      const top_sets = topSets.map((row) => ({
        key: row.color_set_key,
        colors: row.color_set_key.split("-"),
        count: row.count,
      }));

      return json({
        top_sets,
        total_votes: totalRow?.total ?? 0,
        my_vote: myVote,
      });
    }

  return null;
}
