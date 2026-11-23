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

/**
 * 一覧に載っているお題へ着地し直す。ブラウザは読み込みの途中で 1 度だけ断片へ飛ぶが、そのあと
 * 文字の形 (Web フォント) が入ると上の節の高さが変わり、狙ったお題がヘッダの下や画面の外へずれる
 * (スマホの遅い回線ほど大きくずれ、「お題に飛ばない」に見える)。読み込みが落ち着いてから合わせ直す。
 * 利用者が自分で動かしたあとは触らない。
 */
function settleOnTarget(): void {
  const hash = window.location.hash;
  if (!hash.startsWith(FRAGMENT_PREFIX)) return;
  let target: HTMLElement | null = null;
  try {
    target = document.getElementById(decodeURIComponent(hash.slice(1)));
  } catch {
    target = null;
  }
  if (!target) return;
  const el = target;
  let userMoved = false;
  const stop = () => {
    userMoved = true;
  };
  for (const ev of ["wheel", "touchstart", "keydown"] as const) {
    window.addEventListener(ev, stop, { once: true, passive: true });
  }
  const align = () => {
    if (!userMoved) el.scrollIntoView({ block: "start" });
  };
  align();
  void document.fonts?.ready.then(align);
  if (document.readyState === "complete") requestAnimationFrame(align);
  else window.addEventListener("load", align, { once: true });
}

export function watchMissingPoll(): void {
  update();
  settleOnTarget();
  window.addEventListener("hashchange", update);
}
