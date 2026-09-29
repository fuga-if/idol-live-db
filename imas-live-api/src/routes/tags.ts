// routes/tags.ts — ユーザータグ API (曲 / アイドル / ユニットの 3 プール + 類似)
//
// 3 つのプールは同じ形をしている。
//   語彙 (マスタ):  POST/GET <master>、GET/PUT/DELETE <master>/:id、
//                   GET <master>/:id/history、POST <master>/:id/report
//   対象への付与:   POST/GET <entity>/:id/tags、DELETE <entity>/:id/tags/:tag_id
// なので、表の名前と応答のキーだけを TagPool に持たせ、ハンドラは 1 本にしてある。
// プールごとに違うのは次の 2 点だけで、どちらも TagPool の項目で明示している。
//   - recount: 曲だけ、付与・取り外しのたびに類似曲の分母 (song_tag_counts) を数え直す
//   - similar: 類似の並べ方と候補の上限。曲は減衰つき Jaccard (上限 50)、
//              アイドル・ユニットは共有タグ数 → 票数合計 (上限 30)
//
// ⚠️ 応答のキー・ステータス・Cache-Control と SQL は、1 本にする前の 3 つの複製と同じ
//    (そのあと Q-10 で、応答から作成者・編集者の ID を外し、履歴の編集者を先頭 8 文字にした)。
//    表の名前は TagPool の定数だけを埋め込む (ユーザーの入力は常にバインドする)。

import { getAuthUser } from "../auth";
import { maskUserRef } from "../masking";
import { checkRateLimit, commitIpRateLimit } from "../rate_limit";
import { checkIsAdmin } from "../users";
import { parsePositiveInt, escapeLike } from "../validation";
import type { RouteContext } from "./context";
import {
  decodePathParam,
  readJsonBody,
  requireActiveUser,
  requireDeviceWrite,
  type JsonFields,
} from "./guards";

// ---------------------------------------------------------------------------
// プールの定義
// ---------------------------------------------------------------------------

interface TagPool {
  /** 語彙 (マスタ) の API の接頭辞。 */
  masterPath: string;
  /** 語彙の表。 */
  masterTable: "tags" | "idol_tag_master" | "unit_tag_master";
  /** 説明の編集履歴の表。 */
  historyTable: string;
  /** 通報の表。 */
  reportTable: string;
  /** タグを付ける対象の API の接頭辞。 */
  entityPath: string;
  /** 対象の ID の列名。付与・類似の応答のキーにもなる。 */
  entityKey: "song_id" | "idol_id" | "unit_id";
  /** 対象ごとの票数の表。 */
  linkTable: string;
  /** 端末ごとの付与の記録 (同じ端末の再送を数えないための表)。 */
  deviceTable: string;
  /** GET <master>/:id と類似の応答で、対象を並べるキー。 */
  listKey: "songs" | "idols" | "units";
  /** 付与・取り外しの batch の末尾に足す文。曲だけ (類似曲の分母を数え直す)。 */
  recount?: (db: D1Database, entityId: string) => D1PreparedStatement;
  /** GET <entity>/:id/similar の並べ方と、limit の上限。 */
  similar: {
    maxLimit: number;
    rows: (db: D1Database, entityId: string, limit: number) => Promise<unknown[]>;
  };
  routes: {
    tag: RegExp;
    history: RegExp;
    report: RegExp;
    entityTags: RegExp;
    entityTag: RegExp;
    similar: RegExp;
  };
}

function poolRoutes(masterPath: string, entityPath: string): TagPool["routes"] {
  return {
    tag: new RegExp(`^${masterPath}/([^/]+)$`),
    history: new RegExp(`^${masterPath}/([^/]+)/history$`),
    report: new RegExp(`^${masterPath}/([^/]+)/report$`),
    entityTags: new RegExp(`^${entityPath}/([^/]+)/tags$`),
    entityTag: new RegExp(`^${entityPath}/([^/]+)/tags/([^/]+)$`),
    similar: new RegExp(`^${entityPath}/([^/]+)/similar$`),
  };
}

/**
 * 1 曲ぶんの song_tag_counts を数え直す文を作る。
 *
 * 類似曲スコアの分母 (相手の曲のタグ総数) をここに持たせている。
 * タグ付け / 取り外しの batch に混ぜて、その曲だけを数え直す (数行の読み取りで済む)。
 * タグ自体が removed になった場合は全曲に効くので、日次 cron
 * (scheduled.ts の refreshTagCounts) が全体を数え直して辻褄を合わせる。
 */
