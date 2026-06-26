import Foundation

/// 任意の Encodable 値を辞書フィールドに突っ込むための消去型ラッパ。
///
/// マスタ編集 (EditService → `POST /edits`) で CloudKit フィールド値 (String / Int / Double 等の
/// 混在辞書) を 1 つの `[String: AnyEncodable]` として camelCase のまま送るために使う。
///
/// 旧 `AdminWriteService` (admin 限定 `/admin/cloudkit/save`) はオープン編集モデルへの移行で
/// `EditService` (`POST /edits`) に一般化・置換された。本ファイルは共有の `AnyEncodable` のみ残す。
struct AnyEncodable: Encodable, @unchecked Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void
    init<T: Encodable & Sendable>(_ value: T) {
        self._encode = { try value.encode(to: $0) }
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }

    /// JSON `null` の明示送信。`POST /edits` の update はサーバ側マージセマンティクス
    /// (未送信フィールド = 現状維持) のため、フィールドを意図的に空にするには
    /// null を明示送信してクリアと解釈させる必要がある。
    static let null = AnyEncodable(Optional<String>.none)

    /// マスタ編集フォームのテキスト値から update の送信値を決める:
    /// - 非空 → trim した値を送信 (上書き)
    /// - 空 & 元値あり → `.null` (明示クリア)
    /// - 空 & 元から空 → `nil` (送らない = 現状維持)
    static func clearable(_ raw: String, original: String?) -> AnyEncodable? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return AnyEncodable(trimmed) }
        if let original, !original.isEmpty { return .null }
        return nil
    }
}
