//! オープン編集 (作成/修正/削除・コミュニティ投稿) の権限判定。純粋ロジック。
//!
//! 判定材料は「ログインしているか」「BAN されているか」の 2 つだけ。
//! 認証サービス (iOS `AuthService.shared` 等) から切り離してあるので、
//! 4 通りの組み合わせをそのまま単体テストできる。実際の認証状態から
//! `EditPermissionRules` を組み立てるのは各プラットフォームの入口
//! (iOS `EditPermission`) の役目。
//!
//! 確定モデル: 即時オープン編集。ログイン済み全ユーザーが直接編集でき、承認待ちはゼロ。
//! 荒らしは事後モデレーション (BAN + revert) で対処する。

/// 権限判定の入力射影。認証状態のうち判定に要る 2 フィールドだけを FFI で渡す
/// (ユーザーエンティティ全体は渡さない)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct EditPermissionRules {
    pub is_signed_in: bool,
    pub is_banned: bool,
}

/// 編集導線を押した時に何をするか。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum EditTapOutcome {
    /// 編集 UI を出す。
    Present,
    /// ログイン誘導を出す。
    PromptLogin,
    /// 何もしない (BAN 済み。そもそも導線を出していない)。
    Ignore,
}

impl EditPermissionRules {
    /// 編集 UI を実際に出してよいか。
    ///
    /// BAN を見ないと、荒らしが BAN 後も編集シートを開けて 403 を量産できてしまう。
    pub fn can_edit(&self) -> bool {
        self.is_signed_in && !self.is_banned
    }

    /// 未ログインで編集導線を押した時にログイン誘導を出すべきか。
    pub fn should_prompt_login(&self) -> bool {
        !self.is_signed_in
    }

    /// 編集 / 新規作成ボタン自体を表示してよいか。
    /// - 未ログイン: 表示する (押下でログイン誘導。発見性のため)
    /// - ログイン済み・未 BAN: 表示する (押下で編集 UI)
    /// - ログイン済み・BAN 済み: 隠す (押下しても 403 になるだけで UX が悪い)
    pub fn show_edit_affordance(&self) -> bool {
        !self.is_banned
    }

    /// 編集導線を押した時の分岐。優先順は「編集可 > ログイン誘導 > 無視」。
    pub fn outcome_on_edit_tap(&self) -> EditTapOutcome {
        if self.can_edit() {
            return EditTapOutcome::Present;
        }
        if self.should_prompt_login() {
            return EditTapOutcome::PromptLogin;
        }
        EditTapOutcome::Ignore
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SIGNED_OUT: EditPermissionRules = EditPermissionRules {
        is_signed_in: false,
        is_banned: false,
    };
    const SIGNED_IN: EditPermissionRules = EditPermissionRules {
        is_signed_in: true,
        is_banned: false,
    };
    const BANNED: EditPermissionRules = EditPermissionRules {
        is_signed_in: true,
        is_banned: true,
    };

    // ── can_edit ──────────────────────────────────────────────

    #[test]
    fn only_signed_in_and_not_banned_can_edit() {
        assert!(!SIGNED_OUT.can_edit());
        assert!(SIGNED_IN.can_edit());
        // BAN 済みが編集シートを開けると 403 を量産できてしまう
        assert!(!BANNED.can_edit());
    }

    // ── show_edit_affordance ─────────────────────────────────

    /// 未ログインにもボタンは見せる (押してログインしてもらう導線)。
    #[test]
    fn affordance_is_shown_to_signed_out_users() {
        assert!(SIGNED_OUT.show_edit_affordance());
    }

    /// BAN 済みには出さない (押しても 403 になるだけ)。
    #[test]
    fn affordance_is_hidden_from_banned_users() {
        assert!(!BANNED.show_edit_affordance());
    }

    // ── outcome_on_edit_tap ──────────────────────────────────

    #[test]
    fn signed_in_user_gets_the_editor() {
        assert_eq!(SIGNED_IN.outcome_on_edit_tap(), EditTapOutcome::Present);
    }

    #[test]
    fn signed_out_user_gets_login_prompt() {
        assert_eq!(SIGNED_OUT.outcome_on_edit_tap(), EditTapOutcome::PromptLogin);
    }

    /// BAN 済みは何も起きない。ログイン誘導を出してしまうと、
    /// 既にログインしているのにログイン画面が出る意味不明な挙動になる。
    #[test]
    fn banned_user_gets_nothing() {
        assert_eq!(BANNED.outcome_on_edit_tap(), EditTapOutcome::Ignore);
    }

    /// 導線が出ている状態なら、押した結果が `Ignore` になることはない
    /// (押せるのに何も起きないボタンを作らない)。
    #[test]
    fn visible_affordance_always_does_something() {
        for rules in [SIGNED_OUT, SIGNED_IN, BANNED] {
            if rules.show_edit_affordance() {
                assert_ne!(rules.outcome_on_edit_tap(), EditTapOutcome::Ignore, "{rules:?}");
            }
        }
    }

    /// 4 通り目 (未ログイン & BAN)。BAN はアカウントに紐づくので通常到達しないが、
    /// 万一この状態になっても「導線は隠れ、押せてもログイン誘導に倒れる」ことを固定する
    /// (iOS 版はこの組み合わせをテストしていなかったので Rust 側で追加)。
    #[test]
    fn signed_out_banned_combination_is_pinned() {
        let rules = EditPermissionRules {
            is_signed_in: false,
            is_banned: true,
        };
        assert!(!rules.can_edit());
        assert!(!rules.show_edit_affordance());
        assert_eq!(rules.outcome_on_edit_tap(), EditTapOutcome::PromptLogin);
    }
}
