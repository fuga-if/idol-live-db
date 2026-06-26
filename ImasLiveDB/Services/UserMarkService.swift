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

    /// bool 系マーク (collected/favorite/myPick/attended) のインメモリ集合。
    /// キーは "entity|kind|id"。一覧の各行トグルが body 評価のたびに同期 SQLite を引いて
    /// メインスレッドをブロックしていたのを、O(1) のメモリ参照に置き換えるためのキャッシュ。
    /// 書き込みは全て本サービス経由なので、setBool / setAttendance で同期更新すれば整合する。
    private var boolMarks: Set<String> = []

    /// 自動回収済み song_id キャッシュ（attended 変更時に更新）
    private var collectedIds: Set<String> = []

    private init() {
        self.db = AppDatabase.shared
        reloadBoolMarks()
        refreshAutoCollected()
        // 起動時に保留中のファボ送信をリトライ
        PendingCommunityActions.shared.flushPendingFavorites()
    }

    private static func markKey(_ entity: UserMarkEntity, _ kind: UserMarkKind, _ id: String) -> String {
        "\(entity.rawValue)|\(kind.rawValue)|\(id)"
    }

    /// 全 bool 系マークを DB から読み直してメモリ集合を再構築する (起動時に1回)。
    private func reloadBoolMarks() {
        var marks: Set<String> = []
        for kind in [UserMarkKind.collected, .favorite, .myPick, .attended] {
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
            Task {
                do {
                    try await CommunityAPI.shared.toggleFavorite(songId: id, value: value)
                } catch {
                    logger.warning("toggleFavorite failed, enqueuing: songId=\(id) error=\(error.localizedDescription)")
                    PendingCommunityActions.shared.enqueue(songId: id, value: value)
                }
            }
        }
        version &+= 1
    }

    func toggle(_ kind: UserMarkKind, entity: UserMarkEntity, id: String) throws {
        try setBool(kind, entity: entity, id: id, value: !bool(kind, entity: entity, id: id))
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
        if let type {
            try db.upsertUserMark(entity: entity, id: id, kind: .attended, boolValue: true)
            try db.upsertUserMarkText(entity: entity, id: id, kind: .attended, text: type.rawValue)
            updateBoolCache(entity, .attended, id, true)
        } else {
            try db.upsertUserMark(entity: entity, id: id, kind: .attended, boolValue: false)
            try db.upsertUserMarkText(entity: entity, id: id, kind: .attended, text: nil)
            updateBoolCache(entity, .attended, id, false)
        }
        refreshAutoCollected()
        version &+= 1
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
