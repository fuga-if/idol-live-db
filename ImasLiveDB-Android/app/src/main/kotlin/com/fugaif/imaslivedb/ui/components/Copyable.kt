package com.fugaif.imaslivedb.ui.components

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import com.fugaif.imaslivedb.ui.theme.DS

/** コピーする項目。label はメニュー文言、text は実際にコピーされる原文。 */
data class CopyItem(val label: String, val text: String?)

/**
 * 名前・曲名などを長押しでコピーできるようにするラッパ (iOS `imasCopyable` の移植)。
 *
 * 「正式な曲名で外部検索したい」「アイドル名をそのまま貼りたい」といった用途で、
 * 一覧・詳細のどこからでも原文を取り出せるようにする。
 *
 * タップ (詳細へ遷移) と共存させたいので、長押しでメニューを出す形にしている。
 * 表示が省略されていても **原文** を渡すこと。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun Copyable(
    items: List<CopyItem>,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit
) {
    val valid = items.mapNotNull { item ->
        item.text?.trim()?.takeIf { it.isNotEmpty() }?.let { item.label to it }
    }
    if (valid.isEmpty()) {
        Box(modifier) { content() }
        return
    }

    var expanded by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current

    Box(
        modifier = modifier.combinedClickable(
            onClick = { onClick?.invoke() },
            onLongClick = {
                // コピーは画面に変化が出ないので、触覚で「入った」ことを返す。
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                expanded = true
            }
        )
    ) {
        content()
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            valid.forEach { (label, text) ->
                DropdownMenuItem(
                    text = { Text(label, color = DS.ink) },
                    onClick = {
                        copyToClipboard(context, label, text)
                        expanded = false
                    }
                )
            }
        }
    }
}

/** 単一項目用のショートカット。 */
@Composable
fun Copyable(
    text: String?,
    label: String = "コピー",
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit
) = Copyable(listOf(CopyItem(label, text)), modifier, onClick, content)

private fun copyToClipboard(context: Context, label: String, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    clipboard?.setPrimaryClip(ClipData.newPlainText(label, text))
}
