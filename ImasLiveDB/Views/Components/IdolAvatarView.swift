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
    /// false のとき、担当リング分の外形余白を予約せず可視アバターぴったりのサイズにする。
    /// 呼び出し元が独自にリングを重ねる (isPick を使わない) 場合に指定する。
    var reservesPickRing: Bool = true

    @State private var imageService = CustomImageService.shared

    var body: some View {
        ImasAvatar(
            label: idol.shortName,
            seed: idol.color,
            size: size,
            isPick: isPick,
            imageURL: imageService.imageURL(for: idol.id),
            reservesPickRing: reservesPickRing
        )
        .accessibilityLabel(idol.name)
    }
}
