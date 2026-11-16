import UIKit

/// コール表の画像を、利用者の ChatGPT プランに書き写してもらう。
///
/// 頼み方・答えの検証・歌詞やコールの下書きへの直し方は全部コア
/// (`agent::tools::call_sheet_reader` / `domain::call_guide_import`)。ここは画像を縮めて運び、
/// 同じ画像を端末の文字認識にも通して、突き合わせの材料をコアに渡すだけ。
@MainActor
enum CallSheetRunner {
    /// 送る画像の長辺の上限 (画素)。縦長のコール表でも字が潰れない大きさ。
    private nonisolated static let maxSide: CGFloat = 2048

    static func read(images: [UIImage], onProgress: (String) -> Void) async throws -> CallSheetReading {
        let picked = Array(images.prefix(Int(callSheetMaxImages())))
        // 端末の中の文字認識。モデルが画像に無い歌詞を覚えで補っていないかを、コアがこれと突き合わせる。
        onProgress("画像の字を確かめています…")
        let ocrText = await LyricsCardOCR.read(picked).text
        try Task.checkCancellation()

        let encoded = await Task.detached(priority: .userInitiated) { picked.compactMap(Self.jpegBase64) }.value
        guard let request = callSheetRequest(imagesBase64: encoded) else {
            throw ChatGPTPlanTaskRunner.RunnerError(message: "画像を読み込めませんでした")
        }
        onProgress("ChatGPT が書き写しています…")
        return try await ChatGPTPlanTaskRunner.run(request: request, onProgress: onProgress) { _, _, text in
            guard let reading = callSheetAnswer(text: text, ocrText: ocrText) else {
                throw ChatGPTPlanTaskRunner.RunnerError(message: "歌詞とコールを読み取れませんでした。字がはっきり写った画像で試してください")
            }
            return .finished(reading)
        }
    }

    /// 長辺を上限に縮めて JPEG にし、base64 にする。
    nonisolated static func jpegBase64(_ image: UIImage) -> String? {
        let longest = max(image.size.width, image.size.height) * image.scale
        let ratio = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)?.base64EncodedString()
    }
}
