import Foundation
import os
import GRDB

// MARK: - Show Query Types

struct ShowWithEventName: Codable, FetchableRecord, Identifiable, Sendable {
    var id: String
    var eventId: String
    var name: String
    var date: String
    var venue: String?
    var eventName: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case name, date, venue
        case eventName = "event_name"
    }

    /// 「<event_name> — <show_name>」形式 (event_name 空なら show_name のみ)
    var displayTitle: String {
        eventName.isEmpty ? name : "\(eventName) — \(name)"
    }

    /// Show ナビゲーション用に Show 値を組み立てる。 event_name 以外の追加属性は持たないので
    /// venueCity / startTime / performerType は nil、sortOrder は 0 で埋める。
    var asShow: Show {
        Show(
            id: id,
            eventId: eventId,
            name: name,
            date: date,
            venue: venue,
            venueCity: nil,
            startTime: nil,
            sortOrder: 0,
            performerType: nil
        )
    }
}

// MARK: - Event Query Types

struct EventWithDate: Sendable, Identifiable, Hashable {
    var id: String { event.id }
    var event: Event
    var firstDate: String?
    var lastDate: String?

    /// 表示用の開催期間 (曜日つき・複数日は ` 〜 ` で結ぶ。Web と同じ)。組み方はコアの
    /// `date_range_display`。一覧の行ごとに FFI を呼ばないよう、日付の組ごとに覚える。
    var dateRange: String? { EventDateRanges.display(first: firstDate, last: lastDate) }
}

private enum EventDateRanges {
    private struct Key: Hashable { let first: String?; let last: String? }
    private static let cache = OSAllocatedUnfairLock<[Key: String?]>(initialState: [:])

    static func display(first: String?, last: String?) -> String? {
        let key = Key(first: first, last: last)
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let value = dateRangeDisplay(first: first, last: last)
        cache.withLock { $0[key] = .some(value) }
        return value
    }
}

struct EventStats: Codable, FetchableRecord, Sendable {
    var showCount: Int
    var totalSongs: Int
    var uniqueSongs: Int
    var castCount: Int

    enum CodingKeys: String, CodingKey {
        case showCount = "show_count"
        case totalSongs = "total_songs"
        case uniqueSongs = "unique_songs"
        case castCount = "cast_count"
    }
}

// MARK: - Setlist Query Types

struct SetlistRow: Codable, FetchableRecord, Identifiable, Sendable {
    var id: String
    var position: Int
    var section: String?
    var notes: String?
    var unitName: String?
    var songId: String
    var songTitle: String
    var appleMusicId: String?
    var artworkUrl: String?
    var previewUrl: String?
    var songBrandId: String?

    enum CodingKeys: String, CodingKey {
        case id, position, section, notes
        case unitName = "unit_name"
        case songId = "song_id"
        case songTitle = "song_title"
        case appleMusicId = "apple_music_id"
        case artworkUrl = "artwork_url"
        case previewUrl = "preview_url"
        case songBrandId = "song_brand_id"
    }
}

struct PerformerRow: Codable, FetchableRecord, Identifiable, Sendable {
    var id: String
    var name: String
    var idolColor: String?
    var idolName: String?
    var idolId: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case idolColor = "idol_color"
        case idolName = "idol_name"
        case idolId = "idol_id"
    }
}

// MARK: - Song Query Types

struct PerformanceHistoryRow: Codable, FetchableRecord, Sendable {
    var showId: String
    var eventId: String
    var eventName: String
    var showName: String
    var date: String
    var venue: String?
    var position: Int
    var section: String?

    enum CodingKeys: String, CodingKey {
        case showId = "show_id"
        case eventId = "event_id"
        case eventName = "event_name"
        case showName = "show_name"
        case date, venue, position, section
    }
}

