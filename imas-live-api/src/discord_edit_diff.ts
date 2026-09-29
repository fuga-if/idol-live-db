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

export interface ChangeField {
  label: string;
  before: string | null;
  after: string | null;
  /** 値が ID (名前に読み替える)。 */
  ref: boolean;
  /** 値をリンクにするときの URL (参考動画の YouTube など)。 */
  url?: string;
  /** 「＋ 追加したもの」「－ 消したもの」の形で出す (紐付けの追加・削除)。 */
  mark?: boolean;
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
  fields: ChangeField[];
  /** セトリの追加・削除曲 (songId)。 */
  addedSongs: string[];
  removedSongs: string[];
  reordered: boolean;
  performerDelta: { added: number; removed: number };
  /** 埋め込みの右上に出す画像 (参考動画のサムネイル)。 */
  thumbnail?: string;
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
  TicketSale: "チケット受付",
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
  startsAt: "受付開始",
  endsAt: "締切",
  resultAt: "当落発表",
  sourceUrl: "出典URL",
  showIds: "対象公演",
  kind: "受付形式",
  youtubeUrl: "動画URL",
  videoTitle: "動画タイトル",
};

/** YouTube の URL から動画 ID (watch / youtu.be / shorts / embed / live)。 */
export function youtubeId(url: string): string | null {
  const m = url.match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/|embed\/|live\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/);
  return m ? m[1] : null;
}

function short(text: string, max: number): string {
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

interface ChildRecord {
  parent: string;
  parentKey: string;
  what: string;
  /** 追加・削除したものの出し方。ref=true なら text は ID (名前に読み替える)。 */
  item: (f: Record<string, unknown>) => { text: string | null; ref: boolean; url?: string; thumbnail?: string };
}

const CHILD_RECORDS: Record<string, ChildRecord> = {
  SongArtist: { parent: "Song", parentKey: "songId", what: "歌唱メンバー", item: (f) => ({ text: asText(f.idolId), ref: true }) },
  ShowCast: { parent: "Show", parentKey: "showId", what: "出演者", item: (f) => ({ text: asText(f.idolId), ref: true }) },
  // セトリのスナップショットが無い batch (古い版のアプリ) の 1 曲ずつの追加・削除。
  SetlistItem: { parent: "Show", parentKey: "showId", what: "セトリの曲", item: (f) => ({ text: asText(f.songId), ref: true }) },
  SongVideo: {
    parent: "Song",
    parentKey: "songId",
    what: "参考動画",
    item: (f) => {
      const url = asText(f.youtubeUrl);
      const id = url ? youtubeId(url) : null;
      return {
        text: asText(f.videoTitle) ?? url,
        ref: false,
        ...(url?.startsWith("https://") ? { url } : {}),
        ...(id ? { thumbnail: `https://i.ytimg.com/vi/${id}/hqdefault.jpg` } : {}),
      };
    },
  },
  TicketSale: {
    parent: "Event",
    parentKey: "eventId",
    what: "チケット受付",
    item: (f) => {
      const url = asText(f.url);
      return { text: asText(f.name), ref: false, ...(url?.startsWith("https://") ? { url } : {}) };
    },
  },
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

  // 親を持つレコード (歌唱メンバー・出演者・参考動画・チケット受付・セトリの曲) は、
  // 自分の ID ではなく親 (曲・公演・イベント) の名前で「曲 X に Y を追加」の形にする。
  const child = CHILD_RECORDS[row.record_type];
  if (child) {
    const parentId = asText(merged[child.parentKey]) ?? row.record_name;
    const c = emptyChange(RECORD_LABELS[child.parent], parentId, pageUrl(child.parent, parentId));
    const item = child.item(merged);
    if (item.thumbnail) c.thumbnail = item.thumbnail;
    const field = (before: string | null, after: string | null): ChangeField => ({
      label: child.what, before, after, ref: item.ref, mark: true, ...(item.url ? { url: item.url } : {}),
    });
    if (row.op === "delete") c.fields.push(field(item.text, null));
    else if (row.op === "create" || !before) c.fields.push(field(null, item.text));
    else {
      for (const [key, value] of Object.entries(after ?? {})) {
        if (SKIP_FIELDS.has(key) || key.startsWith("___") || key === child.parentKey) continue;
        const bv = asText(before[key]);
        const av = asText(value);
        if (bv === av) continue;
        const name = item.ref ? null : item.text;
        c.fields.push({
          label: `${child.what}${name ? `「${short(name, 30)}」` : ""}の${FIELD_LABELS[key] ?? key}`,
          before: bv, after: av, ref: REF_FIELDS.has(key),
        });
      }
      if (c.fields.length === 0) c.verb = `${child.what}を修正`;
    }
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
