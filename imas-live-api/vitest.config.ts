import path from "node:path";
import { defineWorkersConfig, readD1Migrations } from "@cloudflare/vitest-pool-workers/config";

// テストは Workers ランタイム上で走らせる。Request/Response/crypto 等が本番と同じ実装に
// なるので、Node の polyfill と本番で挙動が割れる事故 (署名検証・ヘッダ大小文字等) を防げる。
//
// D1 は miniflare のローカル DB (本番には触らない)。各テストファイルの前に
// test/support/apply_migrations.ts が migrations/ を番号順に当てる。
// isolatedStorage (既定で有効) により、テスト内の書き込みはテストの終わりに巻き戻る。
export default defineWorkersConfig(async () => {
  const migrations = (await readD1Migrations(path.join(__dirname, "migrations"))).map((m) => ({
    ...m,
    // wrangler の分割は、最後の文の後ろに残ったコメント (0010 の末尾) を中身の無い 1 文として返す。
    // D1 は文を含まない SQL を拒むので、コメントだけの断片を落としてから当てる
    // (適用済みの migration は書き換えられない)。
    queries: m.queries.filter((q) => q.replace(/--[^\n]*/g, "").trim() !== ""),
  }));
  return {
    test: {
      include: ["test/**/*.test.ts"],
      setupFiles: ["./test/support/apply_migrations.ts", "./test/support/no_network.ts"],
      poolOptions: {
        workers: {
          wrangler: { configPath: "./wrangler.jsonc" },
          miniflare: {
            // nodejs_compat は vitest-pool-workers の要件。本番 Worker には不要なので
            // wrangler.jsonc は触らず、テスト実行時だけ足す。
            compatibilityFlags: ["nodejs_compat"],
            bindings: { TEST_MIGRATIONS: migrations },
          },
        },
      },
    },
  };
});
