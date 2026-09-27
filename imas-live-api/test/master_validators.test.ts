import { describe, expect, it } from "vitest";
import { validateMasterEdit } from "../src/master_validators";

const ok = (input: Parameters<typeof validateMasterEdit>[0], isAdmin = false) =>
  validateMasterEdit(input, isAdmin);

describe("validateMasterEdit — recordType の入口", () => {
  it("未知の recordType を弾く", () => {
    expect(ok({ recordType: "Nope", op: "update", recordName: "x", fields: {} }))
      .toMatch(/unknown recordType/);
  });

  it("admin 専用型は一般ユーザーに開けない", () => {
    const input = { recordType: "Brand", op: "update" as const, recordName: "cg", fields: {} };
    expect(ok(input)).toMatch(/admin-only/);
    expect(ok(input, true)).toBeNull();
  });

  it("update / delete は recordName が要る", () => {
    expect(ok({ recordType: "Song", op: "update", fields: { title: "x" } }))
      .toMatch(/recordName is required/);
  });

  it("Idol は一般ユーザーが create / delete できない", () => {
    expect(ok({ recordType: "Idol", op: "create", fields: { name: "新人" } }))
      .toMatch(/creating Idol is not allowed/);
    expect(ok({ recordType: "Idol", op: "delete", recordName: "cg_島村卯月" }))
      .toMatch(/deleting Idol is not allowed/);
  });
});

describe("validateMasterEdit — フィールド allowlist", () => {
  it("allowlist 外のフィールドを弾き、admin は通す", () => {
    const input = {
      recordType: "Song",
      op: "update" as const,
      recordName: "cg_everafter",
      fields: { parentSongId: "cg_everlasting" },
    };
    expect(ok(input)).toMatch(/field parentSongId is not editable/);
    expect(ok(input, true)).toBeNull();
  });

  it("null / undefined は「変更なし・クリア」として素通しする", () => {
    expect(ok({
      recordType: "Song", op: "update", recordName: "cg_everlasting",
      fields: { appleMusicId: null, artworkUrl: null },
    })).toBeNull();
  });
});

