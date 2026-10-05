import CoreImage
import CoreImage.CIFilterBuiltins
import NukeUI
import SwiftUI

// =============================================================================
// P名刺 (docs/DESIGN_SYSTEM.md §6.13)
//
// ImasProducerCard   P名刺 1 枚。担当の入場証 (`ImasPass`) を 1 枚に広げた紙。
//                    上の帯が担当の色でストラップの穴、担当の写真、名前を大きく (選んだ書体で)、ひとこと、
//                    担当の行、リンクの行、下に記録の電光掲示板 (`ImasBoard`)。
//                    使わない場面: アイドル 1 人の顔 → `ImasIdolHeader` / 担当の入口 → `ImasPass`。
//                    種類: 担当の写真がある (帯の下に写真) / 無い (写真の面を出さない。担当の行の判子は必ず出す)。
//                          名刺の写真がある (名前の横に証明写真の枠) / 無い (枠を出さない)。
//                    状態: リンク・担当は押すと開く (`onOpenLink` / `onOpenOshi`)。渡さなければ押せない。
// ImasCardPortrait   名刺の写真の証明写真の枠 (3:4)。名刺・名刺入れの行・編集画面で同じ枠。
// ImasPortraitCropper 名刺の写真を枠に合わせて指で動かす・広げる (切り抜きの位置と拡大)。
// ImasNameFontPicker 名前の書体の見本を横に並べ、引いて (または押して) 選ぶ。
// ImasCornerAdjuster 写真に写った紙の名刺の四隅を指で直す (書類カメラの手直しと同じ感覚)。
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
    /// 名刺の写真 (自分で選んだ写真。名前の横の証明写真の枠に出す)。
    var portraitURL: URL? = nil
    /// 名前の書体の PostScript 名 (コアの `CardNameFontInfo.postscriptName`)。nil は見出しの書体。
    var nameFont: String? = nil
    var onOpenLink: ((Link) -> Void)? = nil
    var onOpenOshi: ((Oshi) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var photoHeight: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var portraitWidth: CGFloat = 84

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

            HStack(alignment: .top, spacing: DS.Space.gapLoose) {
                VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                    Text(name)
                        .font(.imasCardName(nameFont, size: 28))
                        .foregroundStyle(DS.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if let message, !message.isEmpty {
                        Text(message).font(.imasFootnote).foregroundStyle(DS.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let portraitURL {
                    ImasCardPortrait(url: portraitURL, label: "\(name)の写真")
                        .frame(width: portraitWidth)
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

// MARK: - 四隅の手直し

/// 写真に写った紙の名刺の四隅を指で直す。写真は枠に収めて出し、四隅に丸い取っ手、
/// 四隅を結ぶ線を重ねる。`corners` は左上・右上・右下・左下の順、写真の中の 0〜1 (左上が原点)。
struct ImasCornerAdjuster: View {
    let image: UIImage
    @Binding var corners: [CGPoint]

    @State private var dragStart: [Int: CGPoint] = [:]
    @ScaledMetric(relativeTo: .body) private var handle: CGFloat = 28

    private static let names = ["左上", "右上", "右下", "左下"]

    var body: some View {
        GeometryReader { geo in
            let fit = fittedRect(in: geo.size)
            let points = corners.map { CGPoint(x: fit.minX + $0.x * fit.width, y: fit.minY + $0.y * fit.height) }
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .offset(x: fit.minX, y: fit.minY)
                    .accessibilityHidden(true)
                if points.count == 4 {
                    Path { path in
                        path.addLines(points)
                        path.closeSubpath()
                    }
                    .stroke(DS.sys, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .allowsHitTesting(false)
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(DS.surface)
                            .overlay(Circle().strokeBorder(DS.sys, lineWidth: 2))
                            .frame(width: handle, height: handle)
                            .position(points[index])
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let start = dragStart[index] ?? corners[index]
                                        dragStart[index] = start
                                        guard fit.width > 0, fit.height > 0 else { return }
                                        corners[index] = CGPoint(
                                            x: min(max(start.x + value.translation.width / fit.width, 0), 1),
                                            y: min(max(start.y + value.translation.height / fit.height, 0), 1))
                                    }
                                    .onEnded { _ in dragStart[index] = nil }
                            )
                            .accessibilityElement()
                            .accessibilityLabel("\(Self.names[index])の角")
                            .accessibilityAdjustableAction { direction in
                                // 読み上げでは、角を写真の真ん中へ寄せる・外へ広げるで直す。
                                let step: CGFloat = direction == .increment ? -0.02 : 0.02
                                let p = corners[index]
                                corners[index] = CGPoint(x: min(max(p.x + (p.x < 0.5 ? step : -step), 0), 1),
                                                         y: min(max(p.y + (p.y < 0.5 ? step : -step), 0), 1))
                            }
                    }
                }
            }
        }
        .aspectRatio(max(image.size.width, 1) / max(image.size.height, 1), contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        let w = max(image.size.width, 1), h = max(image.size.height, 1)
        let scale = min(size.width / w, size.height / h)
        let fitted = CGSize(width: w * scale, height: h * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
                      width: fitted.width, height: fitted.height)
    }
}

// MARK: - QR

// MARK: - 名刺の写真

/// 名刺の写真の証明写真の枠 (3:4)。紙に貼った写真のように、角を小さく丸めて縁を付ける。
struct ImasCardPortrait: View {
    let url: URL?
    var label: String = "名刺の写真"

    var body: some View {
        Group {
            if let url {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        DS.surface2
                    }
                }
            } else {
                DS.surface2
            }
        }
        .aspectRatio(ImasPortraitCrop.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
        .imasSurfaceEdge(cornerRadius: DS.rTag)
        .accessibilityLabel(label)
    }
}

/// 名刺の写真の切り抜き。`zoom` は枠いっぱいに収めた大きさからの拡大 (1 以上)、
/// `center` は元の写真の中で枠の真ん中に来る点 (0〜1、左上が原点)。
struct ImasPortraitCrop: Codable, Equatable, Sendable {
    /// 枠の縦横比 (横 / 縦)。証明写真の 3:4。
    static let aspect: CGFloat = 3.0 / 4.0
    static let maxZoom: CGFloat = 5
    /// 書き出す大きさ (px)。
    static let outputSize = CGSize(width: 900, height: 1200)

    var zoom: CGFloat = 1
    var center = CGPoint(x: 0.5, y: 0.5)

    /// 元の写真 (px) の中で切り抜く四角。
    func rect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let baseW = min(size.width, size.height * Self.aspect)
        let w = baseW / max(1, min(zoom, Self.maxZoom))
        let h = w / Self.aspect
        let cx = min(max(center.x * size.width, w / 2), size.width - w / 2)
        let cy = min(max(center.y * size.height, h / 2), size.height - h / 2)
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// 枠からはみ出さないように直した切り抜き。
    func clamped(to size: CGSize) -> ImasPortraitCrop {
        let r = rect(in: size)
        guard size.width > 0, size.height > 0 else { return self }
        return ImasPortraitCrop(zoom: min(max(zoom, 1), Self.maxZoom),
                                center: CGPoint(x: r.midX / size.width, y: r.midY / size.height))
    }

    /// 切り抜いた写真 (900×1200px)。
    func render(_ image: UIImage) -> UIImage? {
        let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let r = rect(in: px)
        guard r.width > 0 else { return nil }
        let k = Self.outputSize.width / r.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: Self.outputSize, format: format).image { _ in
            image.draw(in: CGRect(x: -r.minX * k, y: -r.minY * k, width: px.width * k, height: px.height * k))
        }
    }
}

/// 名刺の写真を枠に合わせる。引いて動かし、つまんで広げる。枠の外は暗く沈めず、そのまま切る。
struct ImasPortraitCropper: View {
    let image: UIImage
    @Binding var crop: ImasPortraitCrop

    @State private var dragStart: ImasPortraitCrop?
    @State private var zoomStart: ImasPortraitCrop?
    @ScaledMetric(relativeTo: .body) private var maxWidth: CGFloat = 260

    private var pixelSize: CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    var body: some View {
        GeometryReader { geo in
            let frame = geo.size
            let r = crop.rect(in: pixelSize)
            let s = r.width > 0 ? frame.width / r.width : 1
            Image(uiImage: image)
                .resizable()
                .frame(width: pixelSize.width * s, height: pixelSize.height * s)
                .offset(x: -r.minX * s, y: -r.minY * s)
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let start = dragStart ?? crop
                            dragStart = start
                            let startRect = start.rect(in: pixelSize)
                            let scale = startRect.width > 0 ? frame.width / startRect.width : 1
                            var next = start
                            next.center = CGPoint(
                                x: (startRect.midX - value.translation.width / scale) / pixelSize.width,
                                y: (startRect.midY - value.translation.height / scale) / pixelSize.height)
                            crop = next.clamped(to: pixelSize)
                        }
                        .onEnded { _ in dragStart = nil }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { value in
                                let start = zoomStart ?? crop
                                zoomStart = start
                                var next = start
                                next.zoom = start.zoom * value.magnification
                                crop = next.clamped(to: pixelSize)
                            }
                            .onEnded { _ in zoomStart = nil })
                )
        }
        .aspectRatio(ImasPortraitCrop.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.rInner, style: .continuous))
        .imasSurfaceEdge(cornerRadius: DS.rInner)
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("名刺の写真の位置")
        .accessibilityHint("引いて動かし、2 本の指で広げます")
        .accessibilityAdjustableAction { direction in
            var next = crop
            next.zoom += direction == .increment ? 0.25 : -0.25
            crop = next.clamped(to: pixelSize)
        }
    }
}

