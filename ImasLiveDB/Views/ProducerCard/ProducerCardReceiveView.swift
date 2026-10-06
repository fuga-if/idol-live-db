import SwiftUI

/// 受け取りの確認。相手の名刺を見せ、受け取った公演を確かめて ✓ で名刺入れへ。
///
/// QR を読んだとき・名刺のリンク (Universal Link) を開いたとき・名刺ファイルを開いたときの共通の画面。
/// QR から来たときは近くの相手の iPhone から担当の画像が届くのを待つ (届かなくても保存できる)。
struct ProducerCardReceiveView: View {
    @Environment(\.dismiss) private var dismiss

    let incoming: IncomingProducerCard
    /// 近くの相手から画像を受け取る口 (QR を読んだときだけ)。
    var nearby: NearbyCardExchange? = nil
    /// 終わったとき (しまえたら相手の名前と名刺入れの id、やめたら nil)。渡さなければ画面を閉じる。
    var onDone: (((name: String, id: String)?) -> Void)? = nil

    @State private var record: ProducerCardMyRecord?
    @State private var directory = ProducerCardDirectory()
    @State private var images: [CardFileImage] = []
    @State private var imageURLs: [String: URL] = [:]
    /// 届いた名刺の写真 (名刺ファイル・近くの iPhone から。QR だけなら無い)。
    @State private var portraitURL: URL?
    /// 届いた自作の名刺の画像 (名刺ファイル・近くの iPhone から。QR だけなら無いので入場証で描く)。
    @State private var face: ProducerCardDisplay.Face?
    @State private var show: ProducerCardShowInfo?
    @State private var showOptions: [LedgerShowOption] = []
    @State private var pickingShow = false
    @State private var isSaving = false
    @State private var error: String?

    private var card: ProducerCard? { decodeProducerCard(text: incoming.payload) }

    var body: some View {
        ImasPage {
            if let card {
                let display = ProducerCardDisplay.view(
                    card, directory: directory, sharedWith: Set(record?.oshiIds ?? []),
                    imageURL: { imageURLs[$0] }, portraitURL: portraitURL,
                    portraitSource: images.first { $0.kind == .photo }?.photoSource ?? .picked, face: face,
                    payload: incoming.payload, onOpenLink: nil, onOpenOshi: nil)
                display
                display.details
                commonSection(card)
                ImasFormCard {
                    ImasFormLink(label: "受け取った公演", imprint: "SHOW", systemImage: "ticket",
                                 value: show?.label, placeholder: "公演に紐づけない") {
                        pickingShow = true
                    }
                }
                nearbyNote
            } else {
                ImasCard {
                    ImasEmptyState(.failed, title: "名刺を読めませんでした",
                                   message: "新しい版のアプリで作られた名刺かもしれません。アプリを最新にしてからもう一度読んでください。")
                }
            }
        }
        .navigationTitle("名刺を受け取る")
        .navigationBarTitleDisplayMode(.inline)
        .imasSheetToolbar(.edit(canSave: card != nil && !isSaving, onCancel: { close() }, onSave: { Task { await save() } }))
        .imasSavingOverlay(isSaving, label: "保存中")
        .imasErrorAlert("名刺入れに入れられませんでした", message: $error)
        .sheet(isPresented: $pickingShow) {
            LedgerShowPicker(options: showOptions) { option in
                show = option.map { ProducerCardShowInfo(id: $0.id, eventId: $0.eventId, date: $0.date,
                                                         label: $0.label, venue: nil) }
                pickingShow = false
            }
        }
        .task { await load() }
        .onChange(of: nearby?.received) { _, contents in
            guard let contents, contents.payload == incoming.payload else { return }
            accept(contents.images)
        }
    }

    // MARK: - 共通点

    @ViewBuilder
    private func commonSection(_ card: ProducerCard) -> some View {
        if let record {
            let common = producerCardCommon(card: card, myOshiIds: record.oshiIds, myAttended: record.summary.attendedPast)
            let sharedNames = common.sharedOshiIds.compactMap { directory.idols[$0]?.name }
            if !sharedNames.isEmpty || !common.sharedShowIds.isEmpty {
                ImasSection("あなたとの共通点", style: .small) {
                    ImasCardList {
                        if !sharedNames.isEmpty {
                            ImasValueRow(key: "同じ担当", value: sharedNames.joined(separator: "・"))
                                .environment(\.imasRowPosition, .first)
                        }
                        if !common.sharedShowIds.isEmpty {
                            ImasValueRow(key: "同じ公演にいた", value: "\(common.sharedShowIds.count)回", monospaced: true)
                                .environment(\.imasRowPosition, sharedNames.isEmpty ? .first : .following)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nearbyNote: some View {
        if let nearby, incoming.via == .scan {
            switch nearby.phase {
            case .searching, .connected, .waiting:
                ImasNote("近くの相手の iPhone から写真と担当の画像を受け取っています…。繋がると、あなたの名刺も相手の名刺入れに渡ります (× でやめると相手には渡りません)。")
            case .received:
                ImasNote(images.isEmpty ? "相手の名刺を受け取りました (写真・担当の画像は設定されていません)。" : "写真と画像を受け取りました。")
            case .notFound, .idle:
                ImasNote("近くに相手の iPhone が見つかりませんでした。名刺は QR の中身だけで保存できます。写真と担当の画像は、相手に「名刺ファイルで送る」で送ってもらうと届きます。")
            }
        }
    }

    // MARK: - 読み書き

    private func load() async {
        accept(incoming.images)
        if let current = nearby?.received, current.payload == incoming.payload { accept(current.images) }
        let rec = try? await ProducerCardAssembler.loadMyRecord()
        record = rec
        showOptions = (try? await AppContainer.shared.ledgerReading.attendedShowOptions()) ?? []
        let candidate = rec.flatMap { ProducerCardInbox.exchangeShowCandidates(record: $0).first }
        let idols = (card?.oshiIdolIds ?? []) + (rec?.oshiIds ?? [])
        directory = await ProducerCardDirectory.load(
            idolIds: idols, showIds: [candidate, card?.nextShowId].compactMap { $0 })
        if show == nil, let candidate { show = directory.shows[candidate] }
    }

    /// 届いた画像をプレビューできるよう一時フォルダに書く (しまうときは名刺入れの置き場へ)。
    private func accept(_ new: [CardFileImage]) {
        guard !new.isEmpty else { return }
        images = new
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("producer_card_incoming", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [String: URL] = [:]
        var portrait: URL?
        var front: URL?
        var back: URL?
        for (i, image) in new.enumerated() {
            let url = dir.appendingPathComponent("\(i).jpg")
            guard (try? image.jpeg.write(to: url, options: .atomic)) != nil else { continue }
            switch image.kind {
            case .oshi: urls[image.idolId] = url
            case .photo: portrait = url
            case .faceFront: front = url
            case .faceBack: back = url
            }
        }
        imageURLs = urls
        portraitURL = portrait
        face = front.map { ProducerCardDisplay.Face(front: $0, back: back) }
    }

    private func save() async {
        guard let card else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await ProducerCardInbox.store(payload: incoming.payload, images: images,
                                                          source: .app, show: show)
            AppAnalytics.tap("producer_card.receive")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let onDone { onDone((card.name, saved.id)) } else { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func close() {
        if let onDone { onDone(nil) } else { dismiss() }
    }
}

/// 名刺のリンク・名刺ファイルを開いたときのシート (アプリのどこからでも)。
struct ProducerCardReceiveSheet: View {
    let incoming: IncomingProducerCard

    var body: some View {
        NavigationStack {
            ProducerCardReceiveView(incoming: incoming)
        }
    }
}
