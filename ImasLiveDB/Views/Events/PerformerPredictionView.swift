import SwiftUI

// MARK: - PerformerPredictionView

/// 「歌唱メンバー予想」UI。
/// SetlistPredictionView 内の各曲行から展開して表示する。
/// 候補アイドル = その公演の show_cast に登録されたキャスト。
struct PerformerPredictionView: View {
    let showId: String
    let songId: String
    /// 投稿導線の文脈色 (公演のブランド色)。SetlistPredictionView と統一。
    var seed: String? = nil
    /// 未ログイン時のログイン誘導ゲート。親 (SetlistPredictionView) の requireLogin/showLogin/afterLogin
    /// 機構を再利用する。ログイン済みなら即 action、未ログインならログインシート → 完了後に action を実行。
    /// 親から注入することで、セトリ予想トグルと同じログイン誘導体験に揃える。
    var requireLogin: (@escaping () -> Void) -> Void

    @State private var performers: [PerformerPrediction] = []
    @State private var castIdols: [Idol] = []
    /// この曲のオリメン (idol_id)。出演者の並びを「オリメン」と「ほかの出演者」に分ける。
    @State private var originalIds: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let authService = AuthService.shared
    private let predictionService = PredictionService.shared

    private var totalVotes: Int { performers.reduce(0) { $0 + $1.voteCount } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            header
            content
        }
        .task { await load() }
    }

    // MARK: - Header

    // 展開元のボタンが既に「歌唱メンバー予想」と表示しているため、ここでは
    // タイトルを繰り返さず、何をするかと票数だけ出す。
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
            Text("誰が歌う？ 押して予想").imasText(.sectionLabel)
            Spacer(minLength: DS.Space.gap)
            if totalVotes > 0 {
                Text("\(totalVotes)票").imasText(.meta, color: DS.ink3)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && performers.isEmpty && castIdols.isEmpty {
            ImasInlineLoading()
        } else if castIdols.isEmpty {
            ImasNote("出演キャスト情報がありません")
        } else {
            let originals = castIdols.filter { originalIds.contains($0.id) }
            // ほかの出演者は票の多い順 (同票は出演者の並びのまま)。
            let others = castIdols.enumerated()
                .filter { !originalIds.contains($0.element.id) }
                .sorted { (voteCount($0.element), -$0.offset) > (voteCount($1.element), -$1.offset) }
                .map(\.element)
            if !originals.isEmpty {
                group("オリメン", originals)
            }
            group(originals.isEmpty ? nil : "ほかの出演者", others)
        }

        if let errorMessage {
            ImasNotice(kind: .error, message: errorMessage)
        }
    }

    // MARK: - Performer Chips

    private func voteCount(_ idol: Idol) -> Int {
        performers.first { $0.idolId == idol.id }?.voteCount ?? 0
    }

    /// 出演者のチップの並び。選んだ人だけ墨の塗り、先頭のペンライトは担当色。票はチップの中の数字。
    @ViewBuilder
    private func group(_ title: String?, _ idols: [Idol]) -> some View {
        if !idols.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                if let title {
                    Text(title).imasText(.meta, color: DS.ink2)
                }
                FlowLayout(spacing: DS.Space.gap) {
                    ForEach(idols) { idol in
                        let prediction = performers.first { $0.idolId == idol.id }
                        let votes = prediction?.voteCount ?? 0
                        let voted = prediction?.hasUserVoted ?? false
                        ImasFilterChip(
                            text: votes > 0 ? "\(idol.shortName) \(votes)" : idol.shortName,
                            isSelected: voted,
                            seed: idol.color,
                            leading: .dot
                        ) {
                            Task { await handleVote(idol: idol, currentPrediction: prediction) }
                        }
                        .accessibilityLabel(voted
                            ? "\(idol.name) の予想を取り消す (現在\(votes)票)"
                            : "\(idol.name) を予想 (現在\(votes)票)")
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        errorMessage = nil
        // 出演キャストはポート経由でオフメイン取得。予想データ取得と順次呼ぶ。
        castIdols = (try? await AppContainer.shared.showReading.showCastIdols(showId: showId)) ?? []
        originalIds = (try? await AppContainer.shared.showReading.originalArtistIds(songIds: [songId]))?[songId] ?? []
        performers = (try? await predictionService.fetchPerformers(showId: showId, songId: songId)) ?? []
        isLoading = false
    }

    private func handleVote(idol: Idol, currentPrediction: PerformerPrediction?) async {
        guard authService.isSignedIn else {
            // 未ログインでチップを押したら無反応ではなくログイン誘導から始める。
            // 親の requireLogin (showLogin/afterLogin 機構) を再利用し、ログイン後に投票を続行する。
            requireLogin { Task { await handleVote(idol: idol, currentPrediction: currentPrediction) } }
            return
        }
        errorMessage = nil
        do {
            if currentPrediction?.hasUserVoted == true {
                try await predictionService.unvotePerformer(showId: showId, songId: songId, idolId: idol.id)
            } else {
                _ = try await predictionService.votePerformer(showId: showId, songId: songId, idolId: idol.id)
            }
            performers = (try? await predictionService.fetchPerformers(showId: showId, songId: songId)) ?? []
        } catch {
            errorMessage = error.localizedDescription
            AppAnalytics.event("prediction_vote_failed")
        }
    }
}
