// cloudflare:test の env の型。wrangler.jsonc のバインディング (Env) に、
// vitest.config.ts がテスト用に足すバインディングを加えたもの。
import type { Env } from "../src/env";

declare module "cloudflare:test" {
  interface ProvidedEnv extends Env {
    TEST_MIGRATIONS: D1Migration[];
  }
}
