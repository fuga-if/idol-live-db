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
        /// 紙に刷る画像を 5 デザインぶん書き出す (Documents/print_exports/。PNG そのものを見て確かめる)。
        case printExport
        /// 自分の名刺の下の詳細だけ (ひとこと・担当・リンク・記録。画面の下の方を撮る)。
        case details
        /// SNS に貼る P名刺の画像の画面 / 見本の画像を全部書き出す (Documents/profile_exports/)。
        case profile, profileExport
        /// 好きな曲を選ぶ画面 (`PROFILE_CHOSEN=1` で 3 曲を選んだ状態にする。書き出しにも効く)。
        case profileSongs
        /// 担当ブランドのはじめの案内 / 設定の画面。
        case brandRoles, brandSettings
        /// 名刺に載せる担当を選ぶ画面 (`PRODUCER_CARD_OSHI_CHOSEN` で選んだ状態にできる)。
        case oshiPicker
        /// 受け取りの確認で、名刺入れの名刺と同じ人か確かめるところ (名前と担当が同じで中身の違う名刺を受け取る)。
        case samePerson
    }

    /// P名刺の画像の見本の選択 (`PROFILE_SIZE=story`)。

    /// 自分の名刺のデザインを差し替えて撮る (`PRODUCER_CARD_DESIGN=pop`、`custom` は見本の自作の画像も置く)。
    static var envDesign: String? { ProcessInfo.processInfo.environment["PRODUCER_CARD_DESIGN"] }

    /// 自分の担当の人数 (`PRODUCER_CARD_OSHI=5`。既定は 2)。
    static var envOshiCount: Int {
        ProcessInfo.processInfo.environment["PRODUCER_CARD_OSHI"].flatMap(Int.init) ?? 2
    }

    /// 自分の担当を名前で決める (`PRODUCER_CARD_OSHI_NAMES=星井美希,上水流宇宙`)。
    /// 渡すと `PRODUCER_CARD_OSHI` より優先する (ブランドをまたぐ担当の表を撮る)。
    static var envOshiNames: [String]? {
        ProcessInfo.processInfo.environment["PRODUCER_CARD_OSHI_NAMES"]
            .map { $0.split(separator: ",").map(String.init) }
    }

    /// 名刺に載せる担当を名前で選んだ状態にする (`PRODUCER_CARD_OSHI_CHOSEN=星井美希`。担当の中から)。
    static var envOshiChosen: [String]? {
        ProcessInfo.processInfo.environment["PRODUCER_CARD_OSHI_CHOSEN"]
            .map { $0.split(separator: ",").map(String.init) }
    }

    /// 受け取った名刺の詳細で開く名刺の名前 (`PRODUCER_CARD_DETAIL=みどりP`。既定は写真のある名刺)。
    static var envDetail: String? { ProcessInfo.processInfo.environment["PRODUCER_CARD_DETAIL"] }

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
            if let key = Self.envDesign, var mine = try? database.myProducerCard() {
                mine.design = key
                try? database.saveMyProducerCard(mine)
                if key == "custom" { Samples.saveMyFaces() }
            }
            if let names = Self.envOshiChosen, var mine = try? database.myProducerCard() {
                let idols = (try? await AppContainer.shared.idolReading.idols(
                    ids: (try? await AppContainer.shared.markReading.markedEntityIds(entity: .idol, kind: .myPick)) ?? []
                )) ?? []
                mine.cardOshiChoice = names.compactMap { name in idols.first { $0.name == name }?.id }
                try? database.saveMyProducerCard(mine)
            }
            // 名刺の写真のある名刺を先に (写真の出方を見る)。
            let received = (try? await AppContainer.shared.producerCards.receivedCards()) ?? []
            let named = Self.envDetail.flatMap { name in received.first { $0.card?.name == name } }
            let first = named ?? received.first { ProducerCardFiles.cardPhotoURL(cardId: $0.id) != nil } ?? received.first
            firstCardId = first?.id
            samplePayload = first?.payload
            if [.profile, .profileExport, .profileSongs, .editor].contains(mode) {
                await Samples.seedProfile(database)
            }
            record = try? await ProducerCardAssembler.loadMyRecord()
            if let mine = try? await AppContainer.shared.producerCards.myCard(), let record {
                myCard = ProducerCardAssembler.encode(card: mine, record: record)
                directory = await ProducerCardDirectory.load(
                    idolIds: mode == .oshiPicker ? record.oshiIds : myCard?.card.oshiIdolIds ?? [], showIds: [])
            }
            ready = true
        }
    }

    /// 名前と担当はそのままで、ひとこととリンクを変えた名刺 (同じ人か確かめる名刺)。
    private static func remade(_ payload: String) -> String {
        guard var card = decodeProducerCard(text: payload) else { return payload }
        card.message = "名刺を作り直しました"
        card.links = [CardLink(kind: .x, value: "shirokuma_new"), CardLink(kind: .bluesky, value: "shirokuma.bsky.social")]
        return producerCardPayload(card: card)
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
        case .samePerson:
            ProducerCardReceiveSheet(incoming: IncomingProducerCard(payload: Self.remade(samplePayload ?? ""), images: [],
                                                                    via: .nearby))
        case .case: NavigationStack { CardCaseView() }
        case .detail: NavigationStack { ReceivedCardDetailView(cardId: firstCardId ?? "") }
        case .print:
            if let myCard { ProducerCardPrintView(card: myCard, directory: directory) }
        case .paper: PaperCardImportView()
        case .crop:
            CardPhotoCropSheet(image: Samples.portrait(), crop: ImasPortraitCrop(zoom: 1.4, center: CGPoint(x: 0.5, y: 0.4))) { _ in }
        case .profile: NavigationStack { ProducerCardImageView() }
        case .profileSongs:
            if let mine = try? database.myProducerCard() {
                NavigationStack {
                    FavoriteSongPickerView(chosen: mine.profile.songs) { ids in
                        var card = mine
                        card.profile.songs = ids
                        try? database.saveMyProducerCard(card)
                    }
                }
            }
        case .oshiPicker:
            if let mine = try? database.myProducerCard(), let record {
                NavigationStack {
                    CardOshiPickerView(chosen: mine.cardOshiChoice, oshi: record.oshiEntries,
                                       idols: directory.idols, brands: directory.brands) { _ in }
                }
            }
        case .brandRoles: BrandRoleSetupSheet()
        case .brandSettings: NavigationStack { BrandRoleSettingsView() }
        case .profileExport:
            Text(exportedCount.map { "書き出し \($0) 枚" } ?? "書き出し中")
                .task { exportedCount = await Samples.exportProfiles(database) }
        case .details:
            if let myCard {
                ImasPage {
                    ProducerCardDisplay.view(
                        myCard.card, directory: directory,
                        imageURL: { CustomImageService.shared.imageURL(for: $0) },
                        onOpenLink: { _ in }, onOpenOshi: nil
                    ).details
                }
            }
        case .printExport:
            Text(exportedCount.map { "書き出し \($0) 枚" } ?? "書き出し中")
                .task { exportedCount = await Samples.exportPrints(database) }
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
            let myOshi: [String]
            if let names = envOshiNames {
                let found: [String: String] = (try? await db.dbQueue.read { d in
                    try Dictionary(Row.fetchAll(d, sql: "SELECT id, name FROM idols WHERE name IN (\(names.map { _ in "?" }.joined(separator: ",")))",
                                                arguments: StatementArguments(names))
                        .map { ($0["name"] as String, $0["id"] as String) }, uniquingKeysWith: { a, _ in a })
                }) ?? [:]
                myOshi = names.compactMap { found[$0] }
            } else {
                myOshi = Array(idols.prefix(envOshiCount))
            }
            let now = "2026-10-06T00:00:00Z"
            // 自分の担当と参加 (見本なので端末の印に直接書く)。
            try? await db.dbQueue.write { d in
                for id in myOshi {
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
            mine.design = "formal"
            mine.qrUrl = "https://lit.link/fuga"
            try? db.saveMyProducerCard(mine)
            // `PRODUCER_CARD_PHOTO=x` で X のアイコンとして置く (丸く出るかを見る)。
            let photoOrigin: CardPhotoSource = ProcessInfo.processInfo.environment["PRODUCER_CARD_PHOTO"] == "x"
                ? .xIcon : .picked
            try? ProducerCardFiles.saveMyPhoto(source: portrait(), crop: ImasPortraitCrop(), origin: photoOrigin)
            // 担当の代表画像は実機と同じく大きな縦長・横長 (枠からはみ出さないかを見る)。
            // `PRODUCER_CARD_NO_OSHI_IMAGES=1` で置かない (画像の無い担当の判子を見る)。
            let skipImages = ProcessInfo.processInfo.environment["PRODUCER_CARD_NO_OSHI_IMAGES"] == "1"
            for (i, id) in myOshi.enumerated() where !skipImages && !CustomImageService.shared.hasCustomImage(for: id) {
                _ = try? await CustomImageService.shared.addImage(bigPicture(tall: i % 2 == 0, seed: i), for: id)
            }

            let refs = shows.map { CardShowRef(showId: $0.0, date: $0.1) }
            func card(_ name: String, _ message: String, oshi: [String], shows: Int, attended: [CardShowRef],
                      design: CardDesign? = nil) -> String {
                producerCardPayload(card: encodeProducerCard(input: ProducerCardInput(
                    name: name, message: message, sinceYear: 2011, oshiIdolIds: oshi,
                    links: [CardLink(kind: .x, value: "\(name.lowercased())_sample")], showCount: UInt32(shows),
                    songCount: 300, nextShowId: nil, attended: attended, issuedOn: "2026-10-05",
                    design: design, qrUrl: design == nil ? nil : "https://lit.link/shirokuma")).card)
            }
            let samples: [(String, ReceivedProducerCard.Source, (String, String)?, String?)] = [
                (card("しろくまP", "千早の歌を一生聴きたい", oshi: [idols[1]], shows: 63, attended: refs, design: .custom), .app, shows[0], "物販列で隣"),
                (card("あおいP", "", oshi: [idols[3]], shows: 21, attended: [refs[1]]), .app, shows[0], nil),
                (card("かるたP", "", oshi: [idols[2]], shows: 0, attended: []), .paper, shows[0], nil),
                (card("みどりP", "初現地でした", oshi: [idols[0], idols[2], idols[3], idols[4]], shows: 5, attended: [refs[2]], design: .pop), .app, shows[2], nil),
                (card("あかねP", "よろしくお願いいたします", oshi: [idols[2]], shows: 12, attended: [refs[0]], design: .formal), .app, shows[1], nil),
            ]
            // 受け取り方 (会場で交換の札が付くもの・付かないもの)。
            let vias: [CardReceiveVia] = [.nearby, .cameraQr, .paper, .link, .file]
            for (i, s) in samples.enumerated() {
                var fresh = ReceivedProducerCard.make(payload: s.0, source: s.1, showId: s.2?.0, showDate: s.2?.1,
                                                      memo: s.3, via: vias[i])
                fresh.receivedAt = "2026-10-05T2\(i):00:00Z"
                guard let row = try? await db.receiveProducerCard(fresh, matchSamePerson: s.1 == .app) else { continue }
                // しろくまP とは前の公演でも会っている (会った記録が 2 つ)。
                if i == 0 {
                    var earlier = ReceivedProducerCard.make(payload: s.0, source: .app, showId: shows[2].0,
                                                            showDate: shows[2].1, via: .cameraQr)
                    earlier.receivedAt = "2026-01-05T20:00:00Z"
                    _ = try? await db.receiveProducerCard(earlier, matchSamePerson: true)
                }
                if i == 0, let jpeg = ProducerCardFiles.jpeg(bigPicture(tall: true, seed: 1), maxPixels: 2000),
                   let oshiJpeg = ProducerCardFiles.jpeg(bigPicture(tall: true, seed: 0), maxPixels: 1600),
                   let front = ProducerCardFiles.jpeg(face(name: "しろくまP", back: false), maxPixels: 2000),
                   let back = ProducerCardFiles.jpeg(face(name: "しろくまP", back: true), maxPixels: 2000) {
                    try? ProducerCardFiles.saveImages(cardId: row.id, images: [
                        CardFileImage(idolId: "", jpeg: jpeg, kind: .photo),
                        CardFileImage(idolId: idols[1], jpeg: oshiJpeg, kind: .oshi),
                        CardFileImage(idolId: "", jpeg: front, kind: .faceFront),
                        CardFileImage(idolId: "", jpeg: back, kind: .faceBack),
                    ])
                }
            }
        }

        /// P名刺の画像の見本: お気に入りの曲・参加した公演 (担当の出た公演と最近の公演) を増やし、
        /// 次の現場を 1 つ入れる (何度呼んでも同じ)。
        @MainActor
        static func seedProfile(_ db: AppDatabase) async {
            let now = "2026-10-06T00:00:00Z"
            try? await db.dbQueue.write { d in
                // お気に入りは何十曲もある前提 (選ぶ画面で絞り込む)。付けた時刻は 1 曲ずつずらす。
                let songs = try String.fetchAll(d, sql: """
                    SELECT id FROM songs WHERE artwork_url IS NOT NULL ORDER BY release_date DESC LIMIT 40
                    """)
                for (i, id) in songs.enumerated() {
                    try d.execute(sql: """
                        INSERT OR REPLACE INTO user_marks (entity_type, entity_id, kind, bool_value, text_value, updated_at)
                        VALUES ('song', ?, 'favorite', 1, NULL, ?)
                        """, arguments: [id, String(format: "2026-09-%02dT00:00:00Z", 30 - i % 29)])
                }
                let oshiShows = try String.fetchAll(d, sql: """
                    SELECT DISTINCT s.id FROM shows s JOIN show_cast c ON c.show_id = s.id
                    WHERE c.idol_id = (SELECT entity_id FROM user_marks WHERE entity_type = 'idol' AND kind = 'myPick'
                                       AND bool_value = 1 ORDER BY entity_id LIMIT 1)
                      AND s.date <= '2026-10-05' AND s.date >= '2014-01-01'
                    ORDER BY s.date LIMIT 12
                    """)
                let recent = try String.fetchAll(d, sql: """
                    SELECT id FROM shows WHERE date <= '2026-10-05' ORDER BY date DESC LIMIT 8 OFFSET 4
                    """)
                let next = try String.fetchAll(d, sql: "SELECT id FROM shows WHERE date > '2026-10-06' ORDER BY date LIMIT 1")
                for id in oshiShows + recent + next {
                    try d.execute(sql: """
                        INSERT OR REPLACE INTO user_marks (entity_type, entity_id, kind, bool_value, text_value, updated_at)
                        VALUES ('show', ?, 'attended', 1, 'live', ?)
                        """, arguments: [id, now])
                }
            }
            guard var mine = try? db.myProducerCard() else { return }
            if let key = envDesign { mine.design = key }
            mine.profile = profileSample()
            if ProcessInfo.processInfo.environment["PROFILE_CHOSEN"] == "1" {
                // 新しい順の先頭ではない 3 曲を選んだ状態 (選んだ順に載るかを見る)。
                let favorites = (try? db.fetchMarkedEntityIds(entity: .song, kind: .favorite)) ?? []
                mine.profile.songs = [12, 3, 25].compactMap { favorites.indices.contains($0) ? favorites[$0] : nil }
            }
            try? db.saveMyProducerCard(mine)
        }

        static func profileSample() -> ProfileSheet {
            var sheet = profileSheetDefault()
            let env = ProcessInfo.processInfo.environment
            if env["PROFILE_SIZE"] == "story" { sheet.size = .story }
            sheet.hidden = []
            return sheet
        }

        /// 記録の少ない人の見本 (参加 1 公演・担当なし・お気に入りなし・写真なし)。
        static func sparse(_ m: ProfileSheetMaterials) -> ProfileSheetMaterials {
            var out = m
            out.record.attended = Array(m.record.attended.suffix(1))
            out.record.oshiNames = []
            out.record.oshiBrandIds = []
            out.record.favoriteSongs = []
            out.record.songCount = 12
            out.record.sinceYear = nil
            out.record.hasPhoto = false
            out.record.hasQr = false
            out.oshi = []
            out.portrait = nil
            out.qr = nil
            return out
        }

        /// 大きさ × 記録の多い/少ない、と縦長の大きな画像を P名刺の写真に入れたものを PNG に書き出す
        /// (Documents/profile_exports/)。担当ブランドはメイン 2 つ・担当 1 つの設定で描く。
        @MainActor
        static func exportProfiles(_ db: AppDatabase) async -> Int {
            guard let mine = try? db.myProducerCard() else { return 0 }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("profile_exports", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let roles = #"{"main":["765as","sc"],"oshi":["ml"]}"#
            var count = 0
            func write(_ materials: ProfileSheetMaterials, size: ProfileSheetSize, name: String) {
                var sheet = profileSample()
                sheet.size = size
                sheet.songs = mine.profile.songs
                let layout = profileSheetLayout(sheet: sheet, record: materials.record)
                guard let image = ProfileSheetAssembler.render(layout: layout, materials: materials),
                      let png = image.pngData() else { return }
                try? png.write(to: dir.appendingPathComponent(name))
                count += 1
            }
            // 担当の画像は実機と同じく大きな縦長・横長 (書き出しに担当の画像が出るかを見る)。
            let oshiIds = (try? await AppContainer.shared.markReading.markedEntityIds(entity: .idol, kind: .myPick)) ?? []
            for (i, id) in oshiIds.enumerated() where !CustomImageService.shared.hasCustomImage(for: id) {
                _ = try? await CustomImageService.shared.addImage(profileTallPhoto(seed: i), for: id)
            }
            var full = await ProfileSheetAssembler.load(card: mine)
            full.record.brandRolesJson = roles
            for fill in ["many", "few"] {
                let materials = fill == "few" ? sparse(full) : full
                for size in [ProfileSheetSize.portrait, .story] {
                    write(materials, size: size, name: "resume_\(size == .portrait ? "4x5" : "9x16")_\(fill).png")
                }
            }
            // 縦長の大きな画像 (1200×3000) を写真の欄に入れる (枠からはみ出さないか)。P名刺の写真は正方形に
            // 切って持つので、切る前の縦長の画像をそのまま渡して欄の枠で切れるかを見る。
            var tall = full
            tall.portrait = profileTallPhoto(seed: 1)
            write(tall, size: .portrait, name: "resume_4x5_tall_photo.png")
            write(tall, size: .story, name: "resume_9x16_tall_photo.png")
            return count
        }

        /// 実機の写真のような縦長の大きな画像 (1200×3000)。上下の端に黒い帯を付けて、枠で切った位置を見る。
        @MainActor
        static func profileTallPhoto(seed: Int) -> UIImage {
            let size = CGSize(width: 1200, height: 3000)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let base = portrait(seed: seed)
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                base.draw(in: CGRect(x: 0, y: 750, width: 1200, height: 1500))
                UIColor(white: 0.1, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 750))
                ctx.fill(CGRect(x: 0, y: 2250, width: 1200, height: 750))
            }
        }

        /// 5 デザインの紙に刷る画像 (表・裏) を書き出す (Documents/print_exports/)。担当を大きく は担当の
        /// 人数を変えても書き出す (`PRODUCER_CARD_OSHI` の人数で `oshi_front.png`)。
        @MainActor
        static func exportPrints(_ db: AppDatabase) async -> Int {
            guard var mine = try? db.myProducerCard() else { return 0 }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("print_exports", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            saveMyFaces()
            var count = 0
            for design in ["pass", "formal", "pop", "oshi", "custom"] {
                mine.design = design
                guard let record = try? await ProducerCardAssembler.loadMyRecord(),
                      let encoded = ProducerCardAssembler.encode(card: mine, record: record) else { continue }
                let directory = await ProducerCardDirectory.load(idolIds: encoded.card.oshiIdolIds, showIds: [])
                let materials = ProducerCardPrintMaterials.loadMine(card: encoded.card)
                for back in [ProducerCardPrintSheet.Back.exchange, .own] {
                    var sheet = ProducerCardPrintSheet(card: encoded, directory: directory, materials: materials, back: back)
                    sheet.qr = ImasQRCode.render(sheet.backText)
                    let images = sheet.renderImages()
                    for (side, image) in zip(["front", "back_\(back == .own ? "own" : "exchange")"], images) {
                        if side == "front" && back == .own { continue }
                        guard let png = image.pngData() else { continue }
                        try? png.write(to: dir.appendingPathComponent("\(design)_\(side).png"))
                        count += 1
                    }
                }
            }
            return count
        }

        /// 実機の担当の画像のような大きな写真 (縦長 1200×3000 / 横長 3000×1200)。上下・左右の端に印を付けて、
        /// 枠で切った位置と、枠からはみ出していないかを見る。
        @MainActor
        static func bigPicture(tall: Bool, seed: Int) -> UIImage {
            let size = tall ? CGSize(width: 1200, height: 3000) : CGSize(width: 3000, height: 1200)
            // 見本の写真の地 (写真の代わりなので DS の色ではない)。
            let colors: [UIColor] = [UIColor(hue: 0.95, saturation: 0.45, brightness: 0.85, alpha: 1),
                                     UIColor(hue: 0.55, saturation: 0.45, brightness: 0.8, alpha: 1)]
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                colors[seed % colors.count].setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                UIColor(white: 0.1, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 120))
                ctx.fill(CGRect(x: 0, y: size.height - 120, width: size.width, height: 120))
                let side = min(size.width, size.height) * 0.7
                let symbol = UIImage(systemName: "person.fill",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: side))?
                    .withTintColor(UIColor(white: 1, alpha: 1), renderingMode: .alwaysOriginal)
                symbol?.draw(in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side))
            }
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

        /// 自分の名刺の見本の自作の画像 (表・裏) を置く。
        @MainActor
        static func saveMyFaces() {
            guard ProducerCardFiles.myFaceURL(.front) == nil else { return }
            try? ProducerCardFiles.saveMyFace(face(name: "ふがP", back: false), side: .front)
            try? ProducerCardFiles.saveMyFace(face(name: "ふがP", back: true), side: .back)
        }

        /// 見本の自作の名刺の画像 (91:55。表は名前、裏は QR)。
        @MainActor
        static func face(name: String, back: Bool) -> UIImage {
            let size = CGSize(width: 1820, height: 1100)
            // 見本の画像の色 (自作の画像の代わりなので DS の色ではない)。
            let navy = UIColor(hue: 0.64, saturation: 0.67, brightness: 0.36, alpha: 1)
            let gold = UIColor(hue: 0.12, saturation: 0.61, brightness: 0.93, alpha: 1)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                (back ? gold : navy).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                if back {
                    if let qr = ImasQRCode.render("https://lit.link/\(name == "ふがP" ? "fuga" : "shirokuma")") {
                        let box = CGRect(x: 1100, y: 250, width: 600, height: 600)
                        UIColor(white: 1, alpha: 1).setFill()
                        ctx.fill(box.insetBy(dx: -30, dy: -30))
                        ctx.cgContext.interpolationQuality = .none
                        qr.withTintColor(UIColor(white: 0, alpha: 1), renderingMode: .alwaysOriginal).draw(in: box)
                    }
                    ("SEE YOU AT THE LIVE" as NSString).draw(at: CGPoint(x: 120, y: 480), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 80, weight: .heavy), .foregroundColor: navy])
                } else {
                    gold.setFill()
                    ctx.fill(CGRect(x: 0, y: 900, width: size.width, height: 40))
                    (name as NSString).draw(at: CGPoint(x: 140, y: 330), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 260, weight: .heavy), .foregroundColor: UIColor(white: 1, alpha: 1)])
                    ("PRODUCER / SINCE 2011" as NSString).draw(at: CGPoint(x: 150, y: 680), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 64, weight: .semibold), .foregroundColor: gold])
                }
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
