// edit_history.ts — オープン編集の監査基盤 (edit_batch / edit_history) の D1 ヘルパ。
//
// 契約 (POST /edits の server logic):
//   (6) edit_batch を cloudkit_ok=0 で先行 INSERT → batchId 採番
//   (7) CloudKit forceUpdate / softDelete 実行
//   (8) 成功時のみ cloudkit_ok=1 に UPDATE + 各 op を edit_history へ INSERT
//        (cloudkit_ok=1 と history 行群は 1 つの D1 batch() で原子的に書く)
//   失敗時: edit_batch は cloudkit_ok=0 のまま残し、edit_history は書かない。
//
// revert 対象は cloudkit_ok=1 の batch に限定する (cloudkit_ok=0 = CloudKit 未反映/失敗)。

import type { EditOp } from "./master_validators";

/** edit_batch.op / source。op は batch レベルの意味 (replace は行レベルで update/delete に分解)。 */
export type BatchOp = "create" | "update" | "delete" | "replace" | "revert";
export type BatchSource = "app" | "revert" | "admin" | "seed";

/**
 * 1 件の編集操作の履歴記録。before は cloudKitLookup で得たサーバ権威値。
 *
 * op に加え、setlist 編集の show 単位スナップショット行 ('snapshot') もこの型で表す:
 *   recordType='ShowSetlist', recordName=showId,
 *   before/after = { items: [...全 SetlistItem], performers: [...全 SetlistPerformer] }
 * の丸ごとリスト。これにより SetlistItem の recordName が位置非依存になった後も、
 * revert は「show のセトリ全体を before スナップショットへ置換」するだけで安全に成立する
 * (RedTeam Critical #1 対策: 位置依存 recordName による壊れたセトリ revert を回避)。
 */
export interface EditHistoryEntry {
  recordType: string;
  recordName: string;
  /** 'create'|'update'|'delete' (個別レコード) または 'snapshot' (ShowSetlist の show 単位スナップショット)。 */
  op: EditOp | "snapshot";
  /** 編集前の全フィールド (camelCase)。サーバが権威取得。create 時は null。 */
  before: Record<string, unknown> | null;
  /** 編集後に CloudKit へ送ったフィールド。delete 時は null。 */
  after: Record<string, unknown> | null;
  /** CloudKit に注入した modifiedAt と同値 (差分同期突合用, ms)。 */
  modifiedAt: number;
}

/**
 * cloudkit_ok=0 で edit_batch を先行 INSERT し、採番された batchId を返す (契約 step 6)。
 * CloudKit 書き込み前に呼ぶこと。失敗 (502) 時はこの行が cloudkit_ok=0 のまま残り、revert 対象外になる。
 */
export async function createEditBatch(
  db: D1Database,
  params: {
    editorId: string;
    op: BatchOp;
    source?: BatchSource;
    summary?: string | null;
    revertsBatchId?: number | null;
    createdAt?: number;
  }
): Promise<number> {
  const createdAt = params.createdAt ?? Date.now();
  const row = await db
    .prepare(
      `INSERT INTO edit_batch (editor_id, source, op, summary, reverts_batch_id, cloudkit_ok, created_at)
       VALUES (?, ?, ?, ?, ?, 0, ?)
       RETURNING id`
    )
    .bind(
      params.editorId,
      params.source ?? "app",
      params.op,
      params.summary ?? null,
      params.revertsBatchId ?? null,
      createdAt
    )
    .first<{ id: number }>();
  if (!row) throw new Error("createEditBatch: INSERT returned no id");
  return row.id;
}

/**
 * CloudKit 反映成功後に呼ぶ (契約 step 8 + 9)。1 つの D1 batch() で原子的に:
 *   - edit_batch.cloudkit_ok=1 に UPDATE
 *   - 各 op を edit_history へ INSERT
 *   - editor の users.contribution_count++
 * を実行する。これにより「cloudkit_ok=1 の batch は必ず history 行を伴う」不変条件を保つ。
 */
export async function finalizeEditBatch(
  db: D1Database,
  batchId: number,
  editorId: string,
  entries: EditHistoryEntry[]
): Promise<void> {
  const now = Date.now();
  const stmts: D1PreparedStatement[] = [
    db.prepare("UPDATE edit_batch SET cloudkit_ok = 1 WHERE id = ?").bind(batchId),
  ];
  for (const e of entries) {
    stmts.push(
      db
        .prepare(
          `INSERT INTO edit_history
             (batch_id, record_type, record_name, op, before_json, after_json, modified_at, created_at, reverted)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)`
        )
        .bind(
          batchId,
          e.recordType,
          e.recordName,
          e.op,
          e.before === null ? null : JSON.stringify(e.before),
          e.after === null ? null : JSON.stringify(e.after),
          e.modifiedAt,
          now
        )
    );
  }
  // 貢献度: 編集件数 (受け取った Good 累計とは別集計。合成しない)。1 batch = +1。
  stmts.push(
    db.prepare("UPDATE users SET contribution_count = contribution_count + 1 WHERE id = ?").bind(editorId)
  );
  await db.batch(stmts);
}

/** GET /master/:recordType/:recordName/history の 1 行 (editor は表示名のみ公開、user.id は返さない)。 */
export interface RecordHistoryRow {
  id: number;
  batch_id: number;
  op: string;
  before_json: string | null;
  after_json: string | null;
  modified_at: number;
  created_at: number;
  reverted: number;
  editor_name: string | null;
  source: string;
  reverted_at: number | null;
}

/**
 * あるマスタレコードの編集履歴を新しい順で返す (edit_history JOIN edit_batch JOIN users)。
 * cloudkit_ok=1 の batch のみ (CloudKit に反映済みの編集だけが履歴に意味を持つ)。
 * editor は display_name のみ付与し user.id は露出しない (RedTeam Medium: 編集者匿名性)。
 */
export async function getRecordHistory(
  db: D1Database,
  recordType: string,
  recordName: string,
  limit = 30
): Promise<RecordHistoryRow[]> {
  const { results } = await db
    .prepare(
      `SELECT eh.id, eh.batch_id, eh.op, eh.before_json, eh.after_json,
              eh.modified_at, eh.created_at, eh.reverted,
              eb.source, eb.reverted_at,
              u.display_name AS editor_name
         FROM edit_history eh
         JOIN edit_batch eb ON eb.id = eh.batch_id
         LEFT JOIN users u ON u.id = eb.editor_id
        WHERE eh.record_type = ? AND eh.record_name = ? AND eb.cloudkit_ok = 1
        ORDER BY eh.created_at DESC
        LIMIT ?`
    )
    .bind(recordType, recordName, Math.min(Math.max(limit, 1), 100))
    .all<RecordHistoryRow>();
  return results ?? [];
}
