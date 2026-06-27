import Foundation
import os

/// ログイン済み全ユーザーが マスタ (Event/Show/Idol/Song/SetlistItem/SetlistPerformer/SongArtist 等) を
/// オープン編集するための薄いラッパ。`POST /edits` を 1 リクエスト = 1 edit_batch で叩く。
///
/// 旧 `AdminWriteService` (admin 限定 `/admin/cloudkit/save`) の一般化版。
/// サーバ側で [getAuthUser→ban→rate(edit)→validateMasterEdit→cloudKitLookup(before取得)→
/// edit_batch→buildForceUpdate/buildSoftDelete→cloudKitModify→edit_history] を行う。
///
/// 重要な契約 (contract v2):
/// - `before` はクライアントから送らない。サーバが cloudKitLookup で権威取得する (改竄防止)。
/// - 削除は forceDelete ではなく soft delete (サーバが deletedAt+modifiedAt を注入)。op="delete" を送るだけ。
/// - 新規作成は recordName を省略するとサーバが `<prefix>_<uuid>` を採番し、レスポンスの確定 ID を返す。
/// - 型付けはサーバ (ck_schema.ts) が権威。iOS は fields を camelCase の素の値で送る。
///
/// 注: APIClient.shared は keyEncodingStrategy = .convertToSnakeCase なので
/// recordType / recordName / fields のようなキーや CloudKit フィールド名が snake_case に
/// 変換されてしまう。そのため EditService は専用 encoder (変換なし) で直接 URLSession を叩く。
@MainActor
final class EditService {
    static let shared = EditService()

