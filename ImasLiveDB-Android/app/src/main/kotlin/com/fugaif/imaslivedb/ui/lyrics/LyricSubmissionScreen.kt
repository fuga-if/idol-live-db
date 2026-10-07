package com.fugaif.imaslivedb.ui.lyrics

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.fugaif.imaslivedb.data.lyrics.LyricSubmissionDrafts
import com.fugaif.imaslivedb.data.lyrics.LyricsApi
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCompletionAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasDiscardConfirmation
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormLink
import com.fugaif.imaslivedb.ui.designsystem.ImasFormPage
import com.fugaif.imaslivedb.ui.designsystem.ImasFormSelectableTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasFormToggle
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasRubyPreview
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasStep
import com.fugaif.imaslivedb.ui.designsystem.ImasStepList
import com.fugaif.imaslivedb.ui.producercard.PaperCardCodeReader
import com.fugaif.imaslivedb.ui.producercard.cardCameraAvailable
import com.fugaif.imaslivedb.ui.producercard.rememberDocumentCamera
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.launch
import uniffi.imas_core.LyricSubmissionIssue
import uniffi.imas_core.RubyMark
import uniffi.imas_core.lyricOcrAppend
import uniffi.imas_core.lyricOcrSteps
import uniffi.imas_core.lyricRemoveLines
import uniffi.imas_core.lyricRubyJoin
import uniffi.imas_core.lyricRubyLikeLines
import uniffi.imas_core.lyricRubyMarkAt
import uniffi.imas_core.lyricRubyMarkFound
import uniffi.imas_core.lyricSubmissionCheck
import uniffi.imas_core.lyricSubmissionIssueBlocks
import uniffi.imas_core.lyricSubmissionIssueMessage
import uniffi.imas_core.lyricSubmissionMaxChars