struct SongPlayCount: Codable, FetchableRecord, Identifiable, Sendable {
    var id: String
    var title: String
    var playCount: Int
    var brandId: String?
    /// 一覧のジャケは `songs.artwork_url` の直参照が正本 (URL を組み立てない)。
    /// **ここに無いと画面は出しようがない** — 実際、この型にだけ無かったせいで
    /// 回収率ダッシュボードの披露回数ランキングだけジャケが出ていなかった。
    var artworkUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case playCount = "play_count"
        case brandId = "brand_id"
        case artworkUrl = "artwork_url"
    }
}

// MARK: - Cast Query Types

struct CastShowRow: Codable, FetchableRecord, Sendable {
    var showId: String
    var eventId: String
    var eventName: String
    var showName: String
    var date: String
    var venue: String?
    /// このアイドルがこの公演で担った役割 (通常 / 主演 / ゲスト)。
    var castRole: CastRole = .member

    /// 主演だったか。
    var isLead: Bool { castRole == .lead }
    /// ゲストだったか。
    var isGuest: Bool { castRole == .guest }

    enum CodingKeys: String, CodingKey {
        case showId = "show_id"
        case eventId = "event_id"
        case eventName = "event_name"
        case showName = "show_name"
        case date, venue
        case castRole = "cast_role"
    }
}

struct CastShowCount: Codable, FetchableRecord, Identifiable, Sendable {
    var id: String
    var name: String
    var showCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case showCount = "show_count"
    }
}

// MARK: - Stats Query Types

struct BrandSongCount: Codable, FetchableRecord, Identifiable, Sendable {
    var id: String
    var shortName: String
    var color: String?
    var songCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case shortName = "short_name"
        case color
        case songCount = "song_count"
    }
}

struct DatabaseStats: Sendable {
    var songCount: Int
    var idolCount: Int
    var eventCount: Int
    var showCount: Int
}

// MARK: - Collection Dashboard Query Types

/// ブランド別の現地回収進捗 (回収済み曲数 / そのブランドの全曲数)。
struct BrandCollectionProgress: Identifiable, Sendable {
    var id: String { brandId }
    let brandId: String
    let shortName: String
    let color: String?
    let collected: Int
    let total: Int

    /// 0.0–1.0。total=0 のときは 0。
    var fraction: Double { total > 0 ? Double(collected) / Double(total) : 0 }
}

/// 未回収曲 + その曲の生涯披露回数 (= よく演る/レアの目安)。
struct UncollectedSong: Identifiable, Sendable {
    var id: String { song.id }
    let song: Song
    /// この曲がリアルライブで披露された累計回数 (全ユーザ共通の客観値)。
    let playCount: Int
    /// 披露頻度の区分とその文言。閾値は imas-core (`PlayFrequency`) が持つ。
    let frequency: PlayFrequency
    let frequencyLabel: String
}

/// 未来公演ごとの「未回収が聴けるかも」。
struct UpcomingCatchChance: Identifiable, Sendable {
    var id: String { show.id }
    let show: Show
    let eventName: String
    /// 「イベント名を省略」が ON のときに出す名前 (省略の規則は imas-core)。
    let eventShortName: String
    let brandId: String?
    let brandColor: String?
    /// 過去の同系統セトリに登場した「自分の未回収曲」の異なり数。
    let likelyCount: Int
}

/// 回収ダッシュボード 1 画面ぶん (imas-core `collection_dashboard` の写し)。
struct CollectionDashboard: Sendable {
    let overallCollected: Int
    let overallTotal: Int
    let brandProgress: [BrandCollectionProgress]
    let myPickCollected: Int
    let myPickTotal: Int
    let pickUncollected: [UncollectedSong]
    let allUncollected: [UncollectedSong]
    let catchChances: [UpcomingCatchChance]
}

struct YearlyShowCount: Codable, FetchableRecord, Identifiable, Sendable {
    var year: String
    var showCount: Int

    var id: String { year }

    enum CodingKeys: String, CodingKey {
        case year
        case showCount = "show_count"
    }
}

