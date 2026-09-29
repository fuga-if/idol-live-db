import CloudKit
import XCTest
@testable import ImasLiveDB

/// `CKRecordMapper` がコアの行 (`Ck*Row`) の**全フィールド**をモデルへ渡していることを検査する。
///
/// なぜ個別フィールドのテストではなく網羅チェックなのか:
/// GRDB の `upsert` は「モデルがエンコードした列」を全部書く
/// (`AppDatabase+Sync.swift` の `record.upsert(db)`)。したがって
/// **モデルにプロパティを足して mapper に足し忘れると、同期のたびにその列が
/// NULL で上書きされる** — 列を足さないより悪い。
///
/// これは実際に `series_group` で起きていた。`Song` 側にはプロパティも
/// CodingKeys もあり「宣言漏れを直した」というコメントまで付いていたのに、
/// `CKRecordMapper.song(from:)` だけが `record["seriesGroup"]` を読んでおらず、
/// 1,956 曲の series_group が同期のたび消えてシリーズ絞り込みが壊れていた。
///
/// Android の `SyncMappersCoverageTest` と同じ形にしてある:
/// - 各フィールドに**区別できる値**を入れた行を写し、同名のモデルのプロパティと値で比べる
///   (取り違えて読んだら値が合わない)。真偽値は既定値に紛れないよう true / false の両方で回す。
/// - 行の初期化子は全引数が必須なので、コアが列を足すとサンプルがコンパイルできなくなる。
/// - `CkRow` の場合分けを網羅する switch を置くので、コアがレコード型を足すと
///   ここ (と `CKRecordMapper.record(from:)`) がコンパイルできなくなる。
final class CKRecordMapperCoverageTests: XCTestCase {

    // MARK: - 行 → モデル

    func testEveryRecordTypeHasASample() {
        let names = Set(samples(flag: true).map(caseName))
        XCTAssertEqual(names.count, samples(flag: true).count, "同じレコード型のサンプルが重なっている")
        XCTAssertEqual(names.count, 21)
    }

    func testEveryFieldReachesTheModel() {
        let issues = [true, false].flatMap { flag in
            samples(flag: flag).flatMap { problems(mapping: $0, flag: flag) }
        }
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
    }

    /// 場合分けを網羅する (サンプルの足し忘れをコンパイル時に捕まえるため)。
    private func caseName(_ row: CkRow) -> String {
        switch row {
        case .brand: "brand"
        case .idol: "idol"
        case .event: "event"
        case .show: "show"
        case .venue: "venue"
        case .venueName: "venueName"
        case .venueHall: "venueHall"
        case .unitVersion: "unitVersion"
        case .costume: "costume"
        case .costumeWear: "costumeWear"
        case .creator: "creator"
        case .song: "song"
        case .unit: "unit"
        case .idolBrand: "idolBrand"
        case .songArtist: "songArtist"
        case .unitMember: "unitMember"
        case .showCast: "showCast"
        case .setlistItem: "setlistItem"
        case .setlistPerformer: "setlistPerformer"
        case .songVideo: "songVideo"
        case .showTicket: "showTicket"
        }
    }

    /// 渡し損ねたフィールドを「型.フィールド: 期待 → 実際」の形で返す。
    private func problems(mapping row: CkRow, flag: Bool) -> [String] {
        // 列挙の値は (row: Ck…Row) の形で入っている。中の行を取り出す。
        var payload = Mirror(reflecting: row).children.first!.value
        if Mirror(reflecting: payload).displayStyle == .tuple {
            payload = Mirror(reflecting: payload).children.first!.value
        }
        let model = CKRecordMapper.record(from: row)
        let modelValues = Dictionary(
            Mirror(reflecting: model).children.compactMap { child in child.label.map { ($0, child.value) } },
            uniquingKeysWith: { first, _ in first })
        let typeName = String(describing: type(of: payload))
        return Mirror(reflecting: payload).children.compactMap { child in
            guard let label = child.label else { return nil }
            guard let actual = modelValues[label] else {
                return "\(typeName).\(label): \(type(of: model)) に同名のプロパティが無い"
            }
            let expected = normalized(child.value)
            let got = normalized(actual)
            return expected == got ? nil : "\(typeName).\(label) (flag=\(flag)): \(expected) → \(got)"
        }
    }

