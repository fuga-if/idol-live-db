// routes/users.ts — 自分のアカウント (表示名の変更・退会) と、ユーザーのバッジ。
//
//   POST   /users/me              — 表示名の変更
//   DELETE /users/me              — 退会 (アカウントに紐づく個人データの削除)
//   GET    /users/:user_id/badges — 貢献バッジ

import { getAuthUser } from "../auth";
import { fetchBadges } from "../badges";
import { checkRateLimit } from "../rate_limit";
import type { RouteContext } from "./context";
import { decodePathParam, readJsonBody, requireActiveUser } from "./guards";

/** 退会した人の uid の代わりに入れる値。 */
const DELETED_USER = "deleted";

/**
 * 退会したら uid を DELETED_USER に置き換える列 (表, 列)。値は定数だけ (SQL に埋め込む)。
 * タグの updated_by / edited_by は、端末 ID が無いときに uid が入る。
 */
const USER_REFERENCE_COLUMNS: ReadonlyArray<readonly [string, string]> = [
  ["polls", "created_by"],
  ["poll_entries", "first_voted_by"],
  ["setlist_predictions", "first_voted_by"],
  ["setlist_performer_predictions", "first_voted_by"],
  ["tags", "updated_by"],
  ["idol_tag_master", "updated_by"],
  ["unit_tag_master", "updated_by"],
  ["tag_description_history", "edited_by"],
  ["idol_tag_description_history", "edited_by"],
  ["unit_tag_description_history", "edited_by"],
];

