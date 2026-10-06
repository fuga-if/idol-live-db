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
        case card, editor, exchange, read, receive, `case`, detail, print, paper, crop, corners
        /// プロフィール帳の画面 / 編集シート / 見本の画像を全部書き出す (Documents/profile_exports/)。
        case profile, profileEditor, profileExport
    }

    /// プロフィール帳の見本の中身 (`PROFILE_FILL=many|few`、`PROFILE_STYLE=career`、`PROFILE_SIZE=story`)。
    static var envProfileFill: String { ProcessInfo.processInfo.environment["PROFILE_FILL"] ?? "many" }

    /// 自分の名刺の書体を差し替えて撮る (`PRODUCER_CARD_FONT=pop`)。
    static var envFont: String? { ProcessInfo.processInfo.environment["PRODUCER_CARD_FONT"] }

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
    @State private var profileMaterials: ProfileSheetMaterials?
    @State private var exportedCount: Int?

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
            if let key = Self.envFont, var mine = try? database.myProducerCard() {
                mine.nameFont = key
                try? database.saveMyProducerCard(mine)
            }
            // 名刺の写真のある名刺を先に (写真の出方を見る)。
            let received = (try? await AppContainer.shared.producerCards.receivedCards()) ?? []
            let first = received.first { ProducerCardFiles.cardPhotoURL(cardId: $0.id) != nil } ?? received.first
            firstCardId = first?.id
            samplePayload = first?.payload
            if [.profile, .profileEditor, .profileExport].contains(mode) {
                await Samples.seedProfile(database)
            }
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
        case .crop:
            CardPhotoCropSheet(image: Samples.portrait(), crop: ImasPortraitCrop(zoom: 1.4, center: CGPoint(x: 0.5, y: 0.4))) { _ in }
        case .profile: NavigationStack { ProfileSheetView() }
        case .profileEditor:
            if let mine = try? database.myProducerCard() {
                ProfileSheetEditorView(card: mine, materials: profileMaterials ?? .empty) { _ in }
                    .task { profileMaterials = await ProfileSheetAssembler.load(card: mine, sheet: mine.profile) }
            }
        case .profileExport:
            Text(exportedCount.map { "書き出し \($0) 枚" } ?? "書き出し中")
                .task { exportedCount = await Samples.exportProfiles(database) }
        case .corners:
            PaperCardCornerSheet(image: Samples.paperPhoto(), corners: [
                CGPoint(x: 0.14, y: 0.24), CGPoint(x: 0.86, y: 0.2), CGPoint(x: 0.9, y: 0.72), CGPoint(x: 0.1, y: 0.76),
            ]) { _ in }
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
            mine.nameFont = "mincho"
            mine.qrUrl = "https://lit.link/fuga"
            try? db.saveMyProducerCard(mine)
            try? ProducerCardFiles.saveMyPhoto(source: portrait(), crop: ImasPortraitCrop())

            let refs = shows.map { CardShowRef(showId: $0.0, date: $0.1) }
            func card(_ name: String, _ message: String, oshi: [String], shows: Int, attended: [CardShowRef],
                      font: CardNameFont? = nil) -> String {
                producerCardPayload(card: encodeProducerCard(input: ProducerCardInput(
                    name: name, message: message, sinceYear: 2011, oshiIdolIds: oshi,
                    links: [CardLink(kind: .x, value: "\(name.lowercased())_sample")], showCount: UInt32(shows),
                    songCount: 300, nextShowId: nil, attended: attended, issuedOn: "2026-10-05",
                    nameFont: font, qrUrl: font == nil ? nil : "https://lit.link/shirokuma")).card)
            }
            let samples: [(String, ReceivedProducerCard.Source, (String, String)?, String?)] = [
                (card("しろくまP", "千早の歌を一生聴きたい", oshi: [idols[1]], shows: 63, attended: refs, font: .maru), .app, shows[0], "物販列で隣"),
                (card("あおいP", "", oshi: [idols[3]], shows: 21, attended: [refs[1]]), .app, shows[0], nil),
                (card("かるたP", "", oshi: [idols[2]], shows: 0, attended: []), .paper, shows[0], nil),
                (card("みどりP", "初現地でした", oshi: [idols[0], idols[2]], shows: 5, attended: [refs[2]]), .app, shows[2], nil),
            ]
            for (i, s) in samples.enumerated() {
                var row = ReceivedProducerCard.make(payload: s.0, source: s.1, showId: s.2?.0, showDate: s.2?.1, memo: s.3)
                row.receivedAt = "2026-10-05T2\(i):00:00Z"
                try? db.saveReceivedProducerCard(row)
                if i == 0, let jpeg = ProducerCardFiles.jpeg(portrait(seed: 1)) {
                    try? ProducerCardFiles.saveImages(cardId: row.id, images: [CardFileImage(idolId: "", jpeg: jpeg, kind: .photo)])
                }
            }
        }

        /// プロフィール帳の見本: お気に入りの曲・参加した公演を増やし、次の現場を 1 つ入れ、
        /// 自分の名刺にプロフィール帳の中身を書く (何度呼んでも同じ)。
        @MainActor
        static func seedProfile(_ db: AppDatabase) async {
            let now = "2026-10-06T00:00:00Z"
            try? await db.dbQueue.write { d in
                let songs = try String.fetchAll(d, sql: """
                    SELECT id FROM songs WHERE artwork_url IS NOT NULL ORDER BY release_date DESC LIMIT 5
                    """)
                for id in songs {
                    try d.execute(sql: """
                        INSERT OR REPLACE INTO user_marks (entity_type, entity_id, kind, bool_value, text_value, updated_at)
                        VALUES ('song', ?, 'favorite', 1, NULL, ?)
                        """, arguments: [id, now])
                }
                let past = try String.fetchAll(d, sql: """
                    SELECT id FROM shows WHERE date <= '2026-10-05' AND date >= '2014-01-01'
                    ORDER BY date LIMIT 1 OFFSET 40
                    """) + String.fetchAll(d, sql: """
                    SELECT id FROM shows WHERE date <= '2026-10-05' ORDER BY date DESC LIMIT 14 OFFSET 4
                    """)
                let next = try String.fetchAll(d, sql: "SELECT id FROM shows WHERE date > '2026-10-06' ORDER BY date LIMIT 1")
                for id in past + next {
                    try d.execute(sql: """
                        INSERT OR REPLACE INTO user_marks (entity_type, entity_id, kind, bool_value, text_value, updated_at)
                        VALUES ('show', ?, 'attended', 1, 'live', ?)
                        """, arguments: [id, now])
                }
            }
            guard var mine = try? db.myProducerCard() else { return }
            if let key = envFont { mine.nameFont = key }
            mine.profile = profileSample(fill: envProfileFill, songs: (try? await AppContainer.shared.markReading
                .markedEntityIds(entity: .song, kind: .favorite)) ?? [])
            try? db.saveMyProducerCard(mine)
        }

        static func profileSample(fill: String, songs: [String]) -> ProfileSheet {
            var sheet = profileSheetDefault()
            let env = ProcessInfo.processInfo.environment
            if env["PROFILE_STYLE"] == "career" { sheet.style = .career }
            if env["PROFILE_SIZE"] == "story" { sheet.size = .story }
            sheet.furigana = "ふがぴー"
            sheet.favoriteSongIds = Array(songs.prefix(3))
            let few: [(ProfileQuestion, String)] = [
                (.trigger, "アニメで見たステージに心をつかまれて"),
                (.message, "同僚募集中です。気軽に声をかけてください"),
            ]
            let many: [(ProfileQuestion, String)] = few + [
                (.oshiLove, "まっすぐなところ。歌声に何度も背中を押されてきました"),
                (.bestLive, "はじめての現地。1 曲目のイントロで泣いた"),
                (.favoriteCall, "サビ前のクラップ"),
                (.expedition, "夜行バスで行った西武ドーム。帰りは始発"),
                (.landmark, "担当色のタオルを首に巻いています"),
            ]
            sheet.answers = (fill == "few" ? few : many).map {
                ProfileAnswer(question: $0.0, prompt: "", text: $0.1)
            }
            if fill == "few" {
                sheet.hidden = [.qr, .songs]
            } else {
                sheet.hidden = []
                sheet.brandOn = ["sc"]
            }
            return sheet
        }

        /// 様式 × 大きさ × 書体 × 欄の多い/少ないを全部 PNG に書き出す (Documents/profile_exports/)。
        @MainActor
        static func exportProfiles(_ db: AppDatabase) async -> Int {
            guard var mine = try? db.myProducerCard() else { return 0 }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("profile_exports", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let songs = (try? await AppContainer.shared.markReading.markedEntityIds(entity: .song, kind: .favorite)) ?? []
            var count = 0
            for font in ["hand", "pop", "gothic"] {
                mine.nameFont = font
                for fill in ["many", "few"] {
                    let base = profileSample(fill: fill, songs: songs)
                    let materials = await ProfileSheetAssembler.load(card: mine, sheet: base)
                    for style in [ProfileSheetStyle.resume, .career] {
                        for size in [ProfileSheetSize.portrait, .story] {
                            if font != "hand" && (fill == "few" || size == .story) { continue }
                            var sheet = base
                            sheet.style = style
                            sheet.size = size
                            let layout = profileSheetLayout(sheet: sheet, record: materials.record)
                            guard let image = ProfileSheetAssembler.render(layout: layout, materials: materials),
                                  let png = image.pngData() else { continue }
                            let name = "\(style == .resume ? "resume" : "career")_\(size == .portrait ? "4x5" : "9x16")_\(fill)_\(font).png"
                            try? png.write(to: dir.appendingPathComponent(name))
                            count += 1
                        }
                    }
                }
            }
            return count
        }

        /// 見本の写真 (人の形の記号を色の地に置いたもの)。
        @MainActor
        static func portrait(seed: Int = 0) -> UIImage {
            let size = CGSize(width: 1200, height: 1500)
            // 見本の写真の地 (写真の代わりなので DS の色ではない)。
            let colors: [UIColor] = [UIColor(hue: 0.58, saturation: 0.35, brightness: 0.85, alpha: 1),
                                     UIColor(hue: 0.08, saturation: 0.35, brightness: 0.9, alpha: 1)]
            return UIGraphicsImageRenderer(size: size).image { ctx in
                colors[seed % colors.count].setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let symbol = UIImage(systemName: "person.fill",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 700))?
                    .withTintColor(UIColor(white: 1, alpha: 1), renderingMode: .alwaysOriginal)
                symbol?.draw(in: CGRect(x: 250, y: 380, width: 700, height: 760))
            }
        }

        /// 見本の「斜めから撮った紙の名刺」。
        @MainActor
        static func paperPhoto() -> UIImage {
            let size = CGSize(width: 1500, height: 1100)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 210, y: 264))
                path.addLine(to: CGPoint(x: 1290, y: 220))
                path.addLine(to: CGPoint(x: 1350, y: 792))
                path.addLine(to: CGPoint(x: 150, y: 836))
                path.close()
                UIColor(white: 1, alpha: 1).setFill()
                path.fill()
                ("かるたP" as NSString).draw(at: CGPoint(x: 400, y: 450),
                                           withAttributes: [.font: UIFont.boldSystemFont(ofSize: 120)])
            }
        }
    }
}
#endif
