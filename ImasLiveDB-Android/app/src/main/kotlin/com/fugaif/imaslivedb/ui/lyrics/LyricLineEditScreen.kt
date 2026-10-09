package com.fugaif.imaslivedb.ui.lyrics

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.RemoveRedEye
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.fugaif.imaslivedb.data.lyrics.LyricLine
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormLink
import com.fugaif.imaslivedb.ui.designsystem.ImasFormPage
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormToggle
import com.fugaif.imaslivedb.ui.designsystem.ImasRubyPreview
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.producercard.PaperCardCodeReader
import com.fugaif.imaslivedb.ui.producercard.cardCameraAvailable
import com.fugaif.imaslivedb.ui.producercard.rememberDocumentCamera
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import kotlinx.coroutines.launch
import uniffi.imas_core.lyricRubyJoin
import uniffi.imas_core.lyricRubyRebase
import uniffi.imas_core.lyricRubySplit
import uniffi.imas_core.lyricSubmissionCheck
import uniffi.imas_core.lyricSubmissionIssueBlocks
import uniffi.imas_core.lyricSubmissionIssueMessage

private const val AGREEMENT_PREFS = "imas_settings"
// iOS `@AppStorage("lyricLineEdit.agreedToGuideline")` と同じ鍵。
private const val AGREEMENT_KEY = "lyricLineEdit.agreedToGuideline"

/**
 * 公開中の歌詞の 1 行だけを直す画面 (`PUT /songs/{id}/lyric-lines/{line_id}`)。
 * iOS `LyricLineEditSheet` の移植。
 *
 * 誤字の直しのたびに全文を打ち直させないための入口。行の数は変わらないので、行に付いた
 * タイミング・歌割・コールはその行に残る。送るとすぐ公開され、前の版が残る (投稿と同じ扱い)。
 * 読み仮名は記法を見せず、本文と分けて持つ (`lyricRubySplit` / `lyricRubyRebase` / `lyricRubyJoin`)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LyricLineEditScreen(songId: String, line: LyricLine, onSaved: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // 一度同意した人には同意を求め直さない (同意の中身は投稿と同じガイドライン)。
    var agreed by remember {
        mutableStateOf(context.getSharedPreferences(AGREEMENT_PREFS, Context.MODE_PRIVATE).getBoolean(AGREEMENT_KEY, false))
    }
    fun setAgreed(new: Boolean) {
        agreed = new
        context.getSharedPreferences(AGREEMENT_PREFS, Context.MODE_PRIVATE).edit().putBoolean(AGREEMENT_KEY, new).apply()
    }

    val original = remember(line.id) { lyricRubySplit(line.text) }
    var plain by remember(line.id) { mutableStateOf(original.plain) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showGuide by remember { mutableStateOf(false) }
    var isReading by remember { mutableStateOf(false) }
    var ocrMessage by remember { mutableStateOf<String?>(null) }
    // 読み取った行 (2 行以上読めたとき、どれを入れるか選んでもらう)。
    var scannedLines by remember { mutableStateOf<List<String>>(emptyList()) }

    // 送る形 (読み仮名を、直した本文に付け直して記法で入れたもの)。
    val markup = lyricRubyJoin(plain, lyricRubyRebase(original.plain, plain, original.marks))
    val check = lyricSubmissionCheck(markup, agreed)
    val isChanged = check.normalized != line.text

    /** 読み取った文字を入れる。行が 1 つならそのまま、2 つ以上なら選ぶ候補にする。 */
    fun take(recognized: String) {
        val lines = recognized.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.size == 1) {
            plain = lines[0]
            scannedLines = emptyList()
        } else {
            scannedLines = lines
        }
    }

    fun read(uris: List<Uri>) {
        if (uris.isEmpty()) return
        isReading = true
        scope.launch {
            val images = uris.mapNotNull { PaperCardCodeReader.loadBitmap(context, it) }
            val reading = LyricsCardOcr.read(images)
            isReading = false
            if (reading.text.isEmpty()) {
                ocrMessage = "歌詞カードが画面いっぱいに写った、明るい写真を選んでください。"
            } else {
                take(reading.text)
            }
        }
    }

    fun submit() {
        val currentCheck = check
        if (!currentCheck.canSubmit || !isChanged) return
        isSaving = true
        scope.launch {
            try {
                AppModule.from(context).lyricsApi.editLine(songId, line.id, currentCheck.normalized)
                isSaving = false
                onSaved()
                onDismiss()
            } catch (e: Exception) {
                isSaving = false
                errorMessage = "時間をおいてもう一度お試しください。(${e.message})"
            }
        }
    }

    val openCamera = rememberDocumentCamera(maxPages = 1, onFinish = ::read)
    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) read(listOf(uri))
    }

    Box(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth()) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Submit(
                    canSubmit = check.canSubmit && isChanged && !isSaving && !isReading,
                    isSubmitting = isSaving,
                    onCancel = onDismiss,
                    onSubmit = ::submit
                ),
                title = "この行を直す"
            )
            ImasFormPage {
                ImasFormCard {
                    ImasFormTextField(label = "この行", text = plain, onTextChange = { plain = it }, imprint = "LINE", icon = Icons.Filled.TextFields)
                    if (original.marks.isNotEmpty()) {
                        ImasFormField(label = "見本", imprint = "PREVIEW", icon = Icons.Filled.RemoveRedEye) {
                            ImasRubyPreview(text = markup)
                        }
                    }
                }

                IssueNotes(check)

                OcrSection(
                    canUseCamera = cardCameraAvailable(context),
                    enabled = !isSaving && !isReading,
                    onCamera = openCamera,
                    onPickPhoto = { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                    scannedLines = scannedLines,
                    onPick = { candidate -> plain = candidate; scannedLines = emptyList() }
                )

                ImasFormCard {
                    ImasFormLink(
                        label = "投稿ガイドライン",
                        value = "投稿できるもの・できないもの",
                        onClick = { showGuide = true },
                        imprint = "GUIDE",
                        icon = Icons.Filled.Book
                    )
                    ImasFormToggle(
                        label = "確認",
                        imprint = "CHECK",
                        title = "投稿ガイドラインを読み、それに沿って入力しました",
                        isOn = agreed,
                        onCheckedChange = { setAgreed(it) }
                    )
                }

                ImasText(
                    "直した行はすぐに公開され、運営があとから確認します。この行のタイミング・パート分け・コールはそのまま残ります。",
                    ImasTextRole.NOTE
                )
            }
        }
        ImasSavingOverlay(isSaving || isReading, label = if (isReading) "読み取り中" else "送信中")
    }

    ImasErrorAlert(message = errorMessage, onDismiss = { errorMessage = null }, title = "送信できませんでした")
    ImasErrorAlert(message = ocrMessage, onDismiss = { ocrMessage = null }, title = "文字を読み取れませんでした")

    if (showGuide) {
        Dialog(onDismissRequest = { showGuide = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            LyricSubmissionGuideScreen(onBack = { showGuide = false })
        }
    }
}

