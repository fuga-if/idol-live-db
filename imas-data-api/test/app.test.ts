import { beforeEach, describe, expect, it } from "vitest";
import { handle, resetMemo, type Deps, type Env } from "../src/app";
type J = any;
import { ctx, d1, emptyDb, memoryCache, realFold } from "./helpers";

const fold = (await realFold()) ?? ((s: string) => s.toLowerCase());
const hasRealFold = (await realFold()) !== null;

function setup() {
  const db = emptyDb();
  db.exec(`
    INSERT INTO meta VALUES ('version','v-test'),('generated_at','2026-10-01T00:00:00Z');
    INSERT INTO idols VALUES (1,'ml_a','ml','春日未来','かすが みく',0),(2,'ml_b','ml','最上静香','もがみ しずか',0),(3,'cg_c','cg','島村卯月','しまむら うづき',0);
    INSERT INTO songs VALUES (1,'s1','ml','Thank You!','Thank You!','2020-01-01'),(2,'s2','cg','ありがとう','ありがとう','2019-01-01');
    INSERT INTO song_idols VALUES ('ml_a',1);
    INSERT INTO units VALUES (1,'u1','ml','LiLiLiLi','りりりり',1);
    INSERT INTO docs VALUES ('idol','ml_a','{"id":"ml_a","name":"春日未来"}'),('brands','all','{"brands":[]}');
  `);
  const t = (kind: string, s: string, ord: number) =>
    db.prepare("INSERT INTO terms VALUES (?,?,?)").run(kind, fold(s), ord);
  t("idol", "春日未来", 1); t("idol", "かすが みく", 1); t("idol", "最上静香", 2); t("idol", "島村卯月", 3);
  t("song", "Thank You!", 1); t("song", "ありがとう", 2);
  const { db: env, stats } = d1(db);
  let limited = false;
  const e: Env = {
    DB: env,
    RATE_LIMITER: { limit: async () => ({ success: !limited }) },
  };
  const deps: Deps = { fold, cache: memoryCache() };
  const get = (path: string, init?: RequestInit) =>
    handle(new Request(`https://x.test${path}`, init), e, ctx, deps);
  return { get, stats, limit: () => (limited = true), deps };
}

beforeEach(() => resetMemo());

describe("ルーティング", () => {
  it("詳細は文書をそのまま返し、CORS とキャッシュ指示が付く", async () => {
    const { get } = setup();
    const r = await get("/v1/idols/ml_a");
    expect(r.status).toBe(200);
    expect(await r.text()).toBe('{"id":"ml_a","name":"春日未来"}');
    expect(r.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(r.headers.get("Cache-Control")).toBe("public, max-age=3600");
  });

  it("日本語 id は percent-encode のままでも引ける", async () => {
    const { get } = setup();
    expect((await get("/v1/idols/" + encodeURIComponent("ml_a"))).status).toBe(200);
    expect((await get("/v1/idols/%E3%81%82")).status).toBe(404);
  });

  it("無い id は 404 JSON、知らないパスも 404、POST は 405、OPTIONS は 204", async () => {
    const { get } = setup();
    const r = await get("/v1/songs/none");
    expect(r.status).toBe(404);
    expect((await r.json() as J).error.code).toBe("not_found");
    expect((await get("/")).status).toBe(404);
    expect((await get("/v1/idols/a", { method: "POST" })).status).toBe(405);
    const o = await get("/v1/idols", { method: "OPTIONS" });
    expect(o.status).toBe(204);
    expect(o.headers.get("Access-Control-Allow-Methods")).toContain("GET");
  });

  it("一覧はキーセットで続きを読める", async () => {
    const { get } = setup();
    const a = await (await get("/v1/idols?limit=2")).json() as J;
    expect(a.items.map((i: { id: string }) => i.id)).toEqual(["ml_a", "ml_b"]);
    expect(a.next_cursor).toBe(2);
    const b = await (await get("/v1/idols?limit=2&cursor=2")).json() as J;
    expect(b.items.map((i: { id: string }) => i.id)).toEqual(["cg_c"]);
    expect(b.next_cursor).toBeNull();
    expect(a.items[0].path).toBe("/v1/idols/ml_a");
  });

  it("brand と持ち歌 (idol) と前方一致で絞れる", async () => {
    const { get } = setup();
    expect((await (await get("/v1/idols?brand=cg")).json() as J).items.map((i: { id: string }) => i.id)).toEqual(["cg_c"]);
    expect((await (await get("/v1/songs?idol=ml_a")).json() as J).items.map((i: { id: string }) => i.id)).toEqual(["s1"]);
    expect((await (await get("/v1/idols?q=" + encodeURIComponent("春日"))).json() as J).items.map((i: { id: string }) => i.id)).toEqual(["ml_a"]);
    expect((await (await get("/v1/idols?q=" + encodeURIComponent("春日") + "&brand=cg")).json() as J).items).toEqual([]);
    expect((await (await get("/v1/songs?q=thank")).json() as J).items.map((i: { id: string }) => i.id)).toEqual(["s1"]);
  });

  it.runIf(hasRealFold)("かな・カナの揺れは本物の畳み込みで吸収される", async () => {
    const { get } = setup();
    expect((await (await get("/v1/idols?q=" + encodeURIComponent("カスガ"))).json() as J).items.map((i: { id: string }) => i.id)).toEqual(["ml_a"]);
  });

  it("不正な引数は 400 で、DB に行かない", async () => {
    const { get, stats } = setup();
    for (const p of ["limit=0", "limit=101", "limit=x", "cursor=-1", "brand=A%20B", "foo=1", "q=a&idol=b"]) {
      const path = p.startsWith("q=") ? `/v1/songs?${p}` : `/v1/idols?${p}`;
      expect((await get(path)).status, path).toBe(400);
    }
    expect(stats.statements).toBe(0);
  });
});

describe("費用の守り", () => {
  it("同じ要求の 2 回目はキャッシュに当たり、D1 を読まない", async () => {
    const { get, stats } = setup();
    await get("/v1/idols/ml_a");
    const before = stats.statements;
    const r = await get("/v1/idols/ml_a");
    expect(r.status).toBe(200);
    expect(stats.statements).toBe(before);
    // 引数の並びが違っても同じ鍵
    await get("/v1/idols?limit=5&brand=ml");
    const mid = stats.statements;
    await get("/v1/idols?brand=ml&limit=5");
    expect(stats.statements).toBe(mid);
  });

  it("キャッシュに無い要求は、制限を超えると 429 になる (当たる要求は通る)", async () => {
    const { get, limit } = setup();
    await get("/v1/idols/ml_a");
    limit();
    expect((await get("/v1/idols/ml_a")).status).toBe(200);
    const r = await get("/v1/songs/s1");
    expect(r.status).toBe(429);
    expect(r.headers.get("Retry-After")).toBe("60");
  });

  it("同期の版が変わるとキャッシュの鍵が変わる", async () => {
    const s = setup();
    await s.get("/v1/idols/ml_a");
    resetMemo();
    // 版を差し替える
    const db = emptyDb();
    db.exec(`INSERT INTO meta VALUES ('version','v2'); INSERT INTO docs VALUES ('idol','ml_a','{"id":"new"}');`);
    const { db: d } = d1(db);
    const r = await handle(new Request("https://x.test/v1/idols/ml_a"), {
      DB: d, RATE_LIMITER: { limit: async () => ({ success: true }) },
    }, ctx, s.deps);
    expect(await r.text()).toBe('{"id":"new"}');
  });
});
