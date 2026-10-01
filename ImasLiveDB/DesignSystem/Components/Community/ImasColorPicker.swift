import SwiftUI

// =============================================================================
// タグの色選択 (docs/DESIGN_SYSTEM.md §7)
//
// ImasColorPicker  色の丸から 1 つ選ぶ。「なし」+ プリセット 10 色 + カスタム (OS の ColorPicker)。
//                  選んだ色の丸に墨の輪、読み上げは色名。タグの色のように「データとしての色」を
//                  そのまま塗る数少ない部品 (`ImasSwatch` と同じ例外。§1.2)。
//                  以前は `Views/Tags/TagColorPicker.swift` に画面の部品として置かれていた。
// =============================================================================

struct ImasColorPicker: View {
    @Binding var selectedHex: String

    /// システム ColorPicker 用。初期値だけ selectedHex から取り、以後は独立 (プリセット選択では同期しない)。
    @State private var customColor: Color

    /// 並べるプリセット (彩度・色相をばらして視認しやすい 10 色)。
    static let presets: [String] = [
        "#FF6B6B", "#FF8C42", "#FFD93D", "#6BCB77", "#1DD1A1",
        "#4D96FF", "#5F6CAF", "#9B5DE5", "#F15BB5", "#8D99AE",
    ]

    init(selectedHex: Binding<String>) {
        self._selectedHex = selectedHex
        let initial = HexColor(rawValue: selectedHex.wrappedValue).map { Color(hexColor: $0) } ?? .blue
        self._customColor = State(initialValue: initial)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.gap), count: 6)

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
    }
    private func isSelected(_ hex: String) -> Bool {
        !selectedHex.isEmpty && normalize(hex) == normalize(selectedHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
            LazyVGrid(columns: columns, spacing: DS.Space.gap) {
                // 「なし」(色をクリア)
                Button { selectedHex = "" } label: {
                    swatch(hex: nil, selected: selectedHex.isEmpty)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("色なし")

                ForEach(Self.presets, id: \.self) { hex in
                    Button { selectedHex = hex } label: {
                        swatch(hex: hex, selected: isSelected(hex))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("カラー: \(ColorAccessibilityName.of(hex))")
                }
            }

            ColorPicker(selection: $customColor, supportsOpacity: false) {
                Text("カスタム色を選ぶ").imasText(.value)
            }
            .onChange(of: customColor) { _, newColor in
                selectedHex = newColor.tagHexString()
            }
        }
    }

    /// 色の丸。選んだ色には墨の輪、「なし」はスラッシュ。
    @ViewBuilder
    private func swatch(hex: String?, selected: Bool) -> some View {
        ZStack {
            if let hex {
                Circle().fill(Color(hexString: hex))
            } else {
                Circle().fill(DS.fill)
                Image(systemName: "slash.circle").font(.imasCaption).foregroundStyle(DS.ink2)
            }
        }
        .frame(width: ImasSwatch.Size.large.rawValue, height: ImasSwatch.Size.large.rawValue)
        .overlay(Circle().strokeBorder(selected ? DS.ink : DS.sep, lineWidth: selected ? 2.5 : 0.5))
    }
}
