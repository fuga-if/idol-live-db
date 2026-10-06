import UIKit
import XCTest
@testable import ImasLiveDB

/// 歌詞カードの読み取りを、文字を描いた画像で通しで確かめる (Vision の枠の向きの変換 + コアの並べ直し)。
final class LyricsCardOCRTests: XCTestCase {

    /// 白地に黒で、横書きの行を上から描く。`nil` の行は空けるだけ (まとまりの切れ目)。
    private func card(_ lines: [String?]) -> UIImage {
        let size = CGSize(width: 1200, height: 160 * lines.count + 120)
        return UIGraphicsImageRenderer(size: size, format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }()).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .medium), .foregroundColor: UIColor.black,
            ]
            for (i, line) in lines.enumerated() {
                guard let line else { continue }
                (line as NSString).draw(at: CGPoint(x: 80, y: 60 + i * 110), withAttributes: attrs)
            }
        }
    }

    func testHorizontalCardIsReadTopToBottomWithParagraphBreak() async {
        let text = await LyricsCardOCR.read([card(["きらめくステージ", "走り出そう", nil, nil, "夢のその先へ"])])
        XCTAssertEqual(text, "きらめくステージ\n走り出そう\n\n夢のその先へ")
    }

    func testBlankImageReadsNothing() async {
        let text = await LyricsCardOCR.read([card([nil, nil])])
        XCTAssertEqual(text, "")
    }
}
