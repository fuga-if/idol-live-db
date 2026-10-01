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
                            ProgressView()
                            Text("画像を作っています…").font(.imasCaption).foregroundStyle(DS.ink3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                    if board.unplacedIds.count > 0 {
                        Text("未分類の \(board.unplacedIds.count) 件は画像に入りません。")
                            .font(.imasCaption).foregroundStyle(DS.ink3)
                    }
                }
                .padding(DS.sp5)
            }
            .background(DS.bg)
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("画像にする")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
            }
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
                Button {
                    AppAnalytics.tap("tier_list.save_photo")
                    Task { await saveToPhotos() }
                } label: {
                    Label("写真に保存", systemImage: "square.and.arrow.down")
                        .font(.imasHeadline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    AppAnalytics.tap("tier_list.share_image")
                    if let image { SystemShare.present(items: [ShareCardImageSource(image)]) }
                } label: {
                    Label("シェア", systemImage: "square.and.arrow.up")
                        .font(.imasHeadline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            }
            .disabled(image == nil)
            Button("テキストでシェア") {
                AppAnalytics.tap("tier_list.share_text")
                SystemShare.present(items: [shareText])
            }
            .font(.imasSubhead)
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
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: TierListBoardImage.width, height: nil)
        image = renderer.uiImage
    }

    /// 段に載っている曲のジャケを小さく読む (数百枚でも重くならない大きさ)。
    private func loadThumbnails() async -> [String: UIImage] {
        let targets: [(String, URL)] = board.itemIds.compactMap { id in
            guard board.tierIndex(of: id) != nil, case .song(let song)? = items[id],
                  let url = song.artworkUrl.flatMap(URL.safeHTTP(string:)) else { return nil }
            return (id, url)
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

/// 書き出す 1 枚。near-black の地に、見出し → 段ごとの行 → フッター。
///
/// ImageRenderer で焼く固定キャンバスなので、色は固定色、文字は固定 pt
/// (アプリの文字サイズ倍率がかかると枠からあふれる。共有カードと同じ扱い)。
/// 版権の都合でアイドルの絵は載せず、メンバーカラーのモノグラムにする。
struct TierListBoardImage: View {
    let board: TierListBoard
    let items: [String: SortMakerItem]
    let thumbnails: [String: UIImage]

    static let width: CGFloat = 540
    private let labelWidth: CGFloat = 76
    private let cell: CGFloat = 62
    private let gap: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 2) {
                ForEach(board.tiers) { tier in
                    row(tier)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 18)
            ShareCardFooter(ink: .white.opacity(0.62), rule: .white.opacity(0.16))
                .padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: Self.width)
        .background(ShareInk.nearBlack)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Rectangle().fill(ShareCardPalette(seed: board.tiers.first?.colorSeed).accent).frame(width: 18, height: 3)
                Text("TIER LIST")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(board.displayTitle)
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.top, 4)
            Text(board.scopeLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
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
            .frame(maxWidth: .infinity, minHeight: cell + 22 + gap * 2, alignment: .topLeading)
            .background(Color.white.opacity(0.06))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ id: String) -> some View {
        VStack(spacing: 3) {
            visual(id)
                .frame(width: cell, height: cell)
            Text(items[id]?.title ?? "")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: cell)
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
