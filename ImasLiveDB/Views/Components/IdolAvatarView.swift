import SwiftUI

/// アイドルのアバターを円形表示するコンポーネント。
/// カスタム画像があれば表示、なければデザインシステムのモノグラム
/// (淡ティント面 + 細リング + アクセント頭文字) でフォールバックする。
/// 担当 (`isPick`) のときはトーナル二重輪 (D3) をまとう。
struct IdolAvatarView: View {
    let idol: Idol
    var size: CGFloat = 56
    /// 担当アイドルのとき true → 外側にトーナル二重輪を表示。
    var isPick: Bool = false

    @State private var imageService = CustomImageService.shared

    var body: some View {
        ImasAvatar(
            label: idol.shortName,
            seed: idol.color,
            size: size,
            isPick: isPick,
            imageURL: imageService.imageURL(for: idol.id)
        )
        .accessibilityLabel(idol.name)
    }
}
