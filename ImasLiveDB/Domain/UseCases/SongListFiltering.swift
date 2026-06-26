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

/// 楽曲一覧へマイマーク/タグ絞り込みと、タグ票数ランキング並べ替えを適用する純粋ロジック。
///
/// DB にも UI にも依存しない (集合は解決済みで受け取る) ので単体テスト可能。
/// 適用順: 回収 → お気に入り → メモ → 担当 → タグ集合 → (任意で) タグ票数降順。
func applySongMarkFilters(_ songs: [SongWithArtists], _ ctx: SongMarkFilterContext) -> [SongWithArtists] {
    var results = songs

    switch ctx.collectFilter {
    case .all:
        break
    case .collected:
        results = results.filter { ctx.collectedIds.contains($0.song.id) }
    case .uncollected:
        results = results.filter { !ctx.collectedIds.contains($0.song.id) }
    }

    if ctx.requireFavorite {
        results = results.filter { ctx.favoriteIds.contains($0.song.id) }
    }
    if ctx.requireNote {
        results = results.filter { ctx.noteIds.contains($0.song.id) }
    }
    if ctx.requireMyPick {
        results = results.filter { ctx.myPickSongIds.contains($0.song.id) }
    }

    if let tagSongIds = ctx.tagSongIds {
        results = results.filter { tagSongIds.contains($0.song.id) }
        // 同票は 50 音 (titleKana → title) で安定化。
        if ctx.rankByTagVotes {
            results.sort { lhs, rhs in
                let lv = ctx.tagVoteCounts[lhs.song.id] ?? 0
                let rv = ctx.tagVoteCounts[rhs.song.id] ?? 0
                if lv != rv { return lv > rv }
                return (lhs.song.titleKana ?? lhs.song.title) < (rhs.song.titleKana ?? rhs.song.title)
            }
        }
    }

    return results
}
