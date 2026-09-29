import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "user_mark")

@Observable
@MainActor
final class UserMarkService {
    static let shared = UserMarkService()

    private let db: AppDatabase
    /// SwiftUI 再描画トリガ。bool/note を読む View は依存登録、書き込み時に bump する。
    private var version: Int = 0

    /// 変更のたびに増える番号。**重い集計を `.task(id:)` で回す画面が依存に混ぜる**ための口。
    ///
    /// マークを読むと `version` への依存が登録されて body が再評価される。習熟度の
    /// ヒートマップのように「2,000 曲を射影して FFI に渡す」画面が body の中で集計すると、
    /// 無関係なマーク変更や 1 打鍵ごとに全部やり直しになる。値だけ取り出して
    /// `.task(id:)` の鍵に混ぜれば、**本当に変わったときだけ**組み直せる。
    var changeToken: Int { version }

    /// bool 系マーク (collected/favorite/myPick/attended) のインメモリ集合。
    /// キーは "entity|kind|id"。一覧の各行トグルが body 評価のたびに同期 SQLite を引いて
    /// メインスレッドをブロックしていたのを、O(1) のメモリ参照に置き換えるためのキャッシュ。
    /// 書き込みは全て本サービス経由なので、setBool / setAttendance で同期更新すれば整合する。
    private var boolMarks: Set<String> = []

    /// 自動回収済み song_id キャッシュ（attended 変更時に更新）
    private var collectedIds: Set<String> = []

    /// マーク変更を iCloud KVS にミラーするデバウンス用タスク。
    private var backupTask: Task<Void, Never>?

    private init() {
        self.db = AppDatabase.shared
        // iCloud バックアップから非破壊で復元 (再インストール/機種変対策)。ローカルは消さない。
        restoreFromBackup()
        reloadBoolMarks()
        reloadMastery()
        refreshAutoCollected()
        // 他端末での変更を受信したら非破壊マージ + キャッシュ更新。
        UserMarkBackup.shared.startObserving { [weak self] in
            self?.restoreFromBackup()
            self?.reloadBoolMarks()
            self?.reloadMastery()
            self?.refreshAutoCollected()
            self?.version &+= 1
        }
        // 起動時に保留中のファボ送信をリトライ
        PendingCommunityActions.shared.flushPendingFavorites()
    }

    /// iCloud バックアップ → ローカルに非破壊復元 (無い行だけ追加)。
    private func restoreFromBackup() {
        guard let backed = UserMarkBackup.shared.loadBackup(), !backed.isEmpty else { return }
        do {
            let added = try db.restoreUserMarksIfAbsent(backed)
            if added > 0 { logger.info("restored \(added) user marks from iCloud backup") }
        } catch {
            logger.error("restore from backup failed: \(error.localizedDescription)")
        }
    }

