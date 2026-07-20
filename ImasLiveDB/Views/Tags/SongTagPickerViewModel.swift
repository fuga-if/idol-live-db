import Foundation
import Observation

/// SongTagPicker のデータ取得・付与担当 (Presentation)。
///
/// タグ検索の debounce・付与済み判定・付与実行・付与完了シェアの組み立てを持つ。
/// 曲/ブランドの解決は `SongReading` / `BrandReading` ポート越し (AppDatabase 直叩きを排除)。
@MainActor
@Observable
final class SongTagPickerViewModel {
    let songId: String

    private(set) var tags: [CommunityTag] = []
    private(set) var myTagIds: Set<String> = []
    private(set) var isLoading = false
    private(set) var isApplying = false
    var applyError: String?

    private let tagReading: any CommunityTagReading
    private let tagWriting: any CommunityTagWriting
    private let songReading: any SongReading
    private let brandReading: any BrandReading
    /// 検索デバウンス用の世代 ID (古い Task の結果が新しい入力を上書きしないためのガード)。
    private var loadToken = 0

    /// View の init (nonisolated) から生成できるよう init も nonisolated にする。
    nonisolated init(
        songId: String,
        tagReading: any CommunityTagReading = AppContainer.shared.communityTagReading,
        tagWriting: any CommunityTagWriting = AppContainer.shared.communityTagWriting,
        songReading: any SongReading = AppContainer.shared.songReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading
    ) {
        self.songId = songId
        self.tagReading = tagReading
        self.tagWriting = tagWriting
        self.songReading = songReading
        self.brandReading = brandReading
    }

    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        async let tagResult = tagReading.tags(search: "", category: "", sort: "popular", limit: 1000, offset: 0)
        async let songTagResult = tagReading.songTags(songId: songId)
        tags = (try? await tagResult) ?? []
        if let result = try? await songTagResult {
            myTagIds = Set(result.myTagIds)
        }
    }

    /// 入力中の連打を抑えるための簡易デバウンス + 古い結果で新しい入力を上書きしないための世代ガード
    /// (SongSearchPickerView.scheduleLoad と同方式)。
    func scheduleSearch(_ searchText: String) {
        loadToken += 1
        let token = loadToken
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard token == loadToken else { return }
            await search(searchText)
        }
    }

    private func search(_ searchText: String) async {
        let result = (try? await tagReading.tags(search: searchText, category: "", sort: "popular", limit: 1000, offset: 0)) ?? []
        tags = result
    }

    /// 新規タグ作成直後に候補一覧の先頭へ即時反映する。
    func insertCreated(_ tag: CommunityTag) {
        tags.insert(tag, at: 0)
    }

    /// 選択タグをまとめて付与する。成功時は完了シェア用のコンテキストを返す。
    func applyTags(_ selectedTagIds: Set<String>, selectedTagsById: [String: CommunityTag], song: SongWithArtists?) async -> TagShareContext? {
        guard !selectedTagIds.isEmpty else { return nil }
        isApplying = true
        defer { isApplying = false }
        do {
            try await tagWriting.applySongTags(songId: songId, tagIds: Array(selectedTagIds))
            let appliedTags = selectedTagIds.compactMap { selectedTagsById[$0] }
            return await makeShareContext(applied: appliedTags, song: song)
        } catch {
            applyError = (error as? APIClientError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 付与完了シェアの内容を組み立てる。seed は曲のブランドカラー → 先頭タグ色。
    private func makeShareContext(applied: [CommunityTag], song: SongWithArtists?) async -> TagShareContext {
        let resolvedSong: Song?
        if let loaded = song?.song {
            resolvedSong = loaded
        } else {
            resolvedSong = try? await songReading.song(id: songId)
        }
        var brandColor: String?
        if let bid = resolvedSong?.brandId {
            brandColor = (try? await brandReading.brands())?.first { $0.id == bid }?.color
        }
        return TagShareContext(
            songTitle: resolvedSong?.title ?? "この曲",
            artistNames: song?.artistNames ?? resolvedSong?.singerLabel,
            tags: applied,
            seed: ColorMath.firstValidHex(brandColor, applied.first?.color?.rawValue),
            artworkUrl: resolvedSong?.artworkUrl
        )
    }
}
