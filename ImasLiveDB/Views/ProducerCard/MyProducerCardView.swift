import SwiftUI

/// 自分の P名刺。91:55 の名刺 1 枚と、名刺に収まらない詳細 (ひとこと・担当・リンク) を下に並べる。
///
/// 名刺は交換するもの (誰で、どうつながれるか)。記録の数は名刺の下には出さず、裏 (紙の名刺の裏と同じ) と
/// SNS に貼る画像 (見せるもの) に載る。担当と記録の数はアプリの記録から毎回作る。
/// 出し方は 3 つ: 交換する (QR を見せる / 読む・名刺ファイル)・紙に刷る・SNS に貼る画像。それと名刺入れ。
struct MyProducerCardView: View {
    @Environment(\.openURL) private var openURL

    @State private var myCard: MyProducerCard?
    @State private var record: ProducerCardMyRecord?
    @State private var encoded: EncodedProducerCard?
    @State private var directory = ProducerCardDirectory()
    @State private var caseCount = 0
    @State private var loaded = false

    @State private var editing: MyProducerCard?
    @State private var showingExchange = false
    @State private var showingPrint = false
    @State private var showingCase = false
    @State private var showingImage = false
    @State private var qrMode: QRMode = .exchange
    @State private var portraitURL: URL?
    @State private var face: ProducerCardDisplay.Face?

    /// 名刺の画面で見せる QR。自分の QR を載せていなければ交換用だけ。
    enum QRMode: Hashable { case exchange, own }

