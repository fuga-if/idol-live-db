package com.fugaif.imaslivedb.ui.chatgpt

import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.TextSnippet
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.producercard.PaperCardCodeReader
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import uniffi.imas_core.CallSheetReading
import uniffi.imas_core.SheetLine
import uniffi.imas_core.callSheetLyricLineCount
import uniffi.imas_core.callSheetMaxImages

/**
 * コール表の画像から、歌詞の下書きを作るシート。iOS `CallSheetImportSheet`。
 *
 * 画像を利用者の ChatGPT プランに送って書き写してもらう ([com.fugaif.imaslivedb.data.chatgpt.CallSheetRunner])。
 * できるのは下書きまでで、歌詞は投稿画面の入力欄に入れ、本人が確かめてから送る。ここからは何も保存しない。
 * 読んだ中身の検証・歌詞への当て方はコア (`domain::call_guide_import`)。
 *
 * Android にはコールの編集画面が無いので、読んだコールは使わない (iOS の「歌詞がまだ無い曲」の経路だけ)。
 *
 * @param onUse 「歌詞の投稿に入れる」を押した。読んだ中身を渡してシートを閉じる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallSheetImportSheet(onUse: (CallSheetReading) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val session by module.chatGptPlanService.state.collectAsState()
    val scope = rememberCoroutineScope()
    var progress by remember { mutableStateOf<String?>(null) }
    var reading by remember { mutableStateOf<CallSheetReading?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var job by remember { mutableStateOf<Job?>(null) }

    fun start(uris: List<android.net.Uri>) {
        if (uris.isEmpty() || !session.canUsePlan || progress != null) return
        progress = "画像を開いています…"
        job = scope.launch {
            try {
                val images = uris.mapNotNull { PaperCardCodeReader.loadBitmap(context, it) }
                if (images.isEmpty()) throw com.fugaif.imaslivedb.data.chatgpt.ChatGptPlanTaskException("画像を開けませんでした")
                reading = module.callSheetRunner.read(images) { label -> progress = label }
            } catch (e: CancellationException) {
                // やめた。
                throw e
            } catch (e: Exception) {
                Log.e("CallSheetImport", "call_sheet_read_failed: ${e.message}")
                errorMessage = e.message ?: ""
            } finally {
                progress = null
            }
        }
    }

    fun cancel() {
        job?.cancel()
        job = null
        progress = null
    }

    fun close() {
        job?.cancel()
        onDismiss()
    }

    val pickPhotos = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(callSheetMaxImages().toInt().coerceAtLeast(2)),
    ) { start(it) }
    DisposableEffect(Unit) { onDispose { job?.cancel() } }

    ModalBottomSheet(
        onDismissRequest = { close() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg,
    ) {
        ImasFormBackdrop {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = { close() }), title = "コール表から下書き")
                Column(
                    Modifier.padding(horizontal = DS.Space.screen),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
                ) {
                    val current = reading
                    if (current != null) {
                        Result(
                            reading = current,
                            onUse = { onUse(current); onDismiss() },
                            onRetry = { reading = null },
                        )
                    } else {
                        Intro(
                            canUsePlan = session.canUsePlan,
                            progress = progress,
                            onCancel = { cancel() },
                            onPick = { pickPhotos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                        )
                    }
                }
            }
        }
    }
    ImasErrorAlert(message = errorMessage, onDismiss = { errorMessage = null }, title = "読み取れませんでした")
}

@Composable
private fun Intro(canUsePlan: Boolean, progress: String?, onCancel: () -> Unit, onPick: () -> Unit) {
    ImasNote(
        "コール表の画像を ChatGPT に書き写してもらい、歌詞の下書きを作ります。できるのは下書きまでで、送る前にあなたが確かめます。",
        icon = Icons.Filled.DocumentScanner,
    )
    when {
        !canUsePlan -> ImasNote("マイページで ChatGPT とつなぐと使えます。", icon = Icons.Filled.Link)
        progress != null -> Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
        ) {
            ImasInlineLoading(tint = DS.sys)
            ImasText(progress, role = ImasTextRole.NOTE)
            ImasButton(title = "やめる", onClick = onCancel, icon = Icons.Filled.Close, role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL)
        }
        else -> ImasButton(
            title = "画像を選ぶ",
            onClick = onPick,
            icon = Icons.Filled.PhotoLibrary,
            role = ImasButtonRole.PRIMARY,
            fillsWidth = true,
        )
    }
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasText("選んだ画像は、あなたの ChatGPT のアカウントに送られます。", role = ImasTextRole.NOTE)
        ImasText("自分で作ったコール表か、作った人が使ってよいと言っているものだけを選んでください。", role = ImasTextRole.NOTE)
        ImasText("歌詞は、歌詞カードと見比べて直してから投稿してください (投稿ガイドラインは変わりません)。", role = ImasTextRole.NOTE)
    }
}

@Composable
private fun Result(reading: CallSheetReading, onUse: () -> Unit, onRetry: () -> Unit) {
    ImasNote("歌詞 ${reading.lines.size} 行・コール ${reading.callCount} 件を読みました。", icon = Icons.Filled.Check)
    if (!reading.ocrChecked) {
        ImasNotice(
            kind = ImasNoticeKind.WARNING,
            message = "端末の文字認識で字を拾えなかったので、読んだ中身を確かめられていません。",
        )
    } else if (reading.doubtfulLines > 0u) {
        ImasNotice(
            kind = ImasNoticeKind.WARNING,
            message = "印の付いた ${reading.doubtfulLines} 行は、端末の文字認識で同じ字を確かめられませんでした。歌詞の下書きには入れません。",
        )
    }
    // 歌詞の下書きに入るのは、文字認識で同じ字を確かめられた行だけ (何行かはコアが決める)。
    val usable = callSheetLyricLineCount(reading).toInt()
    if (usable > 0) {
        ImasButton(
            title = "歌詞の投稿に入れる",
            onClick = onUse,
            icon = Icons.Filled.TextSnippet,
            role = ImasButtonRole.PRIMARY,
            size = ImasButtonSize.LARGE,
            fillsWidth = true,
        )
        if (usable < reading.lines.size) {
            ImasNote("確かめられた $usable 行だけを入れます。残りは歌詞カードを見て足してください。", icon = Icons.Filled.Warning)
        }
    } else {
        ImasNote("確かめられた行が無いので、歌詞の下書きは作れません。字がはっきり写った画像で試してください。", icon = Icons.Filled.Warning)
    }
    ImasButton(
        title = "別の画像で読み直す",
        onClick = onRetry,
        icon = Icons.Filled.Refresh,
        role = ImasButtonRole.SECONDARY,
        size = ImasButtonSize.SMALL,
    )
    ImasSection("読んだ中身", style = ImasSectionHeaderStyle.SMALL) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            reading.lines.forEach { line ->
                LineRow(line, Modifier.padding(top = if (line.breakBefore) DS.Space.gap else androidx.compose.ui.unit.Dp(0f)))
            }
        }
    }
}

@Composable
private fun LineRow(line: SheetLine, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            if (line.doubtful) {
                androidx.compose.material3.Icon(
                    Icons.Filled.Warning,
                    contentDescription = "確かめられなかった行",
                    tint = DS.danger,
                )
            }
            ImasText(line.lyric, role = ImasTextRole.BODY)
        }
        if (line.calls.isNotEmpty()) {
            androidx.compose.material3.Text(
                line.calls.joinToString(" / ") { it.text },
                style = ImasTextRole.NOTE.style.copy(fontWeight = FontWeight.SemiBold),
                color = DS.sys,
            )
        }
    }
}
