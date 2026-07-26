import SwiftUI

/// アイドルを顔アイコン + 名前のグリッドで並べるセクション。
///
/// 楽曲詳細の「歌唱アイドル」(オリジナル歌唱) と「ライブ歌唱歴」(実演者) が同じ見た目。
struct IdolGridSection: View {
    let title: String
    let idols: [Idol]
    let navigate: (DetailDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: title, count: "\(idols.count)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: DS.sp3)], spacing: DS.sp4) {
                ForEach(idols) { idol in
                    Button { navigate(.idol(idol)) } label: {
                        VStack(spacing: 6) {
                            IdolAvatarView(idol: idol, size: 52)
                            Text(idol.name)
                                .font(.imasCaption.weight(.medium))
                                .foregroundStyle(DS.ink2)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
