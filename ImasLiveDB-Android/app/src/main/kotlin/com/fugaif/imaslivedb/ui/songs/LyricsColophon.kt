package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.lyrics.LyricsCredit
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRowKind
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceDialog
import com.fugaif.imaslivedb.ui.designsystem.ImasCompletionAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasValueRow
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import uniffi.imas_core.ShowCreditInput
import uniffi.imas_core.ShowCreditLine
import uniffi.imas_core.lyricsCreditLine

/** 報告の理由 (サーバの LYRICS_REPORT_REASONS と同じ鍵)。 */
private val REPORT_REASONS = listOf(
    "copied" to "歌詞サイト・他サービスからの転載",
    "wrong" to "歌詞の誤り",
    "rights" to "権利者としての削除の求め",
    "other" to "その他",
)

/**
 * 歌詞の末尾の奥付と、報告・モデレーターの操作 (iOS LyricsColophon の移植)。
 * - 歌詞入力: 投稿で公開した人 (名前は本人が載せると選んだ人だけ。並びと「ほか N 人」はコア)。
 * - この歌詞を報告: 転載・誤り・削除の求めを運営に送る (本文は送らない)。
 * - モデレーター: 非公開 ⇄ 公開、投稿で上書きされる前の版に戻す。どれも本文は消さない。
 */
@Composable
fun LyricsColophon(
    songId: String,
    credit: LyricsCredit?,
    isDraft: Boolean,
    isSignedIn: Boolean,
    canModerate: Boolean,
    onChanged: () -> Unit,
    modifier: Modifier = Modifier
) {
    val api = AppModule.from(LocalContext.current).lyricsApi
    val scope = rememberCoroutineScope()
    var showReasons by remember { mutableStateOf(false) }
    var reportSent by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var isWorking by remember { mutableStateOf(false) }

    fun run(action: suspend () -> Unit, after: () -> Unit = onChanged) {
        isWorking = true
        scope.launch {
            try {
                action()
                after()
            } catch (e: Exception) {
                error = e.message ?: "送れませんでした"
            } finally {
                isWorking = false
            }
        }
    }

    val line = credit?.let { lyricsCreditLine(ShowCreditInput(it.names, it.total.coerceAtLeast(0).toUInt())) }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        if (line != null) {
            ImasCardList { ImasValueRow(key = "歌詞入力", value = creditNames(line)) }
        }
        ImasCardList {
            ImasActionRow(
                title = "この歌詞を報告",
                icon = Icons.Filled.Flag,
                isLoading = isWorking,
                onClick = { if (isSignedIn && !isWorking) showReasons = true }
            )
            if (canModerate) {
                ImasRowDivider()
                ImasActionRow(
                    title = if (isDraft) "公開する" else "非公開にする",
                    icon = if (isDraft) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
                    kind = if (isDraft) ImasActionRowKind.STANDARD else ImasActionRowKind.DESTRUCTIVE,
                    onClick = { if (!isWorking) run({ api.setPublished(songId, isDraft) }) }
                )
                ImasRowDivider()
                ImasActionRow(
                    title = "1 つ前の版に戻す",
                    icon = Icons.AutoMirrored.Filled.Undo,
                    onClick = { if (!isWorking) run({ api.restorePrevious(songId) }) }
                )
            }
        }
        ImasNote("歌詞サイトや他のサービスから写した歌詞は、公開後でも削除します。")
    }

    ImasChoiceDialog(
        title = "この歌詞を報告",
        isPresented = showReasons,
        options = REPORT_REASONS,
        message = "運営が確認し、必要なら非公開にします。",
        onPick = { key -> run({ api.report(songId, key) }, after = { reportSent = true }) },
        onDismiss = { showReasons = false }
    )
    ImasCompletionAlert(
        title = "報告を送りました",
        message = if (reportSent) "ありがとうございます。運営が確認します。" else null,
        onDismiss = { reportSent = false }
    )
    ImasErrorAlert(error, onDismiss = { error = null }, title = "送れませんでした")
}

/** 「A・B ほか 2 人」。名前を載せる人がいなければ「3 人」。 */
private fun creditNames(line: ShowCreditLine): String {
    val names = line.names.joinToString("・")
    val unnamed = line.unnamedCount.toInt()
    if (unnamed == 0) return names
    return if (names.isEmpty()) "$unnamed 人" else "$names ほか $unnamed 人"
}
