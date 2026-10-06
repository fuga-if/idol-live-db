import Foundation

/// お気に入りの曲 1 つと、お気に入りに付けた時刻。載せる曲を選ぶ材料 (規則はコアの `favoriteSongPicks`)。
struct FavoriteSong: Identifiable, Sendable {
    let song: Song
    /// お気に入りに付けた時刻 (ISO 8601)。
    let favoritedAt: String

    var id: String { song.id }

    /// コアに渡す形。
    var input: ProfileSongInput {
        ProfileSongInput(id: song.id, title: song.title, favoritedAt: favoritedAt)
    }
}

/// お気に入りの曲を引く (P名刺の画像・P名刺の編集・載せる曲を選ぶ画面で共有する。引けない曲は入れない)。
@MainActor
enum FavoriteSongSource {
    static func load() async -> [FavoriteSong] {
        let c = AppContainer.shared
        let times = (try? await c.markReading.markedTimes(entity: .song, kind: .favorite)) ?? [:]
        guard !times.isEmpty else { return [] }
        let songs = (try? await c.songReading.songs(ids: Array(times.keys))) ?? []
        return songs.map { FavoriteSong(song: $0, favoritedAt: times[$0.id] ?? "") }
    }
}
