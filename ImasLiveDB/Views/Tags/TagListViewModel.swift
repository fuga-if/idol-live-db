import Foundation
import Observation

/// TagListView のデータ取得担当 (Presentation)。
///
/// カテゴリ/並び順の切り替えごとの再取得を debounce しつつ直列化する (`SongListViewModel.scheduleLoad`
/// と同じ方式)。フィルタ条件 (カテゴリ/並び順) の UI 状態自体は View 側が保持し、呼び出し時に渡す。
@MainActor
@Observable
final class TagListViewModel {
    private(set) var tags: [CommunityTag] = []
    private(set) var isLoading = false

    private let reading: any CommunityTagReading
    private var loadTask: Task<Void, Never>?

    /// View の init (nonisolated) から生成できるよう init も nonisolated にする。
    nonisolated init(reading: any CommunityTagReading = AppContainer.shared.communityTagReading) {
        self.reading = reading
    }

    @discardableResult
    func scheduleLoad(category: String, sort: String, debounce: Bool) -> Task<Void, Never> {
        loadTask?.cancel()
        let task = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            await load(category: category, sort: sort)
        }
        loadTask = task
        return task
    }

    func load(category: String, sort: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try Task.checkCancellation()
            let result = try await reading.tags(search: "", category: category, sort: sort, limit: 1000, offset: 0)
            try Task.checkCancellation()
            tags = result
        } catch is CancellationError {
            // キャンセル済み
        } catch {
            tags = []
        }
    }

    /// タグ作成直後に一覧へ即時反映する (人気順ソート等の並びはそのまま次回ロードに委ねる)。
    func insertCreated(_ tag: CommunityTag) {
        tags.insert(tag, at: 0)
    }
}
