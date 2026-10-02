package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Chair
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.HowToReg
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkBar
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkTile
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasThemeProvider

/**
 * 参加 / お気に入り / メモ / 座席 のマーキングバー。iOS `UserMarkBar` の移植。
 * 見た目は DesignSystem の `ImasMarkBar` (1 本の帯) + `ImasMarkTile` (ON は実体の色で点く丸いパンチ)。
 *
 * ON/OFF の実体は呼び出し側が持つ — この部品は DB を知らない。公演とイベントで参加マークの
 * 持ち方が違う (公演は形態つき、イベントは公演選択シート経由) ので、書き込みを内側に閉じ込めると
 * どちらかに寄った作りになってしまうため。
 *
 * 座席は「参加」済みのときだけ出す。行っていない公演の座席を記録する意味がない。
 */
@Composable
fun UserMarkBar(
    attendedLabel: String,
    attendedOn: Boolean,
    onAttendedClick: () -> Unit,
    favoriteOn: Boolean,
    onFavoriteClick: () -> Unit,
    note: String?,
    /** (新しい値, 保存できたときに呼ぶ)。書けなかったときは編集を閉じない。 */
    onNoteChange: (String?, () -> Unit) -> Unit,
    seat: String?,
    /** (新しい値, 保存できたときに呼ぶ)。書けなかったときは編集を閉じない。 */
    onSeatChange: (String?, () -> Unit) -> Unit,
    seed: String? = null,
    brand: String? = null,
    modifier: Modifier = Modifier
) {
    var editingNote by remember { mutableStateOf(false) }
    var editingSeat by remember { mutableStateOf(false) }

    ImasThemeProvider(seed = seed, brand = brand) {
        ImasMarkBar(modifier = modifier.fillMaxWidth()) {
            ImasMarkTile(
                icon = Icons.Filled.HowToReg,
                label = attendedLabel,
                isOn = attendedOn,
                onClick = onAttendedClick,
                modifier = Modifier.weight(1f)
            )
            ImasMarkTile(
                icon = if (favoriteOn) Icons.Filled.Star else Icons.Filled.StarBorder,
                label = "お気に入り",
                isOn = favoriteOn,
                onClick = onFavoriteClick,
                modifier = Modifier.weight(1f)
            )
            ImasMarkTile(
                icon = Icons.Filled.EditNote,
                label = "メモ",
                isOn = !note.isNullOrBlank(),
                onClick = { editingNote = true },
                modifier = Modifier.weight(1f)
            )
            // 参加していない公演に座席は無い。iOS と同じく attended のときだけ出す。
            if (attendedOn) {
                ImasMarkTile(
                    icon = Icons.Filled.Chair,
                    label = seat?.takeIf { it.isNotBlank() } ?: "座席",
                    isOn = !seat.isNullOrBlank(),
                    onClick = { editingSeat = true },
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }

    if (editingNote) {
        TextMarkDialog(
            title = "メモ",
            placeholder = "この公演の思い出・持ち物・同行者など",
            initial = note.orEmpty(),
            singleLine = false,
            onDismiss = { editingNote = false },
            onSave = { onNoteChange(it) { editingNote = false } }
        )
    }
    if (editingSeat) {
        TextMarkDialog(
            title = "座席",
            placeholder = "例: アリーナ A6 ブロック 12番",
            initial = seat.orEmpty(),
            singleLine = true,
            onDismiss = { editingSeat = false },
            onSave = { onSeatChange(it) { editingSeat = false } }
        )
    }
}

/**
 * メモ / 座席の入力ダイアログ。空にして保存すると「未入力」に戻る
 * (削除ボタンを別に置くと、消したいだけの操作に 2 手かかるため)。
 */
@Composable
private fun TextMarkDialog(
    title: String,
    placeholder: String,
    initial: String,
    singleLine: Boolean,
    onDismiss: () -> Unit,
    onSave: (String?) -> Unit
) {
    var draft by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                placeholder = { Text(placeholder, color = DS.ink3) },
                singleLine = singleLine,
                minLines = if (singleLine) 1 else 3,
                modifier = Modifier.fillMaxWidth()
            )
        },
        confirmButton = {
            TextButton(onClick = { onSave(draft.trim().ifEmpty { null }) }) { Text("保存") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("キャンセル") } }
    )
}
