// 振り仮名の記法 (《》)。取り込み時の変換・移行の口・行の区切り編集の「ルビにする / やめる」。
// 本文には実在の歌詞を使わない (意味の無い文字列だけ)。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { convertLinesToRubyNotation, stripRuby, toRubyNotation } from "../src/lyrics_ruby";
import { applyStructureOp, parseStructureOp } from "../src/lyrics_structure";
import { callJson, makeEnv } from "./support/worker";
import { exec, row } from "./support/d1";

const PUSH_TOKEN = "push-token-for-test";
const env = () => makeEnv({ LYRICS_PUSH_TOKEN: PUSH_TOKEN });

beforeEach(() => void vi.spyOn(console, "log").mockImplementation(() => {}));
afterEach(() => vi.restoreAllMocks());

describe("振り仮名の記法", () => {
  it("漢字の直後の、かなだけの括弧だけを《》に直す (文字数は変わらない)", () => {
    expect(toRubyNotation("見本字（みほんじ）の行")).toBe("見本字《みほんじ》の行");
    expect(toRubyNotation("見本(み　ほん)")).toBe("見本《み　ほん》");
    expect(toRubyNotation("問い？（勿論さ！）")).toBe("問い？（勿論さ！）");
    expect(toRubyNotation("走る (手伸ばせ)")).toBe("走る (手伸ばせ)");
    expect(toRubyNotation("夢を（ゆめを）")).toBe("夢を（ゆめを）");
    expect(Array.from(toRubyNotation("見本字（みほんじ）")).length).toBe(Array.from("見本字（みほんじ）").length);
    expect(stripRuby("見本字《みほんじ》の｜ダミー《だみ》")).toBe("見本字のダミー");
  });

  it("移行でコールの控えも直す", () => {
    const lines = [{ kind: "lyric", text: "見本（みほん）だ", calls: [{ start: 0, end: 7, anchorText: "見本（みほん）" }] }];
    const r = convertLinesToRubyNotation(lines);
    expect(r.changed).toBe(1);
    expect(r.lines[0].calls![0].anchorText).toBe("見本《みほん》");
  });

  it("取り込み (PUT) と移行の口", async () => {
    const put = await callJson("PUT", "/admin/lyrics/s_ruby", {
      headers: { "X-Push-Token": PUSH_TOKEN },
      body: { status: "published", lines: [{ kind: "lyric", text: "見本字（みほんじ）の行" }] },
      env: env(),
    });
    expect(put.status).toBe(200);
    const saved = await row<{ lines_json: string; body: string }>("SELECT lines_json, body FROM song_lyrics WHERE song_id = 's_ruby'");
    expect(JSON.parse(saved!.lines_json)[0].text).toBe("見本字《みほんじ》の行");
    expect(saved!.body).toBe("見本字の行");

    // 前から入っている括弧書きの曲を移行で直す。応答は件数だけ。
    await exec("INSERT INTO song_lyrics (song_id, source, status, lines_json) VALUES ('s_old', 'src', 'published', ?)",
      JSON.stringify([{ id: "l1", ord: 0, kind: "lyric", text: "古字（ふるじ）だ", calls: [] }]));
    const dry = await callJson("POST", "/admin/lyrics/ruby-notation", {
      headers: { "X-Push-Token": PUSH_TOKEN }, body: { dryRun: true }, env: env(),
    });
    expect(dry.body).toMatchObject({ dryRun: true, changedSongs: 1, changedLines: 1 });
    expect(JSON.stringify(dry.body)).not.toContain("古字");
    const apply = await callJson("POST", "/admin/lyrics/ruby-notation", {
      headers: { "X-Push-Token": PUSH_TOKEN }, body: {}, env: env(),
    });
    expect(apply.body).toMatchObject({ dryRun: false, changedSongs: 1 });
    const old = await row<{ lines_json: string }>("SELECT lines_json FROM song_lyrics WHERE song_id = 's_old'");
    expect(JSON.parse(old!.lines_json)[0].text).toBe("古字《ふるじ》だ");
    expect((await callJson("POST", "/admin/lyrics/ruby-notation", { body: {} })).status).toBe(401);
  });

  it("行の区切り編集で振り仮名にする / やめる", () => {
    const lines = [{ id: "a", ord: 0, kind: "lyric", text: "見本（みほん）だ", section: null, start_ms: null, clap: null, calls: [] }];
    const on = applyStructureOp(lines as any, { op: "ruby", lineId: "a", at: 2 }, () => "x");
    expect(on.ok && on.lines[0].text).toBe("見本《みほん》だ");
    const off = applyStructureOp((on as any).lines, { op: "unruby", lineId: "a", at: 2 }, () => "x");
    expect(off.ok && off.lines[0].text).toBe("見本（みほん）だ");
    const bad = applyStructureOp([{ ...lines[0], text: "だ（みほん）" }] as any, { op: "ruby", lineId: "a", at: 1 }, () => "x");
    expect(bad.ok).toBe(false);
  });

  it("親字の頭を決め直す (｜を置く・置き直す)", () => {
    const call = { id: "c", start: 7, end: 8, anchorText: "だ", text: "Hi" };
    const lines = [{ id: "a", ord: 0, kind: "lyric", text: "記憶抱《イダ》だ", section: null, start_ms: null, clap: null, calls: [call] }];
    const one = applyStructureOp(lines as any, { op: "rubyBase", lineId: "a", at: 3, base: 2 }, () => "x");
    expect(one.ok && one.lines[0].text).toBe("記憶｜抱《イダ》だ");
    expect(one.ok && one.lines[0].calls?.[0]).toMatchObject({ start: 8, end: 9, anchorText: "だ" });
    expect(one.ok && one.lines[0].calls?.[0]?.stale).toBeUndefined();
    // 置き直すと前の｜は外れる
    const two = applyStructureOp((one as any).lines, { op: "rubyBase", lineId: "a", at: 4, base: 1 }, () => "x");
    expect(two.ok && two.lines[0].text).toBe("記｜憶抱《イダ》だ");
    // 漢字でない親字にも置ける
    const ateji = applyStructureOp([{ ...lines[0], text: "あのSTAR《ほし》", calls: [] }] as any,
      { op: "rubyBase", lineId: "a", at: 6, base: 2 }, () => "x");
    expect(ateji.ok && ateji.lines[0].text).toBe("あの｜STAR《ほし》");
    const bad = applyStructureOp(lines as any, { op: "rubyBase", lineId: "a", at: 3, base: 3 }, () => "x");
    expect(bad.ok).toBe(false);
  });

  it("括弧を振り仮名にするとき親字の頭を選べる (当て字)", () => {
    const lines = [{ id: "a", ord: 0, kind: "lyric", text: "あのSTAR（ほし）", section: null, start_ms: null, clap: null, calls: [] }];
    expect(applyStructureOp(lines as any, { op: "ruby", lineId: "a", at: 6 }, () => "x").ok).toBe(false);
    const on = applyStructureOp(lines as any, { op: "ruby", lineId: "a", at: 6, base: 2 }, () => "x");
    expect(on.ok && on.lines[0].text).toBe("あの｜STAR《ほし》");
    // 漢字のまとまりそのものを選び直したら「｜」は外れる
    const k = [{ ...lines[0], text: "記憶｜抱《イダ》" }];
    const back = applyStructureOp(k as any, { op: "rubyBase", lineId: "a", at: 4, base: 0 }, () => "x");
    expect(back.ok && back.lines[0].text).toBe("記憶抱《イダ》");
    expect(parseStructureOp({ op: "ruby", lineId: "a", at: 1, base: 0 })).toEqual({ op: "ruby", lineId: "a", at: 1, base: 0 });
  });
});
