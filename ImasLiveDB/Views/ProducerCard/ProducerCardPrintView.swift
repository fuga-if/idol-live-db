import SwiftUI

/// 紙に刷る P名刺の画像 (表と裏)。91×55mm の比で、印刷所に入稿できる解像度で書き出す。
/// 表は名刺のデザインの組み (自作の画像の名刺はその画像)。裏の QR は既定でアプリの交換と同じ中身、
/// 自分の QR を載せていればそちらも、自作の画像の裏があればその画像も選べる。
struct ProducerCardPrintView: View {
    @Environment(\.dismiss) private var dismiss

    let card: EncodedProducerCard
    let directory: ProducerCardDirectory

    @State private var qr: UIImage?
    @State private var back: ProducerCardPrintSheet.Back = .exchange
    @State private var materials = ProducerCardPrintMaterials()

    private var sheet: ProducerCardPrintSheet {
        ProducerCardPrintSheet(card: card, directory: directory, materials: materials, back: back, qr: qr)
    }

    var body: some View {
        NavigationStack {
            ImasPage {
                ImasSection("表", style: .small) { ProducerCardPrintPreview { sheet.frontView } }
                ImasSection("裏", style: .small,
                            footer: "日付を刷るのは、記録の数がその時点のものだからです。書き出した画像はそのまま名刺の印刷に使えます (1638×990px)。") {
                    VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                        if sheet.backOptions.count > 1 {
                            ImasSegmented(options: sheet.backOptions, selection: $back) { option in
                                switch option {
                                case .faceBack: return "自作の裏"
                                case .exchange: return "交換用の QR"
                                case .own: return "自分の QR"
                                }
                            }
                        }
                        ProducerCardPrintPreview { sheet.backView }
                    }
                }
                ImasButton(title: "画像を書き出す", systemImage: "square.and.arrow.up", role: .primary, size: .large) {
                    export()
                }
            }
            .navigationTitle("紙に刷る")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
        }
        .task(id: back) { qr = ImasQRCode.render(sheet.backText) }
        .task {
            materials = ProducerCardPrintMaterials.loadMine(card: card.card)
            if materials.faceBack != nil { back = .faceBack }
        }
    }

    private func export() {
        let images = sheet.renderImages()
        guard !images.isEmpty else { return }
        AppAnalytics.tap("producer_card.print_export")
        SystemShare.present(items: images.map(ShareCardImageSource.init))
    }
}

/// 紙に刷る画像に焼く、読み込み済みの画像。ImageRenderer は画像の読み込みを待たないので、
/// 書き出す前に全部 UIImage に読んでおく (URL のまま渡すと担当の写真が焼かれない)。
struct ProducerCardPrintMaterials {
    var portrait: UIImage?
    var faceFront: UIImage?
    var faceBack: UIImage?
    /// 担当の写真 (アイドルの id → 画像)。
    var oshiImages: [String: UIImage] = [:]

    /// 自分の名刺の画像 (名刺の写真・担当の代表画像・自作の画像) を読む。
    @MainActor
    static func loadMine(card: ProducerCard) -> ProducerCardPrintMaterials {
        var out = ProducerCardPrintMaterials()
        out.portrait = ProducerCardFiles.myPhotoURL.flatMap { ProducerCardFiles.printImage(at: $0, maxPixels: 900) }
        for id in card.oshiIdolIds {
            if let url = CustomImageService.shared.imageURL(for: id),
               let image = ProducerCardFiles.printImage(at: url) { out.oshiImages[id] = image }
        }
        let face = ProducerCardDisplay.myFace()
        if ProducerCardDisplay.design(card, face: face).usesFaceImage, let face {
            out.faceFront = ProducerCardFiles.printImage(at: face.front, maxPixels: 2000)
            out.faceBack = face.back.flatMap { ProducerCardFiles.printImage(at: $0, maxPixels: 2000) }
        }
        return out
    }
}

/// 紙に刷る表と裏の組み立て (画面の見本と書き出しで同じもの)。
@MainActor
struct ProducerCardPrintSheet {
    enum Back: Hashable { case faceBack, exchange, own }

    let card: EncodedProducerCard
    let directory: ProducerCardDirectory
    let materials: ProducerCardPrintMaterials
    var back: Back = .exchange
    var qr: UIImage?

    var backOptions: [Back] {
        (materials.faceBack == nil ? [] : [.faceBack]) + [.exchange] + (card.card.qrUrl == nil ? [] : [.own])
    }

    /// 表の組み (載せる担当・畳む数・ハンドルはコア)。
    private var face: CardFace {
        producerCardFace(card: card.card, drawableIdolIds: card.card.oshiIdolIds.filter { directory.idols[$0] != nil })
    }

    /// 裏の QR の中身。
    var backText: String {
        back == .own ? (card.card.qrUrl ?? card.url) : card.url
    }

    private var look: ImasMeishiFront.Look {
        switch ProducerCardDisplay.design(card.card, face: nil).design {
        case .formal: return .formal
        case .pop: return .pop
        case .pass, .custom: return .pass
        }
    }

    private var front: ProducerCardPrintFront {
        let face = face
        return ProducerCardPrintFront(
            look: look,
            name: card.card.name,
            sinceImprint: face.sinceImprint,
            oshi: face.oshiIdolIds.compactMap { id in
                directory.idols[id].map {
                    ProducerCardPrintOshi(id: id, name: $0.name, shortName: $0.shortName, seed: $0.color,
                                          image: materials.oshiImages[id])
                }
            },
            moreOshi: Int(face.moreOshi),
            seed: card.card.oshiIdolIds.first.flatMap { directory.idols[$0]?.color },
            handle: face.handle?.display,
            nameFont: ProducerCardDisplay.nameFont(card.card),
            portrait: materials.portrait
        )
    }

    @ViewBuilder
    var frontView: some View {
        if let faceFront = materials.faceFront {
            ProducerCardPrintImage(image: faceFront)
        } else {
            front
        }
    }

    private var qrBack: ProducerCardPrintBack {
        let own = back == .own ? card.card.qrUrl.map { cardQrLinkView(url: $0).display } : nil
        return ProducerCardPrintBack(
            url: backText,
            note: own.map { "読み取ると \($0) が開きます。" }
                ?? "読み取るとアプリの名刺入れに入ります。アプリが無ければ Web で開きます。",
            showCount: card.card.showCount, songCount: card.card.songCount,
            issuedLabel: face.issuedLabel, qrImage: qr
        )
    }

    @ViewBuilder
    var backView: some View {
        if back == .faceBack, let faceBack = materials.faceBack {
            ProducerCardPrintImage(image: faceBack)
        } else {
            qrBack
        }
    }

    /// 書き出す画像 (表・裏、1638×990px)。
    func renderImages() -> [UIImage] {
        [ProducerCardPrint.render(frontView), ProducerCardPrint.render(backView)].compactMap { $0 }
    }
}
