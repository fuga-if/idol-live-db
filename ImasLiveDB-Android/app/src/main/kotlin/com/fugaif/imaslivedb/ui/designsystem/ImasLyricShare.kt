package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Share
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.share.SocialShare
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import kotlinx.coroutines.delay

// =============================================================================
// 歌詞の一部の共有 (公開サイトの曲ページの `#lyric-…` へのリンク)。iOS `ImasLyricShare.swift` の移植。
//
// 用途      歌詞タブで行を長押しして選んだ範囲の塗りと、画面の下に浮かぶ帯。
//           帯から渡すのは **URL だけ**。歌詞の本文は共有にもコピーにも乗せない
//           (JASRAC 許諾の条件。SongLyricsTab の ⚠️ と同じ)。
// 構成      選んだ行 … 字の下に曲の色 (ソロは担当色、ほかはブランド色) の平らな面 + 下端の線。
//                      公開サイトの塗り (`.lyrics__mark`) と同じ見え方。
//           帯 … 左に曲の色の縦帯、「12〜14行目 / この部分へのリンク」、共有・コピー・× の記号。
//                平らな面 + 枠線 (iOS 26 だけ Liquid Glass。Android は平らなまま)。
//
// 光らせない・ぼかさない (グラデーション・光は禁止)。色は曲の配色だけ。
// =============================================================================

/** 共有のために選んだ歌詞の行の塗り。 */
@Composable
fun Modifier.imasLyricSharePicked(isPicked: Boolean, seed: String?, brand: String?): Modifier {
    val accent = imasThemeForBrand(seed, brand).accent
    // 面は Web と同じ濃さ (24%)。下端の線で「ここを選んだ」をくっきり示す。
    val fill by animateColorAsState(if (isPicked) accent.copy(alpha = 0.24f) else Color.Transparent, label = "lyricSharePicked")
    val line by animateColorAsState(if (isPicked) accent else Color.Transparent, label = "lyricSharePickedLine")
    val shape = RoundedCornerShape(DS.rTag)
    return this
        .semantics { selected = isPicked }
        .clip(shape)
        .background(fill)
        .drawBehindUnderline(line)
}

private fun Modifier.drawBehindUnderline(color: Color): Modifier = drawBehind {
    if (color.alpha == 0f) return@drawBehind
    val h = 2.dp.toPx()
    drawRect(color, topLeft = Offset(0f, size.height - h), size = Size(size.width, h))
}

/**
 * 選んだ歌詞へのリンクを渡す帯。画面の下に浮かべる。
 *
 * 渡すのは [url] だけ。共有 (標準シェアシート) もコピーも URL しか持たない。
 *
 * @param linesLabel 「12行目」「12〜14行目」(コアの `shareLyricLinesLabel`)。
 * @param note 下段の一言 (「この部分へのリンク」/ 広げ方の案内)。コピーした直後だけ「コピーしました」に替わる。
 */
@Composable
fun ImasLyricShareBar(
    linesLabel: String,
    url: String,
    seed: String?,
    brand: String?,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    note: String = "この部分へのリンク",
) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    val view = LocalView.current
    val accent = imasThemeForBrand(seed, brand).accent
    var copiedToken by remember { mutableIntStateOf(0) }
    var showsCopied by remember { mutableStateOf(false) }
    LaunchedEffect(copiedToken) {
        if (copiedToken == 0) return@LaunchedEffect
        showsCopied = true
        delay(2_000)
        showsCopied = false
    }
    val shape = RoundedCornerShape(DS.rCard)
    Row(
        modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clip(shape)
            .background(DS.surface)
            .border(1.dp, DS.sep, shape)
            .padding(start = DS.sp4, end = DS.sp2, top = DS.sp3, bottom = DS.sp3)
            .semantics { paneTitle = "選んだ歌詞の共有" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.sp3),
    ) {
        Box(
            Modifier
                .padding(vertical = DS.sp1)
                .width(4.dp)
                .fillMaxHeight()
                .clip(RoundedCornerShape(DS.rTag))
                .background(accent)
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
            ImasText(linesLabel, ImasTextRole.ROW_TITLE)
            AnimatedContent(targetState = if (showsCopied) "リンクをコピーしました" else note, label = "lyricShareNote") {
                ImasText(it, ImasTextRole.META, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            }
        }
        ImasIconButton(
            icon = Icons.Filled.Share, label = "この部分へのリンクを共有",
            style = ImasIconButtonStyle.FILLED,
            onClick = { SocialShare.shareText(context, url) },
        )
        ImasIconButton(
            icon = if (showsCopied) Icons.Filled.Check else Icons.Filled.ContentCopy,
            label = "この部分へのリンクをコピー",
            onClick = {
                // URL だけを載せる (本文は載せない)。
                clipboard.setText(AnnotatedString(url))
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                view.announceForAccessibility("リンクをコピーしました")
                copiedToken++
            },
        )
        ImasIconButton(
            icon = Icons.Filled.Close, label = "選択を解除",
            size = ImasIconButtonSize.SMALL, style = ImasIconButtonStyle.PLAIN,
            onClick = onClose,
        )
    }
}
