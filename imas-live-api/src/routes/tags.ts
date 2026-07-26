// routes/tags.ts — ユーザータグ API (song / idol / unit の 3 プール + 類似)
//
// index.ts から切り出した 3 つめのルート群。同じ形のプールが 3 つ並ぶため
// index.ts の 4 割超を占めていた。
//
// タグ専用のヘルパ (REPORT_THRESHOLD / TAG_* 定数 / validateTagFields /
// slugify / resolveSlugFromTable) は index.ts の他の場所から使われていないので
// 一緒に持ってきている。
//
// ⚠️ ルート本文は移動しただけで、SQL もレスポンス JSON のキーも
//    ステータスコードも Cache-Control も変えていない。

import { getAuthUser } from "../auth";
import { checkRateLimit, dryCheckIpRateLimit, commitIpRateLimit } from "../rate_limit";
import { checkIsAdmin } from "../users";
import { parsePositiveInt, escapeLike } from "../validation";
import type { RouteContext } from "./context";

// REPORT_THRESHOLD はタグ通報 (POST /tags/:id/report) で使用。
// 投稿承認系の APPROVAL_THRESHOLD は submission 撤去 (0014) に伴い削除。
const REPORT_THRESHOLD = 3;

// ---------------------------------------------------------------------------
// タグ (song/idol/unit 共通) フィールド検証
// ---------------------------------------------------------------------------

const TAG_HEX_COLOR_RE = /^#[0-9a-fA-F]{6}$/;
const TAG_DESCRIPTION_MAX_LEN = 300;
const TAG_CATEGORY_MAX_LEN = 30;

/**
 * /tags, /idol-tags, /unit-tags の POST (新規作成) と PUT (更新) 共通で使う
 * description/category/color の検証。キーが undefined のときは「指定なし」として
 * 素通しする (POST は任意項目、PUT は未指定フィールドを更新しない仕様のため)。
 * null は「クリア」として許容する。
 */
function validateTagFields(fields: {
  description?: unknown;
  category?: unknown;
  color?: unknown;
}): string | null {
  const { description, category, color } = fields;
  if (description !== undefined && description !== null) {
    if (typeof description !== "string") return "description must be a string";
    if (description.length > TAG_DESCRIPTION_MAX_LEN) {
      return `description must be ${TAG_DESCRIPTION_MAX_LEN} characters or less`;
    }
  }
  if (category !== undefined && category !== null) {
    if (typeof category !== "string") return "category must be a string";
    if (category.length > TAG_CATEGORY_MAX_LEN) {
      return `category must be ${TAG_CATEGORY_MAX_LEN} characters or less`;
    }
  }
  if (color !== undefined && color !== null && color !== "") {
    if (typeof color !== "string" || !TAG_HEX_COLOR_RE.test(color)) {
      return "color must be a #RRGGBB hex code";
    }
  }
  return null;
}

function slugify(input: string): string {
  const ascii = input
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  // ASCII 化が短すぎる、または "tag_" 単体になる場合はハッシュベースIDを使う
  if (ascii.length < 2 || ascii === "tag_") {
    // Web Crypto は sync で使えないので btoa ベースの fallback
    const encoded = btoa(unescape(encodeURIComponent(input)))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=/g, "");
    return "tag_" + encoded.slice(0, 16);
  }
  return ascii;
}

/**
 * name から一意な id (slug) を解決する。table は "tags" | "idol_tag_master" | "unit_tag_master" のみを渡す
 * 想定 (呼び出し元固定・ユーザー入力を直接渡さない → SQL 組み立てに使っても injection 経路にならない)。
 */
async function resolveSlugFromTable(
  db: D1Database,
  table: "tags" | "idol_tag_master" | "unit_tag_master",
  name: string
): Promise<string> {
  const base = slugify(name);
  // 衝突時は -2, -3, ... を最大10回試みる (name の UNIQUE 制約で同名は弾けるが PK 衝突を防ぐ)
  for (let i = 0; i <= 10; i++) {
    const candidate = i === 0 ? base : `${base}-${i + 1}`;
    const existing = await db
      .prepare(`SELECT id FROM ${table} WHERE id = ?`)
      .bind(candidate)
      .first();
    if (!existing) return candidate;
  }
  // 万が一全て衝突した場合はタイムスタンプサフィックス
  return `${base}-${Date.now()}`;
}

/**
 * タグ類似スコアの平滑化定数。Jaccard 係数の分母に足す。
 *
 * `shared / (tags_a + tags_b - shared + DAMPING)`
 *
 * 0 にすると素の Jaccard になり「タグ2個中2個一致 = 100%」が
 * 「10個中8個一致」に勝ってしまう。タグはユーザー投稿のみで自動付与しない方針なので
 * タグ数の少ない曲が多数派であり、この小サンプル事故が主流になる。
 * 大きくするほど「タグがよく付いている曲」が有利になり、旧実装 (共有タグ数順) の
 * 人気バイアスに近づく。5 はその中間。
 */
const SIMILARITY_DAMPING = 5;

/**
 * /tags, /idol-tags, /unit-tags, /{songs,idols,units}/:id/tags,
 * および /{songs,idols,units}/:id/similar を処理する。
 * どのルートにも一致しなければ `null` を返し、呼び出し元の if チェーンへ処理を戻す。
 */
