import SwiftUI

/// アイドルアイコンをオーバーラップして横並びに表示するスタック。
/// Slack / FaceTime の参加者ピル風の見た目。中身は DesignSystem の `ImasAvatarStack`
/// (入り切らなかった人数の丸バッジ・重なりの打ち消しなど、見た目のロジックはそちらに一本化)。
struct StackedAvatars: View {
    let idols: [Idol]
    var maxVisible: Int = 5
    var size: CGFloat = 24
    var onTap: (() -> Void)? = nil

    var body: some View {
        ImasAvatarStack(people: idols.map(performer), maxVisible: maxVisible, size: size, onTap: onTap)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("出演者 \(idols.count)名")
    }

    private func performer(_ idol: Idol) -> ImasPerformer {
        ImasPerformer(id: idol.id, name: idol.name, color: idol.color,
                      iconLabel: idol.shortName, imageURL: CustomImageService.shared.imageURL(for: idol.id))
    }
}