function recountSongTags(db: D1Database, songId: string): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO song_tag_counts (song_id, tag_count)
       VALUES (?, (SELECT COUNT(*)
                     FROM song_tags s
                     JOIN tags t ON t.id = s.tag_id AND t.status != 'removed'
                    WHERE s.song_id = ?))
       ON CONFLICT(song_id) DO UPDATE SET tag_count = excluded.tag_count`
    )
    .bind(songId, songId);
}

const SONG_TAGS: TagPool = {
  masterPath: "/tags",
  masterTable: "tags",
  historyTable: "tag_description_history",
  reportTable: "tag_reports",
  entityPath: "/songs",
  entityKey: "song_id",
  linkTable: "song_tags",
  deviceTable: "device_song_tag",
  listKey: "songs",
  recount: recountSongTags,
  similar: { maxLimit: 50, rows: (db, songId, limit) => similarSongRows(db, songId, limit) },
  routes: poolRoutes("/tags", "/songs"),
};

// アイドル・ユニットのタグは曲タグとは別の語彙 (性格/属性 vs ムード/ジャンル) なので、
// マスタごと別の表に分けてある。
const IDOL_TAGS: TagPool = {
  masterPath: "/idol-tags",
  masterTable: "idol_tag_master",
  historyTable: "idol_tag_description_history",
  reportTable: "idol_tag_reports",
  entityPath: "/idols",
  entityKey: "idol_id",
  linkTable: "idol_tags",
  deviceTable: "device_idol_tag",
  listKey: "idols",
  similar: { maxLimit: 30, rows: (db, idolId, limit) => sharedTagRows(db, IDOL_TAGS, idolId, limit) },
  routes: poolRoutes("/idol-tags", "/idols"),
};

const UNIT_TAGS: TagPool = {
  masterPath: "/unit-tags",
  masterTable: "unit_tag_master",
  historyTable: "unit_tag_description_history",
  reportTable: "unit_tag_reports",
  entityPath: "/units",
  entityKey: "unit_id",
  linkTable: "unit_tags",
  deviceTable: "device_unit_tag",
  listKey: "units",
  similar: { maxLimit: 30, rows: (db, unitId, limit) => sharedTagRows(db, UNIT_TAGS, unitId, limit) },
  routes: poolRoutes("/unit-tags", "/units"),
};

const TAG_POOLS: readonly TagPool[] = [SONG_TAGS, IDOL_TAGS, UNIT_TAGS];

// ---------------------------------------------------------------------------
// 語彙の項目の検証
// ---------------------------------------------------------------------------

/**
 * 応答に載せるタグの列。作成者・編集者 (created_by / updated_by) は端末 ID か uid なので載せない
 * (公開の応答で、誰がどの語彙を作ったかを追えないように。表には残す)。
 */
const TAG_COLUMNS = "id, name, description, category, color, created_at, updated_at, is_official, status";

/** 通報がこの件数に達したら under_review の印を付ける。 */
const REPORT_THRESHOLD = 3;

const TAG_HEX_COLOR_RE = /^#[0-9a-fA-F]{6}$/;
const TAG_NAME_MAX_LEN = 30;
const TAG_DESCRIPTION_MAX_LEN = 300;
const TAG_CATEGORY_MAX_LEN = 30;
/** 1 端末が 1 日に作れるタグの数 (3 プール共有。プールで分けると片方の枠で回避できてしまう)。 */
const DAILY_TAG_CREATE_LIMIT = 10;

/** 説明・分類・色。undefined は「指定なし」(PUT では更新しない)、null は「消す」。 */
interface TagFields {
  description?: string | null;
  category?: string | null;
  color?: string | null;
}

/**
 * POST (新規作成) と PUT (更新) 共通の description / category / color の検証。
 * だめなら理由の文字列を返す。色の空文字は、そのまま保存する (従来どおり)。
 */
function parseTagFields(body: JsonFields): TagFields | string {
  const { description, category, color } = body;
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
  // ここまでで 3 つとも string / null / undefined のどれかに絞れている。
  return {
    description: description as TagFields["description"],
    category: category as TagFields["category"],
    color: color as TagFields["color"],
  };
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

/** name から、語彙の表でまだ使われていない id (slug) を決める。 */
async function resolveSlugFromTable(
  db: D1Database,
  table: TagPool["masterTable"],
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

function nowSec(): number {
  return Math.floor(Date.now() / 1000);
}

// ---------------------------------------------------------------------------
// 曲詳細の束ね (GET /songs/:id/detail) と共有する取得ロジック
//
// ⚠️ 「対象のタグ一覧」と「タグ類似曲」の唯一の実装。<entity>/:id/tags・/songs/:id/similar と
//    routes/song_detail.ts の両方がこれを呼ぶ。片方だけ直して形が食い違う事故を防ぐため、
//    SQL もレスポンスのキーもここ以外に書かないこと。
// ---------------------------------------------------------------------------

/** GET <entity>/:id/tags の本体。deviceId が無ければ my_tag_ids は空配列。 */
async function fetchEntityTagList(
  db: D1Database,
  pool: TagPool,
  entityId: string,
  deviceId: string | null
): Promise<{ tags: unknown[]; my_tag_ids: string[] }> {
  const { results: tags } = await db
    .prepare(
      `SELECT t.id, t.name, t.color, t.category, l.vote_count
         FROM ${pool.linkTable} l
         JOIN ${pool.masterTable} t ON t.id = l.tag_id
        WHERE l.${pool.entityKey} = ? AND t.status != 'removed'
        ORDER BY l.vote_count DESC`
    )
    .bind(entityId)
    .all();

  let myTagIds: string[] = [];
  if (deviceId) {
    const { results: myRows } = await db
      .prepare(`SELECT tag_id FROM ${pool.deviceTable} WHERE device_id = ? AND ${pool.entityKey} = ?`)
      .bind(deviceId, entityId)
      .all<{ tag_id: string }>();
    myTagIds = myRows.map((r) => r.tag_id);
  }

  return { tags, my_tag_ids: myTagIds };
}

/** GET /songs/:song_id/tags の本体 (曲詳細の束ねからも呼ぶ)。 */
export function fetchSongTagList(
  db: D1Database,
  songId: string,
  deviceId: string | null
): Promise<{ tags: unknown[]; my_tag_ids: string[] }> {
  return fetchEntityTagList(db, SONG_TAGS, songId, deviceId);
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
 * 曲の類似 (減衰つき Jaccard の降順)。limit は呼び出し側でクランプ済み。
 *
 * 分母の「相手の曲のタグ総数」は song_tag_counts から引く。かつては候補 1 件ごとに
 * 相関副問い合わせで数え直しており、候補が数百件出る曲では 1 回 16,800 行
 * (平均 5,497 行 ≒ song_tags 全 4,717 行) を読んで、これだけで D1 無料枠
 * 500 万行/日 の 40% を消費していた。数えるのをやめて引くだけにしても
 * スコア式は変わらないので、返る類似曲も並び順も従来と完全に同一。
 *
 * COALESCE は song_tag_counts に行が無いときの保険。日次 cron と
 * タグ付け/取り外しの両方で更新しているので通常は当たらない。
 */
async function similarSongRows(db: D1Database, songId: string, limit: number): Promise<unknown[]> {
  const { results } = await db
    .prepare(
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
                  + COALESCE(c.tag_count, COUNT(*))
                  - COUNT(*) + ?
                ) AS score
         FROM song_tags st2
         JOIN a_tags ON a_tags.tag_id = st2.tag_id
         LEFT JOIN song_tag_counts c ON c.song_id = st2.song_id
         WHERE st2.song_id != ?
         GROUP BY st2.song_id
         ORDER BY score DESC, shared_tags DESC
         LIMIT ?`
    )
    .bind(songId, SIMILARITY_DAMPING, songId, limit)
    .all();
  return results;
}

