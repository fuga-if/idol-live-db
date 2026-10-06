import SwiftUI
import UIKit

/// 投票結果の画像に載せる候補 1 つ (名前・差し色・焼き込む画像)。
struct PollResultShareItem {
    let name: String
    /// 差し色の拠り所 (曲・ユニットはブランド色、アイドルはメンバーカラー)。
    let seed: String?
    /// 表彰台に焼く画像。曲はジャケ、アイドル・ユニットは端末に保存した画像。
    var image: UIImage?
    /// 画像の無いアイドルの判子の文字 (略称)。曲・ユニットは nil。
    var monogram: String?
}

/// みんなの投票の結果をシェアするシート。画像の中身 (見出し・順位・載せる数) はコアの `pollResultCard`。
struct PollResultShareSheet: View {
    let poll: Poll
    let entries: [PollEntry]

    @State private var card: PollResultCard?
    @State private var items: [String: PollResultShareItem] = [:]

    var body: some View {
        ShareCardSheet(title: "結果をシェア", screenName: "poll_result_share") {
            ShareCardActionPane(card: { size in
                if let card {
                    PollResultShareCard(card: card, items: items, size: size)
                } else {
                    ShareInk.nearBlack.frame(width: size.width, height: size.height)
                }
            }, isPreparingCard: card == nil)
        }
        .task { await load() }
    }

    private func load() async {
        let now = Date()
        let input = PollResultCardInput(
            title: poll.title,
            target: poll.targetType.cardTarget,
            isActive: poll.isActive,
            endsAtEpochMs: Int64((poll.endsAt.timeIntervalSince1970 * 1000).rounded()),
            nowEpochMs: Int64((now.timeIntervalSince1970 * 1000).rounded()),
            // 締切後は締切日を、締切前は今日を刷るので、その時点の時刻帯のずれを渡す。
            tzOffsetSeconds: Int32(TimeZone.current.secondsFromGMT(for: poll.isActive ? now : poll.endsAt)),
            totalVotes: poll.totalVotes.map { UInt32(clamping: $0) },
            entries: entries.map { PollCardEntryInput(entityId: $0.entityId, voteCount: UInt32(clamping: $0.voteCount)) }
        )
        let built = pollResultCard(input: input)
        items = await Self.resolveItems(
            ids: (built.podium + built.rest).map(\.entityId),
            podiumIds: Set(built.podium.map(\.entityId)),
            target: poll.targetType
        )
        card = built
    }

    /// 候補の名前と色を master から引き、表彰台の分だけ画像を読む。
    /// ImageRenderer は読み込みを待たないので、画像は UIImage にしてから渡す。
    private static func resolveItems(ids: [String], podiumIds: Set<String>, target: PollTargetType) async -> [String: PollResultShareItem] {
        var out: [String: PollResultShareItem] = [:]
        switch target {
        case .song:
            let songs = (try? await AppContainer.shared.songReading.songs(ids: ids)) ?? []
            for song in songs {
                let image = podiumIds.contains(song.id) ? await ShareCardArtwork.load(from: song.artworkUrl) : nil
                out[song.id] = PollResultShareItem(name: song.title, seed: BrandColors.hex(for: song.brandId), image: image)
            }
        case .idol:
            let idols = (try? await AppContainer.shared.idolReading.idols(ids: ids)) ?? []
            for idol in idols {
                out[idol.id] = PollResultShareItem(
                    name: idol.name, seed: idol.color,
                    image: podiumIds.contains(idol.id) ? await localImage(idol.id, kind: .idol) : nil,
                    monogram: idol.shortName)
            }
        case .unit:
            let wanted = Set(ids)
            let units = ((try? await AppContainer.shared.unitReading.allUnits()) ?? []).filter { wanted.contains($0.id) }
            for unit in units {
                out[unit.id] = PollResultShareItem(
                    name: unit.displayName, seed: BrandColors.hex(for: unit.brandId),
                    image: podiumIds.contains(unit.id) ? await localImage(unit.id, kind: .unit) : nil)
            }
        }
        return out
    }

    /// 端末に保存したアイドル・ユニットの代表画像 (無ければ nil → 判子か名前の札)。
    @MainActor
    private static func localImage(_ id: String, kind: GalleryKind) -> UIImage? {
        CustomImageService.shared.imageURL(for: id, kind: kind).flatMap { ProducerCardFiles.printImage(at: $0, maxPixels: 600) }
    }
}

extension PollTargetType {
    var cardTarget: PollCardTarget {
        switch self {
        case .song: return .song
        case .idol: return .idol
        case .unit: return .unit
        }
    }
}

