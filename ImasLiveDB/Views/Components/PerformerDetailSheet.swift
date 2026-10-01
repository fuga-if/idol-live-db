import SwiftUI

/// セトリ行の出演者詳細を表示するシート
struct PerformerDetailSheet: View {
    let songTitle: String
    /// 並べる歌唱者。**アイドルと表示名を 1 組で受け取る。**
    /// 以前は `[Idol]` と `[PerformerRow]` を別々に受け取り、シート側が id で
    /// 突き合わせ直していた (2 本が食い違い得る不変条件を人が守る必要があり、
    /// 人数分の線形探索も走っていた)。組むのは呼び出し側の仕事。
    let performers: [ResolvedPerformer]
    let navigate: (DetailDestination) -> Void

    @State private var imageService = CustomImageService.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(performers) { performer in
                    Button {
                        AppAnalytics.tap("performer_detail.select_idol")
                        navigate(.idol(performer.idol))
                    } label: {
                        // 題は idol.name 固定の `ImasIdolRow` ではなくここで組む。
                        // 歌唱者の表示名設定 (CV 名優先など) で主/副が入れ替わるため、
                        // 解決済みの `performer.name` をそのまま使う必要がある。
                        ImasRow(
                            title: performer.name.primary,
                            subtitle: performer.name.secondary,
                            leading: .avatar(label: performer.idol.shortName, seed: performer.idol.color,
                                            imageURL: imageService.imageURL(for: performer.idol.id)),
                            trailing: .chevron,
                            titleLineLimit: 1
                        )
                    }
                    .buttonStyle(.imasRow)
                }
            }
            .navigationTitle("\(songTitle) / 出演者 \(performers.count)名")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .trackScreen("performer_detail")
    }
}