/**
 * 歌詞を投稿する画面 (iOS `LyricSubmissionSheet` の移植)。CD の歌詞カードなどの一次ソースを
 * 見て入力した歌詞を送る。
 *
 * 歌詞の無い曲なら送るとすぐ公開され、運営があとから確認する ([LyricsApi.submitLyricSubmission])。
 * 投稿ガイドラインに同意しないと送れない。入力元は書かせない (どこから写したかは確かめようが
 * なく、規約で縛る)。本文の整え方・上限・注意はコア ([lyricSubmissionCheck]) が決める。
 *
 * 入力は [LyricSubmissionDrafts] に置く (曲ごと・メモリだけ)。画面が作り直されても消えない
 * ようにするため (同期の完了などで再構成されると `remember` は消える)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LyricSubmissionScreen(song: Song, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val draft = LyricSubmissionDrafts.draft(song.id)
    val text = draft.text
    val agreed = draft.agreed
    val rubies = draft.rubies
    /** 送る形の本文 (読み仮名を記法で入れたもの)。画面には出さない。 */
    val markup = lyricRubyJoin(text, rubies)
    fun setText(new: String) = LyricSubmissionDrafts.setText(song.id, new)
    fun setAgreed(new: Boolean) = LyricSubmissionDrafts.update(song.id) { it.copy(agreed = new) }

    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }
    /** 送れたあとの知らせ (公開したか、直しの提案として預かったか)。 */
    var sentMessage by remember { mutableStateOf<String?>(null) }
    var isReading by remember { mutableStateOf(false) }
    var ocrMessage by remember { mutableStateOf<String?>(null) }
    var showGuide by remember { mutableStateOf(false) }

    val check = lyricSubmissionCheck(markup, agreed)
    val isDirty = text.trim().isNotEmpty()

    fun requestDismiss() {
        if (isDirty) confirmDiscard = true else onDismiss()
    }

    fun submit() {
        val currentCheck = check
        if (!currentCheck.canSubmit) return
        isSaving = true
        scope.launch {
            try {
                val published = AppModule.from(context).lyricsApi.submitLyricSubmission(
                    songId = song.id,
                    text = currentCheck.normalized
                )
                LyricSubmissionDrafts.clear(song.id)
                isSaving = false
                sentMessage = if (published) {
                    "歌詞を公開しました。運営があとから確認します。ありがとうございました。"
                } else {
                    "この曲には歌詞があるので、直しの提案として運営が確認します。ありがとうございました。"
                }
            } catch (e: Exception) {
                isSaving = false
                errorMessage = "時間をおいてもう一度お試しください。(${e.message})"
            }
        }
    }

    /** 書類カメラ・写真で撮った歌詞カードを読む。読んだ文字は入力欄に足すだけで、本人が見直してから送る。 */
    fun read(uris: List<Uri>) {
        if (uris.isEmpty()) return
        isReading = true
        scope.launch {
            val images = uris.mapNotNull { PaperCardCodeReader.loadBitmap(context, it) }
            val reading = LyricsCardOcr.read(images)
            isReading = false
            if (reading.text.isEmpty()) {
                ocrMessage = "明るい所で、歌詞カードが画面いっぱいに写るように撮ってください。"
            } else {
                val current = LyricSubmissionDrafts.draft(song.id).text
                LyricSubmissionDrafts.setText(song.id, lyricOcrAppend(current, reading.text))
                LyricSubmissionDrafts.update(song.id) { it.copy(doubtfulLines = it.doubtfulLines + reading.doubtfulLines) }
            }
        }
    }

    val openCamera = rememberDocumentCamera(maxPages = 10, onFinish = ::read)
    val pickPhotos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { read(it) }

    Box(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth()) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Submit(
                    canSubmit = check.canSubmit && !isSaving,
                    isSubmitting = isSaving,
                    onCancel = ::requestDismiss,
                    onSubmit = ::submit
                ),
                title = "歌詞を投稿"
            )
            ImasFormPage {
                ImasFormCard {
                    ImasFormField(label = "曲", imprint = "SONG", icon = Icons.Filled.MusicNote) {
                        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                            Text(song.title)
                            val singer = song.singerLabel
                            if (!singer.isNullOrEmpty()) {
                                ImasText(singer, ImasTextRole.NOTE)
                            }
                        }
                    }
                }

                ImasFormCard {
                    ImasFormLink(
                        label = "投稿ガイドライン",
                        value = "投稿できるもの・できないもの",
                        onClick = { showGuide = true },
                        imprint = "GUIDE",
                        icon = Icons.Filled.Book
                    )
                }

                ImasFormCard {
                    LyricsRubyFields(
                        text = text,
                        onTextChange = { setText(it) },
                        onAddRuby = { start, end, reading ->
                            val mark = lyricRubyMarkAt(plain = text, start = start.toUInt(), end = end.toUInt(), reading = reading)
                            if (mark != null) {
                                LyricSubmissionDrafts.update(song.id) { it.copy(rubies = it.rubies + mark) }
                            }
                        }
                    )
                }

                RubySection(songId = song.id, text = text, markup = markup, rubies = rubies)

                OcrButtons(
                    canUseCamera = cardCameraAvailable(context),
                    enabled = !isReading && !isSaving,
                    onCamera = openCamera,
                    onPickPhotos = {
                        pickPhotos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                )

                IssueNotes(song.id, check.lineCount, check.charCount, check.issues, draft.doubtfulLines)

                ImasFormCard {
                    ImasFormToggle(
                        label = "確認",
                        imprint = "CHECK",
                        title = "投稿ガイドラインを読み、それに沿って入力しました",
                        isOn = agreed,
                        onCheckedChange = { setAgreed(it) }
                    )
                }

                ImasText(
                    "送った歌詞はすぐに公開され、運営があとから確認します。歌詞サイトや他のサービスから写した歌詞は、公開後でも削除し、投稿した人のアカウントを止めることがあります。聴き取りの書き起こしも投稿できません。",
                    ImasTextRole.NOTE
                )
            }
        }
        ImasSavingOverlay(isSaving || isReading, label = if (isReading) "読み取り中" else "送信中")
    }

    ImasDiscardConfirmation(
        isPresented = confirmDiscard,
        onDismiss = { confirmDiscard = false },
        onDiscard = { confirmDiscard = false; LyricSubmissionDrafts.clear(song.id); onDismiss() }
    )

    ImasErrorAlert(message = errorMessage, onDismiss = { errorMessage = null }, title = "送信できませんでした")
    ImasErrorAlert(message = ocrMessage, onDismiss = { ocrMessage = null }, title = "文字を読み取れませんでした")

    ImasCompletionAlert(
        title = "歌詞を送りました",
        message = sentMessage,
        onDismiss = { sentMessage = null; onDismiss() }
    )

    if (showGuide) {
        Dialog(onDismissRequest = { showGuide = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            LyricSubmissionGuideScreen(onBack = { showGuide = false })
        }
    }
}

