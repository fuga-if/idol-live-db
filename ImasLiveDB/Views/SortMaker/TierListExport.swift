import Nuke
import OSLog
import Photos
import SwiftUI

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "tier_list_export")

/// 並べ終えたティアー表を「全部入りの 1 枚」にして、写真に保存 / シェアする。
///
/// 画像は段ごとに、ジャケ (曲) かメンバーカラーのモノグラム (アイドル) を全部並べる。
/// 件数で縦に伸びる (横幅は SNS で縮んでも読める 1080px 固定)。
/// ImageRenderer は画像の非同期読み込みを待たないので、ジャケは先に小さく読んでから焼く。
struct TierListExportSheet: View {
    let board: TierListBoard
    let items: [String: SortMakerItem]

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.sp4) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
                    } else {
                        VStack(spacing: DS.sp3) {
                            ImasInlineLoading()
                            Text("画像を作っています…").font(.imasCaption).foregroundStyle(DS.ink3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                    if board.unplacedIds.count > 0 {
                        ImasNote("未分類の \(board.unplacedIds.count) 件は画像に入りません。")
                    }
                }
                .padding(DS.sp5)
            }
            .background(DS.bg)
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("画像にする")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .alert(saveMessage ?? "", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) {
                Button("OK") {}
            }
            .task { await render() }
            .trackScreen("tier_list_export")
        }
    }

    private var actions: some View {
        VStack(spacing: DS.sp3) {
            HStack(spacing: DS.sp3) {
                ImasButton(title: "写真に保存", systemImage: "square.and.arrow.down", role: .primary, size: .large) {
                    AppAnalytics.tap("tier_list.save_photo")
                    Task { await saveToPhotos() }
                }
                ImasButton(title: "シェア", systemImage: "square.and.arrow.up", role: .secondary, size: .large) {
                    AppAnalytics.tap("tier_list.share_image")
                    if let image { SystemShare.present(items: [ShareCardImageSource(image)]) }
                }
            }
            .disabled(image == nil)
            ImasButton(title: "テキストでシェア", role: .plain, size: .medium) {
                AppAnalytics.tap("tier_list.share_text")
                SystemShare.present(items: [shareText])
            }
        }
        .padding(.horizontal, DS.sp5)
        .padding(.vertical, DS.sp3)
        .background(.bar)
    }

    /// 文面はコアが組む (空の段を飛ばす・1 段 5 件まで)。
    private var shareText: String {
        tierListShareText(
            title: board.displayTitle, scopeLabel: board.scopeLabel,
            tiers: board.tiers.map { t in
                TierListShareTier(label: t.label, names: board.ids(inTier: t.id).compactMap { items[$0]?.title })
            })
    }

    // MARK: - 画像

    private func render() async {
        let thumbnails = await loadThumbnails()
        let content = TierListBoardImage(board: board, items: items, thumbnails: thumbnails)
        // 縦が長すぎると描画できる上限 (一辺 8192px 前後) を超えて真っ黒になるため、
        // 等倍で高さを測ってから上限に収まる倍率で焼く専用パス (普段は 2 倍 = 横 1080px)。
        image = ShareCardRenderer.renderTall(content, width: TierListBoardImage.width,
                                             maxPixelHeight: TierListBoardImage.maxPixelHeight)
    }

    /// 段に載っているものの絵を小さく読む (数百枚でも重くならない大きさ)。
    /// 曲はジャケ、アイドルはアプリ内で出しているのと同じアイコン (利用者が設定した画像)。
    /// アイコンが無いアイドルはモノグラムのまま。
    private func loadThumbnails() async -> [String: UIImage] {
        let imageService = CustomImageService.shared
        let targets: [(String, URL)] = board.itemIds.compactMap { id in
            guard board.tierIndex(of: id) != nil else { return nil }
            switch items[id] {
            case .song(let song): return song.artworkUrl.flatMap(URL.safeHTTP(string:)).map { (id, $0) }
            case .idol(let idol): return imageService.imageURL(for: idol.id).map { (id, $0) }
            case nil: return nil
            }
        }
        return await withTaskGroup(of: (String, UIImage?).self) { group in
            var result: [String: UIImage] = [:]
            var iterator = targets.makeIterator()
            // 同時に読むのは 8 枚まで。
            for _ in 0..<8 {
                guard let (id, url) = iterator.next() else { break }
                group.addTask { (id, await Self.thumbnail(url)) }
            }
            for await (id, image) in group {
                if let image { result[id] = image }
                if let (nextId, url) = iterator.next() {
                    group.addTask { (nextId, await Self.thumbnail(url)) }
                }
            }
            return result
        }
    }

    private static func thumbnail(_ url: URL) async -> UIImage? {
        // 端末内の画像 (アイドルのアイコン) はその場で縮める。
        if url.isFileURL {
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            let side: CGFloat = 144
            let scale = side / min(image.size.width, image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        let request = ImageRequest(url: url, processors: [.resize(size: CGSize(width: 144, height: 144), unit: .pixels)])
        do {
            return try await ImagePipeline.shared.image(for: request)
        } catch {
            logger.error("tier_list_thumbnail_failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveToPhotos() async {
        guard let image else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveMessage = "写真への保存が許可されていません。設定アプリの「写真」から許可してください。"
            return
        }
        do {
            // performChanges はクロージャを別キューで走らせる。MainActor を継がせないよう @Sendable にする
            // (付けないと Swift 6 で「non-Sendable なクロージャを送る」コンパイルエラー)。
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saveMessage = "写真に保存しました"
        } catch {
            logger.error("tier_list_save_photo_failed: \(error.localizedDescription)")
            saveMessage = "保存できませんでした。もう一度試してください。"
        }
    }
}

/// 書き出す 1 枚。骨格は `PosterShareScaffold` (見出し・透かし・フッター)、中身は段ごとの行。
///
/// ImageRenderer で焼く固定キャンバスなので、色は固定色、文字は固定 pt
/// (アプリの文字サイズ倍率がかかると枠からあふれる。共有カードと同じ扱い)。
/// アイドルはアプリ内と同じアイコン (利用者が設定した画像) を、無ければメンバーカラーのモノグラムを載せる。
struct TierListBoardImage: View {
    let board: TierListBoard
    let items: [String: SortMakerItem]
    let thumbnails: [String: UIImage]

    static let width: CGFloat = 540
    /// 書き出す画像の縦の上限 (px)。これを超えるときは倍率を下げる。
    static let maxPixelHeight: CGFloat = 8000
    private let labelWidth: CGFloat = 76
    private let gap: CGFloat = 6

    /// 載せる件数が多いほど 1 枚を小さくして、縦に伸びすぎないようにする
    /// (全曲から数百件を段に入れても読める大きさで 1 枚に収める)。
    private var placedCount: Int { board.placedCount }
    private var cell: CGFloat { placedCount <= 150 ? 62 : (placedCount <= 400 ? 46 : 34) }
    private var showsNames: Bool { placedCount <= 400 }
    private var palette: ShareCardPalette { ShareCardPalette(seed: board.tiers.first?.colorSeed) }

    var body: some View {
        PosterShareScaffold(
            palette: palette,
            width: Self.width, height: nil,
            kicker: "TIER LIST",
            title: board.displayTitle,
            titleSize: 32,
            subtitle: board.scopeLabel
        ) {
            VStack(spacing: 2) {
                ForEach(board.tiers) { tier in
                    row(tier)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 18)
        }
    }

    private func row(_ tier: TierDef) -> some View {
        let ids = board.ids(inTier: tier.id)
        let accent = ShareCardPalette(seed: tier.colorSeed).accent
        return HStack(alignment: .top, spacing: 0) {
            Text(tier.label)
                .font(.system(size: tier.label.count <= 2 ? 30 : 14, weight: .black))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .foregroundStyle(ColorMath.onColor(accent))
                .padding(.horizontal, 4)
                .frame(width: labelWidth)
                .frame(maxHeight: .infinity)
                .background(accent)
            FlowLayout(spacing: gap) {
                ForEach(ids, id: \.self) { id in
                    tile(id)
                }
            }
            .padding(gap)
            .frame(maxWidth: .infinity, minHeight: cell + (showsNames ? 22 : 8) + gap * 2, alignment: .topLeading)
            .background(Color.white.opacity(0.06))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ id: String) -> some View {
        VStack(spacing: 3) {
            visual(id)
                .frame(width: cell, height: cell)
            if showsNames {
                Text(items[id]?.title ?? "")
                    .font(.system(size: cell >= 60 ? 9 : 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(width: cell)
            }
        }
    }

    @ViewBuilder
    private func visual(_ id: String) -> some View {
        switch items[id] {
        case .song(let song):
            if let image = thumbnails[id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ShareCardPalette(seed: BrandColors.hex(for: song.brandId)).accentDeep)
                    .overlay(
                        Text(song.title)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(4)
                    )
            }
        case .idol(let idol) where thumbnails[id] != nil:
            Image(uiImage: thumbnails[id]!)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
                .overlay(Circle().stroke(ShareCardPalette(seed: idol.color).accent, lineWidth: 2))
        case .idol(let idol):
            let palette = ShareCardPalette(seed: idol.color)
            Circle()
                .fill(palette.accentDeep)
                .overlay(Circle().stroke(palette.accent, lineWidth: 2))
                .overlay(
                    Text(idol.shortName)
                        .font(.system(size: idol.shortName.count >= 3 ? 14 : 19, weight: .black))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(6)
                )
        case nil:
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.1))
        }
    }
}
