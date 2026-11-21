import UIKit

/// コアが検査した操作 1 件を、既存の書き込み口 1 回に写す。
///
/// 規則 (どの操作があるか・id が実在するか・どこまで届くか) はコア (`domain::ai_actions`)。
/// ここは OS の持ち物 (端末の DB・再生・サーバへの送信) を呼ぶだけで、判断を足さない。
@MainActor
enum AssistantExecutor {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 実行のあと、画面の側でやること。
    enum Opened {
        /// シートの中に詳細を積む。
        case detail(DetailDestination)
        /// 一覧のタブへ移った (シートを閉じる)。
        case list
        /// 利用者の持ち物の画面 (シートの中に積む)。
        case screen(Screen)
    }

    /// `open_screen` で開ける画面。rawValue はコアのキー (`ai_actions::SCREENS`)。
    enum Screen: String, Identifiable, Hashable {
        case producerCard = "producer_card"
        case cardCase = "card_case"
        case ledger, playlists, mastery, favorites
        case myPredictions = "my_predictions"
        case myVotes = "my_votes"
        case myContributions = "my_contributions"

        var id: String { rawValue }
    }

    /// - Parameter images: その番の発言に添えた画像 (P名刺の写真・素材に使う)。
    /// - Returns: 開くもの (`open` / `open_list` / 名刺を直したとき)。
    @discardableResult
    static func perform(_ action: AiAction, images: [UIImage] = []) async throws -> Opened? {
        let marks = UserMarkService.shared
        let container = AppContainer.shared
        switch action {
        case .setAttendance(let showId, let attendance, let on):
            guard let type = AttendanceType(rawValue: attendance) else { throw Failure(message: "参加の種類が分かりません") }
            try marks.setAttendance(entity: .show, id: showId, type: type, on: on)
        case .setFavoriteSong(let songId, let on):
            try marks.setBool(.favorite, entity: .song, id: songId, value: on)
        case .setMyPick(let idolId, let on):
            try marks.setBool(.myPick, entity: .idol, id: idolId, value: on)
        case .setNote(let entity, let id, let text):
            guard let entity = UserMarkEntity(rawValue: entity) else { throw Failure(message: "メモを書けない対象です") }
            try marks.setNote(entity: entity, id: id, text: text.isEmpty ? nil : text)
        case .setSeat(let showId, let text):
            try marks.setSeat(entity: .show, id: showId, text: text.isEmpty ? nil : text)
        case .addPersonalTag(let entity, let id, let name):
            guard PersonalTagService.shared.addTag(entityType: entity, entityId: id, name: name) else {
                throw Failure(message: "タグを付けられませんでした (同じ名前のタグがあるかもしれません)")
            }
        case .removePersonalTag(let entity, let id, let name):
            PersonalTagService.shared.removeTag(entityType: entity, entityId: id, name: name)
        case .createPlaylist(let name, let songIds):
            let playlist = try await container.playlists.create(name: name)
            do {
                try await container.playlists.setSongIds(playlistId: playlist.id, songIds: songIds)
            } catch {
                // 曲を入れられなかったら、空のプレイリストを残さない。
                try? await container.playlists.delete(id: playlist.id)
                throw error
            }
        case .addToPlaylist(let playlistId, let songIds):
            try await container.playlists.append(playlistId: playlistId, songIds: songIds)
        case .addExpense(let date, let category, let amount, let showId, let eventId, let note):
            try await container.ledgerWriting.save(
                Expense.make(date: date, category: category, amount: amount, showId: showId, eventId: eventId, note: note)
            )
        case .open(let entity, let id, let section):
            return .detail(try await destination(entity: entity, id: id, section: section))
        case .playSongs(let songIds):
            let songs = try await orderedSongs(songIds)
            guard await PlaylistPlayback.play(songs) else {
                throw Failure(message: "続けて流すには Apple Music の契約か Spotify の連携が要ります")
            }
        case .setOwnedRelease(let releaseId, let on):
            try marks.setBool(.owned, entity: .release, id: releaseId, value: on)
        case .setTicketApplication(let saleId, let application):
            try marks.setTicketApplication(saleId: saleId, application)
        case .setMastery(let songIds, let level):
            try marks.setMastery(songIds: songIds, level: UInt8(clamping: level))
        case .addToCalendar(let showId):
            guard let show = try await container.showReading.show(id: showId),
                  let event = try await container.eventReading.event(id: show.eventId) else {
                throw Failure(message: "公演が見つかりませんでした")
            }
            if case .permissionDenied = try await CalendarExportService.shared.exportShow(show, event: event) {
                throw Failure(message: "カレンダーへの追加が許可されていません。設定アプリで許可してください")
            }
        case .setNotification(let kind, let on):
            // 保存先は設定画面のスイッチと同じ鍵。予約の組み直しも同じ口。
            UserDefaults.standard.set(on, forKey: "notif_\(kind)")
            await NotificationService.shared.rescheduleAll(database: .shared, reason: on ? .refresh : .settingTurnedOff)
        case .openList(let list, let query):
            let tab: RootTab
            switch list {
            case "events": tab = .events
            case "songs": tab = .songs
            case "idols": tab = .idols
            default: throw Failure(message: "開く先が見つかりませんでした")
            }
            CrossTabSearch.shared.hand(query, to: tab)
            return .list
        case .setProducerCard(let edit):
            try await AssistantCardEditor.apply(edit, images: images)
            // 直した結果をその場で見せる。
            return .screen(.producerCard)
        case .openScreen(let screen):
            guard let screen = Screen(rawValue: screen) else { throw Failure(message: "開く先が見つかりませんでした") }
            return .screen(screen)
        case .predictSong(let showId, let songId, let on):
            if on {
                _ = try await PredictionService.shared.vote(showId: showId, songId: songId)
            } else {
                try await PredictionService.shared.unvote(showId: showId, songId: songId)
            }
        case .likeSetlistSong(let showId, let songId, let on):
            if on {
                _ = try await SetlistLikeService.shared.like(showId: showId, songId: songId)
            } else {
                _ = try await SetlistLikeService.shared.unlike(showId: showId, songId: songId)
            }
        }
        return nil
    }

    private static func orderedSongs(_ ids: [String]) async throws -> [Song] {
        let songs = try await AppContainer.shared.songReading.songs(ids: ids)
        let byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    private static func destination(entity: String, id: String, section: String) async throws -> DetailDestination {
        let container = AppContainer.shared
        let missing = Failure(message: "開く先が見つかりませんでした")
        switch entity {
        case "song":
            guard let song = try await orderedSongs([id]).first else { throw missing }
            switch section {
            case "history": return .songHistory(song)
            case "lyrics": return .songLyrics(song)
            default: return .song(song)
            }
        case "idol":
            guard let idol = try await container.idolReading.idols(ids: [id]).first else { throw missing }
            return .idol(idol)
        case "event":
            guard let event = try await container.eventReading.event(id: id) else { throw missing }
            return .event(event)
        case "show":
            guard let show = try await container.showReading.show(id: id) else { throw missing }
            return .show(show)
        case "unit":
            guard let unit = try await container.unitReading.unit(id: id) else { throw missing }
            return .unit(unit)
        default:
            throw missing
        }
    }
}