    /// Optional を剥がし、数は Int / Int64 / Double の違いを無視し、列挙は生の値で比べる。
    private func normalized(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first?.value else { return "nil" }
            return normalized(wrapped)
        }
        switch value {
        case let number as Int: return "\(Double(number))"
        case let number as Int64: return "\(Double(number))"
        case let number as Double: return "\(number)"
        case let role as CastRole: return role.rawValue
        default: return "\(value)"
        }
    }

    // MARK: - サンプル (全フィールドに区別できる値)

    private func v(_ field: String) -> String { "\(field)-値" }

    private func samples(flag: Bool) -> [CkRow] {
        [
            .brand(row: CkBrandRow(
                id: v("id"), name: v("name"), shortName: v("shortName"), color: v("color"),
                sortOrder: 11, iconUrl: v("iconUrl"))),
            .idol(row: CkIdolRow(
                id: v("id"), brandId: v("brandId"), name: v("name"), nameKana: v("nameKana"),
                nameRomaji: v("nameRomaji"), familyName: v("familyName"), givenName: v("givenName"),
                nickname: v("nickname"), color: v("color"), sortOrder: 12, birthday: v("birthday"),
                bloodType: v("bloodType"), height: 161.5, weight: 42.5, birthPlace: v("birthPlace"),
                age: 16, bust: 72.5, waist: 55.5, hip: 78.5, constellation: v("constellation"),
                hobbies: v("hobbies"), talents: v("talents"), description: v("description"),
                gender: v("gender"), handedness: v("handedness"), debutDate: v("debutDate"),
                attribute: v("attribute"), isExternal: flag, aliases: v("aliases"))),
            .event(row: CkEventRow(
                id: v("id"), brandId: v("brandId"), name: v("name"), eventType: v("eventType"),
                isStreaming: flag, isSolo: !flag, kind: v("kind"), ticketOpenDate: v("ticketOpenDate"),
                ticketDeadline: v("ticketDeadline"), ticketLotteryDate: v("ticketLotteryDate"),
                ticketUrl: v("ticketUrl"), jointBrandIds: v("jointBrandIds"), nameKana: v("nameKana"))),
            .show(row: CkShowRow(
                id: v("id"), eventId: v("eventId"), name: v("name"), date: v("date"), venue: v("venue"),
                venueId: v("venueId"), hall: v("hall"), streamPlatform: v("streamPlatform"),
                venueCity: v("venueCity"), startTime: v("startTime"), sortOrder: 13,
                performerType: v("performerType"))),
            .venue(row: CkVenueRow(
                id: v("id"), name: v("name"), nameKana: v("nameKana"), prefecture: v("prefecture"),
                city: v("city"), aliases: v("aliases"), capacity: 10_000, sortOrder: 14)),
            .venueName(row: CkVenueNameRow(
                id: v("id"), venueId: v("venueId"), name: v("name"), validFrom: v("validFrom"),
                validTo: v("validTo"))),
            .venueHall(row: CkVenueHallRow(id: v("id"), venueId: v("venueId"), name: v("name"), capacity: 7_000)),
            .unitVersion(row: CkUnitVersionRow(
                id: v("id"), unitId: v("unitId"), code: v("code"), name: v("name"),
                catchphrase: v("catchphrase"), logoUrl: v("logoUrl"), validFrom: v("validFrom"),
                validTo: v("validTo"), sortOrder: 15)),
            .costume(row: CkCostumeRow(
                id: v("id"), brandId: v("brandId"), name: v("name"), nameKana: v("nameKana"),
                unitId: v("unitId"), idolId: v("idolId"), description: v("description"),
                sourceUrl: v("sourceUrl"), sortOrder: 16)),
            .costumeWear(row: CkCostumeWearRow(
                id: v("id"), costumeId: v("costumeId"), showId: v("showId"),
                setlistItemId: v("setlistItemId"), idolId: v("idolId"), sortOrder: 17)),
            .creator(row: CkCreatorRow(id: v("id"), name: v("name"), nameKana: v("nameKana"), aliases: v("aliases"))),
            .song(row: CkSongRow(
                id: v("id"), title: v("title"), titleKana: v("titleKana"), brandId: v("brandId"),
                songType: v("songType"), releaseDate: v("releaseDate"), durationSec: 240,
                composer: v("composer"), lyricist: v("lyricist"), arranger: v("arranger"),
                cdSeries: v("cdSeries"), cdTitle: v("cdTitle"), artworkUrl: v("artworkUrl"),
                previewUrl: v("previewUrl"), appleMusicId: v("appleMusicId"),
                appleMusicAlbumId: v("appleMusicAlbumId"), isrc: v("isrc"), lyricsUrl: v("lyricsUrl"),
                parentSongId: v("parentSongId"), singerLabel: v("singerLabel"), unitName: v("unitName"),
                unitId: v("unitId"), seriesGroup: v("seriesGroup"), unitVersionId: v("unitVersionId"),
                jointBrandIds: v("jointBrandIds"), isCollab: flag, hasKamisabiCard: !flag,
                note: v("note"))),
            .unit(row: CkUnitRow(
                id: v("id"), brandId: v("brandId"), name: v("name"), isPermanent: flag,
                nameAlt: v("nameAlt"), nameKana: v("nameKana"))),
            .idolBrand(row: CkIdolBrandRow(idolId: v("idolId"), brandId: v("brandId"), isPrimary: flag)),
            .songArtist(row: CkSongArtistRow(songId: v("songId"), idolId: v("idolId"), role: v("role"))),
            .unitMember(row: CkUnitMemberRow(unitId: v("unitId"), idolId: v("idolId"))),
            // castRole はコアが member / lead / guest に正規化済みの値だけが来る。
            .showCast(row: CkShowCastRow(showId: v("showId"), idolId: v("idolId"), castRole: flag ? "lead" : "guest")),
            .setlistItem(row: CkSetlistItemRow(
                id: v("id"), showId: v("showId"), songId: v("songId"), position: 7, section: v("section"),
                notes: v("notes"), unitName: v("unitName"))),
            .setlistPerformer(row: CkSetlistPerformerRow(setlistItemId: v("setlistItemId"), idolId: v("idolId"))),
            .songVideo(row: CkSongVideoRow(
                id: v("id"), songId: v("songId"), youtubeUrl: v("youtubeUrl"), videoTitle: v("videoTitle"),
                note: v("note"), createdAt: v("createdAt"), authorDisplayName: v("authorDisplayName"))),
            .showTicket(row: CkShowTicketRow(
                id: v("id"), showId: v("showId"), kind: v("kind"), name: v("name"), price: 6_600,
                isEstimate: flag, note: v("note"), sortOrder: 18)),
        ]
    }

    // MARK: - CKRecord → モデル (21 型を 1 件ずつ)

    /// 21 型それぞれ、サンプルの行と同じ値を載せた CKRecord を型名つきで取り込み、
    /// モデルまで届くこと。`mapped(_:as:)` に渡す型名を打ち間違えると、その型の同期が
    /// 黙って全件落ちる (nil で warning ログが出るだけ) ので、ここで捕まえる。
    func testEveryRecordTypeIsIngestedFromACKRecord() {
        var issues: [String] = []
        for row in samples(flag: true) {
            let name = caseName(row)
            let recordType = name.prefix(1).uppercased() + name.dropFirst()
            let fields = recordFields(of: rowPayload(row))
            // id を recordName から採る型があるので、recordName も id にそろえる。
            let recordName = (fields.first { $0.label == "id" }?.value as? String) ?? "test-\(name)"
            let rec = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName))
            for (label, value) in fields {
                guard let value = ckRecordValue(value) else { continue }
                rec[label] = value
            }
            guard let model = ingest(rec, as: row) else {
                issues.append("\(recordType): 取り込めなかった")
                continue
            }
            let modelValues = Dictionary(
                Mirror(reflecting: model).children.compactMap { c in c.label.map { ($0, c.value) } },
                uniquingKeysWith: { first, _ in first })
            for (label, value) in fields {
                guard let got = modelValues[label] else { continue }
                if normalized(value) != normalized(got) {
                    issues.append("\(recordType).\(label): \(normalized(value)) → \(normalized(got))")
                }
            }
        }
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
    }

    /// 実数 (NSNumber の double) と時刻 (Date) の列が、ckNumberValue / ckValue の変換を経て届くこと。
    func testRealAndTimestampColumnsAreProjected() throws {
        let idolRec = CKRecord(recordType: "Idol", recordID: CKRecord.ID(recordName: "i"))
        idolRec["id"] = "i1" as NSString
        idolRec["brandId"] = "ml" as NSString
        idolRec["name"] = "名前" as NSString
        idolRec["height"] = NSNumber(value: 158.5)
        idolRec["age"] = NSNumber(value: 14)
        idolRec["isExternal"] = NSNumber(value: true)
        let idol = try XCTUnwrap(CKRecordMapper.idol(from: idolRec))
        XCTAssertEqual(idol.height, 158.5)
        XCTAssertEqual(idol.age, 14)
        XCTAssertTrue(idol.isExternal)

        let videoRec = CKRecord(recordType: "SongVideo", recordID: CKRecord.ID(recordName: "v"))
        videoRec["id"] = "v1" as NSString
        videoRec["songId"] = "s1" as NSString
        videoRec["youtubeUrl"] = "https://www.youtube.com/watch?v=x" as NSString
        // 2026-09-23T00:00:00.999Z。秒未満は切り捨てる。
        videoRec["createdAt"] = Date(timeIntervalSince1970: 1_790_121_600.999) as NSDate
        let video = try XCTUnwrap(CKRecordMapper.songVideo(from: videoRec))
        XCTAssertEqual(video.createdAt, "2026-09-23T00:00:00Z")
    }

    /// 行のフィールドを CKRecord に載せる値にする。色はコアが 16 進として検査するので正しい形にし、
    /// 時刻 (createdAt) は Date で来る列なので、ここでは載せず下の専用のテストで見る。
    private func recordFields(of payload: Any) -> [(label: String, value: Any)] {
        Mirror(reflecting: payload).children.compactMap { child in
            guard let label = child.label, label != "createdAt" else { return nil }
            return (label, label == "color" ? "E22B30" : child.value)
        }
    }

    private func rowPayload(_ row: CkRow) -> Any {
        var payload = Mirror(reflecting: row).children.first!.value
        if Mirror(reflecting: payload).displayStyle == .tuple {
            payload = Mirror(reflecting: payload).children.first!.value
        }
        return payload
    }

    /// 行の値を CloudKit が持つ形 (NSString / NSNumber) にする。nil は載せない。
    private func ckRecordValue(_ value: Any) -> CKRecordValue? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first?.value else { return nil }
            return ckRecordValue(wrapped)
        }
        switch value {
        case let text as String: return text as NSString
        case let flag as Bool: return NSNumber(value: flag)
        case let number as Int64: return NSNumber(value: number)
        case let number as Int32: return NSNumber(value: number)
        case let number as UInt32: return NSNumber(value: number)
        case let number as Int: return NSNumber(value: number)
        case let number as Double: return NSNumber(value: number)
        default: return nil
        }
    }

    /// 型ごとの取り込み口 (`CKRecordMapper.xxx(from:)`) を呼ぶ。
    private func ingest(_ rec: CKRecord, as row: CkRow) -> Any? {
        switch row {
        case .brand: CKRecordMapper.brand(from: rec)
        case .idol: CKRecordMapper.idol(from: rec)
        case .event: CKRecordMapper.event(from: rec)
        case .show: CKRecordMapper.show(from: rec)
        case .venue: CKRecordMapper.venue(from: rec)
        case .venueName: CKRecordMapper.venueName(from: rec)
        case .venueHall: CKRecordMapper.venueHall(from: rec)
        case .unitVersion: CKRecordMapper.unitVersion(from: rec)
        case .costume: CKRecordMapper.costume(from: rec)
        case .costumeWear: CKRecordMapper.costumeWear(from: rec)
        case .creator: CKRecordMapper.creator(from: rec)
        case .song: CKRecordMapper.song(from: rec)
        case .unit: CKRecordMapper.unit(from: rec)
        case .idolBrand: CKRecordMapper.idolBrand(from: rec)
        case .songArtist: CKRecordMapper.songArtist(from: rec)
        case .unitMember: CKRecordMapper.unitMember(from: rec)
        case .showCast: CKRecordMapper.showCast(from: rec)
        case .setlistItem: CKRecordMapper.setlistItem(from: rec)
        case .setlistPerformer: CKRecordMapper.setlistPerformer(from: rec)
        case .songVideo: CKRecordMapper.songVideo(from: rec)
        case .showTicket: CKRecordMapper.showTicket(from: rec)
        }
    }

    // MARK: - CKRecord → モデル (射影を通した 1 本)

    /// CKRecord の値 (文字列・整数・小数・真偽値) をコアの入力に潰して、行を経てモデルまで届くこと。
    func testSongRecordIsProjectedThroughTheCore() throws {
        let rec = CKRecord(recordType: "Song", recordID: CKRecord.ID(recordName: "test"))
        rec["id"] = "s1" as NSString
        rec["title"] = "蒼い鳥" as NSString
        rec["songType"] = "unit" as NSString
        rec["durationSec"] = 240 as NSNumber
        rec["seriesGroup"] = "LIVE THE@TER FORWARD" as NSString
        rec["isCollab"] = 1 as NSNumber
        rec["hasKamisabiCard"] = true as NSNumber
        rec["note"] = "ミリシタ 1 周年記念楽曲" as NSString

        let song = try XCTUnwrap(CKRecordMapper.song(from: rec))
        XCTAssertEqual(song.title, "蒼い鳥")
        XCTAssertEqual(song.durationSec, 240)
        XCTAssertEqual(song.seriesGroup, "LIVE THE@TER FORWARD")
        XCTAssertTrue(song.isCollab)
        XCTAssertTrue(song.hasKamisabiCard)
        XCTAssertEqual(song.note, "ミリシタ 1 周年記念楽曲")
    }
}