/** /users/me (POST・DELETE) と /users/:user_id/badges。どれでもなければ null。 */
export async function handleUsers(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;

  // ----------------------------------------------------------------
  // POST /users/me — 自分の表示名 (display_name) を更新
  //   メソッドは POST。この Worker の書き込みは POST/PUT/DELETE のみで、
  //   PATCH は isWriteMethod にも CORS Allow-Methods にも無い (= 未サポート)。
  //   既存の書き込み規約に合わせる。
  // ----------------------------------------------------------------
  if (path === "/users/me" && request.method === "POST") {
    const user = await getAuthUser(request, env);
    if (!user) return error("Unauthorized", 401);

    // 先にボディを検証する。checkRateLimit は原子的にカウンタを +1 するので、
    // 検証より前に走らせると空文字・型不正など 400 になるリクエストでも 1日3枠を
    // 消費し、ユーザーが表示名を変更できなくなる (自爆ロックアウト)。検証後に課金する。
    const body = await readJsonBody(ctx, "display_name is required");
    if (body instanceof Response) return body;
    const raw = body.display_name;
    if (typeof raw !== "string") return error("display_name is required");
    const name = raw.trim();
    if (name.length === 0) return error("display_name must not be empty");
    // 長さは UTF-16 code unit ではなく Unicode code point で数える ([...name])。
    // 絵文字等を 2 文字とカウントして見た目40字未満を弾く誤判定を避ける。
    if ([...name].length > 40) return error("display_name too long (max 40)");

    const [inactive, rl] = await Promise.all([
      requireActiveUser(ctx, user),
      checkRateLimit(env.DB, user.uid, "profile"),
    ]);
    if (inactive) return inactive;
    if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

    // upsertUser は使わない (display_name を email 等で上書きしうるため)。
    // 行は login 時に必ず作られているので plain UPDATE。INSERT...ON CONFLICT にすると、
    // 行が消えた (削除済みだがトークンだけ生きている) アカウントを display_name だけの
    // 不完全な行で復活させてしまうため、ここでは新規作成しない。0件更新なら 404。
    const updated = await env.DB.prepare(
      `UPDATE users SET display_name = ?, updated_at = datetime('now') WHERE id = ?`
    )
      .bind(name, user.uid)
      .run();
    if (!updated.meta.changes) return error("user not found", 404);

    return json({ displayName: name });
  }

  // ----------------------------------------------------------------
  // DELETE /users/me — 本人によるアカウント削除 (App Store 5.1.1(v) 対応)
  //   退会を妨げないため BAN 中でも許可する。リクエストボディは無い。
  //   ログインで初めて作られるアカウント紐付けデータ (投票・like・編集履歴・Good) は
  //   すべて物理削除する。Good 数や like 数は保存値ではなく都度 COUNT(*) なので、
  //   本人の行を消せば表示カウントも自然に減る。予想/投票の集計テーブル (vote_count 等) は
  //   端末・匿名の共有データなので触らない。
  //   foreign_keys が ON でも通るよう、子テーブルの参照を先に外してから親 → users の順に消す。
  //   一連の操作は env.DB.batch() で原子的に実行し、途中失敗で中途半端な状態を残さない。
  //   共有データ (お題・予想・タグの語彙と履歴) に残る本人の uid は "deleted" に置き換える。
  //   手元に残ったセッション JWT は、users の行が無いので書き込みの経路・/auth/me・
  //   /auth/refresh で 401 になる (isRevokedSession。読み取りだけの GET は期限まで通る)。
  // ----------------------------------------------------------------
  if (path === "/users/me" && request.method === "DELETE") {
    const user = await getAuthUser(request, env);
    if (!user) return error("Unauthorized", 401);
    const uid = user.uid;

    await env.DB.batch([
      // 本人だけに紐づく個人データ。FK は無いのでそのまま削除する。
      env.DB.prepare("DELETE FROM rate_limits WHERE user_id = ?").bind(uid),
      env.DB.prepare("DELETE FROM setlist_prediction_votes WHERE user_id = ?").bind(uid),
      env.DB
        .prepare("DELETE FROM setlist_performer_prediction_votes WHERE user_id = ?")
        .bind(uid),
      env.DB.prepare("DELETE FROM poll_votes WHERE user_id = ?").bind(uid),
      env.DB.prepare("DELETE FROM setlist_song_likes WHERE user_id = ?").bind(uid),

      // Good は本人が付けた分と、本人の編集が受け取った分の双方を削除する。
      // edit_batch を消す前に、それを参照する edit_good を先に消す (FK)。
      env.DB.prepare("DELETE FROM edit_good WHERE user_id = ?").bind(uid),
      env.DB
        .prepare(
          "DELETE FROM edit_good WHERE batch_id IN (SELECT id FROM edit_batch WHERE editor_id = ?)"
        )
        .bind(uid),

      // edit_history も edit_batch を参照するので先に消す (FK)。
      env.DB
        .prepare(
          "DELETE FROM edit_history WHERE batch_id IN (SELECT id FROM edit_batch WHERE editor_id = ?)"
        )
        .bind(uid),

      // 他者の batch に残る本人の batch / 本人への参照を外す (FK)。
      //   reverts_batch_id: 本人の編集を revert した他者 batch から、消える batch への参照を外す
      //   reverted_by:      本人が他者の編集を revert した記録の実行者参照を外す
      env.DB
        .prepare(
          "UPDATE edit_batch SET reverts_batch_id = NULL WHERE reverts_batch_id IN (SELECT id FROM edit_batch WHERE editor_id = ?)"
        )
        .bind(uid),
      env.DB.prepare("UPDATE edit_batch SET reverted_by = NULL WHERE reverted_by = ?").bind(uid),

      // 本人のコール編集履歴を消す。コールそのもの (lines_json) は消さない —
      // タグ・投票集計と同じ「みんなの共有データ」であって個人データではないため。
      env.DB.prepare("DELETE FROM call_edit_history WHERE user_id = ?").bind(uid),
      // 「最後にコールを書いた人」の参照だけ外す (表示は「匿名」に落ちる)。
      env.DB
        .prepare("UPDATE song_call_stats SET updated_by_uid = NULL WHERE updated_by_uid = ?")
        .bind(uid),

      // 参照を外したので本人の編集 batch を削除し、最後に users 行を削除する。
      env.DB.prepare("DELETE FROM edit_batch WHERE editor_id = ?").bind(uid),
      env.DB.prepare("DELETE FROM users WHERE id = ?").bind(uid),

      // ここから下は、みんなの共有データ (お題・予想・タグの語彙と履歴) に残った本人の uid を
      // "deleted" に置き換える (データは残し、誰のものかだけを消す)。これらの列には索引が無く
      // 表全体を読むが、退会はまれなので索引を張って毎回の書き込みを重くするより安い。
      ...USER_REFERENCE_COLUMNS.map(([table, column]) =>
        env.DB.prepare(`UPDATE ${table} SET ${column} = '${DELETED_USER}' WHERE ${column} = ?`).bind(uid)
      ),
      // 本人が発行した引き継ぎコード (中身は本人の端末のデータ)。
      env.DB.prepare("DELETE FROM transfer_codes WHERE user_id = ?").bind(uid),
    ]);

    return json({ deleted: true });
  }

  // ----------------------------------------------------------------
  // GET /users/:user_id/badges
  // ----------------------------------------------------------------
  const badgesMatch = path.match(/^\/users\/([^/]+)\/badges$/);
  if (badgesMatch && request.method === "GET") {
    const userId = decodePathParam(ctx, badgesMatch[1], "user_id");
    if (userId instanceof Response) return userId;
    const badges = await fetchBadges(env.DB, userId);
    return json(badges);
  }

  return null;
}
