package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.player.AppleMusicState
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind

/**
 * Apple Music に繋がっていないときの案内。歌詞プレイヤー・タイミング編集の頭に出す。
 *
 * 鳴らそうとした時点でサインインの画面 (アプリ内ブラウザ) は自動で開くので、ここは
 * 「いま何が起きているか」と、閉じてしまったときに開き直す口を出すだけ。繋がっていれば何も出さない。
 */
@Composable
fun AppleMusicSignInNotice(state: AppleMusicState, onSignIn: () -> Unit, modifier: Modifier = Modifier) {
    when (state) {
        AppleMusicState.READY -> Unit
        AppleMusicState.UNAVAILABLE -> ImasNotice(
            kind = ImasNoticeKind.INFO,
            message = "この端末では Apple Music で再生できません。歌詞はそのまま読めます。",
            modifier = modifier,
            icon = Icons.Filled.MusicNote,
        )
        AppleMusicState.SIGNED_OUT -> ImasNotice(
            kind = ImasNoticeKind.INFO,
            title = "Apple Music にサインイン",
            message = "サインインすると、曲をフル尺で鳴らして歌詞を追いかけられます。",
            modifier = modifier,
            icon = Icons.Filled.MusicNote,
            actionTitle = "サインイン",
            actionIcon = Icons.AutoMirrored.Filled.OpenInNew,
            onAction = onSignIn,
        )
        AppleMusicState.SIGNING_IN -> ImasNotice(
            kind = ImasNoticeKind.INFO,
            title = "ブラウザでサインインしています",
            message = "サインインを終えてアプリに戻ると、再生が始まります。",
            modifier = modifier,
            icon = Icons.Filled.MusicNote,
            actionTitle = "もう一度開く",
            actionIcon = Icons.AutoMirrored.Filled.OpenInNew,
            onAction = onSignIn,
        )
    }
}
