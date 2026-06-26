import Foundation
import DeviceCheck
import CryptoKit

/// クローンアプリのただ乗り対策。App Attest で「正規アプリ」を証明し、
/// Worker から短命の app token を取得して X-App-Token ヘッダに載せる。
///
/// フロー:
///   1. GET /app/challenge → challenge
///   2. 初回: DCAppAttestService.generateKey → attestKey → POST /app/attest → appToken
///      2回目以降: generateAssertion → POST /app/assert → appToken
///   3. token は ~24h 有効。期限が近ければ assertion で再取得。
actor AppAttestService {
    static let shared = AppAttestService()

    private let service = DCAppAttestService.shared
    private let keyIdDefaultsKey = "appAttestKeyId"
    private var cachedToken: String?
    private var cachedExpiry: Date = .distantPast
    private var refreshing = false

    private var keyId: String? {
        get { UserDefaults.standard.string(forKey: keyIdDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: keyIdDefaultsKey) }
    }

    /// 現在有効な app token。無ければ取得を試みる (失敗時 nil)。
    func token() async -> String? {
        if let t = cachedToken, cachedExpiry > Date().addingTimeInterval(60 * 60) {
            return t
        }
        guard service.isSupported, !refreshing else { return cachedToken }
        refreshing = true
        defer { refreshing = false }
        do {
            try await refresh()
        } catch {
            #if DEBUG
            print("[AppAttest] refresh failed: \(error)")
            #endif
        }
        return cachedToken
    }

    /// 起動時などに先回りで token を温めておく。
    func warmUp() async { _ = await token() }

    private func refresh() async throws {
        let challenge = try await fetchChallenge()
        let challengeData = Data(base64urlEncoded: challenge) ?? Data()
        let clientDataHash = Data(SHA256.hash(data: challengeData))

        if let existingKeyId = keyId {
            do {
                let assertion = try await service.generateAssertion(existingKeyId, clientDataHash: clientDataHash)
                cachedToken = try await postAssert(keyId: existingKeyId, assertion: assertion, challenge: challenge)
                cachedExpiry = Date().addingTimeInterval(60 * 60 * 24)
                return
            } catch {
                // 鍵が無効化された等 → 作り直しにフォールバック
                keyId = nil
            }
        }
        let newKeyId = try await service.generateKey()
        let attestation = try await service.attestKey(newKeyId, clientDataHash: clientDataHash)
        cachedToken = try await postAttest(keyId: newKeyId, attestation: attestation, challenge: challenge)
        cachedExpiry = Date().addingTimeInterval(60 * 60 * 24)
        keyId = newKeyId
    }

    // MARK: - Worker calls

    private func fetchChallenge() async throws -> String {
        let url = APIEndpoints.baseURL.appendingPathComponent("app/challenge")
        let (data, _) = try await URLSession.shared.data(from: url)
        struct R: Decodable { let challenge: String }
        return try JSONDecoder().decode(R.self, from: data).challenge
    }

    private func postAttest(keyId: String, attestation: Data, challenge: String) async throws -> String {
        try await postApp("app/attest", [
            "keyId": keyId,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge,
        ])
    }

    private func postAssert(keyId: String, assertion: Data, challenge: String) async throws -> String {
        try await postApp("app/assert", [
            "keyId": keyId,
            "assertion": assertion.base64EncodedString(),
            "challenge": challenge,
        ])
    }

    private func postApp(_ path: String, _ body: [String: String]) async throws -> String {
        var req = URLRequest(url: APIEndpoints.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }
        struct R: Decodable { let appToken: String }
        return try JSONDecoder().decode(R.self, from: data).appToken
    }
}

private extension Data {
    /// base64url (padding 無し可) をデコード。
    init?(base64urlEncoded s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }
}