/**
 * 歌詞カードを撮る・写真から読む (iOS `LyricSubmissionSheet.ocrButtons` の移植)。
 * 読み取りは端末の中だけで行い、読んだ文字は入力欄に足すだけで本人が見直してから送る。
 */
@Composable
private fun OcrButtons(canUseCamera: Boolean, enabled: Boolean, onCamera: () -> Unit, onPickPhotos: () -> Unit) {
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
                onClick = onPickPhotos,
                modifier = Modifier.weight(1f),
                icon = Icons.Filled.PhotoLibrary,
                role = ImasButtonRole.SECONDARY,
                fillsWidth = true,
                enabled = enabled
            )
        }
        ImasStepList(
            // Android には iOS の「テキストをスキャン」(LiveTextCapture) に当たる機能が無い。
            steps = lyricOcrSteps(tapScanner = false).map { ImasStep(title = it.title, detail = it.detail) },
            modifier = Modifier.padding(top = DS.Space.gapTight)
        )
        ImasText(
            "文字の読み取りは端末の中だけで行い、写真はどこにも送りません。",
            ImasTextRole.NOTE,
            color = DS.ink3
        )
    }
}

/** 行数・文字数と、コアが出した注意。送信を止める注意は朱で出す。読み取りに自信の無い行があれば見直しを促す。 */
@Composable
private fun IssueNotes(
    songId: String,
    lineCount: UInt,
    charCount: UInt,
    issues: List<LyricSubmissionIssue>,
    doubtfulLines: List<String>
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        if (lineCount > 0u) {
            ImasText("$lineCount 行 · $charCount / ${lyricSubmissionMaxChars()} 字", ImasTextRole.NOTE)
        }
        if (doubtfulLines.isNotEmpty()) {
            Text(
                "読み取りに自信の無い行があります。歌詞カードと見比べてください:\n" +
                    doubtfulLines.take(12).joinToString("\n") { "・$it" },
                style = ImasTextRole.NOTE.style.copy(fontWeight = FontWeight.SemiBold),
                color = DS.ink2
            )
        }
        issues.forEach { issue ->
            if (issue != LyricSubmissionIssue.Empty) {
                ImasText(
                    lyricSubmissionIssueMessage(issue),
                    ImasTextRole.NOTE,
                    color = if (lyricSubmissionIssueBlocks(issue)) DS.danger else ImasTextRole.NOTE.color
                )
                if (issue is LyricSubmissionIssue.RubyLikeLines) {
                    ImasButton(
                        title = "この行を消す",
                        onClick = {
                            LyricSubmissionDrafts.update(songId) {
                                it.copy(text = lyricRemoveLines(it.text, lyricRubyLikeLines(it.text)))
                            }
                        },
                        role = ImasButtonRole.SECONDARY,
                        size = ImasButtonSize.SMALL
                    )
                }
            }
        }
    }
}

/**
 * 歌詞の入力欄と「選んだ字に読み仮名を付ける」(iOS `LyricsRubyEditor` の移植。文字の選択を読む)。
 * 本文は書き換えず、選んだ範囲 (コードポイントの位置) と読みを [onAddRuby] で返す。読み仮名は
 * 本文と分けて持つ。選択は [TextFieldValue.selection] の UTF-16 の位置なので、呼び出し側に渡す前に
 * コードポイントの位置へ直す。
 */
