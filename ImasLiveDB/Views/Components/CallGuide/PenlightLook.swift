import SwiftUI

/// ペンライトの指示を描くための引き方。色の書き方の読みはコア (`lyricPenlightColor`)、
/// アイドルの色と名前は原唱者 (`LyricPartCast`) から引く。
struct PenlightLook {
    let penlight: LyricPenlight
    let cast: LyricPartCast

    private var parsed: PenlightColor? { penlight.parsedColor }

    var fill: ImasPenlightStick.Fill {
        guard let parsed else { return .none }
        switch parsed.kind {
        case .oshi:
            return .stripes(QS.penlights)
        case .idol:
            guard let hex = parsed.idolId.flatMap({ cast.colors([$0]).first }) else { return .none }
            return .color(Color(hexString: hex, default: DS.ink3))
        case .fixed:
            return .color(Self.color(rgb: parsed.rgb ?? 0))
        }
    }

    var isOff: Bool { penlight.move == .off }

    /// 色の名前 (アイドルの色は「春香の色」)。名付けられなければ nil。
    var colorName: String? {
        let given = parsed?.kind == .idol
            ? parsed?.idolId.flatMap { cast.names([$0]).first }.map { "\($0)の色" }
            : nil
        return lyricPenlightColorName(spec: penlight.color, given: given)
    }

    /// 古いアプリ向けの代わりの文言 (保存するときコールの text に入れる)。読み上げにも使う。
    var description: String {
        lyricPenlightFallbackText(color: penlight.color, colorName: colorName,
                                  moveKey: penlight.move?.rawValue, note: penlight.note)
    }

    static func color(rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255)
    }
}

// MARK: - 原唱者を下へ配る

private struct LyricPartCastKey: EnvironmentKey {
    static let defaultValue = LyricPartCast.empty
}

extension EnvironmentValues {
    /// 歌詞の部品がアイドルの色・名前を引く表 (ペンライトの「アイドルの色」に使う)。
    var lyricPartCast: LyricPartCast {
        get { self[LyricPartCastKey.self] }
        set { self[LyricPartCastKey.self] = newValue }
    }
}

// MARK: - 歌詞タブの 1 行

/// 歌詞タブのコール欄に並ぶペンライトの指示 1 つ。
struct CallGuidePenlightLabel: View {
    let penlight: LyricPenlight
    @Environment(\.lyricPartCast) private var cast

    var body: some View {
        let look = PenlightLook(penlight: penlight, cast: cast)
        ImasPenlightCueLabel(fill: look.fill, moveSymbol: penlight.move?.symbol,
                             isOff: look.isOff, note: penlight.note)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(look.description)
    }
}
