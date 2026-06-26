import UIKit

/// ギャラリー画像 1 枚分のメタ。`manifest.json` に順序付きで保存する (先頭=プライマリ)。
/// 旧仕様では純粋な `[String]` (ファイル名配列) だったため、読み込み時に後方互換で移行する。
struct GalleryImageMeta: Codable, Equatable {
    let name: String
    /// ホーム画面ウィジェットのスライドショー対象に含めるか (既定 true)。
    var inSlideshow: Bool

    init(name: String, inSlideshow: Bool = true) {
        self.name = name
        self.inSlideshow = inSlideshow
    }
}

/// アイドル / ブランドごとのカスタム画像を Documents/ に保存・管理するサービス。
///
/// アイドルは **1 件 = 複数画像のギャラリー**。`custom_images/{idolId}/` フォルダに
/// `{uuid}.jpg` を並べ、順序と代表(プライマリ)を `manifest.json` (順序付きファイル名配列、
/// 先頭=プライマリ) で管理する。アプリ内アバターは常にプライマリを使う (`imageURL(for:)`)。
/// 旧仕様の単一ファイル `custom_images/{idolId}.jpg` は初回に各フォルダへ自動移行する。
///
/// ブランドは従来どおり単一画像 (`custom_images_brands/{brandId}.jpg`)。
@Observable @MainActor
final class CustomImageService {
    static let shared = CustomImageService()

    /// 画像を 1 枚以上持つアイドル ID 集合 (アバター有無判定用)。
    private(set) var idolsWithImages: Set<String> = []
    private(set) var brandsWithImages: Set<String> = []
    /// アイドルギャラリーの変更通知用バージョン (View 再描画トリガ)。
    private(set) var galleryVersion: Int = 0