/**
 * アイドル・ユニットの類似 (共有タグ数を第一キー、共有タグの票数合計を第二キーの降順)。
 * D1 にはアイドル・ユニットのマスタが無い (0019 で削除済み。マスタの正は CloudKit と
 * 端末の master.sqlite) ので、ID は不透明な文字列として集計するだけ。外部ゲスト演者の
 * 除外もしない (is_external は端末の master.sqlite にしか無い)。
 */
async function sharedTagRows(
  db: D1Database,
  pool: TagPool,
  entityId: string,
  limit: number
): Promise<unknown[]> {
  const key = pool.entityKey;
  const { results } = await db
    .prepare(
      `SELECT l2.${key} AS ${key},
              COUNT(*) AS shared_tags,
              SUM(l2.vote_count) AS score
       FROM ${pool.linkTable} l1
       JOIN ${pool.linkTable} l2 ON l2.tag_id = l1.tag_id AND l2.${key} != l1.${key}
       JOIN ${pool.masterTable} m ON m.id = l1.tag_id AND m.status != 'removed'
       WHERE l1.${key} = ?
       GROUP BY l2.${key}
       ORDER BY shared_tags DESC, score DESC
       LIMIT ?`
    )
    .bind(entityId, limit)
    .all();
  return results;
}

/** GET /songs/:song_id/similar の本体 (完全にユーザー非依存。曲詳細の束ねからも呼ぶ)。 */
export async function fetchSimilarSongs(
  db: D1Database,
  songId: string,
  limit: number
): Promise<{ song_id: string; songs: unknown[] }> {
  return { song_id: songId, songs: await similarSongRows(db, songId, limit) };
}

/** 類似の limit のクランプ (既定 fallback、1 以上 max 以下)。曲詳細の束ねと揃えるため関数化。 */
export function clampSimilarLimit(
  raw: string | null,
  fallback = 10,
  max = SONG_TAGS.similar.maxLimit
): number {
  const parsed = parseInt(raw ?? String(fallback), 10);
  return Math.min(Math.max(Number.isFinite(parsed) ? parsed : fallback, 1), max);
}

/** タグ類似の応答ヘッダ。ユーザー非依存なのでエッジで全ユーザ共有キャッシュできる。 */
export const SIMILAR_CACHE_HEADERS: Record<string, string> = {
  "Cache-Control": "public, max-age=600, stale-while-revalidate=3600",
};

// ---------------------------------------------------------------------------
// ルーター
// ---------------------------------------------------------------------------

/**
 * /tags・/idol-tags・/unit-tags、/{songs,idols,units}/:id/tags・/similar と
 * /tags/activity を処理する。どれにも一致しなければ null を返し、呼び出し元の
 * if チェーンへ処理を戻す。
 */
export async function handleTags(ctx: RouteContext): Promise<Response | null> {
  // 汎用の GET /tags/:id より先に見る ("activity" がタグ id として食われないように)。
  if (ctx.path === "/tags/activity" && ctx.request.method === "GET") return tagActivity(ctx);
  for (const pool of TAG_POOLS) {
    const res = await handleTagPool(ctx, pool);
    if (res) return res;
  }
  return null;
}

