// env.ts — Worker の環境バインディング (wrangler.jsonc の vars/secrets + D1)。
//
// index.ts / auth.ts / routes/ が同じ型を参照するため独立させている。
// 非秘密の値は wrangler.jsonc の vars、秘密は `wrangler secret put` で入れる。

export interface Env {
  DB: D1Database;
  APPLE_BUNDLE_ID: string;
  CLOUDKIT_KEY_ID: string;
  CLOUDKIT_PRIVATE_KEY: string;
  ADMIN_USER_IDS?: string;
  ALLOWED_ORIGINS?: string;
  SESSION_JWT_SECRET?: string;
  // クローンただ乗り対策 (App Attest / Play Integrity)
  APP_ATTEST_MODE?: string;        // "off" | "monitor" | "enforce" (既定 monitor)
  APP_ATTEST_ALLOW_DEV?: string;   // "true" のときだけ dev attestation (appattestdevelop) を許可
  GOOGLE_SERVICE_ACCOUNT?: string; // Play Integrity 検証用 (Android)
  GOOGLE_WEB_CLIENT_ID?: string;   // Android Sign in with Google の ID トークン検証用 (aud として使う Web クライアント ID)
  // マスタ修正リクエストの GitHub issue 化用 (secret: wrangler secret put GITHUB_TOKEN)。
  GITHUB_TOKEN?: string;
  GITHUB_REPO?: string;            // "owner/repo" 省略時 "fuga-if/idol-live-db"
}
