// routes/polls.ts — みんなの投票 (Community Theme Polls) API
//
// index.ts の if チェーンから切り出した 2 つめのルート群。
// 一覧 / 結果 / 実績 / 詳細 / 作成 / 投票 / 投票取消 / 削除。
//
// ⚠️ 本文は index.ts から移動しただけで、SQL もレスポンス JSON のキーも
//    ステータスコードも Cache-Control も変えていない。

import { getAuthUser } from "../auth";
import { checkRateLimit, peekRateLimit, VOTE_LIMIT } from "../rate_limit";
import { upsertUser, checkIsAdmin } from "../users";
import {
  parsePositiveInt, parseScopeIds, validateScopeIdsAgainstTable,
} from "../validation";
import type { RouteContext } from "./context";
import { decodePathParam, readJsonBody, requireActiveUser, requireOpaqueKey } from "./guards";

/**
 * /polls/* を処理する。
 * どのルートにも一致しなければ `null` を返し、呼び出し元の if チェーンへ処理を戻す。
 */
export async function handlePolls(ctx: RouteContext): Promise<Response | null> {
  const { request, env, url, path, json, error, rateLimitResponse } = ctx;

    // ----------------------------------------------------------------
    // GET /polls/months — 終了したお題がある月 (日本時間) と件数。新しい月から
    //   ※ /polls/:id より前に置く。アプリは終了タブをこの月ごとにさかのぼって読む。
    // ----------------------------------------------------------------
    if (path === "/polls/months" && request.method === "GET") {
      const { results } = await env.DB.prepare(`
        SELECT strftime('%Y-%m', ends_at, '+9 hours') AS month, COUNT(*) AS count
          FROM polls
         WHERE status = 'active' AND ends_at <= datetime('now')
         GROUP BY month
         ORDER BY month DESC
      `).all();
      return json(
        (results as any[]).map((r) => ({
          month: r.month,
          // 月の見出し (年月の大きい数字) の文言はここだけで作る。iOS / Android はそのまま出す。
          label: r.month.replace("-", "."),
          count: r.count,
        }))
      );
    }

    // ----------------------------------------------------------------
    // GET /polls/counts — 開催中 / 終了のお題の件数 ({ active, past })
    //   ※ /polls/:id より前に置く。一覧は 20 件ずつしか読まないので、並び替えの行に出す総数はここで取る。
    //   お題の行だけを数える (候補は読まない)。誰が見ても同じなので一覧と同じく Cache API に 30 秒置く
    //   (一覧を開くたびに呼ばれるため。件数は最大 30 秒遅れる)。
    // ----------------------------------------------------------------
    if (path === "/polls/counts" && request.method === "GET") {
      const countsKey = new Request(`${url.origin}/__cache/polls-counts`);
      const cachedCounts = await caches.default.match(countsKey);
      if (cachedCounts) return json(await cachedCounts.json());
      const r = await env.DB.prepare(`
        SELECT SUM(CASE WHEN ends_at > datetime('now') THEN 1 ELSE 0 END) AS active,
               SUM(CASE WHEN ends_at <= datetime('now') THEN 1 ELSE 0 END) AS past
          FROM polls
         WHERE status = 'active'
      `).first<any>();
      const counts = { active: r?.active ?? 0, past: r?.past ?? 0 };
      const put = caches.default.put(countsKey, json(counts, 200, { "Cache-Control": "public, max-age=30" }));
      if (ctx.waitUntil) ctx.waitUntil(put);
      else await put;
      return json(counts);
    }

    // ----------------------------------------------------------------
    // GET /polls/quota — 今日あと何件お題を作れるか (auth必須)。作成画面の頭に出す
    //   ※ /polls/:id より前に置く。数えるだけで枠は使わない。人ごとの値なので no-store
    // ----------------------------------------------------------------
    if (path === "/polls/quota" && request.method === "GET") {
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);
      const quota = await peekRateLimit(env.DB, user.uid, "poll");
      return json(quota, 200, { "Cache-Control": "private, no-store" });
    }

    // ----------------------------------------------------------------
    // GET /polls?status=active|past&month=YYYY-MM&sort=ends|created|votes&order=asc|desc&limit&offset
    //   — 投票一覧 (auth任意)
    // ----------------------------------------------------------------
    // active = status='active' AND ends_at > now
    // past   = status='active' AND ends_at <= now
    // month  = 締切が日本時間でその月のものだけ (past の月送り用)。指定時は limit の既定を 100 にする
    // sort   = 並びの軸。ends=締切 (既定) / created=作った日時 / votes=票の合計。知らない値は ends
    // order  = asc / desc。省略時は今までと同じ (active は締切の近い順 = asc、past は新しい順 = desc)。
    //          軸を指定して order を省くと、その軸の既定 (created / votes は desc = 新しい順・多い順)
    if (path === "/polls" && request.method === "GET") {
      const authUser = await getAuthUser(request, env);
      const uid = authUser?.uid ?? "";
      const statusParam = url.searchParams.get("status") ?? "active";
      const monthParam = url.searchParams.get("month");
      const monthMatch = monthParam?.match(/^(\d{4})-(0[1-9]|1[0-2])$/);
      if (monthParam != null && !monthMatch) return error("month must be YYYY-MM", 400);
      const limit = parsePositiveInt(url.searchParams.get("limit"), monthMatch ? 100 : 20, 100);
      const offset = parsePositiveInt(url.searchParams.get("offset"), 0, Number.MAX_SAFE_INTEGER);

      const isActive = statusParam !== "past";
      const sort = parsePollListSort(url.searchParams.get("sort"), url.searchParams.get("order"), isActive);

      // 誰が見ても同じ部分 (お題・票数・1 位) は Worker の Cache API に 30 秒置いて使い回し、
      // 人ごとの部分 (自分の票数・自分のお題か) だけを毎回足す。応答の形は変えない。
      // 票数は最大 30 秒遅れる。キーは認証を含まないので、人ごとの値を shared に入れないこと。
      const sharedKey = new Request(
        `${url.origin}/__cache/polls-list?status=${isActive ? "active" : "past"}` +
          `&month=${monthMatch ? monthParam : ""}&sort=${sort.key}&order=${sort.ascending ? "asc" : "desc"}` +
          `&limit=${limit}&offset=${offset}`
      );
      let shared: any[];
      const cached = await caches.default.match(sharedKey);
      if (cached) {
        shared = await cached.json();
      } else {
        shared = await fetchPollListShared(env.DB, isActive, monthMatch ? monthParam! : null, sort, limit, offset);
        const put = caches.default.put(sharedKey, json(shared, 200, { "Cache-Control": "public, max-age=30" }));
        if (ctx.waitUntil) ctx.waitUntil(put);
        else await put;
      }

      // 自分の票数: ページのお題だけを (poll_id, user_id) の索引で数える。未ログインは 0。
      const myVotes = new Map<string, number>();
      if (uid !== "" && shared.length > 0) {
        const ids = shared.map((r) => r.id);
        const { results: mine } = await env.DB.prepare(
          `SELECT poll_id, COUNT(*) AS c FROM poll_votes
            WHERE user_id = ? AND poll_id IN (${ids.map(() => "?").join(",")})
            GROUP BY poll_id`
        ).bind(uid, ...ids).all<any>();
        for (const m of mine) myVotes.set(m.poll_id, m.c);
      }

      // この応答は Cache-Control を付けない (エッジの共有キャッシュに載らない) ので、人ごとの値を入れてよい。
      return json(
        shared.map((r) => ({
          ...r,
          // 呼び出した人のお題か (削除の導線を出す判定)。アプリはこれに移り、created_by は後で消す。
          is_own_poll: uid !== "" && r.created_by === uid,
          my_vote_count: myVotes.get(r.id) ?? 0,
        }))
      );
    }

    // ----------------------------------------------------------------
    // GET /polls/results — 終了したお題の結果(優勝者) 一覧 (公開・殿堂用)
    //   ※ /polls/:id より前に置く (results が :id に食われないように)
    // ----------------------------------------------------------------
    if (path === "/polls/results" && request.method === "GET") {
      const { results } = await env.DB.prepare(
        `SELECT poll_id, title, target_type, ends_at, entity_id, vote_count
           FROM (
             SELECT p.id AS poll_id, p.title, p.target_type,
                    CAST(strftime('%s', p.ends_at) AS INTEGER) AS ends_at,
                    pe.entity_id, pe.vote_count,
                    RANK() OVER (PARTITION BY p.id ORDER BY pe.vote_count DESC) AS rnk
               FROM polls p
               JOIN poll_entries pe ON pe.poll_id = p.id
              WHERE p.status = 'active'
                AND p.ends_at < datetime('now')
                AND pe.vote_count > 0
           )
          WHERE rnk = 1
          ORDER BY ends_at DESC
          LIMIT 50`
      ).all();
      // 同点1位は複数行返るので poll_id 単位で先頭のみ採用。
      const seen = new Set<string>();
      const winners = (results as any[]).filter((r) => {
        if (seen.has(r.poll_id)) return false;
        seen.add(r.poll_id);
        return true;
      });
      return json(winners, 200, { "Cache-Control": "public, max-age=300" });
    }

    // ----------------------------------------------------------------
    // GET /polls/achievements/:entityId — その曲/アイドルが終了お題で取った順位 (上位3位まで)
    // ----------------------------------------------------------------
    const pollAchvMatch = path.match(/^\/polls\/achievements\/([^/]+)$/);
    if (pollAchvMatch && request.method === "GET") {
      const entityId = decodePathParam(ctx, pollAchvMatch[1], "entity_id");
      if (entityId instanceof Response) return entityId;
      // 先に entity_id でエントリを絞り、その曲/アイドルが出たお題の中だけで順位を出す。
      // 旧実装は「終了お題の全エントリを RANK してから entity_id で絞る」形で、
      // 1 回あたり 3,954 行 (poll_entries ほぼ全件) を読んでいた。
      // RANK() は「自分より票が多いエントリ数 + 1」と等価なので、
      // 対象お題ごとの数え上げに置き換えても同点の扱いを含めて結果は変わらない。
      const { results } = await env.DB.prepare(
        `SELECT poll_id, title, target_type, ends_at, vote_count, rnk
           FROM (
             SELECT p.id AS poll_id, p.title, p.target_type,
                    CAST(strftime('%s', p.ends_at) AS INTEGER) AS ends_at,
                    pe.vote_count,
                    (SELECT COUNT(*) + 1
                       FROM poll_entries x
                      WHERE x.poll_id = pe.poll_id
                        AND x.vote_count > pe.vote_count) AS rnk
               FROM poll_entries pe
               JOIN polls p ON p.id = pe.poll_id
              WHERE pe.entity_id = ?
                AND pe.vote_count > 0
                AND p.status = 'active'
                AND p.ends_at < datetime('now')
           )
          WHERE rnk <= 3
          ORDER BY rnk ASC, ends_at DESC
          LIMIT 20`
      ).bind(entityId).all();
      return json(results, 200, { "Cache-Control": "public, max-age=300" });
    }

    // ----------------------------------------------------------------
    // GET /polls/:id — 投票詳細 (auth任意)
    // ----------------------------------------------------------------
    const pollGetMatch = path.match(/^\/polls\/([^/]+)$/);
    if (pollGetMatch && request.method === "GET") {
      const pollId = decodePathParam(ctx, pollGetMatch[1], "poll_id");
      if (pollId instanceof Response) return pollId;
      const authUser = await getAuthUser(request, env);
      const uid = authUser?.uid ?? "";

      const poll = await env.DB.prepare(`
        SELECT
          p.id,
          p.title,
          p.description,
          p.target_type,
          p.created_by,
          CAST(strftime('%s', p.created_at) AS INTEGER) AS created_at,
          CAST(strftime('%s', p.ends_at) AS INTEGER) AS ends_at,
          p.status,
          p.candidate_scope,
          p.scope_brand_ids,
          p.scope_entity_ids,
          COALESCE(SUM(pe.vote_count), 0) AS total_votes,
          COUNT(pe.entity_id) AS entry_count
        FROM polls p
        LEFT JOIN poll_entries pe ON pe.poll_id = p.id
        WHERE p.id = ?
        GROUP BY p.id
      `)
        .bind(pollId)
        .first<any>();

      if (!poll) return error("Poll not found", 404);

      const scopeBrandIds = parseScopeIds(poll.scope_brand_ids);
      const scopeEntityIds = parseScopeIds(poll.scope_entity_ids);

      const { results: entries } = await env.DB.prepare(`
        SELECT
          pe.entity_id,
          pe.vote_count,
          CASE WHEN pv.user_id IS NOT NULL THEN 1 ELSE 0 END AS has_user_voted
        FROM poll_entries pe
        LEFT JOIN poll_votes pv
          ON pv.poll_id = pe.poll_id
          AND pv.entity_id = pe.entity_id
          AND pv.user_id = ?
        WHERE pe.poll_id = ?
        ORDER BY pe.vote_count DESC, pe.first_voted_at ASC
      `)
        .bind(uid, pollId)
        .all<any>();

      // manual スコープでは未投票の指定候補も 0 票で返す（候補が見えないと投票できない）
      let resultEntries = entries as any[];
      if ((poll.candidate_scope ?? "all") === "manual" && scopeEntityIds && scopeEntityIds.length > 0) {
        const seen = new Set(resultEntries.map((e: any) => e.entity_id));
        const placeholders = scopeEntityIds
          .filter((id) => !seen.has(id))
          .map((entity_id) => ({ entity_id, vote_count: 0, has_user_voted: 0 }));
        resultEntries = [...resultEntries, ...placeholders];
      }

      const myVoteRow = await env.DB.prepare(
        "SELECT COUNT(*) AS c FROM poll_votes WHERE poll_id = ? AND user_id = ?"
      )
        .bind(pollId, uid)
        .first<{ c: number }>();

      return json({
        poll: {
          id: poll.id,
          title: poll.title,
          description: poll.description,
          target_type: poll.target_type,
          created_by: poll.created_by,
          is_own_poll: uid !== "" && poll.created_by === uid,
          created_at: poll.created_at,
          ends_at: poll.ends_at,
          status: poll.status,
          candidate_scope: poll.candidate_scope ?? "all",
          scope_brand_ids: scopeBrandIds,
          scope_entity_ids: scopeEntityIds,
          total_votes: poll.total_votes,
          entry_count: poll.entry_count,
        },
        entries: resultEntries.map((e: any) => ({
          entity_id: e.entity_id,
          vote_count: e.vote_count,
          has_user_voted: e.has_user_voted === 1,
        })),
        my_vote_count: myVoteRow?.c ?? 0,
      });
    }

    // ----------------------------------------------------------------
    // POST /polls — お題作成 (auth必須・rate limit "poll")
    // ----------------------------------------------------------------
    if (path === "/polls" && request.method === "POST") {
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      const [inactive, rl] = await Promise.all([
        requireActiveUser(ctx, user),
        checkRateLimit(env.DB, user.uid, "poll"),
      ]);
      if (inactive) return inactive;
      if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

      await upsertUser(env, user.uid);

      const body = await readJsonBody(ctx);
      if (body instanceof Response) return body;
      const { title, description, target_type, days } = body;
      const candidateScope = body.candidate_scope ?? "all";
      const scopeBrandIdsInput = body.scope_brand_ids;
      const scopeEntityIdsInput = body.scope_entity_ids;

      if (!title || typeof title !== "string" || title.trim().length === 0) {
        return error("title is required");
      }
      if (title.trim().length > 80) {
        return error("title must be 80 characters or less");
      }
      if (description !== undefined && description !== null) {
        if (typeof description !== "string" || description.length > 280) {
          return error("description must be 280 characters or less");
        }
      }
      if (!target_type || (target_type !== "song" && target_type !== "idol" && target_type !== "unit")) {
        return error("target_type must be 'song', 'idol', or 'unit'");
      }
      if (candidateScope !== "all" && candidateScope !== "brand" && candidateScope !== "manual") {
        return error("candidate_scope must be 'all', 'brand', or 'manual'");
      }

      let scopeBrandIdsStored: string | null = null;
      let scopeEntityIdsStored: string | null = null;

      if (candidateScope === "brand") {
        const result = await validateScopeIdsAgainstTable(env.DB, scopeBrandIdsInput, {
          minLen: 1, maxLen: 16, maxEntryLen: 32,
          allowDuplicates: true, table: "brands", fieldName: "scope_brand_ids",
        });
        if ("error" in result) return error(result.error);
        scopeBrandIdsStored = result.json;
      } else if (candidateScope === "manual") {
        // 実在チェックは行わない (バンドル master.sqlite と server D1 の同期ラグで
        // クライアントに存在する曲が server 側に未投入のケースがある)
        const result = await validateScopeIdsAgainstTable(env.DB, scopeEntityIdsInput, {
          minLen: 2, maxLen: 500, maxEntryLen: 64,
          allowDuplicates: false, table: null,
          fieldName: "scope_entity_ids",
        });
        if ("error" in result) return error(result.error);
        scopeEntityIdsStored = result.json;
      }

      const daysNum = typeof days === "number" ? Math.min(Math.max(1, Math.floor(days)), 30) : 14;
      const pollId = crypto.randomUUID();
      const now = new Date();
      const endsAt = new Date(now.getTime() + daysNum * 24 * 60 * 60 * 1000);
      const endsAtStr = endsAt.toISOString().replace("T", " ").replace(/\.\d{3}Z$/, "");

      await env.DB.prepare(
        `INSERT INTO polls (id, title, description, target_type, created_by, ends_at,
                            candidate_scope, scope_brand_ids, scope_entity_ids)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
        .bind(
          pollId,
          title.trim(),
          description ?? null,
          target_type,
          user.uid,
          endsAtStr,
          candidateScope,
          scopeBrandIdsStored,
          scopeEntityIdsStored
        )
        .run();

      const created = await env.DB.prepare(
        `SELECT id, title, description, target_type, created_by,
                CAST(strftime('%s', created_at) AS INTEGER) AS created_at,
                CAST(strftime('%s', ends_at) AS INTEGER) AS ends_at,
                status, candidate_scope, scope_brand_ids, scope_entity_ids
         FROM polls WHERE id = ?`
      )
        .bind(pollId)
        .first<any>();

      return json(
        {
          id: created.id,
          title: created.title,
          description: created.description,
          target_type: created.target_type,
          created_by: created.created_by,
          is_own_poll: true,
          created_at: created.created_at,
          ends_at: created.ends_at,
          status: created.status,
          candidate_scope: created.candidate_scope ?? "all",
          scope_brand_ids: parseScopeIds(created.scope_brand_ids),
          scope_entity_ids: parseScopeIds(created.scope_entity_ids),
          total_votes: 0,
          entry_count: 0,
        },
        201
      );
    }

    // ----------------------------------------------------------------
    // POST /polls/:id/votes — 投票 (auth必須。1 お題 3 票の上限だけで、1 日の枠は持たない)
    // ----------------------------------------------------------------
    const pollVotePostMatch = path.match(/^\/polls\/([^/]+)\/votes$/);
    if (pollVotePostMatch && request.method === "POST") {
      const pollId = decodePathParam(ctx, pollVotePostMatch[1], "poll_id");
      if (pollId instanceof Response) return pollId;
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      // 1 日の枠 (旧 poll_vote、60 票) は 2026-11-25 に外した。開催中のお題が 79 件に増え、
      // 全部に入れたい人が枠切れで投票できなくなっていた。1 お題 3 票の上限 (VOTE_LIMIT) が
      // 1 人が動かせる票数をお題ごとに抑えているので、日次の枠は要らない。
      const body = await readJsonBody(ctx);
      if (body instanceof Response) return body;
      const entity_id = requireOpaqueKey(ctx, body.entity_id, "entity_id");
      if (entity_id instanceof Response) return entity_id;

      const inactive = await requireActiveUser(ctx, user);
      if (inactive) return inactive;

      // poll 存在確認 + active チェック
      const poll = await env.DB.prepare(
        "SELECT id, status, ends_at, target_type, candidate_scope, scope_brand_ids, scope_entity_ids FROM polls WHERE id = ?"
      )
        .bind(pollId)
        .first<{
          id: string;
          status: string;
          ends_at: string;
          target_type: string;
          candidate_scope: string | null;
          scope_brand_ids: string | null;
          scope_entity_ids: string | null;
        }>();

      if (!poll) return error("Poll not found", 404);
      if (poll.status !== "active") {
        return error("Poll is not active", 409);
      }
      // ends_at は SQLite の datetime 文字列 "YYYY-MM-DD HH:MM:SS" または ISO
      const endsAtMs = new Date(poll.ends_at.replace(" ", "T") + (poll.ends_at.includes("T") ? "" : "Z")).getTime();
      if (Date.now() > endsAtMs) {
        return error("Poll has ended", 409);
      }

      // candidate_scope による entity_id 妥当性チェック
      // - manual: scope_entity_ids 配列との照合 (サーバ自己完結)
      // - brand : クライアントの picker UI 側で brand 内に絞り込むので、サーバでは検証しない。
      //           server には songs/idols マスタが無い (バンドル master.sqlite 側にしかない)
      //           ので brand_id を引けない。万一クライアント改造で scope 外の entity_id が
      //           来ても、悪用シナリオは「他ブランド限定の投票枠を埋める」程度で、
      //           レート制限 (60票/日) と合わせて実害は低い。
      const scope = poll.candidate_scope ?? "all";
      if (scope === "manual") {
        const allowed = new Set(parseScopeIds(poll.scope_entity_ids) ?? []);
        if (!allowed.has(entity_id)) {
          return error("entity_id is not in poll candidates", 422);
        }
      }

      // 3票上限チェック
      const myVoteRow = await env.DB.prepare(
        "SELECT COUNT(*) AS c FROM poll_votes WHERE poll_id = ? AND user_id = ?"
      )
        .bind(pollId, user.uid)
        .first<{ c: number }>();
      const myVoteCount = myVoteRow?.c ?? 0;
      if (myVoteCount >= VOTE_LIMIT) {
        return error("vote limit", 409);
      }

      // 二重投票チェック（PK 制約でも弾かれるが先に返す）
      const existing = await env.DB.prepare(
        "SELECT 1 FROM poll_votes WHERE poll_id = ? AND entity_id = ? AND user_id = ?"
      )
        .bind(pollId, entity_id, user.uid)
        .first();
      if (existing) {
        const entry = await env.DB.prepare(
          "SELECT vote_count FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
        )
          .bind(pollId, entity_id)
          .first<{ vote_count: number }>();
        return json({ entity_id, vote_count: entry?.vote_count ?? 0, my_vote_count: myVoteCount }, 200);
      }

      await upsertUser(env, user.uid);

      // 応答の票数は、書く前に読んだ値 + 1 (従来どおり)。
      const entry = await env.DB.prepare(
        "SELECT vote_count FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
      )
        .bind(pollId, entity_id)
        .first<{ vote_count: number }>();

      // 票の INSERT と集計の +1 を 1 つの batch (= 1 トランザクション) で書く。集計は読んだ値を
      // 書き戻さず相対で +1 し、票が実際に入ったとき (changes() > 0) だけ動かす。
      // 同時の投票で票を取りこぼさず、同じ候補への同時の再送で二重に数えない。
      const [inserted] = await env.DB.batch([
        env.DB.prepare(
          `INSERT OR IGNORE INTO poll_votes (poll_id, entity_id, user_id, voted_at)
           VALUES (?, ?, ?, datetime('now'))`
        ).bind(pollId, entity_id, user.uid),
        env.DB.prepare(
          `INSERT INTO poll_entries (poll_id, entity_id, vote_count, first_voted_by, first_voted_at)
           SELECT ?, ?, 1, ?, datetime('now') WHERE changes() > 0
           ON CONFLICT(poll_id, entity_id) DO UPDATE SET vote_count = vote_count + 1`
        ).bind(pollId, entity_id, user.uid),
      ]);
      if (!inserted.meta.changes) {
        // 同じ候補への同時の投票が先に入った。再投票と同じ 200 を返す。
        const current = await env.DB.prepare(
          "SELECT vote_count FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
        )
          .bind(pollId, entity_id)
          .first<{ vote_count: number }>();
        return json({ entity_id, vote_count: current?.vote_count ?? 0, my_vote_count: myVoteCount + 1 }, 200);
      }

      return json({ entity_id, vote_count: (entry?.vote_count ?? 0) + 1, my_vote_count: myVoteCount + 1 }, 201);
    }

    // ----------------------------------------------------------------
    // DELETE /polls/:id/votes/:entityId — 投票取消 (auth必須)
    // ----------------------------------------------------------------
    const pollVoteDeleteMatch = path.match(/^\/polls\/([^/]+)\/votes\/([^/]+)$/);
    if (pollVoteDeleteMatch && request.method === "DELETE") {
      const pollId = decodePathParam(ctx, pollVoteDeleteMatch[1], "poll_id");
      if (pollId instanceof Response) return pollId;
      const entityId = decodePathParam(ctx, pollVoteDeleteMatch[2], "entity_id");
      if (entityId instanceof Response) return entityId;
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      const vote = await env.DB.prepare(
        "SELECT 1 FROM poll_votes WHERE poll_id = ? AND entity_id = ? AND user_id = ?"
      )
        .bind(pollId, entityId, user.uid)
        .first();

      if (!vote) {
        const entry = await env.DB.prepare(
          "SELECT vote_count FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
        )
          .bind(pollId, entityId)
          .first<{ vote_count: number }>();
        const myVoteRow = await env.DB.prepare(
          "SELECT COUNT(*) AS c FROM poll_votes WHERE poll_id = ? AND user_id = ?"
        )
          .bind(pollId, user.uid)
          .first<{ c: number }>();
        return json({ entity_id: entityId, vote_count: entry?.vote_count ?? 0, my_vote_count: myVoteRow?.c ?? 0 });
      }

      const currentEntry = await env.DB.prepare(
        "SELECT vote_count FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
      )
        .bind(pollId, entityId)
        .first<{ vote_count: number }>();

      const newCount = (currentEntry?.vote_count ?? 1) - 1;

      // 票の DELETE と集計の変更を 1 つの batch で書く。集計は票が実際に消えたとき
      // (changes() > 0) だけ動かすので、同じ票の同時の取り消しで二重に減らない。
      // 最後の 1 票なら候補の行ごと消し、そうでなければ相対で -1 する (読んだ値を書き戻さない)。
      // 行を消すかは読んだ票数で決める (読み直すと D1 の読み取り行数が増えるため)。
      const updateEntry =
        newCount <= 0
          ? env.DB.prepare(
              `DELETE FROM poll_entries
                WHERE poll_id = ? AND entity_id = ? AND vote_count <= 1 AND changes() > 0`
            )
          : env.DB.prepare(
              `UPDATE poll_entries SET vote_count = MAX(0, vote_count - 1)
                WHERE poll_id = ? AND entity_id = ? AND changes() > 0`
            );
      const [, , mine] = await env.DB.batch<{ c: number }>([
        env.DB.prepare(
          "DELETE FROM poll_votes WHERE poll_id = ? AND entity_id = ? AND user_id = ?"
        ).bind(pollId, entityId, user.uid),
        updateEntry.bind(pollId, entityId),
        env.DB.prepare(
          "SELECT COUNT(*) AS c FROM poll_votes WHERE poll_id = ? AND user_id = ?"
        ).bind(pollId, user.uid),
      ]);

      return json({ entity_id: entityId, vote_count: Math.max(0, newCount), my_vote_count: mine.results[0]?.c ?? 0 });
    }

    // ----------------------------------------------------------------
    // DELETE /polls/:id — お題削除（作成者本人 or admin → status='removed'）
    // ----------------------------------------------------------------
    const pollDeleteMatch = path.match(/^\/polls\/([^/]+)$/);
    if (pollDeleteMatch && request.method === "DELETE") {
      const pollId = decodePathParam(ctx, pollDeleteMatch[1], "poll_id");
      if (pollId instanceof Response) return pollId;
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);

      const poll = await env.DB.prepare(
        "SELECT id, created_by, status FROM polls WHERE id = ?"
      )
        .bind(pollId)
        .first<{ id: string; created_by: string; status: string }>();

      if (!poll) return error("Poll not found", 404);

      const isAdmin = await checkIsAdmin(env, user.uid);
      if (poll.created_by !== user.uid && !isAdmin) {
        return error("Forbidden", 403);
      }

      await env.DB.prepare("UPDATE polls SET status = 'removed' WHERE id = ?")
        .bind(pollId)
        .run();

      return json({ id: pollId, status: "removed" });
    }

  return null;
}

/** GET /polls の並び。`key` は軸、`ascending` は向き。 */
export type PollListSort = { key: "ends" | "created" | "votes"; ascending: boolean };

/**
 * `sort` / `order` を読む。知らない軸は締切 (ends) に倒す (古いアプリ・打ち間違いでも一覧は出す)。
 * order を省いたときの向きは、締切なら今まで通り (開催中は近い順 = 昇順、終了は新しい順 = 降順)、
 * 作った日時・票数は新しい順・多い順 (降順)。
 */
export function parsePollListSort(sortParam: string | null, orderParam: string | null, isActive: boolean): PollListSort {
  const key: PollListSort["key"] = sortParam === "created" || sortParam === "votes" ? sortParam : "ends";
  const defaultAscending = key === "ends" ? isActive : false;
  const ascending = orderParam === "asc" ? true : orderParam === "desc" ? false : defaultAscending;
  return { key, ascending };
}

/**
 * 並びの ORDER BY。同じ値が並んだときの順も毎回同じにする (offset で読み進めたとき、
 * ページの継ぎ目でお題が重なったり抜けたりしないように)。票数が同じなら締切の近い順。
 * `alias` を省くと列名だけで書く (page の中では sort_votes が SELECT の別名なので、表の名前を付けると引けない)。
 */
function pollListOrderBy(sort: PollListSort, alias?: string): string {
  const dir = sort.ascending ? "ASC" : "DESC";
  const c = (column: string) => (alias ? `${alias}.${column}` : column);
  switch (sort.key) {
    case "created":
      return `${c("created_at")} ${dir}, ${c("id")} ${dir}`;
    case "votes":
      return `${c("sort_votes")} ${dir}, ${c("ends_at")} ASC, ${c("id")} ASC`;
    default:
      return `${c("ends_at")} ${dir}, ${c("id")} ${dir}`;
  }
}

/**
 * GET /polls の、誰が見ても同じ部分。人ごとの値 (my_vote_count / is_own_poll) は入れない
 * (Cache API に置くため)。キーの並びは旧応答と同じに保つ (呼び出し側で人ごとの値を差し込む)。
 *
 * 先にお題をページ分だけ選び (page)、そのお題の候補だけを 1 回なめて集計する (agg)。
 * 旧実装は polls と poll_entries を JOIN して GROUP BY してから LIMIT していたので、
 * 条件に合う全お題の候補を毎回読んでいた (1 回 4,000〜7,000 行。D1 の読みの 7 割)。
 *
 * 票数順だけは並べる前に合計が要るので、条件に合うお題 (開催中、または終了の 1 か月) の候補を
 * 合計してからページを切る。終了タブは月で絞った後なので、全期間をなめることはない。
 */
async function fetchPollListShared(
  db: D1Database,
  isActive: boolean,
  month: string | null,
  sort: PollListSort,
  limit: number,
  offset: number
): Promise<any[]> {
  const timeCondition = isActive ? "p.ends_at > datetime('now')" : "p.ends_at <= datetime('now')";
  // 日本時間の月初〜翌月初を UTC に直した範囲で絞る (idx_polls_status_ends が効く形)。
  const monthStart = month ? `${month}-01` : null;
  const monthCondition = monthStart
    ? "AND p.ends_at >= datetime(?, '-9 hours') AND p.ends_at < datetime(?, '+1 month', '-9 hours')"
    : "";
  const where = `p.status = 'active' AND ${timeCondition} ${monthCondition}`;
  const page =
    sort.key === "votes"
      ? `
    scoped AS (SELECT id FROM polls p WHERE ${where}),
    totals AS (
      SELECT poll_id, SUM(vote_count) AS votes
      FROM poll_entries
      WHERE poll_id IN (SELECT id FROM scoped)
      GROUP BY poll_id
    ),
    page AS (
      SELECT p.*, COALESCE(t.votes, 0) AS sort_votes
      FROM polls p
      LEFT JOIN totals t ON t.poll_id = p.id
      WHERE p.id IN (SELECT id FROM scoped)
      ORDER BY ${pollListOrderBy(sort)}
      LIMIT ? OFFSET ?
    )`
      : `
    page AS (
      SELECT p.*, 0 AS sort_votes FROM polls p
      WHERE ${where}
      ORDER BY ${pollListOrderBy(sort)}
      LIMIT ? OFFSET ?
    )`;
  // 日付は iOS デコーダ (.secondsSince1970) に合わせ epoch 秒の数値で返す
  const { results } = await db.prepare(`
    WITH ${page},
    agg AS (
      SELECT poll_id,
             SUM(vote_count) AS total_votes,
             COUNT(*) AS entry_count,
             MAX(vote_count) AS top_vote_count
      FROM poll_entries
      WHERE poll_id IN (SELECT id FROM page)
      GROUP BY poll_id
    )
    SELECT
      p.id,
      p.title,
      p.description,
      p.target_type,
      p.created_by,
      CAST(strftime('%s', p.created_at) AS INTEGER) AS created_at,
      CAST(strftime('%s', p.ends_at) AS INTEGER) AS ends_at,
      p.status,
      p.candidate_scope,
      p.scope_brand_ids,
      p.scope_entity_ids,
      COALESCE(agg.total_votes, 0) AS total_votes,
      COALESCE(agg.entry_count, 0) AS entry_count,
      (SELECT pe2.entity_id FROM poll_entries pe2 WHERE pe2.poll_id = p.id AND pe2.vote_count > 0
         ORDER BY pe2.vote_count DESC LIMIT 1) AS top_entity_id,
      agg.top_vote_count AS top_vote_count
    FROM page p
    LEFT JOIN agg ON agg.poll_id = p.id
    ORDER BY ${pollListOrderBy(sort, "p")}
  `)
    .bind(...(monthStart ? [monthStart, monthStart] : []), limit, offset)
    .all();

  return results.map((r: any) => ({
    id: r.id,
    title: r.title,
    description: r.description,
    target_type: r.target_type,
    created_by: r.created_by,
    is_own_poll: false,
    created_at: r.created_at,
    ends_at: r.ends_at,
    status: r.status,
    candidate_scope: r.candidate_scope ?? "all",
    scope_brand_ids: parseScopeIds(r.scope_brand_ids),
    scope_entity_ids: parseScopeIds(r.scope_entity_ids),
    total_votes: r.total_votes,
    entry_count: r.entry_count,
    my_vote_count: 0,
    // 一覧行に現在1位の曲/アイドルの写真を出すための ID (まだ無投票なら null → クライアント側で汎用表示)。
    top_entity_id: r.top_entity_id,
    // 1 位の票数 (終了タブの行に「1位 ○○ · N票」と出す)。
    top_vote_count: r.top_entity_id ? r.top_vote_count : null,
  }));
}
