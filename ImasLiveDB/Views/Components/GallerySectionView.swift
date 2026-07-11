import SwiftUI
import PhotosUI

/// 複数画像ギャラリーの汎用セクション (`CustomImageService` の `GalleryKind` 共通)。
/// アイドル詳細画面の実装 (`IdolDetailView.gallerySection`) と同等の見た目・操作を、
/// 任意のエンティティ (現状はユニット) 向けに再利用できる形にしたもの。
///
/// ウィジェットのスライドショー選択 (`inSlideshow`) はホーム画面ウィジェットが
/// アイドル画像専用のため、このコンポーネントには含めない。
struct GallerySectionView: View {
    let kind: GalleryKind
    let entityId: String
    /// 空状態メッセージに使う呼称 (例: "アイコン")。
    var entityLabel: String = "アイコン"

    @State private var imageService = CustomImageService.shared
    @State private var galleryPicks: [PhotosPickerItem] = []

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
                Text("画像を追加すると、先頭の1枚が\(entityLabel)になります。")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.sp5)
            } else {
                galleryGrid(urls: urls)

                Text("長押しで\(entityLabel)に設定・削除できます。")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink3)
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
                        galleryThumb(url: urls[i], isPrimary: i == 0)
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

    private func galleryThumb(url: URL, isPrimary: Bool) -> some View {
        Color.clear
            .overlay {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    DS.fill
                }
            }
            // グリッドのセルは .fit で列幅に収める。.fill だと flexible 列が貪欲セルに
            // 合わせて広がり、count:3 指定でも 2 列しか並ばなくなる (SwiftUI のレイアウト罠)。
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
            .overlay(alignment: .topLeading) {
                if isPrimary {
                    Label(entityLabel, systemImage: "star.fill")
                        .font(.imasScaled(9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(5)
                }
            }
            .contextMenu {
                if !isPrimary {
                    Button {
                        imageService.setPrimary(url, for: entityId, kind: kind)
                    } label: {
                        Label("\(entityLabel)にする", systemImage: "star")
                    }
                }
                Button(role: .destructive) {
                    Task { try? await imageService.deleteImage(at: url, for: entityId, kind: kind) }
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
