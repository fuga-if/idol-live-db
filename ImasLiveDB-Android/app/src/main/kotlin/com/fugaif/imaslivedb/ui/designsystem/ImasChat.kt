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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import android.graphics.Bitmap
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

// =============================================================================
// チャット (docs/DESIGN_SYSTEM.md §9)。iOS `ImasChat.swift` と対。
//
// 用途      会話の画面。利用者の発言の紙片、考えている途中の一行、画面の下に据える入力欄。
// 使わない  相手の返事 → 地の文 (ImasText の BODY) のまま。吹き出しにしない。
//           検索 → ImasSearchField
// 構成      紙片: 右に寄せた角丸の四角 (地は surface2)。色を付けない。画像は字の上に小さく並べる。
//           途中: [くるくる] [何をしているかの一言] を 1 行で。止めるのは入力欄のボタン。
//           入力欄: [添える (+)] [複数行の欄] [送る ↑ / 止める ■]。上に区切り線。
//                   添えた画像は欄の上に小さく並び、× で外せる。
// 状態      送る: 通常 / 無効 (薄く) / 考えている途中 (■ に替わり、押すと止まる)
// =============================================================================

/** 利用者の発言。右に寄せた紙片。 */
@Composable
fun ImasChatBubble(text: String, modifier: Modifier = Modifier, images: List<Bitmap> = emptyList()) {
    Column(
        modifier.fillMaxWidth().padding(start = DS.Space.section),
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
    ) {
        if (images.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                images.forEach { ImasChatThumbnail(it, side = 72.dp) }
            }
        }
        if (text.isNotEmpty()) {
            ImasText(
                text,
                role = ImasTextRole.BODY,
                modifier = Modifier
                    .background(DS.surface2, RoundedCornerShape(12.dp))
                    .padding(horizontal = DS.Space.card, vertical = DS.Space.gap),
            )
        }
    }
}

/** 相手の返事。地の文で、中の http/https の URL は下線つきで押せる (Web や X の出どころ)。 */
@Composable
fun ImasChatReply(text: String, modifier: Modifier = Modifier) {
    val linked = remember(text) {
        buildAnnotatedString {
            append(text)
            URL_PATTERN.findAll(text).forEach { match ->
                // 文末の句読点・閉じ括弧は URL に含めない。
                val url = match.value.trimEnd('.', ',', ')', '）', '。', '、', '」')
                addLink(
                    LinkAnnotation.Url(url, TextLinkStyles(SpanStyle(textDecoration = TextDecoration.Underline))),
                    match.range.first,
                    match.range.first + url.length,
                )
            }
        }
    }
    Text(linked, modifier = modifier, color = ImasTextRole.BODY.color, style = ImasTextRole.BODY.style)
}

private val URL_PATTERN = Regex("""https?://[\x21-\x7E]+""")

/** 考えている途中の一行。 */
@Composable
fun ImasChatThinking(label: String, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
    ) {
        CircularProgressIndicator(Modifier.size(16.dp), color = DS.ink3, strokeWidth = 2.dp)
        ImasText(label, role = ImasTextRole.NOTE, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** 添えた画像の小さな写し。[onRemove] が null なら × を出さない (送ったあとの紙片)。 */
@Composable
fun ImasChatThumbnail(
    image: Bitmap,
    modifier: Modifier = Modifier,
    side: androidx.compose.ui.unit.Dp = 56.dp,
    onRemove: (() -> Unit)? = null,
) {
    Box(modifier.size(side)) {
        Image(
            bitmap = image.asImageBitmap(),
            contentDescription = "添えた画像",
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(side)
                .clip(RoundedCornerShape(8.dp))
                .border(BorderStroke(1.dp, DS.line), RoundedCornerShape(8.dp)),
        )
        if (onRemove != null) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = 6.dp, y = (-6).dp)
                    .size(20.dp)
                    .background(DS.sys, CircleShape)
                    .semantics { contentDescription = "画像を外す" }
                    .clickable(onClick = onRemove),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, contentDescription = null, tint = DS.onSys, modifier = Modifier.size(12.dp))
            }
        }
    }
}

/** [ImasChatAccessoryMenu] の 1 項目。 */
class ImasChatAccessoryItem(val title: String, val onClick: () -> Unit)

/** 入力欄の左に置く、記号だけの四角いボタン。押すと項目のメニューが開く (画像を添える)。 */
@Composable
fun ImasChatAccessoryMenu(
    items: List<ImasChatAccessoryItem>,
    contentDescription: String = "画像を添える",
    enabled: Boolean = true,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier
                .size(40.dp)
                .alpha(if (enabled) 1f else 0.35f)
                .border(BorderStroke(1.dp, DS.line), RoundedCornerShape(10.dp))
                .semantics { this.contentDescription = contentDescription }
                .clickable(enabled = enabled) { open = true },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = DS.ink)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            items.forEach { item ->
                DropdownMenuItem(
                    text = { ImasText(item.title, role = ImasTextRole.BODY) },
                    onClick = { open = false; item.onClick() },
                )
            }
        }
    }
}

/**
 * 画面の下に据える入力欄と送るボタン。Enter は改行で、送るのは右のボタンだけ。
 *
 * [accessory] は欄の左に置く小物 (画像を添えるメニューなど)。考えている途中 ([isRunning]) は
 * 送るボタンが「止める」に替わる。
 */
@Composable
fun ImasChatComposer(
    prompt: String,
    text: String,
    onTextChange: (String) -> Unit,
    canSend: Boolean,
    onSend: () -> Unit,
    attachments: List<Bitmap> = emptyList(),
    onRemoveAttachment: (Int) -> Unit = {},
    isRunning: Boolean = false,
    onStop: () -> Unit = {},
    accessory: @Composable () -> Unit = {},
) {
    val focus = LocalFocusManager.current
    Column(Modifier.fillMaxWidth().background(DS.paper)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(DS.line))
        if (attachments.isNotEmpty()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen).padding(top = DS.Space.gap + DS.Space.gapTight),
                horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
            ) {
                attachments.forEachIndexed { index, image ->
                    ImasChatThumbnail(image, onRemove = { onRemoveAttachment(index) })
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        ) {
            accessory()
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
            val enabled = isRunning || canSend
            Box(
                Modifier
                    .size(40.dp)
                    .alpha(if (enabled) 1f else 0.35f)
                    .background(DS.sys, RoundedCornerShape(10.dp))
                    .semantics { contentDescription = if (isRunning) "止める" else "送る" }
                    .clickable(enabled = enabled) {
                        if (isRunning) {
                            onStop()
                        } else {
                            // 送ったら返事が見えるようにキーボードを下げる。
                            focus.clearFocus()
                            onSend()
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                Icon(if (isRunning) Icons.Filled.Stop else Icons.Filled.ArrowUpward, contentDescription = null, tint = DS.onSys)
            }
        }
    }
}
