import SwiftUI

/// コールの編集シートの「ペンライト」側。色とメモを選ぶ。
///
/// 色は棒そのものを並べて選ばせる (名前の文字より先に色が目に入るように)。
/// 並びは よく使う順: 担当色 → この曲の歌唱メンバーの色 → 決まった色。
/// 振り方は人や現場で違うので選ばせない (書きたければメモに書く)。
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
            Swatch(id: "oshi", value: "oshi", name: "担当色", fill: .oshi),
        ]
        for idol in cast.artists {
            out.append(Swatch(id: "idol:\(idol.id)", value: "idol:\(idol.id)", name: idol.shortName,
                              fill: idol.color.map { .hex($0) } ?? .none))
        }
        for preset in lyricPenlightPresets() {
            out.append(Swatch(id: preset.value, value: preset.value, name: preset.name,
                              fill: .rgb(preset.rgb)))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp5) {
            colorSection
            noteSection
        }
    }

    // MARK: - 色

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text("色").imasText(.sectionLabel)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: DS.sp2)], spacing: DS.sp3) {
                ForEach(swatches) { swatch in
                    ImasPenlightSwatch(fill: swatch.fill, name: swatch.name,
                                       isSelected: penlight.color == swatch.value) {
                        penlight.color = swatch.value
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
                TextField("2本持ち・サビ頭で一斉に など", text: Binding(
                    get: { penlight.note ?? "" },
                    set: { penlight.note = String($0.prefix(80)) }
                ))
                .imasText(.body)
            }
            ImasNote("語を選んで付けるとそのフレーズの指示、行末の ＋ から付けると歌い終わってからの指示になります。")
        }
    }
}
