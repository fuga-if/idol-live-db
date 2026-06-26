import SwiftUI

/// 指定エンティティ(曲/アイドル)が「みんなの投票」の終了お題で取った順位をバッジ表示する。
/// 実績が無ければ何も描画しない。アイドル詳細・曲詳細に差し込んで使う。
struct PollAchievementBadges: View {
    let entityId: String
    @State private var achievements: [PollAchievement] = []

    var body: some View {
        Group {
            if !achievements.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(achievements) { a in
                        HStack(spacing: 4) {
                            Image(systemName: a.rnk == 1 ? "crown.fill" : "rosette")
                                .font(.imasScaled(11))
                            Text("\(a.title) \(a.rankLabel)")
                                .font(.imasCaption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(a.rnk == 1 ? .white : DS.ink)
                        .background(
                            a.rnk == 1
                                ? AnyShapeStyle(LinearGradient(colors: [.orange, .yellow],
                                                               startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(DS.fill),
                            in: Capsule()
                        )
                    }
                }
            }
        }
        .task(id: entityId) { await load() }
    }

    private func load() async {
        achievements = (try? await AppContainer.shared.communityVoting.pollAchievements(entityId: entityId)) ?? []
    }
}
