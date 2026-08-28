package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Chair
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.HowToReg
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/**
 * 参加 / お気に入り / メモ / 座席 のマーキングバー。iOS `UserMarkBar` の移植。
 *
 * 各マークは「アイコンタイル + ラベル」の軽量セルで、ON のときだけエンティティ色
 * (seed から導出した accent) をまとう。ON/OFF の実体は呼び出し側が持つ — この
 * コンポーネントは DB を知らない。公演とイベントで参加マークの持ち方が違う
 * (公演は形態つき、イベントは公演選択シート経由) ので、書き込みを内側に閉じ込めると
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
    onNoteChange: (String?) -> Unit,
    seat: String?,
    onSeatChange: (String?) -> Unit,
    seed: String? = null,
    brand: String? = null,
    modifier: Modifier = Modifier
) {
    val t = ImasTheme.derive(seed, brand, dark = true)
    var editingNote by remember { mutableStateOf(false) }
    var editingSeat by remember { mutableStateOf(false) }

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        MarkCell(
            icon = Icons.Filled.HowToReg,
            label = attendedLabel,
            isOn = attendedOn,
            theme = t,
            modifier = Modifier.weight(1f),
            onClick = onAttendedClick
        )
        MarkCell(
            icon = if (favoriteOn) Icons.Filled.Star else Icons.Filled.StarBorder,
            label = "お気に入り",
            isOn = favoriteOn,
            theme = t,
            modifier = Modifier.weight(1f),
            onClick = onFavoriteClick
        )
        MarkCell(
            icon = Icons.Filled.EditNote,
            label = "メモ",
            isOn = !note.isNullOrBlank(),
            theme = t,
            modifier = Modifier.weight(1f),
            onClick = { editingNote = true }
        )
        // 参加していない公演に座席は無い。iOS と同じく attended のときだけ出す。
        if (attendedOn) {
            MarkCell(
                icon = Icons.Filled.Chair,
                label = seat?.takeIf { it.isNotBlank() } ?: "座席",
                isOn = !seat.isNullOrBlank(),
                theme = t,
                modifier = Modifier.weight(1f),
                onClick = { editingSeat = true }
            )
        }
    }

    if (editingNote) {
        TextMarkDialog(
            title = "メモ",
            placeholder = "この公演の思い出・持ち物・同行者など",
            initial = note.orEmpty(),
            singleLine = false,
            onDismiss = { editingNote = false },
            onSave = { editingNote = false; onNoteChange(it) }
        )
    }
    if (editingSeat) {
        TextMarkDialog(
            title = "座席",
            placeholder = "例: アリーナ A6 ブロック 12番",
            initial = seat.orEmpty(),
            singleLine = true,
            onDismiss = { editingSeat = false },
            onSave = { editingSeat = false; onSeatChange(it) }
        )
    }
}

/**
 * アイコンタイル + ラベルの 1 セル。タイルは 50dp 固定でタップ領域を確保する
 * (ラベルの長さでタップ面積が変わらないように)。
 */
@Composable
private fun MarkCell(
    icon: ImageVector,
    label: String,
    isOn: Boolean,
    theme: ImasTheme,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Column(
        modifier = modifier.clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        Box(
            modifier = Modifier
                .size(50.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(if (isOn) theme.accent else theme.chipBg)
                .then(
                    if (isOn) Modifier
                    else Modifier.border(0.5.dp, DS.sep, RoundedCornerShape(15.dp))
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (isOn) theme.onAccent else theme.chipText,
                modifier = Modifier.size(19.dp)
            )
        }
        Text(
            label,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = if (isOn) theme.accent else DS.ink2,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center
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
