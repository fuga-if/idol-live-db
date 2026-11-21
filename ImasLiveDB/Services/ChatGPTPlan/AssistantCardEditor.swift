import UIKit

/// チャットから頼まれた P名刺の直し 1 回ぶんを、名刺の行と画像のファイルに書く。
///
/// 何を変えるか・どの画像を何に使うか・上限は、コアが検査して `AiProducerCardEdit` に詰めてある
/// (`domain::ai_producer_card`)。ここは編集画面と同じ保存の口を呼ぶだけ。
/// 画像は、発言に添えた手元の画像をそのまま使う (モデルから画像は受け取らない)。
@MainActor
enum AssistantCardEditor {
    /// - Parameters:
    ///   - images: その番の発言に添えた画像 (番号は 1 始まりで、この並び)。
    ///   - generated: その番で描いてもらった画像 (名刺の表にするのは最後の 1 枚)。
    static func apply(_ edit: AiProducerCardEdit, images: [UIImage], generated: [UIImage]) async throws {
        let store = AppContainer.shared.producerCards
        var card = (try await store.myCard()) ?? .empty()
        if let name = edit.name { card.name = name }
        if let message = edit.message { card.message = message }
        if let year = edit.sinceYear { card.sinceYear = Int(year) }
        if let links = edit.links { card.links = links }
        if let design = edit.design { card.cardDesign = design }
        if let ink = edit.inkKey { card.ink = ink.isEmpty ? nil : ink }
        if let oshi = edit.oshiIdolIds { card.cardOshiChoice = oshi }
        // 中身を渡された項目は、名刺から外していたら載せ直す (どれを載せ直すかはコアが決めてある)。
        card.hidden.subtract(edit.showFields.compactMap(ProducerCardField.init(rawValue:)))

        // QR に収まるか (リンクの長さと記録の数しだい) は、編集画面の保存と同じ検査で確かめる。
        let record = try await ProducerCardAssembler.loadMyRecord()
        if let error = validateProducerCard(input: ProducerCardAssembler.input(card: card, record: record)) {
            throw AssistantExecutor.Failure(message: producerCardInputErrorMessage(error: error))
        }

        // 画像は先に全部そろえる (取れない・切り抜けないなら、名刺を半端に書き換えない)。
        let photo: (image: UIImage, origin: CardPhotoSource)?
        if let number = edit.photoImage {
            photo = (try attached(number, in: images), .picked)
        } else if let handle = edit.photoXHandle {
            switch await XAvatarFetcher.fetch(handle: handle) {
            case .image(let image): photo = (image, .xIcon)
            case .failed(let message):
                throw AssistantExecutor.Failure(message: message.isEmpty ? "X のアイコンを取れませんでした" : message)
            }
        } else {
            photo = nil
        }
        let face: UIImage?
        if edit.faceGenerated {
            guard let drawn = generated.last else {
                throw AssistantExecutor.Failure(message: "名刺の絵が描かれていませんでした。もう一度「名刺の絵を描いて」と頼んでください")
            }
            // 描いた絵は名刺と形が違う (3:2) ので、名刺の形に真ん中で切る。
            face = cropped(drawn, toAspect: ImasMeishi.aspect)
        } else {
            face = try edit.faceImage.map { try attached($0, in: images) }
        }
        var stickers = ProducerCardFiles.myStickers
        var stickerData: [String: Data] = [:]
        for number in edit.stickerImages {
            var image = try attached(number, in: images)
            if edit.stickerCutout {
                do {
                    image = try await StickerCutout.cutout(image)
                } catch {
                    throw AssistantExecutor.Failure(message: "素材の背景を切り抜けませんでした。切り抜かずに置くか、別の画像で試してください")
                }
            }
            guard let png = ProducerCardFiles.stickerPNG(image) else {
                throw AssistantExecutor.Failure(message: "素材の画像を読み込めませんでした")
            }
            let id = String(UUID().uuidString.prefix(8)).lowercased()
            let next = cardStickersAdd(stickers: stickers, id: id)
            guard next.count > stickers.count else {
                throw AssistantExecutor.Failure(message: "素材はこれ以上置けません")
            }
            stickers = next
            stickerData[id] = png
        }

        if let photo {
            try ProducerCardFiles.saveMyPhoto(source: photo.image, crop: ImasPortraitCrop(), origin: photo.origin)
        }
        if let face {
            try ProducerCardFiles.saveMyFace(PaperCardRectifier.upright(face), side: .front)
        }
        if !stickerData.isEmpty {
            try ProducerCardFiles.saveMyStickers(stickers, newImages: stickerData)
        }
        let latest = try await store.myCard()
        try await store.saveMyCard(card.applyingEdit(onto: latest))
        NotificationCenter.default.post(name: .myProducerCardChanged, object: nil)
    }

    /// 真ん中を、横 / 縦 = `aspect` の形に切る。
    private static func cropped(_ image: UIImage, toAspect aspect: CGFloat) -> UIImage {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard size.width > 0, size.height > 0, aspect > 0 else { return image }
        let target = size.width / size.height > aspect
            ? CGSize(width: size.height * aspect, height: size.height)
            : CGSize(width: size.width, height: size.width / aspect)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2,
                                  width: size.width, height: size.height))
        }
    }

    private static func attached(_ number: UInt32, in images: [UIImage]) throws -> UIImage {
        let index = Int(number) - 1
        guard images.indices.contains(index) else {
            throw AssistantExecutor.Failure(message: "添えた画像が見つかりませんでした。画像を添えて、もう一度頼んでください")
        }
        return images[index]
    }
}
