import CloudKit
import Foundation

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

    // MARK: - Core Entities

    static func brand(from record: CKRecord) -> Brand? {
        guard case .brand(let row)? = mapped(record, as: "Brand") else { return nil }
        return Brand(
            id: row.id,
            name: row.name,
            shortName: row.shortName,
            color: row.color,
            sortOrder: Int(row.sortOrder),
            iconUrl: row.iconUrl
        )
    }

    static func idol(from record: CKRecord) -> Idol? {
        guard case .idol(let row)? = mapped(record, as: "Idol") else { return nil }
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

    // Cast テーブル廃止: CastMember レコードは取り込まない。 旧 CK スキーマに存在する
    // CastMember レコードは CloudKitSyncEngine 側で無視する。

    static func event(from record: CKRecord) -> Event? {
        guard case .event(let row)? = mapped(record, as: "Event") else { return nil }
        return Event(
            id: row.id,
            brandId: row.brandId,
            name: row.name,
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

    static func show(from record: CKRecord) -> Show? {
        guard case .show(let row)? = mapped(record, as: "Show") else { return nil }
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
            performerType: row.performerType
        )
    }

    /// 会場 (施設)。会場は ID で管理するので、名前が変わっても履歴が分断されない。
    static func venue(from record: CKRecord) -> Venue? {
        guard case .venue(let row)? = mapped(record, as: "Venue") else { return nil }
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

    /// 会場名と有効期間。表示を「公演日時点の名前」にするために使う。
    static func venueName(from record: CKRecord) -> VenueName? {
        guard case .venueName(let row)? = mapped(record, as: "VenueName") else { return nil }
        return VenueName(
            id: row.id, venueId: row.venueId, name: row.name,
            validFrom: row.validFrom,
            validTo: row.validTo
        )
    }

    /// 会場のホール/構成。キャパは構成で変わるので施設と分けて持つ。
    static func venueHall(from record: CKRecord) -> VenueHall? {
        guard case .venueHall(let row)? = mapped(record, as: "VenueHall") else { return nil }
        return VenueHall(id: row.id, venueId: row.venueId, name: row.name, capacity: row.capacity.map(Int.init))
    }

    static func song(from record: CKRecord) -> Song? {
        guard case .song(let row)? = mapped(record, as: "Song") else { return nil }
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
            seriesGroup: row.seriesGroup
        )
    }

    static func unit(from record: CKRecord) -> Unit? {
        guard case .unit(let row)? = mapped(record, as: "ImasUnit") else { return nil }
        return Unit(
            id: row.id,
            brandId: row.brandId,
            name: row.name,
            isPermanent: row.isPermanent,
            nameAlt: row.nameAlt
        )
    }

    // MARK: - Junction Tables

    // IdolCast 廃止: idol.voiceActors に統合済み、 旧 CK レコードは無視する。

    static func idolBrand(from record: CKRecord) -> IdolBrand? {
        guard case .idolBrand(let row)? = mapped(record, as: "IdolBrand") else { return nil }
        return IdolBrand(
            idolId: row.idolId,
            brandId: row.brandId,
            isPrimary: row.isPrimary
        )
    }

    static func songArtist(from record: CKRecord) -> SongArtist? {
        guard case .songArtist(let row)? = mapped(record, as: "SongArtist") else { return nil }
        return SongArtist(
            songId: row.songId,
            idolId: row.idolId,
            role: row.role
        )
    }

    static func unitMember(from record: CKRecord) -> UnitMember? {
        guard case .unitMember(let row)? = mapped(record, as: "UnitMember") else { return nil }
        return UnitMember(
            unitId: row.unitId,
            idolId: row.idolId
        )
    }

    static func showCast(from record: CKRecord) -> ShowCast? {
        guard case .showCast(let row)? = mapped(record, as: "ShowCast") else { return nil }
        // 共有コアが member/lead/guest に正規化済み。未知の役割は member に倒っている。
        return ShowCast(
            showId: row.showId,
            idolId: row.idolId,
            castRole: CastRole(rawValue: row.castRole) ?? .member
        )
    }

    static func setlistItem(from record: CKRecord) -> SetlistItem? {
        guard case .setlistItem(let row)? = mapped(record, as: "SetlistItem") else { return nil }
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

    static func setlistPerformer(from record: CKRecord) -> SetlistPerformer? {
        guard case .setlistPerformer(let row)? = mapped(record, as: "SetlistPerformer") else { return nil }
        return SetlistPerformer(setlistItemId: row.setlistItemId, idolId: row.idolId)
    }

    // MARK: - Community Content

    static func songCall(from record: CKRecord) -> SongCall? {
        guard case .songCall(let row)? = mapped(record, as: "SongCall") else { return nil }
        return SongCall(
            id: row.id,
            songId: row.songId,
            callText: row.callText,
            sourceUrl: row.sourceUrl,
            createdAt: row.createdAt,
            authorDisplayName: row.authorDisplayName
        )
    }

    static func songVideo(from record: CKRecord) -> SongVideo? {
        guard case .songVideo(let row)? = mapped(record, as: "SongVideo") else { return nil }
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

    /// 投稿系 (SongCall / SongVideo) の createdAt 欠損時に使う既定値。
    /// 共有コアは OS 時刻を取らない規約なので、ここで渡す。
    private static func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
    }
}
