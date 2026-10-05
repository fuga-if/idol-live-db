#if DEBUG
import GRDB
import SwiftUI

/// P名刺の見た目をシミュレータで確かめる DEBUG 専用ハーネス (`CALL_GUIDE_PREVIEW` と同じ流儀)。
/// カメラはシミュレータで使えないので、見本の名刺を端末 DB に書いてから実画面を出す。
///
///     SIMCTL_CHILD_SCREENSHOT_MODE=1 SIMCTL_CHILD_PRODUCER_CARD_PREVIEW=case \
///     xcrun simctl launch <udid> com.fugaif.ImasLiveDB
struct ProducerCardPreviewHarness: View {
    enum Mode: String {
        case card, editor, exchange, read, receive, `case`, detail, print, paper
    }

    static var envMode: Mode? {
        ProcessInfo.processInfo.environment["PRODUCER_CARD_PREVIEW"].flatMap(Mode.init(rawValue:))
    }

    let mode: Mode
    @Environment(AppDatabase.self) private var database
    @State private var ready = false
    @State private var firstCardId: String?
    @State private var samplePayload: String?
    @State private var myCard: EncodedProducerCard?
    @State private var directory = ProducerCardDirectory()
    @State private var record: ProducerCardMyRecord?

    var body: some View {
        Group {
            if !ready {
                ImasLoadingState()
            } else {
                screen
            }
        }
        .task {
            await Samples.seed(database)
            firstCardId = try? await AppContainer.shared.producerCards.receivedCards().first?.id
            samplePayload = try? await AppContainer.shared.producerCards.receivedCards().first?.payload
            record = try? await ProducerCardAssembler.loadMyRecord()
            if let mine = try? await AppContainer.shared.producerCards.myCard(), let record {
                myCard = ProducerCardAssembler.encode(card: mine, record: record)
                directory = await ProducerCardDirectory.load(idolIds: myCard?.card.oshiIdolIds ?? [], showIds: [])
            }
            ready = true
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch mode {
        case .card: NavigationStack { MyProducerCardView() }
        case .editor:
            ProducerCardEditorView(card: (try? database.myProducerCard()) ?? .empty(), record: record) { _ in }
        case .exchange: ProducerCardExchangeView(myCard: myCard)
        case .read: ProducerCardExchangeView(myCard: myCard, initialMode: .read)
        case .receive:
            ProducerCardReceiveSheet(incoming: IncomingProducerCard(payload: samplePayload ?? "", images: [], via: .link))
        case .case: NavigationStack { CardCaseView() }
        case .detail: NavigationStack { ReceivedCardDetailView(cardId: firstCardId ?? "") }
        case .print:
            if let myCard { ProducerCardPrintView(card: myCard, directory: directory) }
        case .paper: PaperCardImportView()
        }
    }

    /// 見本の名刺。端末に入っている実在のアイドル・公演の id から組む (中身はダミーの名前)。
    enum Samples {
        @MainActor
        static func seed(_ db: AppDatabase) async {
            guard (try? db.allReceivedProducerCardIds().isEmpty) ?? true else { return }
            let idols: [String] = (try? await db.dbQueue.read { d in
                try String.fetchAll(d, sql: "SELECT id FROM idols WHERE color IS NOT NULL ORDER BY sort_order LIMIT 6")
            }) ?? []
            let shows: [(String, String)] = (try? await db.dbQueue.read { d in
                try Row.fetchAll(d, sql: "SELECT id, date FROM shows WHERE date <= '2026-10-05' ORDER BY date DESC LIMIT 4")
                    .map { ($0["id"] as String, $0["date"] as String) }
            }) ?? []
            guard idols.count >= 4, shows.count >= 3 else { return }
            let now = "2026-10-06T00:00:00Z"
            // 自分の担当と参加 (見本なので端末の印に直接書く)。
            try? await db.dbQueue.write { d in
                for id in idols.prefix(2) {
                    try d.execute(sql: """
                        INSERT OR REPLACE INTO user_marks (entity_type, entity_id, kind, bool_value, text_value, updated_at)
                        VALUES ('idol', ?, 'myPick', 1, NULL, ?)
                        """, arguments: [id, now])
                }
                for (id, _) in shows {
                    try d.execute(sql: """
                        INSERT OR REPLACE INTO user_marks (entity_type, entity_id, kind, bool_value, text_value, updated_at)
                        VALUES ('show', ?, 'attended', 1, 'live', ?)
                        """, arguments: [id, now])
                }
            }
            var mine = MyProducerCard.empty()
            mine.name = "ふがP"
            mine.message = "現地派・Pライブ皆勤目指してます"
            mine.sinceYear = 2014
            mine.links = [CardLink(kind: .x, value: "fuga_p"), CardLink(kind: .bluesky, value: "fuga.bsky.social")]
            try? db.saveMyProducerCard(mine)

            let refs = shows.map { CardShowRef(showId: $0.0, date: $0.1) }
            func card(_ name: String, _ message: String, oshi: [String], shows: Int, attended: [CardShowRef]) -> String {
                producerCardPayload(card: encodeProducerCard(input: ProducerCardInput(
                    name: name, message: message, sinceYear: 2011, oshiIdolIds: oshi,
                    links: [CardLink(kind: .x, value: "\(name.lowercased())_sample")], showCount: UInt32(shows),
                    songCount: 300, nextShowId: nil, attended: attended, issuedOn: "2026-10-05")).card)
            }
            let samples: [(String, ReceivedProducerCard.Source, (String, String)?, String?)] = [
                (card("しろくまP", "千早の歌を一生聴きたい", oshi: [idols[1]], shows: 63, attended: refs), .app, shows[0], "物販列で隣"),
                (card("あおいP", "", oshi: [idols[3]], shows: 21, attended: [refs[1]]), .app, shows[0], nil),
                (card("かるたP", "", oshi: [idols[2]], shows: 0, attended: []), .paper, shows[0], nil),
                (card("みどりP", "初現地でした", oshi: [idols[0], idols[2]], shows: 5, attended: [refs[2]]), .app, shows[2], nil),
            ]
            for (i, s) in samples.enumerated() {
                var row = ReceivedProducerCard.make(payload: s.0, source: s.1, showId: s.2?.0, showDate: s.2?.1, memo: s.3)
                row.receivedAt = "2026-10-05T2\(i):00:00Z"
                try? db.saveReceivedProducerCard(row)
            }
        }
    }
}
#endif
