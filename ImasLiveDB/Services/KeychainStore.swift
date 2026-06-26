import Foundation
import Security

/// 認証トークン等の小さな機密値を Keychain に保管するためのシンプルなラッパ。
/// アクセス: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
///   - 端末ロック解除後のみ読み書き可能
///   - kSecAttrSynchronizable は不指定 = iCloud Keychain 同期しない (家族デバイス漏洩防止)
///   - This Device Only = 端末バックアップ復元時も別端末には移らない
enum KeychainStore {
    private static let service = "com.fugaif.ImasLiveDB.auth"

    static func set(_ value: String?, forKey key: String) {
        // 既存削除 → 必要なら追加
        delete(key: key)
        guard let value, let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
