import SwiftUI

/// コールの編集シートの「ペンライト」側。色・動き・メモを選ぶ。
///
/// 色は棒そのものを並べて選ばせる (名前の文字より先に色が目に入るように)。
/// 並びは よく使う順: 担当色 → この曲の歌唱メンバーの色 → 決まった色。
/// 動きは記号付きの札。もう一度押すと外れる (色を変えるだけの指示もあるので、動きは必須にしない)。
struct CallEditorPenlightSection: View {
    @Binding var penlight: LyricPenlight
    var seed: String?
    let cast: LyricPartCast

    private struct Swatch: Identifiable {
        let id: String
        /// 保存する値。nil は「色の指示なし」。
        let value: String?
        let name: String
        let fill: ImasPenlightStick.Fill
    }

    private var swatches: [Swatch] {
        var out: [Swatch] = [
            Swatch(id: "none", value: nil, name: "指定なし", fill: .none),
            Swatch(id: "oshi", value: "oshi", name: "担当色", fill: .stripes(QS.penlights)),
        ]
        for idol in cast.artists {
            out.append(Swatch(id: "idol:\(idol.id)", value: "idol:\(idol.id)", name: idol.shortName,
                              fill: .color(Color(hexString: idol.color, default: DS.ink3))))
        }
        for preset in lyricPenlightPresets() {
            out.append(Swatch(id: preset.value, value: preset.value, name: preset.name,
                              fill: .color(PenlightLook.color(rgb: preset.rgb))))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp5) {
            colorSection
            moveSection
            noteSection
        }
    }

    // MARK: - 色

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text("色").imasText(.sectionLabel)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: DS.sp2)], spacing: DS.sp3) {
                ForEach(swatches) { swatch in
                    swatchButton(swatch)
                }
            }
        }
    }

    private func swatchButton(_ swatch: Swatch) -> some View {
        let isSelected = penlight.color == swatch.value
        let shape = RoundedRectangle(cornerRadius: DS.rControl(DS.Size.chip), style: .continuous)
        return Button {
            penlight.color = swatch.value
        } label: {
            VStack(spacing: DS.sp1) {
                ImasPenlightStick(fill: swatch.fill, height: 28)
                Text(swatch.name)
                    .font(.imasCaption2)
                    .foregroundStyle(isSelected ? DS.ink : DS.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(shape)
            .overlay(shape.strokeBorder(isSelected ? DS.ink : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 動き

    private var moveSection: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text("動き").imasText(.sectionLabel)
            FlowLayout(spacing: DS.sp2, lineSpacing: DS.sp2) {
                ForEach(LyricPenlightMove.allCases, id: \.self) { move in
                    ImasFilterChip(text: move.label, systemImage: move.symbol,
                                   isSelected: penlight.move == move, seed: seed) {
                        penlight.move = penlight.move == move ? nil : move
                    }
                }
            }
        }
    }

    // MARK: - メモ

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text("メモ").imasText(.sectionLabel)
            ImasCard {
                TextField("2本持ち など", text: Binding(
                    get: { penlight.note ?? "" },
                    set: { penlight.note = String($0.prefix(80)) }
                ))
                .imasText(.body)
            }
            ImasNote("語を選んで付けるとそのフレーズで、行末の ＋ から付けると歌い終わってから振る指示になります。")
        }
    }
}
