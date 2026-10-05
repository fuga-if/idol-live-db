import CoreImage
import CoreImage.CIFilterBuiltins
import NukeUI
import SwiftUI

// =============================================================================
// P名刺 (docs/DESIGN_SYSTEM.md §6.13)
//
// ImasProducerCard   P名刺 1 枚。担当の入場証 (`ImasPass`) を 1 枚に広げた紙。
//                    上の帯が担当の色でストラップの穴、担当の写真、名前を大きく、ひとこと、
//                    担当の行、リンクの行、下に記録の電光掲示板 (`ImasBoard`)。
//                    使わない場面: アイドル 1 人の顔 → `ImasIdolHeader` / 担当の入口 → `ImasPass`。
//                    種類: 担当の写真がある (帯の下に写真) / 無い (写真の面を出さない。担当の行の判子は必ず出す)。
//                    状態: リンク・担当は押すと開く (`onOpenLink` / `onOpenOshi`)。渡さなければ押せない。
// ImasCameraFrame    カメラの読み取り窓。面と同じ角丸で切り、縦長 (3:4) に収める。中身はカメラの View。
// ImasQRCode         QR。チケットの紙 (ダークでも明るい) に墨で刷る。誤り訂正は L (中身が長いので
//                    読み取りやすさより収まりを取る)。題 (`caption`) を下に添えられる。
// =============================================================================

// MARK: - P名刺

struct ImasProducerCard: View {
    /// 名刺に載せる担当 1 人。
    struct Oshi: Identifiable, Hashable {
        let id: String
        let name: String
        /// 判子の略称。
        let shortName: String
        var seed: String? = nil
        var brand: String? = nil
        var imageURL: URL? = nil
        /// 副題 (ブランド・CV)。
        var subtitle: String? = nil
        /// 見ている人と同じ担当 (受け取った名刺で「担当被り」を出す)。
        var isShared: Bool = false
    }

    /// 名刺に載せるリンク 1 本。
    struct Link: Identifiable, Hashable {
        var id: String { url }
        /// 種類の名前 (X・Bluesky…)。
        let label: String
        /// 右に出す値 (@handle)。
        let display: String
        let url: String
    }

    /// 帯の右の印字 (「SINCE 2014」)。
    var sinceImprint: String? = nil
    let name: String
    var message: String? = nil
    var oshi: [Oshi] = []
    var links: [Link] = []
    /// 記録の数 (参加公演・回収曲・次の現場)。空なら掲示板を出さない。
    var cells: [ImasBoard.Cell] = []
    /// 掲示板の右上の印字 (「2014 — 2026」)。
    var boardTrailing: String? = nil
    /// 帯の下に大きく出す担当の写真。
    var photoURL: URL? = nil
    var onOpenLink: ((Link) -> Void)? = nil
    var onOpenOshi: ((Oshi) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var photoHeight: CGFloat = 220

    var body: some View {
        let lead = oshi.first
        let t = ImasTheme.derive(seed: lead?.seed, brand: lead?.brand, scheme: scheme)
        let band = t.isNeutral ? DS.sys : t.accent
        let onBand = t.isNeutral ? DS.onSys : t.onAccent
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                HStack {
                    Text("PRODUCER PASS").imasText(.imprint, color: onBand.opacity(0.9))
                    Spacer(minLength: 60)
                    if let sinceImprint { Text(sinceImprint).imasText(.imprint, color: onBand.opacity(0.9)) }
                }
                .padding(.horizontal, DS.Space.card)
                Capsule().fill(DS.bg).frame(width: 44, height: 10)
                    .overlay(Capsule().strokeBorder(DS.line, lineWidth: 1))
                    .accessibilityHidden(true)
            }
            .frame(height: 44)
            .background(band)

            if let photoURL {
                LazyImage(url: photoURL) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        DS.surface2
                    }
                }
                .frame(height: photoHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityLabel(lead.map { "\($0.name)の写真" } ?? "担当の写真")
            }

            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text(name)
                    .font(.imasHeading(28, weight: .heavy))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let message, !message.isEmpty {
                    Text(message).font(.imasFootnote).foregroundStyle(DS.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DS.Space.card)
            .padding(.vertical, DS.Space.gapLoose)

            if !oshi.isEmpty {
                ImasPerforation(color: DS.perforation).padding(.horizontal, DS.Space.card)
                VStack(spacing: 0) {
                    ForEach(Array(oshi.enumerated()), id: \.element.id) { index, item in
                        oshiRow(item)
                            .environment(\.imasRowPosition, index == 0 ? .first : .following)
                    }
                }
            }

            if !links.isEmpty {
                ImasPerforation(color: DS.perforation).padding(.horizontal, DS.Space.card)
                VStack(spacing: 0) {
                    ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                        linkRow(link)
                            .environment(\.imasRowPosition, index == 0 ? .first : .following)
                    }
                }
            }

            if !cells.isEmpty {
                ImasBoard(title: "RECORD", trailing: boardTrailing, cells: cells)
                    .padding(DS.Space.gapLoose)
            }
        }
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .imasSurfaceEdge(cornerRadius: DS.rCard)
    }

    @ViewBuilder
    private func oshiRow(_ item: Oshi) -> some View {
        let row = ImasRow(
            title: item.name,
            subtitle: item.subtitle,
            leading: .avatar(label: item.shortName, seed: item.seed, brand: item.brand,
                             imageURL: item.imageURL, isPick: true),
            trailing: item.isShared ? .badge(ImasBadge(text: "担当被り", kind: .new)) : .badge(ImasBadge(text: "担当", kind: .lead)),
            density: .compact
        )
        if let onOpenOshi {
            Button { onOpenOshi(item) } label: { row }.buttonStyle(.imasRow)
        } else {
            row
        }
    }

    @ViewBuilder
    private func linkRow(_ link: Link) -> some View {
        let row = ImasValueRow(key: link.label, value: link.display, isLink: onOpenLink != nil)
        if let onOpenLink {
            Button { onOpenLink(link) } label: { row }
                .buttonStyle(.imasRow)
                .accessibilityHint("開く")
        } else {
            row
        }
    }
}

// MARK: - QR

/// QR。チケットの紙に墨で刷る (ダークでも明るい紙なので、どの端末のカメラでも読める)。
struct ImasQRCode: View {
    let text: String
    var caption: String? = nil

    @State private var image: UIImage?
    @State private var renderedText: String?

    var body: some View {
        VStack(spacing: DS.Space.gapLoose) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(DS.ticketInk)
                } else {
                    DS.ticket
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel("名刺の QR コード")
            if let caption {
                Text(caption)
                    .font(.imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.ticketSub)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DS.Space.section)
        .frame(maxWidth: .infinity)
        .background(DS.ticket, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .imasSurfaceEdge(cornerRadius: DS.rCard)
        .task(id: text) {
            guard renderedText != text else { return }
            image = Self.render(text)
            renderedText = text
        }
    }

    private static let context = CIContext()

    /// 模様の所だけが不透明な画像にする (色は `foregroundStyle` で墨に塗る)。
    static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        let invert = CIFilter.colorInvert()
        invert.inputImage = output
        let mask = CIFilter.maskToAlpha()
        mask.inputImage = invert.outputImage
        guard let masked = mask.outputImage,
              let cg = context.createCGImage(masked, from: masked.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - カメラの窓

/// カメラの読み取り窓。面と同じ角丸で切り、縦長 (3:4) に収める。
struct ImasCameraFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .aspectRatio(3 / 4, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(DS.board)
            .clipShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
            .imasSurfaceEdge(cornerRadius: DS.rCard)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("カメラ")
    }
}
