import SwiftUI

// MARK: - Design Tokens (IntroQuiz 由来を ImasLiveDB 向けに移植)

/// IntroDon 用デザイントークン。デザインシステム(DS)へのエイリアスに統一し、
/// ゲーム画面もアプリ本体と同じトーン(背景/サーフェス/インク/アクセント)に揃える。
/// (旧: 独自の固定ダーク配色。各画面の呼び出し側はそのままで DS 化される)
enum ID {
    // MARK: - Background / Surface → DS
    static let bgDark  = DS.bg
    static let bgLight = DS.bg
    static let menuBg = DS.bg
    static let menuCardWhite   = DS.surface
    static let menuCardSubtle  = DS.fill
    static let surfaceDark        = DS.surface
    static let surfaceDarkCard    = DS.surface
    static let surfaceDarkSubtle  = DS.fill
    static let menuDivider = DS.sep

    // MARK: - Text → DS インク
    static let menuText          = DS.ink
    static let menuTextSecondary = DS.ink2
    static let menuTextMuted     = DS.ink3
    static let t0 = DS.ink
    static let t1 = DS.ink
    static let t2 = DS.ink2
    static let t3 = DS.ink3

    // MARK: - 反転強調カード → accent CTA
    static let menuCardDark     = Color.accentColor
    static let menuCardDarkText = Color.white

    // MARK: - Accent → DS
    static let correct   = DS.success
    static let incorrect = DS.danger
    static let accentGold   = DS.favorite          // ゴールド系は DS のお気に入り色に
    static let accentPink   = DS.pick
    static let accentBlue   = DS.sys
    static let accentPurple = Color(red: 0.58, green: 0.34, blue: 0.92)

    // MARK: - Dividers → DS
    static let dividerDark  = DS.sep
    static let dividerLight = DS.sep

    // MARK: - Corner
    static let corner: CGFloat = 18

    // MARK: - Typography (DS に寄せた system default)
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.imasScaled( size, weight: weight)
    }
}

// MARK: - IntroCorner Shape (left-top only radius — IntroQuiz signature)

struct IDCorner: Shape {
    var radius: CGFloat = ID.corner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Press Button Style

struct IDPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    func idPress() -> some View {
        self.buttonStyle(IDPressStyle())
    }
}
