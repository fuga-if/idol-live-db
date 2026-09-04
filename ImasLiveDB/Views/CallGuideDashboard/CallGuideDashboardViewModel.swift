import Foundation
import os
import Observation

/// コールガイド ダッシュボードの取得・組み立て (Presentation)。
///
/// 画面 1 枚 = サーバ 1 リクエスト + ローカル解決 1 回。3 セクションの song_id を
/// **まとめて 1 回**解決するのは、セクションごとに引くと同じ曲を何度も引き当て、
/// 起動直後の一覧より遅くなるため (`TagActivityView.load` と同じ流儀)。
///
/// データ取得は `CallGuideDashboardReading` / `SongReading` ポート越しなので、
/// フェイク注入で単体テストできる。
@MainActor
@Observable
final class CallGuideDashboardViewModel {
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var withCalls: [CallGuideSongRow] = []
    private(set) var recentEdits: [CallGuideEditRow] = []
    private(set) var wanted: [CallGuideWantedRow] = []
    private(set) var tag: CallGuideTagStatus?
    /// 未整備セクションがサーバ側の上限で打ち切られているか (footer の断り書き用)。
    private(set) var wantedTruncated = false

    private let dashboard: any CallGuideDashboardReading
    private let songReading: any SongReading

    /// サーバの `taggedWithoutCalls` はこの件数で打ち切られる (§2.4 のサーバ定数)。
    private static let wantedServerLimit = 100

    nonisolated init(
        dashboard: any CallGuideDashboardReading = AppContainer.shared.callGuideDashboardReading,
        songReading: any SongReading = AppContainer.shared.songReading
    ) {
        self.dashboard = dashboard
        self.songReading = songReading
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await dashboard.callGuideDashboard()
            // 3 セクションぶんの song_id を 1 回で解決する。
            // `listableSongs` は曲一覧と同じ母集合 (派生曲・その他ブランドを落とす) なので、
            // ここで出た曲は必ず一覧・詳細から到達できる。
            var ids = Set(response.songsWithCalls.map(\.songId))
            ids.formUnion(response.recentEdits.map(\.songId))
            ids.formUnion(response.taggedWithoutCalls)
            let songs = try await songReading.listableSongs(ids: Array(ids))
            let byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            // ローカルに無い id の行は落とす。差分同期前 / 統合で消えた曲を
            // 「曲を読み込み中」のまま並べても押せない。件数の齟齬は `callTag` の数で説明が付く。
            withCalls = response.songsWithCalls.compactMap { s in
                guard let song = byId[s.songId] else { return nil }
                return CallGuideSongRow(
                    song: song, callLines: s.callLines, callCount: s.callCount,
                    updatedAt: s.updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    updatedBy: s.updatedBy)
            }
            recentEdits = response.recentEdits.compactMap { e in
                guard let song = byId[e.songId] else { return nil }
                return CallGuideEditRow(
                    id: e.id, song: song, at: Date(timeIntervalSince1970: TimeInterval(e.at)),
                    by: e.by, countBefore: e.callCountBefore, countAfter: e.callCountAfter,
                    linesAfter: e.callLinesAfter)
            }
            wanted = response.taggedWithoutCalls.compactMap { id in
                byId[id].map(CallGuideWantedRow.init)
            }
            wantedTruncated = response.taggedWithoutCalls.count >= Self.wantedServerLimit
            tag = response.callTag
            loadError = nil
            let dropped = ids.count - songs.count
            if dropped > 0 {
                Logger.database.debug("call_guide_dashboard: 未解決の曲 \(dropped) 件を非表示")
            }
        } catch {
            // 失敗しても既に出ている行は消さない (再読み込みで一瞬空になるのを避ける)。
            loadError = (error as? APIClientError)?.errorDescription ?? "通信エラー"
        }
    }
}

// MARK: - 行モデル (Presentation)
//
// View が id → 曲の解決を持たないよう、`Song` は解決済みで渡す。

struct CallGuideSongRow: Identifiable, Sendable {
    var id: String { song.id }
    let song: Song
    let callLines: Int
    let callCount: Int
    let updatedAt: Date?
    let updatedBy: String

    var detailLabel: String { "\(callLines)行・\(callCount)コール" }
}

struct CallGuideEditRow: Identifiable, Sendable {
    let id: Int
    let song: Song
    let at: Date
    let by: String
    let countBefore: Int
    let countAfter: Int
    let linesAfter: Int

    /// サーバの `summary` は監査用の機械文字列なので、表示文言はここで組み立てる
    /// (純粋な導出なのでテスト対象)。
    var label: String {
        if countBefore == 0 && countAfter > 0 { return "コールを付けた (\(countAfter)件・\(linesAfter)行)" }
        if countAfter == 0 && countBefore > 0 { return "コールを削除した (\(countBefore)件→0)" }
        return "コールを更新 (\(countBefore)→\(countAfter)件)"
    }
}

struct CallGuideWantedRow: Identifiable, Sendable {
    var id: String { song.id }
    let song: Song
}
