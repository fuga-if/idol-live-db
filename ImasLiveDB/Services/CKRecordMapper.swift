import CloudKit
import Foundation
import GRDB

/// CloudKit のレコードをローカル DB のモデルに変換する。
///
/// 変換規則の本体は imas-core (Rust) の `domain/ck_record_mapping.rs`。
/// 「必須キーが欠けた 1 件だけ捨てる」「任意項目は型違いなら既定値へ倒す」
/// 「`songs` に列を足したら読み落とすと同期のたび NULL 上書きされる」といった判断と、
/// その境界 (空文字 id・小数の Int64・未知の castRole 等) はそちらでテスト済み。
///
/// **通信はここにも共有コアにも無い。** CKQuery・カーソル・リトライ・チェックポイントは
/// `CloudKitSyncEngine` に残す (docs/SHARED_CORE_STUDY.md §4-B1: CloudKit の transport は
/// iOS が CloudKit.framework、Android が Web Services で非対称なので共有しない)。
/// ここが担うのは 2 つの橋渡しだけ:
/// 1. `CKRecord` → 射影 (`CkRecordInput` = キーと 5 種の値) — CloudKit のネイティブ型を
///    共有コアが読める形に潰す。Android は同じ 5 種を JSON の `type` から作る。
/// 2. 返ってきた行 (`CkRow`) → GRDB のモデル。
enum CKRecordMapper {

    /// コアの行 1 つを GRDB のモデルにする。
    ///
    /// `CkRow` の場合分けを網羅しているので、コアが取り込むレコード型を足すと
    /// ここがコンパイルエラーになる (写し方の書き忘れを防ぐ)。
    static func record(from row: CkRow) -> any PersistableRecord {
        switch row {
        case .brand(let row): brand(row)
        case .idol(let row): idol(row)
        case .event(let row): event(row)
        case .show(let row): show(row)
        case .venue(let row): venue(row)
        case .creator(let row): creator(row)
        case .unitVersion(let row): unitVersion(row)
        case .costume(let row): costume(row)
        case .costumeWear(let row): costumeWear(row)
        case .showTicket(let row): showTicket(row)
        case .ticketSale(let row): ticketSale(row)
        case .venueName(let row): venueName(row)
        case .venueHall(let row): venueHall(row)
        case .song(let row): song(row)
        case .unit(let row): unit(row)
        case .idolBrand(let row): idolBrand(row)
        case .songArtist(let row): songArtist(row)
        case .unitMember(let row): unitMember(row)
        case .showCast(let row): showCast(row)
        case .setlistItem(let row): setlistItem(row)
        case .setlistPerformer(let row): setlistPerformer(row)
        case .songVideo(let row): songVideo(row)
        }
    }

    // MARK: - Core Entities

    static func brand(_ row: CkBrandRow) -> Brand {
        return Brand(
            id: row.id,
            name: row.name,
            shortName: row.shortName,
            color: row.color,
            sortOrder: Int(row.sortOrder),
            iconUrl: row.iconUrl
        )
    }

    static func brand(from record: CKRecord) -> Brand? {
        guard case .brand(let row)? = mapped(record, as: "Brand") else { return nil }
        return brand(row)
    }

    static func idol(_ row: CkIdolRow) -> Idol {
        return Idol(
            id: row.id,
            brandId: row.brandId,
            name: row.name,
            nameKana: row.nameKana,
            nameRomaji: row.nameRomaji,
            familyName: row.familyName,
            givenName: row.givenName,
            nickname: row.nickname,
            color: row.color,
            sortOrder: Int(row.sortOrder),
            birthday: row.birthday,
            bloodType: row.bloodType,
            height: row.height,
            weight: row.weight,
            birthPlace: row.birthPlace,
            age: row.age.map(Int.init),
            bust: row.bust,
            waist: row.waist,
            hip: row.hip,
            constellation: row.constellation,
            hobbies: row.hobbies,
            talents: row.talents,
            description: row.description,
            gender: row.gender,
            handedness: row.handedness,
            debutDate: row.debutDate,
            attribute: row.attribute,
            isExternal: row.isExternal,
            aliases: row.aliases
            // voiceActors は読まない。声優は idol_voice_actors (期間つき履歴) が正で、
            // Idol からは外した。CloudKit 側のフィールドは旧アプリ向けにまだ送っているが、
            // こちらで読むと廃止した列に書き戻そうとして落ちる。
        )
    }

