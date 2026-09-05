import SwiftUI

/// セトリ行の出演者詳細を表示するシート
struct PerformerDetailSheet: View {
    @Environment(AppDatabase.self) private var database
    let songTitle: String
    /// 並べる歌唱者。**アイドルと表示名を 1 組で受け取る。**
    /// 以前は `[Idol]` と `[PerformerRow]` を別々に受け取り、シート側が id で
    /// 突き合わせ直していた (2 本が食い違い得る不変条件を人が守る必要があり、
    /// 人数分の線形探索も走っていた)。組むのは呼び出し側の仕事。
    let performers: [ResolvedPerformer]
    let navigate: (DetailDestination) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(performers) { performer in
                    Button {
                        AppAnalytics.tap("performer_detail.select_idol")
                        navigate(.idol(performer.idol))
                    } label: {
                        HStack(spacing: DS.sp4) {
                            IdolAvatarView(idol: performer.idol, size: 40)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(performer.name.primary)
                                    .font(.imasBody)
                                    .foregroundStyle(DS.ink)
                                if let sub = performer.name.secondary {
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
            .navigationTitle("\(songTitle) / 出演者 \(performers.count)名")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .trackScreen("performer_detail")
    }
}
