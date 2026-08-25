import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

// テストは Workers ランタイム上で走らせる。Request/Response/crypto 等が本番と同じ実装に
// なるので、Node の polyfill と本番で挙動が割れる事故 (署名検証・ヘッダ大小文字等) を防げる。
export default defineWorkersConfig({
  test: {
    include: ["test/**/*.test.ts"],
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.jsonc" },
        // nodejs_compat は vitest-pool-workers の要件。本番 Worker には不要なので
        // wrangler.jsonc は触らず、テスト実行時だけ足す。
        miniflare: { compatibilityFlags: ["nodejs_compat"] },
      },
    },
  },
});
