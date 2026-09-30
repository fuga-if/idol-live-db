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

/// 画像カード: ランキングのポスター。
///
/// 上に「MY BEST 10」の大見出し、中央に 1〜3 位の表彰台 (1 位を大きく真ん中に)、
/// 下に 4〜10 位を 2 列で。near-black の単色地に、1 位の色を差し色として 1 点だけ使う
/// (ShareCardScaffold のアートディレクション)。
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

    private var accent: Color { rows.first.map { color(for: $0.item) } ?? ShareCardPalette(seed: nil).accent }

    /// 差し色。アイドルはメンバーカラー、曲はブランド色 (`SortMakerItem.seed`)。
    private func color(for item: SortMakerItem) -> Color {
        ShareCardPalette(seed: item.seed).accent
    }
    private var podium: [(rank: Int, item: SortMakerItem)] { Array(rows.prefix(3)) }
    private var rest: [(rank: Int, item: SortMakerItem)] { Array(rows.dropFirst(3).prefix(7)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShareInk.nearBlack
            watermark
            VStack(alignment: .leading, spacing: 0) {
                header
                podiumRow
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                if !rest.isEmpty {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                        .padding(.top, 18)
                    restGrid.padding(.top, 14)
                }
                Spacer(minLength: 0)
                ShareCardFooter(ink: .white.opacity(0.62), rule: .white.opacity(0.16))
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 28)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: 見出し

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Rectangle().fill(accent).frame(width: 18, height: 3)
                Text(subject.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 8)
                Text("RESULT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Text(rows.count >= 10 ? "MY BEST 10" : "MY BEST \(rows.count)")
                .font(.system(size: 50, weight: .black).width(.compressed))
                .foregroundStyle(.white)
                .padding(.top, 6)
            Text(scopeLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
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
                .foregroundStyle(isFirst ? accent : .white.opacity(0.75))
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

    /// 右上に覗く淡い同心円 1 つ (他の共有カードと同じ透かし)。
    private var watermark: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.06), lineWidth: 1.5)
                .frame(width: size.width, height: size.width)
            Circle().stroke(accent.opacity(0.16), lineWidth: 1.5)
                .frame(width: size.width * 0.667, height: size.width * 0.667)
        }
        .frame(width: size.width, height: size.height)
        .offset(x: size.width * 0.42, y: -size.height * 0.32)
    }
}
