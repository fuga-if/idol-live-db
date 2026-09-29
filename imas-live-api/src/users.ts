// users.ts — users テーブルまわりの共通操作。
//
// 複数のルート (routes/*.ts と edits.ts 等) から使うので独立させている。

import type { Env } from "./env";

/** Apple/Google uid の行を作る (表示名の上書き事故を防ぐ規則はコメント参照)。 */
export async function upsertUser(env: Env, uid: string, name?: string, picture?: string) {
  // display_name は INSERT (初回ログインで行を作る) 時のみ設定し、CONFLICT では一切更新しない。
  // 既存ユーザーの表示名は POST /users/me でのみ変更する設計にする。これにより、
  // Apple が fullName を初回認可時しか返さない (2台目/再インストール後は name=undefined)
  // 再ログインでも、ユーザーが POST /users/me で設定した display_name を上書きしない。
  // 書き込みの経路 (投票・予想・Good・編集) は name を渡さない。メールアドレスを
  // 表示名として保存しないため (行が無いときは "匿名" で作る)。
  // avatar_url は渡されたときだけ更新し、無ければ COALESCE で既存を温存する。
  await env.DB.prepare(
    `INSERT INTO users (id, display_name, avatar_url) VALUES (?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       avatar_url = COALESCE(?, users.avatar_url),
       updated_at = datetime('now')`
  )
    .bind(uid, name || "匿名", picture ?? null, picture ?? null)
    .run();
}

/** env の許可リスト (ADMIN_USER_IDS) に載っているか。D1 を読まない。 */
export function isAllowlistedAdmin(env: Env, uid: string): boolean {
  if (!env.ADMIN_USER_IDS) return false;
  return env.ADMIN_USER_IDS.split(",").map((s) => s.trim()).filter(Boolean).includes(uid);
}

/** env の allowlist または users.is_admin でモデレーター判定。 */
export async function checkIsAdmin(env: Env, uid: string): Promise<boolean> {
  if (isAllowlistedAdmin(env, uid)) return true;
  const row = await env.DB.prepare("SELECT is_admin FROM users WHERE id = ?")
    .bind(uid)
    .first<{ is_admin: number }>();
  return !!row?.is_admin;
}
