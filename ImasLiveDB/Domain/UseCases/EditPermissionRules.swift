import Foundation

/// オープン編集 (作成/修正/削除・コミュニティ投稿) の権限判定。純粋ロジック。
///
/// 判定材料は「ログインしているか」「BAN されているか」の 2 つだけ。
/// `AuthService.shared` から切り離してあるので、4 通りの組み合わせを単体テストできる。
/// 実際の認証状態から組み立てるのは `EditPermission` の役目。
///
/// 確定モデル: 即時オープン編集。ログイン済み全ユーザーが直接編集でき、承認待ちはゼロ。
/// 荒らしは事後モデレーション (BAN + revert) で対処する。
struct EditPermissionRules: Equatable {
    var isSignedIn: Bool
    var isBanned: Bool

    /// 編集 UI を実際に出してよいか。
    ///
    /// BAN を見ないと、荒らしが BAN 後も編集シートを開けて 403 を量産できてしまう。
    var canEdit: Bool { isSignedIn && !isBanned }

    /// 未ログインで編集導線を押した時にログイン誘導を出すべきか。
    var shouldPromptLogin: Bool { !isSignedIn }

    /// 編集 / 新規作成ボタン自体を表示してよいか。
    /// - 未ログイン: 表示する (押下でログイン誘導。発見性のため)
    /// - ログイン済み・未 BAN: 表示する (押下で編集 UI)
    /// - ログイン済み・BAN 済み: 隠す (押下しても 403 になるだけで UX が悪い)
    var showEditAffordance: Bool { !isBanned }

    /// 編集導線を押した時に何をするか。
    enum EditTapOutcome: Equatable {
        /// 編集 UI を出す。
        case present
        /// ログイン誘導を出す。
        case promptLogin
        /// 何もしない (BAN 済み。そもそも導線を出していない)。
        case ignore
    }

    var outcomeOnEditTap: EditTapOutcome {
        if canEdit { return .present }
        if shouldPromptLogin { return .promptLogin }
        return .ignore
    }
}
