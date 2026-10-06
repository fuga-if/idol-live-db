/**
 * `/p/` の island — このサイトで 2 つ目の、ブラウザ JS を使うページ (他は `/search/`)。
 *
 * やること: URL の `#` の後ろ (保存してある形そのもの) を wasm に渡して読み解き、
 * 返ってきた値をそのまま DOM に置く。**判断はここに無い** — 担当・次の現場の名前や
 * 色・URL は id を `p/catalog.json` (ビルド時に Rust が出した台帳) と突き合わせるだけで、
 * 一致しない id (台帳に無い = アイドルが消えた/公演が過去になった) は黙って出さない。
 *
 * 名刺の読み解き自体が失敗したとき (版が違う・URL が壊れている) は
 * `catalog.unreadableText` を出す。どちらの場合も「アプリで開く」導線は出す
 * (名刺が読めなくても、アプリの方は読めるかもしれない)。
 */
import { decodeCard, decodeCardFace } from "./decode";
import type { CardCatalog } from "../schema/CardCatalog";
import type { Ref } from "../schema/Ref";
import type { CardFace, CardLinkView, CardOshiEntry, CardView } from "./types";

interface Elements {
  root: HTMLElement;
  status: HTMLElement;
  card: HTMLElement;
  band: HTMLElement;
  imprint: HTMLElement;
  name: HTMLElement;
  faceOshi: HTMLElement;
  handle: HTMLElement;
  details: HTMLElement;
  oshiSection: HTMLElement;
  linksSection: HTMLElement;
  message: HTMLElement;
  since: HTMLElement;
  oshi: HTMLElement;
  links: HTMLElement;
  showCount: HTMLElement;
  songCount: HTMLElement;
  next: HTMLElement;
  asof: HTMLElement;
  caseBox: HTMLElement;
  caseNote: HTMLElement;
  caseScheme: HTMLAnchorElement;
  unreadable: HTMLElement;
}

function elements(): Elements | null {
  const root = document.querySelector<HTMLElement>("[data-meishi]");
  const status = document.querySelector<HTMLElement>("[data-meishi-status]");
  const card = document.querySelector<HTMLElement>("[data-meishi-card]");
  const band = document.querySelector<HTMLElement>("[data-meishi-band]");
  const imprint = document.querySelector<HTMLElement>("[data-meishi-imprint]");
  const name = document.querySelector<HTMLElement>("[data-meishi-name]");
  const faceOshi = document.querySelector<HTMLElement>("[data-meishi-face-oshi]");
  const handle = document.querySelector<HTMLElement>("[data-meishi-handle]");
  const details = document.querySelector<HTMLElement>("[data-meishi-details]");
  const oshiSection = document.querySelector<HTMLElement>("[data-meishi-oshi-section]");
  const linksSection = document.querySelector<HTMLElement>("[data-meishi-links-section]");
  const message = document.querySelector<HTMLElement>("[data-meishi-message]");
  const since = document.querySelector<HTMLElement>("[data-meishi-since]");
  const oshi = document.querySelector<HTMLElement>("[data-meishi-oshi]");
  const links = document.querySelector<HTMLElement>("[data-meishi-links]");
  const showCount = document.querySelector<HTMLElement>("[data-meishi-show-count]");
  const songCount = document.querySelector<HTMLElement>("[data-meishi-song-count]");
  const next = document.querySelector<HTMLElement>("[data-meishi-next]");
  const asof = document.querySelector<HTMLElement>("[data-meishi-asof]");
  const caseBox = document.querySelector<HTMLElement>("[data-meishi-case]");
  const caseNote = document.querySelector<HTMLElement>("[data-meishi-case-note]");
  const caseScheme = document.querySelector<HTMLAnchorElement>("[data-meishi-case-scheme]");
  const unreadable = document.querySelector<HTMLElement>("[data-meishi-unreadable]");
  if (
    !root || !status || !card || !band || !imprint || !name || !faceOshi || !handle || !details ||
    !oshiSection || !linksSection || !message || !since || !oshi || !links ||
    !showCount || !songCount || !next || !asof || !caseBox || !caseNote || !caseScheme ||
    !unreadable
  ) {
    return null;
  }
  return {
    root, status, card, band, imprint, name, faceOshi, handle, details, oshiSection, linksSection, message, since, oshi, links, showCount, songCount, next,
    asof, caseBox, caseNote, caseScheme, unreadable,
  };
}

