package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress
import java.text.BreakIterator

// =============================================================================
// チップ型の 1 行追加入力 (iOS `Idols/ImasChipInputField.swift` の移植)。
//
// マイタグ等、押すと増える手元のチップを 1 行で追加する欄。カプセルの入力欄 + 丸い追加ボタン。
// アイドル・ユニット詳細の「マイタグ」で共通して使う。
// =============================================================================

/** 先頭から見た目の文字 [n] 個ぶん (絵文字や結合文字を割らない)。 */
private fun prefixGraphemes(text: String, n: Int): String {
    val iterator = BreakIterator.getCharacterInstance()
    iterator.setText(text)
    var end = 0
    repeat(n) {
        val next = iterator.next()
        if (next == BreakIterator.DONE) return text
        end = next
    }
    return text.substring(0, end)
}

/**
 * チップを 1 行で追加する欄 (iOS `ImasChipInputField`)。
 *
 * @param limit 文字数の上限。超えた分は切り詰める。
 * @param submitAccessibilityLabel 追加ボタンの読み上げ (「マイタグを追加」等)。記号だけのボタンなので必須。
 */
@Composable
fun ImasChipInputField(
    text: String,
    onTextChange: (String) -> Unit,
    prompt: String,
    submitAccessibilityLabel: String,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
    limit: Int? = null,
    isEnabled: Boolean = true
) {
    var field by remember { mutableStateOf(TextFieldValue(text, TextRange(text.length))) }
    if (field.text != text) field = TextFieldValue(text, TextRange(text.length))
    val style = ImasType.text(15.sp)
    val ink = DS.ink
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        verticalAlignment = Alignment.CenterVertically
    ) {
        BasicTextField(
            value = field,
            onValueChange = { next ->
                val limited = if (limit != null && graphemeCount(next.text) > limit) {
                    val cut = prefixGraphemes(next.text, limit)
                    TextFieldValue(cut, TextRange(cut.length))
                } else {
                    next
                }
                field = limited
                if (limited.text != text) onTextChange(limited.text)
            },
            modifier = Modifier
                .weight(1f)
                .background(DS.fill, CircleShape)
                .padding(horizontal = DS.Space.gapLoose, vertical = DS.Space.gap)
                .semantics { contentDescription = prompt },
            textStyle = style.copy(color = ink),
            singleLine = true,
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onSubmit() }),
            cursorBrush = SolidColor(ink),
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (text.isEmpty()) Text(prompt, style = style, color = DS.ink3, maxLines = 1)
                    inner()
                }
            }
        )
        Box(
            Modifier
                .size(DS.Size.touch)
                .clearAndSetSemantics {
                    contentDescription = submitAccessibilityLabel
                    role = Role.Button
                    if (!isEnabled) disabled()
                    if (isEnabled) onClick { onSubmit(); true }
                }
                .imasPress(enabled = isEnabled, onClick = onSubmit),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Filled.AddCircle,
                contentDescription = null,
                tint = if (isEnabled) DS.ink else DS.ink3,
                modifier = Modifier.size(with(LocalDensity.current) { 28.sp.toDp() })
            )
        }
    }
}
