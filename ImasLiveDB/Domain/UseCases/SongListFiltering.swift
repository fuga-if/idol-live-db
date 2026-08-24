import Foundation

/// 楽曲一覧のマイマーク/タグ絞り込みに必要な、解決済みの集合とフラグ。
/// 各 id 集合は呼び出し側 (View) が UserMarkService 等から事前に解決して渡す。
struct SongMarkFilterContext {
    var collectFilter: SongCollectFilter
    /// 回収済み song_id (collectFilter が .all の時は未使用)。
    var collectedIds: Set<String> = []
    var requireFavorite: Bool = false
    var favoriteIds: Set<String> = []
    var requireNote: Bool = false
    var noteIds: Set<String> = []
    var requireMyPick: Bool = false
    /// 担当アイドルが歌唱に関わる song_id 集合。
    var myPickSongIds: Set<String> = []
    /// コミュニティタグ絞り込みの song_id 集合 (nil = タグ絞り込みなし)。
    var tagSongIds: Set<String>? = nil
    /// 単一タグ絞り込み + デフォルト並びの時に「そのタグの票数」降順へ並べ替えるか。
    var rankByTagVotes: Bool = false
    var tagVoteCounts: [String: Int] = [:]
}

/// 楽曲一覧へマイマーク/タグ絞り込みと、タグ票数ランキング並べ替えを適用する。
///
/// 本体は imas-core の domain/song_list_filtering.rs (適用順・同票時の 50 音安定化もそちら参照)。
/// ここはエンティティ全体を FFI へ渡さないための薄いラッパ: `SongWithArtists` を判定に要る
/// 3 フィールドの射影 (`SongListFilterEntry`) へ落とし、返ってきた index 列で自国の配列を
/// 引き直すだけ。生成側の型名が `SongCollectMode` / `SongListFilterCriteria` なのは、
/// 既存 Swift 型 (`SongCollectFilter` / この struct) と同一モジュール内で衝突するため。
func applySongMarkFilters(_ songs: [SongWithArtists], _ ctx: SongMarkFilterContext) -> [SongWithArtists] {
    let entries = songs.map {
        SongListFilterEntry(songId: $0.song.id, title: $0.song.title, titleKana: $0.song.titleKana)
    }
    let collectMode: SongCollectMode
    switch ctx.collectFilter {
    case .all: collectMode = .all
    case .collected: collectMode = .collected
    case .uncollected: collectMode = .uncollected
    }
    let criteria = SongListFilterCriteria(
        collectMode: collectMode,
        collectedIds: Array(ctx.collectedIds),
        requireFavorite: ctx.requireFavorite,
        favoriteIds: Array(ctx.favoriteIds),
        requireNote: ctx.requireNote,
        noteIds: Array(ctx.noteIds),
        requireMyPick: ctx.requireMyPick,
        myPickSongIds: Array(ctx.myPickSongIds),
        tagSongIds: ctx.tagSongIds.map(Array.init),
        rankByTagVotes: ctx.rankByTagVotes,
        tagVoteCounts: ctx.tagVoteCounts.mapValues(Int64.init))
    return filterSongList(entries: entries, criteria: criteria).map { songs[Int($0)] }
}