// MARK: - Song List Row

struct SongWithArtists: Identifiable, Sendable {
    var id: String { song.id }
    var song: Song
    var artistNames: String
    /// 一覧でアイドルアイコンを並べるための performer idol 配列。
    /// fetchSongs ではコスト軽減のため空のまま返し、表示側で必要なら別途 fetchSongPerformerIdols を呼ぶ。
    var performerIdols: [Idol] = []
}

// MARK: - Filter Criteria

enum SongFilterCriterion: Hashable, Sendable {
    case brand(id: String, label: String)
    case cdSeries(String)
    case seriesGroup(String)   // CDシリーズグループ（例: "LIVE THE@TER PERFORMANCE"）
    case songType(String)
    case releaseYear(String)  // "YYYY"
    case creator(String)      // 作詞・作曲・編曲いずれかで関わったクリエイター名
    case songIds([String], title: String)  // 任意の楽曲ID集合 (お気に入り・記録曲など)

    var navigationTitle: String {
        switch self {
        case .brand(_, let label): return "\(label)の楽曲"
        case .cdSeries(let s): return s
        case .seriesGroup(let s): return s
        case .songType(let t): return "\(t)の楽曲"
        case .releaseYear(let y): return "\(y)年リリースの楽曲"
        case .creator(let n): return "\(n)が関わった楽曲"
        case .songIds(_, let title): return title
        }
    }
}

// MARK: - Song With Roles (クリエイター検索結果用)

struct SongWithRoles: Identifiable, Sendable {
    var id: String { song.id }
    var song: Song
    var artists: [Idol]
    var roles: [String]  // ["作曲", "編曲"] 等

    var rolesLabel: String { roles.joined(separator: "・") }
}

// MARK: - Idol Performed Song (アイドル歌唱曲 + 披露回数)

struct IdolPerformedSong: Identifiable, Sendable {
    var id: String { song.id }
    var song: Song
    var performCount: Int
}

/// アイドル詳細「楽曲（原曲）」の 1 節 (ソロ曲/ユニット曲/全体曲/カバー/その他)。
/// 節分け・見出し・並びは共有コア (`idol_original_song_sections`) が決める
/// (親曲を持つ派生曲の除外、カバーの独立節化も含む)。
/// 見出しは節ごとに異なるので Identifiable の id・小タブの選択値にそのまま使える。
struct IdolSongSection: Identifiable, Sendable {
    var id: String { heading }
    var heading: String
    /// 小タブに出す短い見出し (「ソロ」等)。件数と組み合わせて「ソロ 12」のように使う。
    var shortHeading: String
    var songs: [Song]
}

enum IdolFilterCriterion: Hashable, Sendable {
    case brand(id: String, label: String)
    case birthMonth(Int)
    case constellation(String)
    case birthPlace(String)
    case bloodType(String)

    var navigationTitle: String {
        switch self {
        case .brand(_, let label): return "\(label)のアイドル"
        case .birthMonth(let m): return "\(m)月生まれのアイドル"
        case .constellation(let c): return "\(c)のアイドル"
        case .birthPlace(let p): return "\(p)出身のアイドル"
        case .bloodType(let t): return "\(t)型のアイドル"
        }
    }
}

enum EventFilterCriterion: Hashable, Sendable {
    case brand(id: String, label: String)
    case year(Int)

    var navigationTitle: String {
        switch self {
        case .brand(_, let label): return "\(label)のライブ"
        case .year(let y): return "\(y)年のライブ"
        }
    }
}

enum ShowFilterCriterion: Hashable, Sendable {
    case venue(String)
    case date(String)  // "YYYY-MM-DD"

    var navigationTitle: String {
        switch self {
        case .venue(let v): return "\(v)での公演"
        case .date(let d): return "\(d)の公演"
        }
    }
}

// MARK: - Calendar Entry