    private let session = URLSession.shared
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let enc = JSONEncoder()
        // keyEncodingStrategy は触らない (camelCase のまま送る) = サーバ側で
        // op / recordType / recordName / fields がそのまま取れる。
        enc.dateEncodingStrategy = .secondsSince1970
        self.encoder = enc

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
    }

    // MARK: - Request / Response types

    enum EditOp: String, Encodable, Sendable {
        case create
        case update
        case delete
    }

    /// 1 マスタ操作。`before` は送らない (サーバが権威取得)。
    /// - create: recordName 省略可 (サーバ採番)。fields 必須。
    /// - update: recordName 必須。fields 必須。
    /// - delete: recordName 必須。fields 不要 (サーバが deletedAt 注入)。
    struct EditOperation: Encodable, Sendable {
        let op: EditOp
        let recordType: String
        let recordName: String?
        let fields: [String: AnyEncodable]?

        init(
            op: EditOp,
            recordType: String,
            recordName: String? = nil,
            fields: [String: AnyEncodable]? = nil
        ) {
            self.op = op
            self.recordType = recordType
            self.recordName = recordName
            self.fields = fields
        }
    }

    private struct EditRequest: Encodable, Sendable {
        let ops: [EditOperation]
        let summary: String?
    }

    /// サーバが返す 1 op の確定結果。
    ///
    /// 契約 §1: `{ recordType, recordName, op, ok, fields }` を素の camelCase で返す。
    /// `recordName` は **サーバ確定値**: create でサーバ採番した場合は採番後の ID が入る。
    /// クライアントは送信値ではなくこの確定 `recordName` でローカル upsert する (契約 #3)。
    /// `fields` は「反映後の確定レコード」(サーバ正規化済み。modifiedAt 注入 / 採番 recordName 込み)。
    /// delete は fields=null。存在する場合はローカル upsert の権威ソースとして利用できる。
    struct EditResult: Decodable, Sendable {
        /// CloudKit recordType (op 順ではなく type でも対応づけられるようサーバが併せて返す)。
        let recordType: String?
        let recordName: String
        let op: String
        let ok: Bool
        /// サーバ確定フィールド (camelCase キー)。delete / 未提供なら nil。
        let fields: [String: JSONValue]?

        private enum CodingKeys: String, CodingKey {
            case recordType, recordName, op, ok, fields
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            recordType = try c.decodeIfPresent(String.self, forKey: .recordType)
            recordName = try c.decode(String.self, forKey: .recordName)
            op = try c.decode(String.self, forKey: .op)
            ok = (try c.decodeIfPresent(Bool.self, forKey: .ok)) ?? true
            fields = try c.decodeIfPresent([String: JSONValue].self, forKey: .fields)
        }
    }

    /// 修正リクエスト (issue化) のレスポンス。CloudKit 未反映なのでローカル更新はしない。
    struct EditRequestResponse: Decodable, Sendable {
        let ok: Bool
        let issueNumber: Int?
        let issueUrl: String?
    }

    /// マスタ編集の結末。admin は直接反映、一般ユーザーは修正リクエスト(issue)。
    enum MasterEditOutcome: Sendable {
        case applied(EditResponse)
        case requested(EditRequestResponse)
    }

    struct EditResponse: Decodable, Sendable {
        let ok: Bool
        let batchId: Int?
        let results: [EditResult]

        /// 先頭 op の確定 recordName (= サーバ確定値)。各 EditView は「主レコード」を ops[0] で
        /// 送るため results[0] がその確定値に対応する (サーバ results[] は recordType を含まない
        /// ので type ではなく順序で対応づける)。create のサーバ採番 ID もここから引く。
        /// `fallback` は単一レコード編集で結果が空だった場合の保険 (既存 ID 等)。
        func primaryRecordName(fallback: String? = nil) -> String? {
            results.first?.recordName ?? fallback
        }
    }

    // MARK: - API

    /// マスタ編集 batch を送信する。成功時のみ呼び出し側がローカル upsert を行う (楽観更新)。
    /// 失敗時は throw するのでローカルは未変更のまま (ロールバック不要)。
    @discardableResult
    func submit(ops: [EditOperation], summary: String? = nil) async throws -> EditResponse {
        guard !ops.isEmpty else {
            return EditResponse(ok: true, batchId: nil, results: [])
        }

        let url = APIEndpoints.baseURL.appendingPathComponent("/edits")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceIdentity.shared, forHTTPHeaderField: "X-Device-Id")
        if let token = AuthService.shared.bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try encoder.encode(EditRequest(ops: ops, summary: summary))

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.transport(URLError(.badServerResponse))
        }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            // body にはサーバ側 recordName / field 値が含まれうるため privacy: .private で
            // 第三者ログ視聴 (Console.app / sysdiagnose / TestFlight) からマスクする。
            Logger.community.error("edits HTTP \(http.statusCode, privacy: .public) body=\(body, privacy: .private)")
            switch http.statusCode {
            case 401:
                // 未ログイン / トークン失効。
                AuthService.shared.invalidateToken()
                throw APIClientError.notAuthorized
            case 403:
                // BAN されている可能性が高い。ローカルに反映して編集導線を畳む。
                AuthService.shared.markBannedFromServer()
                throw APIClientError.notAuthorized
            case 429:
                throw APIClientError.rateLimited(retryAfter: nil)
            default:
                throw APIClientError.server(status: http.statusCode, body: body)
            }
        }
        return try decoder.decode(EditResponse.self, from: data)
    }

    /// マスタ修正リクエストを送る (CloudKit には書かず GitHub issue 化)。一般ユーザー用。
    @discardableResult
    func submitRequest(ops: [EditOperation], summary: String? = nil) async throws -> EditRequestResponse {
        guard !ops.isEmpty else {
            return EditRequestResponse(ok: true, issueNumber: nil, issueUrl: nil)
        }
        let url = APIEndpoints.baseURL.appendingPathComponent("/edit-requests")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceIdentity.shared, forHTTPHeaderField: "X-Device-Id")
        if let token = AuthService.shared.bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try encoder.encode(EditRequest(ops: ops, summary: summary))

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.transport(URLError(.badServerResponse))
        }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            Logger.community.error("edit-requests HTTP \(http.statusCode, privacy: .public) body=\(body, privacy: .private)")
            switch http.statusCode {
            case 401:
                AuthService.shared.invalidateToken()
                throw APIClientError.notAuthorized
            case 403:
                AuthService.shared.markBannedFromServer()
                throw APIClientError.notAuthorized
            case 429:
                throw APIClientError.rateLimited(retryAfter: nil)
            default:
                throw APIClientError.server(status: http.statusCode, body: body)
            }
        }
        return try decoder.decode(EditRequestResponse.self, from: data)
    }

    /// マスタ編集の送信。admin は直接反映、一般ユーザーは修正リクエスト(issue)に回す。
    /// 呼び出し側は outcome で「ローカル楽観更新するか」「リクエスト受付表示にするか」を分岐する。
    func submitMaster(ops: [EditOperation], summary: String? = nil) async throws -> MasterEditOutcome {
        if AuthService.shared.isAdmin {
            return .applied(try await submit(ops: ops, summary: summary))
        } else {
            return .requested(try await submitRequest(ops: ops, summary: summary))
        }
    }
}
