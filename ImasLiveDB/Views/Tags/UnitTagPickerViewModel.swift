import Foundation
import Observation

/// UnitTagPicker のデータ取得・付与担当 (Presentation)。`IdolTagPickerViewModel` と同じ役割分担だが、
/// ユニットタグは曲/アイドルとは別プール (unit_tag_master)。
@MainActor
@Observable
final class UnitTagPickerViewModel {
    let unitId: String

    private(set) var tags: [CommunityTag] = []
    private(set) var myTagIds: Set<String> = []
    private(set) var isLoading = false
    private(set) var isApplying = false
    var applyError: String?

    private let tagReading: any CommunityTagReading
    private let tagWriting: any CommunityTagWriting
    /// 検索デバウンス用の世代 ID (古い Task の結果が新しい入力を上書きしないためのガード)。
    private var loadToken = 0

    /// View の init (nonisolated) から生成できるよう init も nonisolated にする。
    nonisolated init(
        unitId: String,
        tagReading: any CommunityTagReading = AppContainer.shared.communityTagReading,
        tagWriting: any CommunityTagWriting = AppContainer.shared.communityTagWriting
    ) {
        self.unitId = unitId
        self.tagReading = tagReading
        self.tagWriting = tagWriting
    }

    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        async let tagResult = tagReading.unitTagCatalog(search: "", category: "", sort: "popular", limit: 1000, offset: 0)
        async let unitTagResult = tagReading.unitTags(unitId: unitId)
        tags = (try? await tagResult) ?? []
        if let result = try? await unitTagResult {
            myTagIds = Set(result.myTagIds)
        }
    }

    /// 入力中の連打を抑えるための簡易デバウンス + 古い結果で新しい入力を上書きしないための世代ガード
    /// (SongTagPickerViewModel.scheduleSearch と同方式)。
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
        let result = (try? await tagReading.unitTagCatalog(search: searchText, category: "", sort: "popular", limit: 1000, offset: 0)) ?? []
        tags = result
    }

    /// 新規タグ作成直後に候補一覧の先頭へ即時反映する。
    func insertCreated(_ tag: CommunityTag) {
        tags.insert(tag, at: 0)
    }

    /// 選択タグをまとめて付与する。成功可否を返す。
    @discardableResult
    func applyTags(_ selectedTagIds: Set<String>) async -> Bool {
        guard !selectedTagIds.isEmpty else { return false }
        isApplying = true
        defer { isApplying = false }
        do {
            try await tagWriting.applyUnitTags(unitId: unitId, tagIds: Array(selectedTagIds))
            return true
        } catch {
            applyError = (error as? APIClientError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
