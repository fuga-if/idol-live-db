package com.fugaif.imaslivedb.ui.edit

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.friendlyMessage
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS

// =============================================================================
// マスタ編集フォームの共通部品。iOS の各 *EditView (SongEditView / IdolEditView /
// EventEditView / ShowEditView) が SwiftUI の Form + toolbar で共有していた見た目と
// 振る舞いを、Compose 側で 1 箇所にまとめたもの。
//
// 新しい UI 言語は持ち込まない: 枠は SetlistEditScreen (Scaffold + TopAppBar +
// 保存中オーバーレイ + AlertDialog) を、入力欄は CallEditSheet (OutlinedTextField +
// 補足文) をそのまま踏襲する。
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
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onCancel) { Icon(Icons.Filled.Close, "キャンセル") }
                },
                actions = {
                    TextButton(onClick = onSave, enabled = canSave && !isSaving) {
                        Text("保存", fontWeight = FontWeight.SemiBold)
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            Column(
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                content = content
            )
            if (isSaving) {
                // 保存中は全面を覆って二重送信を止める (iOS の savingOverlay と同じ役割)。
                Box(
                    Modifier.fillMaxSize().background(DS.bg.copy(alpha = 0.5f)),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        modifier = Modifier.clip(RoundedCornerShape(12.dp)).background(DS.surface).padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        CircularProgressIndicator()
                        Text("保存中…", fontSize = 13.sp, color = DS.ink2, modifier = Modifier.padding(top = 8.dp))
                    }
                }
            }
        }
    }
}

/** Form の 1 セクション。iOS の `Section(header:footer:)` 相当。 */
@Composable
fun EditSection(
    title: String,
    footer: String? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Text(
            title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
            modifier = Modifier.padding(bottom = 6.dp)
        )
        Column(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                .background(DS.surface).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content
        )
        if (footer != null) {
            Text(footer, fontSize = 11.sp, color = DS.ink3, modifier = Modifier.padding(top = 6.dp))
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
    minLines: Int = 1,
    isError: Boolean = false,
    supportingText: String? = null
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = singleLine,
        minLines = minLines,
        isError = isError,
        supportingText = supportingText?.let { { Text(it, fontSize = 11.sp) } },
        keyboardOptions = if (numeric) KeyboardOptions(keyboardType = KeyboardType.Number) else KeyboardOptions.Default,
        modifier = Modifier.fillMaxWidth()
    )
}

/**
 * 選択肢から 1 つ選ぶ行 (iOS の `Picker`)。
 * `options` は (内部値, 表示ラベル)。未選択を許す場合は空文字の選択肢を先頭に入れておく。
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
        Row(
            modifier = Modifier.fillMaxWidth().clickable { expanded = true }.padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(label, fontSize = 15.sp, color = DS.ink2)
            Box(Modifier.weight(1f))
            Text(
                selectedLabel, fontSize = 15.sp, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = DS.ink3)
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
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("$label: $value", fontSize = 15.sp, color = DS.ink, modifier = Modifier.weight(1f))
        TextButton(onClick = { onValueChange((value - 1).coerceIn(range)) }) { Text("−", fontSize = 18.sp) }
        TextButton(onClick = { onValueChange((value + 1).coerceIn(range)) }) { Text("＋", fontSize = 18.sp) }
    }
}

/** タップで別画面/シートを開く行 (iOS の Button + chevron 行)。未選択時は placeholder を薄く出す。 */
@Composable
fun EditNavRow(label: String, value: String?, placeholder: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(label, fontSize = 12.sp, color = DS.ink2)
            Text(
                value?.takeIf { it.isNotEmpty() } ?: placeholder,
                fontSize = 15.sp,
                color = if (value.isNullOrEmpty()) DS.ink3 else DS.ink
            )
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = DS.ink3)
    }
}

/** 編集できない値を見せるだけの行 (レコード ID など)。 */
@Composable
fun EditReadonlyRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, fontSize = 15.sp, color = DS.ink2)
        Box(Modifier.weight(1f))
        Text(value, fontSize = 13.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** 保存に失敗した時のダイアログ (iOS の `.alert("エラー")`)。 */
@Composable
fun EditErrorDialog(message: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        title = { Text("エラー") },
        text = { Text(message) }
    )
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
                        modifier = Modifier.padding(top = 8.dp).clickable { uriHandler.openUri(issueUrl) }
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
 * - ローカルに書いたら**その場で**スナップショットを作り直す。省くとスナップショット経由で
 *   読む口だけが次の同期完了まで編集前の値を返し、「編集直後に自分の編集が見えない」に
 *   なる (EventRepository.replaceSetlist と同じ理由)。
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
                applyLocally(resolved)
                module.snapshotStoreProvider.reload()
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
