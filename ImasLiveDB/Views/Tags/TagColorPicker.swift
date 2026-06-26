import SwiftUI

/// タグ色の選択 UI。プリセット色のスウォッチ + システムの ColorPicker + 「なし」。
///
/// 選択値は `"#RRGGBB"` 形式の HEX 文字列として `selectedHex` に書き込む (空文字 = 色なし)。
/// HEX を手入力させるのは難しいため、TagCreateSheet / TagEditSheet 双方でこれを使う。
struct TagColorPicker: View {
    @Binding var selectedHex: String

    /// システム ColorPicker 用。初期値だけ selectedHex から取り、以後は独立 (プリセット選択では同期しない)。
    @State private var customColor: Color

    init(selectedHex: Binding<String>) {
        self._selectedHex = selectedHex
        let initial = HexColor(rawValue: selectedHex.wrappedValue).map { Color(hexColor: $0) } ?? .blue
        self._customColor = State(initialValue: initial)
    }

    /// 並べるプリセット (彩度・色相をばらして視認しやすい 10 色)。
    private static let presets: [String] = [
        "#FF6B6B", "#FF8C42", "#FFD93D", "#6BCB77", "#1DD1A1",
        "#4D96FF", "#5F6CAF", "#9B5DE5", "#F15BB5", "#8D99AE",
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
    }
    private func isSelected(_ hex: String) -> Bool {
        !selectedHex.isEmpty && normalize(hex) == normalize(selectedHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, spacing: 12) {
                // 「なし」(色をクリア)
                Button { selectedHex = "" } label: {
                    swatch(fill: nil, selected: selectedHex.isEmpty)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("色なし")

                ForEach(Self.presets, id: \.self) { hex in
                    Button { selectedHex = hex } label: {
                        swatch(fill: Color(hexString: hex), selected: isSelected(hex))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("色 \(hex)")
                }
            }

            ColorPicker(selection: $customColor, supportsOpacity: false) {
                Text("カスタム色を選ぶ")
                    .font(.imasSubhead)
            }
            .onChange(of: customColor) { _, newColor in
                selectedHex = newColor.tagHexString()
            }
        }
        .padding(.vertical, 4)
    }

    /// 円形スウォッチ。fill=nil は「なし」(スラッシュ)。selected で選択リングを出す。
    @ViewBuilder
    private func swatch(fill: Color?, selected: Bool) -> some View {
        ZStack {
            if let fill {
                Circle().fill(fill)
            } else {
                Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                Image(systemName: "slash.circle").font(.imasCaption).foregroundStyle(.secondary)
            }
            if selected {
                Circle().strokeBorder(Color.primary, lineWidth: 2.5)
            }
        }
        .frame(width: 34, height: 34)
    }
}