async function handleTagPool(ctx: RouteContext, pool: TagPool): Promise<Response | null> {
  const { path } = ctx;
  const method = ctx.request.method;
  const { routes } = pool;
  let m: RegExpMatchArray | null;

  if (path === pool.masterPath) {
    if (method === "POST") return createTag(ctx, pool);
    if (method === "GET") return listTags(ctx, pool);
    return null;
  }
  if ((m = path.match(routes.tag))) {
    if (method === "GET") return getTag(ctx, pool, m[1]);
    if (method === "PUT") return updateTag(ctx, pool, m[1]);
    if (method === "DELETE") return removeTag(ctx, pool, m[1]);
    return null;
  }
  if ((m = path.match(routes.history))) return method === "GET" ? tagHistory(ctx, pool, m[1]) : null;
  if ((m = path.match(routes.report))) return method === "POST" ? reportTag(ctx, pool, m[1]) : null;
  if ((m = path.match(routes.entityTags))) {
    if (method === "POST") return applyTags(ctx, pool, m[1]);
    if (method === "GET") return listEntityTags(ctx, pool, m[1]);
    return null;
  }
  if ((m = path.match(routes.entityTag))) {
    return method === "DELETE" ? detachTag(ctx, pool, m[1], m[2]) : null;
  }
  if ((m = path.match(routes.similar))) return method === "GET" ? listSimilar(ctx, pool, m[1]) : null;
  return null;
}

// ---------------------------------------------------------------------------
// 語彙 (マスタ)
// ---------------------------------------------------------------------------

