import SwiftUI

/// 指定エンティティ(曲/アイドル)が「みんなの投票」の終了お題で取った順位をバッジ表示する。
/// 実績が無ければ高さ0で何も見えない。アイドル詳細・曲詳細に差し込んで使う。
/// バッジ自体はデザインシステムの共通部品 `ImasAwardChip`。タップで対象お題の詳細を開く。
struct PollAchievementBadges: View {
    let entityId: String

    @Environment(AppDatabase.self) private var database
    @State private var achievements: [PollAchievement] = []
    @State private var openPoll: PollLink?

    /// sheet(item:) 用に pollId を Identifiable で包む。
    private struct PollLink: Identifiable { let id: String }

    var body: some View {
        // FlowLayout を常に描画する。`Group { if … }` だと初期(実績ゼロ)で EmptyView になり、
        // EmptyView には .task が installされず取得が走らない (= 永遠に空) ため。
        // 実績ゼロのときは subview 0 で高さ0になり見えない。
        FlowLayout(spacing: 6) {
            ForEach(achievements) { a in
                Button {
                    AppAnalytics.tap("poll_achievement.open")
                    openPoll = PollLink(id: a.pollId)
                } label: {
                    ImasAwardChip(title: a.title, rank: a.rnk)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: entityId) { await load() }
        .sheet(item: $openPoll) { link in
            NavigationStack {
                PollDetailView(pollId: link.id)
                    .environment(database)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("閉じる") { openPoll = nil }
                        }
                    }
            }
        }
    }

    private func load() async {
        achievements = (try? await AppContainer.shared.communityVoting.pollAchievements(entityId: entityId)) ?? []
    }
}
