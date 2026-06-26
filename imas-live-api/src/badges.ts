// badges.ts — 貢献バッジ判定。
//
// 即時オープン編集への移行に伴い、集計元を submissions(status='approved') から
// オープン編集の監査ログ (edit_batch / edit_history / edit_good) へ差し替えた。
// 貢献度は 2 指標を個別集計し合成しない (確定契約 §3):
//   - editCount     = cloudkit_ok=1 かつ source='app' の edit_batch 件数 (= users.contribution_count と同値)
//                     revert/seed batch は数えない。revert 済み (reverted_at IS NOT NULL) は通算カウントに残す。
//   - goodsReceived = 自分の編集 (source='app') batch が累計で受け取った edit_good 数
// バッジ tier は editCount (編集件数) を主指標とする
// (Good は sybil 水増し耐性が低いため。RedTeam edge_case)。
// レスポンスキーは確定契約により camelCase 直返し。旧キー (totalApproved/contributionCount) は廃止。

export type BadgeTier = "none" | "bronze" | "silver" | "gold" | "platinum";

const TIERS: Array<{ tier: BadgeTier; min: number }> = [
  { tier: "platinum", min: 500 },
  { tier: "gold", min: 200 },
  { tier: "silver", min: 50 },
  { tier: "bronze", min: 10 },
];

/** 編集件数から tier を判定する (Good 累計ではなく編集件数が主指標)。 */
export function calcTier(editCount: number): BadgeTier {
  for (const { tier, min } of TIERS) {
    if (editCount >= min) return tier;
  }
  return "none";
}

// レスポンスキーは確定契約 §3 により camelCase 直返しで統一する (editCount / goodsReceived)。
// 貢献度 2 指標は個別集計し合成しない:
//   - editCount     = 編集 batch 件数 (cloudkit_ok=1 かつ source='app')
//   - goodsReceived = 自分の編集が累計で受け取った Good 数
// 旧キー (totalApproved / contributionCount) は廃止 (確定契約)。
export interface BadgeInfo {
  tier: BadgeTier;
  /** 編集件数 (確定契約の主指標。tier 算定元)。 */
  editCount: number;
  /** 自分の編集が累計で受け取った Good 数 (編集件数とは別集計)。 */
  goodsReceived: number;
  /** record_type 別の編集件数内訳 (source='app' に限定)。 */
  categories: Record<string, number>;
}

/**
 * ユーザーの貢献バッジを集計する (確定契約 §3: 全て source='app' に限定)。
 *   - 編集件数 = cloudkit_ok=1 かつ source='app' の edit_batch 件数 (revert/seed は除外。revert 済みは通算維持)
 *   - record_type 別内訳 = edit_history を batch JOIN し record_type で GROUP BY (source='app' 限定)
 *     (1 batch が複数 record_type を含む setlist 一括編集もあるため、内訳は op 行ベース)
 *   - 受け取った Good = 自分が editor の編集 (source='app') batch に付いた edit_good の総数
 */
export async function fetchBadges(
  db: D1Database,
  userId: string
): Promise<BadgeInfo> {
  const [editCountRow, categoryRows, goodsRow] = await Promise.all([
    db
      .prepare(
        "SELECT COUNT(*) AS cnt FROM edit_batch WHERE editor_id = ? AND cloudkit_ok = 1 AND source = 'app'"
      )
      .bind(userId)
      .first<{ cnt: number }>(),
    db
      .prepare(
        `SELECT eh.record_type AS rt, COUNT(*) AS cnt
           FROM edit_history eh
           JOIN edit_batch eb ON eb.id = eh.batch_id
          WHERE eb.editor_id = ? AND eb.cloudkit_ok = 1 AND eb.source = 'app'
          GROUP BY eh.record_type`
      )
      .bind(userId)
      .all<{ rt: string; cnt: number }>(),
    db
      .prepare(
        `SELECT COUNT(*) AS cnt
           FROM edit_good g
           JOIN edit_batch eb ON eb.id = g.batch_id
          WHERE eb.editor_id = ? AND eb.source = 'app'`
      )
      .bind(userId)
      .first<{ cnt: number }>(),
  ]);

  const editCount = Number(editCountRow?.cnt) || 0;
  const goodsReceived = Number(goodsRow?.cnt) || 0;

  const categories: Record<string, number> = {};
  for (const row of categoryRows.results ?? []) {
    categories[row.rt] = Number(row.cnt) || 0;
  }

  return {
    tier: calcTier(editCount),
    editCount,
    goodsReceived,
    categories,
  };
}
