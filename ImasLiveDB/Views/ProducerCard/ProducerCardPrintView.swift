import SwiftUI

/// 紙に刷る P名刺の画像 (表と裏)。91×55mm の比で、印刷所に入稿できる解像度で書き出す。
/// 表は選んだ書体の名前と名刺の写真。裏の QR は既定でアプリの交換と同じ中身、自分の QR を
/// 載せていればそちらも選べる。
struct ProducerCardPrintView: View {
    @Environment(\.dismiss) private var dismiss

    let card: EncodedProducerCard
    let directory: ProducerCardDirectory

    enum BackQR: Hashable { case exchange, own }

    @State private var qr: UIImage?
    @State private var backQR: BackQR = .exchange
    @State private var portrait: UIImage?

    var body: some View {
        NavigationStack {
            ImasPage {
                ImasSection("表", style: .small) { ProducerCardPrintPreview { front } }
                ImasSection("裏", style: .small,
                            footer: "日付を刷るのは、記録の数がその時点のものだからです。書き出した画像はそのまま名刺の印刷に使えます (1638×990px)。") {
                    VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                        if card.card.qrUrl != nil {
                            ImasSegmented(options: [BackQR.exchange, .own], selection: $backQR) {
                                $0 == .exchange ? "交換用の QR" : "自分の QR"
                            }
                        }
                        ProducerCardPrintPreview { back }
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
        .task(id: backQR) { qr = ImasQRCode.render(backText) }
        .task { portrait = ProducerCardFiles.myPhotoURL.flatMap { UIImage(contentsOfFile: $0.path) } }
    }

    private var oshiNames: [String] {
        card.card.oshiIdolIds.compactMap { directory.idols[$0]?.name }
    }

    /// 裏の QR の中身。
    private var backText: String {
        backQR == .own ? (card.card.qrUrl ?? card.url) : card.url
    }

    private var front: ProducerCardPrintFront {
        ProducerCardPrintFront(
            name: card.card.name,
            sinceYear: card.card.sinceYear,
            oshiNames: oshiNames,
            seed: card.card.oshiIdolIds.first.flatMap { directory.idols[$0]?.color },
            handle: card.card.links.first.map { cardLinkView(link: $0).display },
            nameFont: ProducerCardDisplay.nameFont(card.card),
            portrait: portrait
        )
    }

    private var back: ProducerCardPrintBack {
        let own = backQR == .own ? card.card.qrUrl.map { cardQrLinkView(url: $0).display } : nil
        return ProducerCardPrintBack(
            url: backText,
            note: own.map { "読み取ると \($0) が開きます。" }
                ?? "読み取るとアプリの名刺入れに入ります。アプリが無ければ Web で開きます。",
            showCount: card.card.showCount, songCount: card.card.songCount,
            issuedLabel: cardIssuedLabel(issuedOn: card.card.issuedOn), qrImage: qr
        )
    }

    private func export() {
        let images = [ProducerCardPrint.render(front), ProducerCardPrint.render(back)].compactMap { $0 }
        guard !images.isEmpty else { return }
        AppAnalytics.tap("producer_card.print_export")
        SystemShare.present(items: images.map(ShareCardImageSource.init))
    }
}
