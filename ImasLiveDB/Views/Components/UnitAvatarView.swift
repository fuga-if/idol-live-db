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
            ZStack {
                // 透過ロゴの下地。 .fit だと円の四隅が余るので、 敷かないと
                // リングの中に絵が浮いて見える。
                t.tint
                LazyImage(url: imageURL) { state in
                    if let img = state.image {
                        // ユニットアイコンは横長のロゴタイプが多い (SideM 等)。
                        // .fill だと左右が切れて何のユニットか判らなくなるので .fit で全体を収める。
                        // シャニの円形アイコンは 1:1 なのでほぼ余白なしで収まり、
                        // SideM の横長ロゴだけがひと回り小さく収まる。
                        img.resizable().scaledToFit().padding(size * 0.04)
                    } else {
                        fallback(t)
                    }
                }
                .processors([
                    ImageProcessors.Resize(
                        size: CGSize(width: px, height: px), unit: .pixels, contentMode: .aspectFit
                    )
                ])
            }
        } else {
            fallback(t)
        }
    }

    private func fallback(_ t: ImasTheme) -> some View {
        ZStack {
            t.tint
            Image(systemName: "person.3.fill")
                .font(.imasDisplay(size * 0.42, weight: .semibold))
                .foregroundStyle(t.accent)
        }
    }
}
