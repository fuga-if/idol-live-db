// discord_edit_diff.ts — #更新通知 に出す「データの編集」の中身 (何がどう変わったか) を組む。
//
// edit_history の before_json / after_json (サーバが CloudKit から権威取得した値と、送った値) を
// 比べて、項目ごとに「変更前 → 変更後」を出す。セトリは 1 公演ぶんのスナップショット行
// (record_type = 'ShowSetlist') があるので、個々の SetlistItem 行ではなくそれを見て、
// 追加・削除された曲と曲順の入れ替えをまとめる。
//
// ⚠️ 編集者は出さない (edit_batch.editor_id を読まない)。値は利用者が入れた文字列なので、
//    呼び出し側で md() を通して Markdown を無効化する (ここでは素の文字列を返す)。

const WEB_BASE = "https://idollivedb.fugaapp.site";

export interface HistoryRow {
  batch_id: number;
  record_type: string;
  record_name: string;
  op: string;
  before_json: string | null;
  after_json: string | null;
}

/** 1 レコード (またはセトリ 1 公演) ぶんの変化。 */
export interface Change {
  /** 見出しの種類 (曲・公演…)。 */
  label: string;
  /** 見出しの名前を引く ID (名前が値に無いとき)。 */
  nameId: string;
  /** 値に名前があればそれ。 */
  name: string | null;
  url: string | null;
  /** 「追加」「削除」など、項目の差分が無いときの一言。 */
  verb: string | null;
  /** 項目ごとの差分 [項目名, 変更前, 変更後]。値が ID のものは ref=true。 */
  fields: Array<{ label: string; before: string | null; after: string | null; ref: boolean }>;
  /** セトリの追加・削除曲 (songId)。 */
  addedSongs: string[];
  removedSongs: string[];
  reordered: boolean;
  performerDelta: { added: number; removed: number };
}

export const RECORD_LABELS: Record<string, string> = {
  SetlistItem: "セトリ",
  ShowSetlist: "セトリ",
  Song: "曲",
  Show: "公演",
  Event: "イベント",
  Idol: "アイドル",
  Unit: "ユニット",
  ImasUnit: "ユニット",
  Venue: "会場",
  SongArtist: "歌唱メンバー",
  ShowCast: "出演者",
  SongVideo: "参考動画",
};

const FIELD_LABELS: Record<string, string> = {
  title: "曲名",
  titleKana: "よみ",
  name: "名前",
  nameKana: "よみ",
  composer: "作曲",
  lyricist: "作詞",
  arranger: "編曲",
  releaseDate: "発売日",
  cdTitle: "収録CD",
  cdSeries: "CDシリーズ",
  durationSec: "長さ(秒)",
  note: "補足",
  notes: "メモ",
  date: "日付",
  startDate: "開始日",
  endDate: "終了日",
  venue: "会場",
  venueId: "会場",
  venueCity: "所在地",
  hall: "ホール",
  startTime: "開演",
  streamPlatform: "配信",
  performerType: "出演形態",
  venueMode: "会場の形態",
  position: "曲順",
  section: "セクション",
  songId: "曲",
  idolId: "アイドル",
  unitId: "ユニット",
  unitName: "ユニット名",
  eventId: "イベント",
  showId: "公演",
  url: "URL",
  description: "説明",
  singerLabel: "歌唱",
  lyricsUrl: "歌詞URL",
  appleMusicId: "Apple Music",
  artworkUrl: "ジャケ写",
  isSolo: "ソロ",
  isStreaming: "配信あり",
  role: "役割",
};

/** 名前に読み替える ID の項目。 */
const REF_FIELDS = new Set(["songId", "idolId", "unitId", "eventId", "showId", "venueId"]);
/** 差分に出さない項目。 */
const SKIP_FIELDS = new Set(["modifiedAt", "deletedAt", "sortOrder", "createdAt"]);

