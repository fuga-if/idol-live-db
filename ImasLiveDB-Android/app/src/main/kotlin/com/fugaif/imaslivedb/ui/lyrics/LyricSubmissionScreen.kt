package com.fugaif.imaslivedb.ui.lyrics

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Album
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.lyrics.LyricsApi
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasChoice
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceCards
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceCardsStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasCompletionAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasDiscardConfirmation
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormPage
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormToggle
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.producercard.PaperCardCodeReader
import com.fugaif.imaslivedb.ui.producercard.cardCameraAvailable
import com.fugaif.imaslivedb.ui.producercard.rememberDocumentCamera
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.launch
import uniffi.imas_core.LyricSourceKind
import uniffi.imas_core.LyricSubmissionIssue
import uniffi.imas_core.lyricOcrAppend
import uniffi.imas_core.lyricSourceDetail
import uniffi.imas_core.lyricSourceKinds
import uniffi.imas_core.lyricSourceLabel
import uniffi.imas_core.lyricSubmissionCheck
import uniffi.imas_core.lyricSubmissionIssueBlocks
import uniffi.imas_core.lyricSubmissionIssueMessage
import uniffi.imas_core.lyricSubmissionMaxChars

/**
 * 歌詞を投稿する画面 (iOS `LyricSubmissionSheet` の移植)。CD の歌詞カードなどの一次ソースを
 * 見て入力した歌詞を送る。
 *
 * 送った歌詞は確認待ちで預かられ、公開はモデレーターの確認後 ([LyricsApi.submitLyricSubmission])。
 * 入力元の選択と「歌詞サイトから写していない」の確認が無いと送れない。
 * 本文の整え方・上限・注意はコア ([lyricSubmissionCheck]) が決める。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LyricSubmissionScreen(song: Song, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var source by remember { mutableStateOf<LyricSourceKind?>(null) }
    var sourceNote by remember { mutableStateOf("") }
    var text by remember { mutableStateOf("") }
    var attested by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var sent by remember { mutableStateOf(false) }
    var isReading by remember { mutableStateOf(false) }
    var ocrMessage by remember { mutableStateOf<String?>(null) }

    val check = lyricSubmissionCheck(text, source, attested)
    val isDirty = text.trim().isNotEmpty() || source != null

    fun requestDismiss() {
        if (isDirty) confirmDiscard = true else onDismiss()
    }

    fun submit() {
        val currentCheck = check
        val currentSource = source
        if (!currentCheck.canSubmit || currentSource == null) return
        val note = sourceNote.trim()
        isSaving = true
        scope.launch {
            try {
                AppModule.from(context).lyricsApi.submitLyricSubmission(
                    songId = song.id,
                    sourceKind = currentSource,
                    sourceNote = note.ifEmpty { null },
                    text = currentCheck.normalized
                )
                isSaving = false
                sent = true
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
            val recognized = LyricsCardOcr.read(images)
            isReading = false
            if (recognized.isEmpty()) {
                ocrMessage = "明るい所で、歌詞カードが画面いっぱいに写るように撮ってください。"
            } else {
                text = lyricOcrAppend(text, recognized)
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

                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
                    ImasSectionHeader(title = "何を見て入力しましたか", style = ImasSectionHeaderStyle.SMALL)
                    ImasChoiceCards(
                        choices = lyricSourceKinds().map { kind ->
                            ImasChoice(
                                value = kind,
                                title = lyricSourceLabel(kind),
                                icon = sourceIcon(kind),
                                subtitle = lyricSourceDetail(kind)
                            )
                        },
                        selection = source,
                        onSelect = { source = it },
                        style = ImasChoiceCardsStyle.ROW
                    )
                }

                ImasFormCard {
                    ImasFormTextArea(
                        label = "歌詞",
                        text = text,
                        onTextChange = { text = it },
                        prompt = "1 行ずつ改行して入力してください",
                        imprint = "LYRICS"
                    )
                    ImasFormTextField(
                        label = "入力元の補足 (任意)",
                        text = sourceNote,
                        onTextChange = { sourceNote = it },
                        imprint = "SOURCE",
                        prompt = "例: 初回限定盤のブックレット"
                    )
                }

                OcrButtons(
                    canUseCamera = cardCameraAvailable(context),
                    enabled = !isReading && !isSaving,
                    onCamera = openCamera,
                    onPickPhotos = {
                        pickPhotos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                )

                IssueNotes(check.lineCount, check.charCount, check.issues)

                ImasFormCard {
                    ImasFormToggle(
                        label = "確認",
                        imprint = "CHECK",
                        title = "歌詞サイトから写していません",
                        isOn = attested,
                        onCheckedChange = { attested = it }
                    )
                }

                ImasText(
                    "送った歌詞は運営が確認してから公開します。CD の歌詞カードや、公式に公開されている歌詞を見て入力してください。\n" +
                        "次のものは投稿できません: 歌詞サイトから写した歌詞、聴き取りの書き起こし、歌詞が公表されていない曲、" +
                        "翻訳や替え歌、歌詞ではない文 (作詞・作曲などのクレジット)。分かった時点で削除します。",
                    ImasTextRole.NOTE
                )
            }
        }
        ImasSavingOverlay(isSaving || isReading, label = if (isReading) "読み取り中" else "送信中")
    }

    ImasDiscardConfirmation(
        isPresented = confirmDiscard,
        onDismiss = { confirmDiscard = false },
        onDiscard = { confirmDiscard = false; onDismiss() }
    )

    ImasErrorAlert(message = errorMessage, onDismiss = { errorMessage = null }, title = "送信できませんでした")
    ImasErrorAlert(message = ocrMessage, onDismiss = { ocrMessage = null }, title = "文字を読み取れませんでした")

    ImasCompletionAlert(
        title = "歌詞を送りました",
        message = if (sent) "運営が確認してから公開します。ありがとうございました。" else null,
        onDismiss = { sent = false; onDismiss() }
    )
}

private fun sourceIcon(kind: LyricSourceKind): ImageVector = when (kind) {
    LyricSourceKind.BOOKLET -> Icons.Filled.Album
    LyricSourceKind.OFFICIAL -> Icons.Filled.Public
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
        ImasText(
            "文字の読み取りは端末の中だけで行い、写真は送りません。読み取った歌詞は誤りがないか見直してから送ってください。",
            ImasTextRole.NOTE,
            color = DS.ink3
        )
    }
}

/** 行数・文字数と、コアが出した注意。送信を止める注意は朱で出す。 */
@Composable
private fun IssueNotes(lineCount: UInt, charCount: UInt, issues: List<LyricSubmissionIssue>) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        if (lineCount > 0u) {
            ImasText("$lineCount 行 · $charCount / ${lyricSubmissionMaxChars()} 字", ImasTextRole.NOTE)
        }
        issues.forEach { issue ->
            if (issue != LyricSubmissionIssue.Empty) {
                ImasText(
                    lyricSubmissionIssueMessage(issue),
                    ImasTextRole.NOTE,
                    color = if (lyricSubmissionIssueBlocks(issue)) DS.danger else ImasTextRole.NOTE.color
                )
            }
        }
    }
}
