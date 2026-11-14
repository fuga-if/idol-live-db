import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "user_mark")

@Observable
@MainActor
final class UserMarkService {
    static let shared = UserMarkService()

    private let db: AppDatabase
    /// SwiftUI 再描画トリガ。読む View は依存登録、書き込み時に bump する。
    /// **実体の種類ごとに分ける** (1 本だと、曲の習熟度を 1 つ変えただけでアイドル一覧・ライブ一覧の
    /// 全行まで描き直しになる)。習熟度・ここ好きも別。
    private var songVersion = 0
    private var idolVersion = 0
    private var eventVersion = 0
    private var showVersion = 0
    private var releaseVersion = 0
    private var ticketSaleVersion = 0
    private var masteryVersion = 0
    private var lyricLikeVersion = 0

    private func observe(_ entity: UserMarkEntity) {
        switch entity {
        case .song: _ = songVersion
        case .idol: _ = idolVersion
        case .event: _ = eventVersion
        case .show: _ = showVersion
        case .release: _ = releaseVersion
        case .ticketSale: _ = ticketSaleVersion
        }
    }

    private func bump(_ entity: UserMarkEntity) {
        switch entity {
        case .song: songVersion &+= 1
        case .idol: idolVersion &+= 1
        case .event: eventVersion &+= 1
        case .show: showVersion &+= 1
        case .release: releaseVersion &+= 1
        case .ticketSale: ticketSaleVersion &+= 1
        }
    }

    private func bumpAll() {
        UserMarkEntity.allCases.forEach(bump)
        masteryVersion &+= 1
        lyricLikeVersion &+= 1
    }

    /// 変更のたびに増える番号。**重い集計を `.task(id:)` で回す画面が依存に混ぜる**ための口。
    ///
    /// マークを読むと `version` への依存が登録されて body が再評価される。習熟度の
    /// ヒートマップのように「2,000 曲を射影して FFI に渡す」画面が body の中で集計すると、
    /// 無関係なマーク変更や 1 打鍵ごとに全部やり直しになる。値だけ取り出して
    /// `.task(id:)` の鍵に混ぜれば、**本当に変わったときだけ**組み直せる。
    var changeToken: Int {
        songVersion &+ idolVersion &+ eventVersion &+ showVersion &+ releaseVersion &+ masteryVersion &+ lyricLikeVersion
            &+ collectedVersion
    }

    /// bool 系マーク (collected/favorite/myPick/attended) のインメモリ集合。
    /// キーは "entity|kind|id"。一覧の各行トグルが body 評価のたびに同期 SQLite を引いて
    /// メインスレッドをブロックしていたのを、O(1) のメモリ参照に置き換えるためのキャッシュ。
    /// 書き込みは全て本サービス経由なので、setBool / setAttendance で同期更新すれば整合する。
    ///
    /// 観測には載せない。載せると、どれか 1 つのマークを変えただけで、この集合を読んだ行が
    /// 実体の種類に関係なく全部描き直しになる (描き直しの合図は上の `*Version`)。
    @ObservationIgnored private var boolMarks: Set<String> = []

    /// 全マークの行そのもの (解除済みの行も含む)。キーは `boolMarks` と同じ。
    ///
    /// メモ・座席・参加形態・申込・ここ好きは、読むたびに同期 SQLite を 1 行引いていた。
    /// 一覧の行が body のたびに引くと、行数 × 描き直しの回数だけメインスレッドが止まる。
    /// 書き込みは全て本サービス経由で、書いた行だけ `refreshRow` で読み直す。
    @ObservationIgnored private var rows: [String: UserMark] = [:]

    /// 自動回収済み song_id キャッシュ（attended 変更時に更新）。
    /// 集計は裏で回して届いたら差し替えるので、これは観測に載せる (届いたら描き直す)。
    private var collectedIds: Set<String> = []
    /// 回収の集計の世代。遅れて届いた古い結果を捨てる。
    @ObservationIgnored private var collectedGeneration = 0
    /// 回収の集計が届いて中身が変わるたびに増える (`changeToken` に混ぜる)。
    private var collectedVersion = 0

    /// マーク変更を iCloud KVS にミラーするデバウンス用タスク。
    private var backupTask: Task<Void, Never>?

