package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

// =============================================================================
// チャット (docs/DESIGN_SYSTEM.md §9)。iOS `ImasChat.swift` と対。
//
// 用途      会話の画面。利用者の発言の紙片と、画面の下に据える入力欄。
// 使わない  相手の返事 → 地の文 (ImasText の BODY) のまま。吹き出しにしない。
//           検索 → ImasSearchField
// 構成      紙片: 右に寄せた角丸の四角 (地は surface2)。色を付けない。
//           入力欄: [複数行の欄] [送る (墨の四角に ↑)]。上に区切り線。
// 状態      送る: 通常 / 無効 (薄く)
// =============================================================================

/** 利用者の発言。右に寄せた紙片。 */
@Composable
fun ImasChatBubble(text: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().padding(start = DS.Space.section), contentAlignment = Alignment.CenterEnd) {
        ImasText(
            text,
            role = ImasTextRole.BODY,
            modifier = Modifier
                .background(DS.surface2, RoundedCornerShape(12.dp))
                .padding(horizontal = DS.Space.card, vertical = DS.Space.gap),
        )
    }
}

/** 画面の下に据える入力欄と送るボタン。Enter は改行で、送るのは右のボタンだけ。 */
@Composable
fun ImasChatComposer(
    prompt: String,
    text: String,
    onTextChange: (String) -> Unit,
    canSend: Boolean,
    onSend: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().background(DS.paper)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(DS.line))
        Row(
            Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        ) {
            Box(
                Modifier
                    .weight(1f)
                    .background(DS.surface, RoundedCornerShape(12.dp))
                    .border(BorderStroke(1.dp, DS.line), RoundedCornerShape(12.dp))
                    .padding(horizontal = DS.Space.card, vertical = DS.Space.gap),
            ) {
                if (text.isEmpty()) ImasText(prompt, role = ImasTextRole.NOTE)
                BasicTextField(
                    value = text,
                    onValueChange = onTextChange,
                    modifier = Modifier.fillMaxWidth(),
                    textStyle = ImasTextRole.BODY.style.copy(color = DS.ink),
                    cursorBrush = SolidColor(DS.sys),
                    maxLines = 5,
                )
            }
            Box(
                Modifier
                    .size(40.dp)
                    .alpha(if (canSend) 1f else 0.35f)
                    .background(DS.sys, RoundedCornerShape(10.dp))
                    .semantics { contentDescription = "送る" }
                    .clickable(enabled = canSend, onClick = onSend),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.ArrowUpward, contentDescription = null, tint = DS.onSys)
            }
        }
    }
}
