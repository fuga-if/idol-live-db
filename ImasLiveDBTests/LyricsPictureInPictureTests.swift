import CoreImage
import CoreMedia
import UIKit
import XCTest
@testable import ImasLiveDB

/// 歌詞の PiP の 1 コマが描けること (層に流せる映像の 1 コマになっているか)。
@MainActor
final class LyricsPictureInPictureTests: XCTestCase {
    private func idol(_ id: String, _ color: String) -> Idol {
        Idol(id: id, brandId: "as", name: id, nameKana: nil, nameRomaji: nil, familyName: nil, givenName: nil,
             nickname: nil, color: color, sortOrder: 0, birthday: nil, bloodType: nil, height: nil, weight: nil,
             birthPlace: nil, age: nil, bust: nil, waist: nil, hip: nil, constellation: nil, hobbies: nil,
             talents: nil, description: nil, gender: nil, handedness: nil, debutDate: nil, attribute: nil,
             aliases: nil)
    }

    private func line(_ id: String, _ ord: Int, _ text: String, _ ms: Int, singers: [String] = [],
                      breaks: [LyricLinePartBreak] = []) -> LyricLine {
        LyricLine(id: id, ord: ord, kind: .lyric, text: text, section: nil, startMs: ms, clap: nil, calls: [],
                  singers: singers, partBreaks: breaks)
    }

    private func entry() -> LyricsSession.Entry {
        let lines = [
            line("1", 0, "ここに見本の一行目を置く", 1_000, singers: ["a"],
                 breaks: [LyricLinePartBreak(at: 5, singers: ["a", "b"])]),
            line("2", 1, "見本《みほん》の二行目 (追いかけ)", 6_000, singers: ["b"]),
        ]
        return .init(song: makeStubSong("s1"), seed: "#E4007F", artistLine: nil, artworkURL: nil,
                     lyrics: Lyrics(songId: "s1", source: nil, updatedAt: nil, lines: lines.map { var l = $0; if l.id == "1" { l.calls = [LyricCall(id: "c", start: 0, end: 0, anchorText: "", text: "ハイ！", emphasis: .normal, timing: .after, stale: nil, startMs: 1_500)] }; return l }, status: nil),
                     cast: LyricPartCast(artists: [idol("a", "#E4007F"), idol("b", "#2743D2")]))
    }

    func testRendersAFrameForTheCurrentLine() throws {
        let entry = entry()
        for dark in [false, true] {
            let frame = LyricsPictureInPicture.frame(entry, positionMs: 2_000, dark: dark)
            XCTAssertEqual(frame.lineIndex, 0)
            XCTAssertEqual(frame.nextIndex, 1)
            let sample = try XCTUnwrap(LyricsPictureInPicture.render(entry, frame: frame))
            let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            XCTAssertEqual(CVPixelBufferGetWidth(image), 960)
            XCTAssertEqual(CVPixelBufferGetHeight(image), 540)
            if let dir = ProcessInfo.processInfo.environment["PIP_SNAPSHOT_DIR"] {
                let ci = CIImage(cvPixelBuffer: image)
                let cg = try XCTUnwrap(CIContext().createCGImage(ci, from: ci.extent))
                try UIImage(cgImage: cg).pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pip_\(dark).png"))
            }
        }
    }

    func testIntroHasNoCurrentLine() {
        let frame = LyricsPictureInPicture.frame(entry(), positionMs: 0, dark: false)
        XCTAssertNil(frame.lineIndex)
        XCTAssertEqual(frame.nextIndex, 0)
    }
}
