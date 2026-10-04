import SwiftUI

// =============================================================================
// Liquid Glass (iOS 26) は**浮いている枠だけ**に使う。
//
// 紙面 (地・一覧・カード・帯) は今までどおり平ら。ぼかした光・光沢を中身に足さない決まり
// (docs/DESIGN_SYSTEM.md・グラデーションと光の禁止) はそのまま。ガラスにするのは、
// 中身の上に浮いて中身が透けて見える部品 — 再生ボタン群・再生中バー・OS のツールバー — だけ。
// iOS 17〜25 と古い SDK (CI の macos-15) では、平らな面のまま。
// =============================================================================

extension View {
    /// 中身の上に浮く枠の面 (歌詞プレイヤーの再生ボタン群など)。iOS 26 は Liquid Glass、
    /// それより前は平らな面 (`DS.surface`)。
    @ViewBuilder
    func imasFloatingChrome(cornerRadius: CGFloat = DS.rXL) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(DS.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        background(DS.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    /// OS が描くガラス (タブバーの上の枠など) の中に薄く紙の色を敷く。ガラスだけだと後ろの文字が
    /// 読めるほど透け、縁に後ろの色がにじむので、透けは枠の手触りだけに留める。
    func imasGlassPaperFill() -> some View {
        background(DS.surface.opacity(0.82), in: Capsule())
    }
}
