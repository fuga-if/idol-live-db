import { DatabaseSync } from "node:sqlite";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
export const SCHEMA = readFileSync(join(here, "../schema.sql"), "utf8");

/** 空のスキーマだけの DB。 */
export function emptyDb(): DatabaseSync {
  const db = new DatabaseSync(":memory:");
  db.exec(SCHEMA);
  return db;
}

/** node:sqlite を D1 の形に見せる薄い殻 (テスト専用)。読んだ文の数を数える。 */
export function d1(db: DatabaseSync) {
  const stats = { statements: 0 };
  const shim = {
    prepare(sql: string) {
      const make = (args: unknown[]) => ({
        bind: (...a: unknown[]) => make(a),
        first: async () => {
          stats.statements++;
          return (db.prepare(sql).all(...(args as never[]))[0] as never) ?? null;
        },
        all: async () => {
          stats.statements++;
          return { results: db.prepare(sql).all(...(args as never[])) as never[] };
        },
      });
      return make([]);
    },
  };
  return { db: shim as unknown as D1Database, stats };
}

/** 本物の imas-fold-wasm (npm run wasm で作る)。無ければ null。 */
export async function realFold(): Promise<((s: string) => string) | null> {
  const wasm = join(here, "../src/fold/imas_fold_wasm_bg.wasm");
  if (!existsSync(wasm)) return null;
  const mod = await import("../src/fold/imas_fold_wasm.js");
  mod.initSync({ module: readFileSync(wasm) });
  return mod.fold;
}

export function memoryCache(): Cache {
  const store = new Map<string, Response>();
  return {
    match: async (req: Request) => store.get(req.url)?.clone(),
    put: async (req: Request, res: Response) => void store.set((req as Request).url, res),
  } as unknown as Cache;
}

export const ctx = { waitUntil: (p: Promise<unknown>) => void p.catch(() => {}), passThroughOnException() {} } as unknown as ExecutionContext;
