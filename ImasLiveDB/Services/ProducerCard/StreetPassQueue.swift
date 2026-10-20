import Foundation

/// すれちがいで見つけた相手に繋ぐ順番 (BLE を持たない純粋な部分。`StreetPassService` が使う)。
///
/// - 端末の識別子ごとに「次に繋いでよい時刻」を持つ。読めた (既に読んだ人も) なら `reconnectAfterRead`、
///   失敗なら `reconnectAfterFailure` だけ空ける。
/// - 待ち行列の要素は見つけた時刻を持ち、取り出すときに `stale` より古いものは捨てる。長さが `max` を超えたら
///   古いものから捨てる。同じ識別子は 1 つだけ (見つけ直したら時刻を新しくして後ろへ)。
///
/// 数字はコアの `streetpassTuning()`。
struct StreetPassQueue<ID: Hashable> {
    let reconnectAfterRead: TimeInterval
    let reconnectAfterFailure: TimeInterval
    let max: Int
    let stale: TimeInterval

    private(set) var waiting: [(id: ID, foundAt: Date)] = []
    private var nextAllowed: [ID: Date] = [:]

    init(reconnectAfterRead: TimeInterval, reconnectAfterFailure: TimeInterval, max: Int, stale: TimeInterval) {
        self.reconnectAfterRead = reconnectAfterRead
        self.reconnectAfterFailure = reconnectAfterFailure
        self.max = max
        self.stale = stale
    }

    init(tuning: StreetpassTuning) {
        self.init(reconnectAfterRead: TimeInterval(tuning.reconnectAfterReadSeconds),
                  reconnectAfterFailure: TimeInterval(tuning.reconnectAfterFailureSeconds),
                  max: Int(tuning.queueMax), stale: TimeInterval(tuning.queueStaleSeconds))
    }

    /// 今この相手に繋いでよいか。
    func canConnect(_ id: ID, now: Date) -> Bool {
        nextAllowed[id].map { now >= $0 } ?? true
    }

    /// 見つけた。繋いでよい時刻より前なら足さない。足したら true。
    @discardableResult
    mutating func offer(_ id: ID, now: Date) -> Bool {
        guard canConnect(id, now: now) else { return false }
        waiting.removeAll { $0.id == id }
        waiting.append((id, now))
        if waiting.count > max { waiting.removeFirst(waiting.count - max) }
        return true
    }

    /// 次に繋ぐ相手 (古すぎるもの・まだ繋げないものは捨てる)。無ければ nil。
    mutating func next(now: Date) -> ID? {
        while !waiting.isEmpty {
            let item = waiting.removeFirst()
            if now.timeIntervalSince(item.foundAt) > stale || !canConnect(item.id, now: now) { continue }
            return item.id
        }
        return nil
    }

    func contains(_ id: ID) -> Bool { waiting.contains { $0.id == id } }

    /// 読めた (既に読んだ人だった、も含む)。
    mutating func markRead(_ id: ID, now: Date) {
        nextAllowed[id] = now.addingTimeInterval(reconnectAfterRead)
    }

    /// 繋げなかった・読めなかった。
    mutating func markFailed(_ id: ID, now: Date) {
        nextAllowed[id] = now.addingTimeInterval(reconnectAfterFailure)
    }

    /// もう過ぎた「次に繋いでよい時刻」を落とす (覚えすぎない)。
    mutating func prune(now: Date) {
        nextAllowed = nextAllowed.filter { now < $0.value }
    }

    mutating func removeAll() { waiting = [] }
}
