// rate_limit.ts — D1ベースのレートリミット

export interface RateLimitResult {
  allowed: boolean;
  used: number;
  limit: number;
  reset_at: string;
}

function todayUtc(): string {
  return new Date().toISOString().slice(0, 10); // "YYYY-MM-DD"
}

function tomorrowMidnightUtc(): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + 1);
  d.setUTCHours(0, 0, 0, 0);
  return d.toISOString();
}

const LIMITS: Record<string, number> = {
  submit: 10,
  vote: 100,
  prediction: 30,
  // edit: 1 日あたりの編集 batch 数 (1 セトリ保存 = 1 batch なので op 数ではなく操作回数)。
  // 大量改竄の速度を抑える一次防御。根本対策は BAN + ユーザー単位 revert。
  edit: 100,
  // good: 編集フィードを流し読みしながら拍手する操作。緩めに許容。
  good: 300,
  // poll: お題作成。スパム防止のため厳しめ（1日5件まで）。
  poll: 5,
  // poll_vote: 投票・取消。推しに入れる操作なので緩めに許容。
  poll_vote: 60,
  // performer_prediction: 出演者予想。1曲あたり最大8人選択できるため prediction より緩め。
  performer_prediction: 60,
  // profile: 表示名など自分のプロフィール更新。頻度は低いはず + 誤字修正の余地を見て 1日3回。
  profile: 3,
  // app_attest: アプリ証明 (/app/*) の IP 単位上限。正規端末は 1 日数回程度。
  // Google Play Integrity / ECDSA 検証コストのクォータ枯渇 (自爆 DoS) を防ぐ一次防御。
  app_attest: 50,
};

/**
 * 原子的 UPSERT でカウントを増加し、増加後の値でレート制限を判定する。
 * TOCTOU を排除するため check と increment を一体化している。
 * 呼び出し側は戻り値の allowed が false の場合は処理を中断すること。
 */
export async function checkRateLimit(
  db: D1Database,
  userId: string,
  action: string
): Promise<RateLimitResult> {
  const limit = LIMITS[action] ?? 100;
  const date = todayUtc();

  const row = await db
    .prepare(
      `INSERT INTO rate_limits (user_id, date, action, count)
       VALUES (?, ?, ?, 1)
       ON CONFLICT(user_id, date, action) DO UPDATE SET count = count + 1
       RETURNING count`
    )
    .bind(userId, date, action)
    .first<{ count: number }>();

  const used = row?.count ?? 1;
  return {
    allowed: used <= limit,
    used,
    limit,
    reset_at: tomorrowMidnightUtc(),
  };
}
