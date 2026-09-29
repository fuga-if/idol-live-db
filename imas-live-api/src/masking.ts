// masking.ts — 公開の応答に載せる前に、利用者を特定できる値を丸める。

/** 利用者の ID を応答に残す文字数 (アプリも先頭 8 文字 + "..." で表示している)。 */
const USER_REF_VISIBLE_CHARS = 8;

/**
 * 利用者の ID (端末 ID か uid) を、公開の応答に載せる形 (先頭 8 文字) にする。
 * 値の無い行 (NULL) は null のまま返す。表には全体を残し、応答でだけ丸める。
 * 使う所: タグの説明の編集履歴の edited_by、予想セトリ・出演者予想の一覧の first_voted_by。
 */
export function maskUserRef(value: unknown): string | null {
  return typeof value === "string" ? value.slice(0, USER_REF_VISIBLE_CHARS) : null;
}
