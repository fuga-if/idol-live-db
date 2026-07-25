import SwiftUI

/// セトリの「シンプル表示」1 行。
///
/// 通常の `SetlistRowView` はジャケ写・Good・カバータグ・ユニットチップ・アバターを
/// 載せていて 1 曲で 80pt 前後になる。 20 曲超のライブだと 3 画面ぶんスクロールが要り、
/// 「セトリ全体を 1 枚のスクショで残す」ができない。
///
/// この行は公式のセトリ画像と同じ **番号・曲名・演者名だけ**に絞り、
/// 1 曲 40pt 前後に収める。 曲名はブランド色で出すので、色だけで所属が読み取れる。
struct SetlistSimpleRowView: View {
    let item: SetlistRow
    var displayNumber: Int?
    /// 「ユニット名」「全員」「アイドル名／アイドル名」のいずれか。 空なら演者行を出さない。
    var performerLabel: String
    /// 曲名の色。 ブランド色 hex。
    var brandHex: String?

    @Environment(\.colorScheme) private var scheme

    private var titleColor: Color {
        guard let brandHex else { return DS.ink }
        return ImasTheme.derive(seed: brandHex, brand: nil, scheme: scheme).accent
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.sp3) {
            // 番号は幅を固定して曲名の頭を揃える (等幅数字。 二桁で桁が動くと読みにくい)。
            Text(displayNumber.map { String(format: "%02d", $0) } ?? "–")
                .font(.imasCaption.monospacedDigit())
                .foregroundStyle(DS.ink3)
                .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.songTitle)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                if !performerLabel.isEmpty {
                    // 公式のセトリ画像に倣って ♪ を頭に置く。 演者は横並びにすると
                    // 長い名前 (アスラン=ベルゼビュートⅡ世 等) で曲名が潰れるため下段に置く。
                    Text("♪ \(performerLabel)")
                        .font(.imasCaption2)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, DS.sp2)
        .contentShape(Rectangle())
        .imasCopyable([
            ("曲名をコピー", item.songTitle),
            ("演者をコピー", performerLabel.isEmpty ? nil : performerLabel),
        ])
    }
}
