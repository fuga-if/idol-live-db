/**
 * 閲覧者ごとの表示の好みを localStorage に出し入れするだけの層。
 *
 * **モードもラベルも既定もここに無い。** 選択肢は `imas-core` が `meta.json` 越しに配り、
 * 既定は HTML の `<option selected>` として描かれている (呼び出し側がそこから読む)。
 * サーバが描いた HTML は既定モードで出ているので、既定のままの閲覧者には JS が要らない。
 */
export function readPref(key: string, known: readonly string[], fallback: string): string {
  try {
    const v = localStorage.getItem(key);
    return v && known.includes(v) ? v : fallback;
  } catch {
    // プライベートウィンドウ等で localStorage が投げることがある。既定で続ける。
    return fallback;
  }
}

/** 既定のモードは保存しない (既定が変わったときに、選んでいない人まで古い既定に縛らない)。 */
export function writePref(key: string, mode: string, fallback: string): void {
  try {
    if (mode === fallback) localStorage.removeItem(key);
    else localStorage.setItem(key, mode);
  } catch {
    // 保存できなくても表示は切り替わる (次の訪問で既定に戻るだけ)。
  }
}