@Composable
private fun LyricsRubyFields(text: String, onTextChange: (String) -> Unit, onAddRuby: (Int, Int, String) -> Unit) {
    var field by rememberRubyFieldValue(text)
    var pending by remember { mutableStateOf<IntRange?>(null) }
    var reading by remember { mutableStateOf("") }

    val selection = field.selection
    val selectedCodepoints: IntRange? = if (selection.collapsed) {
        null
    } else {
        val start = text.codePointCount(0, selection.min)
        val end = text.codePointCount(0, selection.max)
        start until end
    }

    ImasFormSelectableTextArea(
        label = "歌詞",
        value = field,
        onValueChange = {
            field = it
            if (it.text != text) onTextChange(it.text)
        },
        prompt = "1 行ずつ改行して入力してください",
        imprint = "LYRICS"
    )
    ImasFormField(label = "読み仮名を付ける", imprint = "RUBY", icon = Icons.Filled.TextFields) {
        ImasButton(
            title = if (selectedCodepoints == null) "歌詞の字を選んでください" else "選んだ字に読み仮名を付ける",
            onClick = {
                reading = ""
                pending = selectedCodepoints
            },
            role = ImasButtonRole.SECONDARY,
            size = ImasButtonSize.SMALL,
            enabled = selectedCodepoints != null
        )
    }

    val range = pending
    if (range != null) {
        RubyReadingDialog(
            reading = reading,
            onReadingChange = { reading = it },
            onConfirm = {
                onAddRuby(range.first, range.last + 1, reading)
                pending = null
            },
            onDismiss = { pending = null }
        )
    }
}

/**
 * 付けた読み仮名の一覧 (外せる) と、送ったときの見た目の見本。記法は見せない (iOS `rubySection` の移植)。
 */
@Composable
private fun RubySection(songId: String, text: String, markup: String, rubies: List<RubyMark>) {
    if (rubies.isEmpty()) return
    ImasFormCard {
        ImasFormField(label = "読み仮名", imprint = "RUBY", icon = Icons.Filled.TextFields) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                rubies.forEachIndexed { index, mark ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                        Text("${mark.base} → ${mark.reading}")
                        if (!lyricRubyMarkFound(text, mark)) {
                            ImasText("歌詞に見つかりません", ImasTextRole.NOTE, color = DS.danger)
                        }
                        Spacer(Modifier.weight(1f))
                        ImasIconButton(
                            icon = Icons.Filled.Close,
                            label = "${mark.base} の読み仮名を外す",
                            size = ImasIconButtonSize.SMALL,
                            style = ImasIconButtonStyle.PLAIN,
                            onClick = {
                                LyricSubmissionDrafts.update(songId) { d ->
                                    d.copy(rubies = d.rubies.filterIndexed { i, _ -> i != index })
                                }
                            }
                        )
                    }
                }
            }
        }
        ImasFormField(label = "見本", imprint = "PREVIEW", icon = Icons.Filled.Visibility) {
            ImasRubyPreview(text = markup)
        }
    }
}

/** 外から渡された本文と、手元の入力 (選択を含む) を揃える。 */
@Composable
private fun rememberRubyFieldValue(text: String): MutableState<TextFieldValue> {
    val state = remember { mutableStateOf(TextFieldValue(text, TextRange(text.length))) }
    if (state.value.text != text) {
        state.value = TextFieldValue(text, TextRange(text.length))
    }
    return state
}

/** 読みを入れるダイアログ (iOS の `.alert("読み仮名", …)` の移植)。 */
@Composable
private fun RubyReadingDialog(
    reading: String,
    onReadingChange: (String) -> Unit,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("読み仮名") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                Text("歌詞カードに振られている読み仮名だけを付けてください。")
                OutlinedTextField(
                    value = reading,
                    onValueChange = onReadingChange,
                    placeholder = { Text("歌詞カードに振られている読み", color = DS.ink3) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = { ImasButton(title = "付ける", onClick = onConfirm, role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL) },
        dismissButton = { ImasButton(title = "キャンセル", onClick = onDismiss, role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL) }
    )
}
