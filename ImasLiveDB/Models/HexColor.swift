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

extension KeyedDecodingContainer {
    /// 任意項目の色は、壊れた値 (空文字・`red` など) を「色なし」として読む。
    ///
    /// `HexColor` の `init(from:)` は不正値で throw するので、そのままだと色が 1 件おかしいだけで
    /// 応答全体 (タグ一覧・タグ詳細・曲のタグ) のデコードが落ちる。実際に空文字の色のタグ
    /// (「カラオケ未実装」) が 1 件入っただけで、タグのピッカーが空になり絞り込みが効かなくなっていた。
    /// 色は飾りなので、読めなければ無色で出すのが正しい。合成された `Codable` もこの多重定義を使う。
    func decodeIfPresent(_ type: HexColor.Type, forKey key: Key) throws -> HexColor? {
        guard let raw = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return HexColor(rawValue: raw)
    }
}
