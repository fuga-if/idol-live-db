// Universal Links (AASA と /app/{events,shows,polls}/:id の着地ページ) と、アプリ証明の IP 上限。
//   - アプリ証明の IP 上限 (1 日 50 回) はアプリ証明の口だけに掛ける。共有リンクの着地ページの
//     閲覧 (OGP のクローラー等) で、同じ IP の端末のアプリ証明を 429 にしない。

import { describe, expect, it } from "vitest";
import { call, callJson, makeEnv, TEST_IP } from "./support/worker";
import { exec, rows } from "./support/d1";

const TODAY = () => new Date().toISOString().slice(0, 10);

async function exhaustAppAttestQuota() {
  await exec(
    "INSERT INTO rate_limits (user_id, date, action, count) VALUES (?, ?, 'app_attest', 50)",
    `ip:${TEST_IP}`, TODAY()
  );
}

describe("GET /.well-known/apple-app-site-association", () => {
  it("アプリが開けるパスだけを JSON で返す", async () => {
    const res = await call("GET", "/.well-known/apple-app-site-association");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/json");
    expect(res.headers.get("Cache-Control")).toBe("public, max-age=3600");
    expect(await res.json()).toEqual({
      applinks: {
        details: [{
          appIDs: ["GQ3WP34LFW.com.fugaif.ImasLiveDB"],
          components: [{ "/": "/app/events/*" }, { "/": "/app/shows/*" }, { "/": "/app/polls/*" }],
        }],
      },
    });
  });
});

describe("GET /app/{events,shows,polls}/:id (着地ページ)", () => {
  it("開催中のお題は 200 の HTML。CSP と nosniff を付ける", async () => {
    await exec(
      "INSERT INTO polls (id, title, description, target_type, created_by, ends_at) VALUES ('p1', '<好き>', 'せつめい', 'song', 'u', datetime('now', '+1 day'))"
    );
    const res = await call("GET", "/app/polls/p1");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
    expect(res.headers.get("Content-Security-Policy")).toBe(
      "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    );
    expect(res.headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(res.headers.get("X-Request-Id")).toBeTruthy();
    const html = await res.text();
    expect(html).toContain("<title>&lt;好き&gt; | アイドルライブDB</title>");
    expect(html).toContain("imaslivedb://polls/p1");
  });

  it("無いお題・名前を引けないイベント・壊れた percent-encoding は 404 の HTML", async () => {
    for (const path of ["/app/polls/none", "/app/events/ev_x", "/app/shows/%G0"]) {
      const res = await call("GET", path);
      expect(res.status, path).toBe(404);
      expect(res.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
    }
  });

  it("アプリ証明の IP 上限を使い切っていても開ける。枠も消費しない", async () => {
    await exhaustAppAttestQuota();
    const res = await call("GET", "/app/polls/none");
    expect(res.status).toBe(404);
    expect(res.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
    expect(await rows("SELECT count FROM rate_limits WHERE action = 'app_attest'")).toEqual([{ count: 50 }]);
  });
});

describe("アプリ証明の口 (/app/challenge など)", () => {
  it("チャレンジを返す。secret 未設定は 500", async () => {
    const res = await callJson("GET", "/app/challenge");
    expect(res.status).toBe(200);
    expect(Object.keys(res.body)).toEqual(["challenge"]);
    const noSecret = await callJson("GET", "/app/challenge", { env: makeEnv({ SESSION_JWT_SECRET: undefined }) });
    expect(noSecret.status).toBe(500);
  });

  it("IP ごとに 1 日 50 回まで", async () => {
    await exhaustAppAttestQuota();
    const res = await callJson("GET", "/app/challenge");
    expect(res.status).toBe(429);
    expect(res.body).toEqual({ error: "rate limited" });
    const attest = await callJson("POST", "/app/attest", { body: {} });
    expect(attest.status).toBe(429);
  });
});