    static func idol(from record: CKRecord) -> Idol? {
        guard case .idol(let row)? = mapped(record, as: "Idol") else { return nil }
        return idol(row)
    }

    // Cast テーブル廃止: CastMember レコードは取り込まない。 旧 CK スキーマに存在する
    // CastMember レコードは CloudKitSyncEngine 側で無視する。

    static func event(_ row: CkEventRow) -> Event {
        return Event(
            id: row.id,
            brandId: row.brandId,
            name: row.name,
            nameKana: row.nameKana,
            eventType: row.eventType,
            isStreaming: row.isStreaming,
            isSolo: row.isSolo,
            kind: row.kind,
            ticketOpenDate: row.ticketOpenDate,
            ticketDeadline: row.ticketDeadline,
            ticketLotteryDate: row.ticketLotteryDate,
            ticketUrl: row.ticketUrl,
            jointBrandIds: row.jointBrandIds
        )
    }

    static func event(from record: CKRecord) -> Event? {
        guard case .event(let row)? = mapped(record, as: "Event") else { return nil }
        return event(row)
    }

    static func show(_ row: CkShowRow) -> Show {
        return Show(
            id: row.id,
            eventId: row.eventId,
            name: row.name,
            date: row.date,
            venue: row.venue,
            venueId: row.venueId,
            hall: row.hall,
            streamPlatform: row.streamPlatform,
            venueCity: row.venueCity,
            startTime: row.startTime,
            sortOrder: Int(row.sortOrder),
            performerType: row.performerType,
            venueMode: row.venueMode
        )
    }

    static func show(from record: CKRecord) -> Show? {
        guard case .show(let row)? = mapped(record, as: "Show") else { return nil }
        return show(row)
    }

    /// 会場 (施設)。会場は ID で管理するので、名前が変わっても履歴が分断されない。
    static func venue(_ row: CkVenueRow) -> Venue {
        return Venue(
            id: row.id,
            name: row.name,
            nameKana: row.nameKana,
            prefecture: row.prefecture,
            city: row.city,
            aliases: row.aliases,
            capacity: row.capacity.map(Int.init),
            sortOrder: Int(row.sortOrder)
        )
    }

    static func venue(from record: CKRecord) -> Venue? {
        guard case .venue(let row)? = mapped(record, as: "Venue") else { return nil }
        return venue(row)
    }

    /// 作詞・作曲・編曲の表記とその読み。
    static func creator(_ row: CkCreatorRow) -> Creator {
        return Creator(id: row.id, name: row.name, nameKana: row.nameKana, aliases: row.aliases)
    }

    static func creator(from record: CKRecord) -> Creator? {
        guard case .creator(let row)? = mapped(record, as: "Creator") else { return nil }
        return creator(row)
    }

    /// ユニットの版 (Project“ReLight”AXE8 等)。
    ///
    /// ユニット自体は 1 行のまま。版で分かれるのは曲側 (`Song.unitVersionId`)。
    static func unitVersion(_ row: CkUnitVersionRow) -> UnitVersion {
        return UnitVersion(
            id: row.id, unitId: row.unitId, code: row.code, name: row.name,
            catchphrase: row.catchphrase, logoUrl: row.logoUrl,
            validFrom: row.validFrom, validTo: row.validTo,
            sortOrder: Int(row.sortOrder)
        )
    }

    static func unitVersion(from record: CKRecord) -> UnitVersion? {
        guard case .unitVersion(let row)? = mapped(record, as: "UnitVersion") else { return nil }
        return unitVersion(row)
    }

    /// ライブ衣装の目録。
    static func costume(_ row: CkCostumeRow) -> Costume {
        return Costume(
            id: row.id, brandId: row.brandId, name: row.name, nameKana: row.nameKana,
            unitId: row.unitId, idolId: row.idolId, description: row.description,
            sourceUrl: row.sourceUrl, sortOrder: Int(row.sortOrder)
        )
    }

    static func costume(from record: CKRecord) -> Costume? {
        guard case .costume(let row)? = mapped(record, as: "Costume") else { return nil }
        return costume(row)
    }

