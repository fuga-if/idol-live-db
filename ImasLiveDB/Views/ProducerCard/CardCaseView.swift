import SwiftUI

/// 名刺入れ。受け取った名刺を、受け取った公演ごと (公演の半券の下) に束ねて新しい順に並べる。
///
/// 束ね方・並び順はコア (`cardCaseSections`)。行頭の帯は相手の担当の色、自分と担当が同じなら
/// 朱の札「担当被り」。行は右に引くとメモ、左に引くと削除。
///
/// ⚠️ 行のスワイプを効かせるため **List** で組む。
struct CardCaseView: View {
    @State private var cards: [ReceivedProducerCard] = []
    @State private var decoded: [String: ProducerCard] = [:]
    @State private var sections: [CardCaseSection] = []
    @State private var directory = ProducerCardDirectory()
    @State private var myOshi: Set<String> = []
    @State private var myCard: EncodedProducerCard?
    @State private var loaded = false

    @State private var openCard: ReceivedProducerCard?
    @State private var memoTarget: ReceivedProducerCard?
    @State private var showingExchange = false
    @State private var showingPaper = false
    @State private var error: String?

    var body: some View {
        List {
            if !loaded {
                ImasInlineLoading().padding(.vertical, DS.Space.section).plainRow(background: DS.bg)
            } else if cards.isEmpty {
                ImasEmptyState(
                    systemImage: "tray",
                    title: "まだ名刺がありません",
                    message: "会場で相手の P名刺の QR を読むか、紙の名刺を撮って取り込むと、受け取った公演ごとにここへしまわれます。",
                    actionTitle: "QR を読む",
                    action: { showingExchange = true }
                )
                .plainRow(background: DS.bg)
            } else {
                ImasListSummary(count: cards.count, unit: "枚")
                    .plainRow(background: DS.bg)
                ForEach(sections, id: \.self) { section in
                    sectionHeader(section)
                    ForEach(section.entryIds, id: \.self) { id in
                        if let card = cards.first(where: { $0.id == id }) {
                            row(card)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("名刺入れ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingExchange = true } label: { Label("QR を読む", systemImage: "qrcode.viewfinder") }
                    Button { showingPaper = true } label: { Label("紙の名刺を取り込む", systemImage: "camera") }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("名刺を足す")
            }
        }
        .navigationDestination(item: $openCard) { card in
            ReceivedCardDetailView(cardId: card.id)
        }
        .sheet(item: $memoTarget) { card in
            CardMemoEditorView(card: card)
        }
        .sheet(isPresented: $showingExchange) {
            ProducerCardExchangeView(myCard: myCard, initialMode: .read)
        }
        .sheet(isPresented: $showingPaper) {
            PaperCardImportView()
        }
        .imasErrorAlert("名刺を消せませんでした", message: $error)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .producerCardsChanged)) { _ in
            Task { await load() }
        }
        .trackScreen("card_case")
    }

    // MARK: - 束の頭 (公演の半券)

    @ViewBuilder
    private func sectionHeader(_ section: CardCaseSection) -> some View {
        let show = section.showId.flatMap { directory.shows[$0] }
        let count = "\(section.entryIds.count)枚"
        ImasStubRow(
            date: ImasStubDate(section.date),
            title: show?.label ?? "公演に紐づかない名刺",
            subtitle: [show?.venue, count].compactMap { $0 }.joined(separator: " · ")
        )
        .padding(.top, DS.Space.gapLoose)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 行

    private func row(_ card: ReceivedProducerCard) -> some View {
        let content = decoded[card.id]
        let lead = content?.oshiIdolIds.compactMap { directory.idols[$0] }.first
        let brand = lead.flatMap { directory.brands[$0.brandId] }
        let shared = content.map { !Set($0.oshiIdolIds).isDisjoint(with: myOshi) } ?? false
        let oshiIcon = lead.map {
            ImasRowPortraitOshi(label: $0.shortName, seed: $0.color, brand: brand?.color,
                                imageURL: ProducerCardFiles.oshiImageURL(cardId: card.id, idolId: $0.id))
        }
        // 自作の名刺の画像があればその小さな見本、名刺の写真があれば証明写真の枠 (どちらも右下に
        // 担当のアイコンを重ねる)、無ければ担当のアイコン。
        let leading: ImasRowLeading
        if let content, let face = ProducerCardDisplay.receivedFace(cardId: card.id),
           ProducerCardDisplay.design(content, face: face).usesFaceImage {
            leading = .cardFace(face.front, oshi: oshiIcon)
        } else if let portrait = ProducerCardFiles.cardPhotoURL(cardId: card.id) {
            leading = .portrait(portrait, round: ProducerCardFiles.cardPhotoRound(cardId: card.id), oshi: oshiIcon)
        } else if let oshiIcon {
            leading = .avatar(label: oshiIcon.label, seed: oshiIcon.seed, brand: oshiIcon.brand,
                              imageURL: oshiIcon.imageURL, isPick: true)
        } else {
            leading = .icon(card.sourceValue == .paper ? "doc.text.image" : "person.text.rectangle", tone: .neutral)
        }
        var subtitle = content.map { ProducerCardDisplay.summaryLine($0, directory: directory) } ?? ""
        if card.sourceValue == .paper { subtitle = subtitle.isEmpty ? "紙の名刺" : "紙の名刺 · \(subtitle)" }
        return Button {
            openCard = card
        } label: {
            ImasRow(
                title: content?.name ?? "読めない名刺",
                subtitle: subtitle.isEmpty ? nil : subtitle,
                leading: leading,
                leadBar: lead.map { ImasRowLeadBar(seed: $0.color, brand: brand?.color) },
                trailing: shared ? .badge(ImasBadge(text: "担当被り", kind: .new)) : .none
            ) {
                if let memo = card.memo, !memo.isEmpty {
                    Text(memo).imasText(.note).lineLimit(1)
                }
            }
        }
        .buttonStyle(.imasRow)
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.screen, bottom: 0, trailing: DS.Space.screen))
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
        .imasSwipe(
            leading: [ImasSwipeAction(.memo, title: "メモ") { memoTarget = card }],
            trailing: [ImasSwipeAction(.delete, title: "削除") { Task { await delete(card) } }]
        )
    }

    // MARK: - 読み書き

    private func load() async {
        let store = AppContainer.shared.producerCards
        let all = (try? await store.receivedCards()) ?? []
        var map: [String: ProducerCard] = [:]
        for card in all { if let c = card.card { map[card.id] = c } }
        let entries = all.map {
            CardCaseEntry(id: $0.id, showId: $0.showId, showDate: $0.showDate, receivedAt: $0.receivedAt)
        }
        let record = try? await ProducerCardAssembler.loadMyRecord()
        let built = cardCaseSections(entries: entries)
        let idolIds = map.values.flatMap(\.oshiIdolIds)
        directory = await ProducerCardDirectory.load(idolIds: idolIds, showIds: built.compactMap(\.showId))
        myOshi = Set(record?.oshiIds ?? [])
        if myCard == nil, let mine = try? await store.myCard(), let record {
            myCard = ProducerCardAssembler.encode(card: mine, record: record)
        }
        cards = all
        decoded = map
        sections = built
        loaded = true
    }

    private func delete(_ card: ReceivedProducerCard) async {
        do {
            try await ProducerCardInbox.delete(card)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 受け取った名刺のメモ。
struct CardMemoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let card: ReceivedProducerCard

    @State private var memo: String
    @State private var isSaving = false
    @State private var error: String?

    init(card: ReceivedProducerCard) {
        self.card = card
        _memo = State(initialValue: card.memo ?? "")
    }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasFormCard {
                    ImasFormTextArea(label: "メモ", text: $memo, prompt: "物販列で隣。蒼い鳥の話で盛り上がった", autofocus: true)
                }
                ImasNote("メモは端末の中だけに置きます。相手には見えません。")
            }
            .navigationTitle(card.card?.name ?? "メモ")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(canSave: !isSaving, onCancel: { dismiss() }, onSave: { Task { await save() } }))
            .imasSavingOverlay(isSaving, label: "保存中")
            .imasErrorAlert("メモを保存できませんでした", message: $error)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = card
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.memo = trimmed.isEmpty ? nil : trimmed
        do {
            try await ProducerCardInbox.update(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
