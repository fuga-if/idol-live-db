// 入口 (index.ts) の共通の層: CORS・Origin の検査・セキュリティヘッダ・request id・404・
// エッジキャッシュ (Cache API)。ルートの中身ではなく「どのルートにも共通で掛かる処理」を固める。
//
// ルーティングの作りを差し替える (Hono の導入) ときに、ここが最初に壊れる所なので
// 振る舞いを先に書き留めておく。各ルートの内容は個別のテストファイルにある。

import { describe, expect, it } from "vitest";
import { bearer, call, callJson, device, makeEnv, request as makeRequest, fetchWorker, BASE } from "./support/worker";

const ORIGIN = "https://web.example.test";
const OTHER_ORIGIN = "https://evil.example.test";
const corsEnv = () => makeEnv({ ALLOWED_ORIGINS: `${ORIGIN}, https://second.example.test` });

/** 同じ URL を 2 回叩かないよう、テストごとに URL を変える (エッジキャッシュに載るため)。 */
const uniq = () => crypto.randomUUID();

describe("CORS", () => {
  it("OPTIONS はプリフライトだけ返す (本文なし)。許可した Origin はそのまま返す", async () => {
    const res = await call("OPTIONS", "/favorites/ranking", { headers: { Origin: ORIGIN }, env: corsEnv() });
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("");
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(ORIGIN);
    expect(res.headers.get("Access-Control-Allow-Methods")).toBe("GET, POST, PUT, DELETE, OPTIONS");
    expect(res.headers.get("Access-Control-Allow-Headers")).toBe("Content-Type, Authorization, X-Device-Id");
    expect(res.headers.get("Vary")).toBe("Origin");
    expect(res.headers.get("X-Request-Id")).toBeTruthy();
  });

  it("許可していない Origin と Origin なし (iOS) には Allow-Origin を付けない。Vary は常に付ける", async () => {
    const denied = await call("OPTIONS", "/favorites/ranking", { headers: { Origin: OTHER_ORIGIN }, env: corsEnv() });
    expect(denied.headers.get("Access-Control-Allow-Origin")).toBeNull();
    expect(denied.headers.get("Vary")).toBe("Origin");

    const native = await call("OPTIONS", "/favorites/ranking", { env: corsEnv() });
    expect(native.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("ALLOWED_ORIGINS が空なら、どの Origin にも付けない", async () => {
    const res = await call("OPTIONS", "/favorites/ranking", { headers: { Origin: ORIGIN } });
    expect(res.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("GET の応答にも Origin ごとの CORS ヘッダが乗る", async () => {
    const res = await call("GET", `/favorites/ranking?t=${uniq()}`, { headers: { Origin: ORIGIN }, env: corsEnv() });
    expect(res.status).toBe(200);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(ORIGIN);
  });
});

describe("書き込みの Origin 検査", () => {
  const body = { song_id: "s1", value: true };

  it("許可していない Origin からの書き込みは 403 で、ルートに届かない", async () => {
    const res = await callJson("POST", "/favorites/toggle", {
      headers: { Origin: OTHER_ORIGIN, ...device("dev-origin") }, body, env: corsEnv(),
    });
    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden: origin not allowed" });
    expect(res.res.headers.get("Vary")).toBe("Origin");
    expect(res.res.headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(res.res.headers.get("X-Request-Id")).toBeTruthy();
  });

  it("Origin なし (iOS) と許可した Origin からの書き込みは通る", async () => {
    expect((await callJson("POST", "/favorites/toggle", { headers: device("dev-a"), body, env: corsEnv() })).status).toBe(200);
    expect((await callJson("POST", "/favorites/toggle", {
      headers: { Origin: ORIGIN, ...device("dev-b") }, body, env: corsEnv(),
    })).status).toBe(200);
  });

  it("読み取りは Origin を検査しない (許可していない Origin でも通す)", async () => {
    const res = await call("GET", `/favorites/ranking?t=${uniq()}`, { headers: { Origin: OTHER_ORIGIN }, env: corsEnv() });
    expect(res.status).toBe(200);
  });

  it.each(["POST", "PUT", "DELETE"])("%s は書き込みとして検査する", async (method) => {
    const res = await call(method, "/favorites/toggle", { headers: { Origin: OTHER_ORIGIN }, body, env: corsEnv() });
    expect(res.status).toBe(403);
  });
});

describe("共通のヘッダと 404", () => {
  it("JSON の応答には nosniff と request id が付く", async () => {
    const res = await call("GET", `/favorites/ranking?t=${uniq()}`);
    expect(res.headers.get("Content-Type")).toContain("application/json");
    expect(res.headers.get("X-Content-Type-Options")).toBe("nosniff");
  });

  it("知らないパスは request id 付きの 404", async () => {
    const res = await callJson("GET", `/no-such-endpoint?t=${uniq()}`);
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "Not found" });
    expect(res.res.headers.get("X-Request-Id")).toBeTruthy();
  });

  it("知っているパスでも method が違えば 404", async () => {
    expect((await callJson("PUT", "/favorites/ranking")).status).toBe(404);
  });
});

describe("エッジキャッシュ", () => {
  /** 同じ URL を 2 回叩き、2 回目がキャッシュから返ったかを返す。 */
  async function twice(path: string, headers: Record<string, string> = {}) {
    const first = await fetchWorker(makeRequest("GET", path, { headers }));
    await first.text();
    const second = await fetchWorker(makeRequest("GET", path, { headers }));
    await second.text();
    return [first.headers.get("X-Edge-Cache"), second.headers.get("X-Edge-Cache")];
  }

  /**
   * その URL のエッジキャッシュに目印の応答を仕込む。
   * 入口がキャッシュを読む経路なら、この目印がそのまま返る (= 読みを外していない)。
   * 応答が no-store の口は「書かない」だけでは確かめたことにならないので、読み側をこれで試す。
   */
  async function plant(path: string): Promise<void> {
    const key = new Request(`${BASE}${path}`, { method: "GET" });
    await caches.default.put(
      key,
      new Response(JSON.stringify({ planted: true }), {
        headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "public, max-age=60" },
      })
    );
  }

  it("公開 GET (Cache-Control: public) の 2 回目はエッジから返る", async () => {
    expect(await twice(`/favorites/ranking?t=${uniq()}`)).toEqual([null, "HIT"]);
  });

  it("Authorization 付きは読みも書きもしない (個人データを共有キャッシュに載せない)", async () => {
    const path = `/favorites/ranking?t=${uniq()}`;
    const auth = await bearer("001094.cache");
    expect(await twice(path, auth)).toEqual([null, null]);
    // 認証なしで叩いても、認証付きの応答は載っていない
    expect(await twice(path)).toEqual([null, "HIT"]);
  });

  it("歌詞の読み取りはエッジを読まない (エッジで返すとリクエスト回数が数えられない)", async () => {
    // 認証ヘッダは付けない。付けると Authorization の除外が先に効いて、
    // パスでの除外 (isLyricsRead) を試したことにならない。
    for (const path of [`/songs/s_cache/lyrics?t=${uniq()}`, `/lyrics/search?q=てすと&t=${uniq()}`]) {
      await plant(path);
      const res = await callJson("GET", path);
      expect(res.res.headers.get("X-Edge-Cache"), path).toBeNull();
      expect(res.body?.planted, path).toBeUndefined();
    }
  });

  it("曲詳細は端末ヘッダ付きのとき、エッジを読まない (他人の my_* を配らない)", async () => {
    const path = `/songs/s_cache/detail?t=${uniq()}`;
    await plant(path);
    const withDevice = await callJson("GET", path, { headers: device("dev-detail") });
    expect(withDevice.res.headers.get("X-Edge-Cache")).toBeNull();
    expect(withDevice.body.planted).toBeUndefined();
    // 端末ヘッダなしなら従来どおりエッジで賄う
    const shared = await callJson("GET", path);
    expect(shared.res.headers.get("X-Edge-Cache")).toBe("HIT");
    expect(shared.body.planted).toBe(true);
  });

  it("Cache-Control が public でない応答 (404) は載せない", async () => {
    expect(await twice(`/no-such-endpoint?t=${uniq()}`)).toEqual([null, null]);
  });
});