/// 画像: 投票結果のポスター。骨格は `PosterShareScaffold`、中身はソートメーカーの画像と同じ組み
/// (1〜3 位の表彰台を 2 位・1 位・3 位の順に、4 位以降を 2 列)。票数は順位の下と行末に刷る。
///
/// ImageRenderer で焼く固定キャンバスなので、色は固定色だけ、文字は固定 pt。
struct PollResultShareCard: View {
    let card: PollResultCard
    let items: [String: PollResultShareItem]
    var size: ShareCard.Size = ShareCard.portrait

    private var palette: ShareCardPalette {
        ShareCardPalette(seed: card.podium.first.flatMap { items[$0.entityId]?.seed })
    }

    var body: some View {
        PosterShareScaffold(
            palette: palette,
            width: size.width, height: size.height,
            kicker: card.kicker,
            trailingKicker: card.imprint,
            title: card.title,
            titleSize: 38,
            subtitle: card.subtitle
        ) {
            VStack(alignment: .leading, spacing: 0) {
                podiumRow
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                if !card.rest.isEmpty {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                        .padding(.top, 16)
                    restGrid.padding(.top, 14)
                }
            }
        }
    }

    private func name(_ row: PollCardRow) -> String { items[row.entityId]?.name ?? "" }

    // MARK: 表彰台

    private var podiumRow: some View {
        let order = [1, 0, 2].filter { $0 < card.podium.count }
        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(order, id: \.self) { i in
                podiumSlot(card.podium[i], isFirst: i == 0)
            }
        }
    }

    private func podiumSlot(_ row: PollCardRow, isFirst: Bool) -> some View {
        let side: CGFloat = isFirst ? 148 : 112
        return VStack(spacing: 8) {
            Text("\(row.rank)")
                .font(.system(size: isFirst ? 44 : 32, weight: .black).width(.compressed).monospacedDigit())
                .foregroundStyle(row.rank == 1 ? palette.accent : .white.opacity(0.75))
            visual(row, side: side)
            Text(name(row))
                .font(.system(size: isFirst ? 15 : 12, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: side + 12, height: isFirst ? 40 : 32, alignment: .top)
            votes(row.voteCount, size: isFirst ? 26 : 20)
        }
    }

    private func votes(_ count: UInt32, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(count)")
                .font(.system(size: size, weight: .heavy).width(.compressed).monospacedDigit())
                .foregroundStyle(.white)
            Text("票")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    /// 画像は大きさの決まった枠を先に作り、上寄せで重ねて切る (縦長の写真で顔が切れにくい)。
    @ViewBuilder
    private func visual(_ row: PollCardRow, side: CGFloat) -> some View {
        let item = items[row.entityId]
        let shape = RoundedRectangle(cornerRadius: side * 0.08, style: .continuous)
        if let image = item?.image {
            Color.clear
                .frame(width: side, height: side)
                .overlay(alignment: .top) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .clipShape(shape)
        } else if let monogram = item?.monogram {
            // 画像の無いアイドルは判子 (メンバーカラーの丸に略称)。
            let palette = ShareCardPalette(seed: item?.seed)
            Circle()
                .fill(palette.accentDeep)
                .overlay(Circle().stroke(palette.accent, lineWidth: side * 0.03))
                .overlay(
                    Text(monogram)
                        .font(.system(size: side * (monogram.count >= 3 ? 0.24 : 0.32), weight: .black))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(side * 0.12)
                )
                .frame(width: side, height: side)
        } else {
            shape
                .fill(ShareCardPalette(seed: item?.seed).accentDeep)
                .frame(width: side, height: side)
                .overlay(
                    Text(name(row))
                        .font(.system(size: side * 0.12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(side * 0.1)
                )
        }
    }

    // MARK: 4 位以降

    private var restGrid: some View {
        // 縦に読めるよう左列に前半 4 件、右列に残り。
        let left = Array(card.rest.prefix(4))
        let right = Array(card.rest.dropFirst(4))
        return HStack(alignment: .top, spacing: 20) {
            column(left)
            column(right)
        }
    }

    private func column(_ rows: [PollCardRow]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(rows, id: \.entityId) { row in
                HStack(spacing: 8) {
                    Text("\(row.rank)")
                        .font(.system(size: 20, weight: .heavy).width(.compressed).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 22, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(ShareCardPalette(seed: items[row.entityId]?.seed).accent)
                        .frame(width: 3, height: 14)
                    Text(name(row))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(row.voteCount)")
                        .font(.system(size: 15, weight: .heavy).width(.compressed).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
