package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS

// 画面の上に浮かぶ小窓 (参考動画の PiP) の枠と、バーのつまみ。iOS `ImasFloatingWindow.swift` と同じ。

/** 画面の上に浮かぶ小窓の枠。紙の面・角丸・細い縁 (影や光は付けない)。 */
@Composable
fun Modifier.imasFloatingWindow(): Modifier {
    val shape = RoundedCornerShape(DS.rSM)
    return this.clip(shape).background(DS.surface).border(1.dp, DS.line, shape)
}

/** 動画の場所 (16:9・角丸) に収める。サムネと同じ角。 */
fun Modifier.imasVideoFrame(): Modifier = this.aspectRatio(16f / 9f).clip(RoundedCornerShape(DS.rXS))

/** 小窓のバーの左端に置く、つまんで動かせることを示す印。 */
@Composable
fun ImasWindowGrip() {
    Box(Modifier.size(width = 4.dp, height = 18.dp).clip(RoundedCornerShape(2.dp)).background(DS.ink3))
}
