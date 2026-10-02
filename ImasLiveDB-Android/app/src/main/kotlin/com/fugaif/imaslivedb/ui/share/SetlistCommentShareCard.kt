package com.fugaif.imaslivedb.ui.share

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

// =============================================================================
// 機能 3: セトリコメントカード
// セトリの曲に感想を書いて「曲名 + コメント + 装飾」のカード画像を生成する。
// コメントはシェア用途のみのローカル入力で、サーバーには保存しない。
// iOS ImasLiveDB/Views/Share/SetlistCommentShareCard.swift の移植。
// =============================================================================

/**
 * セトリコメントカード本体。
 * ジャケ写を上に敷き、下パネルに感想の短い引用 + 曲名 (主役) + 小さな公演/日付を白基調で置く。
 * 余白を贅沢に取り、装飾はメンバーカラーの短い罫線 1 本だけのミニマル構成。
 */
@Composable
fun SetlistCommentShareCard(
    songTitle: String,
    showName: String?,
    showDate: String?,
    comment: String,
    seed: String?,
    artwork: ImageBitmap?,
    size: ShareCardSize
) {
    val palette = rememberShareCardPalette(seed)
    val meta = listOfNotNull(showName, showDate).filter { it.isNotEmpty() }.joinToString("  ·  ")

    PhotoShareScaffold(artwork = artwork, palette = palette, size = size) {
        ShareEyebrow(text = "セトリの感想", accent = palette.accent, ink = ShareInk.ink.copy(alpha = 0.82f))

        // 感想を短い引用として (明朝・大きめ、編集的)。
        Text(
            comment,
            fontSize = 23.sp,
            fontFamily = FontFamily.Serif,
            color = ShareInk.ink,
            lineHeight = 30.sp,
            maxLines = 4,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 14.dp)
        )

        // 曲名 (主役) + 小さな公演/日付メタ。継ぎ目に短い罫線。
        Box(
            Modifier
                .padding(top = 18.dp)
                .width(28.dp)
                .height(2.dp)
                .background(palette.accent)
        )

        Text(
            songTitle,
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Serif,
            color = ShareInk.ink,
            lineHeight = 32.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 12.dp)
        )

        if (meta.isNotEmpty()) {
            Text(
                meta,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = 0.5.sp,
                color = ShareInk.ink.copy(alpha = 0.6f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 5.dp)
            )
        }
    }
}

/**
 * 感想入力 + ライブプレビュー + シェアのシート。セトリ曲行の長押しから開く。
 *
 * プレビューはレンダリング済み画像ではなく実カードを縮小表示しているので、
 * 入力中の文字がそのまま反映される (出力とプレビューが必ず一致する)。
 */
@Composable
fun SetlistCommentComposeSheet(
    songTitle: String,
    showName: String?,
    showDate: String?,
    seed: String?,
    artworkUrl: String?,
    onDismiss: () -> Unit
) {
    var comment by remember { mutableStateOf("") }
    val artwork = rememberShareArtwork(artworkUrl)

    // 未入力時はプレースホルダで完成形を見せる (空のカードを見せない)。
    val displayComment = comment.trim().ifEmpty { "ここに感想が入ります" }

    ShareCardSheet(title = "感想カードを作る", onDismiss = onDismiss) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            ImasText("この曲の感想", role = ImasTextRole.SECTION_LABEL, color = DS.ink3)
            ImasCard {
                CommentField(
                    text = comment,
                    onTextChange = { comment = it },
                    prompt = "最高だった！ 泣いた…など"
                )
            }
        }

        ShareCardActionPane(
            isPreparingCard = artwork.isPreparing,
            fileNamePrefix = "setlist_comment"
        ) { size ->
            SetlistCommentShareCard(
                songTitle = songTitle,
                showName = showName,
                showDate = showDate,
                comment = displayComment,
                seed = seed,
                artwork = artwork.image,
                size = size
            )
        }
    }
}

/**
 * 感想の自由入力 (飾りの無い複数行欄)。[ImasCard] の中に置くので枠は持たず、
 * 空のときだけ誘いの文を薄灰で出す (iOS の `TextField(_:text:axis:.vertical)` と同じ、枠なしの地)。
 */
@Composable
private fun CommentField(text: String, onTextChange: (String) -> Unit, prompt: String) {
    Box {
        if (text.isEmpty()) {
            // 読み上げは欄の名前として読ませる (誘いの文を欄と切り離された別の文として読ませない)。
            Text(prompt, style = ImasTextRole.BODY.style, color = DS.ink3, modifier = Modifier.clearAndSetSemantics {})
        }
        BasicTextField(
            value = text,
            onValueChange = onTextChange,
            textStyle = ImasTextRole.BODY.style.copy(color = DS.ink),
            cursorBrush = SolidColor(DS.ink),
            minLines = 3,
            maxLines = 6,
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = prompt }
        )
    }
}
