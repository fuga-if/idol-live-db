import SwiftUI

/// マスタのオープン編集 (作成/修正/削除) の権限判定を 1 箇所に集約する。
///
/// 確定モデル: 即時オープン編集。ログイン済み全ユーザーが直接編集できる。
/// 承認待ちはゼロ。荒らしは事後モデレーション (BAN + revert) で対処する。
///
/// - `canEdit`: 編集 UI を実際に出してよいか。ログイン済み かつ BAN されていない。
///   (RedTeam: BAN を見ないと荒らしが BAN 後も編集 sheet を開けて 403 を量産でき UX も最悪)
/// - `shouldPromptLogin`: 未ログインで編集導線を押した時にログイン誘導を出すべきか。
///
/// 構造マスタ (Brand/IdolCast 等) は admin 限定なので、それらの編集導線は引き続き
/// `AuthService.shared.isAdmin` で個別ゲートする (本ヘルパは扱わない)。
enum EditPermission {
    /// オープン編集 UI を出してよいか (ログイン済み かつ 未 BAN)。
    @MainActor
    static var canEdit: Bool {
        let auth = AuthService.shared
        return auth.isSignedIn && !auth.isBanned
    }

    /// 編集導線を押下した時にログイン誘導 sheet を出すべきか (= 未ログイン)。
    @MainActor
    static var shouldPromptLogin: Bool {
        !AuthService.shared.isSignedIn
    }

    /// 編集 / 新規作成ボタン自体を表示してよいか。
    /// - 未ログイン: 表示する (押下でログイン誘導。発見性のため)。
    /// - ログイン済み・未 BAN: 表示する (押下で編集 UI)。
    /// - ログイン済み・BAN 済み: 隠す (押下しても 403 になるだけで UX が悪い)。
    @MainActor
    static var showEditAffordance: Bool {
        !AuthService.shared.isBanned
    }
}
