import CoreImage
import CoreImage.CIFilterBuiltins
import NukeUI
import SwiftUI

// =============================================================================
// P名刺 (docs/DESIGN_SYSTEM.md §6.13)
//
// ImasProducerCard   P名刺 1 枚。名刺そのものは 91:55 の横長の紙 1 枚 (紙に刷る画像の表・裏と同じ組み、
//                    `ImasMeishiFront` / `ImasMeishiBack`)。押すと裏返って裏 (QR・参加公演数・回収曲数・日付)。
//                    デザイン (`design`) は 4 つと自作の画像 (一覧・既定・書体はコアの `cardDesigns`)。
//                    - 担当を大きく (oshi): 左半分に担当の画像を大きく (`heroOshi` の順。無い担当は大きな判子)。
//                    表に載せるのは名前・P歴・名刺の写真・担当 (判子か写真をブランドごとにまとめる)・ハンドル 1 つ
//                    (載せる担当・まとめ方・判子の下の文言・ハンドルはコアの `producerCardFace`)。
//                    - 自作の画像 (face): 表は自分で作った名刺の画像。裏は裏の画像 (無ければ QR の裏)。
//                      画像が手元に無い名刺は入場証で描く (コアが決める)。
//                    名刺に収まらないもの (ひとこと・担当の一覧・リンクの一覧・記録の掲示板) は
//                    `details` (`ImasProducerCardDetails`) で名刺の下の紙面に並べる。記録の掲示板は
//                    受け取った名刺だけ (自分の名刺は `cells` を渡さない。自分の記録は P名刺の画像で見せる)。
//                    使わない場面: アイドル 1 人の顔 → `ImasIdolHeader` / 担当の入口 → `ImasPass`。
//                    状態: 裏返せる (`isFlippable`、編集画面の固定の見本は返さない)。リンク・担当は
//                          `onOpenLink` / `onOpenOshi` を渡すと詳細の行が押せる。
// ImasProducerCardDetails 名刺の下の紙面 (ひとこと・担当の写真と一覧・リンクの一覧・記録の掲示板)。
// ImasCardFace       自作の名刺の画像の小さな見本 (91:55 の枠に収める。名刺入れの行・デザインの札・編集画面)。
// ImasCardPortrait   名刺の写真の枠 (正方形。X のアイコンは丸)。
//                    名刺入れの行・編集画面で同じ枠。
// ImasPortraitCropper 名刺の写真を枠に合わせて指で動かす・広げる (切り抜きの位置と拡大)。
// ImasCardDesignPicker 名刺のデザインの見本 (小さな名刺) を横に並べ、引いて (または押して) 選ぶ。
// ImasCornerAdjuster 写真に写った紙の名刺の四隅を指で直す (書類カメラの手直しと同じ感覚)。
// ImasCameraFrame    カメラの読み取り窓。面と同じ角丸で切り、縦長 (3:4) に収める。中身はカメラの View。
// ImasQRCode         QR。チケットの紙 (ダークでも明るい) に墨で刷る。誤り訂正は L (中身が長いので
//                    読み取りやすさより収まりを取る)。題 (`caption`) を下に添えられる。
// =============================================================================

// MARK: - P名刺

struct ImasProducerCard: View {
    /// 名刺のデザイン (一覧・既定・書体はコアの `cardDesigns`)。表に載せるものは同じで、組みと線と書体が変わる。
    enum Design: Equatable {
        /// 入場証。左に担当色の縦の帯。
        case pass
        /// かしこまった名刺。紙のまま、担当色は名前の上の細い罫と判子だけ。
        case formal
        /// ポップ。墨の太い枠と担当色の太い帯、名前の下の太い線。
        case pop
        /// 担当を大きく。左半分に担当の画像を大きく、右に名前・P歴・ハンドル。
        case oshi
        /// 自作の画像。表は自分で作った名刺の画像、裏は裏の画像 (無ければ QR の裏)。
        case face(front: URL, back: URL?)
    }

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

