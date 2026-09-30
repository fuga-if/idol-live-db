import SwiftUI

/// 結果の共有シート。画像カード (ベスト10) と、文字だけの共有。
struct SortMakerShareSheet: View {
    let subject: SortMakerSubject
    let scopeLabel: String
    let rows: [(rank: Int, item: SortMakerItem)]

    @State private var artwork = ShareArtworkLoader()

    private var topArtworkURL: String? {
        if case .song(let song) = rows.first?.item { return song.artworkUrl }
        return nil
    }

    var body: some View {
        ShareCardSheet(title: "結果をシェア", screenName: "sort_maker_share") {
            VStack(spacing: DS.sp4) {
                ShareCardActionPane(card: { size in
                    SortMakerShareCard(subject: subject, scopeLabel: scopeLabel, rows: rows,
                                       artwork: artwork.image, size: size)
                }, isPreparingCard: artwork.isPreparing(urlString: topArtworkURL))

                Button {
                    AppAnalytics.tap("sort_maker.share_text")
                    SystemShare.present(items: [shareText])
                } label: {
                    Label("テキストでシェア", systemImage: "text.alignleft")
                        .font(.imasSubhead.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .task { await artwork.load(from: topArtworkURL) }
    }

    /// 文面はコアが組む (順位の書き方・件数の上限・ハッシュタグ)。
    private var shareText: String {
        sortMakerShareText(title: subject.title, scopeLabel: scopeLabel,
                           rows: rows.map { SortMakerShareRow(rank: UInt32($0.rank), name: $0.item.title) })
    }
}

/// 画像カード。near-black 地に 1 位を大きく、2〜10 位を 1 行ずつ。
/// ImageRenderer で焼くので DS の動的色は使わず固定色だけ (ShareCardScaffold の方針)。
/// 版権の都合でアイドルの画像は載せず、メンバーカラーの印だけにする。
struct SortMakerShareCard: View {
    let subject: SortMakerSubject
    let scopeLabel: String
    let rows: [(rank: Int, item: SortMakerItem)]
    var artwork: UIImage?
    var size: ShareCard.Size = ShareCard.portrait

    private var palette: ShareCardPalette { ShareCardPalette(seed: rows.first?.item.seed) }

    var body: some View {
        let palette = self.palette
        SoloShareScaffold(palette: palette, size: size, badge: subject.title) {
            VStack(alignment: .leading, spacing: 0) {
                Text(scopeLabel)
                    .font(.imasScaled(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.top, 10)

                if let first = rows.first {
                    HStack(spacing: 16) {
                        if subject == .song {
                            firstVisual(first.item)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(first.rank)位")
                                .font(.imasScaled(15, weight: .bold))
                                .foregroundStyle(palette.accent)
                            Text(first.item.title)
                                .font(.imasScaled(32, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .padding(.top, 18)
                }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(rows.dropFirst().prefix(9).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 10) {
                            Text("\(row.rank)")
                                .font(.imasScaled(15, weight: .bold)).monospacedDigit()
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 26, alignment: .trailing)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ShareCardPalette(seed: row.item.seed).accent)
                                .frame(width: 4, height: 16)
                            Text(row.item.title)
                                .font(.imasScaled(16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 20)
            }
        }
    }

    @ViewBuilder
    private func firstVisual(_ item: SortMakerItem) -> some View {
        if let artwork {
            Image(uiImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.accentDeep)
                .frame(width: 96, height: 96)
                .overlay(Image(systemName: "music.note").font(.imasScaled(32)).foregroundStyle(.white.opacity(0.3)))
        }
    }
}
