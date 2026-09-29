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

import { commitIpRateLimit } from "../rate_limit";
import { parsePositiveInt } from "../validation";
import type { RouteContext } from "./context";
import { decodePathParam, readJsonBody, requireDeviceWrite, requireOpaqueKey } from "./guards";


/**
 * GET /penlight/votes/:song_id の本体。
 *
 * ⚠️ 曲詳細バンドル (routes/song_detail.ts) と共有する唯一の実装。
 *    SQL もレスポンスのキーもここ以外に書かないこと。
 *    deviceId が無ければ my_vote は null (= 端末非依存の集計だけになる)。
 */
export async function fetchPenlightVotes(
  db: D1Database,
  songId: string,
  deviceId: string | null
): Promise<{
  top_sets: Array<{ key: string; colors: string[]; count: number }>;
  total_votes: number;
  my_vote: { color_set_key: string; colors: string[] } | null;
}> {
  const { results: topSets } = await db
    .prepare(
      `SELECT color_set_key, count FROM penlight_color_set_votes
         WHERE song_id = ? ORDER BY count DESC LIMIT 5`
    )
    .bind(songId)
    .all<{ color_set_key: string; count: number }>();

  const totalRow = await db
    .prepare(`SELECT SUM(count) as total FROM penlight_color_set_votes WHERE song_id = ?`)
    .bind(songId)
    .first<{ total: number }>();

  let myVote: { color_set_key: string; colors: string[] } | null = null;
  if (deviceId) {
    const myRow = await db
      .prepare("SELECT color_set_key FROM device_song_penlight WHERE device_id = ? AND song_id = ?")
      .bind(deviceId, songId)
      .first<{ color_set_key: string }>();
    if (myRow) {
      myVote = {
        color_set_key: myRow.color_set_key,
        colors: myRow.color_set_key.split("-"),
      };
    }
  }

  return {
    top_sets: topSets.map((row) => ({
      key: row.color_set_key,
      colors: row.color_set_key.split("-"),
      count: row.count,
    })),
    total_votes: totalRow?.total ?? 0,
    my_vote: myVote,
  };
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
      const guard = await requireDeviceWrite(ctx);
      if (guard instanceof Response) return guard;
      const { deviceId, ipQuota } = guard;

      const body = await readJsonBody(ctx);
      if (body instanceof Response) return body;
      const song_id = requireOpaqueKey(ctx, body.song_id, "song_id");
      if (song_id instanceof Response) return song_id;
      const { value } = body;
      if (typeof value !== "boolean") return error("value must be boolean");

      // 数は端末の行が実際に変わったとき (直前の文の changes() > 0) だけ動かす。
      // 同じ端末の再送や、登録していない端末の解除では動かない。
      if (value) {
        // お気に入り追加: device upsert + count++ を batch
        const insertDevice = env.DB.prepare(
          `INSERT OR IGNORE INTO device_song_favorite (device_id, song_id, created_at) VALUES (?, ?, ?)`
        ).bind(deviceId, song_id, Math.floor(Date.now() / 1000));
        const upsertCount = env.DB.prepare(
          `INSERT INTO song_favorites (song_id, count) SELECT ?, 1 WHERE changes() > 0
           ON CONFLICT(song_id) DO UPDATE SET count = count + 1`
        ).bind(song_id);
        await env.DB.batch([insertDevice, upsertCount]);
      } else {
        // お気に入り解除: device delete + count-- を batch (count は MAX(0,...) で防御)
        const deleteDevice = env.DB.prepare(
          "DELETE FROM device_song_favorite WHERE device_id = ? AND song_id = ?"
        ).bind(deviceId, song_id);
        const decrementCount = env.DB.prepare(
          `UPDATE song_favorites SET count = MAX(0, count - 1) WHERE song_id = ? AND changes() > 0`
        ).bind(song_id);
        await env.DB.batch([deleteDevice, decrementCount]);
      }

      const row = await env.DB.prepare(
        "SELECT count FROM song_favorites WHERE song_id = ?"
      )
        .bind(song_id)
        .first<{ count: number }>();

      await commitIpRateLimit(env.DB, ipQuota);
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
      const guard = await requireDeviceWrite(ctx);
      if (guard instanceof Response) return guard;
      const { deviceId, ipQuota } = guard;

      const body = await readJsonBody(ctx);
      if (body instanceof Response) return body;
      const song_id = requireOpaqueKey(ctx, body.song_id, "song_id");
      if (song_id instanceof Response) return song_id;
      const { colors } = body;
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

      await commitIpRateLimit(env.DB, ipQuota);
      return json({ song_id, color_set_key: colorSetKey, count: row?.count ?? 1 });
    }

    // ----------------------------------------------------------------
    // DELETE /penlight/vote — 投票取消
    // ----------------------------------------------------------------
    if (path === "/penlight/vote" && request.method === "DELETE") {
      const guard = await requireDeviceWrite(ctx);
      if (guard instanceof Response) return guard;
      const { deviceId, ipQuota } = guard;

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

      await commitIpRateLimit(env.DB, ipQuota);
      return json({ song_id: songId, cancelled: true });
    }

    // ----------------------------------------------------------------
    // GET /penlight/votes/:song_id — 投票結果
    // ----------------------------------------------------------------
    const penlightVotesMatch = path.match(/^\/penlight\/votes\/([^/]+)$/);
    if (penlightVotesMatch && request.method === "GET") {
      const songId = decodePathParam(ctx, penlightVotesMatch[1], "song_id");
      if (songId instanceof Response) return songId;
      const deviceId = request.headers.get("X-Device-Id");
      return json(await fetchPenlightVotes(env.DB, songId, deviceId));
    }

  return null;
}
