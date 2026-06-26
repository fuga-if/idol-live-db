import Foundation

/// バリデーション済み HEX カラー文字列の newtype。
/// "#" プレフィックスは省略可。6桁または8桁（アルファ付き）を受け付ける。
struct HexColor: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        let stripped = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !stripped.isEmpty,
              stripped.count == 6 || stripped.count == 8,
              stripped.allSatisfy({ $0.isHexDigit }) else { return nil }
        self.rawValue = stripped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = HexColor(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid hex color string: \(raw)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// "#" 付きの文字列（Color(hexString:) 等に渡す用）
    var hashPrefixed: String { "#\(rawValue)" }
}
