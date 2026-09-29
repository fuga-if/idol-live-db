/**
 * セトリの歌唱者をどの名前で出すか — 閲覧者ごとの表示の好み。
 * 選択肢は `imas-core` の `performer_name_options`。出し入れは `store.ts`。
 */
import { readPref, writePref } from "./store";

const KEY = "performerName";

export const readMode = (known: readonly string[], fallback: string) => readPref(KEY, known, fallback);
export const writeMode = (mode: string, fallback: string) => writePref(KEY, mode, fallback);