    private let idolDirectory: URL
    private let brandDirectory: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        idolDirectory = documents.appendingPathComponent("custom_images")
        brandDirectory = documents.appendingPathComponent("custom_images_brands")
        try? FileManager.default.createDirectory(at: idolDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: brandDirectory, withIntermediateDirectories: true)
        migrateLegacySingleImages()
        idolsWithImages = scanIdolIds()
        brandsWithImages = Self.scanIds(in: brandDirectory)
    }

    // MARK: - Idol gallery (multi-image)

    private func idolFolder(_ idolId: String) -> URL {
        idolDirectory.appendingPathComponent(idolId, isDirectory: true)
    }

    private func manifestURL(_ idolId: String) -> URL {
        idolFolder(idolId).appendingPathComponent("manifest.json")
    }

    /// プライマリを含む順序付きエントリ (先頭=プライマリ)。フォルダ実体と突き合わせて健全化する。
    /// 旧形式 (`[String]`) は全件スライドショー対象として読み込む。
    private func manifest(_ idolId: String) -> [GalleryImageMeta] {
        let folder = idolFolder(idolId)
        let onDisk = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".jpg") })
        let saved = (try? Data(contentsOf: manifestURL(idolId))).map(Self.parseManifest) ?? []
        // 消えたファイルを除外 + 同一ファイル名の重複エントリを除去 (過去の不正 manifest 対策)。
        var order = Self.dedupedByName(saved.filter { onDisk.contains($0.name) })
        // manifest に無いがディスクにある画像を末尾に追加 (取りこぼし防止)
        let known = Set(order.map(\.name))
        for name in onDisk.sorted() where !known.contains(name) { order.append(GalleryImageMeta(name: name)) }
        return order
    }

    /// 同一ファイル名の重複エントリを除去する (最初の出現=プライマリ寄りを残す)。
    /// 過去の不正な manifest に同名が複数入っていると、同じ画像が複数セルに描画され、
    /// 片方を消すと両方消える不具合になる。その対策。FS 非依存・純粋なのでテスト可能。
    nonisolated static func dedupedByName(_ entries: [GalleryImageMeta]) -> [GalleryImageMeta] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.name).inserted }
    }

    /// `manifest.json` のバイト列を `[GalleryImageMeta]` に解釈する。
    /// 新形式 (オブジェクト配列) を優先し、旧形式 (`[String]`) は全件スライドショー対象として移行する。
    /// FS 非依存・純粋なのでテスト可能。
    nonisolated static func parseManifest(_ data: Data) -> [GalleryImageMeta] {
        if let saved = try? JSONDecoder().decode([GalleryImageMeta].self, from: data) {
            return saved
        }
        if let legacy = try? JSONDecoder().decode([String].self, from: data) {
            return legacy.map { GalleryImageMeta(name: $0) }
        }
        return []
    }

    /// スライドショーに出すエントリを選ぶ。inSlideshow=true のものだけ。
    /// 1 枚も選ばれていなければ全件にフォールバックし、ウィジェットが空にならないようにする。
    /// FS 非依存・純粋なのでテスト可能。
    nonisolated static func slideshowFiltered(_ entries: [GalleryImageMeta]) -> [GalleryImageMeta] {
        let included = entries.filter(\.inSlideshow)
        return included.isEmpty ? entries : included
    }

    private func writeManifest(_ entries: [GalleryImageMeta], for idolId: String) {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: manifestURL(idolId))
        }
    }

    /// 代表(プライマリ)画像 URL。アプリ内アバター・通知・ゲームはこれを使う (読み取り互換)。
    func imageURL(for idolId: String) -> URL? {
        guard let first = manifest(idolId).first else { return nil }
        return idolFolder(idolId).appendingPathComponent(first.name)
    }

    /// ギャラリー全画像 URL (順序付き、先頭=プライマリ)。
    func imageURLs(for idolId: String) -> [URL] {
        let folder = idolFolder(idolId)
        return manifest(idolId).map { folder.appendingPathComponent($0.name) }
    }

    // MARK: - スライドショー対象選択 (ウィジェット)

    /// スライドショー対象 (inSlideshow=true) の画像 URL (順序付き)。
    /// 1 枚も選ばれていなければ全件にフォールバックし、ウィジェットが空にならないようにする。
    func slideshowURLs(for idolId: String) -> [URL] {
        let folder = idolFolder(idolId)
        return Self.slideshowFiltered(manifest(idolId)).map { folder.appendingPathComponent($0.name) }
    }

    /// 指定画像がスライドショー対象か (manifest に無ければ既定 true)。
    func isInSlideshow(_ url: URL, for idolId: String) -> Bool {
        manifest(idolId).first { $0.name == url.lastPathComponent }?.inSlideshow ?? true
    }

    /// 指定画像のスライドショー対象フラグを設定する。
    func setInSlideshow(_ included: Bool, url: URL, for idolId: String) {
        let name = url.lastPathComponent
        var order = manifest(idolId)
        guard let idx = order.firstIndex(where: { $0.name == name }) else { return }
        order[idx].inSlideshow = included
        writeManifest(order, for: idolId)
        galleryVersion &+= 1
    }

    func imageCount(for idolId: String) -> Int { manifest(idolId).count }

    func hasCustomImage(for idolId: String) -> Bool {
        idolsWithImages.contains(idolId)
    }

    /// ギャラリーに 1 枚追加する (末尾に追加)。返り値は追加した画像 URL。
    @discardableResult
    func addImage(_ image: UIImage, for idolId: String) async throws -> URL {
        let folder = idolFolder(idolId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).jpg"
        let url = folder.appendingPathComponent(name)
        // manifest を「書き込み前」に読む。先に書くと manifest() の reconcile が
        // 新ファイルを拾い、続く append と二重登録になる (同じ画像が2枚並ぶ不具合)。
        var order = manifest(idolId)
        order.append(GalleryImageMeta(name: name))
        try await Self.write(image, to: url)
        writeManifest(order, for: idolId)
        idolsWithImages.insert(idolId)
        galleryVersion &+= 1
        return url
    }

    /// 単一画像として設定する (既存を全消去して 1 枚に)。一括インポートの「アイコンを設定」用途。
    func saveImage(_ image: UIImage, for idolId: String) async throws {
        await deleteAllImages(for: idolId)
        try await addImage(image, for: idolId)
    }

    /// 指定 URL の 1 枚を削除する。
    func deleteImage(at url: URL, for idolId: String) async throws {
        try await Self.delete(at: url)
        let order = manifest(idolId).filter { $0.name != url.lastPathComponent }
        writeManifest(order, for: idolId)
        if order.isEmpty { idolsWithImages.remove(idolId) }
        galleryVersion &+= 1
    }

    /// 指定 URL をプライマリ(先頭)にする。
    func setPrimary(_ url: URL, for idolId: String) {
        let name = url.lastPathComponent
        var order = manifest(idolId)
        guard let idx = order.firstIndex(where: { $0.name == name }), idx != 0 else { return }
        let entry = order.remove(at: idx)
        order.insert(entry, at: 0)
        writeManifest(order, for: idolId)
        galleryVersion &+= 1
    }

    /// このアイドルの全画像を削除する。
    func deleteAllImages(for idolId: String) async {
        let folder = idolFolder(idolId)
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: folder)
        }.value
        idolsWithImages.remove(idolId)
        galleryVersion &+= 1
    }

    // MARK: - Brand (single image)

    func brandImageURL(for brandId: String) -> URL? {
        guard brandsWithImages.contains(brandId) else { return nil }
        return brandDirectory.appendingPathComponent("\(brandId).jpg")
    }

    func saveBrandImage(_ image: UIImage, for brandId: String) async throws {
        try await Self.write(image, to: brandDirectory.appendingPathComponent("\(brandId).jpg"))
        brandsWithImages.insert(brandId)
    }

    func deleteBrandImage(for brandId: String) async throws {
        try await Self.delete(at: brandDirectory.appendingPathComponent("\(brandId).jpg"))
        brandsWithImages.remove(brandId)
    }

    func hasBrandImage(for brandId: String) -> Bool {
        brandsWithImages.contains(brandId)
    }

    // MARK: - Bulk reset

    /// アイドルカスタム画像を全削除する (フォルダごと)。
    func clearAllIdolImages() async throws {
        let dir = idolDirectory
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                try? fm.removeItem(atPath: dir.appendingPathComponent(f).path)
            }
        }.value
        idolsWithImages = []
        galleryVersion &+= 1
    }

    func clearAllBrandImages() async throws {
        let dir = brandDirectory
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for f in files where f.hasSuffix(".jpg") {
                try? fm.removeItem(atPath: dir.appendingPathComponent(f).path)
            }
        }.value
        brandsWithImages = []
    }

    // MARK: - Migration & scan

    /// 旧仕様の単一ファイル `custom_images/{idolId}.jpg` を `custom_images/{idolId}/{uuid}.jpg`
    /// (+ manifest) へ移行する。初回起動 1 回だけ実体が動く (以降は対象ファイルが無いので no-op)。
    private func migrateLegacySingleImages() {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: idolDirectory.path)) ?? []
        for entry in entries where entry.hasSuffix(".jpg") {
            let idolId = String(entry.dropLast(4))
            let legacy = idolDirectory.appendingPathComponent(entry)
            let folder = idolFolder(idolId)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = "\(UUID().uuidString).jpg"
            try? fm.moveItem(at: legacy, to: folder.appendingPathComponent(name))
            writeManifest([GalleryImageMeta(name: name)], for: idolId)
        }
    }

    /// 画像を 1 枚以上持つアイドル ID (= manifest が空でないフォルダ)。
    private func scanIdolIds() -> Set<String> {
        let fm = FileManager.default
        var result: Set<String> = []
        for entry in (try? fm.contentsOfDirectory(atPath: idolDirectory.path)) ?? [] {
            let path = idolDirectory.appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if !manifest(entry).isEmpty { result.insert(entry) }
        }
        return result
    }

    private static func scanIds(in directory: URL) -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(files.compactMap { $0.hasSuffix(".jpg") ? String($0.dropLast(4)) : nil })
    }

    // MARK: - File IO (off main)

    private static func write(_ image: UIImage, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            // ギャラリー/ウィジェット用に元のアスペクトを保ったまま最大 1024px へ縮小する
            // (アバターは円内 aspectFill で正方クロップされるので元データを正方化しない)。
            guard let data = downsampledJPEGNonisolated(image, maxPixels: 1024, quality: 0.82) else {
                throw ImageError.compressionFailed
            }
            try data.write(to: url)
        }.value
    }

    private static func delete(at url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.removeItem(at: url)
        }.value
    }

    enum ImageError: Error {
        case compressionFailed
    }
}

/// MainActor 外で安全に呼べるダウンサンプリング + JPEG 化。元のアスペクト比を保つ。
/// 既に小さい画像はそのまま JPEG 化する。
private func downsampledJPEGNonisolated(_ image: UIImage, maxPixels: CGFloat, quality: CGFloat) -> Data? {
    func originalJPEG() -> Data? { image.jpegData(compressionQuality: quality) }

    guard let cg = image.cgImage else { return originalJPEG() }
    let w = CGFloat(cg.width)
    let h = CGFloat(cg.height)
    let longSide = max(w, h)
    guard longSide > maxPixels else { return originalJPEG() }

    let scale = maxPixels / longSide
    let tw = max(1, Int((w * scale).rounded()))
    let th = max(1, Int((h * scale).rounded()))
    guard let ctx = CGContext(
        data: nil,
        width: tw,
        height: th,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return originalJPEG()
    }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
    guard let scaled = ctx.makeImage() else { return originalJPEG() }
    return UIImage(cgImage: scaled).jpegData(compressionQuality: quality)
}
