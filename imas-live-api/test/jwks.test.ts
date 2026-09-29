// JWKS のキャッシュ (jwt.ts の JwksCache)。
//   - 正常な応答だけをキャッシュし、失敗した取得は手元の前の鍵のまま少し待って取り直す。
//   - 知らない kid なら 1 回だけ取り直す。その取り直しは retryMs に 1 回まで。

import { fetchMock } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { JwksCache } from "../src/jwt";

const ORIGIN = "https://jwks.example.test";
const HOUR = 60 * 60 * 1000;
const RETRY = 60 * 1000;

const key = (kid: string) => ({ kty: "RSA", kid, n: "AQAB", e: "AQAB" });

let fetches = 0;
let path = "";

/** 次の取得 1 回ぶんの応答を用意する。 */
function serve(status: number, body: unknown) {
  fetchMock.get(ORIGIN).intercept({ path }).reply(() => {
    fetches += 1;
    return { statusCode: status, data: JSON.stringify(body) };
  });
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-09-23T00:00:00Z"));
  fetches = 0;
  path = `/keys-${crypto.randomUUID()}`;
});
afterEach(() => vi.useRealTimers());

function cache() {
  return new JwksCache(`${ORIGIN}${path}`, HOUR, RETRY);
}

describe("JwksCache", () => {
  it("1 時間はキャッシュから返す。切れたら取り直す", async () => {
    const jwks = cache();
    serve(200, { keys: [key("a")] });
    expect(await jwks.find("a")).toMatchObject({ kid: "a" });
    expect(await jwks.find("a")).toMatchObject({ kid: "a" });
    expect(fetches).toBe(1);

    vi.setSystemTime(Date.now() + HOUR);
    serve(200, { keys: [key("a")] });
    expect(await jwks.find("a")).toMatchObject({ kid: "a" });
    expect(fetches).toBe(2);
  });

  it("失敗した応答はキャッシュしない。少し待てば取り直して通る", async () => {
    const jwks = cache();
    serve(500, { error: "unavailable" });
    expect(await jwks.find("a")).toBeNull();
    expect(fetches).toBe(1); // 取ったばかりなので、同じ要求の中では取り直さない

    // 次の要求では、知らない kid として 1 回だけ取り直す。
    serve(500, { error: "unavailable" });
    expect(await jwks.find("a")).toBeNull();
    expect(fetches).toBe(2);

    // その後は RETRY たつまで取りに行かない。
    expect(await jwks.find("a")).toBeNull();
    expect(fetches).toBe(2);

    vi.setSystemTime(Date.now() + RETRY);
    serve(200, { keys: [key("a")] });
    expect(await jwks.find("a")).toMatchObject({ kid: "a" });
    expect(fetches).toBe(3);
  });

  it("鍵が入れ替わった直後の知らない kid は、1 回だけ取り直して通る", async () => {
    const jwks = cache();
    serve(200, { keys: [key("old")] });
    expect(await jwks.find("old")).toMatchObject({ kid: "old" });

    serve(200, { keys: [key("old"), key("new")] });
    expect(await jwks.find("new")).toMatchObject({ kid: "new" });
    expect(fetches).toBe(2);
  });

  it("知らない kid を並べても、取り直しは RETRY に 1 回まで", async () => {
    const jwks = cache();
    serve(200, { keys: [key("a")] });
    await jwks.find("a");
    serve(200, { keys: [key("a")] });
    expect(await jwks.find("x1")).toBeNull();
    expect(await jwks.find("x2")).toBeNull();
    expect(await jwks.find("x3")).toBeNull();
    expect(fetches).toBe(2);

    vi.setSystemTime(Date.now() + RETRY);
    serve(200, { keys: [key("a"), key("x4")] });
    expect(await jwks.find("x4")).toMatchObject({ kid: "x4" });
    expect(fetches).toBe(3);
  });

  it("取り直しに失敗したら、手元の前の鍵を使う", async () => {
    const jwks = cache();
    serve(200, { keys: [key("a")] });
    await jwks.find("a");

    vi.setSystemTime(Date.now() + HOUR);
    serve(503, "down");
    expect(await jwks.find("a")).toMatchObject({ kid: "a" });
    expect(fetches).toBe(2);
  });

  it("keys の無い応答も失敗として扱い、キャッシュしない", async () => {
    const jwks = cache();
    serve(200, { nope: true });
    expect(await jwks.find("a")).toBeNull();
    serve(200, { keys: [key("a")] });
    expect(await jwks.find("a")).toMatchObject({ kid: "a" });
    expect(fetches).toBe(2);
  });
});
