import SwiftUI

/// セトリ行の出演者詳細を表示するシート
struct PerformerDetailSheet: View {
    @Environment(AppDatabase.self) private var database
    let songTitle: String
    let idols: [Idol]
    let navigate: (DetailDestination) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(idols) { idol in
                    Button {
                        AppAnalytics.tap("performer_detail.select_idol")
                        navigate(.idol(idol))
                    } label: {
                        HStack(spacing: 12) {
                            IdolAvatarView(idol: idol, size: 40)
                            Text(idol.name)
                                .font(.imasBody)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.imasCaption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("\(songTitle) / 出演者 \(idols.count)名")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .trackScreen("performer_detail")
    }
}