    /// 名刺の表で 1 つのブランドにまとめて並べる担当 (コアの `CardFaceOshiGroup`)。
    struct FaceGroup: Hashable {
        /// ブランドの略称 (「765AS」)。`faceCaption` が無いときだけ判子の下に刷る。
        let label: String
        let oshi: [Oshi]
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

    /// 名刺の裏 (紙に刷る裏と同じ: QR・参加公演数・回収曲数・日付)。
    struct Back: Equatable {
        /// QR にする中身 (交換用の名刺の URL か、自分の QR の URL)。
        let qr: String
        /// QR の読み上げ (「交換用の QR コード」)。
        var qrLabel: String = "交換用の QR コード"
        /// QR の横の案内。
        var note: String = "読み取るとアプリの名刺入れに入ります。アプリが無ければ Web で開きます。"
        var showCount: UInt32? = nil
        var songCount: UInt32? = nil
        /// 「2026.10.06 時点」。
        let issuedLabel: String
    }

    var design: Design = .pass
    /// 印字の P 歴 (「SINCE 2014」)。
    var sinceImprint: String? = nil
    let name: String
    var message: String? = nil
    /// 担当の全員 (名刺の下の担当の一覧)。
    var oshi: [Oshi] = []
    /// 名刺の表に並べる担当のブランドごとのまとまり (コアの `producerCardFace`)。
    var faceGroups: [FaceGroup] = []
    /// 名刺の表の判子の下の 1 行 (「星井美希 担当」)。nil ならまとまりごとにブランドの略称を刷る。
    var faceCaption: String? = nil
    /// 担当を大きく並べる順 (担当を大きく のデザイン。コアの `CardFace.heroIdolIds`)。
    var heroOshi: [Oshi] = []
    /// 表で数で畳んだ担当の人数。
    var moreOshi: Int = 0
    /// 表に刷るハンドル 1 つ。
    var handle: String? = nil
    var links: [Link] = []
    /// 記録の数 (参加公演・回収曲・次の現場)。空なら掲示板を出さない。
    var cells: [ImasBoard.Cell] = []
    /// 掲示板の右上の印字 (「2014 — 2026」)。
    var boardTrailing: String? = nil
    /// 担当の写真 (名刺の下の担当の一覧の上に広げる)。
    var photoURL: URL? = nil
    /// 名刺の写真 (自分で選んだ写真か X のアイコン。表の右の正方形の枠に出す)。
    var portraitURL: URL? = nil
    /// 名刺の写真を丸く切る (X のアイコン。切り方はコアの `cardPhotoShape`)。
    var portraitRound = false
    /// 名前の書体の PostScript 名 (コアの `CardDesignInfo.font.postscriptName`)。nil は見出しの書体。
    var nameFont: String? = nil
    /// 裏。nil なら返さない (自作の画像に裏の画像があればそれを裏にする)。
    var back: Back? = nil
    /// 押して裏返せる (編集画面の固定の見本は返さない)。
    var isFlippable = true
    var onOpenLink: ((Link) -> Void)? = nil
    var onOpenOshi: ((Oshi) -> Void)? = nil

    /// 名刺の幅の上限 (広い画面で紙が大きくなりすぎないように)。
    static let maxWidth: CGFloat = 480

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingBack = false
    @State private var qrImage: UIImage?

    /// 名刺の下の紙面 (ひとこと・担当・リンク・記録)。
    var details: ImasProducerCardDetails { ImasProducerCardDetails(card: self) }

    private var ink: ImasMeishiInk {
        ImasMeishiInk.screen(seed: oshi.first?.seed, brand: oshi.first?.brand)
    }

    /// 裏があるか (自作の画像の裏、または QR の裏)。
    private var hasBack: Bool {
        if case let .face(_, faceBack) = design, faceBack != nil { return true }
        return back != nil
    }

