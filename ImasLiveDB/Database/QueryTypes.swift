import Foundation
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

    /// 表示用の開催日。複数日なら "first〜last"、単日なら first のみ。
    var dateRange: String? {
        guard let first = firstDate, !first.isEmpty else { return nil }
        if let last = lastDate, !last.isEmpty, last != first {
            return "\(first)〜\(last)"
        }
        return first
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

struct EventCastRow: Codable, FetchableRecord, Identifiable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case id, title
        case playCount = "play_count"
        case brandId = "brand_id"
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

    /// 披露頻度のラベル。閾値はざっくり: 10+ 定番 / 3+ ときどき / 1+ レア / 0 未披露。
    var frequencyLabel: String {
        switch playCount {
        case 10...: return "定番"
        case 3...:  return "ときどき"
        case 1...:  return "レア"
        default:    return "未披露"
        }
    }
}

/// 未来公演ごとの「未回収が聴けるかも」スコア。
/// score = この公演の親イベント (シリーズ) が過去に未回収曲を披露した延べ回数。
struct UpcomingCatchChance: Identifiable, Sendable {
    var id: String { show.id }
    let show: Show
    let eventName: String
    let brandId: String?
    let brandColor: String?
    /// 過去の同系統セトリに登場した「自分の未回収曲」の異なり数。
    let likelyCount: Int
}

struct SyncDiagnostics: Sendable, Equatable {
    var eventsAt: Int
    var showsAt: Int
    var setlistItemsAt: Int
    var ml13thLiveExists: Bool
    var ml13thShowsCount: Int
    var ml13thSetlistItemsCount: Int
    var sc8thName: String?
    var sc8thKind: String?
    var sc8thShowsCount: Int
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

// MARK: - Search

struct SearchResults: Sendable {
    var songs: [Song]
    var idols: [Idol]
    var events: [Event]

    var isEmpty: Bool { songs.isEmpty && idols.isEmpty && events.isEmpty }
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

    var label: String { self == .deadline ? "申込締切" : "当落発表" }
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
    case birthday(Idol)
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
        case .birthday(let idol): return "birthday_\(idol.id)"
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
        case .birthday(let idol):
            return idol.birthday ?? ""
        case .personal(let event):
            return event.start.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        case .ticket(let row):
            return row.date
        case .ticketPeriod(let row):
            return row.start
        }
    }

    /// 同日内ソート順: 受付期間帯=0, ticket=1, show=2, release=3, birthday=4, personal=5
    /// チケット系は「その日やるべきこと」なので最上段に出す。受付期間の帯は各日で
    /// 縦位置を揃えたいので最優先 (0)。
    var sortOrder: Int {
        switch self {
        case .ticketPeriod: return 0
        case .ticket: return 1
        case .show: return 2
        case .release: return 3
        case .birthday: return 4
        case .personal: return 5
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
}

/// 楽曲一覧のソート方向。 SongSortOrder と直交させて、 UI から昇降を反転できるようにする。
enum SongSortDirection: String, CaseIterable, Sendable {
    case ascending = "昇順"
    case descending = "降順"
}

// MARK: - Event Absence Info

struct EventAbsenceInfo: Sendable {
    let totalIdols: Int
    let presentIdols: [Idol]
    let absentIdols: [Idol]

    var brandTotal: Int { totalIdols }
    var isFullAttendance: Bool { absentIdols.isEmpty && totalIdols > 0 }
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

    /// 日付カテゴリでアイドルをグループ化。
    /// 複数日公演なら「全日」「特定日のみ」「欠席」を、
    /// 単一日公演なら「出席」「欠席」のみを返す。
    struct Group: Identifiable {
        let id: String
        let label: String
        let idols: [Idol]
    }

    func grouped() -> [Group] {
        guard !brandIdols.isEmpty else { return [] }
        let allShowIds = shows.map(\.id)
        let totalDays = allShowIds.count

        // 各 idol がどの show に出たか
        var showsByIdol: [String: [String]] = [:]  // 出演した show_id の list (順序付き)
        for show in shows {
            let ids = presenceByShow[show.id] ?? []
            for iid in ids {
                showsByIdol[iid, default: []].append(show.id)
            }
        }

        // グループ別
        // - "全日" (全 show に出演)
        // - "\(日付)のみ" or "\(ラベル)のみ"
        // - "欠席"
        var byKey: [(order: Int, label: String, idols: [Idol])] = []
        var added: [String: Int] = [:]  // label → index

        func bucket(label: String, order: Int, idol: Idol) {
            if let idx = added[label] {
                byKey[idx].idols.append(idol)
            } else {
                byKey.append((order, label, [idol]))
                added[label] = byKey.count - 1
            }
        }

        let showLabelById: [String: String] = Dictionary(uniqueKeysWithValues: shows.enumerated().map { idx, sh in
            // 複数日公演なら DAY番号、単一ならただ日付
            if totalDays > 1 {
                return (sh.id, "DAY\(idx + 1)")
            }
            return (sh.id, sh.name)
        })

        let showIndexById: [String: Int] = Dictionary(
            uniqueKeysWithValues: shows.enumerated().map { ($0.element.id, $0.offset) }
        )

        for idol in brandIdols {
            let attended = showsByIdol[idol.id] ?? []
            if attended.isEmpty {
                bucket(label: "欠席", order: 999, idol: idol)
            } else if attended.count == totalDays {
                bucket(label: totalDays > 1 ? "全日" : "出演", order: 0, idol: idol)
            } else {
                let labels = attended.compactMap { showLabelById[$0] }
                let combined = labels.joined(separator: "・")
                // 「DAY1 のみ」→「DAY2 のみ」→ … の順を安定化させるため、
                // 出演開始日 (= attended の最小 show index) を主キーに、出演日数を副キーに使う。
                let firstIdx = attended.compactMap { showIndexById[$0] }.min() ?? 0
                let order = 100 + firstIdx * 10 + attended.count
                bucket(label: "\(combined) のみ", order: order, idol: idol)
            }
        }

        byKey.sort { $0.order < $1.order }
        return byKey.map { Group(id: $0.label, label: $0.label, idols: $0.idols) }
    }
}

// MARK: - GridCardItem Conformance

extension AlbumSummary: GridCardItem {
    var title: String { cdSeries }
    var subtitle: String? {
        var parts: [String] = ["\(songCount)曲"]
        if let year = displayYear { parts.append(year) }
        return parts.joined(separator: " / ")
    }
    var placeholderSystemImage: String { "music.note" }
}

extension SeriesSummary: GridCardItem {
    var title: String { name }
    var subtitle: String? {
        var parts: [String] = ["\(cdCount)枚 / \(songCount)曲"]
        if let years = yearRange { parts.append("· \(years)") }
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

    var displayYear: String? { earliestDate.flatMap { String($0.prefix(4)) } }
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

    var yearRange: String? {
        let from = earliestDate.flatMap { String($0.prefix(4)) }
        let to = latestDate.flatMap { String($0.prefix(4)) }
        switch (from, to) {
        case let (f?, t?) where f == t: return f
        case let (f?, t?): return "\(f) – \(t)"
        case let (f?, nil): return f
        case let (nil, t?): return t
        default: return nil
        }
    }
}
