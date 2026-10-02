// Android の Apple Music サインインの受け渡し: 始めた端末だけが一度だけ取れる。
import { describe, expect, it } from "vitest";
import { callJson, call } from "./support/worker";

const DEV = { "X-Device-Id": "dev-a" };

describe("music-auth", () => {
  it("start → deposit → take は始めた端末に一度だけ渡す", async () => {
    const start = await callJson("POST", "/music-auth/start", { headers: DEV });
    expect(start.status).toBe(200);
    const code = start.body.code as string;

    const page = await call("GET", `/music-auth?code=${code}`);
    expect(page.status).toBe(200);
    expect(await page.text()).toContain("imaslivedb://music-auth");

    expect((await callJson("GET", `/music-auth/take?code=${code}`, { headers: DEV })).body).toEqual({ ready: false });
    expect((await callJson("POST", "/music-auth/deposit", { body: { code, token: "user-token" } })).status).toBe(200);
    // 別のトークンでの上書きは拒む。
    expect((await callJson("POST", "/music-auth/deposit", { body: { code, token: "other" } })).status).toBe(409);
    // 別の端末には渡さない。
    expect((await callJson("GET", `/music-auth/take?code=${code}`, { headers: { "X-Device-Id": "dev-b" } })).status).toBe(404);
    expect((await callJson("GET", `/music-auth/take?code=${code}`, { headers: DEV })).body).toEqual({ ready: true, token: "user-token" });
    // 渡したら消える。
    expect((await callJson("GET", `/music-auth/take?code=${code}`, { headers: DEV })).status).toBe(404);
  });

  it("知らない合言葉には預けさせない", async () => {
    const code = "00000000-0000-0000-0000-000000000000";
    expect((await callJson("POST", "/music-auth/deposit", { body: { code, token: "t" } })).status).toBe(404);
  });
});
