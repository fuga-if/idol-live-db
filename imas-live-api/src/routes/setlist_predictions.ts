// routes/setlist_predictions.ts — 予想セトリ / 出演者予想 / セトリいいね
//
// index.ts から切り出した 4 つめのルート群。show 単位のコミュニティ集計で、
// マスタ (CloudKit) には無いデータを D1 に持つ。
//
// 曲・アイドルの実在チェックはしない。song_id / idol_id は不透明キーとして扱い、
// メタは iOS 側のローカルカタログが解決する (CloudKit にあるが D1 に未同期の
// 新曲でも投票できるようにするため)。
//
// ⚠️ ルート本文は移動しただけで、SQL もレスポンス JSON のキーも
//    ステータスコードも Cache-Control も変えていない
//    (そのあと Q-10 で、一覧の first_voted_by の値を先頭 8 文字にした。キーは残す)。

import { getAuthUser } from "../auth";
import { maskUserRef } from "../masking";
import { checkRateLimit, VOTE_LIMIT } from "../rate_limit";
import { upsertUser } from "../users";
import { validateOpaqueKey } from "../validation";
import type { RouteContext } from "./context";
import { decodePathParam, readJsonBody, requireActiveUser, requireOpaqueKey } from "./guards";

/**
 * /me/predictions, /shows/:showId/predictions,
 * /shows/:showId/songs/:songId/performers, /shows/:showId/likes,
 * /shows/:showId/songs/:songId/like を処理する。
 * どのルートにも一致しなければ `null` を返し、呼び出し元の if チェーンへ処理を戻す。
 */
