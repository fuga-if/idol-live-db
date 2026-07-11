import SwiftUI

/// ユニットのアバターを円形表示するコンポーネント。
/// アイドルと異なりユニット単位のカスタム写真はまだ無いため、ブランドキー由来の
/// 安定色 + person.3.fill アイコンで表示する (IdolAvatarView のモノグラム相当)。
struct UnitAvatarView: View {
    let unit: Unit
    var size: CGFloat = 36

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(categoryKey: unit.brandId, scheme: scheme)
        ZStack {
            Circle().fill(t.tint)
            Image(systemName: "person.3.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(t.accent)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(t.ring, lineWidth: 1.5))
        .accessibilityLabel(unit.displayName)
    }
}