    var body: some View {
        let flipped = showingBack && hasBack && isFlippable
        VStack(spacing: DS.Space.gap) {
            GeometryReader { geo in
                let scale = geo.size.width / ImasMeishi.canvas.width
                // 角丸の切り抜きと縁は面ごとに付けて、面と一緒に回す (外に付けると回る途中で枠だけ残る)。
                ZStack {
                    paperEdge(front(scale: scale)).opacity(flipped ? 0 : 1)
                    if hasBack {
                        paperEdge(backSide(scale: scale))
                            .opacity(flipped ? 1 : 0)
                            .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    }
                }
                .rotation3DEffect(.degrees(flipped && !reduceMotion ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            }
            .aspectRatio(ImasMeishi.aspect, contentMode: .fit)
            .frame(maxWidth: Self.maxWidth)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { flip() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(flipped ? backLabel : frontLabel)
            .accessibilityAddTraits(canFlip ? [.isImage, .isButton] : .isImage)
            .accessibilityHint(canFlip ? (flipped ? "押すと表を見せます" : "押すと裏を見せます") : "")
            .accessibilityAction { flip() }
            if canFlip {
                HStack(spacing: DS.Space.gap) {
                    Text("表").imasText(.imprint, color: flipped ? DS.ink3 : DS.ink)
                    Text("裏").imasText(.imprint, color: flipped ? DS.ink : DS.ink3)
                }
                .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: showingBack)
        #if DEBUG
        .onAppear {
            // シミュレータでの見た目確認 (PRODUCER_CARD_BACK=1 で裏から見せる)。
            if ProcessInfo.processInfo.environment["PRODUCER_CARD_BACK"] == "1" { showingBack = true }
        }
        #endif
        .task(id: canFlip ? back?.qr : nil) {
            // 返せない名刺 (編集画面の見本) は裏を出さないので QR を描かない。
            qrImage = canFlip ? back.flatMap { ImasQRCode.render($0.qr) } : nil
        }
    }

    /// 紙の角丸と縁 (面ごとに付けて、裏返るときに面と一緒に回す)。
    private func paperEdge(_ side: some View) -> some View {
        side
            .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
            .imasSurfaceEdge(cornerRadius: DS.rTag)
    }

    private var canFlip: Bool { isFlippable && hasBack }

    private func flip() {
        guard canFlip else { return }
        withAnimation(.imasStandard) { showingBack.toggle() }
    }

    // MARK: 表・裏

    @ViewBuilder
    private func front(scale: CGFloat) -> some View {
        switch design {
        case let .face(url, _):
            imageSide(url, scale: scale)
        case .pass, .formal, .pop, .oshi:
            ImasMeishiFront(
                look: look,
                name: name,
                sinceImprint: sinceImprint,
                oshiGroups: faceGroups.map { group in
                    ImasMeishiOshiGroup(label: group.label, oshi: group.oshi.map(meishiOshi))
                },
                hero: heroOshi.map(meishiOshi),
                oshiCaption: faceCaption,
                moreOshi: moreOshi,
                handle: handle,
                nameFont: nameFont,
                portrait: portraitURL.map { .url($0) },
                portraitRound: portraitRound,
                ink: ink,
                scale: scale
            )
        }
    }

    private var look: ImasMeishiFront.Look {
        switch design {
        case .formal: return .formal
        case .pop: return .pop
        case .oshi: return .oshi
        case .pass, .face: return .pass
        }
    }

    /// 名刺の紙に刷る担当 1 人 (判子の色は明るい紙の上の担当色)。
    private func meishiOshi(_ item: Oshi) -> ImasMeishiOshi {
        let theme = ImasTheme.derive(seed: item.seed, brand: item.brand, scheme: .light)
        return ImasMeishiOshi(id: item.id, name: item.name, shortName: item.shortName,
                              color: theme.isNeutral ? DS.ticketInk : theme.accent,
                              picture: item.imageURL.map { .url($0) })
    }

    @ViewBuilder
    private func backSide(scale: CGFloat) -> some View {
        if case let .face(_, faceBack?) = design {
            imageSide(faceBack, scale: scale)
        } else if let back {
            ImasMeishiBack(qr: qrImage, note: back.note, showCount: back.showCount, songCount: back.songCount,
                           issuedLabel: back.issuedLabel, ink: ink, scale: scale)
        }
    }

    /// 自作の名刺の画像。紙の大きさの枠を先に作り、画像は比率のまま切らずに収める (余りは紙の色)。
    private func imageSide(_ url: URL, scale: CGFloat) -> some View {
        ink.paper
            .frame(width: ImasMeishi.canvas.width * scale, height: ImasMeishi.canvas.height * scale)
            .overlay { ImasMeishiPictureView(picture: .url(url), contentMode: .fit, fallback: ink.paper) }
            .clipped()
    }

    // MARK: 読み上げ

    private var frontLabel: String {
        if case .face = design { return "\(name)の名刺の画像" }
        var parts = ["\(name)の名刺"]
        if let sinceImprint { parts.append(sinceImprint) }
        if !faceGroups.isEmpty {
            // 読み上げはブランドごとに「765AS 星井美希」(1 ブランドなら名前だけ)。
            let names = faceGroups.map { group in
                let members = group.oshi.map(\.name).joined(separator: "、")
                return faceGroups.count > 1 && !group.label.isEmpty ? "\(group.label) \(members)" : members
            }.joined(separator: "、")
            parts.append(moreOshi > 0 ? "担当 \(names) ほか\(moreOshi)人" : "担当 \(names)")
        }
        if let handle { parts.append(handle) }
        if portraitURL != nil { parts.append("写真あり") }
        return parts.joined(separator: "。")
    }

    private var backLabel: String {
        if case .face(_, _?) = design { return "\(name)の名刺の画像の裏" }
        guard let back else { return "\(name)の名刺の裏" }
        var parts = ["\(name)の名刺の裏", back.qrLabel]
        if let shows = back.showCount { parts.append("参加公演 \(shows)") }
        if let songs = back.songCount { parts.append("回収曲 \(songs)") }
        if !back.issuedLabel.isEmpty { parts.append(back.issuedLabel) }
        return parts.joined(separator: "。")
    }
}

// MARK: - 名刺の下の紙面

/// 名刺に収まらない詳細を名刺の下に並べる: ひとこと・担当 (担当の写真と一覧)・リンクの一覧・記録の掲示板。
/// 自分の名刺・受け取った名刺・受け取りの確認で同じ組み。
struct ImasProducerCardDetails: View {
    let card: ImasProducerCard

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.section) {
            if let message = card.message, !message.isEmpty {
                ImasSection("ひとこと", style: .small) {
                    ImasCard {
                        Text(message).imasText(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !card.oshi.isEmpty {
                ImasSection("担当", style: .small) {
                    ImasCardList {
                        if let photoURL = card.photoURL { oshiPhoto(photoURL) }
                        ForEach(Array(card.oshi.enumerated()), id: \.element.id) { index, item in
                            oshiRow(item)
                                .environment(\.imasRowPosition, index == 0 && card.photoURL == nil ? .first : .following)
                        }
                    }
                }
            }
            if !card.links.isEmpty {
                ImasSection("リンク", style: .small) {
                    ImasCardList {
                        ForEach(Array(card.links.enumerated()), id: \.element.id) { index, link in
                            linkRow(link)
                                .environment(\.imasRowPosition, index == 0 ? .first : .following)
                        }
                    }
                }
            }
            if !card.cells.isEmpty {
                ImasBoard(title: "RECORD", trailing: card.boardTrailing, cells: card.cells)
            }
        }
    }

    /// 担当の写真の帯。写真は枠いっぱいに広げて枠で切る。`scaledToFill` の画像に後から高さを
    /// 付けると、画像は元の比率の大きさのまま描かれて下の行に被さる (実機の縦長の写真で起きた)。
    /// 先に大きさの決まった枠を作り、その上に画像を重ねてから切る。
    private func oshiPhoto(_ url: URL) -> some View {
        Color.clear
            .aspectRatio(ImasMeishi.aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { ImasMeishiPictureView(picture: .url(url)) }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(card.oshi.first.map { "\($0.name)の写真" } ?? "担当の写真")
    }

    @ViewBuilder
    private func oshiRow(_ item: ImasProducerCard.Oshi) -> some View {
        let row = ImasRow(
            title: item.name,
            subtitle: item.subtitle,
            leading: .avatar(label: item.shortName, seed: item.seed, brand: item.brand,
                             imageURL: item.imageURL, isPick: true),
            trailing: item.isShared ? .badge(ImasBadge(text: "担当被り", kind: .new)) : .badge(ImasBadge(text: "担当", kind: .lead)),
            density: .compact
        )
        if let onOpenOshi = card.onOpenOshi {
            Button { onOpenOshi(item) } label: { row }.buttonStyle(.imasRow)
        } else {
            row
        }
    }

    @ViewBuilder
    private func linkRow(_ link: ImasProducerCard.Link) -> some View {
        let row = ImasValueRow(key: link.label, value: link.display, isLink: card.onOpenLink != nil)
        if let onOpenLink = card.onOpenLink {
            Button { onOpenLink(link) } label: { row }
                .buttonStyle(.imasRow)
                .accessibilityHint("開く")
        } else {
            row
        }
    }
}

// MARK: - 自作の名刺の画像

/// 自作の名刺の画像の小さな見本 (91:55 の枠に収める。比率の違う画像も切らずに収める)。
/// 名刺入れの行の先頭・デザインの札・編集画面。名刺そのものは `ImasProducerCard` の `.face`。
struct ImasCardFace: View {
    let front: URL
    var label: String = "名刺の画像"

    /// 日本の名刺の比 (91:55)。
    static var aspect: CGFloat { ImasMeishi.aspect }

    var body: some View {
        Color.clear
            .aspectRatio(Self.aspect, contentMode: .fit)
            .overlay { ImasMeishiPictureView(picture: .url(front), contentMode: .fit) }
            .background(DS.surface2)
            .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
            .imasSurfaceEdge(cornerRadius: DS.rTag)
            .accessibilityElement()
            .accessibilityLabel(label)
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

/// 名刺の写真の枠。P名刺は正方形 (`.card`)。3:4 (`.resume`) は前の版の切り抜きの比。
/// 紙に貼った写真のように角を小さく丸めて縁を付ける。X のアイコン (`round`) は X と同じく丸く切り、
/// 3:4 の枠ではその中に丸く置く。
struct ImasCardPortrait: View {
    let url: URL?
    var label: String = "名刺の写真"
    var frame: ImasPortraitCrop.Frame = .card
    /// 丸く切る (X のアイコン。切り方はコアの `cardPhotoShape`)。
    var round = false

    var body: some View {
        // 大きさは枠の比で決め、写真はその上に重ねて切る (画像の大きさで枠が膨らまないように)。
        Color.clear
            .aspectRatio(frame.aspect, contentMode: .fit)
            .overlay {
                if round {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { picture }
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(DS.line, lineWidth: 1))
                } else {
                    picture
                        .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
                        .imasSurfaceEdge(cornerRadius: DS.rTag)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
    }

    @ViewBuilder private var picture: some View {
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
}

/// 名刺の写真の切り抜き。`zoom` は枠いっぱいに収めた大きさからの拡大 (1 以上)、
/// `center` は元の写真の中で枠の真ん中に来る点 (0〜1、左上が原点)。枠の形 (`Frame`) は持たないので、
/// 前の 3:4 の切り抜きも正方形の枠で真ん中を保ったまま読み替えられる。
struct ImasPortraitCrop: Codable, Equatable, Sendable {
    /// 切り抜く枠。
    enum Frame: Sendable {
        /// P名刺の写真 (正方形。X のアイコンはこの枠に内接する丸で出す)。
        case card
        /// 3:4 (前の版の P名刺の写真・履歴書の様式の証明写真の欄の比。前の切り抜きの読み替えを確かめるのに使う)。
        case resume

        /// 枠の縦横比 (横 / 縦)。
        var aspect: CGFloat {
            switch self {
            case .card: return 1
            case .resume: return 3.0 / 4.0
            }
        }

        /// 書き出す大きさ (px)。
        var outputSize: CGSize {
            switch self {
            case .card: return CGSize(width: 1080, height: 1080)
            case .resume: return CGSize(width: 900, height: 1200)
            }
        }
    }

    static let maxZoom: CGFloat = 5

    var zoom: CGFloat = 1
    var center = CGPoint(x: 0.5, y: 0.5)

    /// 元の写真 (px) の中で切り抜く四角。
    func rect(in size: CGSize, frame: Frame) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let baseW = min(size.width, size.height * frame.aspect)
        let w = baseW / max(1, min(zoom, Self.maxZoom))
        let h = w / frame.aspect
        let cx = min(max(center.x * size.width, w / 2), size.width - w / 2)
        let cy = min(max(center.y * size.height, h / 2), size.height - h / 2)
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// 枠からはみ出さないように直した切り抜き。
    func clamped(to size: CGSize, frame: Frame) -> ImasPortraitCrop {
        let r = rect(in: size, frame: frame)
        guard size.width > 0, size.height > 0 else { return self }
        return ImasPortraitCrop(zoom: min(max(zoom, 1), Self.maxZoom),
                                center: CGPoint(x: r.midX / size.width, y: r.midY / size.height))
    }

    /// 切り抜いた写真 (`frame.outputSize`)。
    func render(_ image: UIImage, frame: Frame) -> UIImage? {
        let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let r = rect(in: px, frame: frame)
        guard r.width > 0 else { return nil }
        let k = frame.outputSize.width / r.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: frame.outputSize, format: format).image { _ in
            image.draw(in: CGRect(x: -r.minX * k, y: -r.minY * k, width: px.width * k, height: px.height * k))
        }
    }
}

/// 名刺の写真を枠に合わせる。引いて動かし、つまんで広げる。枠の外は暗く沈めず、そのまま切る。
struct ImasPortraitCropper: View {
    let image: UIImage
    @Binding var crop: ImasPortraitCrop
    var frame: ImasPortraitCrop.Frame = .card
    /// 丸く切る写真 (X のアイコン。枠は正方形で渡す) は、枠に内接する丸で見せる (切り抜きそのものは枠の四角)。
    var round = false

    @State private var dragStart: ImasPortraitCrop?
    @State private var zoomStart: ImasPortraitCrop?
    @ScaledMetric(relativeTo: .body) private var maxWidth: CGFloat = 260

    private var pixelSize: CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    var body: some View {
        GeometryReader { geo in
            let frame = geo.size
            let r = crop.rect(in: pixelSize, frame: self.frame)
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
                            let startRect = start.rect(in: pixelSize, frame: self.frame)
                            let scale = startRect.width > 0 ? frame.width / startRect.width : 1
                            var next = start
                            next.center = CGPoint(
                                x: (startRect.midX - value.translation.width / scale) / pixelSize.width,
                                y: (startRect.midY - value.translation.height / scale) / pixelSize.height)
                            crop = next.clamped(to: pixelSize, frame: self.frame)
                        }
                        .onEnded { _ in dragStart = nil }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { value in
                                let start = zoomStart ?? crop
                                zoomStart = start
                                var next = start
                                next.zoom = start.zoom * value.magnification
                                crop = next.clamped(to: pixelSize, frame: self.frame)
                            }
                            .onEnded { _ in zoomStart = nil })
                )
        }
        .aspectRatio(frame.aspect, contentMode: .fit)
        // 丸は正方形の枠の角を半分まで丸めたもの (角の丸めは辺の半分で止まる)。
        .clipShape(RoundedRectangle(cornerRadius: round ? maxWidth : DS.rInner, style: round ? .circular : .continuous))
        .imasSurfaceEdge(cornerRadius: round ? maxWidth : DS.rInner)
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("名刺の写真の位置")
        .accessibilityHint("引いて動かし、2 本の指で広げます")
        .accessibilityAdjustableAction { direction in
            var next = crop
            next.zoom += direction == .increment ? 0.25 : -0.25
            crop = next.clamped(to: pixelSize, frame: frame)
        }
    }
}

// MARK: - 名刺のデザイン

/// 名刺のデザインの見本を横に並べる。引くと真ん中に来たデザインを選び、押してもそのデザインを選ぶ。
/// 見本は紙の札 (地は紙のまま) に、そのデザインの小さな名刺 (帯・罫・枠と書体) を組む。
/// 選んだ札は墨の太い縁と ✓。自作の画像の札は、選んだ画像 (まだ無ければ画像を選ぶ案内) を出す。
struct ImasCardDesignPicker: View {
    struct Option: Identifiable, Hashable {
        enum Look: Hashable {
            case pass, formal, pop
            /// 担当を大きく (先頭の担当の画像。無ければ判子)。
            case oshi(URL?)
            /// 自作の画像 (表の画像。まだ選んでいなければ nil)。
            case face(URL?)
        }

        /// 保存のキー (`pass`)。
        let id: String
        /// デザインの名前 (「かしこまった名刺」)。
        let label: String
        let look: Look
        /// 名前の書体の PostScript 名。
        let postScriptName: String
    }

    let options: [Option]
    @Binding var selection: String
    /// 見本に組む名前。
    let sample: String
    /// 担当の色 (帯・罫)。
    var seed: String? = nil
    var brand: String? = nil

    @Environment(\.colorScheme) private var scheme
    @State private var scrolled: String?
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 176
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 132

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
        .accessibilityLabel("名刺のデザイン")
    }

    private var accent: Color {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        return t.isNeutral ? DS.sys : t.accent
    }

    private var name: String { sample.isEmpty ? "ふがP" : sample }

    private func tile(_ option: Option) -> some View {
        let on = option.id == selection
        return Button {
            withAnimation(.imasStandard) { selection = option.id }
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                look(option)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: DS.Space.gapTight) {
                    Text(option.label).imasText(.rowLabel, color: on ? DS.ink : DS.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    ImasSelectionMark(isSelected: on, isSingle: true)
                }
            }
            .padding(DS.Space.gap)
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

    /// そのデザインの小さな名刺。
    @ViewBuilder
    private func look(_ option: Option) -> some View {
        let nameText = Text(name)
            .font(.imasCardName(option.postScriptName, size: 18))
            .foregroundStyle(DS.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        switch option.look {
        case .pass:
            VStack(alignment: .leading, spacing: 0) {
                accent.frame(height: 12)
                nameText.padding(DS.Space.gap)
                Spacer(minLength: 0)
                ImasPerforation(color: DS.perforation).padding(.horizontal, DS.Space.gap)
                Spacer(minLength: 0)
            }
            .background(DS.bg)
            .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
        case .formal:
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text("PRODUCER").imasText(.imprint, color: DS.ink2)
                accent.frame(height: 1)
                nameText
                Spacer(minLength: 0)
            }
            .padding(DS.Space.gap)
            .background(DS.bg)
            .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
        case .pop:
            VStack(alignment: .leading, spacing: 0) {
                accent.frame(height: 12)
                DS.ink.frame(height: 2)
                VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                    nameText
                    accent.frame(width: 32, height: 5)
                }
                .padding(DS.Space.gap)
                Spacer(minLength: 0)
            }
            .background(DS.bg)
            .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous).strokeBorder(DS.ink, lineWidth: 2))
        case let .oshi(url):
            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        if let url {
                            ImasMeishiPictureView(picture: .url(url), fallback: DS.bg)
                        } else {
                            Circle().strokeBorder(accent, lineWidth: 2).padding(DS.Space.gap)
                        }
                    }
                    .clipped()
                accent.frame(width: 2)
                VStack(alignment: .leading, spacing: 0) {
                    nameText
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.gapTight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(DS.bg)
            .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
        case let .face(url):
            if let url {
                ImasCardFace(front: url, label: option.label)
            } else {
                VStack(spacing: DS.Space.gapTight) {
                    Image(systemName: "photo.on.rectangle").foregroundStyle(DS.ink2)
                    Text("画像を選ぶ").imasText(.note)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.rTag, style: .continuous)
                        .strokeBorder(DS.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
        }
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