export async function handleSetlistPredictions(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;

    // ================================================================
    // 予想セトリ API
    // ================================================================

    // ----------------------------------------------------------------
    // GET /me/predictions — 自分が投票した予想一覧 (auth必須)
    // ----------------------------------------------------------------
    // 曲メタ・公演メタは返さず show_id/song_id のみ。iOS が local カタログで解決する
    // (D1 songs ミラー非依存)。
    if (path === "/me/predictions" && request.method === "GET") {
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);
      const { results } = await env.DB.prepare(`
        SELECT spv.show_id, spv.song_id, sp.vote_count, spv.voted_at
        FROM setlist_prediction_votes spv
        LEFT JOIN setlist_predictions sp
          ON sp.show_id = spv.show_id AND sp.song_id = spv.song_id
        WHERE spv.user_id = ?
        ORDER BY spv.voted_at DESC
        LIMIT 200
      `).bind(user.uid).all();
      return json(results.map((r: any) => ({ ...r, vote_count: r.vote_count ?? 1 })));
    }

    // ----------------------------------------------------------------
    // GET /shows/:showId/predictions — 予想一覧 (auth optional)
    // ----------------------------------------------------------------
    // 公演単位の予想に統一 (旧 event-level 予想は 2026-05-28 クリーンスタートで全削除)
    const predictionsGetMatch = path.match(/^\/shows\/([^/]+)\/predictions$/);
    if (predictionsGetMatch && request.method === "GET") {
      const showId = decodePathParam(ctx, predictionsGetMatch[1], "show_id");
      if (showId instanceof Response) return showId;
      const authUser = await getAuthUser(request, env);
      const uid = authUser?.uid ?? "";

      // 曲メタデータ (title/artwork 等) は返さない。song_id はカタログ非依存の不透明キーとして扱い、
      // 曲名・ジャケ写は iOS が local カタログ (CloudKit が正) から解決する。
      // D1 に songs ミラーを持たせて JOIN すると、新曲追加のたびにズレて取りこぼすため。
      const { results } = await env.DB.prepare(`
        SELECT
          sp.show_id,
          sp.song_id,
          sp.vote_count,
          sp.first_voted_by,
          sp.first_voted_at,
          CASE WHEN spv.user_id IS NOT NULL THEN 1 ELSE 0 END as has_user_voted
        FROM setlist_predictions sp
        LEFT JOIN setlist_prediction_votes spv
          ON spv.show_id = sp.show_id
          AND spv.song_id = sp.song_id
          AND spv.user_id = ?
        WHERE sp.show_id = ?
        ORDER BY sp.vote_count DESC, sp.first_voted_at ASC
      `)
        .bind(uid, showId)
        .all();

      return json(
        results.map((r: any) => ({
          ...r,
          // 最初に入れた人 (uid) は先頭 8 文字だけ返す (タグの履歴の edited_by と同じ)。
          first_voted_by: maskUserRef(r.first_voted_by),
          has_user_voted: r.has_user_voted === 1,
        }))
      );
    }

    // ----------------------------------------------------------------
    // POST /shows/:showId/predictions — 投票 (auth必須)
    // ----------------------------------------------------------------
    const predictionsPostMatch = path.match(/^\/shows\/([^/]+)\/predictions$/);
    if (predictionsPostMatch && request.method === "POST") {
      const showId = decodePathParam(ctx, predictionsPostMatch[1], "show_id");
      if (showId instanceof Response) return showId;
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      const [inactive, rl] = await Promise.all([
        requireActiveUser(ctx, user),
        checkRateLimit(env.DB, user.uid, "prediction"),
      ]);
      if (inactive) return inactive;
      if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

      await upsertUser(env, user.uid);

      const body = await readJsonBody(ctx);
      if (body instanceof Response) return body;
      const song_id = requireOpaqueKey(ctx, body.song_id, "song_id");
      if (song_id instanceof Response) return song_id;

      // 曲存在チェックは行わない。song_id は不透明キーとして保存し、曲メタは iOS local が解決する。
      // (D1 songs ミラーで検証すると、CloudKit にあるが D1 に未同期の新曲が 404 になる)

      // 「この曲に投票済みか」と「この公演で何票使ったか」は同じ行集合から判るので、
      // D1 は 1 クエリで済ませる (投票 POST ごとのクエリ数を増やさない)。
      const { results: myVotes } = await env.DB.prepare(
        "SELECT song_id FROM setlist_prediction_votes WHERE show_id = ? AND user_id = ?"
      )
        .bind(showId, user.uid)
        .all<{ song_id: string }>();
      const myVoteCount = myVotes.length;
      const existingVote = myVotes.some((v) => v.song_id === song_id);

      if (existingVote) {
        const current = await env.DB.prepare(
          "SELECT vote_count FROM setlist_predictions WHERE show_id = ? AND song_id = ?"
        )
          .bind(showId, song_id)
          .first<{ vote_count: number }>();
        return json({
          song_id,
          vote_count: current?.vote_count ?? 1,
          already_voted: true,
          my_vote_count: myVoteCount,
        });
      }

      // 1公演あたり 1人 3票まで (poll_votes と同じ上限)。
      // 上限導入前に3票超で投票済みのユーザーは、取り消して3以下に戻すまで新規投票のみ弾かれる。
      if (myVoteCount >= VOTE_LIMIT) {
        return error("vote limit", 409);
      }

      await env.DB.prepare(
        `INSERT INTO setlist_prediction_votes (show_id, song_id, user_id, voted_at)
         VALUES (?, ?, ?, datetime('now'))`
      )
        .bind(showId, song_id, user.uid)
        .run();

      const existing = await env.DB.prepare(
        "SELECT vote_count FROM setlist_predictions WHERE show_id = ? AND song_id = ?"
      )
        .bind(showId, song_id)
        .first<{ vote_count: number }>();

      let voteCount: number;
      if (existing) {
        voteCount = (existing.vote_count ?? 0) + 1;
        await env.DB.prepare(
          "UPDATE setlist_predictions SET vote_count = ? WHERE show_id = ? AND song_id = ?"
        )
          .bind(voteCount, showId, song_id)
          .run();
      } else {
        voteCount = 1;
        await env.DB.prepare(
          `INSERT INTO setlist_predictions (show_id, song_id, vote_count, first_voted_by, first_voted_at)
           VALUES (?, ?, 1, ?, datetime('now'))`
        )
          .bind(showId, song_id, user.uid)
          .run();
      }

      return json(
        { song_id, vote_count: voteCount, already_voted: false, my_vote_count: myVoteCount + 1 },
        201
      );
    }

    // ----------------------------------------------------------------
    // DELETE /shows/:showId/predictions/:songId — 投票取消 (auth必須)
    // ----------------------------------------------------------------
    const predictionDeleteMatch = path.match(/^\/shows\/([^/]+)\/predictions\/([^/]+)$/);
    if (predictionDeleteMatch && request.method === "DELETE") {
      const showId = decodePathParam(ctx, predictionDeleteMatch[1], "show_id");
      if (showId instanceof Response) return showId;
      const songId = decodePathParam(ctx, predictionDeleteMatch[2], "song_id");
      if (songId instanceof Response) return songId;
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      const vote = await env.DB.prepare(
        "SELECT 1 FROM setlist_prediction_votes WHERE show_id = ? AND song_id = ? AND user_id = ?"
      )
        .bind(showId, songId, user.uid)
        .first();

      if (!vote) {
        return json({ song_id: songId, vote_count: 0, not_voted: true });
      }

      await env.DB.prepare(
        "DELETE FROM setlist_prediction_votes WHERE show_id = ? AND song_id = ? AND user_id = ?"
      )
        .bind(showId, songId, user.uid)
        .run();

      const current = await env.DB.prepare(
        "SELECT vote_count FROM setlist_predictions WHERE show_id = ? AND song_id = ?"
      )
        .bind(showId, songId)
        .first<{ vote_count: number }>();

      const newCount = (current?.vote_count ?? 1) - 1;

      if (newCount <= 0) {
        await env.DB.prepare(
          "DELETE FROM setlist_predictions WHERE show_id = ? AND song_id = ?"
        )
          .bind(showId, songId)
          .run();
      } else {
        await env.DB.prepare(
          "UPDATE setlist_predictions SET vote_count = ? WHERE show_id = ? AND song_id = ?"
        )
          .bind(newCount, showId, songId)
          .run();
      }

      return json({ song_id: songId, vote_count: Math.max(0, newCount) });
    }

    // ----------------------------------------------------------------
    // GET /shows/:showId/songs/:songId/performers — 出演者予想一覧 (auth optional)
    // ----------------------------------------------------------------
    // idol_id は不透明キー。名前/色の解決は iOS ローカル DB が担う (D1 join なし)。
    // has_user_voted を含む user 固有データなので Cache-Control は付けない。
    const performersGetMatch = path.match(/^\/shows\/([^/]+)\/songs\/([^/]+)\/performers$/);
    if (performersGetMatch && request.method === "GET") {
      const showId = decodePathParam(ctx, performersGetMatch[1], "show_id");
      if (showId instanceof Response) return showId;
      const songId = decodePathParam(ctx, performersGetMatch[2], "song_id");
      if (songId instanceof Response) return songId;
      const authUser = await getAuthUser(request, env);
      const uid = authUser?.uid ?? "";

      const { results } = await env.DB.prepare(`
        SELECT
          spp.show_id,
          spp.song_id,
          spp.idol_id,
          spp.vote_count,
          spp.first_voted_by,
          spp.first_voted_at,
          CASE WHEN sppv.user_id IS NOT NULL THEN 1 ELSE 0 END as has_user_voted
        FROM setlist_performer_predictions spp
        LEFT JOIN setlist_performer_prediction_votes sppv
          ON sppv.show_id = spp.show_id
          AND sppv.song_id = spp.song_id
          AND sppv.idol_id = spp.idol_id
          AND sppv.user_id = ?
        WHERE spp.show_id = ? AND spp.song_id = ?
        ORDER BY spp.vote_count DESC, spp.first_voted_at ASC
      `)
        .bind(uid, showId, songId)
        .all();

      return json(
        results.map((r: any) => ({
          ...r,
          // 最初に入れた人 (uid) は先頭 8 文字だけ返す (タグの履歴の edited_by と同じ)。
          first_voted_by: maskUserRef(r.first_voted_by),
          has_user_voted: r.has_user_voted === 1,
        }))
      );
    }

    // ----------------------------------------------------------------
    // POST /shows/:showId/songs/:songId/performers — 出演者予想投票 (auth必須)
    // ----------------------------------------------------------------
    // 1曲あたり同一 user の投票上限は 8 人 (ユニット曲・全体曲対応のため複数選択許可)。
    const performersPostMatch = path.match(/^\/shows\/([^/]+)\/songs\/([^/]+)\/performers$/);
    if (performersPostMatch && request.method === "POST") {
      const showId = decodePathParam(ctx, performersPostMatch[1], "show_id");
      if (showId instanceof Response) return showId;
      const songId = decodePathParam(ctx, performersPostMatch[2], "song_id");
      if (songId instanceof Response) return songId;
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      const inactive = await requireActiveUser(ctx, user);
      if (inactive) return inactive;

      const body = await readJsonBody(ctx);
      if (body instanceof Response) return body;
      const idol_id = requireOpaqueKey(ctx, body.idol_id, "idol_id");
      if (idol_id instanceof Response) return idol_id;

      // idol_id は不透明キーとして保存 — 実在検証は行わない (既存 setlist 予想と同方針)。

      // 冪等チェック: 既に投票済みなら集計を増やさず・レートも消費せず即返す。
      const existingVote = await env.DB.prepare(
        "SELECT 1 FROM setlist_performer_prediction_votes WHERE show_id = ? AND song_id = ? AND idol_id = ? AND user_id = ?"
      )
        .bind(showId, songId, idol_id, user.uid)
        .first();

      if (existingVote) {
        const current = await env.DB.prepare(
          "SELECT vote_count FROM setlist_performer_predictions WHERE show_id = ? AND song_id = ? AND idol_id = ?"
        )
          .bind(showId, songId, idol_id)
          .first<{ vote_count: number }>();
        return json({ idol_id, vote_count: current?.vote_count ?? 1, already_voted: true });
      }

      // 新規投票のときだけレートを消費する。
      const rl = await checkRateLimit(env.DB, user.uid, "performer_prediction");
      if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

      await upsertUser(env, user.uid);

      // 1曲あたりの投票数上限チェック (8人まで)
      const userVoteCount = await env.DB.prepare(
        "SELECT COUNT(*) as cnt FROM setlist_performer_prediction_votes WHERE show_id = ? AND song_id = ? AND user_id = ?"
      )
        .bind(showId, songId, user.uid)
        .first<{ cnt: number }>();

      if ((userVoteCount?.cnt ?? 0) >= 8) {
        return error("Too many votes: max 8 performers per song", 422);
      }

      // votes INSERT + 集計の原子 upsert を batch で実行。
      // first_voted_by/at は INSERT 時のみ入り、ON CONFLICT 側では触らない (最初の投票者を保持)。
      const insertVote = env.DB.prepare(
        `INSERT INTO setlist_performer_prediction_votes (show_id, song_id, idol_id, user_id, voted_at)
         VALUES (?, ?, ?, ?, datetime('now'))`
      ).bind(showId, songId, idol_id, user.uid);
      const upsertCount = env.DB.prepare(
        `INSERT INTO setlist_performer_predictions (show_id, song_id, idol_id, vote_count, first_voted_by, first_voted_at)
         VALUES (?, ?, ?, 1, ?, datetime('now'))
         ON CONFLICT(show_id, song_id, idol_id) DO UPDATE SET vote_count = vote_count + 1
         RETURNING vote_count`
      ).bind(showId, songId, idol_id, user.uid);
      const [, countResult] = await env.DB.batch<{ vote_count: number }>([
        insertVote,
        upsertCount,
      ]);
      const voteCount = countResult.results[0]?.vote_count ?? 1;

      return json({ idol_id, vote_count: voteCount, already_voted: false }, 201);
    }

    // ----------------------------------------------------------------
    // DELETE /shows/:showId/songs/:songId/performers/:idolId — 出演者予想取消 (auth必須)
    // ----------------------------------------------------------------
    const performersDeleteMatch = path.match(
      /^\/shows\/([^/]+)\/songs\/([^/]+)\/performers\/([^/]+)$/
    );
    if (performersDeleteMatch && request.method === "DELETE") {
      const showId = decodePathParam(ctx, performersDeleteMatch[1], "show_id");
      if (showId instanceof Response) return showId;
      const songId = decodePathParam(ctx, performersDeleteMatch[2], "song_id");
      if (songId instanceof Response) return songId;
      const idolId = decodePathParam(ctx, performersDeleteMatch[3], "idol_id");
      if (idolId instanceof Response) return idolId;
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      const vote = await env.DB.prepare(
        "SELECT 1 FROM setlist_performer_prediction_votes WHERE show_id = ? AND song_id = ? AND idol_id = ? AND user_id = ?"
      )
        .bind(showId, songId, idolId, user.uid)
        .first();

      if (!vote) {
        return json({ idol_id: idolId, vote_count: 0, not_voted: true });
      }

      // votes DELETE + 集計の原子デクリメント (MAX で負値防止) を batch で実行。
      const deleteVote = env.DB.prepare(
        "DELETE FROM setlist_performer_prediction_votes WHERE show_id = ? AND song_id = ? AND idol_id = ? AND user_id = ?"
      ).bind(showId, songId, idolId, user.uid);
      const decrementCount = env.DB.prepare(
        `UPDATE setlist_performer_predictions SET vote_count = MAX(0, vote_count - 1)
         WHERE show_id = ? AND song_id = ? AND idol_id = ?
         RETURNING vote_count`
      ).bind(showId, songId, idolId);
      const [, countResult] = await env.DB.batch<{ vote_count: number }>([
        deleteVote,
        decrementCount,
      ]);
      const newCount = countResult.results[0]?.vote_count ?? 0;

      // 0 になったら集計行を削除 (既存挙動を維持)。
      if (newCount <= 0) {
        await env.DB.prepare(
          "DELETE FROM setlist_performer_predictions WHERE show_id = ? AND song_id = ? AND idol_id = ?"
        )
          .bind(showId, songId, idolId)
          .run();
      }

      return json({ idol_id: idolId, vote_count: newCount });
    }

    // ----------------------------------------------------------------
    // GET /shows/:showId/likes — セトリ post-vote 集計 + 自分の like 状態
    // ----------------------------------------------------------------
    // ライブ後にユーザが「この曲良かった」と複数選択する star toggle 用。
    // 集計は count(*) で都度算出 (低トラフィック前提)。
    const likesGetMatch = path.match(/^\/shows\/([^/]+)\/likes$/);
    if (likesGetMatch && request.method === "GET") {
      const showId = decodePathParam(ctx, likesGetMatch[1], "show_id");
      if (showId instanceof Response) return showId;
      const authUser = await getAuthUser(request, env);
      const uid = authUser?.uid ?? "";

      const { results } = await env.DB.prepare(`
        SELECT
          l.song_id,
          COUNT(*) AS like_count,
          MAX(CASE WHEN l.user_id = ? THEN 1 ELSE 0 END) AS has_user_liked
        FROM setlist_song_likes l
        WHERE l.show_id = ?
        GROUP BY l.song_id
      `)
        .bind(uid, showId)
        .all();

      return json(
        results.map((r: any) => ({
          song_id: r.song_id,
          like_count: r.like_count,
          has_user_liked: r.has_user_liked === 1,
        }))
      );
    }

    // ----------------------------------------------------------------
    // POST /shows/:showId/songs/:songId/like — like 登録 (auth必須、 idempotent)
    // ----------------------------------------------------------------
    const likePostMatch = path.match(/^\/shows\/([^/]+)\/songs\/([^/]+)\/like$/);
    if (likePostMatch && request.method === "POST") {
      const showId = decodePathParam(ctx, likePostMatch[1], "show_id");
      if (showId instanceof Response) return showId;
      const songId = decodePathParam(ctx, likePostMatch[2], "song_id");
      if (songId instanceof Response) return songId;
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      const likeSongIdErr = validateOpaqueKey(songId, "song_id");
      if (likeSongIdErr) return error(likeSongIdErr);

      const inactive = await requireActiveUser(ctx, user);
      if (inactive) return inactive;

      await upsertUser(env, user.uid);

      await env.DB.prepare(
        `INSERT OR IGNORE INTO setlist_song_likes (show_id, song_id, user_id, liked_at)
         VALUES (?, ?, ?, datetime('now'))`
      )
        .bind(showId, songId, user.uid)
        .run();

      const count = await env.DB.prepare(
        "SELECT COUNT(*) AS c FROM setlist_song_likes WHERE show_id = ? AND song_id = ?"
      )
        .bind(showId, songId)
        .first<{ c: number }>();

      return json({ song_id: songId, like_count: count?.c ?? 1, liked: true });
    }

    // ----------------------------------------------------------------
    // DELETE /shows/:showId/songs/:songId/like — like 解除
    // ----------------------------------------------------------------
    const likeDeleteMatch = path.match(/^\/shows\/([^/]+)\/songs\/([^/]+)\/like$/);
    if (likeDeleteMatch && request.method === "DELETE") {
      const showId = decodePathParam(ctx, likeDeleteMatch[1], "show_id");
      if (showId instanceof Response) return showId;
      const songId = decodePathParam(ctx, likeDeleteMatch[2], "song_id");
      if (songId instanceof Response) return songId;
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      await env.DB.prepare(
        "DELETE FROM setlist_song_likes WHERE show_id = ? AND song_id = ? AND user_id = ?"
      )
        .bind(showId, songId, user.uid)
        .run();

      const count = await env.DB.prepare(
        "SELECT COUNT(*) AS c FROM setlist_song_likes WHERE show_id = ? AND song_id = ?"
      )
        .bind(showId, songId)
        .first<{ c: number }>();

      return json({ song_id: songId, like_count: count?.c ?? 0, liked: false });
    }

  return null;
}
