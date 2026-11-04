import XCTest
@testable import ImasLiveDB

/// ペンライトの指示 (コールの一種 `kind: "penlight"`) の読み書き。Worker の `PenlightCue` と 1:1。
final class LyricPenlightTests: XCTestCase {

    private func decodeCall(_ json: String) throws -> LyricCall {
        try JSONDecoder().decode(LyricCall.self, from: Data(json.utf8))
    }

    func testDecodesPenlightOnlyWhenKindSaysSo() throws {
        let cue = try decodeCall(##"{"id":"c1","start":0,"end":2,"text":"ペンライト: 青","kind":"penlight","penlight":{"color":"#1E50FF","note":"2本"}}"##)
        XCTAssertEqual(cue.penlight, LyricPenlight(color: "#1E50FF", note: "2本"))
        XCTAssertTrue(cue.isPenlight)

        // kind が無ければ penlight が付いていても叫ぶコールとして読む (サーバの契約)。
        let call = try decodeCall(##"{"id":"c2","start":0,"end":0,"text":"Hi!","penlight":{"color":"oshi"}}"##)
        XCTAssertNil(call.penlight)

        // 型違いの項目は落とさず nil にする。
        let odd = try decodeCall(##"{"id":"c3","start":0,"end":0,"text":"x","kind":"penlight","penlight":{"color":"oshi","note":3}}"##)
        XCTAssertEqual(odd.penlight, LyricPenlight(color: "oshi", note: nil))
    }

    func testPenlightNeverEchoesTheLyric() {
        let line = LyricLine(id: "l", ord: 0, kind: .lyric, text: "あいう", section: nil, startMs: nil,
                             clap: nil, calls: [])
        let cue = LyricCall(id: "c", start: 0, end: 3, anchorText: "あいう", text: "あいう",
                            emphasis: .normal, timing: .over, penlight: LyricPenlight(color: "oshi"))
        XCTAssertFalse(line.echoes(cue))
    }

    func testPayloadCarriesKindOnlyForPenlight() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let cue = LyricCall(id: "c", start: 0, end: 0, anchorText: "", text: "ペンライト: 担当色",
                            emphasis: .normal, penlight: LyricPenlight(color: "oshi", note: "掲げる"))
        let sent = try JSONSerialization.jsonObject(with: encoder.encode(CallGuidePayload.Call(cue))) as? [String: Any]
        XCTAssertEqual(sent?["kind"] as? String, "penlight")
        XCTAssertEqual((sent?["penlight"] as? [String: Any])?["note"] as? String, "掲げる")

        let call = LyricCall(id: "d", start: 0, end: 0, anchorText: "", text: "Hi!", emphasis: .normal)
        let plain = try JSONSerialization.jsonObject(with: encoder.encode(CallGuidePayload.Call(call))) as? [String: Any]
        XCTAssertNil(plain?["kind"])
        XCTAssertNil(plain?["penlight"])
    }

    func testFallbackTextNamesIdolColorFromCast() {
        let look = PenlightLook(penlight: LyricPenlight(color: "oshi", note: "2本持ち"), cast: .empty)
        XCTAssertEqual(look.description, "ペンライト: 担当色・2本持ち")
        XCTAssertEqual(PenlightLook(penlight: LyricPenlight(color: "idol:x"), cast: .empty).description, "ペンライト")
    }
}
