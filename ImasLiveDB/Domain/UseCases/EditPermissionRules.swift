import Foundation

/// オープン編集 (作成/修正/削除・コミュニティ投稿) の権限判定。
///
/// 判定本体は imas-core (Rust) の `domain/edit_permission_rules.rs` にあり、
/// `EditPermissionRules` (Record: isSignedIn / isBanned の 2 射影) と
/// `EditTapOutcome` (present / promptLogin / ignore) の型自体も uniffi 生成
/// バインディングが提供する。ここは Swift らしい computed property の呼び口を
/// 生成関数へ委譲するだけの薄い拡張 (判定を書いたら負け)。
/// なぜ BAN を見るか・導線の出し分けの意図は edit_permission_rules.rs に記載。
///
/// 実際の認証状態 (`AuthService.shared`) から組み立てるのは `EditPermission` の役目。
extension EditPermissionRules {
    /// 編集 UI を実際に出してよいか (ログイン済み かつ 未 BAN)。
    var canEdit: Bool { editPermissionCanEdit(rules: self) }

    /// 未ログインで編集導線を押した時にログイン誘導を出すべきか。
    var shouldPromptLogin: Bool { editPermissionShouldPromptLogin(rules: self) }

    /// 編集 / 新規作成ボタン自体を表示してよいか (BAN 済みのみ隠す)。
    var showEditAffordance: Bool { editPermissionShowEditAffordance(rules: self) }

    /// 編集導線を押した時に何をするか。優先順は「編集可 > ログイン誘導 > 無視」。
    var outcomeOnEditTap: EditTapOutcome { editPermissionOutcomeOnEditTap(rules: self) }
}
