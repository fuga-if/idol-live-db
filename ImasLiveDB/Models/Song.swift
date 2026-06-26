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
    }

    var isRemix: Bool { parentSongId != nil }

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