/** POST <master> — タグの新規作成。1 端末 1 日 DAILY_TAG_CREATE_LIMIT 件まで (3 プール共有)。 */
async function createTag(ctx: RouteContext, pool: TagPool): Promise<Response> {
  const { env, json, error } = ctx;
  const guard = await requireDeviceWrite(ctx);
  if (guard instanceof Response) return guard;
  const { deviceId, ipQuota } = guard;

  const body = await readJsonBody(ctx);
  if (body instanceof Response) return body;
  const rawName = body.name;
  if (!rawName || typeof rawName !== "string") return error("name is required");
  const name = rawName.trim();
  if (name.length < 1 || name.length > TAG_NAME_MAX_LEN) return error("name must be 1-30 characters");
  const fields = parseTagFields(body);
  if (typeof fields === "string") return error(fields);

  // 同名チェック
  const existingByName = await env.DB.prepare(`SELECT ${TAG_COLUMNS} FROM ${pool.masterTable} WHERE name = ?`)
    .bind(name)
    .first();
  if (existingByName) return json({ tag: existingByName, created: false }, 409);

  // 作成数の上限 (INSERT OR IGNORE で行を用意して読む。加算はタグの INSERT と同じ batch)
  const dateYmd = new Date().toISOString().slice(0, 10);
  await env.DB.prepare(
    `INSERT OR IGNORE INTO device_tag_create_quota (device_id, date_ymd, count) VALUES (?, ?, 0)`
  ).bind(deviceId, dateYmd).run();
  const quotaRow = await env.DB.prepare(
    "SELECT count FROM device_tag_create_quota WHERE device_id = ? AND date_ymd = ?"
  ).bind(deviceId, dateYmd).first<{ count: number }>();
  if ((quotaRow?.count ?? 0) >= DAILY_TAG_CREATE_LIMIT) {
    return error("Daily tag creation limit reached", 429);
  }

  const candidateId = await resolveSlugFromTable(env.DB, pool.masterTable, name);
  const now = nowSec();

  // tag INSERT + quota++ を batch で原子化
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO ${pool.masterTable} (id, name, description, category, color, created_by, created_at, updated_at, is_official, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'active')`
    ).bind(
      candidateId, name, fields.description ?? null, fields.category ?? null, fields.color ?? null,
      deviceId, now, now
    ),
    env.DB.prepare(
      `UPDATE device_tag_create_quota SET count = count + 1
       WHERE device_id = ? AND date_ymd = ?`
    ).bind(deviceId, dateYmd),
  ]);

  const tag = await env.DB.prepare(`SELECT ${TAG_COLUMNS} FROM ${pool.masterTable} WHERE id = ?`)
    .bind(candidateId)
    .first();
  await commitIpRateLimit(env.DB, ipQuota);
  return json({ tag, created: true }, 201);
}

/** GET <master> — タグ一覧 (検索・分類・並べ替え)。 */
async function listTags(ctx: RouteContext, pool: TagPool): Promise<Response> {
  const { env, url, json } = ctx;
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
  const where = "WHERE " + conditions.join(" AND ");

  let orderBy = "ORDER BY t.name ASC";
  if (sort === "popular") orderBy = "ORDER BY COALESCE(total_uses, 0) DESC";
  else if (sort === "recent") orderBy = "ORDER BY t.created_at DESC";

  const { results } = await env.DB.prepare(
    `SELECT t.id, t.name, SUBSTR(t.description, 1, 40) as description_preview,
            t.category, t.color, t.created_at,
            COALESCE((SELECT SUM(vote_count) FROM ${pool.linkTable} WHERE tag_id = t.id), 0) as total_uses
       FROM ${pool.masterTable} t
       ${where}
       ${orderBy}
       LIMIT ? OFFSET ?`
  ).bind(...params, limit, offset).all();

  const countRow = await env.DB.prepare(`SELECT COUNT(*) as cnt FROM ${pool.masterTable} t ${where}`)
    .bind(...params)
    .first<{ cnt: number }>();

  // タグ一覧はユーザー非依存・変化が緩やかなので短期キャッシュを許可
  // (タグ追加 UI の再オープン高速化。max-age 60s + SWR 300s)。
  return json({ tags: results, total: countRow?.cnt ?? 0 }, 200, {
    "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
  });
}

/** GET <master>/:id — タグ詳細と、付いている対象の全件 (票数の降順)。 */
async function getTag(ctx: RouteContext, pool: TagPool, rawId: string): Promise<Response> {
  const { env, json, error } = ctx;
  const tagId = decodePathParam(ctx, rawId, "tag_id");
  if (tagId instanceof Response) return tagId;
  // 削除済み (status='removed') は詳細でも返さない。一覧・付与・対象別・類似は全て
  // status != 'removed' で除外しているので、安定 URL から読めてしまわないようにそろえる。
  const tag = await env.DB.prepare(
    `SELECT ${TAG_COLUMNS} FROM ${pool.masterTable} WHERE id = ? AND status != 'removed'`
  ).bind(tagId).first();
  if (!tag) return error("Tag not found", 404);

  // 付いている対象は全件返す (旧 LIMIT 50 だと絞り込み一覧・件数のバッジが欠けていた)。
  const { results } = await env.DB.prepare(
    `SELECT ${pool.entityKey}, vote_count FROM ${pool.linkTable}
      WHERE tag_id = ? ORDER BY vote_count DESC LIMIT 1000`
  ).bind(tagId).all();

  // ユーザー非依存・変化が緩やか。エッジで全ユーザ共有キャッシュ (max-age 5分 + SWR 30分。
  // 自分のタグ付けはクライアント側のキャッシュがすぐ捨てるので、この鮮度で足りる)。
  return json({ tag, [pool.listKey]: results }, 200, {
    "Cache-Control": "public, max-age=300, stale-while-revalidate=1800",
  });
}

/** PUT <master>/:id — 説明・分類・色の更新 (ログイン必須)。説明が変われば前後を履歴に積む。 */
async function updateTag(ctx: RouteContext, pool: TagPool, rawId: string): Promise<Response> {
  const { request, env, json, error, rateLimitResponse } = ctx;
  const tagId = decodePathParam(ctx, rawId, "tag_id");
  if (tagId instanceof Response) return tagId;
  // 端末 ID だけでは誰でも他人のタグを書き換えられたので、ログイン必須にしてある。
  const authUser = await getAuthUser(request, env);
  if (!authUser) return error("Unauthorized", 401);
  const editor = request.headers.get("X-Device-Id") || authUser.uid;

  // BAN の確認 + マスタ編集 (/edits) と共有の "edit" 枠 (大量改竄の速度を抑える一次防御)。
  // タグの乱立は作成側の device_tag_create_quota が別に抑えている。
  const [inactive, rl] = await Promise.all([
    requireActiveUser(ctx, authUser),
    checkRateLimit(env.DB, authUser.uid, "edit"),
  ]);
  if (inactive) return inactive;
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const tag = await env.DB.prepare(`SELECT ${TAG_COLUMNS} FROM ${pool.masterTable} WHERE id = ?`).bind(tagId).first<{
    id: string; description: string | null; status: string;
  }>();
  if (!tag) return error("Tag not found", 404);
  if (tag.status === "removed") return error("Tag has been removed", 403);

  const body = await readJsonBody(ctx);
  if (body instanceof Response) return body;
  const fields = parseTagFields(body);
  if (typeof fields === "string") return error(fields);
  const { description, category, color } = fields;
  const now = nowSec();

  // 説明文変更なら履歴保存 (before + after 両方記録)
  if (description !== undefined && description !== tag.description) {
    await env.DB.prepare(
      `INSERT INTO ${pool.historyTable} (tag_id, description, description_before, edited_by, edited_at)
       VALUES (?, ?, ?, ?, ?)`
    ).bind(tagId, description ?? null, tag.description ?? null, editor, now).run();
  }

  const updates: string[] = ["updated_by = ?", "updated_at = ?"];
  const vals: unknown[] = [editor, now];
  if (description !== undefined) { updates.push("description = ?"); vals.push(description); }
  if (category !== undefined) { updates.push("category = ?"); vals.push(category); }
  if (color !== undefined) { updates.push("color = ?"); vals.push(color); }
  vals.push(tagId);
  await env.DB.prepare(`UPDATE ${pool.masterTable} SET ${updates.join(", ")} WHERE id = ?`)
    .bind(...vals)
    .run();

  const updated = await env.DB.prepare(`SELECT ${TAG_COLUMNS} FROM ${pool.masterTable} WHERE id = ?`).bind(tagId).first();
  return json({ tag: updated });
}

/**
 * GET <master>/:id/history — 説明の編集履歴 (新しい順に 30 件)。
 * 編集者 (端末 ID か uid) は先頭 8 文字だけ返す (maskUserRef。予想の first_voted_by と同じ)。
 */
async function tagHistory(ctx: RouteContext, pool: TagPool, rawId: string): Promise<Response> {
  const tagId = decodePathParam(ctx, rawId, "tag_id");
  if (tagId instanceof Response) return tagId;
  const { results } = await ctx.env.DB.prepare(
    `SELECT id, tag_id,
            description AS description_after,
            description_before,
            edited_by, edited_at
     FROM ${pool.historyTable}
     WHERE tag_id = ? ORDER BY edited_at DESC LIMIT 30`
  ).bind(tagId).all();
  return ctx.json(results.map((r) => ({ ...r, edited_by: maskUserRef(r.edited_by) })));
}

/**
 * DELETE <master>/:id — タグの削除 (admin 限定 → status='removed')。
 *
 * 「きいた」「持ってる」のような個人的なメモは共有の語彙に混ざると他の人には意味が無く
 * 一覧を汚す (そういう用途には、端末の外に出ないアプリ内のタグがある)。共有の語彙から
 * 外すのはモデレーターの判断。通報 3 件で付く under_review は印でしかなく、読み取り側は
 * status != 'removed' しか見ない。実際に消せるのはこの status='removed' だけ。
 * 物理削除ではなく soft delete にして付与の実績は残す (誤操作なら status を戻せば直る)。
 */
async function removeTag(ctx: RouteContext, pool: TagPool, rawId: string): Promise<Response> {
  const { request, env, json, error } = ctx;
  const tagId = decodePathParam(ctx, rawId, "tag_id");
  if (tagId instanceof Response) return tagId;
  const user = await getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);
  if (!(await checkIsAdmin(env, user.uid))) return error("Forbidden", 403);

  const tag = await env.DB.prepare(`SELECT id, status FROM ${pool.masterTable} WHERE id = ?`)
    .bind(tagId)
    .first<{ id: string; status: string }>();
  if (!tag) return error("Tag not found", 404);
  // 冪等: 既に removed なら何もせず同じ応答を返す
  if (tag.status === "removed") return json({ id: tagId, status: "removed" });

  await env.DB.prepare(`UPDATE ${pool.masterTable} SET status = 'removed' WHERE id = ?`).bind(tagId).run();
  return json({ id: tagId, status: "removed" });
}

/**
 * POST <master>/:id/report — 通報。同じ端末は 1 日 1 回、REPORT_THRESHOLD 件で under_review。
 * IP の枠は複数端末を回した連続通報を抑える (端末ごとの 1 日 1 回と二重の防御)。
 */
async function reportTag(ctx: RouteContext, pool: TagPool, rawId: string): Promise<Response> {
  const { env, json, error } = ctx;
  const tagId = decodePathParam(ctx, rawId, "tag_id");
  if (tagId instanceof Response) return tagId;
  const guard = await requireDeviceWrite(ctx);
  if (guard instanceof Response) return guard;
  const { deviceId, ipQuota } = guard;

  const tag = await env.DB.prepare(`SELECT id FROM ${pool.masterTable} WHERE id = ?`).bind(tagId).first();
  if (!tag) return error("Tag not found", 404);

  const today = new Date().toISOString().slice(0, 10);
  const alreadyReported = await env.DB.prepare(
    `SELECT 1 FROM ${pool.reportTable}
      WHERE tag_id = ? AND reported_by = ? AND DATE(reported_at, 'unixepoch') = ?`
  ).bind(tagId, deviceId, today).first();
  if (alreadyReported) return error("Already reported today", 429);

  const body = await readJsonBody(ctx);
  if (body instanceof Response) return body;
  await env.DB.prepare(
    `INSERT INTO ${pool.reportTable} (tag_id, reported_by, reason, reported_at) VALUES (?, ?, ?, ?)`
  ).bind(tagId, deviceId, body.reason ?? null, nowSec()).run();

  const reportCount = await env.DB.prepare(
    `SELECT COUNT(*) as cnt FROM ${pool.reportTable} WHERE tag_id = ?`
  ).bind(tagId).first<{ cnt: number }>();
  const total = reportCount?.cnt ?? 1;

  if (total >= REPORT_THRESHOLD) {
    await env.DB.prepare(
      `UPDATE ${pool.masterTable} SET status = 'under_review' WHERE id = ? AND status = 'active'`
    ).bind(tagId).run();
  }

  await commitIpRateLimit(env.DB, ipQuota);
  return json({ ok: true, total_reports: total });
}

// ---------------------------------------------------------------------------
// 対象 (曲・アイドル・ユニット) への付与
// ---------------------------------------------------------------------------

/** POST <entity>/:id/tags — タグを付ける。付けた (端末の行が増えた) id だけを返す。 */
async function applyTags(ctx: RouteContext, pool: TagPool, rawId: string): Promise<Response> {
  const { env, json, error } = ctx;
  const entityId = decodePathParam(ctx, rawId, pool.entityKey);
  if (entityId instanceof Response) return entityId;
  const guard = await requireDeviceWrite(ctx);
  if (guard instanceof Response) return guard;
  const { deviceId, ipQuota } = guard;

  const body = await readJsonBody(ctx);
  if (body instanceof Response) return body;
  const tagIds = body.tag_ids;
  if (!Array.isArray(tagIds) || tagIds.length === 0) return error("tag_ids must be a non-empty array");

  const now = nowSec();
  const appliedTagIds: unknown[] = [];

  // 同じ id を何度送られても 1 回だけ数える。
  for (const tagId of new Set<unknown>(tagIds)) {
    const tag = await env.DB.prepare(
      `SELECT id FROM ${pool.masterTable} WHERE id = ? AND status != 'removed'`
    ).bind(tagId).first();
    if (!tag) continue;

    const [deviceResult] = await env.DB.batch([
      env.DB.prepare(
        `INSERT OR IGNORE INTO ${pool.deviceTable} (device_id, ${pool.entityKey}, tag_id, created_at)
         VALUES (?, ?, ?, ?)`
      ).bind(deviceId, entityId, tagId, now),
      // 票は端末の行が実際に増えたとき (直前の INSERT OR IGNORE の changes() > 0) だけ +1。
      // 同じ端末の再送で増やさない。
      env.DB.prepare(
        `INSERT INTO ${pool.linkTable} (${pool.entityKey}, tag_id, vote_count) SELECT ?, ?, 1 WHERE changes() > 0
         ON CONFLICT(${pool.entityKey}, tag_id) DO UPDATE SET vote_count = vote_count + 1`
      ).bind(entityId, tagId),
      // 曲は類似曲スコアの分母を即時に追従させる (batch なので上の INSERT 後の状態を見る)。
      ...(pool.recount ? [pool.recount(env.DB, entityId)] : []),
    ]);

    if (deviceResult.meta.changes > 0) appliedTagIds.push(tagId);
  }

  await commitIpRateLimit(env.DB, ipQuota);
  return json({ [pool.entityKey]: entityId, applied_tag_ids: appliedTagIds });
}

/** DELETE <entity>/:id/tags/:tag_id — 自分の端末が付けたタグを外す。 */
async function detachTag(
  ctx: RouteContext,
  pool: TagPool,
  rawEntityId: string,
  rawTagId: string
): Promise<Response> {
  const { env, json } = ctx;
  const entityId = decodePathParam(ctx, rawEntityId, pool.entityKey);
  if (entityId instanceof Response) return entityId;
  const tagId = decodePathParam(ctx, rawTagId, "tag_id");
  if (tagId instanceof Response) return tagId;
  const guard = await requireDeviceWrite(ctx);
  if (guard instanceof Response) return guard;
  const { deviceId, ipQuota } = guard;

  // 端末の行の削除 + 票 -1 (MAX(0,...)) + 0 以下になった行の削除を batch で原子化
  const [deleted] = await env.DB.batch([
    env.DB.prepare(
      `DELETE FROM ${pool.deviceTable} WHERE device_id = ? AND ${pool.entityKey} = ? AND tag_id = ?`
    ).bind(deviceId, entityId, tagId),
    // 票は端末の行が実際に消えたとき (直前の DELETE の changes() > 0) だけ -1。
    // 付けていない端末の取り消しで減らさない。
    env.DB.prepare(
      `UPDATE ${pool.linkTable} SET vote_count = MAX(0, vote_count - 1)
        WHERE ${pool.entityKey} = ? AND tag_id = ? AND changes() > 0`
    ).bind(entityId, tagId),
    env.DB.prepare(
      `DELETE FROM ${pool.linkTable} WHERE ${pool.entityKey} = ? AND tag_id = ? AND vote_count <= 0`
    ).bind(entityId, tagId),
    // 曲は類似曲スコアの分母を即時に追従させる (batch なので上の DELETE 後の状態を見る)。
    ...(pool.recount ? [pool.recount(env.DB, entityId)] : []),
  ]);

  await commitIpRateLimit(env.DB, ipQuota);
  return json({ [pool.entityKey]: entityId, tag_id: tagId, removed: deleted.meta.changes > 0 });
}

/** GET <entity>/:id/tags — 対象のタグ一覧 (票数の降順) と、この端末が付けたタグ。 */
async function listEntityTags(ctx: RouteContext, pool: TagPool, rawId: string): Promise<Response> {
  const entityId = decodePathParam(ctx, rawId, pool.entityKey);
  if (entityId instanceof Response) return entityId;
  const deviceId = ctx.request.headers.get("X-Device-Id");
  return ctx.json(await fetchEntityTagList(ctx.env.DB, pool, entityId, deviceId));
}

// ---------------------------------------------------------------------------
// 類似 (この曲・この人・このユニットが好きな人には、これもおすすめ)
// ---------------------------------------------------------------------------

/**
 * GET <entity>/:id/similar — タグが似ている対象。並べ方と limit の上限はプールごと (TagPool.similar)。
 *
 * 曲は減衰つき Jaccard (score = shared / (tags_a + tags_b - shared + SIMILARITY_DAMPING)):
 *   共有タグ数 → 票数合計の順だと「タグがたくさん付いている有名曲」が何にでも上位に出る
 *   (共有数も票数もタグ数に比例して増えるため)。かといって素の Jaccard では「タグが 1〜2 個
 *   しかない曲がたまたま全部一致して 100%」が勝つ。タグはユーザー投稿のみで自動付与しない
 *   方針なのでタグ数の少ない曲が多数派で、この小サンプル事故が主流になる。分母に定数を足して
 *   平滑化すると、件数が少ないうちは慎重に、タグが貯まるほど素の Jaccard に近づく。
 *   IDF 重み付け (珍しいタグほど重く見る) も検討したが、珍しいタグ 1 本の一致が 9 本の一致に
 *   勝ってしまい類似としては明確に劣るため採らない。
 * アイドル・ユニットは共有タグ数 → 票数合計 (sharedTagRows)。
 *
 * ここでは候補をスコア順に返すだけで、何件をどう見せるかはクライアントが決める (毎回同じ並びに
 * ならないよう重み付き抽選する)。応答は決定的なのでエッジキャッシュがそのまま効く。
 * 完全にユーザー非依存 (my_* を含まない) で変化も緩やかなので、全ユーザ共有でキャッシュする。
 */
async function listSimilar(ctx: RouteContext, pool: TagPool, rawId: string): Promise<Response> {
  const entityId = decodePathParam(ctx, rawId, pool.entityKey);
  if (entityId instanceof Response) return entityId;
  const limit = clampSimilarLimit(ctx.url.searchParams.get("limit"), 10, pool.similar.maxLimit);
  const rows = await pool.similar.rows(ctx.env.DB, entityId, limit);
  return ctx.json({ [pool.entityKey]: entityId, [pool.listKey]: rows }, 200, SIMILAR_CACHE_HEADERS);
}

// ---------------------------------------------------------------------------
// GET /tags/activity — タグ付けの盛り上がり (曲とアイドルの横断。ユニットは含めない)
// ---------------------------------------------------------------------------

type ActivityRow = Record<string, unknown>;

/**
 * device_song_tag / device_idol_tag は「端末 1 件ごとのタグ付与」を created_at 付きで持つので、
 * 新しい表を足さずに直近の流れと期間内の急増を出せる。曲名・アイドル名は解決せず entity_id だけ
 * 返し、名前と色はクライアントが同期済みのローカル DB で引く (GET <master>/:id と同じ分担)。
 */
async function tagActivity(ctx: RouteContext): Promise<Response> {
  const { env, url, json } = ctx;
  const windowDays = Math.min(30, Math.max(1, parseInt(url.searchParams.get("window_days") || "7") || 7));
  const windowStart = nowSec() - windowDays * 86400;

  const [recentSongRows, recentIdolRows, trendSongRows, trendIdolRows, risingSongRows, risingIdolRows] =
    await Promise.all([
      env.DB.prepare(
        `SELECT dst.song_id as entity_id, dst.tag_id, t.name as tag_name, t.color as tag_color,
                t.category as tag_category, dst.created_at
         FROM device_song_tag dst JOIN tags t ON t.id = dst.tag_id
         WHERE t.status != 'removed'
         ORDER BY dst.created_at DESC LIMIT 40`
      ).all<ActivityRow>(),
      env.DB.prepare(
        `SELECT dit.idol_id as entity_id, dit.tag_id, t.name as tag_name, t.color as tag_color,
                t.category as tag_category, dit.created_at
         FROM device_idol_tag dit JOIN idol_tag_master t ON t.id = dit.tag_id
         WHERE t.status != 'removed'
         ORDER BY dit.created_at DESC LIMIT 40`
      ).all<ActivityRow>(),
      env.DB.prepare(
        `SELECT dst.tag_id, t.name as tag_name, t.color as tag_color, t.category as tag_category,
                COUNT(*) as recent_count,
                COALESCE((SELECT SUM(vote_count) FROM song_tags WHERE tag_id = t.id), 0) as total_count
         FROM device_song_tag dst JOIN tags t ON t.id = dst.tag_id
         WHERE dst.created_at >= ? AND t.status != 'removed'
         GROUP BY dst.tag_id ORDER BY recent_count DESC LIMIT 10`
      ).bind(windowStart).all<ActivityRow>(),
      env.DB.prepare(
        `SELECT dit.tag_id, t.name as tag_name, t.color as tag_color, t.category as tag_category,
                COUNT(*) as recent_count,
                COALESCE((SELECT SUM(vote_count) FROM idol_tags WHERE tag_id = t.id), 0) as total_count
         FROM device_idol_tag dit JOIN idol_tag_master t ON t.id = dit.tag_id
         WHERE dit.created_at >= ? AND t.status != 'removed'
         GROUP BY dit.tag_id ORDER BY recent_count DESC LIMIT 10`
      ).bind(windowStart).all<ActivityRow>(),
      env.DB.prepare(
        `SELECT dst.song_id as entity_id, dst.tag_id, t.name as tag_name, t.color as tag_color,
                COUNT(*) as recent_count
         FROM device_song_tag dst JOIN tags t ON t.id = dst.tag_id
         WHERE dst.created_at >= ? AND t.status != 'removed'
         GROUP BY dst.song_id, dst.tag_id HAVING COUNT(*) >= 2
         ORDER BY recent_count DESC LIMIT 10`
      ).bind(windowStart).all<ActivityRow>(),
      env.DB.prepare(
        `SELECT dit.idol_id as entity_id, dit.tag_id, t.name as tag_name, t.color as tag_color,
                COUNT(*) as recent_count
         FROM device_idol_tag dit JOIN idol_tag_master t ON t.id = dit.tag_id
         WHERE dit.created_at >= ? AND t.status != 'removed'
         GROUP BY dit.idol_id, dit.tag_id HAVING COUNT(*) >= 2
         ORDER BY recent_count DESC LIMIT 10`
      ).bind(windowStart).all<ActivityRow>(),
    ]);

  /** 曲とアイドルの行を domain 付きで 1 本にし、key の降順で先頭 n 件。 */
  const merge = (song: ActivityRow[], idol: ActivityRow[], key: string, n: number) =>
    [
      ...song.map((r): ActivityRow => ({ domain: "song", ...r })),
      ...idol.map((r): ActivityRow => ({ domain: "idol", ...r })),
    ]
      .sort((a, b) => (b[key] as number) - (a[key] as number))
      .slice(0, n);

  const recent = merge(recentSongRows.results, recentIdolRows.results, "created_at", 40);
  const trendingTags = merge(trendSongRows.results, trendIdolRows.results, "recent_count", 12);
  const risingEntities = merge(risingSongRows.results, risingIdolRows.results, "recent_count", 12);

  // アクセス集中対策のエッジキャッシュ (max-age 10分)。日次だと「最近つけられたタグ」の
  // 反映が最大24時間遅れて盛り上がり感が薄れるため、鮮度と負荷軽減のバランスでこの値にする。
  return json(
    { window_days: windowDays, recent, trending_tags: trendingTags, rising_entities: risingEntities },
    200,
    { "Cache-Control": "public, max-age=600, stale-while-revalidate=1800" }
  );
}
