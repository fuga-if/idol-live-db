import Foundation

extension ISO8601DateFormatter {
    // ISO8601DateFormatter は内部でスレッドセーフに動作するため nonisolated(unsafe) で許容する。
    nonisolated(unsafe) static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) static let fullDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
