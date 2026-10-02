package com.fugaif.imaslivedb.ui.edit

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.friendlyMessage
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormLink
import com.fugaif.imaslivedb.ui.designsystem.ImasFormPage
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress

// =============================================================================
// マスタ編集フォームの共通部品。iOS の各 *EditView (SongEditView / IdolEditView /
// EventEditView / ShowEditView) が SwiftUI の Form + toolbar で共有していた見た目と
// 振る舞いを、Compose 側で 1 箇所にまとめたもの。
//
// 中身は DesignSystem の「申込書」部品 (docs/DESIGN_SYSTEM.md §2.4) だけで組む:
// ImasFormPage (本体) / ImasFormCard (区画の紙) / ImasFormField 系 (欄) /
// ImasSheetToolbar (×・✓) / ImasSavingOverlay (保存中) / ImasErrorAlert (失敗)。
// 公開関数のシグネチャ (関数名・引数・型) は呼び出し側 (Idol/Song/Event/Show/TicketSale
// の各 EditScreen) に合わせて一切変えていない。変わるのは内部の組み方だけ。
// =============================================================================

/**
 * 編集フォームの画面枠。呼び出し元はフルスクリーン `Dialog` に載せる
 * (RecentEditsScreen → SetlistEditScreen と同じ出し方)。
 *
 * **必ず [Scaffold] を通す**こと。素の Column で組むと、edge-to-edge が効いている
 * この端末構成では「保存」がステータスバーに潜り込み、タップがシステム側に吸われて
 * 押せなくなる (DailyPickSheet で実際に起きた事故)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MasterEditScaffold(
    title: String,
    canSave: Boolean,
    isSaving: Boolean,
    onCancel: () -> Unit,
    onSave: () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    Scaffold(
        topBar = {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Edit(canSave = canSave && !isSaving, onCancel = onCancel, onSave = onSave),
                title = title
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            ImasFormPage(content = content)
            ImasSavingOverlay(isSaving, label = "保存中…")
        }
    }
}

/** Form の 1 セクション。iOS の `Section(header:footer:)` 相当。中身は 1 枚の紙 ([ImasFormCard]) にまとめる。 */
@Composable
fun EditSection(
    title: String,
    footer: String? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(Modifier.fillMaxWidth()) {
        ImasSectionHeader(
            title,
            style = ImasSectionHeaderStyle.SMALL,
            contentPadding = PaddingValues(bottom = DS.Space.header)
        )
        ImasFormCard(content = content)
        if (footer != null) {
            ImasNote(footer, Modifier.padding(top = DS.Space.note))
        }
    }
}

/** 1 行のテキスト入力。`numeric` は数値専用キーボード (iOS の keyboardType 指定に対応)。 */
@Composable
fun EditTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    numeric: Boolean = false,
    singleLine: Boolean = true,
    @Suppress("UNUSED_PARAMETER") minLines: Int = 1,
    isError: Boolean = false,
    supportingText: String? = null
) {
    // isError を欄まで渡さないと、見出しが朱にならずスクリーンリーダーにも誤りが伝わらない
    // (前の OutlinedTextField.isError は枠の色とアクセシビリティの両方を兼ねていた)。
    val errorModifier = if (isError) {
        Modifier.semantics { error(supportingText ?: "入力エラー") }
    } else {
        Modifier
    }
    Column(Modifier.fillMaxWidth()) {
        if (singleLine) {
            ImasFormTextField(
                label = label,
                text = value,
                onTextChange = onValueChange,
                keyboardType = if (numeric) KeyboardType.Number else KeyboardType.Text,
                isError = isError,
                modifier = errorModifier
            )
        } else {
            ImasFormTextArea(
                label = label,
                text = value,
                onTextChange = onValueChange,
                prompt = label,
                imprint = null,
                icon = null,
                modifier = errorModifier
            )
        }
        if (supportingText != null) {
            Text(
                supportingText,
                style = ImasTextRole.NOTE.style,
                color = if (isError) DS.danger else ImasTextRole.NOTE.color,
                modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapTight)
            )
        }
    }
}