struct CalendarShowRow: Sendable {
    var show: Show
    var eventName: String
    var brandId: String?
    var brandColor: String?
    /// 親イベントの kind ("live" / "radio" / "festival" / "release_event" / "stream")
    var eventKind: String?
}

/// チケット日程の種別 (カレンダーに出す申込締切 / 当落発表)。
enum TicketDateKind: String, Sendable {
    case deadline   // 申込締切
    case lottery    // 当落発表

    /// 語はコアの vocabulary (値は events の列名)。
    var label: String {
        Vocab.ticketDate(self == .deadline ? "ticket_deadline" : "ticket_lottery_date")?.label ?? ""
    }
    var icon: String { self == .deadline ? "ticket.fill" : "envelope.open.fill" }
}

/// カレンダーに出すチケット日程 1 件 (イベントの ticket_deadline / ticket_lottery_date 由来)。
struct TicketCalendarRow: Sendable {
    var eventId: String
    var eventName: String
    var brandColor: String?
    var date: String      // YYYY-MM-DD
    var kind: TicketDateKind
    var url: String?
}

/// カレンダーに「受付期間」を帯で出すための日跨ぎスパン (受付開始 → 申込締切)。
struct TicketPeriodRow: Sendable {
    var eventId: String
    var eventName: String
    var brandColor: String?
    var start: String     // 受付開始 YYYY-MM-DD
    var end: String       // 申込締切 YYYY-MM-DD
    var url: String?
}

enum CalendarEntry: Identifiable, Hashable, Sendable {
    case show(CalendarShowRow)
    case release(date: String, songs: [Song])
    /// 誕生日。`occursOn` は表示範囲の中の実際の日 (`YYYY-MM-DD`)。月日の展開
    /// (非閏年の 2/29 は 2/28) はコアの `calendar_entries` が済ませている。
    case birthday(Idol, occursOn: String)
    /// 「アイドル本人ではない関係者」(事務員・社長・幹部) の誕生日。
    case staffBirthday(Staff, occursOn: String)
    /// ブランド/アプリ記念日 (サービス開始・アプリ稼働・アニメ放映 等)。N周年表示用。
    case anniversary(Anniversary, occursOn: String)
    /// 端末カレンダーから取り込んだマイ予定 (アプリ内表示のみ。DB には保存しない)
    case personal(PersonalCalendarEvent)
    /// チケット日程 (申込締切 / 当落発表)。
    case ticket(TicketCalendarRow)
    /// チケット受付期間 (受付開始 → 申込締切) の日跨ぎ帯。
    case ticketPeriod(TicketPeriodRow)

    // MARK: Identifiable

    var id: String {
        switch self {
        case .show(let row): return "show_\(row.show.id)"
        case .release(let date, let songs): return "release_\(date)_\(songs.map(\.id).sorted().joined(separator: "_"))"
        case .birthday(let idol, _): return "birthday_\(idol.id)"
        case .staffBirthday(let staff, _): return "staffbirthday_\(staff.id)"
        case .anniversary(let ann, _): return "anniversary_\(ann.id)"
        case .personal(let event): return "personal_\(event.id)"
        case .ticket(let row): return "ticket_\(row.eventId)_\(row.kind.rawValue)"
        case .ticketPeriod(let row): return "ticketperiod_\(row.eventId)"
        }
    }

    // MARK: Hashable

