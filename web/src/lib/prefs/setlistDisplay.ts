/**
 * セトリの詳しさ (シンプル / 普通 / 詳細) — 閲覧者ごとの表示の好み。
 * 選択肢は `imas-core` の `setlist_display_modes` (アプリの設定と同じ保存値)。出し入れは `store.ts`。
 */
import { readPref, writePref } from "./store";

const KEY = "setlistDisplay";

export const readMode = (known: readonly string[], fallback: string) => readPref(KEY, known, fallback);
export const writeMode = (mode: string, fallback: string) => writePref(KEY, mode, fallback);