    private init() {
        self.db = AppDatabase.shared
        // iCloud バックアップから非破壊で復元 (再インストール/機種変対策)。ローカルは消さない。
        restoreFromBackup()
        reloadMarks()
        // 最初の 1 回だけは同期で読む。集計を待たずに空集合を返すと、起動直後に
        // 「回収済み」で絞った一覧や集計が空になる (読む側の多くは描き直しの合図を持たない)。
        collectedIds = (try? db.fetchAutoCollectedSongIds()) ?? []
        // 他端末での変更を受信したら非破壊マージ + キャッシュ更新。
        UserMarkBackup.shared.startObserving { [weak self] in
            self?.restoreFromBackup()
            self?.reloadMarks()
            self?.refreshAutoCollected()
            self?.bumpAll()
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
        reloadMarks()
        refreshAutoCollected()
        bumpAll()
    }

    /// 全マークを DB から 1 回で読み、メモリ側 (行・bool の集合・習熟度) を作り直す。
    /// 起動時と、このサービスを経由しない書き込みの後に呼ぶ。
    private func reloadMarks() {
        let all = (try? db.allUserMarks()) ?? []
        var byKey: [String: UserMark] = [:]
        byKey.reserveCapacity(all.count)
        for mark in all {
            byKey["\(mark.entityType)|\(mark.kind)|\(mark.entityId)"] = mark
        }
        rows = byKey

        let boolKinds: Set<String> = Set(
            [UserMarkKind.collected, .favorite, .myPick, .attended, .owned].map(\.rawValue))
        var marks: Set<String> = []
        var mastery: [String: UInt8] = [:]
        // 付いているとみなす規則はコア (`UserMark.meaningful`)。
        for mark in UserMark.meaningful(all) {
            if boolKinds.contains(mark.kind), mark.boolValue, UserMarkEntity(rawValue: mark.entityType) != nil {
                marks.insert("\(mark.entityType)|\(mark.kind)|\(mark.entityId)")
            }
            if mark.kind == UserMarkKind.mastery.rawValue, mark.entityType == UserMarkEntity.song.rawValue,
               let raw = mark.textValue, let level = UInt8(raw), level > 0 {
                mastery[mark.entityId] = level
            }
        }
        boolMarks = marks
        masteryById = mastery
        if let saved = UserDefaults.standard.stringArray(forKey: Self.scaleDefaultsKey), !saved.isEmpty {
            scale = MasteryScale(labels: saved)
        }
    }

    /// 書いた 1 行を DB から読み直してメモリ側へ写す (消えた行はメモリからも消える)。
    private func refreshRow(_ entity: UserMarkEntity, _ kind: UserMarkKind, _ id: String) {
        rows[Self.markKey(entity, kind, id)] = try? db.fetchUserMark(entity: entity, id: id, kind: kind)
    }

    private func row(_ entity: UserMarkEntity, _ kind: UserMarkKind, _ id: String) -> UserMark? {
        rows[Self.markKey(entity, kind, id)]
    }

    private func updateBoolCache(_ entity: UserMarkEntity, _ kind: UserMarkKind, _ id: String, _ value: Bool) {
        let key = Self.markKey(entity, kind, id)
        if value { boolMarks.insert(key) } else { boolMarks.remove(key) }
    }

    func bool(_ kind: UserMarkKind, entity: UserMarkEntity, id: String) -> Bool {
        observe(entity)
        return boolMarks.contains(Self.markKey(entity, kind, id))
    }

    func setBool(_ kind: UserMarkKind, entity: UserMarkEntity, id: String, value: Bool) throws {
        try db.upsertUserMark(entity: entity, id: id, kind: kind, boolValue: value)
        refreshRow(entity, kind, id)
        updateBoolCache(entity, kind, id, value)
        // attended 変更時は自動回収キャッシュを更新
        if kind == .attended {
            refreshAutoCollected()
        }
        // 楽曲お気に入りはコミュニティ集計にも背景送信（失敗時はキューに積む）
        if kind == .favorite && entity == .song {
            Task { await PendingCommunityActions.shared.send(songId: id, value: value) }
        }
        bump(entity)
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
    @ObservationIgnored private var masteryById: [String: UInt8] = [:]

    /// 段階の定義。段数を変えると既存の記録の寄せ先が変わるので、
    /// 変更は `setScale` からだけ行う (規則は core の `remapMasteryLevel`)。
    private(set) var scale: MasteryScale = MasteryScale.standard

    private static let scaleDefaultsKey = "mastery_scale_labels_v1"

    func mastery(songId: String) -> UInt8 {
        _ = masteryVersion
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
        refreshRow(.song, .mastery, songId)
        masteryVersion &+= 1
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
            refreshRow(.song, .mastery, id)
            if clamped == 0 { masteryById.removeValue(forKey: id) } else { masteryById[id] = clamped }
        }
        masteryVersion &+= 1
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
                    refreshRow(.song, .mastery, songId)
                    if moved == 0 { masteryById.removeValue(forKey: songId) } else { masteryById[songId] = moved }
                }
            }
            scheduleBackup()
        }
        masteryVersion &+= 1
    }

    /// 段階ごとの曲数 (設定画面の右に出す数字)。index 0 が LV.1。
    func masteryCounts() -> [Int] {
        _ = masteryVersion
        var counts = [Int](repeating: 0, count: Int(scale.steps))
        for level in masteryById.values {
            let i = Int(level) - 1
            if i >= 0 && i < counts.count { counts[i] += 1 }
        }
        return counts
    }

    func note(entity: UserMarkEntity, id: String) -> String? {
        observe(entity)
        return row(entity, .note, id)?.textValue
    }

    func setNote(entity: UserMarkEntity, id: String, text: String?) throws {
        try db.upsertUserMarkNote(entity: entity, id: id, text: text)
        refreshRow(entity, .note, id)
        bump(entity)
        scheduleBackup()
    }

    // MARK: - チケット受付への申込

    /// その受付への自分の申込の記録。記録なし・知らない保存値は nil。
    func ticketApplication(saleId: String) -> TicketApplication? {
        observe(.ticketSale)
        return ticketApplicationFromRaw(raw: row(.ticketSale, .application, saleId)?.textValue)
    }

    /// 申込の記録を付ける。nil で外す (行ごと消す)。
    func setTicketApplication(saleId: String, _ application: TicketApplication?) throws {
        try db.upsertUserMarkText(entity: .ticketSale, id: saleId, kind: .application,
                                  text: application.map { ticketApplicationRaw(application: $0) })
        refreshRow(.ticketSale, .application, saleId)
        bump(.ticketSale)
        scheduleBackup()
    }

    // MARK: - 歌詞の「ここ好き」

    /// その曲で「ここ好き」を付けた歌詞行の ID。本文は持たない (行 ID だけ)。
    func lyricLikes(songId: String) -> Set<String> {
        _ = lyricLikeVersion
        return Set(lyricLikesParse(stored: row(.song, .lyricLikes, songId)?.textValue))
    }

    /// 行の「ここ好き」を付け外しする。並べ方・消し方はコア (`lyricLikesToggle`)。
    func toggleLyricLike(songId: String, lineId: String) throws {
        let stored = try db.fetchUserMark(entity: .song, id: songId, kind: .lyricLikes)?.textValue
        let next = lyricLikesToggle(stored: stored, lineId: lineId)
        try db.upsertUserMarkText(entity: .song, id: songId, kind: .lyricLikes, text: next)
        refreshRow(.song, .lyricLikes, songId)
        lyricLikeVersion &+= 1
        scheduleBackup()
    }

    /// 座席メモ (公演単位)。 空/空白なら nil で消す。
    func seat(entity: UserMarkEntity, id: String) -> String? {
        observe(entity)
        return row(entity, .seat, id)?.textValue
    }

    func setSeat(entity: UserMarkEntity, id: String, text: String?) throws {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.upsertUserMarkText(entity: entity, id: id, kind: .seat,
                                  text: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        refreshRow(entity, .seat, id)
        bump(entity)
        scheduleBackup()
    }

    // MARK: - 参加種別 (現地 / 配信 / LV、複数可)

    /// 公演に付いている参加形態 (語彙の順)。空 = 不参加。
    /// .attended 行の bool_value=参加有無、text_value=形態 (複数は "live,stream")。
    /// 読み方 (旧来の text なし = 現地 など) はコア (`attendanceTypes`)。
    func attendedTypes(entity: UserMarkEntity, id: String) -> [AttendanceType] {
        observe(entity)
        guard let mark = row(entity, .attended, id), mark.boolValue else { return [] }
        return attendanceTypes(textValue: mark.textValue).compactMap(AttendanceType.init(rawValue:))
    }

    /// 参加マークの保存値そのまま (コアに渡す経路用)。不参加なら nil、形態の無い旧来の行は空文字。
    func attendanceText(entity: UserMarkEntity, id: String) -> String? {
        observe(entity)
        guard let mark = row(entity, .attended, id), mark.boolValue else { return nil }
        return mark.textValue ?? ""
    }

    /// 1 つの形態を付ける (`on`) / 外す。最後の 1 つを外すと参加マークごと外れる。
    /// 付け外しの規則 (並び・区切り) はコア (`attendanceSetType`)。
    func setAttendance(entity: UserMarkEntity, id: String, type: AttendanceType, on: Bool) throws {
        let mark = try db.fetchUserMark(entity: entity, id: id, kind: .attended)
        let text = attendanceSetType(
            current: mark?.textValue, attended: mark?.boolValue ?? false,
            attendanceType: type.rawValue, on: on)
        try writeAttendance(entity: entity, id: id, text: text, added: on ? type : nil)
    }

    /// 参加を取り消す (形態をすべて外す)。
    func clearAttendance(entity: UserMarkEntity, id: String) throws {
        try writeAttendance(entity: entity, id: id, text: nil, added: nil)
    }

    /// `text` が nil なら不参加。`added` はいま付けた形態 (付けたときだけ)。
    private func writeAttendance(entity: UserMarkEntity, id: String, text: String?, added: AttendanceType?) throws {
        try db.setAttendanceMark(entity: entity, id: id, text: text)
        refreshRow(entity, .attended, id)
        updateBoolCache(entity, .attended, id, text != nil)
        // 参加ライブの登録は「一区切りついた瞬間」なのでレビュー依頼の好機に数える。
        // 取り消しは数えない (良い体験ではないので)。
        if added != nil { ReviewPrompt.noteMilestone() }
        // 付けた直後だけ「チケット代を記録しますか」を出す土台にする。載せるのは**いま付けた
        // 1 つの形態** (現地に配信を足したなら配信のチケット代を聞く)。
        // ここに出す条件 (価格が分かっているか / もう記録済みか) は持たせない —
        // DB を引く判断なので、受け取った画面側 (TicketPromptCenter) が決める。
        if entity == .show, let added {
            NotificationCenter.default.post(
                name: .attendanceMarked,
                object: nil,
                userInfo: [AttendanceMarkedKey.showId: id, AttendanceMarkedKey.type: added.rawValue]
            )
        }
        refreshAutoCollected()
        bump(entity)
        scheduleBackup()
    }

    func allMarked(kind: UserMarkKind, entity: UserMarkEntity) -> [String] {
        observe(entity)
        let matching = rows.values.filter { $0.entityType == entity.rawValue && $0.kind == kind.rawValue }
        // 並びは DB の主キー順 (= id 順) に合わせる。
        return UserMark.meaningful(Array(matching)).map(\.entityId).sorted()
    }

    // MARK: - Auto Collected

    /// attended ライブのセトリから自動判定した「回収済み」かどうか
    func isAutoCollected(songId: String) -> Bool {
        _ = showVersion; _ = eventVersion
        return collectedIds.contains(songId)
    }

    /// 自動回収済み song_id セットを再構築する（attended 変更後に呼ぶ）。
    ///
    /// 集計はセトリ全行を公演・イベントに結合する読みなので、メインスレッドでは回さない。
    /// 参加を付け外しした指の下で画面が止まる原因だった。届いたら `collectedIds` を差し替え、
    /// 読んでいた行だけが描き直る。失敗したら前の値を残す。
    func refreshAutoCollected() {
        collectedGeneration &+= 1
        let generation = collectedGeneration
        let db = self.db
        Task { [weak self] in
            do {
                let ids = try await db.fetchAutoCollectedSongIdsAsync()
                guard let self, generation == self.collectedGeneration else { return }
                if ids != self.collectedIds {
                    self.collectedIds = ids
                    self.collectedVersion &+= 1
                }
            } catch {
                logger.error("fetchAutoCollectedSongIds failed: \(error.localizedDescription)")
            }
        }
    }

    /// 自動回収済み song_id の全セット（SongListView フィルタ用）
    func autoCollectedSongIds() -> Set<String> {
        _ = showVersion; _ = eventVersion
        return collectedIds
    }

    // MARK: - App Active

    /// アプリがフォアグラウンドに復帰したときに呼ぶ
    func handleAppActive() {
        PendingCommunityActions.shared.flushPendingFavorites()
    }
}