/**
 * 選択肢から 1 つ選ぶ行 (iOS の `Picker`)。
 * `options` は (内部値, 表示ラベル)。未選択を許す場合は空文字の選択肢を先頭に入れておく。
 *
 * ブランド・種別など選択肢数が呼び出し側ごとに大きく異なる (数個〜数十個) 共通部品なので、
 * 大きな札 ([com.fugaif.imaslivedb.ui.designsystem.ImasChoiceCards]) ではなく、タップでその場に
 * 選択肢一覧を開く形 ([DropdownMenu] は OS 標準なのでそのまま使う) を保つ。
 */
@Composable
fun EditDropdownField(
    label: String,
    options: List<Pair<String, String>>,
    selected: String,
    onSelect: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedLabel = options.firstOrNull { it.first == selected }?.second ?: selected
    Box(Modifier.fillMaxWidth()) {
        ImasFormField(
            label = label,
            modifier = Modifier
                .clearAndSetSemantics {
                    contentDescription = "$label、$selectedLabel"
                    role = Role.Button
                    onClick { expanded = true; true }
                }
                .imasRowPress(onClick = { expanded = true })
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    selectedLabel,
                    color = DS.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = DS.ink3)
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (value, optionLabel) ->
                DropdownMenuItem(
                    text = { Text(optionLabel) },
                    onClick = { onSelect(value); expanded = false }
                )
            }
        }
    }
}

/** 整数を ± で刻む行 (iOS の `Stepper`)。並び順のように範囲が決まっている値に使う。 */
@Composable
fun EditStepperRow(label: String, value: Int, range: IntRange, onValueChange: (Int) -> Unit) {
    ImasFormField(label = label) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "$value",
                style = ImasNumeralSize.MEDIUM.style,
                color = DS.ink,
                modifier = Modifier.weight(1f).semantics { contentDescription = "$label: $value" }
            )
            TextButton(onClick = { onValueChange((value - 1).coerceIn(range)) }) { Text("−") }
            TextButton(onClick = { onValueChange((value + 1).coerceIn(range)) }) { Text("＋") }
        }
    }
}

/** タップで別画面/シートを開く行 (iOS の Button + chevron 行)。未選択時は placeholder を薄く出す。 */
@Composable
fun EditNavRow(label: String, value: String?, placeholder: String, onClick: () -> Unit) {
    ImasFormLink(
        label = label,
        value = value?.takeIf { it.isNotEmpty() },
        onClick = onClick,
        placeholder = placeholder
    )
}

/** 編集できない値を見せるだけの行 (レコード ID など)。 */
@Composable
fun EditReadonlyRow(label: String, value: String) {
    ImasFormField(label = label) {
        Text(
            value,
            color = DS.ink3,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.semantics { contentDescription = "$label: $value" }
        )
    }
}

/** 保存に失敗した時のダイアログ (iOS の `.alert("エラー")`)。 */
@Composable
fun EditErrorDialog(message: String, onDismiss: () -> Unit) {
    ImasErrorAlert(message = message, onDismiss = onDismiss, title = "エラー")
}

/**
 * 一般ユーザーの編集が修正リクエスト (GitHub issue) になった時の通知。
 * iOS の `.editRequestSentAlert` / SetlistEditScreen の Requested ダイアログと同じ文面。
 */
@Composable
fun EditRequestSentDialog(issueUrl: String?, onDismiss: () -> Unit) {
    val uriHandler = LocalUriHandler.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("編集リクエストを送信しました") },
        text = {
            Column {
                Text("この編集はすぐには反映されず、承認後に反映されます。")
                if (issueUrl != null) {
                    Text(
                        "進捗を見る",
                        color = DS.pick,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(top = DS.Space.gapTight).clickable { uriHandler.openUri(issueUrl) }
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } }
    )
}

// -----------------------------------------------------------------------------
// 送信
// -----------------------------------------------------------------------------

/** マスタ編集の結末。admin は即時反映 + ローカル反映、一般ユーザーは issue 化のみ。 */
sealed class MasterEditSubmitResult {
    /** CloudKit へ反映され、[submitMasterEdit] の `applyLocally` も終わった状態。 */
    data class Applied(val recordName: String) : MasterEditSubmitResult()

    /** 修正リクエストとして受理された。CloudKit 未反映なのでローカルは触っていない。 */
    data class Requested(val issueUrl: String?) : MasterEditSubmitResult()

