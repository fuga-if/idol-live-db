import NukeUI
import SwiftUI

/// 受け取った名刺 1 枚。相手の名刺 (自分の名刺と同じ部品)・あなたとの共通点・会った記録・メモ・紙の名刺の写真。
///
/// 会った記録は同じ人と会うたびに積んだもの (公演の半券の行、会場で交換していれば朱の線の札「会場で交換」)。
/// 並び・何回目か・札はコア (`cardMeetingViews`)。
///
/// 共通点 (同じ担当・同じ公演にいた回数・はじめて同じ会場) はコア (`producerCardCommon`)。
/// 公演の行を押すとその公演の詳細へ。
struct ReceivedCardDetailView: View {
    let cardId: String

    @Environment(AppDatabase.self) private var database
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var row: ReceivedProducerCard?
    @State private var card: ProducerCard?
    @State private var common: CardCommon?
    @State private var meetings: [CardMeetingView] = []
    /// 「この時の名刺に戻す」の確認中の記録。
    @State private var restoringMeeting: CardMeetingView?
    @State private var directory = ProducerCardDirectory()
    @State private var myOshi: Set<String> = []
    @State private var showOptions: [LedgerShowOption] = []
    @State private var loaded = false

    @State private var sheet: DetailDestination?
    @State private var editingMemo: ReceivedProducerCard?
    @State private var pickingShow = false
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
      ScrollViewReader { proxy in
        ImasPage {
            if let row, let card {
                let display = ProducerCardDisplay.view(
                    card, directory: directory, sharedWith: myOshi,
                    imageURL: { ProducerCardFiles.oshiImageURL(cardId: row.id, idolId: $0) },
                    portraitURL: ProducerCardFiles.cardPhotoURL(cardId: row.id),
                    portraitSource: ProducerCardFiles.cardPhotoSource(cardId: row.id),
                    face: ProducerCardDisplay.receivedFace(cardId: row.id),
                    payload: row.payload,
                    onOpenLink: { link in if let url = URL(string: link.url) { openURL(url) } },
                    onOpenOshi: { oshi in
                        if let idol = directory.idols[oshi.id] { sheet = .idol(idol) }
                    }
                )
                display
                display.details
                commonSection(row)
                meetingsSection.id("meetings")
                memoSection(row)
                photoSection(row)
            } else if loaded {
                ImasCard {
                    ImasEmptyState(.failed, title: "名刺を読めませんでした",
                                   message: "新しい版のアプリで作られた名刺かもしれません。アプリを最新にすると読めることがあります。")
                }
            } else {
                ImasInlineLoading()
            }
        }
        #if DEBUG
        .onChange(of: loaded) { _, done in
            // シミュレータでの見た目確認 (PRODUCER_CARD_SCROLL=meetings)。
            if done, let target = ProcessInfo.processInfo.environment["PRODUCER_CARD_SCROLL"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(target, anchor: .top) }
            }
        }
        #endif
      }
        .navigationTitle(card?.name ?? "名刺")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { pickingShow = true } label: { Label("受け取った公演を変える", systemImage: "ticket") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("この名刺を削除", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("その他")
            }
        }
        .sheet(item: $sheet) { dest in
            DetailSheetView(destination: dest).environment(database)
        }
        .sheet(item: $editingMemo) { CardMemoEditorView(card: $0) }
        .sheet(isPresented: $pickingShow) {
            LedgerShowPicker(options: showOptions) { option in
                pickingShow = false
                Task { await changeShow(option) }
            }
        }
        .imasConfirmDestructive("この名刺を削除しますか？", isPresented: $confirmDelete,
                                message: "名刺入れから消えます。写真と受け取った画像も消えます。") {
            Task { await delete() }
        }
        .confirmationDialog("この時の名刺に戻しますか？", isPresented: Binding(
            get: { restoringMeeting != nil }, set: { if !$0 { restoringMeeting = nil } }
        ), titleVisibility: .visible, presenting: restoringMeeting) { meeting in
            Button("この時の名刺に戻す") { Task { await restore(meeting) } }
            Button("キャンセル", role: .cancel) {}
        } message: { meeting in
            Text("名前やリンクなどの中身を \(meeting.date) に受け取った名刺に戻します。写真と担当の画像は今のままです。")
        }
        .imasErrorAlert("名刺を直せませんでした", message: $error)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .producerCardsChanged)) { _ in
            Task { await load() }
        }
        .trackScreen("received_card")
    }

    // MARK: - 共通点

    @ViewBuilder
    private func commonSection(_ row: ReceivedProducerCard) -> some View {
        let sharedNames = (common?.sharedOshiIds ?? []).compactMap { directory.idols[$0]?.name }
        let sharedShows = common?.sharedShowIds ?? []
        let first = sharedShows.first.flatMap { directory.shows[$0] }
        let received = row.showId.flatMap { directory.shows[$0] }
        ImasSection("あなたとの共通点") {
            ImasCardList {
                ImasValueRow(key: "同じ担当", value: sharedNames.isEmpty ? "なし" : sharedNames.joined(separator: "・"))
                    .environment(\.imasRowPosition, .first)
                ImasValueRow(key: "同じ公演にいた", value: "\(sharedShows.count)回", monospaced: true)
                    .environment(\.imasRowPosition, .following)
                if let first {
                    showRow(key: "はじめて同じ会場", show: first, value: "\(first.date.prefix(4)) · \(first.label)")
                }
                if let received {
                    showRow(key: "受け取った公演", show: received, value: received.label)
                } else {
                    Button { pickingShow = true } label: {
                        ImasValueRow(key: "受け取った公演", value: "選ぶ", isLink: true)
                    }
                    .buttonStyle(.imasRow)
                    .environment(\.imasRowPosition, .following)
                }
            }
        }
    }

    private func showRow(key: String, show: ProducerCardShowInfo, value: String) -> some View {
        Button {
            Task {
                if let found = try? await AppContainer.shared.showReading.show(id: show.id) { sheet = .show(found) }
            }
        } label: {
            ImasValueRow(key: key, value: value, isLink: true)
        }
        .buttonStyle(.imasRow)
        .environment(\.imasRowPosition, .following)
    }

    // MARK: - 会った記録

    /// 会った記録。そのときの名刺の中身が今と違う記録には「この時の名刺に戻す」を添える
    /// (同じ人として更新した名刺を、前の中身に戻せるように。戻せるかはコアの `cardMeetingRestorable`)。
    @ViewBuilder
    private var meetingsSection: some View {
        if !meetings.isEmpty, let row {
            ImasSection("会った記録") {
                ImasCardList {
                    ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                        let show = meeting.showId.flatMap { directory.shows[$0] }
                        if index > 0 { ImasRowDivider(inset: DS.sp4) }
                        ImasStubRow(
                            date: ImasStubDate(meeting.date),
                            title: show?.label ?? "公演に紐づかない",
                            subtitle: meeting.viaLabel,
                            badges: [meeting.badge.map { ImasBadgeSpec(text: $0, kind: .positive) },
                                     meeting.ordinalLabel.map { ImasBadgeSpec(text: $0, kind: .neutral) }]
                                .compactMap { $0 }
                        )
                        if cardMeetingRestorable(meetingPayload: meeting.payload, currentPayload: row.payload) {
                            ImasActionRow(title: "この時の名刺に戻す", systemImage: "arrow.uturn.backward") {
                                restoringMeeting = meeting
                            }
                            .environment(\.imasRowPosition, .following)
                        }
                    }
                }
            }
        }
    }

    // MARK: - メモ

    private func memoSection(_ row: ReceivedProducerCard) -> some View {
        ImasSection("メモ", actionTitle: "編集", actionSystemImage: "pencil", onAction: { editingMemo = row }) {
            ImasCard {
                Text(row.memo ?? "どこで会ったか・何を話したかを残しておけます。")
                    .imasText(row.memo == nil ? .note : .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 紙の名刺の写真

    @ViewBuilder
    private func photoSection(_ row: ReceivedProducerCard) -> some View {
        let photos = ProducerCardFiles.Side.allCases.compactMap { ProducerCardFiles.photoURL(cardId: row.id, side: $0) }
        if !photos.isEmpty {
            ImasSection("紙の名刺", footer: "写真は端末の中だけに置いています。") {
                VStack(spacing: DS.Space.gap) {
                    ForEach(photos, id: \.self) { url in
                        ImasCard(style: .inset) {
                            LazyImage(url: url) { state in
                                if let image = state.image {
                                    image.resizable().scaledToFit()
                                } else {
                                    DS.surface2.aspectRatio(91.0 / 55.0, contentMode: .fit)
                                }
                            }
                            .accessibilityLabel("紙の名刺の写真")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 読み書き

    private func load() async {
        let store = AppContainer.shared.producerCards
        guard let found = try? await store.receivedCard(id: cardId) else {
            row = nil
            loaded = true
            return
        }
        let decoded = found.card
        let record = try? await ProducerCardAssembler.loadMyRecord()
        var common: CardCommon?
        if let decoded, let record {
            common = producerCardCommon(card: decoded, myOshiIds: record.oshiIds, myAttended: record.summary.attendedPast)
        }
        let views = cardMeetingViews(meetings: ((try? await store.meetings(cardId: cardId)) ?? []).map(\.record))
        let showIds = [found.showId, decoded?.nextShowId, common?.sharedShowIds.first].compactMap { $0 }
            + views.compactMap(\.showId)
        directory = await ProducerCardDirectory.load(idolIds: decoded?.oshiIdolIds ?? [], showIds: showIds)
        showOptions = (try? await AppContainer.shared.ledgerReading.attendedShowOptions()) ?? []
        myOshi = Set(record?.oshiIds ?? [])
        self.common = common
        meetings = views
        row = found
        card = decoded
        loaded = true
    }

    /// 最後に会った記録の公演を変える (名刺の行にも写す)。
    private func changeShow(_ option: LedgerShowOption?) async {
        guard let row else { return }
        do {
            try await AppContainer.shared.producerCards.changeLatestMeetingShow(
                cardId: row.id, showId: option?.id, showDate: option?.date)
            NotificationCenter.default.post(name: .producerCardsChanged, object: nil)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restore(_ meeting: CardMeetingView) async {
        restoringMeeting = nil
        do {
            try await AppContainer.shared.producerCards.restorePayload(cardId: cardId, meetingId: meeting.id)
            NotificationCenter.default.post(name: .producerCardsChanged, object: nil)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        guard let row else { return }
        do {
            try await ProducerCardInbox.delete(row)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