    /// ローカルのマークを iCloud KVS にミラーする (デバウンス)。マーク変更後に呼ぶ。
    private func scheduleBackup() {
        backupTask?.cancel()
        backupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.backupMarks()
        }
    }

    /// 載せるのは付いている行だけ (`UserMark.meaningful`)。解除済みの行は復元しても何も
    /// 変わらないうえ、KVS の 1 値 1MB の枠を食う。キーと Payload の形は変えない。
    private func backupMarks() {
        if let marks = try? db.allUserMarks() {
            UserMarkBackup.shared.backup(UserMark.meaningful(marks))
        }
    }

    private static func markKey(_ entity: UserMarkEntity, _ kind: UserMarkKind, _ id: String) -> String {
        "\(entity.rawValue)|\(kind.rawValue)|\(id)"
    }

    /// このサービスを経由せず DB へ直接書いた後に、メモリ側を実体へ合わせ直す。
    ///
    /// バックアップ取り込みは `AppDatabase.restoreUserMarksIfAbsent` で DB を直接更新するため、
    /// ここを呼ばないと担当/参加がメモリ集合に載らず「復元したのに戻ってこない」ように見える
    /// (実データは入っており、アプリを再起動すると現れる)。投票だけ戻って見えたのは、
    /// あちらが自前のメモリ状態を更新していたため。
    func reloadAfterExternalWrite() {
        reloadBoolMarks()
        reloadMastery()
        refreshAutoCollected()
        version &+= 1
    }

    /// 全 bool 系マークを DB から読み直してメモリ集合を再構築する (起動時に1回)。
    private func reloadBoolMarks() {
        var marks: Set<String> = []
        for kind in [UserMarkKind.collected, .favorite, .myPick, .attended, .owned] {
            guard let rows = try? db.fetchAllUserMarks(kind: kind) else { continue }
            for mark in rows where mark.boolValue {
                guard let entity = UserMarkEntity(rawValue: mark.entityType) else { continue }
                marks.insert(Self.markKey(entity, kind, mark.entityId))
            }
        }
        boolMarks = marks
    }

    private func updateBoolCache(_ entity: UserMarkEntity, _ kind: UserMarkKind, _ id: String, _ value: Bool) {
        let key = Self.markKey(entity, kind, id)
        if value { boolMarks.insert(key) } else { boolMarks.remove(key) }
    }

    func bool(_ kind: UserMarkKind, entity: UserMarkEntity, id: String) -> Bool {
        _ = version
        return boolMarks.contains(Self.markKey(entity, kind, id))
    }

    func setBool(_ kind: UserMarkKind, entity: UserMarkEntity, id: String, value: Bool) throws {
        try db.upsertUserMark(entity: entity, id: id, kind: kind, boolValue: value)
        updateBoolCache(entity, kind, id, value)
        // attended 変更時は自動回収キャッシュを更新
        if kind == .attended {
            refreshAutoCollected()
        }
        // 楽曲お気に入りはコミュニティ集計にも背景送信（失敗時はキューに積む）
        if kind == .favorite && entity == .song {
            Task { await PendingCommunityActions.shared.send(songId: id, value: value) }
        }
        version &+= 1
        scheduleBackup()
    }

    func toggle(_ kind: UserMarkKind, entity: UserMarkEntity, id: String) throws {
        try setBool(kind, entity: entity, id: id, value: !bool(kind, entity: entity, id: id))
    }

    // MARK: - 習熟度 (段階)

    /// 曲の習熟度。0 = 未設定。
    ///
    /// bool 系と同じ理由でメモリに持つ: 一覧の各行が body 評価のたびに同期 SQLite を
    /// 引くとメインスレッドが詰まる。書き込みは全てここを通るので整合する。
    private var masteryById: [String: UInt8] = [:]

    /// 段階の定義。段数を変えると既存の記録の寄せ先が変わるので、
    /// 変更は `setScale` からだけ行う (規則は core の `remapMasteryLevel`)。
    private(set) var scale: MasteryScale = MasteryScale.standard

    private static let scaleDefaultsKey = "mastery_scale_labels_v1"

    private func reloadMastery() {
        var map: [String: UInt8] = [:]
        if let rows = try? db.fetchAllUserMarks(kind: .mastery) {
            for mark in rows where mark.entityType == UserMarkEntity.song.rawValue {
                guard let raw = mark.textValue, let level = UInt8(raw), level > 0 else { continue }
                map[mark.entityId] = level
            }
        }
        masteryById = map
        if let saved = UserDefaults.standard.stringArray(forKey: Self.scaleDefaultsKey), !saved.isEmpty {
            scale = MasteryScale(labels: saved)
        }
    }

    func mastery(songId: String) -> UInt8 {
        _ = version
        return masteryById[songId] ?? 0
    }

    /// 1 曲の段階を決める。0 で未設定に戻す (行ごと消す)。
    func setMastery(songId: String, level: UInt8) throws {
        let clamped = min(level, scale.steps)
        if clamped == 0 {
            try db.upsertUserMarkText(entity: .song, id: songId, kind: .mastery, text: nil)
            masteryById.removeValue(forKey: songId)
        } else {
            try db.upsertUserMarkText(entity: .song, id: songId, kind: .mastery, text: String(clamped))
            masteryById[songId] = clamped
        }
        version &+= 1
        scheduleBackup()
    }

    /// 一括更新。まとめて書いて再描画は 1 回だけにする
    /// (1 曲ずつ `setMastery` を呼ぶと、数百曲で同数の再描画が走る)。
    func setMastery(songIds: [String], level: UInt8) throws {
        guard !songIds.isEmpty else { return }
        let clamped = min(level, scale.steps)
        let text: String? = clamped == 0 ? nil : String(clamped)
        for id in songIds {
            try db.upsertUserMarkText(entity: .song, id: id, kind: .mastery, text: text)
            if clamped == 0 { masteryById.removeValue(forKey: id) } else { masteryById[id] = clamped }
        }
        version &+= 1
        scheduleBackup()
    }

    /// 段階の定義を差し替える。段を減らしたぶんは **1 つ下へ寄せる** (記録は消さない)。
    /// 寄せ先の規則は core が持つ。
    func setScale(_ next: MasteryScale) throws {
        let old = scale.steps
        let new = next.steps
        scale = next
        UserDefaults.standard.set(next.labels, forKey: Self.scaleDefaultsKey)
        if new < old {
            for (songId, level) in masteryById {
                let moved = remapMasteryLevel(level: level, oldSteps: old, newSteps: new)
                if moved != level {
                    try db.upsertUserMarkText(entity: .song, id: songId, kind: .mastery,
                                              text: moved == 0 ? nil : String(moved))
                    if moved == 0 { masteryById.removeValue(forKey: songId) } else { masteryById[songId] = moved }
                }
            }
            scheduleBackup()
        }
        version &+= 1
    }

    /// 段階ごとの曲数 (設定画面の右に出す数字)。index 0 が LV.1。
    func masteryCounts() -> [Int] {
        _ = version
        var counts = [Int](repeating: 0, count: Int(scale.steps))
        for level in masteryById.values {
            let i = Int(level) - 1
            if i >= 0 && i < counts.count { counts[i] += 1 }
        }
        return counts
    }

    func note(entity: UserMarkEntity, id: String) -> String? {
        _ = version
        do {
            return (try db.fetchUserMark(entity: entity, id: id, kind: .note))?.textValue
        } catch {
            logger.error("fetchUserMark(note) failed: entity=\(entity.rawValue) id=\(id) error=\(error.localizedDescription)")
            return nil
        }
    }

    func setNote(entity: UserMarkEntity, id: String, text: String?) throws {
        try db.upsertUserMarkNote(entity: entity, id: id, text: text)
        version &+= 1
        scheduleBackup()
    }

    /// 座席メモ (公演単位)。 空/空白なら nil で消す。
    func seat(entity: UserMarkEntity, id: String) -> String? {
        _ = version
        do {
            return (try db.fetchUserMark(entity: entity, id: id, kind: .seat))?.textValue
        } catch {
            logger.error("fetchUserMark(seat) failed: entity=\(entity.rawValue) id=\(id) error=\(error.localizedDescription)")
            return nil
        }
    }

    func setSeat(entity: UserMarkEntity, id: String, text: String?) throws {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.upsertUserMarkText(entity: entity, id: id, kind: .seat,
                                  text: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        version &+= 1
        scheduleBackup()
    }

    // MARK: - 参加種別 (現地 / 配信)

    /// 公演の参加種別。.attended 行の bool_value=参加有無、text_value=種別("live"/"stream")。
    /// nil = 不参加。旧来の bool だけの参加 (text なし) は現地(live)扱い。
    func attendance(entity: UserMarkEntity, id: String) -> AttendanceType? {
        _ = version
        guard let mark = try? db.fetchUserMark(entity: entity, id: id, kind: .attended),
              mark.boolValue else { return nil }
        return AttendanceType(rawValue: mark.textValue ?? "") ?? .live
    }

    /// 参加種別を設定する。nil で不参加 (マーク解除)。
    func setAttendance(entity: UserMarkEntity, id: String, type: AttendanceType?) throws {
        try db.setAttendanceMark(entity: entity, id: id, type: type)
        updateBoolCache(entity, .attended, id, type != nil)
        // 参加ライブの登録は「一区切りついた瞬間」なのでレビュー依頼の好機に数える。
        // 取り消しは数えない (良い体験ではないので)。
        if type != nil { ReviewPrompt.noteMilestone() }
        // 付けた直後だけ「チケット代を記録しますか」を出す土台にする。
        // ここに出す条件 (価格が分かっているか / もう記録済みか) は持たせない —
        // DB を引く判断なので、受け取った画面側 (TicketPromptCenter) が決める。
        if entity == .show, let type {
            NotificationCenter.default.post(
                name: .attendanceMarked,
                object: nil,
                userInfo: [AttendanceMarkedKey.showId: id, AttendanceMarkedKey.type: type.rawValue]
            )
        }
        refreshAutoCollected()
        version &+= 1
        scheduleBackup()
    }

    func allMarked(kind: UserMarkKind, entity: UserMarkEntity) -> [String] {
        _ = version
        do {
            return try db.fetchMarkedEntityIds(entity: entity, kind: kind)
        } catch {
            logger.error("fetchMarkedEntityIds failed: entity=\(entity.rawValue) kind=\(kind.rawValue) error=\(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Auto Collected

    /// attended ライブのセトリから自動判定した「回収済み」かどうか
    func isAutoCollected(songId: String) -> Bool {
        _ = version
        return collectedIds.contains(songId)
    }

    /// 自動回収済み song_id セットを再構築する（attended 変更後に呼ぶ）
    func refreshAutoCollected() {
        do {
            collectedIds = try db.fetchAutoCollectedSongIds()
        } catch {
            logger.error("fetchAutoCollectedSongIds failed: \(error.localizedDescription)")
            collectedIds = []
        }
    }

    /// 自動回収済み song_id の全セット（SongListView フィルタ用）
    func autoCollectedSongIds() -> Set<String> {
        _ = version
        return collectedIds
    }

    // MARK: - App Active

    /// アプリがフォアグラウンドに復帰したときに呼ぶ
    func handleAppActive() {
        PendingCommunityActions.shared.flushPendingFavorites()
    }
}
