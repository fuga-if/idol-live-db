import SwiftUI

// MARK: - PerformerPredictionView

/// 「歌唱メンバー予想」UI。
/// SetlistPredictionView 内の各曲行から展開して表示する。
/// 候補アイドル = その公演の show_cast に登録されたキャスト。
struct PerformerPredictionView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme

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
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let authService = AuthService.shared
    private let predictionService = PredictionService.shared

    private var totalVotes: Int { performers.reduce(0) { $0 + $1.voteCount } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            header
            content
        }
        .task { await load() }
    }

    // MARK: - Header

    // 展開元のトグル行が既に「歌唱メンバー予想」と表示しているため、ここでは
    // タイトルを繰り返さず票数だけ出す (文言の二重表示を避ける)。票が無ければ非表示。
    @ViewBuilder
    private var header: some View {
        if totalVotes > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.imasScaled(11, weight: .semibold))
                    .foregroundStyle(DS.ink3)
                Text("\(totalVotes)票")
                    .font(.imasCaption.monospacedDigit())
                    .foregroundStyle(DS.ink3)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && performers.isEmpty && castIdols.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.sp1)
        } else if castIdols.isEmpty {
            Text("出演キャスト情報がありません")
                .font(.imasCaption)
                .foregroundStyle(DS.ink3)
        } else {
            performerChips
        }

        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.imasCaption)
                .foregroundStyle(DS.danger)
        }
    }

    // MARK: - Performer Chips

    /// 出演キャストのチップ一覧。投票済みはメンバーカラーで塗り、未投票はアウトライン。
    private var performerChips: some View {
        FlowLayout(spacing: DS.sp2) {
            ForEach(castIdols) { idol in
                let prediction = performers.first { $0.idolId == idol.id }
                PerformerChip(
                    idol: idol,
                    voteCount: prediction?.voteCount ?? 0,
                    hasUserVoted: prediction?.hasUserVoted ?? false,
                    seed: seed,
                    onTap: { await handleVote(idol: idol, currentPrediction: prediction) }
                )
            }
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        errorMessage = nil
        // castIdols は @MainActor 上の同期 DB 読み取り。async let と組み合わせず順次呼ぶ。
        castIdols = (try? database.fetchShowCastIdols(showId: showId)) ?? []
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

// MARK: - PerformerChip

/// アイドル1人ぶんの投票チップ。
/// 投票済み → メンバーカラー塗りつぶし、未投票 → メンバーカラーアウトライン。
private struct PerformerChip: View {
    @Environment(\.colorScheme) private var scheme
    let idol: Idol
    let voteCount: Int
    let hasUserVoted: Bool
    var seed: String? = nil
    let onTap: () async -> Void

    private var memberColor: Color {
        Color(hexString: idol.color, default: Color(hexString: seed))
    }

    var body: some View {
        Button {
            Task { await onTap() }
        } label: {
            HStack(spacing: 5) {
                ColorDotView(hex: idol.color, size: 7, isDecorative: true)
                Text(idol.shortName)
                    .font(.imasScaled(13, weight: .semibold))
                    .lineLimit(1)
                if voteCount > 0 {
                    Text("\(voteCount)")
                        .font(.imasCaption.monospacedDigit().weight(.semibold))
                        .opacity(0.8)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(hasUserVoted ? .white : memberColor)
            .background(
                hasUserVoted ? memberColor : memberColor.opacity(0.12),
                in: Capsule()
            )
            .overlay(
                hasUserVoted ? nil : Capsule().strokeBorder(memberColor.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Capsule())
            .accessibilityLabel(hasUserVoted
                ? "\(idol.name) の予想を取り消す (現在\(voteCount)票)"
                : "\(idol.name) を予想 (現在\(voteCount)票)")
        }
        .buttonStyle(.borderless)
    }
}