    var body: some View {
        ImasPage {
            if !loaded {
                ImasInlineLoading()
            } else if let encoded {
                let card = cardView(encoded)
                cardSection(encoded, card: card)
                card.details
                if let own = encoded.card.qrUrl {
                    qrSection(encoded, own: own)
                }
                actionsSection
            } else {
                ImasCard {
                    ImasEmptyState(
                        systemImage: "person.text.rectangle",
                        title: "まだ P名刺がありません",
                        message: "名前とひとことを書くと、担当と参加の記録はアプリから自動で入ります。",
                        actionTitle: "名刺を作る",
                        action: { editing = myCard ?? .empty() }
                    )
                }
            }
        }
        .navigationTitle("P名刺")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if encoded != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ImasToolbarButton(systemImage: "pencil", label: "名刺を編集") {
                        editing = myCard ?? .empty()
                    }
                }
            }
        }
        .sheet(item: $editing) { card in
            ProducerCardEditorView(card: card, record: record) { saved in
                // 画像の選択 (大きさ・載せる項目) は画像の画面で書くので、開いた時の古い中身で戻さない。
                let latest = try await AppContainer.shared.producerCards.myCard()
                try await AppContainer.shared.producerCards.saveMyCard(saved.applyingEdit(onto: latest))
                await load()
            }
        }
        .sheet(isPresented: $showingExchange) {
            if let encoded {
                ProducerCardExchangeView(myCard: encoded)
            }
        }
        .sheet(isPresented: $showingPrint) {
            if let encoded {
                ProducerCardPrintView(card: encoded, directory: directory)
            }
        }
        .navigationDestination(isPresented: $showingCase) { CardCaseView() }
        .navigationDestination(isPresented: $showingImage) { ProducerCardImageView() }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .producerCardsChanged)) { _ in
            Task { caseCount = (try? await AppContainer.shared.producerCards.receivedCount()) ?? caseCount }
        }
        .trackScreen("producer_card")
    }

    /// 名刺 1 枚。裏の QR は下の切り替え (交換用の QR / 自分の QR) と同じものを刷る。
    private func cardView(_ encoded: EncodedProducerCard) -> ImasProducerCard {
        let own = qrMode == .own ? encoded.card.qrUrl : nil
        return ProducerCardDisplay.view(
            encoded.card, directory: directory,
            imageURL: { CustomImageService.shared.imageURL(for: $0) },
            portraitURL: portraitURL,
            portraitSource: ProducerCardFiles.myPhotoSource,
            face: face,
            back: own.map { ProducerCardDisplay.ownQRBack(encoded.card, url: $0) }
                ?? ImasProducerCard.Back(qr: encoded.url, showCount: encoded.card.showCount,
                                         songCount: encoded.card.songCount,
                                         issuedLabel: cardIssuedLabel(issuedOn: encoded.card.issuedOn)),
            showsRecord: false,
            onOpenLink: { link in if let url = URL(string: link.url) { openURL(url) } },
            onOpenOshi: nil
        )
    }

    private func cardSection(_ encoded: EncodedProducerCard, card: ImasProducerCard) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
            card
            if encoded.card.design == .custom {
                ImasNote("自作の画像は名刺ファイルと近くの iPhone で渡した相手に届きます。QR だけで受け取った人と Web では入場証で見えます。")
            }
            if encoded.droppedShows > 0 {
                ImasNote("QR に収めるため、古い参加公演 \(encoded.droppedShows) 件を名刺から外しています。")
            }
        }
    }

    /// 交換用の QR (アプリの名刺) と自分の QR を切り替えて見せる。
    private func qrSection(_ encoded: EncodedProducerCard, own: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
            ImasTabs(options: [QRMode.exchange, .own], selection: $qrMode) {
                $0 == .exchange ? "交換用の QR" : "自分の QR"
            }
            switch qrMode {
            case .exchange:
                ImasQRCode(text: encoded.url, caption: "アプリで読むと名刺入れに入ります")
            case .own:
                ImasQRCode(text: own, caption: cardQrLinkView(url: own).display, label: "自分の QR コード")
            }
        }
    }

    private var actionsSection: some View {
        ImasSection("渡す・しまう") {
            ImasCardList {
                Button {
                    AppAnalytics.tap("producer_card.exchange")
                    showingExchange = true
                } label: {
                    ImasNavRow(title: "交換する", subtitle: "QR を見せる・読む。名刺ファイルでも送れる",
                               systemImage: "qrcode")
                }
                .buttonStyle(.imasRow)
                .environment(\.imasRowPosition, .first)
                Button { showingPrint = true } label: {
                    ImasNavRow(title: "紙に刷る", subtitle: "91×55mm の名刺の表と裏を画像で書き出す",
                               systemImage: "printer")
                }
                .buttonStyle(.imasRow)
                .environment(\.imasRowPosition, .following)
                Button { showingImage = true } label: {
                    ImasNavRow(title: "SNS に貼る画像", subtitle: "履歴書の様式で、担当・好きな曲・記録を 1 枚に",
                               systemImage: "doc.richtext")
                }
                .buttonStyle(.imasRow)
                .environment(\.imasRowPosition, .following)
                Button { showingCase = true } label: {
                    ImasNavRow(title: "名刺入れ", subtitle: "受け取った名刺を公演ごとに",
                               systemImage: "tray.full", value: "\(caseCount)枚")
                }
                .buttonStyle(.imasRow)
                .environment(\.imasRowPosition, .following)
            }
        }
    }

    private func load() async {
        let store = AppContainer.shared.producerCards
        myCard = try? await store.myCard()
        caseCount = (try? await store.receivedCount()) ?? 0
        if let rec = try? await ProducerCardAssembler.loadMyRecord() {
            record = rec
        }
        ProducerCardFiles.removeLegacyProfileSheetPhoto()
        portraitURL = ProducerCardFiles.myPhotoURL
        face = ProducerCardDisplay.myFace()
        if let myCard, let record, let enc = ProducerCardAssembler.encode(card: myCard, record: record) {
            encoded = enc
            directory = await ProducerCardDirectory.load(
                idolIds: enc.card.oshiIdolIds, showIds: [enc.card.nextShowId].compactMap { $0 })
        } else {
            encoded = nil
        }
        loaded = true
    }
}

extension MyProducerCard: Identifiable {}
