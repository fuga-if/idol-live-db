import SwiftUI

/// 自分の P名刺。担当の入場証を 1 枚に広げた紙に、担当・記録の数・リンクを載せる。
///
/// 担当と記録の数はアプリの記録から毎回作る (名刺の表には名前・ひとこと・リンクだけ持つ)。
/// ここから「交換する」(QR を見せる / 読む)、名刺ファイルで送る、紙に刷る画像、プロフィール帳、名刺入れへ行く。
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
    @State private var showingProfile = false
    @State private var shareError: String?
    @State private var qrMode: QRMode = .exchange
    @State private var portraitURL: URL?

    /// 名刺の画面で見せる QR。自分の QR を載せていなければ交換用だけ。
    enum QRMode: Hashable { case exchange, own }

    var body: some View {
        ImasPage {
            if !loaded {
                ImasInlineLoading()
            } else if let encoded {
                cardSection(encoded)
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
                try await AppContainer.shared.producerCards.saveMyCard(saved)
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
        .navigationDestination(isPresented: $showingProfile) { ProfileSheetView() }
        .imasErrorAlert("名刺ファイルを作れませんでした", message: $shareError)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .producerCardsChanged)) { _ in
            Task { caseCount = (try? await AppContainer.shared.producerCards.receivedCount()) ?? caseCount }
        }
        .trackScreen("producer_card")
    }

    private func cardSection(_ encoded: EncodedProducerCard) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
            ProducerCardDisplay.view(
                encoded.card, directory: directory,
                imageURL: { CustomImageService.shared.imageURL(for: $0) },
                portraitURL: portraitURL,
                onOpenLink: { link in if let url = URL(string: link.url) { openURL(url) } },
                onOpenOshi: nil
            )
            ImasButton(title: "交換する", systemImage: "qrcode", role: .primary, size: .large) {
                AppAnalytics.tap("producer_card.exchange")
                showingExchange = true
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
                Button { shareCardFile() } label: {
                    ImasNavRow(title: "名刺ファイルで送る", subtitle: "AirDrop や Quick Share で写真と担当の画像ごと渡す",
                               systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.imasRow)
                .environment(\.imasRowPosition, .first)
                Button { showingPrint = true } label: {
                    ImasNavRow(title: "紙に刷る画像", subtitle: "91×55mm の名刺の表と裏を書き出す",
                               systemImage: "printer")
                }
                .buttonStyle(.imasRow)
                .environment(\.imasRowPosition, .following)
                Button { showingProfile = true } label: {
                    ImasNavRow(title: "プロフィール帳", subtitle: "履歴書・職務経歴書の様式で、SNS に貼る自己紹介の 1 枚に",
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

    private func shareCardFile() {
        guard let encoded, let data = ProducerCardAssembler.myCardFile(encoded) else {
            shareError = "名刺の中身を組み立てられませんでした。"
            return
        }
        do {
            let url = try ProducerCardAssembler.writeShareFile(data, card: encoded.card)
            AppAnalytics.tap("producer_card.share_file")
            SystemShare.present(items: [url])
        } catch {
            shareError = error.localizedDescription
        }
    }

    private func load() async {
        let store = AppContainer.shared.producerCards
        myCard = try? await store.myCard()
        caseCount = (try? await store.receivedCount()) ?? 0
        if let rec = try? await ProducerCardAssembler.loadMyRecord() {
            record = rec
        }
        portraitURL = ProducerCardFiles.myPhotoURL
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
