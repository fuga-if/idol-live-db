package com.fugaif.imaslivedb.ui.components

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Indication
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.semantics
import kotlinx.coroutines.withTimeoutOrNull
import com.fugaif.imaslivedb.ui.theme.DS

/** コピーする項目。label はメニュー文言、text は実際にコピーされる原文。 */
data class CopyItem(val label: String, val text: String?)

/**
 * 長押しメニューに足す、コピー以外の操作。
 *
 * 行の長押しは既にコピーが取っているので、行から直に何かを変えたい画面
 * (曲一覧から習熟度を付ける等) は別のジェスチャを生やさずここに足す。
 */
data class RowAction(val label: String, val onSelect: () -> Unit)

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
    actions: List<RowAction> = emptyList(),
    // 押したときの見え方。デザインシステムの行は波紋を出さず面を沈めるので、
    // 押下の状態 (interactionSource) を受け取り、波紋 (indication) を消せるようにする。
    interactionSource: MutableInteractionSource? = null,
    indication: Indication? = LocalIndication.current,
    content: @Composable () -> Unit
) {
    val valid = items.mapNotNull { item ->
        item.text?.trim()?.takeIf { it.isNotEmpty() }?.let { item.label to it }
    }
    if (valid.isEmpty() && actions.isEmpty()) {
        // コピーする物が無くても、押せる行は押せるままにする。
        val click = if (onClick != null) {
            Modifier.clickable(
                interactionSource = interactionSource,
                indication = indication,
                onClick = onClick
            )
        } else Modifier
        Box(modifier.then(click)) { content() }
        return
    }

    var expanded by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current

    val openMenu = {
        // コピーは画面に変化が出ないので、触覚で「入った」ことを返す。
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        expanded = true
    }
    // 自分では押されない (onClick が無い) ときは、長押しだけを拾ってタップは素通しする。
    // combinedClickable を何もしない onClick で付けると、行を押せるようにした外側の clickable より
    // 先にタップを取ってしまい、行の文字やジャケを押しても詳細へ進まなくなる (余白だけ反応する)。
    val press = if (onClick != null) {
        Modifier.combinedClickable(
            interactionSource = interactionSource,
            indication = indication,
            onClick = onClick,
            onLongClick = openMenu
        )
    } else {
        Modifier.longPressOnly(onLongPress = openMenu)
    }
    Box(modifier = modifier.then(press)) {
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
            actions.forEach { action ->
                DropdownMenuItem(
                    text = { Text(action.label, color = DS.ink) },
                    onClick = {
                        action.onSelect()
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
) = Copyable(listOf(CopyItem(label, text)), modifier, onClick, content = content)

/**
 * 長押しだけを拾う。タップ (長押しの時間より前に離した) は消費しないので、外側の clickable に届く。
 * 長押しが成立したら、その後の動き (離す) を消費して、外側がタップとして扱わないようにする。
 * 読み上げには長押しの操作 (「コピー」) として出す。
 */
private fun Modifier.longPressOnly(onLongPress: () -> Unit): Modifier = this
    .pointerInput(onLongPress) {
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false)
            val released = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                waitForUpOrCancellation()
            }
            if (released == null) {
                // 時間切れ = 長押し。離すまでの動きを消費し、外側にタップを渡さない。
                onLongPress()
                do {
                    val event = awaitPointerEvent()
                    event.changes.forEach { it.consume() }
                } while (event.changes.any { it.pressed })
            }
        }
    }
    .semantics { onLongClick(label = "コピー") { onLongPress(); true } }

private fun copyToClipboard(context: Context, label: String, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    clipboard?.setPrimaryClip(ClipData.newPlainText(label, text))
}
