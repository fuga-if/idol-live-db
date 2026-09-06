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
  // edit_request: マスタ修正リクエスト (GitHub issue 化)。スパム防止で控えめ。
  edit_request: 30,
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
  // transfer_create: 引き継ぎコード発行。機種変更等での利用を想定し控えめ。
  transfer_create: 5,
  // transfer_fetch: 引き継ぎコード取得 (入力ミスの再試行を考慮しやや緩め)。
  transfer_fetch: 20,
  // auth_login: 未認証で叩ける /auth/login の IP 単位上限。Apple/Google トークン検証
  // (外部 JWKS fetch・署名検証コスト) の枯渇を防ぐ一次防御。CGNAT 環境で多数ユーザーが
  // 同一 IP を共有しうるため、正当ユーザーを弾かないよう広めに確保する。
  auth_login: 500,
  // auth_refresh: 自前 JWT 検証のみで外部コストは無いが、同じ理由で下限の防御を掛ける。
  auth_refresh: 500,
  // 歌詞の読み取りには日次上限を置かない。
  // 一括取得を防いでいるのは構造 (1リクエスト1曲・一括エンドポイント無し・
  // エクスポート機能無し・認証必須) であって回数制限ではない。日次上限は
  // 正常な利用者に当たるリスクのわりに、決意した相手への効果が薄い。
  // 代わりに routes/lyrics.ts で IP 単位のバースト制限 (30回/分) だけ掛けている。
  // これはクライアントの暴走で Worker 無料枠 (10万req/日) を焼かないための保険。
  // lyrics_admin: PUT /admin/lyrics/:id。投入ツールが1曲1リクエストで流すため、
  // 一括投入が枠で止まらないよう十分広く取る (admin しか叩けない)。
  lyrics_admin: 5000,
  // lyrics_calls: PUT /songs/:id/calls。コール編集は 1 曲を何度も保存し直す作業なので
  // 歌詞投入より試行回数が多い。admin しか叩けないため広く取る。
  lyrics_calls: 5000,
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

/**
 * IP 単位の割り当て。未認証エンドポイント (auth/login 等) や device 集計の
 * 一次防御に使う。user/device 単位の checkRateLimit とは別枠。
 *
 * 既定は 1 分 30 回。歌詞・コールガイドの GET は会場で大勢が同じ IP (キャリアの NAT)
 * から同じ 1 分に開くので、呼び出し側が別の上限を渡す (routes/lyrics.ts の
 * LYRICS_IP_LIMITS)。1 日の上限は、分の上限を上げたぶんの「まとめ取り」の歯止め。
 * 日のバケットは同じ表に**負の鍵**で置く (分のバケットは正の整数なので衝突しない)。
 */
export interface IpRateLimits {
  perMinute: number;
  /** 未指定なら日の上限を見ない (既定の呼び出し側)。 */
  perDay?: number;
}
const IP_RATE_LIMIT_PER_MINUTE = 30;
const DEFAULT_IP_LIMITS: IpRateLimits = { perMinute: IP_RATE_LIMIT_PER_MINUTE };

export interface IpRateCheck {
  allowed: boolean;
  /** 今の分の回数。 */
  count: number;
  bucket: number;
  /** 日の上限を見たときだけ入る (commit で一緒に +1 する)。 */
  dayBucket: number | null;
}

const RATE_ROW_SQL = "SELECT count FROM api_rate_limits WHERE ip = ? AND minute_bucket = ?";

/** チェックのみ（+1 しない）。成功時のみ commitIpRateLimit を呼ぶ。 */
export async function dryCheckIpRateLimit(
  db: D1Database,
  ip: string,
  limits: IpRateLimits = DEFAULT_IP_LIMITS
): Promise<IpRateCheck> {
  const nowSec = Math.floor(Date.now() / 1000);
  const bucket = Math.floor(nowSec / 60);
  const dayBucket = limits.perDay === undefined ? null : -Math.floor(nowSec / 86400);
  const minute = await db.prepare(RATE_ROW_SQL).bind(ip, bucket).first<{ count: number }>();
  const count = minute?.count ?? 0;
  if (count >= limits.perMinute) return { allowed: false, count, bucket, dayBucket };
  if (dayBucket !== null) {
    const day = await db.prepare(RATE_ROW_SQL).bind(ip, dayBucket).first<{ count: number }>();
    if ((day?.count ?? 0) >= limits.perDay!) return { allowed: false, count, bucket, dayBucket };
  }
  return { allowed: true, count, bucket, dayBucket };
}

/** handler 成功直前にのみ呼ぶ（+1 コミット）。日のバケットを見た呼び出しはそちらも +1。 */
export async function commitIpRateLimit(
  db: D1Database,
  ip: string,
  bucket: number,
  dayBucket: number | null = null
): Promise<void> {
  const upsert = (b: number) =>
    db
      .prepare(
        `INSERT INTO api_rate_limits (ip, minute_bucket, count)
         VALUES (?, ?, 1)
         ON CONFLICT(ip, minute_bucket) DO UPDATE SET count = count + 1`
      )
      .bind(ip, b)
      .run();
  await upsert(bucket);
  if (dayBucket !== null) await upsert(dayBucket);
}

/**
 * コミュニティ投票の 1人あたり票数上限。
 * 「みんなの投票」(お題1件) と「セトリ予想」(公演1件) で同じ 3票に揃えている
 * (iOS の CommunityVoteLimit.perTarget と同値)。
 */
export const VOTE_LIMIT = 3;
