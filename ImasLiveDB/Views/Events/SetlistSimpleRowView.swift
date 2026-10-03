import SwiftUI

/// セトリの「シンプル表示」1 行。
///
/// 通常の `SetlistRowView` (`ImasSetlistRow`) はジャケ写・Good・カバータグ・ユニットチップ・
/// アバターを載せていて 1 曲で 80pt 前後になる。 20 曲超のライブだと 3 画面ぶんスクロールが要り、
/// 「セトリ全体を 1 枚のスクショで残す」ができない。`ImasRow` も最小高さ (44pt) を敷くので使わず、
/// この行だけは軽い自前の組み方にする。
///
/// この行は公式のセトリ画像と同じ **番号・曲名・演者名だけ**に絞り、
/// 1 曲 40pt 前後に収める。 曲名はブランド色で出すので、色だけで所属が読み取れる。
struct SetlistSimpleRowView: View {
    let item: SetlistRow
    var displayNumber: Int?
    /// 「ユニット名」「全員」「アイドル名／アイドル名」のいずれか。 空なら演者行を出さない。
    /// 決め方は imas-core (`setlist_performer_label`)。
    var performerLabel: String
    /// 曲名の色。 ブランド色 hex。
    var brandHex: String?

    @Environment(\.colorScheme) private var scheme

    private var titleColor: Color {
        guard let brandHex else { return DS.ink }
        return ImasTheme.derive(seed: brandHex, brand: nil, scheme: scheme).accent
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.rowGap) {
            // 番号は幅を固定して曲名の頭を揃える (等幅数字。 二桁で桁が動くと読みにくい)。
            // 通常表示の `ImasSetlistRow` と同じ書体にして、表示モードが替わっても数字の見え方を揃える。
            Text(displayNumber.map { String(format: "%02d", $0) } ?? "–")
                .font(.imasMono(11.5, weight: .bold))
                .foregroundStyle(DS.ink2)
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.songTitle)
                    .imasText(.rowTitle, color: titleColor)
                    .lineLimit(2)

                if !performerLabel.isEmpty {
                    // 公式のセトリ画像に倣って ♪ を頭に置く。 演者は横並びにすると
                    // 長い名前 (アスラン=ベルゼビュートⅡ世 等) で曲名が潰れるため下段に置く。
                    //
                    // 披露の履歴と自分の回収はこの行には出ない (core がシンプル表示では
                    // 空を返す)。1 枚のスクショに収めるための形なので、行を増やさない。
                    Text("♪ \(performerLabel)")
                        .font(.imasCaption2)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, DS.Space.gapTight)
        .contentShape(Rectangle())
    }
}
