package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

// MARK: - 図解の部品 (よその画面の見立て)。iOS `ImasHowToMock.swift`。

/**
 * 手順の図に置く、よその Web 画面の見立て (Spotify の開発者サイトなど)。上に URL、下に中身。
 * 本物の見た目は写さず、紙の窓に「どこを押すか」だけを描く。読み上げからは隠す (手順の文が同じことを言う)。
 */
@Composable
fun ImasMockBrowser(url: String, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    ImasCard(modifier = modifier.clearAndSetSemantics {}, style = ImasCardStyle.INSET) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                Icon(Icons.Filled.Lock, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(12.dp))
                Text(
                    url,
                    style = ImasTextRole.META.style.copy(fontFamily = FontFamily.Monospace),
                    color = DS.ink3,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            content()
        }
    }
}

/** 見立ての中のボタン。押す所 ([isTarget]) は墨で塗る (主ボタンと同じ見え方で「ここを押す」と読ませる)。 */
@Composable
fun ImasMockButton(title: String, isTarget: Boolean = false) {
    Text(
        title,
        style = ImasTextRole.CHIP.style,
        color = if (isTarget) DS.onSys else DS.ink,
        modifier = Modifier
            .background(if (isTarget) DS.sys else DS.fill, RoundedCornerShape(DS.rControl(32.dp)))
            .padding(horizontal = DS.Space.rowGap, vertical = DS.Space.gap),
    )
}

/** 見立ての中の入力欄・値の欄。触る所には「ここ」の札、使わない欄は薄く「使わない」の札。 */
@Composable
fun ImasMockField(label: String, value: String, isTarget: Boolean = false, isUnused: Boolean = false) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            Text(label, style = ImasTextRole.META.style, color = ImasTextRole.META.color)
            if (isTarget) ImasBadge("ここ", kind = ImasBadgeKind.LEAD)
            if (isUnused) ImasBadge("使わない", kind = ImasBadgeKind.NEUTRAL)
        }
        Text(
            value,
            style = ImasTextRole.VALUE.style.copy(fontFamily = FontFamily.Monospace),
            color = if (isUnused) DS.ink3 else DS.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .background(DS.fill, RoundedCornerShape(DS.rXS))
                .padding(DS.Space.gap),
        )
    }
}

/** 見立ての中のチェック欄。入れる所には「ここ」の札。 */
@Composable
fun ImasMockCheck(label: String, isChecked: Boolean = false) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        Icon(
            if (isChecked) Icons.Filled.CheckBox else Icons.Filled.CheckBoxOutlineBlank,
            contentDescription = null,
            tint = if (isChecked) DS.ink else DS.ink3,
        )
        Text(label, style = ImasTextRole.VALUE.style, color = if (isChecked) DS.ink else DS.ink3)
        if (isChecked) ImasBadge("ここ", kind = ImasBadgeKind.LEAD)
    }
}
