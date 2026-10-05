import PhotosUI
import SwiftUI

/// 紙の名刺を取り込む。表と裏を撮り (名刺の形に切り抜かれる)、刷られた QR を読む。
///
/// - アプリの名刺の QR が刷られていれば、その名刺をそのまま入れる (写真も添える)。
/// - X などのリンクの QR なら、名刺のリンクにする。
/// - 文字は読まない (名前は自分で入れる方が速くて確実)。担当は既存のアイドル選択で付ける。
///
/// 紙の名刺もコアで P名刺の形 (`producerCardPayload`) にして、同じ名刺入れに入れる。
/// 写真は端末の中だけ。
struct PaperCardImportView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [UIImage] = []
    @State private var photoPicks: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var isReading = false

    /// 刷られていたアプリの名刺。
    @State private var appCard: (payload: String, card: ProducerCard)?
    @State private var links: [CardLink] = []
    @State private var otherCodes: [String] = []

    @State private var name = ""
    @State private var oshiIds: [String] = []
    @State private var oshiIdols: [Idol] = []
    @State private var brands: [String: Brand] = [:]
    @State private var pickingOshi = false

    @State private var show: ProducerCardShowInfo?
    @State private var showOptions: [LedgerShowOption] = []
    @State private var pickingShow = false
    @State private var memo = ""

    @State private var isSaving = false
    @State private var error: String?

    private let limits = producerCardLimits()

    var body: some View {
        NavigationStack {
            ImasFormPage {
                photoCard
                if !photos.isEmpty {
                    foundCard
                    if appCard == nil { manualCard }
                    ImasFormCard {
                        ImasFormLink(label: "受け取った公演", imprint: "SHOW", systemImage: "ticket",
                                     value: show?.label, placeholder: "公演に紐づけない") { pickingShow = true }
                        ImasFormTextArea(label: "メモ", text: $memo, prompt: "どこで会ったか・何を話したか")
                    }
                }
                ImasNote("写真は端末の中だけに置きます。文字は読み取らないので、名前は入力してください。")
            }
            .navigationTitle("紙の名刺")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(canSave: canSave, onCancel: { dismiss() }, onSave: { Task { await save() } }))
            .imasSavingOverlay(isSaving || isReading, label: isReading ? "QR を探しています" : "保存中")
            .imasErrorAlert("名刺入れに入れられませんでした", message: $error)
            .fullScreenCover(isPresented: $showingCamera) {
                PaperCardCamera(onFinish: { images in
                    showingCamera = false
                    Task { await accept(images) }
                }, onCancel: { showingCamera = false })
                .ignoresSafeArea()
            }
            .sheet(isPresented: $pickingOshi) {
                IdolPickerView(title: "担当", mode: .multi, selected: Set(oshiIds)) { picked in
                    // 選んだ順は持てないので、前からいた人を先に、増えた人を後ろに足す。
                    let kept = oshiIds.filter(picked.contains)
                    let added = picked.subtracting(kept).sorted()
                    oshiIds = Array((kept + added).prefix(Int(limits.maxOshi)))
                    Task { await loadOshi() }
                }
                .environment(database)
            }
            .sheet(isPresented: $pickingShow) {
                LedgerShowPicker(options: showOptions) { option in
                    show = option.map { ProducerCardShowInfo(id: $0.id, eventId: $0.eventId, date: $0.date,
                                                             label: $0.label, venue: nil) }
                    pickingShow = false
                }
            }
            .onChange(of: photoPicks) { _, picks in
                Task { await loadPicks(picks) }
            }
            .task { await loadDefaults() }
        }
    }

    // MARK: - 写真

    private var photoCard: some View {
        ImasFormCard {
            ImasFormField(label: "表と裏", imprint: "PHOTO") {
                VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                    if !photos.isEmpty {
                        HStack(spacing: DS.Space.gap) {
                            ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                                ImasCard(style: .inset, padding: 0) {
                                    Image(uiImage: image).resizable().scaledToFit()
                                }
                                .accessibilityLabel(index == 0 ? "表の写真" : "裏の写真")
                            }
                        }
                    }
                    if PaperCardCamera.isAvailable {
                        Button { showingCamera = true } label: {
                            Label(photos.isEmpty ? "カメラで撮る" : "撮り直す", systemImage: "camera")
                                .imasText(.rowLabel, color: DS.ink)
                        }
                        .buttonStyle(.plain)
                    }
                    PhotosPicker(selection: $photoPicks, maxSelectionCount: 2, matching: .images) {
                        PaperCardPickLabel()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 読み取れたもの

    private var foundCard: some View {
        ImasFormCard {
            ImasFormField(label: "読み取れたもの", imprint: "FOUND") {
                VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                    if let appCard {
                        Text("P名刺の QR: \(appCard.card.name)").imasText(.value)
                    }
                    ForEach(links, id: \.self) { link in
                        let view = cardLinkView(link: link)
                        Text("\(view.label) \(view.display)").imasText(.value)
                    }
                    ForEach(otherCodes, id: \.self) { text in
                        Text(text).imasText(.note).lineLimit(2)
                    }
                    if appCard == nil, links.isEmpty, otherCodes.isEmpty {
                        Text("QR は見つかりませんでした").imasText(.note)
                    }
                }
            }
        }
    }

    // MARK: - 手で入れる (アプリの名刺でないとき)

    private var manualCard: some View {
        ImasFormCard {
            ImasFormTextField(label: "名前", imprint: "NAME", text: $name, prompt: "かるたP",
                              error: name.count > Int(limits.maxNameChars) ? "\(limits.maxNameChars)文字までです" : nil)
            ImasFormField(label: "担当", imprint: "OSHI") {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    ForEach(oshiIdols) { idol in
                        HStack(spacing: DS.Space.gap) {
                            ImasAvatar(label: idol.shortName, seed: idol.color, brand: brands[idol.brandId]?.color,
                                       size: 26, isPick: true)
                            Text(idol.name).imasText(.rowTitle)
                        }
                    }
                    Button { pickingOshi = true } label: {
                        Label(oshiIdols.isEmpty ? "担当を付ける" : "担当を選び直す", systemImage: "plus")
                            .imasText(.rowLabel, color: DS.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 読み書き

    private var canSave: Bool {
        guard !photos.isEmpty, !isSaving else { return false }
        if appCard != nil { return true }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= Int(limits.maxNameChars)
    }

    private func loadDefaults() async {
        showOptions = (try? await AppContainer.shared.ledgerReading.attendedShowOptions()) ?? []
        if let record = try? await ProducerCardAssembler.loadMyRecord(),
           let candidate = ProducerCardInbox.exchangeShowCandidates(record: record).first,
           let option = showOptions.first(where: { $0.id == candidate }) {
            show = ProducerCardShowInfo(id: option.id, eventId: option.eventId, date: option.date,
                                        label: option.label, venue: nil)
        }
        if let all = try? await AppContainer.shared.brandReading.brands() {
            brands = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func loadPicks(_ picks: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for pick in picks {
            if let data = try? await pick.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        if !images.isEmpty { await accept(images) }
    }

    /// 撮った写真から QR を拾い、名刺 / リンク / それ以外に分ける (分け方はコア)。
    private func accept(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        photos = Array(images.prefix(2))
        isReading = true
        let codes = await PaperCardCodeReader.codes(in: photos)
        isReading = false
        appCard = nil
        links = []
        otherCodes = []
        for code in codes {
            switch classifyScannedCode(text: code) {
            case .card(let card, let payload):
                if appCard == nil { appCard = (payload, card) }
            case .link(let url, let link):
                if let link, !links.contains(link), links.count < Int(limits.maxLinks) {
                    links.append(link)
                } else if link == nil {
                    otherCodes.append(url)
                }
            case .text(let text):
                otherCodes.append(text)
            }
        }
    }

    private func loadOshi() async {
        let idols = (try? await AppContainer.shared.idolReading.idols(ids: oshiIds)) ?? []
        let byId = Dictionary(idols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        oshiIdols = oshiIds.compactMap { byId[$0] }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let payload: String
        if let appCard {
            payload = appCard.payload
        } else {
            let card = ProducerCard(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines), message: "", sinceYear: nil,
                oshiIdolIds: oshiIds, links: links, showCount: nil, songCount: nil, nextShowId: nil,
                attended: [], attendedTruncated: false, issuedOn: JSTDay.today())
            payload = producerCardPayload(card: card)
        }
        do {
            var saved = try await ProducerCardInbox.store(payload: payload, images: [], source: .paper, show: show)
            let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, saved.memo == nil {
                saved.memo = trimmed
                try await ProducerCardInbox.update(saved)
            }
            for (image, side) in zip(photos, ProducerCardFiles.Side.allCases) {
                try ProducerCardFiles.savePhoto(image, cardId: saved.id, side: side)
            }
            NotificationCenter.default.post(name: .producerCardsChanged, object: nil)
            AppAnalytics.tap("producer_card.paper_import")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 写真から選ぶボタンの文言 (PhotosPicker の label は MainActor の外で組まれるので View に包む)。
private struct PaperCardPickLabel: View {
    var body: some View {
        Label("写真から選ぶ", systemImage: "photo.on.rectangle")
            .imasText(.rowLabel, color: DS.ink)
    }
}