// MARK: - 名前の書体

/// 名前の書体の見本を横に並べる。引くと真ん中に来た書体を選び、押してもその書体を選ぶ。
/// 見本は紙の札 (地は紙のまま)。選んだ札は墨の太い縁と ✓。
struct ImasNameFontPicker: View {
    struct Option: Identifiable, Hashable {
        /// 保存のキー (`gothic`)。
        let id: String
        /// 書体の名前 (「明朝」)。
        let label: String
        /// PostScript 名。
        let postScriptName: String
    }

    let options: [Option]
    @Binding var selection: String
    /// 見本に組む名前。
    let sample: String

    @State private var scrolled: String?
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 176

    var body: some View {
        GeometryReader { geo in
            let inset = max(0, (geo.size.width - tileWidth) / 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.gap) {
                    ForEach(options) { option in
                        tile(option)
                            .frame(width: tileWidth)
                            .id(option.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolled, anchor: .center)
        }
        .frame(height: tileHeight)
        .onAppear { scrolled = selection }
        .onChange(of: scrolled) { _, new in
            if let new, new != selection { selection = new }
        }
        .onChange(of: selection) { _, new in
            if scrolled != new { withAnimation(.imasStandard) { scrolled = new } }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("名前の書体")
    }

    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 92

    private func tile(_ option: Option) -> some View {
        let on = option.id == selection
        return Button {
            withAnimation(.imasStandard) { selection = option.id }
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text(sample.isEmpty ? "ふがP" : sample)
                    .font(.imasCardName(option.postScriptName, size: 24))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: DS.Space.gapTight) {
                    Text(option.label).imasText(.rowLabel, color: on ? DS.ink : DS.ink2)
                    Spacer(minLength: 0)
                    ImasSelectionMark(isSelected: on, isSingle: true)
                }
            }
            .padding(DS.Space.card)
            .frame(maxHeight: .infinity)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rInner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rInner, style: .continuous)
                    .strokeBorder(on ? DS.ink : DS.line, lineWidth: on ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - QR

/// QR。チケットの紙に墨で刷る (ダークでも明るい紙なので、どの端末のカメラでも読める)。
struct ImasQRCode: View {
    let text: String
    var caption: String? = nil
    /// 読み上げの名前 (「名刺の QR コード」「自分の QR コード」)。
    var label: String = "名刺の QR コード"

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
            .accessibilityLabel(label)
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
