import Foundation

enum BackupTransferError: LocalizedError {
    case notFoundOrExpired
    case notAuthorized
    case network(Error)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notFoundOrExpired:
            return "コードが無効か期限切れです"
        case .notAuthorized:
            return "ログインが必要です"
        case .network:
            return "通信エラーが発生しました"
        case .server(let message):
            return message
        }
    }
}

/// バックアップ引き継ぎコード API (`/transfer`) のクライアント。
enum BackupTransferClient {
    private struct CreateBody: Encodable { let payload: String }
    // expiresAt/createdAt はサーバーが `Date.toISOString()` で返す文字列 (ミリ秒含む)。
    // APIClient の共有デコーダーは dateDecodingStrategy=.secondsSince1970 固定のため、
    // Date として直接デコードさせず String で受けてから ISO8601 でパースする。
    private struct CreateResponse: Decodable { let code: String; let expiresAt: String }
    private struct FetchResponse: Decodable { let payload: String; let createdAt: String }

    private static func parseISO8601(_ s: String) -> Date {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFractional.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? Date()
    }

    /// `POST /transfer` を呼び、発行されたコードと有効期限を返す。
    static func createTransferCode(payloadJSON: String) async throws -> (code: String, expiresAt: Date) {
        do {
            let response: CreateResponse = try await APIClient.shared.request(
                "POST", path: "/transfer",
                body: CreateBody(payload: payloadJSON),
                authorized: true
            )
            return (response.code, parseISO8601(response.expiresAt))
        } catch let error as APIClientError {
            throw mapError(error)
        } catch {
            throw BackupTransferError.network(error)
        }
    }

    /// `GET /transfer/:code` を呼び、payload JSON 文字列を返す。
    static func fetchTransferCode(_ code: String) async throws -> String {
        // コードは元々 A-Z2-9 のみの値域 (generateCode 参照)。APIClient のパス構築は "/" を
        // 区切り文字として素通りさせる (percent-encode しない) ため、ユーザーが誤って "/" 等を
        // 含む文字列を貼り付けるとパスが壊れうる。英数字以外を除去して安全な値域に正規化する。
        let sanitized = code.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        do {
            let response: FetchResponse = try await APIClient.shared.request(
                "GET", path: "/transfer/\(sanitized)",
                authorized: true
            )
            return response.payload
        } catch let error as APIClientError {
            throw mapError(error)
        } catch {
            throw BackupTransferError.network(error)
        }
    }

    private static func mapError(_ error: APIClientError) -> BackupTransferError {
        switch error {
        case .notFound:
            return .notFoundOrExpired
        case .notAuthorized:
            return .notAuthorized
        default:
            return .server(error.errorDescription ?? "サーバーエラー")
        }
    }
}
