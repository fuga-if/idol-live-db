package com.fugaif.imaslivedb.data.auth

import uniffi.imas_core.EditPermissionRules
import uniffi.imas_core.EditTapOutcome
import uniffi.imas_core.editPermissionCanEdit
import uniffi.imas_core.editPermissionOutcomeOnEditTap
import uniffi.imas_core.editPermissionShouldPromptLogin
import uniffi.imas_core.editPermissionShowEditAffordance

// =============================================================================
// マスタのオープン編集 (作成/修正/削除・コミュニティ投稿) の権限判定を 1 箇所に集約する。
// iOS Services/EditPermission.swift の Android 版。
//
// 判定規則そのものは imas-core (Rust) の domain/edit_permission_rules.rs にあり、
// ここは現在の認証状態 (AuthState) を規則に食わせるだけの薄い入口
// (画面側で isSignedIn を直接見て分岐を書き直したら負け。iOS と黙ってズレる)。
//
// 構造マスタ (Brand/IdolCast 等) は admin 限定なので、それらの編集導線は引き続き
// AuthState.isAdmin で個別ゲートする (本ヘルパは扱わない)。
//
// 【Compose から使う時の注意】
// 下の extension property は 1 回ごとに EditPermissionRules を RustBuffer へ詰め直して
// JNA 越しにコアを呼ぶ。Swift の直結 FFI と違って無料ではないので、composable の中では
// `remember(authState) { authState.showEditAffordance }` のように認証状態が変わった時だけ
// 評価する形に畳むこと。リスト要素ごと・再コンポーズごとに呼ぶのは禁止
// (スクロール中ずっと JNA を跨ぎ続ける)。
// =============================================================================

/**
 * 認証状態 → 判定規則の射影 (コアが要る 2 フィールドだけ)。
 *
 * `isBanned` の供給元は iOS と同じ 2 経路: 起動時の `AuthService.refreshMe` (`GET /auth/me`) と、
 * 編集 API が 403 を返した時の `AuthService.markBannedFromServer`。
 * `/auth/login` のレスポンスに isBanned は含まれない契約なので、ログインだけでは埋まらない。
 */
fun AuthState.editPermissionRules(): EditPermissionRules =
    EditPermissionRules(isSignedIn = isSignedIn, isBanned = isBanned)

/** 編集 UI を実際に出してよいか (ログイン済み かつ 未 BAN)。 */
val AuthState.canEdit: Boolean get() = editPermissionCanEdit(editPermissionRules())

/** 編集導線を押下した時にログイン誘導を出すべきか (= 未ログイン)。 */
val AuthState.shouldPromptLogin: Boolean get() = editPermissionShouldPromptLogin(editPermissionRules())

/** 編集 / 新規作成ボタン自体を表示してよいか (BAN 済みのみ隠す)。 */
val AuthState.showEditAffordance: Boolean get() = editPermissionShowEditAffordance(editPermissionRules())

/** 編集導線を押した時の分岐 (present / promptLogin / ignore)。 */
val AuthState.outcomeOnEditTap: EditTapOutcome get() = editPermissionOutcomeOnEditTap(editPermissionRules())

/**
 * 投稿/編集導線の共通ゲート。iOS `DetailSheet.startCommunityEdit` と同じ方針で、
 * 未ログインは [promptLogin]、BAN 済みは [onBanned]、ログイン済み・未 BAN のみ [present]。
 *
 * 分岐の優先順はコア (`outcome_on_edit_tap`) が決める。呼び出し側が
 * if で並べ直すと優先順が崩れるので、必ずこの入口を通すこと。
 *
 * [onBanned] の既定が「何もしない」なのは、BAN 済みには導線自体を出していない
 * (`showEditAffordance` が false) 画面が大半で、そこでは押しようがないから。
 * 導線を隠しきれない場所 (既に開いているシートの保存ボタン等) では、
 * 押しても無反応になるのを避けるため理由を出すこと。
 */
fun AuthState.startCommunityEdit(
    promptLogin: () -> Unit,
    onBanned: () -> Unit = {},
    present: () -> Unit
) {
    when (outcomeOnEditTap) {
        EditTapOutcome.PRESENT -> present()
        EditTapOutcome.PROMPT_LOGIN -> promptLogin()
        EditTapOutcome.IGNORE -> onBanned()
    }
}
