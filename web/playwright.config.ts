import { defineConfig, devices } from "@playwright/test";

/**
 * Web の E2E (ローカル専用。CI では回さない)。
 *
 * 対象はフィクスチャ (`data-fixture/`) でビルドした `dist/` を、本番と同じ配信
 * (`wrangler dev` = `_headers` の CSP・trailing slash・404 込み) で出したもの。
 * 外部への通信はテストが全部止めるか差し替える (`e2e/support/test.ts`)。
 *
 * どのテストがどのシナリオかは `e2e/ledger/scenarios/*.json` が正。
 * 使い方は e2e/README.md。
 */
const PORT = 8799;

export default defineConfig({
  testDir: "./e2e/tests",
  fullyParallel: true,
  forbidOnly: true,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: "retain-on-failure",
    locale: "ja-JP",
    timezoneId: "Asia/Tokyo",
  },
  projects: [
    { name: "pc", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile", use: { ...devices["Pixel 7"] } },
  ],
  webServer: {
    command: `npx wrangler dev --port ${PORT} --log-level warn`,
    url: `http://localhost:${PORT}/`,
    reuseExistingServer: true,
    timeout: 60_000,
    env: { WRANGLER_SEND_METRICS: "false" },
  },
});