/**
 * 歌詞カードの読み取り (iOS `LyricLineEditSheet.ocrSection` の移植)。読んだ行が 1 つならそのまま
 * 入れ、2 つ以上なら押して選んでもらう ([LyricLineEditScreen.take] 相当の呼び出し側で判定済み)。
 * Android には iOS の「テキストをスキャン」(LiveTextCapture) に当たる機能が無いので、書類カメラと
 * 写真選択の 2 つだけ。
 */
@Composable
private fun OcrSection(
    canUseCamera: Boolean,
    enabled: Boolean,
    onCamera: () -> Unit,
    onPickPhoto: () -> Unit,
    scannedLines: List<String>,
    onPick: (String) -> Unit
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            if (canUseCamera) {
                ImasButton(
                    title = "歌詞カードを撮る",
                    onClick = onCamera,
                    modifier = Modifier.weight(1f),
                    icon = Icons.Filled.DocumentScanner,
                    role = ImasButtonRole.SECONDARY,
                    fillsWidth = true,
                    enabled = enabled
                )
            }
            ImasButton(
                title = "写真から読む",
                onClick = onPickPhoto,
                modifier = Modifier.weight(1f),
                icon = Icons.Filled.PhotoLibrary,
                role = ImasButtonRole.SECONDARY,
                fillsWidth = true,
                enabled = enabled
            )
        }
        if (scannedLines.isNotEmpty()) {
            ImasFormCard {
                ImasFormField(label = "読み取った行", imprint = "SCAN", icon = Icons.Filled.TextFields) {
                    Column {
                        scannedLines.forEach { candidate ->
                            androidx.compose.material3.Text(
                                candidate,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = DS.Size.touch)
                                    .imasRowPress(onClick = { onPick(candidate) })
                                    .padding(vertical = DS.Space.gapTight)
                            )
                        }
                    }
                }
            }
        }
        ImasText(
            "文字の読み取りは端末の中だけで行い、映像や写真はどこにも送りません。",
            ImasTextRole.NOTE,
            color = DS.ink3
        )
    }
}

/** コアが出した注意。送信を止める注意は朱で出す (空は送るボタンで分かるので出さない)。 */
@Composable
private fun IssueNotes(check: uniffi.imas_core.LyricSubmissionCheck) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        check.issues.forEach { issue ->
            if (issue != uniffi.imas_core.LyricSubmissionIssue.Empty) {
                ImasText(
                    lyricSubmissionIssueMessage(issue),
                    ImasTextRole.NOTE,
                    color = if (lyricSubmissionIssueBlocks(issue)) DS.danger else ImasTextRole.NOTE.color
                )
            }
        }
    }
}
