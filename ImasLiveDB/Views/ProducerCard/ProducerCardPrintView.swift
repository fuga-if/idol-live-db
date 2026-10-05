import SwiftUI

/// 紙に刷る P名刺の画像 (表と裏)。91×55mm の比で、印刷所に入稿できる解像度で書き出す。
/// 裏の QR はアプリの交換と同じ中身。
struct ProducerCardPrintView: View {
    @Environment(\.dismiss) private var dismiss

    let card: EncodedProducerCard
    let directory: ProducerCardDirectory

    @State private var qr: UIImage?

    var body: some View {
        NavigationStack {
            ImasPage {
                ImasSection("表", style: .small) { ProducerCardPrintPreview { front } }
                ImasSection("裏", style: .small,
                            footer: "日付を刷るのは、記録の数がその時点のものだからです。書き出した画像はそのまま名刺の印刷に使えます (1638×990px)。") {
                    ProducerCardPrintPreview { back }
                }
                ImasButton(title: "画像を書き出す", systemImage: "square.and.arrow.up", role: .primary, size: .large) {
                    export()
                }
            }
            .navigationTitle("紙に刷る")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
        }
        .task { qr = ImasQRCode.render(card.url) }
    }

    private var oshiNames: [String] {
        card.card.oshiIdolIds.compactMap { directory.idols[$0]?.name }
    }

    private var front: ProducerCardPrintFront {
        ProducerCardPrintFront(
            name: card.card.name,
            sinceYear: card.card.sinceYear,
            oshiNames: oshiNames,
            seed: card.card.oshiIdolIds.first.flatMap { directory.idols[$0]?.color },
            handle: card.card.links.first.map { cardLinkView(link: $0).display }
        )
    }

    private var back: ProducerCardPrintBack {
        ProducerCardPrintBack(
            url: card.url, showCount: card.card.showCount, songCount: card.card.songCount,
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
