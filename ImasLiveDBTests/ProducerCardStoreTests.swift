import UIKit
import GRDB
import XCTest
@testable import ImasLiveDB

/// P名刺 (自分の名刺・名刺入れ) の端末 DB とバックアップの往復のテスト。
///
/// 名刺は端末にしか無いので、復元は「無い行を足すだけ」で、既にある名刺のメモや
/// 書き直した自分の名刺を古いもので上書きしないこと。
@MainActor
final class ProducerCardStoreTests: XCTestCase {

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(dbQueue: makeMigratedDatabase())
    }

    /// コアで組んだ本物の名刺の中身。
    private func payload(name: String) -> String {
        let input = ProducerCardInput(
            name: name, message: "", sinceYear: 2014, oshiIdolIds: ["765_haruka"],
            links: [CardLink(kind: .x, value: "fuga_p")], showCount: 3, songCount: 10,
            nextShowId: nil, attended: [], issuedOn: "2026-10-06")
        return producerCardPayload(card: encodeProducerCard(input: input).card)
    }

    private func received(_ id: String, name: String, memo: String? = nil) -> ReceivedProducerCard {
        ReceivedProducerCard(id: id, payload: payload(name: name), source: "app", showId: "sh_1",
                             showDate: "2026-10-05", memo: memo, receivedAt: "2026-10-05T21:00:00Z",
                             updatedAt: "2026-10-05T21:00:00Z")
    }

    func testMyCardRoundTripsLinksAndHiddenFields() throws {
        let db = try makeDatabase()
        XCTAssertNil(try db.myProducerCard())
        var card = MyProducerCard.empty()
        card.name = "ふがP"
        card.sinceYear = 2014
        card.links = [CardLink(kind: .x, value: "fuga_p"), CardLink(kind: .bluesky, value: "fuga.bsky.social")]
        card.hidden = [.attended, .songCount]
        try db.saveMyProducerCard(card)

        let loaded = try XCTUnwrap(db.myProducerCard())
        XCTAssertEqual(loaded.name, "ふがP")
        XCTAssertEqual(loaded.links, card.links)
        XCTAssertEqual(loaded.hidden, [.attended, .songCount])
        XCTAssertTrue(loaded.shows(.oshi))
        XCTAssertFalse(loaded.shows(.attended))
    }

    /// 判子の下のブランド名は既定で外す。足す前の行 (保存の文字列に無い) も外れたまま、
    /// 「刷る」と決めたときだけ保存の文字列に書き、名刺の中身に乗る。
    func testBrandLabelsAreOptInAndRideOnTheCard() throws {
        let db = try makeDatabase()
        var card = MyProducerCard.empty()
        card.name = "ふがP"
        card.hiddenFields = "attended" // 足す前の版が書いた行
        XCTAssertFalse(card.shows(.brandLabels))
        XCTAssertTrue(card.hidden.contains(.attended))
        let record = ProducerCardMyRecord(oshiIds: [], attended: [], songCount: 0)
        XCTAssertFalse(ProducerCardAssembler.input(card: card, record: record).showBrandLabels)

        card.hidden.remove(.brandLabels)
        XCTAssertTrue(card.shows(.brandLabels))
        XCTAssertEqual(card.hiddenFields, "attended,brand_labels")
        try db.saveMyProducerCard(card)
        let loaded = try XCTUnwrap(db.myProducerCard())
        XCTAssertTrue(loaded.shows(.brandLabels))
        XCTAssertFalse(loaded.shows(.attended))
        let encoded = try XCTUnwrap(ProducerCardAssembler.encode(card: loaded, record: record))
        XCTAssertTrue(try XCTUnwrap(decodeProducerCard(text: encoded.url)).showBrandLabels)
    }

    // MARK: - 名刺に載せる担当の選択

    private func oshiEntry(_ id: String, brand: String) -> CardOshiEntry {
        CardOshiEntry(idolId: id, name: id, brandId: brand, brandLabel: brand)
    }

    /// 名刺に載せる担当は自分の名刺の行に持つ。まだ選んでいなければブランドごとに 1 人、選べばその人だけ
    /// その順に載る。担当から外した人は抜け、全員抜ければ自動の選び方に戻る (規則はコア)。
    func testOshiChoiceRoundTripsAndDrivesTheCard() throws {
        let db = try makeDatabase()
        let entries = [oshiEntry("haruka", brand: "765as"), oshiEntry("chihaya", brand: "765as"),
                       oshiEntry("sora", brand: "876"), oshiEntry("temari", brand: "gakuen"),
                       oshiEntry("momoko", brand: "ml"), oshiEntry("miki", brand: "765as"),
                       oshiEntry("misuzu", brand: "gakuen")]
        let record = ProducerCardMyRecord(oshiIds: entries.map(\.idolId), oshiEntries: entries,
                                          attended: [], songCount: 0)
        var card = MyProducerCard.empty()
        card.name = "ふがP"
        XCTAssertNil(card.cardOshiChoice)
        XCTAssertEqual(ProducerCardAssembler.input(card: card, record: record).oshiIdolIds,
                       ["haruka", "chihaya", "sora", "temari", "momoko"], "まだ選んでいなければブランドごとに 1 人")

        card.cardOshiChoice = ["miki"]
        try db.saveMyProducerCard(card)
        let loaded = try XCTUnwrap(db.myProducerCard())
        XCTAssertEqual(loaded.cardOshiChoice, ["miki"])
        let encoded = try XCTUnwrap(ProducerCardAssembler.encode(card: loaded, record: record))
        XCTAssertEqual(try XCTUnwrap(decodeProducerCard(text: encoded.url)).oshiIdolIds, ["miki"], "1 人だけ選べば 1 人")

        // 上限で切る。担当から外した人は抜ける。
        card.cardOshiChoice = ["misuzu", "gone", "momoko", "temari", "sora", "chihaya", "haruka"]
        XCTAssertEqual(ProducerCardAssembler.input(card: card, record: record).oshiIdolIds,
                       ["misuzu", "momoko", "temari", "sora", "chihaya"])
        card.cardOshiChoice = ["gone"]
        XCTAssertEqual(ProducerCardAssembler.input(card: card, record: record).oshiIdolIds,
                       ["haruka", "chihaya", "sora", "temari", "momoko"], "全員外れたら自動の選び方")
        // 空の選択は持たない (まだ選んでいないに戻る)。
        card.cardOshiChoice = []
        XCTAssertNil(card.cardOshiJson)
    }

    /// P名刺の編集で直した好きな曲は保存の時点の行に重ね、画像の選択 (大きさ・外した欄) は今の行のまま。
    func testEditKeepsLatestImageChoicesAndTakesEditedSongs() {
        var opened = MyProducerCard.empty()
        opened.name = "ふがP"
        var edited = opened
        edited.profile.songs = ["s2", "s1"]
        var latest = opened
        var sheet = latest.profile
        sheet.size = .story
        sheet.hidden = [.qr]
        latest.profile = sheet
        let merged = edited.applyingEdit(onto: latest)
        XCTAssertEqual(merged.profile.songs, ["s2", "s1"])
        XCTAssertEqual(merged.profile.size, .story)
        XCTAssertEqual(merged.profile.hidden, [.qr])
        XCTAssertEqual(edited.applyingEdit(onto: nil), edited)
    }

    /// P名刺の画像の選択と好きな曲は自分の名刺の行に持つ。まだ選んでいなければ既定の中身 (規則はコア)。
    func testProfileSheetRoundTripsOnMyCard() throws {
        let db = try makeDatabase()
        var card = MyProducerCard.empty()
        card.name = "ふがP"
        XCTAssertEqual(card.profile, profileSheetDefault())
        var sheet = card.profile
        sheet.size = .story
        sheet.hidden = [.songs, .qr] // 保存の形の並び (選ぶ画面の順)
        card.profile = sheet
        try db.saveMyProducerCard(card)
        XCTAssertEqual(try db.myProducerCard()?.profile, sheet)

        // P名刺を直して保存しても、画像の選択は消えない。
        var edited = try XCTUnwrap(db.myProducerCard())
        edited.message = "現地派"
        try db.saveMyProducerCard(edited)
        XCTAssertEqual(try db.myProducerCard()?.profile, sheet)
    }

    /// 職務経歴書・プロフィール帳 (今の P名刺の画像) の中の丸の上書きがあった頃の保存も落ちずに読める (やめた項目は読み捨てる)。
    func testOldProfileJsonWithCareerStyleStillReads() throws {
        let db = try makeDatabase()
        var card = MyProducerCard.empty()
        card.name = "ふがP"
        card.profileJson = #"{"style":"career","size":"story","hidden":["qr","oshi_heard","yearly"],"brandOn":["sc"],"brandMain":"sc"}"#
        try db.saveMyProducerCard(card)
        let loaded = try XCTUnwrap(db.myProducerCard())
        XCTAssertEqual(loaded.profile.size, .story)
        XCTAssertEqual(loaded.profile.hidden, [.qr])
        XCTAssertEqual(profileSheetLayout(sheet: loaded.profile, record: ProfileSheetMaterials.empty.record).title, "履歴書")
    }

    /// 履歴書に載せる好きな曲は曲 id の並びで自分の名刺の行に持つ。選ぶ前の保存 (キーなし) は「まだ選んでいない」。
    func testChosenProfileSongsRoundTripAndOldJsonReadsAsUnchosen() throws {
        let db = try makeDatabase()
        var card = MyProducerCard.empty()
        card.name = "ふがP"
        card.profileJson = #"{"size":"portrait","hidden":["qr","peak_year","prefectures"],"songs":["自分で書いた曲"]}"#
        try db.saveMyProducerCard(card)
        var loaded = try XCTUnwrap(db.myProducerCard())
        XCTAssertNil(loaded.profile.songs, "前の版の保存は、まだ選んでいない")
        XCTAssertEqual(loaded.profile.hidden, [.qr], "やめた欄 (いちばん通った年・都道府県) は読み捨てる")

        var sheet = loaded.profile
        sheet.songs = ["s3", "s1"]
        loaded.profile = sheet
        try db.saveMyProducerCard(loaded)
        XCTAssertEqual(try db.myProducerCard()?.profile.songs, ["s3", "s1"])

        // 全部外した (空) は「まだ選んでいない」と区別して残る。
        sheet.songs = []
        loaded.profile = sheet
        try db.saveMyProducerCard(loaded)
        XCTAssertEqual(try db.myProducerCard()?.profile.songs, [])
    }

    /// お気に入りから外した曲は、選んでいても履歴書に載らない (お気に入りの時刻は端末のマークから引く)。
    func testUnfavoritedSongsDropOutOfTheProfileSheet() async throws {
        let db = try makeDatabase()
        try db.upsertUserMark(entity: .song, id: "s1", kind: .favorite, boolValue: true)
        try db.upsertUserMark(entity: .song, id: "s2", kind: .favorite, boolValue: true)
        try db.upsertUserMark(entity: .song, id: "s3", kind: .favorite, boolValue: true)
        try db.upsertUserMark(entity: .song, id: "s2", kind: .favorite, boolValue: false)
        let times = try await db.fetchMarkedTimesAsync(entity: .song, kind: .favorite)
        XCTAssertEqual(Set(times.keys), ["s1", "s3"])

        let favorites = times.keys.sorted().map {
            ProfileSongInput(id: $0, title: "曲\($0)", favoritedAt: times[$0] ?? "")
        }
        var record = ProfileSheetMaterials.empty.record
        record.today = "2026-10-06"
        record.favoriteSongs = favorites
        var sheet = profileSheetDefault()
        sheet.songs = ["s2", "s3", "s1"]
        let layout = profileSheetLayout(sheet: sheet, record: record)
        XCTAssertEqual(layout.sections.first?.entries.first?.text, "「曲s3」「曲s1」")

        // 選ぶ画面: 載っている曲を押すと外れ、上限までは末尾に足す (規則はコア)。
        XCTAssertEqual(favoriteSongToggle(chosen: ["s3"], favorites: favorites, songId: "s1"), ["s3", "s1"])
        XCTAssertEqual(favoriteSongToggle(chosen: ["s3", "s1"], favorites: favorites, songId: "s3"), ["s1"])
        XCTAssertEqual(favoriteSongPicks(chosen: ["s2", "s1"], favorites: favorites).picked.map(\.id), ["s1"])
    }

    func testReceivedCardsSaveFindByPayloadAndDelete() async throws {
        let db = try makeDatabase()
        let a = received("c1", name: "しろくまP")
        try db.saveReceivedProducerCard(a)
        try db.saveReceivedProducerCard(received("c2", name: "あおいP"))

        XCTAssertEqual(try db.allReceivedProducerCards().count, 2)
        let found = try await db.receivedProducerCardAsync(payload: a.payload)
        XCTAssertEqual(found?.id, "c1")
        XCTAssertEqual(found?.card?.name, "しろくまP")

        var edited = a
        edited.memo = "物販列で隣"
        try db.saveReceivedProducerCard(edited)
        XCTAssertEqual(try db.allReceivedProducerCards().count, 2, "同じ id は上書き")

        try db.deleteReceivedProducerCard(id: "c1")
        XCTAssertEqual(try db.allReceivedProducerCardIds(), ["c2"])
    }

    func testRestoreAddsOnlyMissingCardsAndKeepsMyCard() throws {
        let db = try makeDatabase()
        try db.saveReceivedProducerCard(received("c1", name: "しろくまP", memo: "新しいメモ"))
        let added = try db.restoreReceivedProducerCardsIfAbsent([
            received("c1", name: "しろくまP", memo: "古いメモ"),
            received("c2", name: "あおいP"),
        ])
        XCTAssertEqual(added, 1)
        let memos = Dictionary(uniqueKeysWithValues: try db.allReceivedProducerCards().map { ($0.id, $0.memo) })
        XCTAssertEqual(memos["c1"], "新しいメモ", "既にある名刺のメモを古いもので上書きしない")

        var mine = MyProducerCard.empty()
        mine.name = "書き直した名前"
        try db.saveMyProducerCard(mine)
        var old = MyProducerCard.empty()
        old.name = "古い名前"
        XCTAssertEqual(try db.restoreMyProducerCardsIfAbsent([old]), 0)
        XCTAssertEqual(try db.myProducerCard()?.name, "書き直した名前")
    }

    /// 同じ相手の名刺 (中身が同じ) は、別の id で届いても 1 枚にする。
    func testSamePayloadIsNotStoredTwice() async throws {
        let db = try makeDatabase()
        let first = try await db.insertReceivedProducerCardIfNew(received("c1", name: "しろくまP"))
        let second = try await db.insertReceivedProducerCardIfNew(received("c2", name: "しろくまP"))
        XCTAssertEqual(first.id, "c1")
        XCTAssertEqual(second.id, "c1", "同じ中身なら既にある名刺を返す")
        XCTAssertEqual(try db.restoreReceivedProducerCardsIfAbsent([received("c3", name: "しろくまP")]), 0)
        XCTAssertEqual(try db.allReceivedProducerCardIds(), ["c1"])
    }

    /// 書き出したバックアップを空の端末に取り込むと、名刺入れと自分の名刺が戻る。
    func testBackupRoundTripRestoresProducerCards() throws {
        let source = try makeDatabase()
        var mine = MyProducerCard.empty()
        mine.name = "ふがP"
        mine.message = "現地派"
        mine.sinceYear = 2014
        mine.links = [CardLink(kind: .x, value: "fuga_p")]
        mine.hidden = [.attended]
        mine.cardDesign = .formal
        mine.qrUrl = "https://lit.link/fuga"
        var sheet = profileSheetDefault()
        sheet.size = .story
        sheet.songs = ["s2", "s1"]
        mine.profile = sheet
        mine.cardOshiChoice = ["765as_星井美希", "876_上水流宇宙"]
        try source.saveMyProducerCard(mine)
        try source.saveReceivedProducerCard(received("c1", name: "しろくまP", memo: "物販列で隣"))

        let json = try BackupExportImportService.buildEnvelopeJSON(database: source)

        let target = try makeDatabase()
        let result = try BackupExportImportService.importEnvelopeJSON(json, database: target, restoreDeviceId: false)
        XCTAssertEqual(result.addedProducerCards, 1)
        let card = try XCTUnwrap(target.allReceivedProducerCards().first)
        XCTAssertEqual(card.id, "c1")
        XCTAssertEqual(card.memo, "物販列で隣")
        XCTAssertEqual(card.card?.name, "しろくまP")
        let restored = try XCTUnwrap(target.myProducerCard())
        XCTAssertEqual(restored.name, "ふがP")
        XCTAssertEqual(restored.sinceYear, 2014)
        XCTAssertEqual(restored.links, mine.links)
        XCTAssertEqual(restored.hidden, [.attended])
        XCTAssertEqual(restored.cardDesign, .formal)
        XCTAssertEqual(restored.qrUrl, "https://lit.link/fuga")
        XCTAssertEqual(restored.profile, sheet, "P名刺の画像の選択と好きな曲もバックアップで戻る")
        XCTAssertEqual(restored.cardOshiChoice, ["765as_星井美希", "876_上水流宇宙"], "名刺に載せる担当の選択も戻る")

        // 2 回目は何も増えない (id で重複を弾く)。
        let again = try BackupExportImportService.importEnvelopeJSON(json, database: target, restoreDeviceId: false)
        XCTAssertEqual(again.addedProducerCards, 0)
        XCTAssertEqual(try target.allReceivedProducerCards().count, 1)
    }

    /// 名刺のリンク・名刺ファイルの判定はコアの規則で、Deeplink に載る。
    func testDeeplinkParsesCardUrlsAndFiles() throws {
        let p = payload(name: "ふがP")
        let https = try XCTUnwrap(URL(string: producerCardUrlFromPayload(payload: p)))
        XCTAssertEqual(DeeplinkRouter.parse(https), .producerCard(payload: p))
        let custom = try XCTUnwrap(URL(string: "imaslivedb://p#\(p)"))
        XCTAssertEqual(DeeplinkRouter.parse(custom), .producerCard(payload: p))
        let file = URL(fileURLWithPath: "/tmp/ふがPのP名刺.imascard")
        XCTAssertEqual(DeeplinkRouter.parse(file), .producerCardFile(file))
        XCTAssertNil(DeeplinkRouter.parse(URL(fileURLWithPath: "/tmp/a.json")))
    }

    // MARK: - デザイン・自分の QR・写真

    /// デザインと自分の QR は端末の表に入り、名刺の中身にも載る。デザインを選んでいなければ既定。
    func testMyCardDesignAndQRReachTheCard() throws {
        let db = try makeDatabase()
        var mine = MyProducerCard.empty()
        mine.name = "ふがP"
        XCTAssertEqual(mine.cardDesign, cardDesigns()[0].design, "空のキーは既定のデザイン")
        mine.cardDesign = .pop
        mine.qrUrl = normalizeCardQrUrl(raw: "lit.link/fuga")
        try db.saveMyProducerCard(mine)
        let loaded = try XCTUnwrap(db.myProducerCard())
        XCTAssertEqual(loaded.design, "pop")
        XCTAssertEqual(loaded.qrUrl, "https://lit.link/fuga")

        let record = ProducerCardMyRecord(oshiIds: [], attended: [], songCount: 0)
        let encoded = try XCTUnwrap(ProducerCardAssembler.encode(card: loaded, record: record))
        let back = try XCTUnwrap(decodeProducerCard(text: encoded.url))
        XCTAssertEqual(back.design, .pop)
        XCTAssertEqual(ProducerCardDisplay.links(back).first?.label, "QR")
        XCTAssertEqual(ProducerCardDisplay.nameFont(back), "MochiyPopOne-Regular")
    }

    /// 書体を選んでいた頃の保存のキーは、近いデザインに読み替える。
    func testOldFontKeysReadAsNearestDesign() {
        var mine = MyProducerCard.empty()
        for (key, design) in [("gothic", CardDesign.pass), ("mincho", .formal), ("maru", .pop), ("hand", .pop),
                              ("pop", .pop), ("", .pass), ("unknown", .pass)] {
            mine.design = key
            XCTAssertEqual(mine.cardDesign, design, key)
        }
    }

    /// 自作の画像の名刺は、画像が手元にあれば画像で、無ければ (QR だけで受け取った) 入場証で描く。
    func testCustomDesignNeedsFaceImage() throws {
        let card = encodeProducerCard(input: ProducerCardInput(
            name: "しろくまP", message: "", sinceYear: nil, oshiIdolIds: [], links: [], showCount: nil, songCount: nil,
            nextShowId: nil, attended: [], issuedOn: "2026-10-06", design: .custom, qrUrl: nil)).card
        let face = ProducerCardDisplay.Face(front: URL(fileURLWithPath: "/tmp/front.jpg"), back: nil)
        XCTAssertEqual(ProducerCardDisplay.cardDesign(card, face: face), .face(front: face.front, back: nil))
        XCTAssertEqual(ProducerCardDisplay.cardDesign(card, face: nil), .pass)
    }

    /// 名刺ファイルの自作の画像 (表・裏) は受け取った名刺の顔として書き、名刺入れから引ける。
    func testReceivedFaceImagesAreStored() throws {
        let cardId = "test-\(UUID().uuidString)"
        defer { ProducerCardFiles.deleteAll(cardId: cardId) }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x02])
        try ProducerCardFiles.saveImages(cardId: cardId, images: [
            CardFileImage(idolId: "", jpeg: jpeg, kind: .faceFront),
            CardFileImage(idolId: "", jpeg: jpeg, kind: .faceBack),
        ])
        let face = try XCTUnwrap(ProducerCardDisplay.receivedFace(cardId: cardId))
        XCTAssertNotNil(face.back)
        XCTAssertNil(ProducerCardFiles.cardPhotoURL(cardId: cardId))
    }

    /// 自分の名刺ファイルには、デザインが自作の画像のときだけ表・裏の画像が入る。
    func testMyCardFileCarriesFacesOnlyForCustomDesign() throws {
        defer {
            ProducerCardFiles.deleteMyFace(.front)
            ProducerCardFiles.deleteMyFace(.back)
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 91, height: 55)).image { ctx in
            UIColor(white: 0.5, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 91, height: 55))
        }
        try ProducerCardFiles.saveMyFace(image, side: .front)
        try ProducerCardFiles.saveMyFace(image, side: .back)
        var mine = MyProducerCard.empty()
        mine.name = "ふがP"
        let record = ProducerCardMyRecord(oshiIds: [], attended: [], songCount: 0)

        mine.cardDesign = .custom
        let custom = try XCTUnwrap(ProducerCardAssembler.encode(card: mine, record: record))
        let file = try XCTUnwrap(decodeCardFile(bytes: try XCTUnwrap(ProducerCardAssembler.myCardFile(custom))))
        // 名刺の写真 (端末に置いてあれば) は別の種類。ここでは自作の画像だけを見る。
        let faces: (CardFileContents) -> [CardFileImageKind] = { $0.images.map(\.kind).filter { $0 != .photo } }
        XCTAssertEqual(faces(file), [.faceFront, .faceBack])

        mine.cardDesign = .formal
        let formal = try XCTUnwrap(ProducerCardAssembler.encode(card: mine, record: record))
        let plain = try XCTUnwrap(decodeCardFile(bytes: try XCTUnwrap(ProducerCardAssembler.myCardFile(formal))))
        XCTAssertTrue(faces(plain).isEmpty)
    }

    /// X のアイコンの規則 (ID の取り出し・読みに行く先・返事の分け方) はコア。
    func testXAvatarRulesComeFromCore() {
        XCTAssertEqual(cardXAvatarHandle(links: [CardLink(kind: .bluesky, value: "a.bsky.social"),
                                                 CardLink(kind: .x, value: "fuga_p")]), "fuga_p")
        XCTAssertNil(cardXAvatarHandle(links: [CardLink(kind: .bluesky, value: "a.bsky.social")]))
        XCTAssertNotNil(xProfileApiUrl(handle: "fuga_p"))
        XCTAssertEqual(xAvatarLookup(handle: "fuga_p", status: 404, body: ""), .notFound)
        XCTAssertNotNil(xAvatarLookupMessage(lookup: .protected, handle: "fuga_p"))
    }

    /// デザインの書体がすべて PostScript 名で引ける (Info.plist の UIAppFonts と揃っている)。
    func testNameFontsAreBundled() {
        for font in cardNameFonts() {
            XCTAssertNotNil(UIFont(name: font.postscriptName, size: 20), "\(font.key) の書体が引けない")
            XCTAssertNotNil(Bundle.main.url(forResource: font.fileStem, withExtension: "ttf"))
        }
    }

    /// 名刺ファイルの写真は担当の画像と分けて書き、名刺の写真として引ける。
    func testReceivedPhotoIsStoredSeparately() throws {
        let cardId = "test-\(UUID().uuidString)"
        defer { ProducerCardFiles.deleteAll(cardId: cardId) }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x01])
        try ProducerCardFiles.saveImages(cardId: cardId, images: [
            CardFileImage(idolId: "765_haruka", jpeg: jpeg, kind: .oshi),
            CardFileImage(idolId: "", jpeg: jpeg, kind: .photo),
        ])
        XCTAssertNotNil(ProducerCardFiles.oshiImageURL(cardId: cardId, idolId: "765_haruka"))
        XCTAssertNotNil(ProducerCardFiles.cardPhotoURL(cardId: cardId))
        XCTAssertNil(ProducerCardFiles.oshiImageURL(cardId: cardId, idolId: ""))
        XCTAssertFalse(ProducerCardFiles.cardPhotoRound(cardId: cardId))
    }

    /// 届いた写真が X のアイコンなら出どころを残して丸く出し、写真から選んだ写真が届き直したら正方形に戻す。
    func testReceivedXIconPhotoIsRound() throws {
        let cardId = "test-\(UUID().uuidString)"
        defer { ProducerCardFiles.deleteAll(cardId: cardId) }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x01])
        try ProducerCardFiles.saveImages(cardId: cardId, images: [
            CardFileImage(idolId: "", jpeg: jpeg, kind: .photo, photoSource: .xIcon),
        ])
        XCTAssertEqual(ProducerCardFiles.cardPhotoSource(cardId: cardId), .xIcon)
        XCTAssertTrue(ProducerCardFiles.cardPhotoRound(cardId: cardId))
        try ProducerCardFiles.saveImages(cardId: cardId, images: [
            CardFileImage(idolId: "", jpeg: jpeg, kind: .photo),
        ])
        XCTAssertEqual(ProducerCardFiles.cardPhotoSource(cardId: cardId), .picked)
        XCTAssertFalse(ProducerCardFiles.cardPhotoRound(cardId: cardId))
    }

    /// 切り抜きは枠 (P名刺は正方形・前の版の 3:4) の中に収まり、写真の外にはみ出さない。
    func testPortraitCropStaysInsideTheImage() {
        let size = CGSize(width: 4000, height: 3000)
        for frame in [ImasPortraitCrop.Frame.card, .resume] {
            let base = ImasPortraitCrop().rect(in: size, frame: frame)
            XCTAssertEqual(base.width / base.height, frame.aspect, accuracy: 0.001)
            XCTAssertEqual(base.height, 3000, accuracy: 0.5)
            let corner = ImasPortraitCrop(zoom: 2, center: CGPoint(x: 1, y: 1)).rect(in: size, frame: frame)
            XCTAssertEqual(corner.maxX, 4000, accuracy: 0.5)
            XCTAssertEqual(corner.maxY, 3000, accuracy: 0.5)
            XCTAssertEqual(corner.width, base.width / 2, accuracy: 0.5)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { _ in }
            XCTAssertEqual(ImasPortraitCrop().render(image, frame: frame)?.size, frame.outputSize)
        }
    }

    /// 前の版の 3:4 の切り抜き (拡大と真ん中) は、正方形の枠でも真ん中を保ったまま読み替える。
    func testOldPortraitCropKeepsCenterInSquareFrame() {
        let size = CGSize(width: 3000, height: 4000)
        let old = ImasPortraitCrop(zoom: 1.5, center: CGPoint(x: 0.4, y: 0.35))
        let resume = old.rect(in: size, frame: .resume)
        let square = old.rect(in: size, frame: .card)
        XCTAssertEqual(square.width, square.height, accuracy: 0.5)
        XCTAssertEqual(square.midX, resume.midX, accuracy: 0.5)
        XCTAssertEqual(square.midY, resume.midY, accuracy: 0.5)
    }

    /// 斜めに写った紙の名刺の四隅を見つけて平らにする。四隅が無い写真はそのまま。
    func testRectifierFindsCardCorners() async throws {
        let size = CGSize(width: 1500, height: 1100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let photo = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
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
        }
        let result = await PaperCardRectifier.rectify(photo)
        let corners = try XCTUnwrap(result.corners, "四隅が見つからない")
        XCTAssertEqual(corners[0].x, 210 / 1500, accuracy: 0.03)
        XCTAssertEqual(corners[0].y, 264 / 1100, accuracy: 0.03)
        XCTAssertEqual(corners[2].x, 1350 / 1500, accuracy: 0.03)
        XCTAssertGreaterThan(result.image.size.width / result.image.size.height, 1.5)

        let plain = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let none = await PaperCardRectifier.rectify(plain)
        XCTAssertNil(none.corners)
        XCTAssertEqual(none.image.size, plain.size)
    }
}
