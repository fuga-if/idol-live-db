import SwiftUI

// ImasFloatingWindow 画面の上に浮かぶ小窓 (参考動画の PiP) の枠と、バーのつまみ。
// ImasVideoFrame   動画の場所 (16:9・角丸) に置く面 (再生できない動画の案内など)。

/// 画面の上に浮かぶ小窓の枠。紙の面・角丸・細い縁 (影や光は付けない)。
struct ImasFloatingWindowFrame: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.rSM, style: .continuous)
        content
            .background(DS.surface)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DS.line, lineWidth: 1))
    }
}

/// 小窓のバーの左端に置く、つまんで動かせることを示す印。
struct ImasWindowGrip: View {
    var body: some View {
        Capsule().fill(DS.ink3).frame(width: 4, height: 18)
            .accessibilityHidden(true)
    }
}

extension View {
    /// 画面の上に浮かぶ小窓の枠を付ける。
    func imasFloatingWindow() -> some View { modifier(ImasFloatingWindowFrame()) }

    /// 動画の場所 (16:9・角丸・灰の面) に収める。サムネと同じ大きさ・角。
    func imasVideoFrame() -> some View {
        aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(DS.surface2)
            .clipShape(RoundedRectangle(cornerRadius: DS.rXS, style: .continuous))
    }
}
