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
    /// 「ガイドがある曲」がサーバ側の上限で打ち切られているか (断り書き用)。
    private(set) var withCallsTruncated = false
    /// 未整備セクションがサーバ側の上限で打ち切られているか (footer の断り書き用)。
    private(set) var wantedTruncated = false
    /// サーバが返したのに手元の曲マスタで解決できず、行にできなかった件数。
    private(set) var droppedCount = 0
    /// サーバがこの一覧を組み立てた時刻。エッジキャッシュ越しなので「今」ではない。
    private(set) var generatedAt: Date?

    private let dashboard: any CallGuideDashboardReading
    private let songReading: any SongReading

    /// サーバ側の件数上限 (§2.4 のサーバ定数)。ここに達していたら「打ち切られた」とみなす。
    private static let withCallsServerLimit = 200
    private static let wantedServerLimit = 100

    /// `load()` の世代。`await` の間に次の `load()` が始まっていたら、古い応答は捨てる
    /// (`SongListViewModel.currentTaskId` と同じ規約。`refreshable` と `task` が
    /// 重なったときに、遅れて戻ってきた古い一覧で新しい一覧を上書きしないため)。
    private var currentLoadId = UUID()

    nonisolated init(
        dashboard: any CallGuideDashboardReading = AppContainer.shared.callGuideDashboardReading,
        songReading: any SongReading = AppContainer.shared.songReading
    ) {
        self.dashboard = dashboard
        self.songReading = songReading
    }

    func load() async {
        let loadId = UUID()
        currentLoadId = loadId
        isLoading = true
        defer { if currentLoadId == loadId { isLoading = false } }
        do {
            let response = try await dashboard.callGuideDashboard()
            guard currentLoadId == loadId else { return }
            // 3 セクションぶんの song_id を 1 回で解決する。
            // `listableSongs` は曲一覧と同じ母集合なので、ここで出た曲は必ず一覧・詳細から
            // 到達できる。**裏を返すと、派生曲 (ソロ Ver. 等) と「その他」ブランドの曲は
            // コールが書かれていてもこの画面には出ない** (一覧が隠しているものを、この画面
            // だけが見せる状態を作らない)。差分同期前で手元に無い曲も同じく出ない。
            // 落とした件数は `droppedCount` に持ち、footer で「N曲は表示できません」と断る。
            var ids = Set(response.songsWithCalls.map(\.songId))
            ids.formUnion(response.recentEdits.map(\.songId))
            ids.formUnion(response.taggedWithoutCalls)
            let songs = try await songReading.listableSongs(ids: Array(ids))
            guard currentLoadId == loadId else { return }
            let byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            // ローカルに無い id の行は落とす。差分同期前 / 統合で消えた曲を
            // 「曲を読み込み中」のまま並べても押せない。件数の齟齬は `callTag` の数で説明が付く。
            withCalls = response.songsWithCalls.compactMap { s in
                guard let song = byId[s.songId] else { return nil }
                return CallGuideSongRow(
                    song: song, callLines: s.callLines, callCount: s.callCount,
                    // 0 は「記録なし」。1970-01-01 として「56年前」と出さない。
                    updatedAt: s.updatedAt > 0 ? Date(timeIntervalSince1970: TimeInterval(s.updatedAt)) : nil,
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
            withCallsTruncated = response.songsWithCalls.count >= Self.withCallsServerLimit
            wantedTruncated = response.taggedWithoutCalls.count >= Self.wantedServerLimit
            tag = response.callTag
            generatedAt = Date(timeIntervalSince1970: TimeInterval(response.generatedAt))
            loadError = nil
            droppedCount = max(0, ids.count - songs.count)
            if droppedCount > 0 {
                Logger.database.debug("call_guide_dashboard: 未解決の曲 \(self.droppedCount) 件を非表示")
            }
        } catch {
            // 古い世代の失敗で、新しい読み込みの成功を上書きしない。
            guard currentLoadId == loadId else { return }
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
