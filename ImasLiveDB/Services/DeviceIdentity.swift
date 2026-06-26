import Foundation
import Security
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "device_identity")

/// 端末固有ID管理。Keychainに永続保存し、アンインストール後も同じ値を返す。
/// Keychain 書き込み失敗時は UserDefaults にフォールバックする。
enum DeviceIdentity {
    private static let service = "com.fugaif.ImasLiveDB.deviceId"
    private static let account = "deviceId"
    private static let fallbackKey = "device_id_fallback"

    private static let queue = DispatchQueue(label: "com.fugaif.ImasLiveDB.device_identity", attributes: [])

    static var shared: String {
        queue.sync {
            if let existing = loadFromKeychain() ?? loadFromFallback() {
                return existing
            }
            let newId = UUID().uuidString
            saveToKeychain(newId)
            return newId
        }
    }

    // MARK: - Keychain

    private static func loadFromKeychain() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        if status != errSecItemNotFound {
            logger.error("keychain_failed status=\(status) op=load")
        }
        return nil
    }

    private static func saveToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // 既存があれば削除して再保存
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logger.error("keychain_failed status=\(deleteStatus) op=delete")
        }

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.error("keychain_failed status=\(addStatus) op=add — falling back to UserDefaults")
            saveToFallback(value)
        } else {
            // Keychain 成功時は fallback も更新しておく（読み込み優先度確認のため）
            saveToFallback(value)
        }
    }

    // MARK: - UserDefaults Fallback

    private static func loadFromFallback() -> String? {
        UserDefaults.standard.string(forKey: fallbackKey)
    }

    private static func saveToFallback(_ value: String) {
        UserDefaults.standard.set(value, forKey: fallbackKey)
    }
}
