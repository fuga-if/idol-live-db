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

  it("揃っていれば通る", () => {
    expect(ok({ recordType: "SetlistItem", op: "create", fields: { showId: "sh_x", songId: "sg_x", position: 1 } }))
      .toBeNull();
  });

  it("update では必須チェックを掛けない (差分送信を許す)", () => {
    expect(ok({ recordType: "SetlistItem", op: "update", recordName: "sh_x_0001", fields: { position: 2 } }))
      .toBeNull();
  });
});
