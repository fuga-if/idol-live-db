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
            return .oshi
        case .idol:
            return parsed.idolId.flatMap { cast.colors([$0]).first }.map { .hex($0) } ?? .none
        case .fixed:
            return .rgb(parsed.rgb ?? 0)
        }
    }

    /// 色の名前 (アイドルの色は「春香の色」)。名付けられなければ nil。
    var colorName: String? {
        let given = parsed?.kind == .idol
            ? parsed?.idolId.flatMap { cast.names([$0]).first }.map { "\($0)の色" }
            : nil
        return lyricPenlightColorName(spec: penlight.color, given: given)
    }

    /// 古いアプリ向けの代わりの文言 (保存するときコールの text に入れる)。読み上げにも使う。
    var description: String {
        lyricPenlightFallbackText(color: penlight.color, colorName: colorName, note: penlight.note)
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
        ImasPenlightCueLabel(fill: look.fill, note: penlight.note)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(look.description)
    }
}