    /// 衣装の着用記録。
    ///
    /// `setlistItemId` / `idolId` の nil は欠損ではない (曲までは特定していない /
    /// その場の全員)。埋めたり捨てたりしないこと。
    static func costumeWear(_ row: CkCostumeWearRow) -> CostumeWear {
        return CostumeWear(
            id: row.id, costumeId: row.costumeId, showId: row.showId,
            setlistItemId: row.setlistItemId, idolId: row.idolId,
            sortOrder: Int(row.sortOrder)
        )
    }

    static func costumeWear(from record: CKRecord) -> CostumeWear? {
        guard case .costumeWear(let row)? = mapped(record, as: "CostumeWear") else { return nil }
        return costumeWear(row)
    }

    /// 公演のチケット価格。席種は自由文字列、kind は live / stream / live_viewing。
    static func showTicket(_ row: CkShowTicketRow) -> ShowTicketRecord {
        return ShowTicketRecord(
            id: row.id, showId: row.showId, kind: row.kind, name: row.name,
            price: row.price, isEstimate: row.isEstimate, note: row.note,
            sortOrder: row.sortOrder
        )
    }

    static func showTicket(from record: CKRecord) -> ShowTicketRecord? {
        guard case .showTicket(let row)? = mapped(record, as: "ShowTicket") else { return nil }
        return showTicket(row)
    }

    /// チケット受付。`kind` と日時は取り込み側では検査しない (寛容に受け、検査は domain と
    /// ローダが持つ)。`showIds` はカンマ区切りの文字列のまま保存する (core 側で分解する)。
    static func ticketSale(_ row: CkTicketSaleRow) -> TicketSaleRecord {
        return TicketSaleRecord(
            id: row.id, eventId: row.eventId, showIds: row.showIds, kind: row.kind, name: row.name,
            startsAt: row.startsAt, endsAt: row.endsAt, resultAt: row.resultAt, url: row.url,
            note: row.note, sourceUrl: row.sourceUrl, sortOrder: row.sortOrder
        )
    }

    static func ticketSale(from record: CKRecord) -> TicketSaleRecord? {
        guard case .ticketSale(let row)? = mapped(record, as: "TicketSale") else { return nil }
        return ticketSale(row)
    }

    /// 会場名と有効期間。表示を「公演日時点の名前」にするために使う。
    static func venueName(_ row: CkVenueNameRow) -> VenueName {
        return VenueName(
            id: row.id, venueId: row.venueId, name: row.name,
            validFrom: row.validFrom,
            validTo: row.validTo
        )
    }

    static func venueName(from record: CKRecord) -> VenueName? {
        guard case .venueName(let row)? = mapped(record, as: "VenueName") else { return nil }
        return venueName(row)
    }

    /// 会場のホール/構成。キャパは構成で変わるので施設と分けて持つ。
    static func venueHall(_ row: CkVenueHallRow) -> VenueHall {
        return VenueHall(id: row.id, venueId: row.venueId, name: row.name, capacity: row.capacity.map(Int.init))
    }

    static func venueHall(from record: CKRecord) -> VenueHall? {
        guard case .venueHall(let row)? = mapped(record, as: "VenueHall") else { return nil }
        return venueHall(row)
    }

