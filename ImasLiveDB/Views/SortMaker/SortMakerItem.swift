import Foundation

/// 対戦カード・順位表の 1 件。曲かアイドルのどちらか。
enum SortMakerItem: Identifiable, Hashable {
    case song(Song)
    case idol(Idol)

    var id: String {
        switch self {
        case .song(let s): return s.id
        case .idol(let i): return i.id
        }
    }

    var title: String {
        switch self {
        case .song(let s): return s.title
        case .idol(let i): return i.name
        }
    }

    /// 曲は歌唱名義、アイドルは CV。
    @MainActor
    var subtitle: String? {
        switch self {
        case .song(let s):
            return s.singerLabel ?? s.unitName
        case .idol(let i):
            return VoiceActorDirectory.shared.current(for: i.id).map { "CV. \($0)" }
        }
    }

    /// テーマ色の種。曲はブランド色 (曲に固有の色は無い)、アイドルはイメージカラー。
    var seed: String? {
        switch self {
        case .song(let s): return BrandColors.hex(for: s.brandId)
        case .idol(let i): return i.color
        }
    }

    var brandId: String? {
        switch self {
        case .song(let s): return s.brandId
        case .idol(let i): return i.brandId
        }
    }

    var detail: DetailDestination {
        switch self {
        case .song(let s): return .song(s)
        case .idol(let i): return .idol(i)
        }
    }
}

/// 設定画面で選ぶ曲の種類。値は songs.song_type。
enum SortMakerSongType: String, CaseIterable, Identifiable {
    case any = ""
    case solo
    case unit
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "すべて"
        case .solo: return "ソロ曲"
        case .unit: return "ユニット曲"
        case .all: return "全体曲"
        }
    }
}

/// 対象の絞り込み。
struct SortMakerScope: Equatable {
    var brandIds: Set<String> = []
    /// 曲だけ: 歌唱アイドル (原唱者) での絞り込み。
    var idolIds: Set<String> = []
    var songType: SortMakerSongType = .any
    var includeRemixes = false
}

/// 対象の読み込み。絞り込みの判定はコア (曲一覧・アイドル一覧と同じ条件) に任せる。
enum SortMakerCandidates {
    static func load(_ subject: SortMakerSubject, scope: SortMakerScope) async -> [SortMakerItem] {
        let container = AppContainer.shared
        switch subject {
        case .song:
            var filter = SongSearchFilter(
                brandIds: scope.brandIds,
                idolIds: scope.idolIds.isEmpty ? nil : Array(scope.idolIds),
                songType: scope.songType == .any ? nil : scope.songType.rawValue,
                includeRemixes: scope.includeRemixes
            )
            // 曲一覧のブラウズと同じ母集団 (歌枠カバー等と、セトリにしか居ない曲は出さない)。
            filter.includeOtherBrand = false
            filter.excludeLiveOnly = true
            let songs = (try? await container.songReading.songs(filter: filter, sortOrder: .titleKana, ascending: nil)) ?? []
            return songs.map { .song($0.song) }
        case .idol:
            let idols: [Idol]
            if scope.brandIds.isEmpty {
                idols = (try? await container.idolReading.idols(brandId: nil)) ?? []
            } else {
                var merged: [Idol] = []
                for brandId in scope.brandIds.sorted() {
                    merged += (try? await container.idolReading.idols(brandId: brandId)) ?? []
                }
                idols = merged
            }
            return idols.filter { !$0.isExternal }.map { .idol($0) }
        }
    }

    /// 保存した id 列の順に引き直す (消えた id は nil のまま位置を保つ。添字がずれないように)。
    static func load(_ subject: SortMakerSubject, ids: [String]) async -> [SortMakerItem?] {
        let container = AppContainer.shared
        switch subject {
        case .song:
            let songs = (try? await container.songReading.songs(ids: ids)) ?? []
            let byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return ids.map { byId[$0].map(SortMakerItem.song) }
        case .idol:
            let idols = (try? await container.idolReading.idols(ids: ids)) ?? []
            let byId = Dictionary(idols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return ids.map { byId[$0].map(SortMakerItem.idol) }
        }
    }
}
