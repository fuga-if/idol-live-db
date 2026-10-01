import SwiftUI

/// 結果の共有シート。画像カード (ベスト10) と、文字だけの共有。
struct SortMakerShareSheet: View {
    let subject: SortMakerSubject
    let scopeLabel: String
    let rows: [(rank: Int, item: SortMakerItem)]

    /// 表彰台 (1〜3 位) のジャケ。ImageRenderer は非同期読み込みを待たないので先に読んでおく。
    @State private var artworks: [String: UIImage] = [:]
    @State private var isLoadingArtwork = true

    var body: some View {
        ShareCardSheet(title: "結果をシェア", screenName: "sort_maker_share") {
            VStack(spacing: DS.sp4) {
                ShareCardActionPane(card: { size in
                    SortMakerShareCard(subject: subject, scopeLabel: scopeLabel, rows: rows,
                                       artworks: artworks, size: size)
                }, isPreparingCard: isLoadingArtwork)

                ImasButton(title: "テキストでシェア", systemImage: "text.alignleft", role: .secondary, size: .medium) {
                    AppAnalytics.tap("sort_maker.share_text")
                    SystemShare.present(items: [shareText])
                }
            }
        }
        .task { await loadArtworks() }
    }

    private func loadArtworks() async {
        var loaded: [String: UIImage] = [:]
        for row in rows.prefix(3) {
            if case .song(let song) = row.item, let image = await ShareCardArtwork.load(from: song.artworkUrl) {
                loaded[song.id] = image
            }
        }
        artworks = loaded
        isLoadingArtwork = false
    }

    /// 文面はコアが組む (順位の書き方・件数の上限・ハッシュタグ)。
    private var shareText: String {
        sortMakerShareText(title: subject.title, scopeLabel: scopeLabel,
                           rows: rows.map { SortMakerShareRow(rank: UInt32($0.rank), name: $0.item.title) })
    }
}

/// 画像カード: ランキングのポスター。骨格は `PosterShareScaffold` (見出し・透かし・フッター)、
/// 中身は 1〜3 位の表彰台 (1 位を大きく真ん中に) と 4〜10 位の 2 列。1 位の色を差し色として 1 点だけ使う。
///
/// ImageRenderer で焼く固定キャンバスなので、色は固定色だけ、文字は固定 pt
/// (アプリ内の文字サイズ倍率がかかると枠からあふれる。QuizShareCard と同じ扱い)。
/// 版権の都合でアイドルの絵は載せず、メンバーカラーのモノグラムにする。
struct SortMakerShareCard: View {
    let subject: SortMakerSubject
    let scopeLabel: String
    let rows: [(rank: Int, item: SortMakerItem)]
    var artworks: [String: UIImage] = [:]
    var size: ShareCard.Size = ShareCard.portrait

    /// 差し色の拠り所。1 位の色 (アイドルはメンバーカラー、曲はブランド色) → 無ければ中立色。
    private var palette: ShareCardPalette {
        rows.first.map { ShareCardPalette(seed: $0.item.seed) } ?? ShareCardPalette(seed: nil)
    }
    /// 差し色。アイドルはメンバーカラー、曲はブランド色 (`SortMakerItem.seed`)。
    private func color(for item: SortMakerItem) -> Color {
        ShareCardPalette(seed: item.seed).accent
    }
    private var podium: [(rank: Int, item: SortMakerItem)] { Array(rows.prefix(3)) }
    private var rest: [(rank: Int, item: SortMakerItem)] { Array(rows.dropFirst(3).prefix(7)) }

    var body: some View {
        PosterShareScaffold(
            palette: palette,
            width: size.width, height: size.height,
            kicker: subject.title,
            trailingKicker: "RESULT",
            title: rows.count >= 10 ? "MY BEST 10" : "MY BEST \(rows.count)",
            subtitle: scopeLabel
        ) {
            VStack(alignment: .leading, spacing: 0) {
                podiumRow
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                if !rest.isEmpty {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                        .padding(.top, 18)
                    restGrid.padding(.top, 14)
                }
            }
        }
    }

    // MARK: 表彰台

    private var podiumRow: some View {
        // 並びは 2 位・1 位・3 位 (1 位を真ん中に高く)。
        let order = [1, 0, 2].filter { $0 < podium.count }
        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(order, id: \.self) { i in
                podiumSlot(podium[i], isFirst: i == 0)
            }
        }
    }

    private func podiumSlot(_ row: (rank: Int, item: SortMakerItem), isFirst: Bool) -> some View {
        let side: CGFloat = isFirst ? 148 : 112
        return VStack(spacing: 8) {
            Text("\(row.rank)")
                .font(.system(size: isFirst ? 44 : 32, weight: .black).width(.compressed).monospacedDigit())
                .foregroundStyle(isFirst ? palette.accent : .white.opacity(0.75))
            visual(row.item, side: side)
            Text(row.item.title)
                .font(.system(size: isFirst ? 15 : 12, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: side + 12, height: isFirst ? 40 : 32, alignment: .top)
        }
    }

    @ViewBuilder
    private func visual(_ item: SortMakerItem, side: CGFloat) -> some View {
        switch item {
        case .song(let song):
            if let image = artworks[song.id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.08, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: side * 0.08, style: .continuous)
                    .fill(ShareCardPalette(seed: nil).accentDeep)
                    .frame(width: side, height: side)
                    .overlay(
                        Text(song.title)
                            .font(.system(size: side * 0.12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(side * 0.1)
                    )
            }
        case .idol(let idol):
            let palette = ShareCardPalette(seed: idol.color)
            Circle()
                .fill(palette.accentDeep)
                .overlay(Circle().stroke(palette.accent, lineWidth: side * 0.03))
                .overlay(
                    Text(idol.shortName)
                        .font(.system(size: side * (idol.shortName.count >= 3 ? 0.24 : 0.32), weight: .black))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(side * 0.12)
                )
                .frame(width: side, height: side)
        }
    }

    // MARK: 4〜10 位

    private var restGrid: some View {
        // 縦に読めるよう左列 4〜7 位、右列 8〜10 位。
        let left = Array(rest.prefix(4))
        let right = Array(rest.dropFirst(4))
        return HStack(alignment: .top, spacing: 20) {
            column(left)
            column(right)
        }
    }

    private func column(_ items: [(rank: Int, item: SortMakerItem)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text("\(row.rank)")
                        .font(.system(size: 20, weight: .heavy).width(.compressed).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 22, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(for: row.item))
                        .frame(width: 3, height: 14)
                    Text(row.item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