async function loadCatalog(): Promise<CardCatalog> {
  const res = await fetch("/p/catalog.json");
  if (!res.ok) throw new Error(`台帳を取得できない: ${res.status}`);
  return (await res.json()) as CardCatalog;
}

function refById(refs: readonly Ref[], id: string): Ref | undefined {
  return refs.find((r) => r.id === id);
}

function renderOshi(el: HTMLElement, idolIds: readonly string[], idols: readonly Ref[]): Ref | null {
  el.replaceChildren();
  let primary: Ref | null = null;
  for (const id of idolIds) {
    const ref = refById(idols, id);
    if (!ref) continue;
    primary ??= ref;
    const li = document.createElement("li");
    const a = document.createElement("a");
    a.href = ref.path;
    a.textContent = ref.name;
    a.dataset.theme = ref.themeKey;
    li.append(a);
    el.append(li);
  }
  return primary;
}

function renderLinks(el: HTMLElement, links: readonly CardLinkView[]): void {
  el.replaceChildren();
  for (const link of links) {
    const li = document.createElement("li");
    const a = document.createElement("a");
    a.href = link.url;
    a.rel = "noopener";
    const label = document.createElement("span");
    label.className = "meishi-card__link-label";
    label.textContent = link.label;
    const display = document.createElement("span");
    display.className = "meishi-card__link-display";
    display.textContent = link.display;
    a.append(label, display);
    li.append(a);
    el.append(li);
  }
}

function renderNext(el: HTMLElement, showId: string | null, shows: readonly Ref[]): void {
  if (!showId) {
    el.hidden = true;
    return;
  }
  const ref = refById(shows, showId);
  if (!ref) {
    // 台帳に無い = もう今後の公演ではない。欄ごと出さない。
    el.hidden = true;
    return;
  }
  el.replaceChildren();
  const label = document.createElement("span");
  label.className = "meishi-card__next-label";
  label.textContent = "次の現場";
  const a = document.createElement("a");
  a.href = ref.path;
  a.textContent = ref.sub ? `${ref.name} (${ref.sub})` : ref.name;
  el.append(label, a);
  el.hidden = false;
}

/**
 * 名刺の表の担当。並べる人・ブランドごとのまとめ方・1 行の文言・畳む数は wasm (`producer_card_face`)。
 * 1 行の文言があればそれだけ (「星井美希 担当」)、無ければブランドごとに「765AS 星井美希」を並べる
 * (Web はアイドルの画像を持たないので、判子の代わりに名前を刷る)。
 */
function renderFaceOshi(el: HTMLElement, face: CardFace, idols: readonly Ref[]): void {
  el.replaceChildren();
  if (face.oshiIdolIds.length === 0) {
    el.hidden = true;
    return;
  }
  if (face.oshiCaption !== null) {
    el.textContent = face.oshiCaption;
  } else {
    for (const group of face.oshiGroups) {
      const names = group.idolIds
        .map((id) => refById(idols, id)?.name)
        .filter((n): n is string => n !== undefined);
      if (names.length === 0) continue;
      const span = document.createElement("span");
      span.className = "meishi-card__face-group";
      if (group.brandLabel) {
        const label = document.createElement("span");
        label.className = "meishi-card__face-brand";
        label.textContent = group.brandLabel;
        span.append(label);
      }
      span.append(names.join("・"));
      el.append(span);
    }
  }
  if (face.moreOshi > 0) {
    const more = document.createElement("span");
    more.className = "meishi-card__face-group";
    more.textContent = `+${face.moreOshi}`;
    el.append(more);
  }
  el.hidden = false;
}

