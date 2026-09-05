import SwiftUI

/// セトリ行の出演者詳細を表示するシート
struct PerformerDetailSheet: View {
    @Environment(AppDatabase.self) private var database
    let songTitle: String
    let idols: [Idol]
    /// 歌唱者の行 (アイドル名と CV 名の両方を持つ)。`idols` と同じ並び・同じ人。
    let performers: [PerformerRow]
    /// どの名前を出すか。規則は imas-core の `performerDisplayName` が持つ。
    var performerName: PerformerNameSetting = .idol
    var isCharacterLive: Bool = false
    let navigate: (DetailDestination) -> Void

    /// idol_id → 表示名。`idols` の並びで引けるようにしておく。
    private func name(for idol: Idol) -> PerformerDisplayName {
        guard let row = performers.first(where: { $0.idolId == idol.id }) else {
            return PerformerDisplayName(primary: idol.name, secondary: nil)
        }
        return row.displayName(performerName, isCharacterLive: isCharacterLive)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(idols) { idol in
                    Button {
                        AppAnalytics.tap("performer_detail.select_idol")
                        navigate(.idol(idol))
                    } label: {
                        HStack(spacing: DS.sp4) {
                            IdolAvatarView(idol: idol, size: 40)
                            VStack(alignment: .leading, spacing: 0) {
                                let shown = name(for: idol)
                                Text(shown.primary)
                                    .font(.imasBody)
                                    .foregroundStyle(DS.ink)
                                if let sub = shown.secondary {
                                    Text(sub)
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                }
                            }
                            Spacer()
                            ImasRowChevron()
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