    static func song(_ row: CkSongRow) -> Song {
        return Song(
            id: row.id,
            title: row.title,
            titleKana: row.titleKana,
            brandId: row.brandId,
            songType: row.songType,
            releaseDate: row.releaseDate,
            durationSec: row.durationSec.map(Int.init),
            composer: row.composer,
            lyricist: row.lyricist,
            arranger: row.arranger,
            cdSeries: row.cdSeries,
            cdTitle: row.cdTitle,
            artworkUrl: row.artworkUrl,
            previewUrl: row.previewUrl,
            appleMusicId: row.appleMusicId,
            appleMusicAlbumId: row.appleMusicAlbumId,
            isrc: row.isrc,
            lyricsUrl: row.lyricsUrl,
            parentSongId: row.parentSongId,
            singerLabel: row.singerLabel,
            unitName: row.unitName,
            unitId: row.unitId,
            // ここを読み落とすと、GRDB の upsert が Song のエンコード列を全部書くため
            // 同期のたび series_group が NULL 上書きされ、シリーズ絞り込みが壊れる。
            // Song に列を足したら共有コアの CkSongRow にも必ず足すこと。
            seriesGroup: row.seriesGroup,
            // 同じ理由。読み落としていたので、同期のたびに版つきの曲 (sc_beam / sc_iwe) が
            // 無印へ戻っていた。`CKRecordMapperCoverageTests` がこれを捕まえる。
            unitVersionId: row.unitVersionId,
            // 同じ理由。落とすと同期のたびに合同曲の指定が消え、参加ブランドの曲一覧から落ちる。
            jointBrandIds: row.jointBrandIds,
            isCollab: row.isCollab,
            // 同じ理由。落とすと同期のたびに KAMISABI 収録フラグが消え、フィルタ/バッジが消える。
            // `CKRecordMapperCoverageTests` がこれを捕まえる。
            hasKamisabiCard: row.hasKamisabiCard,
            // 同じ理由。落とすと同期のたびに曲の補足が消える。
            note: row.note
        )
    }

    static func song(from record: CKRecord) -> Song? {
        guard case .song(let row)? = mapped(record, as: "Song") else { return nil }
        return song(row)
    }

    static func unit(_ row: CkUnitRow) -> Unit {
        return Unit(
            id: row.id,
            brandId: row.brandId,
            name: row.name,
            isPermanent: row.isPermanent,
            nameAlt: row.nameAlt,
            nameKana: row.nameKana
        )
    }

    static func unit(from record: CKRecord) -> Unit? {
        guard case .unit(let row)? = mapped(record, as: "ImasUnit") else { return nil }
        return unit(row)
    }

    // MARK: - Junction Tables

    // IdolCast 廃止: idol.voiceActors に統合済み、 旧 CK レコードは無視する。

    static func idolBrand(_ row: CkIdolBrandRow) -> IdolBrand {
        return IdolBrand(
            idolId: row.idolId,
            brandId: row.brandId,
            isPrimary: row.isPrimary
        )
    }

    static func idolBrand(from record: CKRecord) -> IdolBrand? {
        guard case .idolBrand(let row)? = mapped(record, as: "IdolBrand") else { return nil }
        return idolBrand(row)
    }

    static func songArtist(_ row: CkSongArtistRow) -> SongArtist {
        return SongArtist(
            songId: row.songId,
            idolId: row.idolId,
            role: row.role
        )
    }

    static func songArtist(from record: CKRecord) -> SongArtist? {
        guard case .songArtist(let row)? = mapped(record, as: "SongArtist") else { return nil }
        return songArtist(row)
    }

    static func unitMember(_ row: CkUnitMemberRow) -> UnitMember {
        return UnitMember(
            unitId: row.unitId,
            idolId: row.idolId
        )
    }

    static func unitMember(from record: CKRecord) -> UnitMember? {
        guard case .unitMember(let row)? = mapped(record, as: "UnitMember") else { return nil }
        return unitMember(row)
    }

    static func showCast(_ row: CkShowCastRow) -> ShowCast {
        // 共有コアが member/lead/guest に正規化済み。未知の役割は member に倒っている。
        return ShowCast(
            showId: row.showId,
            idolId: row.idolId,
            castRole: CastRole(rawValue: row.castRole) ?? .member
        )
    }

    static func showCast(from record: CKRecord) -> ShowCast? {
        guard case .showCast(let row)? = mapped(record, as: "ShowCast") else { return nil }
        return showCast(row)
    }

    static func setlistItem(_ row: CkSetlistItemRow) -> SetlistItem {
        return SetlistItem(
            id: row.id,
            showId: row.showId,
            songId: row.songId,
            position: Int(row.position),
            section: row.section,
            notes: row.notes,
            unitName: row.unitName
        )
    }

    static func setlistItem(from record: CKRecord) -> SetlistItem? {
        guard case .setlistItem(let row)? = mapped(record, as: "SetlistItem") else { return nil }
        return setlistItem(row)
    }

    static func setlistPerformer(_ row: CkSetlistPerformerRow) -> SetlistPerformer {
        return SetlistPerformer(setlistItemId: row.setlistItemId, idolId: row.idolId)
    }