function parse(json: string | null): Record<string, unknown> | null {
  if (!json) return null;
  try {
    const v = JSON.parse(json);
    return v && typeof v === "object" ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function asText(v: unknown): string | null {
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return JSON.stringify(v);
}

function pageUrl(recordType: string, id: string): string | null {
  const path = { Song: "songs", Show: "shows", ShowSetlist: "shows", Event: "events", Idol: "idols" }[recordType];
  return path ? `${WEB_BASE}/${path}/${encodeURIComponent(id)}/` : null;
}

function emptyChange(label: string, nameId: string, url: string | null): Change {
  return {
    label, nameId, name: null, url, verb: null, fields: [],
    addedSongs: [], removedSongs: [], reordered: false, performerDelta: { added: 0, removed: 0 },
  };
}

function setlistChange(row: HistoryRow): Change {
  const before = parse(row.before_json) as { items?: any[]; performers?: any[] } | null;
  const after = parse(row.after_json) as { items?: any[]; performers?: any[] } | null;
  const songs = (s: { items?: any[] } | null) =>
    [...(s?.items ?? [])]
      .sort((a, b) => Number(a.fields?.position ?? 0) - Number(b.fields?.position ?? 0))
      .map((i) => String(i.fields?.songId ?? ""))
      .filter(Boolean);
  const b = songs(before);
  const a = songs(after);
  const c = emptyChange("セトリ", row.record_name, pageUrl("Show", row.record_name));
  // 多重集合の差 (同じ曲が 2 回入るセトリもある)。
  const rest = [...b];
  for (const id of a) {
    const i = rest.indexOf(id);
    if (i >= 0) rest.splice(i, 1);
    else c.addedSongs.push(id);
  }
  c.removedSongs = rest;
  c.reordered = c.addedSongs.length === 0 && c.removedSongs.length === 0 && a.join("\n") !== b.join("\n");
  const perfKeys = (s: { performers?: any[] } | null) =>
    new Set((s?.performers ?? []).map((p) => `${p.fields?.setlistItemId}|${p.fields?.idolId}`));
  const pb = perfKeys(before);
  const pa = perfKeys(after);
  c.performerDelta = {
    added: [...pa].filter((k) => !pb.has(k)).length,
    removed: [...pb].filter((k) => !pa.has(k)).length,
  };
  return c;
}

function recordChange(row: HistoryRow): Change {
  const before = parse(row.before_json);
  const after = parse(row.after_json);
  const label = RECORD_LABELS[row.record_type] ?? row.record_type;
  const merged = { ...(before ?? {}), ...(after ?? {}) };

  // 紐付けのレコード (歌唱メンバー・出演者) は「曲 X に Y を追加」の形にする。
  if (row.record_type === "SongArtist" || row.record_type === "ShowCast") {
    const parentType = row.record_type === "SongArtist" ? "Song" : "Show";
    const parentId = asText(merged[row.record_type === "SongArtist" ? "songId" : "showId"]) ?? row.record_name;
    const c = emptyChange(RECORD_LABELS[parentType], parentId, pageUrl(parentType, parentId));
    const idol = asText(merged.idolId);
    const what = row.record_type === "SongArtist" ? "歌唱メンバー" : "出演者";
    if (row.op === "delete") c.fields.push({ label: what, before: idol, after: null, ref: true });
    else if (row.op === "create" || !before) c.fields.push({ label: what, before: null, after: idol, ref: true });
    else c.verb = `${what}を修正`;
    return c;
  }

  const c = emptyChange(label, row.record_name, pageUrl(row.record_type, row.record_name));
  c.name = asText(merged.title) ?? asText(merged.name);
  if (row.op === "delete") {
    c.verb = "削除";
    return c;
  }
  if (row.op === "create" || !before) {
    c.verb = "追加";
    return c;
  }
  for (const [key, value] of Object.entries(after ?? {})) {
    if (SKIP_FIELDS.has(key) || key.startsWith("___")) continue;
    const bv = asText(before[key]);
    const av = asText(value);
    if (bv === av) continue;
    c.fields.push({ label: FIELD_LABELS[key] ?? key, before: bv, after: av, ref: REF_FIELDS.has(key) });
  }
  if (c.fields.length === 0) c.verb = "更新";
  return c;
}

/** batch ごとの変化。セトリのスナップショットがある batch では個々のセトリ行を使わない。 */
export function buildChanges(rows: HistoryRow[]): Map<number, Change[]> {
  const out = new Map<number, Change[]>();
  const withSnapshot = new Set(rows.filter((r) => r.record_type === "ShowSetlist").map((r) => r.batch_id));
  for (const row of rows) {
    if ((row.record_type === "SetlistItem" || row.record_type === "SetlistPerformer") && withSnapshot.has(row.batch_id)) {
      continue;
    }
    const change = row.record_type === "ShowSetlist" ? setlistChange(row) : recordChange(row);
    const list = out.get(row.batch_id) ?? [];
    list.push(change);
    out.set(row.batch_id, list);
  }
  return out;
}

/** 名前を引く必要がある ID (見出しと、値が ID の項目・セトリの曲)。 */
export function referencedIds(changes: Iterable<Change[]>): string[] {
  const ids = new Set<string>();
  for (const list of changes) {
    for (const c of list) {
      if (!c.name) ids.add(c.nameId);
      for (const f of c.fields) {
        if (!f.ref) continue;
        if (f.before) ids.add(f.before);
        if (f.after) ids.add(f.after);
      }
      for (const s of [...c.addedSongs, ...c.removedSongs]) ids.add(s);
    }
  }
  return [...ids];
}
