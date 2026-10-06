import SwiftUI

/// 紙に刷る P名刺の画像 (表と裏)。91×55mm の比で、印刷所に入稿できる解像度で書き出す。
/// 表は名刺のデザインの組み (自作の画像の名刺はその画像)。裏の QR は既定でアプリの交換と同じ中身、
/// 自分の QR を載せていればそちらも、自作の画像の裏があればその画像も選べる。
struct ProducerCardPrintView: View {
    @Environment(\.dismiss) private var dismiss

    let card: EncodedProducerCard
    let directory: ProducerCardDirectory

    enum Back: Hashable { case faceBack, exchange, own }

    @State private var qr: UIImage?
    @State private var back: Back = .exchange
    @State private var portrait: UIImage?
    @State private var faceFront: UIImage?
    @State private var faceBack: UIImage?

    var body: some View {
        NavigationStack {
            ImasPage {
                ImasSection("表", style: .small) { ProducerCardPrintPreview { frontView } }
                ImasSection("裏", style: .small,
                            footer: "日付を刷るのは、記録の数がその時点のものだからです。書き出した画像はそのまま名刺の印刷に使えます (1638×990px)。") {
                    VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                        if backOptions.count > 1 {
                            ImasSegmented(options: backOptions, selection: $back) { option in
                                switch option {
                                case .faceBack: return "自作の裏"
                                case .exchange: return "交換用の QR"
                                case .own: return "自分の QR"
                                }
                            }
                        }
                        ProducerCardPrintPreview { backView }
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
        .task(id: back) { qr = ImasQRCode.render(backText) }
        .task {
            portrait = ProducerCardFiles.myPhotoURL.flatMap { UIImage(contentsOfFile: $0.path) }
            let face = ProducerCardDisplay.myFace()
            if ProducerCardDisplay.design(card.card, face: face).usesFaceImage, let face {
                faceFront = UIImage(contentsOfFile: face.front.path)
                faceBack = face.back.flatMap { UIImage(contentsOfFile: $0.path) }
                if faceBack != nil { back = .faceBack }
            }
        }
    }

    private var backOptions: [Back] {
        (faceBack == nil ? [] : [.faceBack]) + [.exchange] + (card.card.qrUrl == nil ? [] : [.own])
    }

    private var oshiNames: [String] {
        card.card.oshiIdolIds.compactMap { directory.idols[$0]?.name }
    }

    /// 裏の QR の中身。
    private var backText: String {
        back == .own ? (card.card.qrUrl ?? card.url) : card.url
    }

    private var look: ProducerCardPrintFront.Look {
        switch ProducerCardDisplay.design(card.card, face: nil).design {
        case .formal: return .formal
        case .pop: return .pop
        case .pass, .custom: return .pass
        }
    }

    private var front: ProducerCardPrintFront {
        ProducerCardPrintFront(
            look: look,
            name: card.card.name,
            sinceYear: card.card.sinceYear,
            oshiNames: oshiNames,
            seed: card.card.oshiIdolIds.first.flatMap { directory.idols[$0]?.color },
            handle: card.card.links.first.map { cardLinkView(link: $0).display },
            nameFont: ProducerCardDisplay.nameFont(card.card),
            portrait: portrait
        )
    }

    @ViewBuilder
    private var frontView: some View {
        if let faceFront {
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
            issuedLabel: cardIssuedLabel(issuedOn: card.card.issuedOn), qrImage: qr
        )
    }

    @ViewBuilder
    private var backView: some View {
        if back == .faceBack, let faceBack {
            ProducerCardPrintImage(image: faceBack)
        } else {
            qrBack
        }
    }

    private func export() {
        let images = [ProducerCardPrint.render(frontView), ProducerCardPrint.render(backView)].compactMap { $0 }
        guard !images.isEmpty else { return }
        AppAnalytics.tap("producer_card.print_export")
        SystemShare.present(items: images.map(ShareCardImageSource.init))
    }
}