    static func == (lhs: CalendarEntry, rhs: CalendarEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Computed

    /// YYYY-MM-DD 形式の日付文字列
    var dateString: String {
        switch self {
        case .show(let row): return row.show.date
        case .release(let date, _): return date
        case .birthday(let idol, _):
            return idol.birthday ?? ""
        case .staffBirthday(let staff, _):
            return staff.birthday ?? ""
        case .anniversary(let ann, _):
            return ann.date
        case .personal(let event):
            return event.start.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        case .ticket(let row):
            return row.date
        case .ticketPeriod(let row):
            return row.start
        }
    }

    /// 同日内ソート順: 受付期間帯=0, ticket=1, show=2, release=3, anniversary=4, birthday=5, staffBirthday=6, personal=7
    /// チケット系は「その日やるべきこと」なので最上段に出す。受付期間の帯は各日で
    /// 縦位置を揃えたいので最優先 (0)。記念日はアイドル誕生日より上 (ブランド全体のトピックなので)。
    var sortOrder: Int {
        switch self {
        case .ticketPeriod: return 0
        case .ticket: return 1
        case .show: return 2
        case .release: return 3
        case .anniversary: return 4
        case .birthday: return 5
        case .staffBirthday: return 6
        case .personal: return 7
        }
    }
}

// MARK: - Song Filter / Sort

struct SongSearchFilter: Sendable {
    /// 空集合 = 全ブランド対象。 複数選択時は OR 結合 (= IN)。
    var brandIds: Set<String> = []
    var title: String?
    var idolName: String?
    var idolIds: [String]?
    var songwriter: String?
    var cdSeries: String?
    /// 上位シリーズ(series_group)での絞り込み。例: LIVE THE@TER FORWARD / BRILLI@NT WING。
    var seriesGroup: String?
    var liveName: String?
    var songType: String?
    var includeRemixes: Bool = false
    /// brand_id='other' (歌枠カバー等の非ブランド曲) を含めるか。
    /// 既定 true で既存挙動を維持。楽曲一覧のブラウズだけ false にして既定で隠す。
    /// brandIds を明示選択した場合はそちらが優先される (このフラグは未選択=全件時のみ効く)。
    var includeOtherBrand: Bool = true
    /// ライブ履歴 (セトリ) にしか存在しないファントム曲を除外するか。
    /// 既定 false で既存挙動 (検索・絞り込み等の他用途) を維持。楽曲一覧のブラウズだけ true にして、
    /// カタログメタ (apple_music_id / 原唱者 / リリース日 / CD / 作家) を一切持たない、
    /// セトリ追加で生まれただけの曲 (カバー・歌枠等) をカタログから隠す。
    /// apple_music_id 未補完でもメタを持つ正規曲は出す (配信有無では切らない)。
    var excludeLiveOnly: Bool = false
    /// 音楽カードゲーム「KAMISABI」の収録曲だけに絞るか。既定 false (絞らない)。
    /// 判定はコア (`SongListFilter.kamisabiOnly`) に渡すだけで、Swift 側では判定しない。
    var kamisabiOnly: Bool = false

    init(brandIds: Set<String> = [],
         title: String? = nil,
         idolName: String? = nil,
         idolIds: [String]? = nil,
         songwriter: String? = nil,
         cdSeries: String? = nil,
         liveName: String? = nil,
         songType: String? = nil,
         includeRemixes: Bool = false) {
        self.brandIds = brandIds
        self.title = title
        self.idolName = idolName
        self.idolIds = idolIds
        self.songwriter = songwriter
        self.cdSeries = cdSeries
        self.liveName = liveName
        self.songType = songType
        self.includeRemixes = includeRemixes
    }

    /// 旧 API 互換: 単一 brand_id を渡す呼び出し向け。
    init(brandId: String?,
         title: String? = nil,
         idolName: String? = nil,
         idolIds: [String]? = nil,
         songwriter: String? = nil,
         cdSeries: String? = nil,
         liveName: String? = nil,
         songType: String? = nil,
         includeRemixes: Bool = false) {
        self.init(
            brandIds: brandId.map { [$0] } ?? [],
            title: title,
            idolName: idolName,
            idolIds: idolIds,
            songwriter: songwriter,
            cdSeries: cdSeries,
            liveName: liveName,
            songType: songType,
            includeRemixes: includeRemixes
        )
    }

    var isEmpty: Bool {
        brandIds.isEmpty && (title ?? "").isEmpty && (idolName ?? "").isEmpty &&
        (idolIds ?? []).isEmpty && (songwriter ?? "").isEmpty &&
        (cdSeries ?? "").isEmpty && (liveName ?? "").isEmpty && songType == nil
    }

