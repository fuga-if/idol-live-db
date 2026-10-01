import SwiftUI

/// アイドルを名札のグリッドで並べるセクション。見た目は `ImasIdolCell` (DS §6.6)。
///
/// 楽曲詳細の「歌唱アイドル」(オリジナル歌唱) と「ライブ歌唱歴」(実演者) が同じ見た目。
struct IdolGridSection: View {
    let title: String
    let idols: [Idol]
    let navigate: (DetailDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.header) {
            ImasSectionHeader(title: title, count: "\(idols.count)")
            ImasIdolGrid(columns: 4) {
                ForEach(idols) { idol in
                    Button { navigate(.idol(idol)) } label: {
                        ImasIdolCell(idol: idol, isPick: false)
                    }
                    .buttonStyle(.imasPress)
                }
            }
        }
    }
}
