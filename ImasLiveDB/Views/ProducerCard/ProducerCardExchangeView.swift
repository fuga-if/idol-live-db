import SwiftUI
import UIKit

/// 名刺交換。「見せる / 読む」の 2 択だけ。
///
/// - 見せる: 自分の名刺の QR を明るい画面で出し、近くの iPhone に名乗る (読んだ相手に担当の画像を送り、
///   相手の名刺を受け取る)。
/// - 読む: 相手の QR をカメラで読み、受け取りの確認へ。近くに相手の iPhone がいれば担当の画像も届き、
///   自分の名刺を送り返す (1 回のスキャンで双方向)。見つからなければ QR の中身だけで保存できる。
struct ProducerCardExchangeView: View {
    enum Mode: Hashable { case show, read }

    @Environment(\.dismiss) private var dismiss

    /// 自分の名刺。まだ作っていなければ nil (読むだけはできる。相手には送り返さない)。
    let myCard: EncodedProducerCard?
    var initialMode: Mode = .show

    @State private var mode: Mode = .show
    @State private var nearby = NearbyCardExchange()
    @State private var myFile: Data?
    @State private var path: [IncomingProducerCard] = []
    @State private var scanNotice: String?
    @State private var lastReceived: String?
    @State private var savedNotice: String?
    @State private var previousBrightness: CGFloat?

    var body: some View {
        NavigationStack(path: $path) {
            ImasPage {
                ImasTabs(options: [Mode.show, .read], selection: $mode) { $0 == .show ? "見せる" : "読む" }
                switch mode {
                case .show: showSection
                case .read: readSection
                }
            }
            .navigationTitle("名刺交換")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .navigationDestination(for: IncomingProducerCard.self) { incoming in
                ProducerCardReceiveView(incoming: incoming, nearby: nearby) { saved in
                    if let saved { savedNotice = "\(saved)さんの名刺を名刺入れに入れました" }
                    path = []
                }
            }
        }
        .task {
            mode = initialMode
            myFile = myCard.flatMap(ProducerCardAssembler.myCardFile)
            apply(mode)
        }
        .onChange(of: mode) { _, new in apply(new) }
        .onChange(of: path) { _, new in
            // 確認から戻ったら、読む画面の名乗り (探す) をやめる。
            if new.isEmpty, mode == .read { nearby.stop() }
        }
        .onDisappear {
            nearby.stop()
            restoreBrightness()
        }
    }

    // MARK: - 見せる

    @ViewBuilder
    private var showSection: some View {
        if let myCard {
            VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                ImasQRCode(text: myCard.url, caption: caption(myCard))
                if let lastReceived {
                    ImasNotice(kind: .success, title: "\(lastReceived)さんの名刺を受け取りました",
                               message: "名刺入れに入れました。")
                }
                ImasNote("相手のアプリで読むと、近くの iPhone どうしなら担当の画像も元の画質のまま届き、相手の名刺も受け取れます。アプリが無い人がカメラで読むと、Web の名刺ページが開きます。")
            }
        } else {
            ImasCard {
                ImasEmptyState(systemImage: "person.text.rectangle", title: "まだ P名刺がありません",
                               message: "プロデュースの「P名刺」から作ると、ここで QR を見せられます。")
            }
        }
    }

    private func caption(_ myCard: EncodedProducerCard) -> String {
        var parts = [myCard.card.name]
        if !myCard.card.oshiIdolIds.isEmpty { parts.append("担当 \(myCard.card.oshiIdolIds.count)") }
        if let shows = myCard.card.showCount { parts.append("\(shows.formatted()) 公演") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 読む

    @ViewBuilder
    private var readSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
            if CardQRScanner.isAvailable {
                ImasCameraFrame {
                    CardQRScanner { text in handleScan(text) }
                }
                ImasNote("相手の P名刺の QR を枠に入れてください。")
            } else {
                ImasCard {
                    ImasEmptyState(systemImage: "camera", title: "この端末ではカメラで読めません",
                                   message: "相手に「名刺ファイルで送る」で送ってもらうか、カメラアプリで QR を読むと、受け取りの確認が開きます。")
                }
            }
            if let scanNotice {
                ImasNotice(kind: .info, title: scanNotice)
            }
            if let savedNotice {
                ImasNotice(kind: .success, title: savedNotice)
            }
        }
    }

    private func handleScan(_ text: String) {
        guard path.isEmpty else { return }
        switch classifyScannedCode(text: text) {
        case .card(_, let payload):
            scanNotice = nil
            savedNotice = nil
            AppAnalytics.tap("producer_card.scan")
            nearby.onReceive = nil
            nearby.startReading(payload: payload, file: myFile)
            path = [IncomingProducerCard(payload: payload, images: [], via: .scan)]
        case .link:
            scanNotice = "P名刺の QR ではありません。紙の名刺に刷られた QR は、名刺入れの「紙の名刺を取り込む」から読めます。"
        case .text:
            scanNotice = "P名刺の QR ではありません。"
        }
    }

    // MARK: - 切り替え

    private func apply(_ mode: Mode) {
        nearby.stop()
        switch mode {
        case .show:
            guard let myCard else { return }
            raiseBrightness()
            if let myFile {
                nearby.onReceive = { contents in Task { await storeFromReader(contents) } }
                nearby.startShowing(payload: ProducerCardAssembler.payload(of: myCard), file: myFile)
            }
        case .read:
            restoreBrightness()
        }
    }

    /// 読んだ相手が送り返してきた名刺を名刺入れへ (受け取った公演は今日の参加公演)。
    private func storeFromReader(_ contents: CardFileContents) async {
        let record = try? await ProducerCardAssembler.loadMyRecord()
        let showId = record.flatMap { ProducerCardInbox.exchangeShowCandidates(record: $0).first }
        let infos = (try? await AppContainer.shared.producerCards.showInfos(ids: [showId].compactMap { $0 })) ?? [:]
        _ = try? await ProducerCardInbox.store(payload: contents.payload, images: contents.images, source: .app,
                                               show: showId.flatMap { infos[$0] })
        lastReceived = contents.card.name
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - 画面の明るさ (QR を読みやすく)

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }

    private func raiseBrightness() {
        guard let screen, previousBrightness == nil else { return }
        previousBrightness = screen.brightness
        screen.brightness = 1
    }

    private func restoreBrightness() {
        guard let screen, let previous = previousBrightness else { return }
        screen.brightness = previous
        previousBrightness = nil
    }
}

/// 受け取りの確認に渡す名刺 (QR・リンク・名刺ファイルのどれから来たか)。
struct IncomingProducerCard: Hashable, Identifiable {
    enum Via: Hashable { case scan, link, file }

    var id: String { payload }
    let payload: String
    /// 名刺ファイルに入っていた担当の画像。
    let images: [CardFileImage]
    let via: Via
}
