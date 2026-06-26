// setlist_snapshot.ts — setlist 編集を show 単位スナップショットで edit_history に残すためのヘルパ。
//
// 背景 (RedTeam Critical #1):
//   旧 SetlistItem の recordName は位置依存 (`sh_<show>_NNNN` / `sli_<show>_NN`) だったため、
//   個別レコード単位の before/after revert は「間に別編集が挟まると無関係な曲を上書き」して
//   壊れたセトリを生んでいた。契約 v2 #3 で recordName を位置非依存 (sli_<uuid>, position はフィールド) に
//   移したうえで、setlist 編集は **show 単位スナップショット** を 1 行 (record_type='ShowSetlist',
//   record_name=showId) として記録する。revert は「show のセトリ全体を before スナップショットで置換」
//   = 全 SetlistItem/SetlistPerformer の forceUpdate + スナップショットに無い現存分の softDelete、で成立する。
//
// before は cloudKitLookup と同じく **サーバ権威取得** (cloudKitQuery で showId == X の現状を引く)。
// クライアント送信値は before に使わない (revert を任意書き込みプリミティブ化させないため)。

import { cloudKitQuery, flattenCkFields, type CloudKitRecord } from "./cloudkit";

/** setlist 編集に関与する recordType。これらの op を含む batch は ShowSetlist スナップショット対象。 */
export const SETLIST_RECORD_TYPES = new Set(["SetlistItem", "SetlistPerformer"]);

/** show 単位スナップショットの recordType / フィールド名。 */
export const SHOW_SETLIST_TYPE = "ShowSetlist";

/** スナップショット 1 件の SetlistItem (recordName + フィールド)。 */
export interface SnapshotItem {
  recordName: string;
  fields: Record<string, unknown>;
}

/** スナップショット 1 件の SetlistPerformer (recordName + フィールド)。 */
export interface SnapshotPerformer {
  recordName: string;
  fields: Record<string, unknown>;
}

/** ある show のセトリ全体のスナップショット (before/after に格納する形)。 */
export interface ShowSetlistSnapshot {
  showId: string;
  items: SnapshotItem[];
  performers: SnapshotPerformer[];
}

/**
 * show の **編集前** セトリ全体を CloudKit から権威取得する (before スナップショット用)。
 *   1. SetlistItem を showId == showId で query
 *   2. 得た item.recordName ごとに SetlistPerformer を setlistItemId == itemId で query
 * soft-deleted (deletedAt != null) は cloudKitQuery 側で除外済み。
 */
export async function fetchShowSetlistSnapshot(
  showId: string,
  keyId: string,
  pem: string
): Promise<{ ok: true; snapshot: ShowSetlistSnapshot } | { ok: false; error: string }> {
  const itemsRes = await cloudKitQuery("SetlistItem", "showId", showId, keyId, pem);
  if (!itemsRes.ok) return { ok: false, error: `setlist items query: ${itemsRes.error}` };

  const items: SnapshotItem[] = (itemsRes.records ?? []).map(toSnapshotRecord);

  const performers: SnapshotPerformer[] = [];
  for (const item of items) {
    const perfRes = await cloudKitQuery("SetlistPerformer", "setlistItemId", item.recordName, keyId, pem);
    if (!perfRes.ok) return { ok: false, error: `setlist performers query: ${perfRes.error}` };
    for (const rec of perfRes.records ?? []) performers.push(toSnapshotRecord(rec));
  }

  return { ok: true, snapshot: sortSnapshot({ showId, items, performers }) };
}

function toSnapshotRecord(rec: CloudKitRecord): { recordName: string; fields: Record<string, unknown> } {
  // システム系 (___*) / deletedAt / modifiedAt はスナップショットから落とす
  // (revert 時は buildForceUpdate が modifiedAt を再注入する。deletedAt は復活側で明示クリア)。
  const fields = flattenCkFields(rec.fields);
  delete fields.modifiedAt;
  delete fields.deletedAt;
  return { recordName: rec.recordName, fields };
}

/** スナップショットを recordName で決定的にソートする (diff・履歴表示の安定化)。 */
function sortSnapshot(s: ShowSetlistSnapshot): ShowSetlistSnapshot {
  return {
    showId: s.showId,
    items: [...s.items].sort((a, b) => a.recordName.localeCompare(b.recordName)),
    performers: [...s.performers].sort((a, b) => a.recordName.localeCompare(b.recordName)),
  };
}

/**
 * before スナップショットに、この batch の SetlistItem/SetlistPerformer op を適用して
 * **編集後** スナップショットを再構成する (after_json 用)。
 *
 * CloudKit 反映成功後の確定状態を after として残すため、op を before に重ねて算出する:
 *   - create/update → items/performers に upsert (fields は送信値)
 *   - delete        → items/performers から除去
 * これにより after_json は「この編集で show のセトリがどうなったか」を完全に表す。
 */
export function applyOpsToSnapshot(
  before: ShowSetlistSnapshot,
  ops: Array<{ op: "create" | "update" | "delete"; recordType: string; recordName: string; fields: Record<string, unknown> }>
): ShowSetlistSnapshot {
  const itemMap = new Map(before.items.map((i) => [i.recordName, { ...i, fields: { ...i.fields } }]));
  const perfMap = new Map(before.performers.map((p) => [p.recordName, { ...p, fields: { ...p.fields } }]));

  for (const op of ops) {
    const target = op.recordType === "SetlistItem" ? itemMap : op.recordType === "SetlistPerformer" ? perfMap : null;
    if (!target) continue;
    if (op.op === "delete") {
      target.delete(op.recordName);
    } else {
      const cleaned = { ...op.fields };
      delete cleaned.modifiedAt;
      delete cleaned.deletedAt;
      target.set(op.recordName, { recordName: op.recordName, fields: cleaned });
    }
  }

  return sortSnapshot({
    showId: before.showId,
    items: [...itemMap.values()],
    performers: [...perfMap.values()],
  });
}
