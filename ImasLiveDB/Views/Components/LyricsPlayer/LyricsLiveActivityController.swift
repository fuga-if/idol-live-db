import ActivityKit
import Foundation
import OSLog

/// 鳴っている曲の「いま歌っている行」をロック画面に出す (ライブアクティビティ)。
///
/// 再生中バーと同じく `LyricsSession` が預かった歌詞から引く。行が変わったときだけ更新する。
/// 曲を止めた・変えた・歌詞を手放したら即座に終わらせる (`.immediate`: 終わった後に残さない)。
///
/// 更新はアプリが動いている間だけ届く (サーバからの push は使わない。歌詞を外へ出さないため)。
@MainActor
final class LyricsLiveActivityController {
    static let shared = LyricsLiveActivityController()

    /// 出しているアクティビティの id (`Activity` 自体は Sendable でないので持ち回らない)。
    private var activityId: String?
    private var songId: String?
    private var loop: Task<Void, Never>?
    private var lastState: LyricsActivityAttributes.ContentState?

    private init() {}

    /// 再生状態か預かった歌詞が変わったときに呼ぶ。出すべきなら始め、そうでなければ終わらせる。
    func sync() {
        let player = MusicKitService.shared
        guard player.isFullPlayback,
              let entry = LyricsSession.shared.entry(forSongId: player.nowPlayingSongId),
              lyricHasTiming(starts: entry.lyrics.lines.map { $0.startMs.map(Int64.init) }),
              ActivityAuthorizationInfo().areActivitiesEnabled
        else {
            end()
            return
        }
        if songId != entry.song.id { start(entry) }
    }

    private func start(_ entry: LyricsSession.Entry) {
        end()
        let attributes = LyricsActivityAttributes(songTitle: entry.song.title, artistLine: entry.artistLine,
                                                  seedHex: entry.seed)
        let state = Self.state(entry)
        do {
            activityId = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil)).id
            songId = entry.song.id
            lastState = state
        } catch {
            Logger.database.error("lyrics_activity_start_failed: \(error.localizedDescription)")
            return
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                await self?.tick()
            }
        }
    }

    private func tick() async {
        guard let activityId, let entry = LyricsSession.shared.entry(forSongId: songId) else {
            end()
            return
        }
        let state = Self.state(entry)
        guard state != lastState else { return }
        lastState = state
        await Self.update(id: activityId, state: state)
    }

    private func end() {
        loop?.cancel()
        loop = nil
        songId = nil
        lastState = nil
        activityId = nil
        // 前回の起動で残ったもの (アプリが落ちた等) もまとめて終わらせる。
        // いま在るものだけを終わらせる (この後すぐ始める新しい 1 枚を巻き込まない)。
        let ids = Activity<LyricsActivityAttributes>.activities.map(\.id)
        guard !ids.isEmpty else { return }
        Task { await Self.end(ids: ids) }
    }

    private nonisolated static func update(id: String, state: LyricsActivityAttributes.ContentState) async {
        guard let activity = Activity<LyricsActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(.init(state: state, staleDate: nil))
    }

    private nonisolated static func end(ids: [String]) async {
        for activity in Activity<LyricsActivityAttributes>.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// いまの位置から、いま歌っている行と次の行を組む。
    private static func state(_ entry: LyricsSession.Entry) -> LyricsActivityAttributes.ContentState {
        let player = MusicKitService.shared
        let lines = entry.lyrics.lines
        let mainStarts = lines.map { $0.isOverlay ? nil : $0.startMs.map(Int64.init) }
        let index = player.fullPlaybackPositionMs.flatMap {
            lyricActiveLine(starts: mainStarts, positionMs: Int64($0)).map(Int.init)
        }
        let current = index.map { lines[$0] }.flatMap { $0.kind == .lyric ? $0 : nil }
        let next = lines[((index ?? -1) + 1)...].first { $0.kind == .lyric && !$0.isOverlay }
        let singers = current?.singers ?? []
        let calls = lines.flatMap(\.calls)
        let call = player.fullPlaybackPositionMs.flatMap {
            lyricActiveCall(starts: calls.map { $0.startMs.map(Int64.init) }, positionMs: Int64($0)).map { calls[Int($0)].text }
        }
        return .init(line: current.map(mainText), nextLine: next.map(mainText),
                     singerColors: entry.cast.colors(singers), singerNames: entry.cast.names(singers),
                     call: call, isPlaying: player.isPlaying)
    }

    /// 行の中の括弧 (追いかけ) は外す。ロック画面は狭いので本文だけ。
    private static func mainText(_ line: LyricLine) -> String {
        let main = lyricOverlaySplit(text: line.text).main
        return main.isEmpty ? line.text : main
    }
}