export async function handleTags(ctx: RouteContext): Promise<Response | null> {
  const { request, env, url, path, json, error, rateLimitResponse, rateLimitSimple } = ctx;

    // ================================================================
    // ユーザータグ API
    // ================================================================

    // ----------------------------------------------------------------
    // POST /tags — タグ新規作成
    // ----------------------------------------------------------------
    if (path === "/tags" && request.method === "POST") {
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      let { name, description, category, color } = body as {
        name: string;
        description?: string;
        category?: string;
        color?: string;
      };

      if (!name || typeof name !== "string") return error("name is required");
      name = name.trim();
      if (name.length < 1 || name.length > 30) return error("name must be 1-30 characters");
      const tagFieldsErr = validateTagFields({ description, category, color });
      if (tagFieldsErr) return error(tagFieldsErr);

      // 同名チェック
      const existingByName = await env.DB.prepare("SELECT * FROM tags WHERE name = ?").bind(name).first();
      if (existingByName) return json({ tag: existingByName, created: false }, 409);

      // レート制限: 当日10件まで (INSERT OR IGNORE で初期化 → UPDATE で加算、quota check と quota increment を batch)
      const dateYmd = new Date().toISOString().slice(0, 10);
      await env.DB.prepare(
        `INSERT OR IGNORE INTO device_tag_create_quota (device_id, date_ymd, count) VALUES (?, ?, 0)`
      ).bind(deviceId, dateYmd).run();
      const quotaRow = await env.DB.prepare(
        "SELECT count FROM device_tag_create_quota WHERE device_id = ? AND date_ymd = ?"
      ).bind(deviceId, dateYmd).first<{ count: number }>();
      if ((quotaRow?.count ?? 0) >= 10) return error("Daily tag creation limit reached", 429);

      const candidateId = await resolveSlugFromTable(env.DB, "tags", name);
      const now = Math.floor(Date.now() / 1000);

      // tag INSERT + quota++ を batch で原子化 (race condition 解消)
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO tags (id, name, description, category, color, created_by, created_at, updated_at, is_official, status)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'active')`
        ).bind(candidateId, name, description ?? null, category ?? null, color ?? null, deviceId, now, now),
        env.DB.prepare(
          `UPDATE device_tag_create_quota SET count = count + 1
           WHERE device_id = ? AND date_ymd = ?`
        ).bind(deviceId, dateYmd),
      ]);

      const tag = await env.DB.prepare("SELECT * FROM tags WHERE id = ?").bind(candidateId).first();
      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ tag, created: true }, 201);
    }

    // ----------------------------------------------------------------
    // GET /tags — タグ一覧検索
    // ----------------------------------------------------------------
    if (path === "/tags" && request.method === "GET") {
      const search = url.searchParams.get("search") || "";
      const category = url.searchParams.get("category") || "";
      const sort = url.searchParams.get("sort") || "popular";
      // タグ本体は軽量 (name/color/count のみ) かつ Cloudflare + アプリ両側でキャッシュされるので、
      // ピッカーが全件取れるように上限を大きく取る。ページネーションは実質廃止。
      const limit = parsePositiveInt(url.searchParams.get("limit"), 1000, 2000);
      const offset = Math.min(10000, Math.max(0, parseInt(url.searchParams.get("offset") || "0") || 0));

      const params: unknown[] = [];
      const conditions: string[] = ["t.status != 'removed'"];

      if (search) {
        conditions.push("t.name LIKE ? ESCAPE '\\'");
        params.push(`%${escapeLike(search)}%`);
      }
      if (category) {
        conditions.push("t.category = ?");
        params.push(category);
      }

      const where = conditions.length ? "WHERE " + conditions.join(" AND ") : "";

      let orderBy = "ORDER BY t.name ASC";
      if (sort === "popular") orderBy = "ORDER BY COALESCE(total_uses, 0) DESC";
      else if (sort === "recent") orderBy = "ORDER BY t.created_at DESC";

      // 曲タグ専用マスタ (アイドルタグは idol_tag_master に分離済み、GET /idol-tags 参照)。
      const sql = `
        SELECT t.id, t.name, SUBSTR(t.description, 1, 40) as description_preview,
               t.category, t.color, t.created_at,
               COALESCE((SELECT SUM(vote_count) FROM song_tags WHERE tag_id = t.id), 0) as total_uses
        FROM tags t
        ${where}
        ${orderBy}
        LIMIT ? OFFSET ?
      `;
      params.push(limit, offset);

      const { results } = await env.DB.prepare(sql).bind(...params).all();

      const countSql = `SELECT COUNT(*) as cnt FROM tags t ${where}`;
      const countRow = await env.DB.prepare(countSql).bind(...params.slice(0, params.length - 2)).first<{ cnt: number }>();

      // タグ一覧はユーザー非依存・変化が緩やかなので短期キャッシュを許可
      // (タグ追加 UI の再オープン高速化。max-age 60s + SWR 300s)。
      return json({ tags: results, total: countRow?.cnt ?? 0 }, 200, {
        "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
      });
    }

    // ----------------------------------------------------------------
    // GET /tags/activity — タグ付けの盛り上がり (曲/アイドル両ドメイン横断)
    // device_song_tag / device_idol_tag は「端末1件ごとのタグ付与イベント」を
    // created_at 付きで持つ既存ログなので、新規テーブル無しで直近フィード・
    // 期間内急増を算出できる。曲名/アイドル名は解決せず entity_id のみ返し、
    // クライアント側のローカル DB (CloudKit 同期済み) で名前・色を引く
    // (GET /tags/:id 等の既存レスポンスと同じ役割分担)。
    // ※ 汎用マッチの GET /tags/:id (下) より前に置かないと "activity" が
    //    タグ id として食われてしまうので、パス完全一致はここで先に判定する。
    // ----------------------------------------------------------------
    if (path === "/tags/activity" && request.method === "GET") {
      const windowDays = Math.min(30, Math.max(1, parseInt(url.searchParams.get("window_days") || "7") || 7));
      const windowStart = Math.floor(Date.now() / 1000) - windowDays * 86400;

      const [recentSongRows, recentIdolRows, trendSongRows, trendIdolRows, risingSongRows, risingIdolRows] =
        await Promise.all([
          env.DB.prepare(
            `SELECT dst.song_id as entity_id, dst.tag_id, t.name as tag_name, t.color as tag_color,
                    t.category as tag_category, dst.created_at
             FROM device_song_tag dst JOIN tags t ON t.id = dst.tag_id
             WHERE t.status != 'removed'
             ORDER BY dst.created_at DESC LIMIT 40`
          ).all(),
          env.DB.prepare(
            `SELECT dit.idol_id as entity_id, dit.tag_id, t.name as tag_name, t.color as tag_color,
                    t.category as tag_category, dit.created_at
             FROM device_idol_tag dit JOIN idol_tag_master t ON t.id = dit.tag_id
             WHERE t.status != 'removed'
             ORDER BY dit.created_at DESC LIMIT 40`
          ).all(),
          env.DB.prepare(
            `SELECT dst.tag_id, t.name as tag_name, t.color as tag_color, t.category as tag_category,
                    COUNT(*) as recent_count,
                    COALESCE((SELECT SUM(vote_count) FROM song_tags WHERE tag_id = t.id), 0) as total_count
             FROM device_song_tag dst JOIN tags t ON t.id = dst.tag_id
             WHERE dst.created_at >= ? AND t.status != 'removed'
             GROUP BY dst.tag_id ORDER BY recent_count DESC LIMIT 10`
          ).bind(windowStart).all(),
          env.DB.prepare(
            `SELECT dit.tag_id, t.name as tag_name, t.color as tag_color, t.category as tag_category,
                    COUNT(*) as recent_count,
                    COALESCE((SELECT SUM(vote_count) FROM idol_tags WHERE tag_id = t.id), 0) as total_count
             FROM device_idol_tag dit JOIN idol_tag_master t ON t.id = dit.tag_id
             WHERE dit.created_at >= ? AND t.status != 'removed'
             GROUP BY dit.tag_id ORDER BY recent_count DESC LIMIT 10`
          ).bind(windowStart).all(),
          env.DB.prepare(
            `SELECT dst.song_id as entity_id, dst.tag_id, t.name as tag_name, t.color as tag_color,
                    COUNT(*) as recent_count
             FROM device_song_tag dst JOIN tags t ON t.id = dst.tag_id
             WHERE dst.created_at >= ? AND t.status != 'removed'
             GROUP BY dst.song_id, dst.tag_id HAVING COUNT(*) >= 2
             ORDER BY recent_count DESC LIMIT 10`
          ).bind(windowStart).all(),
          env.DB.prepare(
            `SELECT dit.idol_id as entity_id, dit.tag_id, t.name as tag_name, t.color as tag_color,
                    COUNT(*) as recent_count
             FROM device_idol_tag dit JOIN idol_tag_master t ON t.id = dit.tag_id
             WHERE dit.created_at >= ? AND t.status != 'removed'
             GROUP BY dit.idol_id, dit.tag_id HAVING COUNT(*) >= 2
             ORDER BY recent_count DESC LIMIT 10`
          ).bind(windowStart).all(),
        ]);

      const recent = [
        ...recentSongRows.results.map((r: any) => ({ domain: "song", ...r })),
        ...recentIdolRows.results.map((r: any) => ({ domain: "idol", ...r })),
      ]
        .sort((a: any, b: any) => b.created_at - a.created_at)
        .slice(0, 40);

      const trendingTags = [
        ...trendSongRows.results.map((r: any) => ({ domain: "song", ...r })),
        ...trendIdolRows.results.map((r: any) => ({ domain: "idol", ...r })),
      ]
        .sort((a: any, b: any) => b.recent_count - a.recent_count)
        .slice(0, 12);

      const risingEntities = [
        ...risingSongRows.results.map((r: any) => ({ domain: "song", ...r })),
        ...risingIdolRows.results.map((r: any) => ({ domain: "idol", ...r })),
      ]
        .sort((a: any, b: any) => b.recent_count - a.recent_count)
        .slice(0, 12);

      // アクセス集中対策のエッジキャッシュ (max-age 10分)。日次だと「最近つけられたタグ」の
      // 反映が最大24時間遅れて盛り上がり感が薄れるため、鮮度と負荷軽減のバランスでこの値にする。
      return json({ window_days: windowDays, recent, trending_tags: trendingTags, rising_entities: risingEntities }, 200, {
        "Cache-Control": "public, max-age=600, stale-while-revalidate=1800",
      });
    }

    // ----------------------------------------------------------------
    // GET /tags/:id — タグ詳細
    // ----------------------------------------------------------------
    const tagDetailMatch = path.match(/^\/tags\/([^/]+)$/);
    if (tagDetailMatch && request.method === "GET") {
      const tagId = decodeURIComponent(tagDetailMatch[1]);
      // 削除済み (status='removed') は詳細でも返さない。一覧・付与・曲/アイドル/
      // ユニット別・類似は全て status != 'removed' で除外しているのに、ここだけ
      // 素通しだと安定 URL から削除済みタグが読めてしまう。
      const tag = await env.DB.prepare(
        "SELECT * FROM tags WHERE id = ? AND status != 'removed'"
      ).bind(tagId).first();
      if (!tag) return error("Tag not found", 404);

      // タグが付いた全曲を票数降順で返す (旧 LIMIT 50 だと 150 曲付いたタグでも
      // 50 曲しか返らず、絞り込み一覧・曲数バッジが欠落していた)。
      // アイドルタグは idol_tag_master に分離済み (GET /idol-tags/:id 参照) なのでここには出さない。
      const { results: songs } = await env.DB.prepare(
        `SELECT song_id, vote_count FROM song_tags WHERE tag_id = ? ORDER BY vote_count DESC LIMIT 1000`
      ).bind(tagId).all();

      // タグ詳細はユーザー非依存・変化が緩やか。エッジ (Cloudflare) で全ユーザ共有
      // キャッシュして D1 負荷を削減 (max-age 5分 + SWR 30分。自分のタグ付けは
      // クライアント側キャッシュが即無効化するので、この程度の鮮度で十分)。
      return json({ tag, songs }, 200, {
        "Cache-Control": "public, max-age=300, stale-while-revalidate=1800",
      });
    }

    // ----------------------------------------------------------------
    // PUT /tags/:id — タグ情報更新
    // ----------------------------------------------------------------
    if (tagDetailMatch && request.method === "PUT") {
      const tagId = decodeURIComponent(tagDetailMatch![1]);
      // 認証必須化: X-Device-Id だけでは誰でも他人タグを書換できた
      const authUser = await getAuthUser(request, env);
      if (!authUser) return error("Unauthorized", 401);
      const deviceId = request.headers.get("X-Device-Id") || authUser.uid;

      // is_banned チェック + レート制限 (マスタ編集 /edits と同じ "edit" quota を共有し、
      // 大量改竄の速度を抑える一次防御とする)。POST 側の同名チェックに対応する
      // タグ乱立防止は device_tag_create_quota が既に別途担っている。
      const [dbUser, rl] = await Promise.all([
        env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
          .bind(authUser.uid)
          .first<{ is_banned: number }>(),
        checkRateLimit(env.DB, authUser.uid, "edit"),
      ]);
      if (dbUser?.is_banned) return error("Banned", 403);
      if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

      const tag = await env.DB.prepare("SELECT * FROM tags WHERE id = ?").bind(tagId).first<{
        id: string; description: string | null; status: string;
      }>();
      if (!tag) return error("Tag not found", 404);
      if (tag.status === "removed") return error("Tag has been removed", 403);

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const { description, category, color } = body as {
        description?: string;
        category?: string;
        color?: string;
      };
      const tagFieldsErr = validateTagFields({ description, category, color });
      if (tagFieldsErr) return error(tagFieldsErr);
      const now = Math.floor(Date.now() / 1000);

      // 説明文変更なら履歴保存 (before + after 両方記録)
      if (description !== undefined && description !== tag.description) {
        await env.DB.prepare(
          `INSERT INTO tag_description_history (tag_id, description, description_before, edited_by, edited_at)
           VALUES (?, ?, ?, ?, ?)`
        ).bind(tagId, description ?? null, tag.description ?? null, deviceId, now).run();
      }

      const updates: string[] = ["updated_by = ?", "updated_at = ?"];
      const vals: unknown[] = [deviceId, now];

      if (description !== undefined) { updates.push("description = ?"); vals.push(description); }
      if (category !== undefined) { updates.push("category = ?"); vals.push(category); }
      if (color !== undefined) { updates.push("color = ?"); vals.push(color); }

      vals.push(tagId);
      await env.DB.prepare(`UPDATE tags SET ${updates.join(", ")} WHERE id = ?`).bind(...vals).run();

      const updated = await env.DB.prepare("SELECT * FROM tags WHERE id = ?").bind(tagId).first();
      return json({ tag: updated });
    }

    // ----------------------------------------------------------------
    // GET /tags/:id/history — 編集履歴
    // ----------------------------------------------------------------
    const tagHistoryMatch = path.match(/^\/tags\/([^/]+)\/history$/);
    if (tagHistoryMatch && request.method === "GET") {
      const tagId = decodeURIComponent(tagHistoryMatch[1]);
      const { results } = await env.DB.prepare(
        `SELECT id, tag_id,
                description AS description_after,
                description_before,
                edited_by, edited_at
         FROM tag_description_history
         WHERE tag_id = ? ORDER BY edited_at DESC LIMIT 30`
      ).bind(tagId).all();
      return json(results);
    }

    // ----------------------------------------------------------------
    // DELETE /tags/:id — 曲タグの削除 (admin 限定 → status='removed')
    // ----------------------------------------------------------------
    // 「きいた」「持ってる」のような**個人的なメモ**は共有タグの語彙に混ざると
    // 他ユーザーには意味が無く一覧を汚す。そういう用途にはアプリ内の PersonalTag
    // (端末ローカル専用・サーバー非送信) がある。共有プールから外すのはモデレーター判断。
    //
    // 通報 3 件で付く under_review は「印」でしかなく、読み取り側は
    // status != 'removed' しか見ていない (= under_review でも表示され続ける)。
    // 実際に消せるのはこの status='removed' だけ。
    //
    // 物理削除ではなく soft delete にする。付与実績 (song_tags) は残すので、
    // 誤操作なら status を戻すだけで復旧できる。
    const tagDeleteMatch = path.match(/^\/tags\/([^/]+)$/);
    if (tagDeleteMatch && request.method === "DELETE") {
      const tagId = decodeURIComponent(tagDeleteMatch[1]);
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);
      if (!(await checkIsAdmin(env, user.uid))) return error("Forbidden", 403);

      const tag = await env.DB.prepare(
        "SELECT id, status FROM tags WHERE id = ?"
      )
        .bind(tagId)
        .first<{ id: string; status: string }>();

      if (!tag) return error("Tag not found", 404);
      // 冪等: 既に removed なら何もせず同じ応答を返す
      if (tag.status === "removed") return json({ id: tagId, status: "removed" });

      await env.DB.prepare("UPDATE tags SET status = 'removed' WHERE id = ?")
        .bind(tagId)
        .run();

      return json({ id: tagId, status: "removed" });
    }

    // ----------------------------------------------------------------
    // POST /tags/:id/report — タグ通報
    // ----------------------------------------------------------------
    const tagReportMatch = path.match(/^\/tags\/([^/]+)\/report$/);
    if (tagReportMatch && request.method === "POST") {
      const tagId = decodeURIComponent(tagReportMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      // IP 単位の rate-limit: 複数デバイス回しで 1 タグを連続通報する spam を弾く。
      // device 単位の per-day 制限 (下記 already_reported) は二重防御として残す。
      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const tag = await env.DB.prepare("SELECT id FROM tags WHERE id = ?").bind(tagId).first();
      if (!tag) return error("Tag not found", 404);

      const today = new Date().toISOString().slice(0, 10);
      const alreadyReported = await env.DB.prepare(
        `SELECT 1 FROM tag_reports WHERE tag_id = ? AND reported_by = ? AND DATE(reported_at, 'unixepoch') = ?`
      ).bind(tagId, deviceId, today).first();
      if (alreadyReported) return error("Already reported today", 429);

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const now = Math.floor(Date.now() / 1000);
      await env.DB.prepare(
        `INSERT INTO tag_reports (tag_id, reported_by, reason, reported_at) VALUES (?, ?, ?, ?)`
      ).bind(tagId, deviceId, body.reason ?? null, now).run();

      const reportCount = await env.DB.prepare(
        "SELECT COUNT(*) as cnt FROM tag_reports WHERE tag_id = ?"
      ).bind(tagId).first<{ cnt: number }>();
      const total = reportCount?.cnt ?? 1;

      if (total >= REPORT_THRESHOLD) {
        await env.DB.prepare(
          "UPDATE tags SET status = 'under_review' WHERE id = ? AND status = 'active'"
        ).bind(tagId).run();
      }

      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ ok: true, total_reports: total });
    }

    // ==================================================================
    // アイドルタグ (idol_tag_master) — /tags 系と同じ形の別プール。
    // 曲タグ (tags) とは意味的に別語彙 (性格/属性 vs ムード/ジャンル) なので
    // マスタごと分離している (idol_tags/song_tags のドメイン並走パターンをマスタにも適用)。
    // ==================================================================

    // ----------------------------------------------------------------
    // POST /idol-tags — アイドルタグ新規作成
    // ----------------------------------------------------------------
    if (path === "/idol-tags" && request.method === "POST") {
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      let { name, description, category, color } = body as {
        name: string;
        description?: string;
        category?: string;
        color?: string;
      };

      if (!name || typeof name !== "string") return error("name is required");
      name = name.trim();
      if (name.length < 1 || name.length > 30) return error("name must be 1-30 characters");
      const tagFieldsErr = validateTagFields({ description, category, color });
      if (tagFieldsErr) return error(tagFieldsErr);

      const existingByName = await env.DB.prepare("SELECT * FROM idol_tag_master WHERE name = ?").bind(name).first();
      if (existingByName) return json({ tag: existingByName, created: false }, 409);

      // タグ作成レート制限は曲タグと共有 (乱立防止という目的が同じなので、
      // ドメインで分けると片方の quota で回避できてしまう)。
      const dateYmd = new Date().toISOString().slice(0, 10);
      await env.DB.prepare(
        `INSERT OR IGNORE INTO device_tag_create_quota (device_id, date_ymd, count) VALUES (?, ?, 0)`
      ).bind(deviceId, dateYmd).run();
      const quotaRow = await env.DB.prepare(
        "SELECT count FROM device_tag_create_quota WHERE device_id = ? AND date_ymd = ?"
      ).bind(deviceId, dateYmd).first<{ count: number }>();
      if ((quotaRow?.count ?? 0) >= 10) return error("Daily tag creation limit reached", 429);

      const candidateId = await resolveSlugFromTable(env.DB, "idol_tag_master", name);
      const now = Math.floor(Date.now() / 1000);

      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO idol_tag_master (id, name, description, category, color, created_by, created_at, updated_at, is_official, status)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'active')`
        ).bind(candidateId, name, description ?? null, category ?? null, color ?? null, deviceId, now, now),
        env.DB.prepare(
          `UPDATE device_tag_create_quota SET count = count + 1
           WHERE device_id = ? AND date_ymd = ?`
        ).bind(deviceId, dateYmd),
      ]);

      const tag = await env.DB.prepare("SELECT * FROM idol_tag_master WHERE id = ?").bind(candidateId).first();
      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ tag, created: true }, 201);
    }

    // ----------------------------------------------------------------
    // GET /idol-tags — アイドルタグ一覧検索
    // ----------------------------------------------------------------
    if (path === "/idol-tags" && request.method === "GET") {
      const search = url.searchParams.get("search") || "";
      const category = url.searchParams.get("category") || "";
      const sort = url.searchParams.get("sort") || "popular";
      const limit = parsePositiveInt(url.searchParams.get("limit"), 1000, 2000);
      const offset = Math.min(10000, Math.max(0, parseInt(url.searchParams.get("offset") || "0") || 0));

      const params: unknown[] = [];
      const conditions: string[] = ["t.status != 'removed'"];

      if (search) {
        conditions.push("t.name LIKE ? ESCAPE '\\'");
        params.push(`%${escapeLike(search)}%`);
      }
      if (category) {
        conditions.push("t.category = ?");
        params.push(category);
      }

      const where = conditions.length ? "WHERE " + conditions.join(" AND ") : "";

      let orderBy = "ORDER BY t.name ASC";
      if (sort === "popular") orderBy = "ORDER BY COALESCE(total_uses, 0) DESC";
      else if (sort === "recent") orderBy = "ORDER BY t.created_at DESC";

      const sql = `
        SELECT t.id, t.name, SUBSTR(t.description, 1, 40) as description_preview,
               t.category, t.color, t.created_at,
               COALESCE((SELECT SUM(vote_count) FROM idol_tags WHERE tag_id = t.id), 0) as total_uses
        FROM idol_tag_master t
        ${where}
        ${orderBy}
        LIMIT ? OFFSET ?
      `;
      params.push(limit, offset);

      const { results } = await env.DB.prepare(sql).bind(...params).all();

      const countSql = `SELECT COUNT(*) as cnt FROM idol_tag_master t ${where}`;
      const countRow = await env.DB.prepare(countSql).bind(...params.slice(0, params.length - 2)).first<{ cnt: number }>();

      return json({ tags: results, total: countRow?.cnt ?? 0 }, 200, {
        "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
      });
    }

    // ----------------------------------------------------------------
    // GET /idol-tags/:id — アイドルタグ詳細
    // ----------------------------------------------------------------
    const idolTagDetailMatch = path.match(/^\/idol-tags\/([^/]+)$/);
    if (idolTagDetailMatch && request.method === "GET") {
      const tagId = decodeURIComponent(idolTagDetailMatch[1]);
      // 削除済み (status='removed') は詳細でも返さない。一覧・付与・曲/アイドル/
      // ユニット別・類似は全て status != 'removed' で除外しているのに、ここだけ
      // 素通しだと安定 URL から削除済みタグが読めてしまう。
      const tag = await env.DB.prepare(
        "SELECT * FROM idol_tag_master WHERE id = ? AND status != 'removed'"
      ).bind(tagId).first();
      if (!tag) return error("Tag not found", 404);

      const { results: idols } = await env.DB.prepare(
        `SELECT idol_id, vote_count FROM idol_tags WHERE tag_id = ? ORDER BY vote_count DESC LIMIT 1000`
      ).bind(tagId).all();

      return json({ tag, idols }, 200, {
        "Cache-Control": "public, max-age=300, stale-while-revalidate=1800",
      });
    }

    // ----------------------------------------------------------------
    // PUT /idol-tags/:id — アイドルタグ情報更新
    // ----------------------------------------------------------------
    if (idolTagDetailMatch && request.method === "PUT") {
      const tagId = decodeURIComponent(idolTagDetailMatch![1]);
      const authUser = await getAuthUser(request, env);
      if (!authUser) return error("Unauthorized", 401);
      const deviceId = request.headers.get("X-Device-Id") || authUser.uid;

      // is_banned チェック + レート制限 (/tags/:id PUT と同方針。"edit" quota を共有)。
      const [dbUser, rl] = await Promise.all([
        env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
          .bind(authUser.uid)
          .first<{ is_banned: number }>(),
        checkRateLimit(env.DB, authUser.uid, "edit"),
      ]);
      if (dbUser?.is_banned) return error("Banned", 403);
      if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

      const tag = await env.DB.prepare("SELECT * FROM idol_tag_master WHERE id = ?").bind(tagId).first<{
        id: string; description: string | null; status: string;
      }>();
      if (!tag) return error("Tag not found", 404);
      if (tag.status === "removed") return error("Tag has been removed", 403);

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const { description, category, color } = body as {
        description?: string;
        category?: string;
        color?: string;
      };
      const tagFieldsErr = validateTagFields({ description, category, color });
      if (tagFieldsErr) return error(tagFieldsErr);
      const now = Math.floor(Date.now() / 1000);

      if (description !== undefined && description !== tag.description) {
        await env.DB.prepare(
          `INSERT INTO idol_tag_description_history (tag_id, description, description_before, edited_by, edited_at)
           VALUES (?, ?, ?, ?, ?)`
        ).bind(tagId, description ?? null, tag.description ?? null, deviceId, now).run();
      }

      const updates: string[] = ["updated_by = ?", "updated_at = ?"];
      const vals: unknown[] = [deviceId, now];

      if (description !== undefined) { updates.push("description = ?"); vals.push(description); }
      if (category !== undefined) { updates.push("category = ?"); vals.push(category); }
      if (color !== undefined) { updates.push("color = ?"); vals.push(color); }

      vals.push(tagId);
      await env.DB.prepare(`UPDATE idol_tag_master SET ${updates.join(", ")} WHERE id = ?`).bind(...vals).run();

      const updated = await env.DB.prepare("SELECT * FROM idol_tag_master WHERE id = ?").bind(tagId).first();
      return json({ tag: updated });
    }

    // ----------------------------------------------------------------
    // GET /idol-tags/:id/history — 編集履歴
    // ----------------------------------------------------------------
    const idolTagHistoryMatch = path.match(/^\/idol-tags\/([^/]+)\/history$/);
    if (idolTagHistoryMatch && request.method === "GET") {
      const tagId = decodeURIComponent(idolTagHistoryMatch[1]);
      const { results } = await env.DB.prepare(
        `SELECT id, tag_id,
                description AS description_after,
                description_before,
                edited_by, edited_at
         FROM idol_tag_description_history
         WHERE tag_id = ? ORDER BY edited_at DESC LIMIT 30`
      ).bind(tagId).all();
      return json(results);
    }

    // ----------------------------------------------------------------
    // DELETE /idol-tags/:id — アイドルタグの削除 (admin 限定 → status='removed')
    // ----------------------------------------------------------------
    // 「きいた」「持ってる」のような**個人的なメモ**は共有タグの語彙に混ざると
    // 他ユーザーには意味が無く一覧を汚す。そういう用途にはアプリ内の PersonalTag
    // (端末ローカル専用・サーバー非送信) がある。共有プールから外すのはモデレーター判断。
    //
    // 通報 3 件で付く under_review は「印」でしかなく、読み取り側は
    // status != 'removed' しか見ていない (= under_review でも表示され続ける)。
    // 実際に消せるのはこの status='removed' だけ。
    //
    // 物理削除ではなく soft delete にする。付与実績 (idol_tags) は残すので、
    // 誤操作なら status を戻すだけで復旧できる。
    const idolTagMasterDeleteMatch = path.match(/^\/idol-tags\/([^/]+)$/);
    if (idolTagMasterDeleteMatch && request.method === "DELETE") {
      const tagId = decodeURIComponent(idolTagMasterDeleteMatch[1]);
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);
      if (!(await checkIsAdmin(env, user.uid))) return error("Forbidden", 403);

      const tag = await env.DB.prepare(
        "SELECT id, status FROM idol_tag_master WHERE id = ?"
      )
        .bind(tagId)
        .first<{ id: string; status: string }>();

      if (!tag) return error("Tag not found", 404);
      // 冪等: 既に removed なら何もせず同じ応答を返す
      if (tag.status === "removed") return json({ id: tagId, status: "removed" });

      await env.DB.prepare("UPDATE idol_tag_master SET status = 'removed' WHERE id = ?")
        .bind(tagId)
        .run();

      return json({ id: tagId, status: "removed" });
    }

    // ----------------------------------------------------------------
    // POST /idol-tags/:id/report — アイドルタグ通報
    // ----------------------------------------------------------------
    const idolTagReportMatch = path.match(/^\/idol-tags\/([^/]+)\/report$/);
    if (idolTagReportMatch && request.method === "POST") {
      const tagId = decodeURIComponent(idolTagReportMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const tag = await env.DB.prepare("SELECT id FROM idol_tag_master WHERE id = ?").bind(tagId).first();
      if (!tag) return error("Tag not found", 404);

      const today = new Date().toISOString().slice(0, 10);
      const alreadyReported = await env.DB.prepare(
        `SELECT 1 FROM idol_tag_reports WHERE tag_id = ? AND reported_by = ? AND DATE(reported_at, 'unixepoch') = ?`
      ).bind(tagId, deviceId, today).first();
      if (alreadyReported) return error("Already reported today", 429);

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const now = Math.floor(Date.now() / 1000);
      await env.DB.prepare(
        `INSERT INTO idol_tag_reports (tag_id, reported_by, reason, reported_at) VALUES (?, ?, ?, ?)`
      ).bind(tagId, deviceId, body.reason ?? null, now).run();

      const reportCount = await env.DB.prepare(
        "SELECT COUNT(*) as cnt FROM idol_tag_reports WHERE tag_id = ?"
      ).bind(tagId).first<{ cnt: number }>();
      const total = reportCount?.cnt ?? 1;

      if (total >= REPORT_THRESHOLD) {
        await env.DB.prepare(
          "UPDATE idol_tag_master SET status = 'under_review' WHERE id = ? AND status = 'active'"
        ).bind(tagId).run();
      }

      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ ok: true, total_reports: total });
    }

    // ----------------------------------------------------------------
    // POST /songs/:song_id/tags — 曲にタグを付ける
    // ----------------------------------------------------------------
    const songTagsPostMatch = path.match(/^\/songs\/([^/]+)\/tags$/);
    if (songTagsPostMatch && request.method === "POST") {
      const songId = decodeURIComponent(songTagsPostMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const tagIds = body.tag_ids as string[];
      if (!Array.isArray(tagIds) || tagIds.length === 0) return error("tag_ids must be a non-empty array");

      const now = Math.floor(Date.now() / 1000);
      const appliedTagIds: string[] = [];

      for (const tagId of tagIds) {
        const tag = await env.DB.prepare("SELECT id FROM tags WHERE id = ? AND status != 'removed'").bind(tagId).first();
        if (!tag) continue;

        // device upsert + vote_count++ を batch で原子化
        const [deviceResult] = await env.DB.batch([
          env.DB.prepare(
            `INSERT OR IGNORE INTO device_song_tag (device_id, song_id, tag_id, created_at) VALUES (?, ?, ?, ?)`
          ).bind(deviceId, songId, tagId, now),
          env.DB.prepare(
            `INSERT INTO song_tags (song_id, tag_id, vote_count) VALUES (?, ?, 1)
             ON CONFLICT(song_id, tag_id) DO UPDATE SET vote_count = vote_count + 1`
          ).bind(songId, tagId),
        ]);

        if (deviceResult.meta.changes > 0) {
          appliedTagIds.push(tagId);
        }
      }

      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ song_id: songId, applied_tag_ids: appliedTagIds });
    }

    // ----------------------------------------------------------------
    // DELETE /songs/:song_id/tags/:tag_id — タグを外す
    // ----------------------------------------------------------------
    const songTagDeleteMatch = path.match(/^\/songs\/([^/]+)\/tags\/([^/]+)$/);
    if (songTagDeleteMatch && request.method === "DELETE") {
      const songId = decodeURIComponent(songTagDeleteMatch[1]);
      const tagId = decodeURIComponent(songTagDeleteMatch[2]);
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      // device削除 + vote_count-1 (MAX(0,...)) + 0以下なら song_tags 削除 を batch で原子化
      const [deleted] = await env.DB.batch([
        env.DB.prepare(
          "DELETE FROM device_song_tag WHERE device_id = ? AND song_id = ? AND tag_id = ?"
        ).bind(deviceId, songId, tagId),
        env.DB.prepare(
          `UPDATE song_tags SET vote_count = MAX(0, vote_count - 1) WHERE song_id = ? AND tag_id = ?`
        ).bind(songId, tagId),
        env.DB.prepare(
          `DELETE FROM song_tags WHERE song_id = ? AND tag_id = ? AND vote_count <= 0`
        ).bind(songId, tagId),
      ]);

      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ song_id: songId, tag_id: tagId, removed: deleted.meta.changes > 0 });
    }

    // ----------------------------------------------------------------
    // GET /songs/:song_id/tags — 曲のタグ一覧
    // ----------------------------------------------------------------
    const songTagsGetMatch = path.match(/^\/songs\/([^/]+)\/tags$/);
    if (songTagsGetMatch && request.method === "GET") {
      const songId = decodeURIComponent(songTagsGetMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");

      const { results: tags } = await env.DB.prepare(
        `SELECT t.id, t.name, t.color, t.category, st.vote_count
         FROM song_tags st
         JOIN tags t ON t.id = st.tag_id
         WHERE st.song_id = ? AND t.status != 'removed'
         ORDER BY st.vote_count DESC`
      ).bind(songId).all();

      let myTagIds: string[] = [];
      if (deviceId) {
        const { results: myRows } = await env.DB.prepare(
          "SELECT tag_id FROM device_song_tag WHERE device_id = ? AND song_id = ?"
        ).bind(deviceId, songId).all<{ tag_id: string }>();
        myTagIds = myRows.map((r) => r.tag_id);
      }

      return json({ tags, my_tag_ids: myTagIds });
    }

    // ----------------------------------------------------------------
    // POST /idols/:idol_id/tags — アイドルにタグを付ける (song 版と同じロジック)
    // ----------------------------------------------------------------
    const idolTagsPostMatch = path.match(/^\/idols\/([^/]+)\/tags$/);
    if (idolTagsPostMatch && request.method === "POST") {
      const idolId = decodeURIComponent(idolTagsPostMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const tagIds = body.tag_ids as string[];
      if (!Array.isArray(tagIds) || tagIds.length === 0) return error("tag_ids must be a non-empty array");

      const now = Math.floor(Date.now() / 1000);
      const appliedTagIds: string[] = [];

      for (const tagId of tagIds) {
        const tag = await env.DB.prepare("SELECT id FROM idol_tag_master WHERE id = ? AND status != 'removed'").bind(tagId).first();
        if (!tag) continue;

        const [deviceResult] = await env.DB.batch([
          env.DB.prepare(
            `INSERT OR IGNORE INTO device_idol_tag (device_id, idol_id, tag_id, created_at) VALUES (?, ?, ?, ?)`
          ).bind(deviceId, idolId, tagId, now),
          env.DB.prepare(
            `INSERT INTO idol_tags (idol_id, tag_id, vote_count) VALUES (?, ?, 1)
             ON CONFLICT(idol_id, tag_id) DO UPDATE SET vote_count = vote_count + 1`
          ).bind(idolId, tagId),
        ]);

        if (deviceResult.meta.changes > 0) {
          appliedTagIds.push(tagId);
        }
      }

      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ idol_id: idolId, applied_tag_ids: appliedTagIds });
    }

    // ----------------------------------------------------------------
    // DELETE /idols/:idol_id/tags/:tag_id — タグを外す
    // ----------------------------------------------------------------
    const idolTagDeleteMatch = path.match(/^\/idols\/([^/]+)\/tags\/([^/]+)$/);
    if (idolTagDeleteMatch && request.method === "DELETE") {
      const idolId = decodeURIComponent(idolTagDeleteMatch[1]);
      const tagId = decodeURIComponent(idolTagDeleteMatch[2]);
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const [deleted] = await env.DB.batch([
        env.DB.prepare(
          "DELETE FROM device_idol_tag WHERE device_id = ? AND idol_id = ? AND tag_id = ?"
        ).bind(deviceId, idolId, tagId),
        env.DB.prepare(
          `UPDATE idol_tags SET vote_count = MAX(0, vote_count - 1) WHERE idol_id = ? AND tag_id = ?`
        ).bind(idolId, tagId),
        env.DB.prepare(
          `DELETE FROM idol_tags WHERE idol_id = ? AND tag_id = ? AND vote_count <= 0`
        ).bind(idolId, tagId),
      ]);

      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ idol_id: idolId, tag_id: tagId, removed: deleted.meta.changes > 0 });
    }

    // ----------------------------------------------------------------
    // GET /idols/:idol_id/tags — アイドルのタグ一覧
    // ----------------------------------------------------------------
    const idolTagsGetMatch = path.match(/^\/idols\/([^/]+)\/tags$/);
    if (idolTagsGetMatch && request.method === "GET") {
      const idolId = decodeURIComponent(idolTagsGetMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");

      const { results: tags } = await env.DB.prepare(
        `SELECT t.id, t.name, t.color, t.category, it.vote_count
         FROM idol_tags it
         JOIN idol_tag_master t ON t.id = it.tag_id
         WHERE it.idol_id = ? AND t.status != 'removed'
         ORDER BY it.vote_count DESC`
      ).bind(idolId).all();

      let myTagIds: string[] = [];
      if (deviceId) {
        const { results: myRows } = await env.DB.prepare(
          "SELECT tag_id FROM device_idol_tag WHERE device_id = ? AND idol_id = ?"
        ).bind(deviceId, idolId).all<{ tag_id: string }>();
        myTagIds = myRows.map((r) => r.tag_id);
      }

      return json({ tags, my_tag_ids: myTagIds });
    }

    // ==================================================================
    // ユニットタグ (unit_tag_master) — /idol-tags 系と同じ形の別プール。
    // ==================================================================

    // ----------------------------------------------------------------
    // POST /unit-tags — ユニットタグ新規作成
    // ----------------------------------------------------------------
    if (path === "/unit-tags" && request.method === "POST") {
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      let { name, description, category, color } = body as {
        name: string;
        description?: string;
        category?: string;
        color?: string;
      };

      if (!name || typeof name !== "string") return error("name is required");
      name = name.trim();
      if (name.length < 1 || name.length > 30) return error("name must be 1-30 characters");
      const tagFieldsErr = validateTagFields({ description, category, color });
      if (tagFieldsErr) return error(tagFieldsErr);

      const existingByName = await env.DB.prepare("SELECT * FROM unit_tag_master WHERE name = ?").bind(name).first();
      if (existingByName) return json({ tag: existingByName, created: false }, 409);

      // タグ作成レート制限は曲タグ/アイドルタグと共有 (乱立防止という目的が同じなので、
      // ドメインで分けると片方の quota で回避できてしまう)。
      const dateYmd = new Date().toISOString().slice(0, 10);
      await env.DB.prepare(
        `INSERT OR IGNORE INTO device_tag_create_quota (device_id, date_ymd, count) VALUES (?, ?, 0)`
      ).bind(deviceId, dateYmd).run();
      const quotaRow = await env.DB.prepare(
        "SELECT count FROM device_tag_create_quota WHERE device_id = ? AND date_ymd = ?"
      ).bind(deviceId, dateYmd).first<{ count: number }>();
      if ((quotaRow?.count ?? 0) >= 10) return error("Daily tag creation limit reached", 429);

      const candidateId = await resolveSlugFromTable(env.DB, "unit_tag_master", name);
      const now = Math.floor(Date.now() / 1000);

      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO unit_tag_master (id, name, description, category, color, created_by, created_at, updated_at, is_official, status)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'active')`
        ).bind(candidateId, name, description ?? null, category ?? null, color ?? null, deviceId, now, now),
        env.DB.prepare(
          `UPDATE device_tag_create_quota SET count = count + 1
           WHERE device_id = ? AND date_ymd = ?`
        ).bind(deviceId, dateYmd),
      ]);

      const tag = await env.DB.prepare("SELECT * FROM unit_tag_master WHERE id = ?").bind(candidateId).first();
      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ tag, created: true }, 201);
    }

    // ----------------------------------------------------------------
    // GET /unit-tags — ユニットタグ一覧検索
    // ----------------------------------------------------------------
    if (path === "/unit-tags" && request.method === "GET") {
      const search = url.searchParams.get("search") || "";
      const category = url.searchParams.get("category") || "";
      const sort = url.searchParams.get("sort") || "popular";
      const limit = parsePositiveInt(url.searchParams.get("limit"), 1000, 2000);
      const offset = Math.min(10000, Math.max(0, parseInt(url.searchParams.get("offset") || "0") || 0));

      const params: unknown[] = [];
      const conditions: string[] = ["t.status != 'removed'"];

      if (search) {
        conditions.push("t.name LIKE ? ESCAPE '\\'");
        params.push(`%${escapeLike(search)}%`);
      }
      if (category) {
        conditions.push("t.category = ?");
        params.push(category);
      }

      const where = conditions.length ? "WHERE " + conditions.join(" AND ") : "";

      let orderBy = "ORDER BY t.name ASC";
      if (sort === "popular") orderBy = "ORDER BY COALESCE(total_uses, 0) DESC";
      else if (sort === "recent") orderBy = "ORDER BY t.created_at DESC";

      const sql = `
        SELECT t.id, t.name, SUBSTR(t.description, 1, 40) as description_preview,
               t.category, t.color, t.created_at,
               COALESCE((SELECT SUM(vote_count) FROM unit_tags WHERE tag_id = t.id), 0) as total_uses
        FROM unit_tag_master t
        ${where}
        ${orderBy}
        LIMIT ? OFFSET ?
      `;
      params.push(limit, offset);

      const { results } = await env.DB.prepare(sql).bind(...params).all();

      const countSql = `SELECT COUNT(*) as cnt FROM unit_tag_master t ${where}`;
      const countRow = await env.DB.prepare(countSql).bind(...params.slice(0, params.length - 2)).first<{ cnt: number }>();

      return json({ tags: results, total: countRow?.cnt ?? 0 }, 200, {
        "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
      });
    }

    // ----------------------------------------------------------------
    // GET /unit-tags/:id — ユニットタグ詳細
    // ----------------------------------------------------------------
    const unitTagDetailMatch = path.match(/^\/unit-tags\/([^/]+)$/);
    if (unitTagDetailMatch && request.method === "GET") {
      const tagId = decodeURIComponent(unitTagDetailMatch[1]);
      // 削除済み (status='removed') は詳細でも返さない。一覧・付与・曲/アイドル/
      // ユニット別・類似は全て status != 'removed' で除外しているのに、ここだけ
      // 素通しだと安定 URL から削除済みタグが読めてしまう。
      const tag = await env.DB.prepare(
        "SELECT * FROM unit_tag_master WHERE id = ? AND status != 'removed'"
      ).bind(tagId).first();
      if (!tag) return error("Tag not found", 404);

      const { results: units } = await env.DB.prepare(
        `SELECT unit_id, vote_count FROM unit_tags WHERE tag_id = ? ORDER BY vote_count DESC LIMIT 1000`
      ).bind(tagId).all();

      return json({ tag, units }, 200, {
        "Cache-Control": "public, max-age=300, stale-while-revalidate=1800",
      });
    }

    // ----------------------------------------------------------------
    // PUT /unit-tags/:id — ユニットタグ情報更新
    // ----------------------------------------------------------------
    if (unitTagDetailMatch && request.method === "PUT") {
      const tagId = decodeURIComponent(unitTagDetailMatch![1]);
      const authUser = await getAuthUser(request, env);
      if (!authUser) return error("Unauthorized", 401);
      const deviceId = request.headers.get("X-Device-Id") || authUser.uid;

      // is_banned チェック + レート制限 (/tags/:id PUT と同方針。"edit" quota を共有)。
      const [dbUser, rl] = await Promise.all([
        env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
          .bind(authUser.uid)
          .first<{ is_banned: number }>(),
        checkRateLimit(env.DB, authUser.uid, "edit"),
      ]);
      if (dbUser?.is_banned) return error("Banned", 403);
      if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

      const tag = await env.DB.prepare("SELECT * FROM unit_tag_master WHERE id = ?").bind(tagId).first<{
        id: string; description: string | null; status: string;
      }>();
      if (!tag) return error("Tag not found", 404);
      if (tag.status === "removed") return error("Tag has been removed", 403);

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const { description, category, color } = body as {
        description?: string;
        category?: string;
        color?: string;
      };
      const tagFieldsErr = validateTagFields({ description, category, color });
      if (tagFieldsErr) return error(tagFieldsErr);
      const now = Math.floor(Date.now() / 1000);

      if (description !== undefined && description !== tag.description) {
        await env.DB.prepare(
          `INSERT INTO unit_tag_description_history (tag_id, description, description_before, edited_by, edited_at)
           VALUES (?, ?, ?, ?, ?)`
        ).bind(tagId, description ?? null, tag.description ?? null, deviceId, now).run();
      }

      const updates: string[] = ["updated_by = ?", "updated_at = ?"];
      const vals: unknown[] = [deviceId, now];

      if (description !== undefined) { updates.push("description = ?"); vals.push(description); }
      if (category !== undefined) { updates.push("category = ?"); vals.push(category); }
      if (color !== undefined) { updates.push("color = ?"); vals.push(color); }

      vals.push(tagId);
      await env.DB.prepare(`UPDATE unit_tag_master SET ${updates.join(", ")} WHERE id = ?`).bind(...vals).run();

      const updated = await env.DB.prepare("SELECT * FROM unit_tag_master WHERE id = ?").bind(tagId).first();
      return json({ tag: updated });
    }

    // ----------------------------------------------------------------
    // GET /unit-tags/:id/history — 編集履歴
    // ----------------------------------------------------------------
    const unitTagHistoryMatch = path.match(/^\/unit-tags\/([^/]+)\/history$/);
    if (unitTagHistoryMatch && request.method === "GET") {
      const tagId = decodeURIComponent(unitTagHistoryMatch[1]);
      const { results } = await env.DB.prepare(
        `SELECT id, tag_id,
                description AS description_after,
                description_before,
                edited_by, edited_at
         FROM unit_tag_description_history
         WHERE tag_id = ? ORDER BY edited_at DESC LIMIT 30`
      ).bind(tagId).all();
      return json(results);
    }

    // ----------------------------------------------------------------
    // DELETE /unit-tags/:id — ユニットタグの削除 (admin 限定 → status='removed')
    // ----------------------------------------------------------------
    // 「きいた」「持ってる」のような**個人的なメモ**は共有タグの語彙に混ざると
    // 他ユーザーには意味が無く一覧を汚す。そういう用途にはアプリ内の PersonalTag
    // (端末ローカル専用・サーバー非送信) がある。共有プールから外すのはモデレーター判断。
    //
    // 通報 3 件で付く under_review は「印」でしかなく、読み取り側は
    // status != 'removed' しか見ていない (= under_review でも表示され続ける)。
    // 実際に消せるのはこの status='removed' だけ。
    //
    // 物理削除ではなく soft delete にする。付与実績 (unit_tags) は残すので、
    // 誤操作なら status を戻すだけで復旧できる。
    const unitTagMasterDeleteMatch = path.match(/^\/unit-tags\/([^/]+)$/);
    if (unitTagMasterDeleteMatch && request.method === "DELETE") {
      const tagId = decodeURIComponent(unitTagMasterDeleteMatch[1]);
      const user = await getAuthUser(request, env);
      if (!user) return error("Unauthorized", 401);
      if (!(await checkIsAdmin(env, user.uid))) return error("Forbidden", 403);

      const tag = await env.DB.prepare(
        "SELECT id, status FROM unit_tag_master WHERE id = ?"
      )
        .bind(tagId)
        .first<{ id: string; status: string }>();

      if (!tag) return error("Tag not found", 404);
      // 冪等: 既に removed なら何もせず同じ応答を返す
      if (tag.status === "removed") return json({ id: tagId, status: "removed" });

      await env.DB.prepare("UPDATE unit_tag_master SET status = 'removed' WHERE id = ?")
        .bind(tagId)
        .run();

      return json({ id: tagId, status: "removed" });
    }

    // ----------------------------------------------------------------
    // POST /unit-tags/:id/report — ユニットタグ通報
    // ----------------------------------------------------------------
    const unitTagReportMatch = path.match(/^\/unit-tags\/([^/]+)\/report$/);
    if (unitTagReportMatch && request.method === "POST") {
      const tagId = decodeURIComponent(unitTagReportMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const tag = await env.DB.prepare("SELECT id FROM unit_tag_master WHERE id = ?").bind(tagId).first();
      if (!tag) return error("Tag not found", 404);

      const today = new Date().toISOString().slice(0, 10);
      const alreadyReported = await env.DB.prepare(
        `SELECT 1 FROM unit_tag_reports WHERE tag_id = ? AND reported_by = ? AND DATE(reported_at, 'unixepoch') = ?`
      ).bind(tagId, deviceId, today).first();
      if (alreadyReported) return error("Already reported today", 429);

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const now = Math.floor(Date.now() / 1000);
      await env.DB.prepare(
        `INSERT INTO unit_tag_reports (tag_id, reported_by, reason, reported_at) VALUES (?, ?, ?, ?)`
      ).bind(tagId, deviceId, body.reason ?? null, now).run();

      const reportCount = await env.DB.prepare(
        "SELECT COUNT(*) as cnt FROM unit_tag_reports WHERE tag_id = ?"
      ).bind(tagId).first<{ cnt: number }>();
      const total = reportCount?.cnt ?? 1;

      if (total >= REPORT_THRESHOLD) {
        await env.DB.prepare(
          "UPDATE unit_tag_master SET status = 'under_review' WHERE id = ? AND status = 'active'"
        ).bind(tagId).run();
      }

      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ ok: true, total_reports: total });
    }

    // ----------------------------------------------------------------
    // POST /units/:unit_id/tags — ユニットにタグを付ける (idol 版と同じロジック)
    // ----------------------------------------------------------------
    const unitTagsPostMatch = path.match(/^\/units\/([^/]+)\/tags$/);
    if (unitTagsPostMatch && request.method === "POST") {
      const unitId = decodeURIComponent(unitTagsPostMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const body = (await request.json().catch(() => null)) as any;
      if (body === null) return error("invalid JSON body");
      const tagIds = body.tag_ids as string[];
      if (!Array.isArray(tagIds) || tagIds.length === 0) return error("tag_ids must be a non-empty array");

      const now = Math.floor(Date.now() / 1000);
      const appliedTagIds: string[] = [];

      for (const tagId of tagIds) {
        const tag = await env.DB.prepare("SELECT id FROM unit_tag_master WHERE id = ? AND status != 'removed'").bind(tagId).first();
        if (!tag) continue;

        const [deviceResult] = await env.DB.batch([
          env.DB.prepare(
            `INSERT OR IGNORE INTO device_unit_tag (device_id, unit_id, tag_id, created_at) VALUES (?, ?, ?, ?)`
          ).bind(deviceId, unitId, tagId, now),
          env.DB.prepare(
            `INSERT INTO unit_tags (unit_id, tag_id, vote_count) VALUES (?, ?, 1)
             ON CONFLICT(unit_id, tag_id) DO UPDATE SET vote_count = vote_count + 1`
          ).bind(unitId, tagId),
        ]);

        if (deviceResult.meta.changes > 0) {
          appliedTagIds.push(tagId);
        }
      }

      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ unit_id: unitId, applied_tag_ids: appliedTagIds });
    }

    // ----------------------------------------------------------------
    // DELETE /units/:unit_id/tags/:tag_id — タグを外す
    // ----------------------------------------------------------------
    const unitTagDeleteMatch = path.match(/^\/units\/([^/]+)\/tags\/([^/]+)$/);
    if (unitTagDeleteMatch && request.method === "DELETE") {
      const unitId = decodeURIComponent(unitTagDeleteMatch[1]);
      const tagId = decodeURIComponent(unitTagDeleteMatch[2]);
      const deviceId = request.headers.get("X-Device-Id");
      if (!deviceId) return error("X-Device-Id header is required");

      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipDry = await dryCheckIpRateLimit(env.DB, ip);
      if (!ipDry.allowed) {
        return rateLimitSimple();
      }

      const [deleted] = await env.DB.batch([
        env.DB.prepare(
          "DELETE FROM device_unit_tag WHERE device_id = ? AND unit_id = ? AND tag_id = ?"
        ).bind(deviceId, unitId, tagId),
        env.DB.prepare(
          `UPDATE unit_tags SET vote_count = MAX(0, vote_count - 1) WHERE unit_id = ? AND tag_id = ?`
        ).bind(unitId, tagId),
        env.DB.prepare(
          `DELETE FROM unit_tags WHERE unit_id = ? AND tag_id = ? AND vote_count <= 0`
        ).bind(unitId, tagId),
      ]);

      await commitIpRateLimit(env.DB, ip, ipDry.bucket);
      return json({ unit_id: unitId, tag_id: tagId, removed: deleted.meta.changes > 0 });
    }

    // ----------------------------------------------------------------
    // GET /units/:unit_id/tags — ユニットのタグ一覧
    // ----------------------------------------------------------------
    const unitTagsGetMatch = path.match(/^\/units\/([^/]+)\/tags$/);
    if (unitTagsGetMatch && request.method === "GET") {
      const unitId = decodeURIComponent(unitTagsGetMatch[1]);
      const deviceId = request.headers.get("X-Device-Id");

      const { results: tags } = await env.DB.prepare(
        `SELECT t.id, t.name, t.color, t.category, ut.vote_count
         FROM unit_tags ut
         JOIN unit_tag_master t ON t.id = ut.tag_id
         WHERE ut.unit_id = ? AND t.status != 'removed'
         ORDER BY ut.vote_count DESC`
      ).bind(unitId).all();

      let myTagIds: string[] = [];
      if (deviceId) {
        const { results: myRows } = await env.DB.prepare(
          "SELECT tag_id FROM device_unit_tag WHERE device_id = ? AND unit_id = ?"
        ).bind(deviceId, unitId).all<{ tag_id: string }>();
        myTagIds = myRows.map((r) => r.tag_id);
      }

      return json({ tags, my_tag_ids: myTagIds });
    }

    // ----------------------------------------------------------------
    // GET /units/:unit_id/similar — タグが似ているユニット (この人が好きな人にはこのユニットもおすすめ)
    //   共有タグ数を第一キー、共有タグの票数合計を第二キーで近い順に並べる。
    //   D1 には units マスタテーブルが存在しない (idols 版と同様、マスタの真実は
    //   クライアント bundle の master.sqlite / CloudKit) ため、unit_id は不透明文字列として
    //   集計するのみ。
    // ----------------------------------------------------------------
    const unitSimilarMatch = path.match(/^\/units\/([^/]+)\/similar$/);
    if (unitSimilarMatch && request.method === "GET") {
      const unitId = decodeURIComponent(unitSimilarMatch[1]);
      const limitParam = parseInt(url.searchParams.get("limit") ?? "10", 10);
      const limit = Math.min(Math.max(Number.isFinite(limitParam) ? limitParam : 10, 1), 30);

      const { results: units } = await env.DB.prepare(
        `SELECT ut2.unit_id AS unit_id,
                COUNT(*) AS shared_tags,
                SUM(ut2.vote_count) AS score
         FROM unit_tags ut1
         JOIN unit_tags ut2 ON ut2.tag_id = ut1.tag_id AND ut2.unit_id != ut1.unit_id
         JOIN unit_tag_master m ON m.id = ut1.tag_id AND m.status != 'removed'
         WHERE ut1.unit_id = ?
         GROUP BY ut2.unit_id
         ORDER BY shared_tags DESC, score DESC
         LIMIT ?`
      ).bind(unitId, limit).all();

      return json({ unit_id: unitId, units }, 200, {
        "Cache-Control": "public, max-age=600, stale-while-revalidate=3600",
      });
    }

    // ----------------------------------------------------------------
    // GET /songs/:song_id/similar — タグが似ている楽曲 (この曲が好きな人にはこれもおすすめ)
    //
    //   減衰つき Jaccard 係数で「近さ」を出す:
    //       score = shared / (tags_a + tags_b - shared + SIMILARITY_DAMPING)
    //
    //   旧実装は共有タグ数 → 相手の票数合計の順で並べていたが、これだと
    //   「タグがたくさん付いている有名曲」が何にでも上位に出る (共有数も票数も
    //   タグ数に比例して増えるため)。かといって素の Jaccard にすると今度は
    //   「タグが1〜2個しかない曲がたまたま全部一致して 100%」が勝ってしまう。
    //   タグはユーザー投稿のみで自動付与しない方針なのでタグ数の少ない曲が多数派
    //   であり、この小サンプル事故が例外ではなく主流になる。
    //   分母に定数を足して平滑化すると、件数が少ないうちは慎重に、タグが貯まるほど
    //   素の Jaccard に近づく。
    //
    //   ここでは候補をスコア順に返すだけで、実際に何件見せるか / どれを見せるかは
    //   クライアントが決める (毎回同じ並びにならないよう重み付き抽選する)。
    //   サーバ応答は決定的なままなのでエッジキャッシュがそのまま効く。
    // ----------------------------------------------------------------
    const songSimilarMatch = path.match(/^\/songs\/([^/]+)\/similar$/);
    if (songSimilarMatch && request.method === "GET") {
      const songId = decodeURIComponent(songSimilarMatch[1]);
      const limitParam = parseInt(url.searchParams.get("limit") ?? "10", 10);
      const limit = Math.min(Math.max(Number.isFinite(limitParam) ? limitParam : 10, 1), 50);

      const { results: songs } = await env.DB.prepare(
        `WITH a_tags AS (
           SELECT st.tag_id
           FROM song_tags st
           JOIN tags t ON t.id = st.tag_id AND t.status != 'removed'
           WHERE st.song_id = ?
         )
         SELECT st2.song_id AS song_id,
                COUNT(*) AS shared_tags,
                SUM(st2.vote_count) AS vote_score,
                CAST(COUNT(*) AS REAL) / (
                  (SELECT COUNT(*) FROM a_tags)
                  + (SELECT COUNT(*) FROM song_tags s
                     JOIN tags t2 ON t2.id = s.tag_id AND t2.status != 'removed'
                     WHERE s.song_id = st2.song_id)
                  - COUNT(*) + ?
                ) AS score
         FROM song_tags st2
         JOIN a_tags ON a_tags.tag_id = st2.tag_id
         WHERE st2.song_id != ?
         GROUP BY st2.song_id
         ORDER BY score DESC, shared_tags DESC
         LIMIT ?`
      ).bind(songId, SIMILARITY_DAMPING, songId, limit).all();

      // タグ類似は完全にユーザー非依存 (my_* フラグを一切含まない集計のみ)。
      // タグ付けの分布で決まり変化が非常に緩やかなので、エッジ (Cloudflare) で
      // 全ユーザ共有キャッシュして D1 負荷を削減。曲詳細を開くたびに叩かれるため
      // 効果が大きい。鮮度は粗くてよい (max-age 10分 + SWR 1時間)。
      return json({ song_id: songId, songs }, 200, {
        "Cache-Control": "public, max-age=600, stale-while-revalidate=3600",
      });
    }

    // ----------------------------------------------------------------
    // GET /idols/:idol_id/similar — タグが似ているアイドル (この人が好きな人にはこの人もおすすめ)
    //   共有タグ数を第一キー、共有タグの票数合計を第二キーで近い順に並べる。
    //   D1 には idols マスタテーブルが存在しない (0019 で削除済み。マスタの真実は
    //   クライアント bundle の master.sqlite / CloudKit) ため、songs 版と同じく
    //   idol_id は不透明文字列として集計するのみで、外部ゲスト演者の除外はしない
    //   (is_external はクライアント側の master.sqlite にしか無い情報)。
    // ----------------------------------------------------------------
    const idolSimilarMatch = path.match(/^\/idols\/([^/]+)\/similar$/);
    if (idolSimilarMatch && request.method === "GET") {
      const idolId = decodeURIComponent(idolSimilarMatch[1]);
      const limitParam = parseInt(url.searchParams.get("limit") ?? "10", 10);
      const limit = Math.min(Math.max(Number.isFinite(limitParam) ? limitParam : 10, 1), 30);

      const { results: idols } = await env.DB.prepare(
        `SELECT it2.idol_id AS idol_id,
                COUNT(*) AS shared_tags,
                SUM(it2.vote_count) AS score
         FROM idol_tags it1
         JOIN idol_tags it2 ON it2.tag_id = it1.tag_id AND it2.idol_id != it1.idol_id
         JOIN idol_tag_master m ON m.id = it1.tag_id AND m.status != 'removed'
         WHERE it1.idol_id = ?
         GROUP BY it2.idol_id
         ORDER BY shared_tags DESC, score DESC
         LIMIT ?`
      ).bind(idolId, limit).all();

      // タグ類似は完全にユーザー非依存 (my_* フラグを一切含まない集計のみ)。songs 版と同じ理由で
      // エッジ (Cloudflare) で全ユーザ共有キャッシュして D1 負荷を削減する。
      return json({ idol_id: idolId, idols }, 200, {
        "Cache-Control": "public, max-age=600, stale-while-revalidate=3600",
      });
    }

  return null;
}
