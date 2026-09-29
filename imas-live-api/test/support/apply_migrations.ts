// 各テストファイルの前に、ローカル D1 へ migrations/ を番号順に当てる (vitest.config.ts の setupFiles)。
// 当て済みの migration は d1_migrations に記録されるので、何度呼んでも二重には当たらない。
import { applyD1Migrations, env } from "cloudflare:test";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