    var activeFilterCount: Int {
        var count = 0
        if !brandIds.isEmpty { count += 1 }
        if !(idolName ?? "").isEmpty || !(idolIds ?? []).isEmpty { count += 1 }
        if !(songwriter ?? "").isEmpty { count += 1 }
        if !(cdSeries ?? "").isEmpty { count += 1 }
        if !(seriesGroup ?? "").isEmpty { count += 1 }
        if !(liveName ?? "").isEmpty { count += 1 }
        if songType != nil { count += 1 }
        return count
    }
}

/// 楽曲一覧の「現地回収」軸での絞り込みモード。
/// 回収済のみ / 未回収のみ / 制限なし の 3 値。
enum SongCollectFilter: String, CaseIterable, Sendable {
    case all = "すべて"
    case collected = "回収済のみ"
    case uncollected = "未回収のみ"
}

/// 楽曲一覧の「マイマーク」 軸での絞り込み。 旧 MyMarks タブを楽曲フィルタに統合した結果。
/// 担当 / お気に入り / メモ どれか/全部 に該当する曲のみ表示する。
struct SongMyMarkFilter: Sendable, Equatable {
    var requireMyPick: Bool = false
    var requireFavorite: Bool = false
    var requireNote: Bool = false

    var isActive: Bool { requireMyPick || requireFavorite || requireNote }
    var activeCount: Int {
        var c = 0
        if requireMyPick { c += 1 }
        if requireFavorite { c += 1 }
        if requireNote { c += 1 }
        return c
    }
}

enum SongSortOrder: String, CaseIterable, Sendable {
    case titleKana = "五十音順"
    case releaseDate = "リリース日順"
    case performanceCount = "披露回数順"
    case collectedCount = "現地回収回数順"
    case collectedRate = "回収率順"

    /// この sort のデフォルト方向。 五十音順は昇順、 回数/日付系は降順 (多い/新しい順)。
    var defaultAscending: Bool {
        switch self {
        case .titleKana: return true
        case .releaseDate, .performanceCount, .collectedCount, .collectedRate: return false
        }
    }

    /// 一覧行に披露回数を出すか。
    ///
    /// 披露回数そのもので並べている時と、その比 (回収率) で並べている時。
    /// 数値を出さないと「なぜこの順なのか」が行から読み取れない。
    /// 現地回収回数順は行の ✓N バッジが既に根拠になっているので要らない。
    var showsPerformanceCount: Bool {
        self == .performanceCount || self == .collectedRate
    }
}

// MARK: - Event Attendance (show-level)

/// イベント単位での出席情報。show (=公演日) ごとの出演アイドルを保持し、
/// 「両日出席」「DAY1 のみ」「DAY2 のみ」「欠席」等のグループ化を行う。
struct EventAttendance: Sendable {
    /// ブランド全アイドル (対象集合)
    let brandIdols: [Idol]
    /// event 配下の shows (日付昇順)
    let shows: [Show]
    /// show_id → 出演アイドル idol_id の集合
    let presenceByShow: [String: Set<String>]
    /// show_id → 主演 (cast_role='lead') idol_id の集合。 単独 or ツイン主演 (複数) 可。
    var leadByShow: [String: Set<String>] = [:]
    /// show_id → ゲスト (cast_role='guest') idol_id の集合。
    var guestByShow: [String: Set<String>] = [:]

    /// このイベント全体で 1 公演以上の主演を務めたアイドル idol_id 集合。
    var leadIdolIds: Set<String> {
        Set(leadByShow.values.flatMap { $0 })
    }

    /// このイベント全体で 1 公演以上ゲスト出演したアイドル idol_id 集合。
    var guestIdolIds: Set<String> {
        Set(guestByShow.values.flatMap { $0 })
    }