    data class Failed(val message: String) : MasterEditSubmitResult()
}

/**
 * 1 batch のマスタ編集を送り、admin なら [applyLocally] でローカル DB にも楽観反映する。
 *
 * - `recordName` は**サーバ確定値**を使う (create をサーバ採番に任せた時、送信値は空なので)。
 * - [applyLocally] は [com.fugaif.imaslivedb.data.repository.MasterEditRepository] を通して書く。
 *   あちらが 1 トランザクションで書き、その場でスナップショットを作り直す (省くとスナップショット
 *   経由で読む口だけが次の同期完了まで編集前の値を返し、「編集直後に自分の編集が見えない」になる)。
 * - 例外はここで日本語の短文に畳む。呼び出し側が 401/403/429 を個別に扱う必要はない。
 *
 * @param fallbackRecordName create でクライアント採番した ID (Song など)。サーバが
 *        recordName を返さなかった時の保険。
 */
suspend fun submitMasterEdit(
    context: Context,
    ops: List<EditApi.EditOperation>,
    summary: String,
    fallbackRecordName: String? = null,
    applyLocally: suspend (String) -> Unit
): MasterEditSubmitResult {
    val module = AppModule.from(context)
    return try {
        when (val outcome = module.editApi.submitMaster(ops, summary)) {
            is EditApi.MasterEditOutcome.Applied -> {
                val resolved = outcome.response.primaryRecordName(fallbackRecordName)
                    ?: return MasterEditSubmitResult.Failed("保存に失敗しました (ID 未確定)")
                // 端末の DB への反映 (と、スナップショットの作り直し) は MasterEditRepository が行う。
                applyLocally(resolved)
                MasterEditSubmitResult.Applied(resolved)
            }
            is EditApi.MasterEditOutcome.Requested ->
                MasterEditSubmitResult.Requested(outcome.response.issueUrl)
        }
    } catch (e: EditApi.ApiException) {
        MasterEditSubmitResult.Failed(e.friendlyMessage())
    } catch (e: Exception) {
        MasterEditSubmitResult.Failed("保存失敗: ${e.message}")
    }
}

// -----------------------------------------------------------------------------
// 入力値の共通ルール (iOS と条件を 1:1 で揃える)
// -----------------------------------------------------------------------------

/** trim 後に空なら null、それ以外は trim 済み文字列 (iOS `nonEmpty(_:)`)。 */
fun String.nonEmptyTrimmed(): String? = trim().ifEmpty { null }

/**
 * `YYYY-MM-DD` の最小限の妥当性チェック。iOS `SongEditView.isValidISODate` と同じ条件
 * (桁数まで見るのでサーバ validator の `^\d{4}-\d{2}-\d{2}$` と整合する)。
 */
fun isValidIsoDate(s: String): Boolean {
    val parts = s.split("-")
    if (parts.size != 3) return false
    if (parts[0].length != 4 || parts[0].toIntOrNull() == null) return false
    if (parts[1].length != 2) return false
    val m = parts[1].toIntOrNull() ?: return false
    if (m !in 1..12) return false
    if (parts[2].length != 2) return false
    val d = parts[2].toIntOrNull() ?: return false
    return d in 1..31
}

/**
 * 公演日の妥当性チェック。iOS `ShowEditView.isValidDate` と同じ条件で、
 * 月日の**桁数を見ない**ぶん [isValidIsoDate] より緩い ("2024-1-5" を通す)。
 *
 * サーバ validator は `^\d{4}-\d{2}-\d{2}$` なので "2024-1-5" は結局 400 になるが、
 * ここを勝手に厳しくすると iOS と条件がズレる。揃えることを優先し、iOS 側と一緒に
 * 直すべきものとしてこの差を明示しておく。
 */
fun isValidShowDate(s: String): Boolean {
    val parts = s.split("-")
    if (parts.size != 3) return false
    if (parts[0].length != 4 || parts[0].toIntOrNull() == null) return false
    val m = parts[1].toIntOrNull() ?: return false
    if (m !in 1..12) return false
    val d = parts[2].toIntOrNull() ?: return false
    return d in 1..31
}
