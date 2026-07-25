// routes/context.ts — ルートハンドラが index.ts から受け取るもの。
//
// json / error / rateLimitResponse / rateLimitSimple はリクエストごとに作られる
// クロージャ (CORS ヘッダと request id を閉じ込んでいる) なので、import ではなく
// 引数で渡す。env / url / path / request も同様にルーター側の値をそのまま渡す。

import type { Env } from "../env";

export interface RouteContext {
  request: Request;
  env: Env;
  url: URL;
  path: string;
  json: (data: unknown, status?: number, headers?: Record<string, string>) => Response;
  error: (message: string, status?: number) => Response;
  rateLimitResponse: (used: number, limit: number, resetAt: string) => Response;
  rateLimitSimple: (retryAfter?: number) => Response;
}
