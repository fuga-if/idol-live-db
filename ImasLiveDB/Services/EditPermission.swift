import Foundation

/// マスタのオープン編集 (作成/修正/削除) の権限判定を 1 箇所に集約する。
///
/// 判定規則そのものは `EditPermissionRules` (Domain) にあり、ここは
/// 現在の認証状態 (`AuthService.shared`) を規則に食わせるだけの薄い入口。
///
/// 構造マスタ (Brand/IdolCast 等) は admin 限定なので、それらの編集導線は引き続き
/// `AuthService.shared.isAdmin` で個別ゲートする (本ヘルパは扱わない)。
enum EditPermission {
    /// 現在の認証状態から組み立てた判定規則。
    @MainActor
    static var rules: EditPermissionRules {
        let auth = AuthService.shared
        return EditPermissionRules(isSignedIn: auth.isSignedIn, isBanned: auth.isBanned)
    }

    /// オープン編集 UI を出してよいか (ログイン済み かつ 未 BAN)。
    @MainActor
    static var canEdit: Bool { rules.canEdit }

    /// 編集導線を押下した時にログイン誘導 sheet を出すべきか (= 未ログイン)。
    @MainActor
    static var shouldPromptLogin: Bool { rules.shouldPromptLogin }

    /// 編集 / 新規作成ボタン自体を表示してよいか。
    @MainActor
    static var showEditAffordance: Bool { rules.showEditAffordance }
}
