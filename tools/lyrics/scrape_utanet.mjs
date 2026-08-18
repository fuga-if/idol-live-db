#!/usr/bin/env node
/**
 * links.tsv の歌ネット直リンクを全件まわして、歌詞本文とクレジットを
 * lyrics_local/lyrics/<song_id>.json に落とす。
 *
 * lyrics_local/ は .gitignore 済み。歌詞本文はリポジトリにも公開ダンプにも入れない。
 * JASRAC 認可が下りるまでこの JSON は手元の下書き置き場でしかない。
 *
 * 使い方:
 *   node tools/lyrics/scrape_utanet.mjs                 # high のみ (既定)
 *   node tools/lyrics/scrape_utanet.mjs --all           # low / cover も含める
 *   node tools/lyrics/scrape_utanet.mjs --limit 20      # 先頭20件だけ試す
 *   node tools/lyrics/scrape_utanet.mjs --force         # 取得済みも上書き
 *
 * オプション:
 *   --all             confidence が high 以外 (low / cover) も対象にする
 *   --only <a,b>      confidence を明示指定 (例: --only cover)
 *   --limit <n>       先頭 n 件で打ち切り
 *   --concurrency <n> 同時実行数 (既定 3)
 *   --delay <ms>      1リクエストごとの待ち (既定 700)
 *   --force           既存 JSON があっても取り直す
 *   --retry <n>       失敗時のリトライ回数 (既定 2)
 */

import { chromium } from "playwright";
import { readFile, writeFile, mkdir, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const LINKS_TSV = path.join(ROOT, "tools/lyrics/links.tsv");
const OUT_DIR = path.join(ROOT, "lyrics_local/lyrics");
const FAIL_TSV = path.join(ROOT, "lyrics_local/scrape_failed.tsv");

const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

// ---------------------------------------------------------------- args

function parseArgs(argv) {
  const o = {
    only: ["high"],
    limit: Infinity,
    concurrency: 3,
    delay: 700,
    force: false,
    retry: 2,
  };
  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case "--all":         o.only = ["high", "low", "cover"]; break;
      case "--only":        o.only = argv[++i].split(",").map((s) => s.trim()); break;
      case "--limit":       o.limit = Number(argv[++i]); break;
      case "--concurrency": o.concurrency = Number(argv[++i]); break;
      case "--delay":       o.delay = Number(argv[++i]); break;
      case "--retry":       o.retry = Number(argv[++i]); break;
      case "--force":       o.force = true; break;
      default:
        console.error(`不明なオプション: ${argv[i]}`);
        process.exit(1);
    }
  }
  return o;
}

const opts = parseArgs(process.argv.slice(2));

// ---------------------------------------------------------------- links.tsv

/** movie/NNN と song/NNN は同じ曲ID。歌詞ページは song 側にある。 */
function normalizeUrl(url) {
  const m = url.match(/^https?:\/\/(?:www\.)?uta-net\.com\/(?:song|movie)\/(\d+)\/?/);
  return m ? `https://www.uta-net.com/song/${m[1]}/` : null;
}

async function loadTargets() {
  const text = await readFile(LINKS_TSV, "utf8");
  const [header, ...rows] = text.split("\n").filter((l) => l.length > 0);
  const cols = header.split("\t");
  const idx = Object.fromEntries(cols.map((c, i) => [c, i]));

  const targets = [];
  for (const line of rows) {
    const f = line.split("\t");
    const confidence = (f[idx.confidence] ?? "").trim();
    if (!opts.only.includes(confidence)) continue;

    const url = normalizeUrl((f[idx.candidate_url] ?? "").trim());
    if (!url) continue;

    targets.push({
      song_id: f[idx.song_id],
      title: f[idx.title],
      artist: f[idx.artist],
      confidence,
      url,
    });
  }
  return targets;
}

// ---------------------------------------------------------------- 変換

/** #kashi_area の innerHTML を lines[] に割る。マーカーは後から人が足す。 */
function htmlToLines(html) {
  return html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .split("\n")
    .map((s) => s.replace(/\s+$/, ""))
    .reduce((acc, text) => {
      // 空行が続いてもブロック区切りは1つで足りる
      if (!text.trim()) {
        if (acc.length && acc[acc.length - 1].kind !== "blank") {
          acc.push({ kind: "blank", text: "" });
        }
        return acc;
      }
      acc.push({ kind: "lyric", text: text.trim() });
      return acc;
    }, [])
    .filter((l, i, a) => !(l.kind === "blank" && (i === 0 || i === a.length - 1)));
}

// ---------------------------------------------------------------- 取得