describe("validateMasterEdit — 値の形式", () => {
  // アプリからの修正リクエスト 29 件が color を "#" 抜きで送ってきて、
  // マスタ規約 (#RRGGBB) と食い違ったまま issue になった事例の回帰テスト。
  it("Idol.color は #RRGGBB を要求する", () => {
    const withColor = (color: string) =>
      ok({ recordType: "Idol", op: "update", recordName: "sc_櫻木真乃", fields: { color } });
    expect(withColor("#FFBAD6")).toBeNull();
    expect(withColor("FFBAD6")).toMatch(/color must be #RRGGBB/);
    expect(withColor("#FFF")).toMatch(/color must be #RRGGBB/);
  });

  it("appleMusicId は数値 ID のみ", () => {
    const withId = (appleMusicId: string) =>
      ok({ recordType: "Song", op: "update", recordName: "cg_お願いシンデレラ", fields: { appleMusicId } });
    expect(withId("714819390")).toBeNull();
    expect(withId("id714819390")).toMatch(/numeric Apple Music ID/);
  });

  it("releaseDate は YYYY-MM-DD", () => {
    const withDate = (releaseDate: string) =>
      ok({ recordType: "Song", op: "update", recordName: "cg_everafter", fields: { releaseDate } });
    expect(withDate("2013-04-10")).toBeNull();
    expect(withDate("2013/04/10")).toMatch(/invalid format/);
  });

  it("Song.note は一般ユーザーが編集でき、長すぎる文は弾く", () => {
    const withNote = (note: string) =>
      ok({ recordType: "Song", op: "update", recordName: "ml_union", fields: { note } });
    expect(withNote("ミリシタ 1 周年記念楽曲")).toBeNull();
    expect(withNote("あ".repeat(201))).toMatch(/note/);
  });

  it("SongArtist.role は enum に限る", () => {
    const withRole = (role: string) =>
      ok({ recordType: "SongArtist", op: "create", fields: { songId: "s", idolId: "i", role } });
    expect(withRole("original")).toBeNull();
    expect(withRole("singer")).toMatch(/must be one of/);
  });

  it("INT64 の範囲外・非整数を弾く", () => {
    const withPosition = (position: unknown) =>
      ok({ recordType: "SetlistItem", op: "create", fields: { showId: "sh_x", songId: "sg_x", position } });
    expect(withPosition(1)).toBeNull();
    expect(withPosition(1.5)).toMatch(/must be an integer/);
    expect(withPosition(100000)).toMatch(/must be <= 1000/);
  });

  it("空文字はクリアとして許可する (形式チェックを掛けない)", () => {
    expect(ok({ recordType: "Idol", op: "update", recordName: "sc_櫻木真乃", fields: { color: "" } }))
      .toBeNull();
  });
});

describe("validateMasterEdit — create の必須フィールド", () => {
  it("必須が欠けていれば弾く", () => {
    expect(ok({ recordType: "SetlistItem", op: "create", fields: { showId: "sh_x", position: 1 } }))
      .toMatch(/field songId is required/);
  });

  it("update では必須チェックを掛けない (差分送信を許す)", () => {
    expect(ok({ recordType: "SetlistItem", op: "update", recordName: "sh_x_0001", fields: { position: 2 } }))
      .toBeNull();
  });
});

describe("validateMasterEdit — チケット情報 (回帰)", () => {
  // `ticketOpenDate` だけ FIELD_RULES.Event に無く、一般ユーザーが受付開始を
  // 入力するとイベント編集が丸ごと 400 になっていた。CloudKit にも DB にも列があり
  // iOS/Android どちらも送っているのに、Worker だけが知らない状態だった。
  it("受付開始・締切・当落・URL が 4 つとも通る", () => {
    expect(ok({
      recordType: "Event", op: "update", recordName: "ev_x",
      fields: {
        ticketOpenDate: "2026-09-01",
        ticketDeadline: "2026-09-10",
        ticketLotteryDate: "2026-09-15",
        ticketUrl: "https://example.com/ticket",
      },
    })).toBeNull();
  });

  it("知らないフィールドは従来どおり弾く", () => {
    expect(ok({
      recordType: "Event", op: "update", recordName: "ev_x",
      fields: { ticketNopeDate: "2026-09-01" },
    })).toMatch(/ticketNopeDate/);
  });
});

describe("validateMasterEdit — TicketSale (チケット受付)", () => {
  const base = {
    eventId: "ev_x", kind: "lottery", name: "先行抽選",
    sourceUrl: "https://example.com/ticket",
  };

  it("必須フィールドが揃った create を通す", () => {
    expect(ok({ recordType: "TicketSale", op: "create", fields: base })).toBeNull();
  });

  it("日付だけ・日時つきの starts/ends/resultAt をどちらも通す", () => {
    expect(ok({
      recordType: "TicketSale", op: "update", recordName: "ts_x",
      fields: { startsAt: "2026-09-01", endsAt: "2026-09-10 23:59", resultAt: "2026-09-15" },
    })).toBeNull();
  });

  it("日時の形式が違えば弾く", () => {
    expect(ok({
      recordType: "TicketSale", op: "update", recordName: "ts_x",
      fields: { endsAt: "2026/09/10" },
    })).toMatch(/invalid format/);
  });

  it("kind は 4 種の enum のみ", () => {
    expect(ok({ recordType: "TicketSale", op: "create", fields: { ...base, kind: "抽選" } }))
      .toMatch(/must be one of/);
  });

  it("showIds はカンマ区切りの id の形", () => {
    expect(ok({
      recordType: "TicketSale", op: "update", recordName: "ts_x",
      fields: { showIds: "sh_a_01,sh_a_02" },
    })).toBeNull();
    expect(ok({
      recordType: "TicketSale", op: "update", recordName: "ts_x",
      fields: { showIds: "sh_a_01, sh_a_02" },
    })).toMatch(/invalid format/);
  });

  it("sourceUrl が無い create は必須エラー", () => {
    const { sourceUrl: _drop, ...rest } = base;
    expect(ok({ recordType: "TicketSale", op: "create", fields: rest }))
      .toMatch(/field sourceUrl is required/);
  });

  it("sourceUrl / url は http(s) 必須", () => {
    expect(ok({ recordType: "TicketSale", op: "create", fields: { ...base, sourceUrl: "ftp://x" } }))
      .toMatch(/http\(s\) URL/);
    expect(ok({ recordType: "TicketSale", op: "create", fields: { ...base, url: "not-a-url" } }))
      .toMatch(/http\(s\) URL/);
  });
});
