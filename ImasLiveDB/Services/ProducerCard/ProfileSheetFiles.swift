import Foundation
import UIKit

/// プロフィール帳の証明写真の欄に入れる、プロフィール帳だけの画像 (P名刺の写真とは別)。
///
/// 置き場所は `Documents/profile_sheet_photo/`。切り抜く前の元・切り抜きの位置と拡大・切り抜いた JPEG を持つ
/// (P名刺の写真と同じ形)。画像は**端末の中だけ** (バックアップにもクラウドにも載せない。P名刺の写真と同じ扱い)。
/// 無ければ証明写真の欄は P名刺の写真を使う。
enum ProfileSheetFiles {
    private static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_sheet_photo", isDirectory: true)
    }

    /// 切り抜いた後の JPEG。名前は書くたびに変える (画像の読み込みの控えが古い写真を出し続けないように)。
    static var photoURL: URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.first { $0.hasPrefix("photo-") && $0.hasSuffix(".jpg") }
            .map { folder.appendingPathComponent($0) }
    }

    /// 切り抜く前の元 (位置を直すとき用)。
    static var sourceURL: URL? {
        let url = folder.appendingPathComponent("photo_source.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var crop: ImasPortraitCrop? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("photo_crop.json")) else { return nil }
        return try? JSONDecoder().decode(ImasPortraitCrop.self, from: data)
    }

    /// 写真の出どころ (写真から選んだ写真か X のアイコン)。
    static var source: CardPhotoSource {
        ProducerCardFiles.readPhotoSource(at: folder.appendingPathComponent("photo_source_kind.txt"))
    }

    /// 切り抜く枠。X のアイコンは丸く出すので正方形で切り、証明写真の欄 (3:4) の中に丸く置く。
    static func cropFrame(for origin: CardPhotoSource) -> ImasPortraitCrop.Frame {
        cardPhotoShape(source: origin) == .round ? .card : .resume
    }

    /// 書く (元・切り抜き・出どころ・切り抜いた JPEG)。
    static func save(source: UIImage, crop: ImasPortraitCrop, origin: CardPhotoSource) throws {
        guard let cropped = crop.render(source, frame: cropFrame(for: origin)),
              let photo = ProducerCardFiles.jpeg(cropped, maxPixels: 1600),
              let original = ProducerCardFiles.jpeg(source, maxPixels: 3000) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try original.write(to: folder.appendingPathComponent("photo_source.jpg"), options: .atomic)
        try JSONEncoder().encode(crop).write(to: folder.appendingPathComponent("photo_crop.json"), options: .atomic)
        try Data(cardPhotoSourceKey(source: origin).utf8)
            .write(to: folder.appendingPathComponent("photo_source_kind.txt"), options: .atomic)
        let name = "photo-\(UUID().uuidString.prefix(8).lowercased()).jpg"
        try photo.write(to: folder.appendingPathComponent(name), options: .atomic)
        // 前の写真をすべて片付ける (2 つ残るとどちらが出るか決まらない)。
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for old in names where old.hasPrefix("photo-") && old != name {
            try FileManager.default.removeItem(at: folder.appendingPathComponent(old))
        }
    }

    /// 消す (証明写真の欄は P名刺の写真に戻る)。
    static func delete() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// 証明写真の欄に入れる画像の場所: プロフィール帳の画像、無ければ P名刺の写真。
    static var effectiveURL: URL? { photoURL ?? ProducerCardFiles.myPhotoURL }

    /// 証明写真の欄に入れる画像を丸く置くか (X のアイコン。切り方はコアの `cardPhotoShape`)。
    static var effectiveRound: Bool {
        let source = photoURL != nil ? source : ProducerCardFiles.myPhotoSource
        return cardPhotoShape(source: source) == .round
    }
}
