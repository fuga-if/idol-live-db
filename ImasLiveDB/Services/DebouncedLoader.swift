import Foundation

// MARK: - DebouncedLoader

@Observable
@MainActor
final class DebouncedLoader<Key: Equatable & Sendable, Result> {
    private(set) var isLoading = false
    private(set) var result: Result?
    private var currentTask: Task<Void, Never>?
    private var currentToken: UInt64 = 0
    private let debounceMs: UInt64
    private let fetcher: @MainActor (Key) async throws -> Result

    init(debounceMs: UInt64 = 200, fetcher: @escaping @MainActor (Key) async throws -> Result) {
        self.debounceMs = debounceMs
        self.fetcher = fetcher
    }

    func load(_ key: Key) {
        currentToken &+= 1
        let myToken = currentToken
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            }
            guard !Task.isCancelled, self.currentToken == myToken else { return }
            self.isLoading = true
            let value = try? await fetcher(key)
            guard self.currentToken == myToken else { return }
            self.result = value
            self.isLoading = false
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }
}
