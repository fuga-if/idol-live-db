/**
 * 共有 URL (`/polls/#poll-<id>`) で開いたお題が、この一覧にまだ載っていないときの知らせ。
 *
 * お題は利用者の手でいつでも立つが、出面は日に 1 度しか作り直さない。立てた直後に共有された
 * お題はここに無いので、そのままだと一覧の頭が開くだけで何が起きたか分からない。
 * 知らせの文言と行き先の頭は Rust が焼き込む (この島は id を足して出し入れするだけ)。
 */
const FRAGMENT_PREFIX = "#poll-";

function update(): void {
  const notice = document.querySelector<HTMLElement>("[data-poll-missing]");
  const link = notice?.querySelector<HTMLAnchorElement>("[data-poll-missing-link]");
  if (!notice || !link) return;
  const hash = window.location.hash;
  const encoded = hash.startsWith(FRAGMENT_PREFIX) ? hash.slice(FRAGMENT_PREFIX.length) : "";
  let id = "";
  try {
    id = decodeURIComponent(encoded);
  } catch {
    id = "";
  }
  const missing = id !== "" && document.getElementById(`poll-${id}`) === null;
  notice.hidden = !missing;
  // 載っていないお題の断片ではブラウザはどこへも飛ばないので、知らせは一覧の頭 (見出しの下) に出る。
  if (missing) link.href = `${notice.dataset.appUrlPrefix ?? ""}${encodeURIComponent(id)}`;
}

export function watchMissingPoll(): void {
  update();
  window.addEventListener("hashchange", update);
}
