// routes/sync_manifest.ts — 同期の目録。
//
//   GET /sync/manifest — レコードタイプごとの「最も新しい modifiedAt」
//
// アプリの差分同期は、変更が 0 件でもレコードタイプの数だけ CloudKit に問い合わせる
// (24 型 = 24 往復)。この口を先に 1 回読めば、動いていない型は問い合わせずに済む。
//
// 目録は**書き込み側が更新する記録ではなく、CloudKit に問い合わせて組み立てる派生物**。
// CloudKit に書く経路は Worker の編集のほかに手元の Python が数十本あり、「書いたら目録も
// 更新する」を全経路に守らせる作りだと、守り忘れた経路の変更が端末に届かなくなる。
// 問い合わせて作れば、どの経路で書かれても modifiedAt が動いていれば必ず載る。
//
// - 引けなかった型は応答に載せない。アプリは載っていない型を従来どおり問い合わせる。
// - 全部引けなければ 503 (キャッシュしない)。アプリは目録なしの従来の同期に落ちる。
// - 物理削除 (forceDelete) は modifiedAt が動かないので、ここには現れない。アプリ側の
//   定期フル同期 (孤児掃除) が拾う。
//
// 端末にも人にも依らない値なので、エッジで全端末に共有する (index.ts の Cache API)。

import { cloudKitLatestModifiedAt } from "../cloudkit";
import type { RouteContext } from "./context";

/**
 * アプリが同期するレコードタイプ。正は imas-core `domain/sync_planning.rs` の
 * `STEPS_IN_FK_ORDER` で、そちらのテスト (`manifest_route_lists_every_sync_step`) が
 * この一覧に全ステップが載っていることを確かめる。並びに意味は無い。
 */
export const SYNC_RECORD_TYPES = [
  "Brand", "Creator", "Idol", "IdolFacet", "IdolHairstyle", "Event", "ImasUnit",
  "Venue", "VenueName", "VenueHall", "IdolBrand", "Show", "UnitVersion", "Song",
  "UnitMember", "SongArtist", "ShowCast", "SetlistItem", "SetlistPerformer",
  "Costume", "CostumeWear", "ShowTicket", "TicketSale", "SongVideo",
] as const;

/** エッジで共有する秒数。変更が端末に見え始めるまでの遅れの上限になる。 */
const MANIFEST_MAX_AGE_SECONDS = 60;

export async function handleSyncManifest(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error } = ctx;
  if (path !== "/sync/manifest" || request.method !== "GET") return null;

  // 問い合わせる前の時刻を「この目録が確かに見ている時点」とする (後の時刻にすると、
  // 問い合わせの最中に書かれたレコードを見ていないのに見たことになる)。
  const generatedAt = Date.now();
  const results = await Promise.all(
    SYNC_RECORD_TYPES.map((type) =>
      cloudKitLatestModifiedAt(type, env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY)
    )
  );

  const types: Record<string, number | null> = {};
  const failed: Array<{ type: string; error: string }> = [];
  results.forEach((result, i) => {
    const type = SYNC_RECORD_TYPES[i];
    if (result.ok) types[type] = result.modifiedAt;
    else failed.push({ type, error: result.error });
  });
  if (failed.length > 0) {
    console.error(JSON.stringify({ event: "sync_manifest_partial", failed: failed.slice(0, 5), count: failed.length }));
  }
  if (failed.length === SYNC_RECORD_TYPES.length) return error("manifest unavailable", 503);

  return json({ generatedAt, types }, 200, {
    "Cache-Control": `public, max-age=${MANIFEST_MAX_AGE_SECONDS}`,
  });
}