/** 台帳にある担当だけを、wasm に渡す形 (名前とブランド) に詰める。 */
function drawableOshi(idolIds: readonly string[], catalog: CardCatalog): CardOshiEntry[] {
  return idolIds.flatMap((id) => {
    const ref = refById(catalog.idols, id);
    if (!ref) return [];
    const brandId = catalog.idolBrandIds[id] ?? "";
    return [{ idolId: id, name: ref.name, brandId, brandLabel: catalog.brandLabels[brandId] ?? "" }];
  });
}

function renderCard(e: Elements, card: CardView, face: CardFace, catalog: CardCatalog): void {
  e.name.textContent = card.name;
  // 左上の印字の頭 (PRODUCER PASS 等) はデザインごとに CSS が出す。ここは P 歴だけ。
  e.imprint.textContent = face.sinceImprint ?? "";
  renderFaceOshi(e.faceOshi, face, catalog.idols);
  e.handle.textContent = face.handle?.display ?? "";
  // デザインはキーを置くだけ (書体と並びは CSS の `[data-design]`)。
  e.card.dataset.design = card.design;

  e.message.textContent = card.message;
  e.message.hidden = card.message.length === 0;

  if (card.sinceYear !== null) {
    e.since.textContent = `${card.sinceYear}年からプロデューサー`;
    e.since.hidden = false;
  } else {
    e.since.hidden = true;
  }

  // 担当色の帯は先頭の担当 1 人分だけ (カード全体は塗らない。淡い色の地のカードは却下済み)。
  const primaryOshi = renderOshi(e.oshi, card.oshiIdolIds, catalog.idols);
  const theme = primaryOshi?.themeKey ?? "neutral";
  e.band.dataset.theme = theme;
  // ポップの名前の下線も担当色 (カードの地は塗らない。地色は --ds-surface のまま)。
  e.card.dataset.theme = theme;

  // 自分の QR はリンクの先頭に「QR」として出す (アプリの名刺と同じ並び)。
  renderLinks(e.links, card.qrLink ? [card.qrLink, ...card.links] : card.links);

  e.showCount.textContent = card.showCount !== null ? String(card.showCount) : "—";
  e.songCount.textContent = card.songCount !== null ? String(card.songCount) : "—";
  renderNext(e.next, card.nextShowId, catalog.upcomingShows);

  e.asof.textContent = card.issuedOnDisplay;

  e.oshiSection.hidden = e.oshi.childElementCount === 0;
  e.linksSection.hidden = e.links.childElementCount === 0;

  e.card.hidden = false;
  e.details.hidden = false;
}

async function run(): Promise<void> {
  const e = elements();
  if (!e) return;
  e.root.hidden = false;

  // `#` の後ろだけを渡す (保存してある形そのもの)。URL の組み方・origin の判断は
  // すべて wasm 側 (producer_card::decode_producer_card) に任せる。
  const payload = location.hash.slice(1);

  let catalog: CardCatalog;
  try {
    catalog = await loadCatalog();
  } catch {
    e.status.hidden = true;
    e.unreadable.hidden = false;
    return;
  }

  e.caseNote.textContent = catalog.appOpenNote;
  e.caseScheme.href = payload ? `${catalog.deeplinkPrefix}${payload}` : catalog.appStoreUrl;
  e.caseBox.hidden = false;

  if (!payload) {
    e.status.hidden = true;
    e.unreadable.hidden = false;
    return;
  }

  let card: CardView | null;
  try {
    card = await decodeCard(payload);
  } catch {
    card = null;
  }

  let face: CardFace | null = null;
  if (card) {
    // 台帳にある担当だけを渡す (無い担当は名刺に出さないので、畳む数にも数えない)。
    const drawable = drawableOshi(card.oshiIdolIds, catalog);
    try {
      face = await decodeCardFace(payload, drawable);
    } catch {
      face = null;
    }
  }

  e.status.hidden = true;
  if (!card || !face) {
    e.unreadable.hidden = false;
    return;
  }
  renderCard(e, card, face, catalog);
}

void run();