/**
 * コンテキストは1曲ごとに使い捨てる。使い回すと2曲目以降 #kashi_area が
 * 出てこなくなる (歌ネット側がセッションを見て別のページを返している)。
 */
async function scrapeOne(browser, target) {
  const context = await browser.newContext({
    userAgent: UA,
    viewport: { width: 1280, height: 900 },
    locale: "ja-JP",
  });
  const page = await context.newPage();
  // 画像・フォント・動画は歌詞に要らない。相手のサーバも軽くなる。
  // CSS は落とさない。落とすと #kashi_area が visible 判定にならない場合がある。
  await page.route("**/*", (route) => {
    const type = route.request().resourceType();
    return ["image", "font", "media"].includes(type) ? route.abort() : route.continue();
  });

  try {
    await page.goto(target.url, { waitUntil: "domcontentloaded", timeout: 30000 });
    // innerHTML を読むだけなので attached で足りる (visible は表示状態に左右される)
    await page.waitForSelector("#kashi_area", { state: "attached", timeout: 20000 });

    const data = await page.evaluate(() => {
      const text = (sel) => document.querySelector(sel)?.textContent?.trim() ?? "";
      return {
        html: document.querySelector("#kashi_area")?.innerHTML ?? "",
        lyricist: text('[itemprop="lyricist"]'),
        composer: text('[itemprop="composer"]'),
        arranger: text('[itemprop="arranger"]'),
        utanetArtist: text('[itemprop="byArtist"]'),
        utanetTitle: text(".song-title, h2.ms-2"),
      };
    });

    const lines = htmlToLines(data.html);
    if (lines.length === 0) throw new Error("歌詞が空だった");

    return {
      song_id: target.song_id,
      title: target.title,
      source: target.url,
      note: "",
      confidence: target.confidence,
      scraped: {
        utanet_title: data.utanetTitle,
        utanet_artist: data.utanetArtist,
        lyricist: data.lyricist,
        composer: data.composer,
        arranger: data.arranger,
      },
      lines,
    };
  } finally {
    await context.close();
  }
}

// ---------------------------------------------------------------- main

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

await mkdir(OUT_DIR, { recursive: true });

const done = opts.force
  ? new Set()
  : new Set((await readdir(OUT_DIR)).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)));

const all = await loadTargets();
const remaining = all.filter((t) => !done.has(t.song_id));
const queue = remaining.slice(0, opts.limit);

console.error(
  `[start] 対象 ${all.length} 件 / 取得済み ${all.length - remaining.length} 件 / ` +
    `今回 ${queue.length} 件 (confidence: ${opts.only.join(",")})`
);
if (queue.length === 0) {
  console.error("[done] 取り残しなし");
  process.exit(0);
}

const browser = await chromium.launch({ headless: true });

let cursor = 0;
let ok = 0;
const failures = [];

async function worker(id) {
  // 同時実行分をずらして立ち上げ、相手に同時着弾させない
  await sleep(id * opts.delay);
  while (cursor < queue.length) {
    const target = queue[cursor++];
    const n = cursor;

    let lastErr;
    for (let attempt = 0; attempt <= opts.retry; attempt++) {
      try {
        const result = await scrapeOne(browser, target);
        const out = path.join(OUT_DIR, `${target.song_id.replace(/[/\\\0]/g, "_")}.json`);
        await writeFile(out, JSON.stringify(result, null, 2) + "\n", "utf8");
        ok++;
        console.error(
          `[${n}/${queue.length}] ok  ${target.song_id}  (${result.lines.length}行)`
        );
        lastErr = null;
        break;
      } catch (err) {
        lastErr = err;
        if (attempt < opts.retry) await sleep(1500 * (attempt + 1));
      }
    }

    if (lastErr) {
      failures.push({ ...target, error: lastErr.message });
      console.error(`[${n}/${queue.length}] NG  ${target.song_id}  ${lastErr.message}`);
    }

    await sleep(opts.delay * opts.concurrency);
  }
}

await Promise.all(
  Array.from({ length: opts.concurrency }, (_, i) => worker(i))
);

await browser.close();

if (failures.length) {
  await writeFile(
    FAIL_TSV,
    ["song_id\ttitle\turl\tconfidence\terror"]
      .concat(
        failures.map((f) =>
          [f.song_id, f.title, f.url, f.confidence, f.error.replace(/\s+/g, " ")].join("\t")
        )
      )
      .join("\n") + "\n",
    "utf8"
  );
  console.error(`[fail] ${failures.length} 件を ${FAIL_TSV} に記録`);
}

console.error(`[done] 成功 ${ok} / 失敗 ${failures.length} / 対象 ${queue.length}`);