    /// 主演アイドル (brandIdols の並びを保つ)。
    var leadIdols: [Idol] {
        let ids = leadIdolIds
        return brandIdols.filter { ids.contains($0.id) }
    }

    /// ゲストアイドル (brandIdols の並びを保つ)。
    /// ゲストは他ブランド所属の可能性があり brandIdols に含まれないこともあるため、
    /// guestIdols は brandIdols に存在するゲストのみを返す (UI 側で別途解決が必要な分は別扱い)。
    var guestIdols: [Idol] {
        let ids = guestIdolIds
        return brandIdols.filter { ids.contains($0.id) }
    }

    /// ブランド全体で見て、このイベントに 1 日以上出演したアイドル
    var presentIdols: [Idol] {
        let presentIds = Set(presenceByShow.values.flatMap { $0 })
        return brandIdols.filter { presentIds.contains($0.id) }
    }

    /// ブランド内で 1 日も出演しなかったアイドル
    var absentIdols: [Idol] {
        let presentIds = Set(presenceByShow.values.flatMap { $0 })
        return brandIdols.filter { !presentIds.contains($0.id) }
    }

    var isFullAttendance: Bool {
        !brandIdols.isEmpty && absentIdols.isEmpty
    }

    /// show ごとの出演 idol (出演時点の並び)
    func idols(forShow showId: String) -> [Idol] {
        let ids = presenceByShow[showId] ?? []
        return brandIdols.filter { ids.contains($0.id) }
    }

    /// 出演状況の塊 (「全日」「DAY1・DAY3 のみ」「欠席」、単日公演は「出演」「欠席」)。
    /// 塊の切り方・見出し・並びはコア (`EventAttendanceRecord.groups`)。
    struct Group: Identifiable {
        let id: String
        let label: String
        let idols: [Idol]
    }

    var groups: [Group] = []

    /// 出演者を覆う、このイベントで歌唱されたユニット (採った順)。選び方はコア
    /// (`EventAttendanceRecord.coveringUnitIds`: 2 人以上・曲あり・大きい順の貪欲)。
    var coveringUnitIds: [String] = []
}

// MARK: - GridCardItem Conformance

extension AlbumSummary: GridCardItem {
    var title: String { cdSeries }
    var subtitle: String? {
        var parts: [String] = ["\(songCount)曲"]
        if let year = yearDisplay { parts.append(year) }
        return parts.joined(separator: " / ")
    }
    var placeholderSystemImage: String { "music.note" }
}

extension SeriesSummary: GridCardItem {
    var title: String { name }
    var subtitle: String? {
        var parts: [String] = ["\(cdCount)枚 / \(songCount)曲"]
        if let years = yearDisplay { parts.append("· \(years)") }
        return parts.joined(separator: " ")
    }
    var placeholderSystemImage: String { "rectangle.stack.fill" }
}

// MARK: - Album Summary

struct AlbumSummary: Identifiable, Hashable, Sendable {
    var id: String { cdSeries }
    let cdSeries: String
    let artworkUrl: String?
    let songCount: Int
    let earliestDate: String?  // "YYYY-MM-DD"
    let latestDate: String?
    let brandIds: [String]  // このアルバムに含まれる曲のブランド（複数ブランド混在の可能性）
    /// 札に出す年の幅 (`2019` / `2019 – 2021`)。組み方はコア。
    let yearDisplay: String?
}

// MARK: - Series Summary (CDシリーズグループ単位)

struct SeriesSummary: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String          // 例: "LIVE THE@TER PERFORMANCE"
    let songCount: Int
    let cdCount: Int          // シリーズ内の cd_series の異なり数
    let earliestDate: String?
    let latestDate: String?
    let artworkUrl: String?   // 代表ジャケット（最古CDのもの）
    let brandIds: [String]
    /// 札に出す年の幅 (`2019` / `2019 – 2021`)。組み方はコア。
    let yearDisplay: String?
}
