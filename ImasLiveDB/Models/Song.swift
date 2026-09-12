import Foundation
import GRDB

struct Song: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "songs"

    var id: String
    var title: String
    var titleKana: String?
    var brandId: String?
    var songType: String
    var releaseDate: String?
    var durationSec: Int?
    var composer: String?
    var lyricist: String?
    var arranger: String?
    var cdSeries: String?
    var cdTitle: String?
    var artworkUrl: String?
    var previewUrl: String?
    var appleMusicId: String?
    var appleMusicAlbumId: String?
    var isrc: String?
    var lyricsUrl: String?
    var parentSongId: String?
    var singerLabel: String?
    var unitName: String?
    var unitId: String?
    /// 上位シリーズ (例: LIVE THE@TER FORWARD)。DB には存在するが宣言漏れで
    /// 同期のたび NULL に戻っていたため CodingKeys に追加。
    var seriesGroup: String?
    /// この曲がどのユニットの版のものか (`UnitVersion.id`)。nil = 無印。
    ///
    /// ユニットは 1 行のままで、版の違いは曲側が指す。ユニット単位のフラグにすると
    /// リブート前後の曲を区別できない。判定は `UnitVersion.code` で行うこと。
    var unitVersionId: String?
    /// 合同曲 (コラボ曲) で、`brandId` 以外に参加しているブランド (カンマ区切り)。
    /// `Event.jointBrandIds` と同じ形で、参加ブランド全部の曲一覧に出すために使う。
    /// **在籍の重なりでは入れない** — ML の曲に 765AS の面々が居るのも、876 の曲に
    /// 秋月涼が居るのも合同ではない。
    var jointBrandIds: String?
    /// シリーズ横断の合同曲か。判断は人が持つ (原唱者のブランドから導くと在籍の重なりを
    /// 合同と取り違える)。立てるなら `jointBrandIds` も入れる。
    var isCollab: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, composer, lyricist, arranger, isrc
        case titleKana = "title_kana"
        case brandId = "brand_id"
        case songType = "song_type"
        case releaseDate = "release_date"
        case durationSec = "duration_sec"
        case cdSeries = "cd_series"
        case cdTitle = "cd_title"
        case artworkUrl = "artwork_url"
        case previewUrl = "preview_url"
        case appleMusicId = "apple_music_id"
        case appleMusicAlbumId = "apple_music_album_id"
        case lyricsUrl = "lyrics_url"
        case parentSongId = "parent_song_id"
        case singerLabel = "singer_label"
        case unitName = "unit_name"
        case unitId = "unit_id"
        case seriesGroup = "series_group"
        case unitVersionId = "unit_version_id"
        case jointBrandIds = "joint_brand_ids"
        case isCollab = "is_collab"
    }

    var isRemix: Bool { parentSongId != nil }

    /// 参加ブランド (`brandId` が先頭、続いて `jointBrandIds`)。
    var brandIds: [String] {
        ([brandId].compactMap { $0 } + (jointBrandIds?.split(separator: ",").map(String.init) ?? []))
            .filter { !$0.isEmpty }
    }

    /// 日本語表示用の楽曲タイプラベル
    var songTypeLabel: String {
        switch songType {
        case "solo": return "ソロ"
        // "group" は廃止したが、古い local DB が CloudKit pull されるまでの互換ラベル
        case "unit", "group": return "ユニット"
        case "all": return "全体曲"
        case "original": return "オリジナル"
        case "unknown": return "不明"
        default: return songType
        }
    }

    // MARK: - Associations

    static let brand = belongsTo(Brand.self)
    static let songArtists = hasMany(SongArtist.self)
    static let artists = hasMany(Idol.self, through: songArtists, using: SongArtist.idol)
    static let setlistItems = hasMany(SetlistItem.self)

    var brand: QueryInterfaceRequest<Brand> { request(for: Song.brand) }
    var artists: QueryInterfaceRequest<Idol> { request(for: Song.artists) }
    var setlistItems: QueryInterfaceRequest<SetlistItem> { request(for: Song.setlistItems) }
}
