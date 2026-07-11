import Nuke
import NukeUI
import SwiftUI

/// ユニットのアバターを円形表示するコンポーネント。
/// カスタム画像 (`GallerySectionView(kind: .unit)` で登録したアイコン) があれば表示し、
/// 無ければブランドキー由来の安定色 + person.3.fill アイコン (IdolAvatarView のモノグラム相当)。
struct UnitAvatarView: View {
    let unit: Unit
    var size: CGFloat = 36

    @Environment(\.colorScheme) private var scheme
    @State private var imageService = CustomImageService.shared

    var body: some View {
        let t = ImasTheme.derive(categoryKey: unit.brandId, scheme: scheme)
        core(t)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(t.ring, lineWidth: 1.5))
            .accessibilityLabel(unit.displayName)
    }

    @ViewBuilder private func core(_ t: ImasTheme) -> some View {
        if let imageURL = imageService.imageURL(for: unit.id, kind: .unit) {
            let px = Int(size * UIScreen.main.scale)
            LazyImage(url: imageURL) { state in
                if let img = state.image {
                    img.resizable().scaledToFill()
                } else {
                    fallback(t)
                }
            }
            .processors([ImageProcessors.Resize(size: CGSize(width: px, height: px), unit: .pixels)])
        } else {
            fallback(t)
        }
    }

    private func fallback(_ t: ImasTheme) -> some View {
        ZStack {
            t.tint
            Image(systemName: "person.3.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(t.accent)
        }
    }
}