    static func setlistPerformer(from record: CKRecord) -> SetlistPerformer? {
        guard case .setlistPerformer(let row)? = mapped(record, as: "SetlistPerformer") else { return nil }
        return setlistPerformer(row)
    }

    // MARK: - Community Content

    static func songVideo(_ row: CkSongVideoRow) -> SongVideo {
        return SongVideo(
            id: row.id,
            songId: row.songId,
            youtubeUrl: row.youtubeUrl,
            videoTitle: row.videoTitle,
            note: row.note,
            createdAt: row.createdAt,
            authorDisplayName: row.authorDisplayName
        )
    }

    static func songVideo(from record: CKRecord) -> SongVideo? {
        guard case .songVideo(let row)? = mapped(record, as: "SongVideo") else { return nil }
        return songVideo(row)
    }

    // MARK: - Soft Delete

    /// soft delete マーカー。削除伝搬はこの経路のみ (CloudKit の物理削除は追わない)。
    static func deletedAt(from record: CKRecord) -> Date? {
        // 共有コアが見るのは deletedAt キーだけなので、全フィールドを潰さずここだけ射影する
        // (同期 1 件につき生存判定が 2 回走るため、無駄な射影が効いてくる)。
        let projected = CkRecordInput(
            recordName: record.recordID.recordName,
            fields: field(named: "deletedAt", of: record).map { [$0] } ?? []
        )
        guard let millis = ckRecordDeletedAtMillis(record: projected) else { return nil }
        return Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    // MARK: - 射影 (CKRecord → 共有コアの入力)

    /// レコード 1 件を共有コアへ渡し、対応する行を得る。
    /// 必須キー欠損・取り込み対象外の recordType では nil (呼び出し側が warning ログを出す)。
    private static func mapped(_ record: CKRecord, as recordType: String) -> CkRow? {
        ckMapRecord(recordType: recordType, record: projection(of: record), nowMillis: nowMillis())
    }

    /// `CKRecord` のキーと値を共有コアの 5 値 (Text/Int/Real/Bool/Timestamp) に潰す。
    /// 5 値のどれにもならない値 (CKAsset・参照・リスト等) はキーごと落とす。
    /// 落とした結果は「そのキーが無い」= 元実装の `as? String` 等が失敗するのと同じ扱いになる。
    private static func projection(of record: CKRecord) -> CkRecordInput {
        let keys = record.allKeys()
        var fields: [CkField] = []
        fields.reserveCapacity(keys.count)
        for key in keys {
            guard let value = ckValue(record[key]) else { continue }
            fields.append(CkField(key: key, value: value))
        }
        return CkRecordInput(recordName: record.recordID.recordName, fields: fields)
    }

    private static func field(named key: String, of record: CKRecord) -> CkField? {
        guard let value = ckValue(record[key]) else { return nil }
        return CkField(key: key, value: value)
    }

    private static func ckValue(_ raw: Any?) -> CkValue? {
        guard let raw else { return nil }
        switch raw {
        case let text as String:
            return .text(value: text)
        case let date as Date:
            // 秒未満は切り捨て側に寄せる。ISO8601DateFormatter が秒で切るので、
            // 四捨五入すると .9995 秒台のレコードだけ createdAt が 1 秒進む。
            return .timestamp(millis: Int64((date.timeIntervalSince1970 * 1000).rounded(.down)))
        case let number as NSNumber:
            return ckNumberValue(number)
        default:
            return nil
        }
    }

    /// `NSNumber` を Bool / Int64 / Double のどれとして渡すか決める。
    /// Swift の `as?` は NSNumber の中身で成否が変わる (Bool の NSNumber だけ `as? Bool` が通る)
    /// ので、同じ区別を実型から復元して共有コアに伝える。
    private static func ckNumberValue(_ number: NSNumber) -> CkValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(value: number.boolValue)
        }
        switch CFNumberGetType(number as CFNumber) {
        case .float32Type, .float64Type, .floatType, .doubleType, .cgFloatType:
            return .real(value: number.doubleValue)
        default:
            return .int(value: number.int64Value)
        }
    }

    /// 投稿系 (SongVideo) の createdAt 欠損時に使う既定値。
    /// 共有コアは OS 時刻を取らない規約なので、ここで渡す。
    private static func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
    }
}
