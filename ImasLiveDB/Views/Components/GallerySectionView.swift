import SwiftUI
import PhotosUI

/// 複数画像ギャラリーの汎用セクション (`CustomImageService` の `GalleryKind` 共通)。
/// アイドル・ユニット詳細の画像ギャラリーをどちらもこれで組む。
///
/// ウィジェットのスライドショー選択 (`inSlideshow`) はホーム画面ウィジェットが
/// アイドル画像専用のため、`kind == .idol` のときだけ出す。
struct GallerySectionView: View {
    let kind: GalleryKind
    let entityId: String
    /// 空状態メッセージに使う呼称 (例: "アイコン")。
    var entityLabel: String = "アイコン"
    /// ギャラリー変更後の追加の後始末 (ウィジェットへの反映など)。
    var onChange: () -> Void = {}

    @State private var imageService = CustomImageService.shared
    @State private var galleryPicks: [PhotosPickerItem] = []

    private var showsSlideshowToggle: Bool { kind == .idol }

    var body: some View {
        // galleryVersion を読んで追加/削除/並べ替え後に再描画する。
        let _ = imageService.galleryVersion
        let urls = imageService.imageURLs(for: entityId, kind: kind)
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                ImasSectionHeader(title: "ギャラリー", count: urls.isEmpty ? nil : "\(urls.count)", tight: true)
                Spacer()
                PhotosPicker(selection: $galleryPicks, maxSelectionCount: 10, matching: .images) {
                    Label("追加", systemImage: "plus")
                        .font(.imasSubhead.weight(.medium))
                }
            }
            .padding(.horizontal, DS.sp5)

            if urls.isEmpty {
                ImasNote(showsSlideshowToggle
                         ? "画像を追加すると、先頭の1枚が\(entityLabel)になります。ホーム画面ウィジェットにも使えます。"
                         : "画像を追加すると、先頭の1枚が\(entityLabel)になります。")
                    .padding(.horizontal, DS.sp5)
            } else {
                galleryGrid(urls: urls)

                ImasNote(showsSlideshowToggle
                         ? "長押しで\(entityLabel)設定・ウィジェットのスライドショー対象を切り替えられます。"
                         : "長押しで\(entityLabel)に設定・削除できます。")
                    .padding(.horizontal, DS.sp5)
            }
        }
        .onChange(of: galleryPicks) { _, picks in
            guard !picks.isEmpty else { return }
            Task {
                for pick in picks {
                    if let data = try? await pick.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        _ = try? await imageService.addImage(image, for: entityId, kind: kind)
                    }
                }
                galleryPicks = []
                onChange()
            }
        }
    }

    /// ギャラリーを横3列で並べる。`LazyVGrid` + 貪欲セルの組み合わせだと flexible 列が
    /// 広がって列数が崩れる (実機で2列になる) ため、HStack で確実に3等分する。
    @ViewBuilder
    private func galleryGrid(urls: [URL]) -> some View {
        let spacing = DS.sp2
        let perRow = 3
        VStack(spacing: spacing) {
            ForEach(Array(stride(from: 0, to: urls.count, by: perRow)), id: \.self) { start in
                let end = min(start + perRow, urls.count)
                HStack(spacing: spacing) {
                    ForEach(start..<end, id: \.self) { i in
                        galleryThumb(url: urls[i], isPrimary: i == 0,
                                    inSlideshow: showsSlideshowToggle ? imageService.isInSlideshow(urls[i], for: entityId) : true)
                            .frame(maxWidth: .infinity)
                    }
                    // 端数行も 1/3 幅を保つよう空セルで埋める (左寄せ維持)。
                    ForEach(end..<(start + perRow), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, DS.sp5)
    }

    private func galleryThumb(url: URL, isPrimary: Bool, inSlideshow: Bool) -> some View {
        Color.clear
            .overlay {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    DS.fill
                }
                // スライドショー対象外は淡く落として一目で分かるようにする。
                .opacity(inSlideshow ? 1 : 0.45)
            }
            // グリッドのセルは .fit で列幅に収める。.fill だと flexible 列が貪欲セルに
            // 合わせて広がり、count:3 指定でも 2 列しか並ばなくなる (SwiftUI のレイアウト罠)。
            .aspectRatio(1, contentMode: .fit)
            // 可変幅のグリッドセル (列幅に合わせて伸び縮み) の角丸切り抜き。`ImasArtwork` は
            // 固定 size 前提 (テーマ色のフォールバック音符・回収スタンプ等も this では不要) で
            // 流用できないため、トークン (DS.rSM) だけ使って形はここに残す。
            .clipShape(RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
            .overlay(alignment: .topLeading) {
                if isPrimary { ImasMediaBadge(systemImage: "star.fill", label: entityLabel) }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsSlideshowToggle && !inSlideshow {
                    ImasMediaBadge(systemImage: "play.slash.fill", accessibilityLabel: "スライドショー対象外")
                }
            }
            .contextMenu {
                if !isPrimary {
                    Button {
                        imageService.setPrimary(url, for: entityId, kind: kind)
                        onChange()
                    } label: {
                        Label("\(entityLabel)にする", systemImage: "star")
                    }
                }
                if showsSlideshowToggle {
                    Button {
                        imageService.setInSlideshow(!inSlideshow, url: url, for: entityId)
                        onChange()
                    } label: {
                        Label(inSlideshow ? "スライドショーから外す" : "スライドショーに入れる",
                              systemImage: inSlideshow ? "play.slash" : "play.rectangle")
                    }
                }
                Button(role: .destructive) {
                    Task {
                        try? await imageService.deleteImage(at: url, for: entityId, kind: kind)
                        onChange()
                    }
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
    }
}

#Preview {
    ScrollView {
        GallerySectionView(kind: .unit, entityId: "preview-unit", entityLabel: "アイコン")
            .padding(.vertical)
    }
}
