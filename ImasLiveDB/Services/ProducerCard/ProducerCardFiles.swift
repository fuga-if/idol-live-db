import Foundation
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
            case .faceFront:
                try image.jpeg.write(to: faceFile(cardId, side: .front), options: .atomic)
            case .faceBack:
                try image.jpeg.write(to: faceFile(cardId, side: .back), options: .atomic)
            }
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

    /// 切り抜きの位置と拡大。
    static var myPhotoCrop: ImasPortraitCrop? {
        let url = myFolder.appendingPathComponent("photo_crop.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ImasPortraitCrop.self, from: data)
    }

    /// 自分の名刺の写真を書く (元の写真・切り抜き・切り抜いた JPEG)。
    static func saveMyPhoto(source: UIImage, crop: ImasPortraitCrop) throws {
        guard let cropped = crop.render(source),
              let photo = jpeg(cropped, maxPixels: 1600),
              let original = jpeg(source, maxPixels: 3000) else { return }
        try FileManager.default.createDirectory(at: myFolder, withIntermediateDirectories: true)
        try original.write(to: myFolder.appendingPathComponent("photo_source.jpg"), options: .atomic)
        try JSONEncoder().encode(crop).write(to: myFolder.appendingPathComponent("photo_crop.json"), options: .atomic)
        let previous = myPhotoURL
        let name = "photo-\(UUID().uuidString.prefix(8).lowercased()).jpg"
        try photo.write(to: myFolder.appendingPathComponent(name), options: .atomic)
        if let previous { try? FileManager.default.removeItem(at: previous) }
    }

    static func deleteMyPhoto() {
        try? FileManager.default.removeItem(at: myFolder)
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
