// Emit.swift — 認識結果の書き出し。
//
// text 形式は「# で始まる行はメタ情報、それ以外が本文」という規約。
// postprocess.py がこの規約に依存する。

import CoreGraphics
import Foundation

struct EmitOptions {
    var minConfidence: Float = 0.5
    var marker: String = "[?]"
    var blockSeparator: String = "\n"
}

enum Emit {

    static func text(_ pages: [PageResult], options: EmitOptions, header: [String]) -> String {
        var out: [String] = []
        for h in header { out.append("# \(h)") }
        if !header.isEmpty { out.append("") }

        for page in pages {
            out.append("# ===== page \(page.pageIndex) =====")
            out.append("# file: \(page.sourcePath)")
            out.append("# size: \(Int(page.pixelSize.width))x\(Int(page.pixelSize.height))")
            out.append("# orientation: \(page.orientation.rawValue) (\(page.orientationDecidedBy); vote v=\(page.verticalVote) h=\(page.horizontalVote))")
            out.append("# blocks: \(page.blocks.count)")
            let lowCount = page.blocks.flatMap { $0.lines }.filter { $0.confidence < options.minConfidence }.count
            out.append("# low-confidence-lines: \(lowCount) (threshold \(String(format: "%.2f", options.minConfidence)), marker \(options.marker))")
            out.append("# ruby: separated=\(page.rubyPieces.count) ambiguous=\(page.rubyAmbiguousCount)")
            for n in page.notes { out.append("# note: \(n)") }
            out.append("")

            for (bi, block) in page.blocks.enumerated() {
                if page.blocks.count > 1 { out.append("# --- block \(bi + 1) ---") }
                for line in block.lines {
                    if line.confidence < options.minConfidence {
                        out.append("\(options.marker)\(String(format: "%.2f", line.confidence)) \(line.text)")
                        for (i, alt) in line.pieces.flatMap({ $0.alternatives }).prefix(2).enumerated() {
                            out.append("# alt\(i + 1): \(alt)")
                        }
                    } else {
                        out.append(line.text)
                    }
                }
                out.append("")
            }

            if !page.rubyPieces.isEmpty {
                out.append("# --- ruby (本文から分離済み。歌詞本文には含めない) ---")
                var counter = 0
                for (bi, block) in page.blocks.enumerated() {
                    for (li, line) in block.lines.enumerated() {
                        for r in line.ruby {
                            counter += 1
                            out.append("# ruby b\(bi + 1)l\(li + 1): \(r.text)")
                        }
                        _ = li
                    }
                }
                let orphan = page.rubyPieces.count - counter
                if orphan > 0 { out.append("# ruby (本文行に紐づかず): \(orphan) 件") }
                out.append("")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func json(_ pages: [PageResult], options: EmitOptions) -> String {
        var arr: [[String: Any]] = []
        for page in pages {
            var blocks: [[String: Any]] = []
            for block in page.blocks {
                var lines: [[String: Any]] = []
                for line in block.lines {
                    lines.append([
                        "text": line.text,
                        "confidence": Double(line.confidence),
                        "low_confidence": line.confidence < options.minConfidence,
                        "box": rect(line.box),
                        "pieces": line.pieces.map { p -> [String: Any] in
                            ["text": p.text,
                             "confidence": Double(p.confidence),
                             "alternatives": p.alternatives,
                             "box": rect(p.box)]
                        },
                        "ruby": line.ruby.map { r -> [String: Any] in
                            ["text": r.text, "confidence": Double(r.confidence), "box": rect(r.box)]
                        },
                    ])
                }
                blocks.append(["box": rect(block.box), "lines": lines])
            }
            arr.append([
                "file": page.sourcePath,
                "page": page.pageIndex,
                "width": Int(page.pixelSize.width),
                "height": Int(page.pixelSize.height),
                "orientation": page.orientation.rawValue,
                "orientation_decided_by": page.orientationDecidedBy,
                "vote_vertical": page.verticalVote,
                "vote_horizontal": page.horizontalVote,
                "ruby_separated": page.rubyPieces.count,
                "ruby_ambiguous": page.rubyAmbiguousCount,
                "notes": page.notes,
                "blocks": blocks,
            ])
        }
        let data = try? JSONSerialization.data(withJSONObject: ["pages": arr],
                                               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data ?? Data(), encoding: .utf8) ?? "{}"
    }

    private static func rect(_ r: CGRect) -> [String: Int] {
        ["x": Int(r.minX.rounded()), "y": Int(r.minY.rounded()),
         "w": Int(r.width.rounded()), "h": Int(r.height.rounded())]
    }
}
