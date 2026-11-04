import Foundation
import ImageIO
import UIKit

/// 名刺入れの画像ファイル (受け取った担当の画像・紙の名刺の写真・自作の名刺の画像) と、
/// 自分の名刺の写真・自作の名刺の画像。
///
/// 写真は**端末の中だけ** (バックアップにもクラウドにも載せない。アイドルの画像と同じ扱い)。
/// 置き場所は `Documents/producer_cards/<名刺の id>/`。名刺を消したら丸ごと消す。
enum ProducerCardFiles {
    /// 名刺の面 (紙の名刺の写真・自作の名刺の画像)。
    enum Side: String, CaseIterable, Sendable {
        case front, back
    }

    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("producer_cards", isDirectory: true)
    }

    private static func folder(_ cardId: String) -> URL {
        root.appendingPathComponent(safeName(cardId), isDirectory: true)
    }

    /// ファイル名に使える形 (アイドルの id に `/` などが入っても階層を作らない)。
    private static func safeName(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    private static func oshiFile(_ cardId: String, idolId: String) -> URL {
        folder(cardId).appendingPathComponent("oshi_\(safeName(idolId)).jpg")
    }

    private static func photoFile(_ cardId: String, side: Side) -> URL {
        folder(cardId).appendingPathComponent("\(side.rawValue).jpg")
    }

    // MARK: 受け取った担当の画像

    static func oshiImageURL(cardId: String, idolId: String) -> URL? {
        let url = oshiFile(cardId, idolId: idolId)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 受け取った画像 (担当の画像・名刺の写真) を書く。同じ担当の画像・写真は新しいもので置き換える。
    static func saveImages(cardId: String, images: [CardFileImage]) throws {
        guard !images.isEmpty else { return }
        try FileManager.default.createDirectory(at: folder(cardId), withIntermediateDirectories: true)
        // 表が届いたら前の裏は捨てる (相手が裏を外した名刺を送り直したとき、古い裏を出し続けない)。
        if images.contains(where: { $0.kind == .faceFront }) {
            try? FileManager.default.removeItem(at: faceFile(cardId, side: .back))
        }
        for image in images {
            switch image.kind {
            case .oshi:
                try image.jpeg.write(to: oshiFile(cardId, idolId: image.idolId), options: .atomic)
            case .photo:
                try image.jpeg.write(to: cardPhotoFile(cardId), options: .atomic)
                // 写真の出どころ (X のアイコンなら丸く出す)。写真から選んだ写真は書かない (無ければ写真から選んだ写真)。
                let source = image.photoSource ?? .picked
                if source == .picked {
                    try? FileManager.default.removeItem(at: cardPhotoSourceFile(cardId))
                } else {
                    try Data(cardPhotoSourceKey(source: source).utf8).write(to: cardPhotoSourceFile(cardId), options: .atomic)
                }
            case .faceFront:
                try image.jpeg.write(to: faceFile(cardId, side: .front), options: .atomic)
            case .faceBack:
                try image.jpeg.write(to: faceFile(cardId, side: .back), options: .atomic)
            case .sticker:
                break
            }
        }
        // 素材は届いた並びで置き換える (相手が素材を外した名刺を送り直したら、古い素材を出し続けない)。
        try saveReceivedStickers(cardId: cardId, images: images.filter { $0.kind == .sticker })
    }

    // MARK: 受け取った素材

    private static func stickerLayoutFile(_ cardId: String) -> URL {
        folder(cardId).appendingPathComponent("stickers.json")
    }

    private static func stickerFile(_ cardId: String, id: String) -> URL {
        folder(cardId).appendingPathComponent("sticker_\(safeName(id)).img")
    }

    private static func saveReceivedStickers(cardId: String, images: [CardFileImage]) throws {
        for old in receivedStickerLayout(cardId: cardId) {
            try? FileManager.default.removeItem(at: stickerFile(cardId, id: old.id))
        }
        let placed = images.compactMap { image in image.sticker.map { ($0, image.jpeg) } }
        for (sticker, data) in placed {
            try data.write(to: stickerFile(cardId, id: sticker.id), options: .atomic)
        }
        try Data(cardStickersToJson(stickers: placed.map(\.0)).utf8).write(to: stickerLayoutFile(cardId), options: .atomic)
    }

    private static func receivedStickerLayout(cardId: String) -> [CardSticker] {
        (try? String(contentsOf: stickerLayoutFile(cardId), encoding: .utf8)).map { cardStickersFromJson(json: $0) } ?? []
    }

    /// 受け取った名刺の素材 (重なりの順。画像の無いものは除く)。
    static func receivedStickers(cardId: String) -> [(sticker: CardSticker, url: URL)] {
        receivedStickerLayout(cardId: cardId).compactMap { sticker in
            let url = stickerFile(cardId, id: sticker.id)
            return FileManager.default.fileExists(atPath: url.path) ? (sticker, url) : nil
        }
    }

    // MARK: 受け取った名刺の写真 (相手が名刺に載せた写真)

    private static func cardPhotoFile(_ cardId: String) -> URL {
        folder(cardId).appendingPathComponent("card_photo.jpg")
    }

    static func cardPhotoURL(cardId: String) -> URL? {
        let url = cardPhotoFile(cardId)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func cardPhotoSourceFile(_ cardId: String) -> URL {
        folder(cardId).appendingPathComponent("card_photo_source.txt")
    }

    /// 受け取った名刺の写真の出どころ (届いたまま。無ければ写真から選んだ写真)。
    static func cardPhotoSource(cardId: String) -> CardPhotoSource {
        readPhotoSource(at: cardPhotoSourceFile(cardId))
    }

    /// 受け取った名刺の写真を丸く出すか (切り方はコアの `cardPhotoShape`)。
    static func cardPhotoRound(cardId: String) -> Bool {
        cardPhotoShape(source: cardPhotoSource(cardId: cardId)) == .round
    }

    /// 写真の出どころのキーのファイルを読む (キーの読み方はコア。無ければ写真から選んだ写真)。
    static func readPhotoSource(at url: URL) -> CardPhotoSource {
        let key = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return cardPhotoSourceFromKey(key: key)
    }

    // MARK: 受け取った自作の名刺の画像 (相手が自分で作った名刺の表・裏)

    private static func faceFile(_ cardId: String, side: Side) -> URL {
        folder(cardId).appendingPathComponent("face_\(side.rawValue).jpg")
    }

    static func faceURL(cardId: String, side: Side) -> URL? {
        let url = faceFile(cardId, side: side)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: 自分の名刺の写真

    /// 自分の名刺の写真の置き場所 (`Documents/producer_card_me/`)。名刺入れとは別のフォルダ。
    private static var myFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("producer_card_me", isDirectory: true)
    }

    /// 名刺に載せる写真 (切り抜いた後の JPEG)。名刺ファイルで相手にもこの画質で渡る。
    /// 名前は書くたびに変える (画像の読み込みの控えが古い写真を出し続けないように)。
    static var myPhotoURL: URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: myFolder.path)) ?? []
        return names.first { $0.hasPrefix("photo-") && $0.hasSuffix(".jpg") }
            .map { myFolder.appendingPathComponent($0) }
    }

    /// 切り抜く前の写真 (位置を直すとき用)。
    static var myPhotoSourceURL: URL? {
        let url = myFolder.appendingPathComponent("photo_source.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 名刺の写真の出どころ (写真から選んだ写真か X のアイコン)。前の版で選んだ写真は写真から選んだ写真。
    static var myPhotoSource: CardPhotoSource {
        readPhotoSource(at: myFolder.appendingPathComponent("photo_source_kind.txt"))
    }

    /// 自分の名刺の写真を丸く出すか (切り方はコアの `cardPhotoShape`)。
    static var myPhotoRound: Bool { cardPhotoShape(source: myPhotoSource) == .round }

    /// 前の版のプロフィール帳だけの写真 (`Documents/profile_sheet_photo/`) を片付ける。プロフィール帳は
    /// P名刺の画像に一本化し、写真は P名刺の写真を使う (端末の中だけの写しで、元は写真の中にある)。
    static func removeLegacyProfileSheetPhoto() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_sheet_photo", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 切り抜きの位置と拡大。前の版の 3:4 の切り抜きも、正方形の枠で真ん中を保ったまま読み替える。
    static var myPhotoCrop: ImasPortraitCrop? {
        let url = myFolder.appendingPathComponent("photo_crop.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ImasPortraitCrop.self, from: data)
    }

    /// 自分の名刺の写真を書く (元の写真・切り抜き・出どころ・切り抜いた正方形の JPEG)。
    static func saveMyPhoto(source: UIImage, crop: ImasPortraitCrop, origin: CardPhotoSource) throws {
        guard let cropped = crop.render(source, frame: .card),
              let photo = jpeg(cropped, maxPixels: 1600),
              let original = jpeg(source, maxPixels: 3000) else { return }
        try FileManager.default.createDirectory(at: myFolder, withIntermediateDirectories: true)
        try original.write(to: myFolder.appendingPathComponent("photo_source.jpg"), options: .atomic)
        try JSONEncoder().encode(crop).write(to: myFolder.appendingPathComponent("photo_crop.json"), options: .atomic)
        try Data(cardPhotoSourceKey(source: origin).utf8)
            .write(to: myFolder.appendingPathComponent("photo_source_kind.txt"), options: .atomic)
        let previous = myPhotoURL
        let name = "photo-\(UUID().uuidString.prefix(8).lowercased()).jpg"
        try photo.write(to: myFolder.appendingPathComponent(name), options: .atomic)
        if let previous { try? FileManager.default.removeItem(at: previous) }
    }

    static func deleteMyPhoto() {
        try? FileManager.default.removeItem(at: myFolder)
    }

    // MARK: 自分の名刺の素材

    /// 名刺の表に置く素材の置き場所 (`Documents/producer_card_stickers/`)。画像は `<id>.png` (透過のまま)、
    /// 置き方は `stickers.json` (コアの保存の形 `cardStickersToJson`)。名刺の行には持たない (画像と一緒に消えるように)。
    private static var myStickerFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("producer_card_stickers", isDirectory: true)
    }

    static func myStickerURL(id: String) -> URL? {
        let url = myStickerFolder.appendingPathComponent("\(safeName(id)).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 自分の名刺の素材の置き方 (重なりの順。画像の無いものは除く)。
    static var myStickers: [CardSticker] {
        let url = myStickerFolder.appendingPathComponent("stickers.json")
        let stored = (try? String(contentsOf: url, encoding: .utf8)).map { cardStickersFromJson(json: $0) } ?? []
        return stored.filter { myStickerURL(id: $0.id) != nil }
    }

    /// 素材を書き直す (置き方の並びと、新しく足した画像)。並びに無い画像は消す。
    static func saveMyStickers(_ stickers: [CardSticker], newImages: [String: Data]) throws {
        try FileManager.default.createDirectory(at: myStickerFolder, withIntermediateDirectories: true)
        for (id, data) in newImages where stickers.contains(where: { $0.id == id }) {
            try data.write(to: myStickerFolder.appendingPathComponent("\(safeName(id)).png"), options: .atomic)
        }
        let keep = Set(stickers.map { "\(safeName($0.id)).png" })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: myStickerFolder.path)) ?? []
        for name in names where name.hasSuffix(".png") && !keep.contains(name) {
            try? FileManager.default.removeItem(at: myStickerFolder.appendingPathComponent(name))
        }
        try Data(cardStickersToJson(stickers: stickers).utf8)
            .write(to: myStickerFolder.appendingPathComponent("stickers.json"), options: .atomic)
    }

    /// 素材の画像を名刺に置く形にする (長辺 1200px までの PNG。透過を残す)。
    static func stickerPNG(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height) * image.scale
        let ratio = min(1, 1200 / max(longest, 1))
        let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.pngData()
    }

    // MARK: 自分の名刺用の担当の画像

    /// 名刺だけに使う担当の画像の置き場所 (`Documents/producer_card_oshi/`)。アプリの担当の画像
    /// (`CustomImageService`) とは別に持ち、名刺 (画面・紙・SNS の画像・交換で渡す画像) ではこちらを先に使う
    /// (2026-10 ユーザー「使いたい画像を別で好きにアップロードさせてくれないか」)。
    private static var myOshiFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("producer_card_oshi", isDirectory: true)
    }

    /// 名刺用の担当の画像のファイル (新しい順)。名前は書くたびに変える (読み込みの控えが古い画像を出さないように)。
    private static func myOshiFiles(_ idolId: String) -> [URL] {
        let prefix = "\(safeName(idolId))-"
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: myOshiFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "jpg" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
    }

    /// 名刺用に選んだ担当の画像 (無ければ nil)。
    static func myOshiImageURL(idolId: String) -> URL? {
        myOshiFiles(idolId).first
    }

    /// 名刺に出す自分の担当の画像。名刺用に選んだ画像、無ければアプリの担当の画像。
    @MainActor
    static func cardOshiImageURL(idolId: String) -> URL? {
        myOshiImageURL(idolId: idolId) ?? CustomImageService.shared.imageURL(for: idolId)
    }

    /// 名刺用の担当の画像を書く (前の画像は消す)。
    static func saveMyOshiImage(_ image: UIImage, idolId: String) throws {
        guard let data = jpeg(image, maxPixels: 2000) else { return }
        try FileManager.default.createDirectory(at: myOshiFolder, withIntermediateDirectories: true)
        let previous = myOshiFiles(idolId)
        let name = "\(safeName(idolId))-\(UUID().uuidString.prefix(8).lowercased()).jpg"
        try data.write(to: myOshiFolder.appendingPathComponent(name), options: .atomic)
        for url in previous { try? FileManager.default.removeItem(at: url) }
    }

    /// 名刺用の担当の画像を外す (アプリの担当の画像に戻る)。
    static func deleteMyOshiImage(idolId: String) {
        for url in myOshiFiles(idolId) { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: 自分の自作の名刺の画像

    /// 自作の名刺の画像の置き場所 (`Documents/producer_card_face/`)。写真のフォルダとは別
    /// (写真を外しても画像は残す)。
    private static var myFaceFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("producer_card_face", isDirectory: true)
    }

    /// 自作の名刺の画像 (平らにして切り抜いた後の JPEG)。名刺ファイル・近くの端末で相手にこの画質で渡る。
    /// 名前は書くたびに変える (画像の読み込みの控えが古い画像を出し続けないように)。
    static func myFaceURL(_ side: Side) -> URL? {
        myFaceFiles(side).first
    }

    /// その面のファイル (新しい順)。書き込みの途中で落ちて 2 枚残っても新しい方を使う。
    private static func myFaceFiles(_ side: Side) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: myFaceFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func date(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return urls
            .filter { $0.lastPathComponent.hasPrefix("\(side.rawValue)-") && $0.pathExtension == "jpg" }
            .sorted { date($0) > date($1) }
    }

    /// 自作の名刺の画像を書く (長辺 2000px まで。比率はそのまま)。
    static func saveMyFace(_ image: UIImage, side: Side) throws {
        guard let data = jpeg(image, maxPixels: 2000, quality: 0.9) else { return }
        try FileManager.default.createDirectory(at: myFaceFolder, withIntermediateDirectories: true)
        let previous = myFaceFiles(side)
        let name = "\(side.rawValue)-\(UUID().uuidString.prefix(8).lowercased()).jpg"
        try data.write(to: myFaceFolder.appendingPathComponent(name), options: .atomic)
        for url in previous { try? FileManager.default.removeItem(at: url) }
    }

    static func deleteMyFace(_ side: Side) {
        for url in myFaceFiles(side) { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: 紙の名刺の写真

    static func photoURL(cardId: String, side: Side) -> URL? {
        let url = photoFile(cardId, side: side)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func savePhoto(_ image: UIImage, cardId: String, side: Side) throws {
        guard let data = jpeg(image, maxPixels: 2000) else { return }
        try FileManager.default.createDirectory(at: folder(cardId), withIntermediateDirectories: true)
        try data.write(to: photoFile(cardId, side: side), options: .atomic)
    }

    static func deleteAll(cardId: String) {
        try? FileManager.default.removeItem(at: folder(cardId))
    }

    // MARK: 刷る画像

    /// 紙に刷る画像に焼く小さな画像 (長辺 `maxPixels` まで、向きは写真のまま)。ImageRenderer は
    /// 画像の読み込みを待たないので、刷る前にここで読んでおく。大きな写真を丸ごと読まない。
    static func printImage(at url: URL, maxPixels: Int = 600) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: 送る画像

    /// 担当の画像を送る形 (JPEG、長辺 1600px まで) にする。
    static func jpeg(_ image: UIImage, maxPixels: CGFloat = 1600, quality: CGFloat = 0.85) -> Data? {
        let longSide = max(image.size.width * image.scale, image.size.height * image.scale)
        guard longSide > maxPixels else { return flattened(image).jpegData(compressionQuality: quality) }
        let ratio = maxPixels / longSide
        let size = CGSize(width: (image.size.width * image.scale * ratio).rounded(),
                          height: (image.size.height * image.scale * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// 透過のある画像 (PNG のロゴなど) を白地に置いてから JPEG にする (透過は JPEG で黒く潰れる)。
    private static func flattened(_ image: UIImage) -> UIImage {
        guard hasAlphaChannel(image) else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
    }
}
