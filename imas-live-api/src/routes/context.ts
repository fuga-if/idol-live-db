// routes/context.ts — ルートハンドラが index.ts から受け取るもの。
//
// json / error / rateLimitResponse / rateLimitSimple はリクエストごとに作られる
// クロージャ (CORS ヘッダを閉じ込んでいる) なので、import ではなく引数で渡す。
// env / url / path / request / requestId も同様にルーター側の値をそのまま渡す。
// どのルートもこの 1 つの型を受け取る (ルートごとに依存を注入する方式は使わない)。

import type { Env } from "../env";

export interface RouteContext {
  request: Request;
  env: Env;
  url: URL;
  path: string;
  /** このリクエストの ID。応答の X-Request-Id と、失敗のログの突き合わせに使う。 */
  requestId: string;
  json: (data: unknown, status?: number, headers?: Record<string, string>) => Response;
  error: (message: string, status?: number) => Response;
  rateLimitResponse: (used: number, limit: number, resetAt: string) => Response;
  rateLimitSimple: (retryAfter?: number) => Response;
  /**
   * ExecutionContext.waitUntil (bind 済み)。応答を返した後に走らせてよい副作用
   * (エッジキャッシュへの書き込み等) 用。渡されていないルートは await すればよいので任意。
   */
  waitUntil?: (promise: Promise<unknown>) => void;
}
