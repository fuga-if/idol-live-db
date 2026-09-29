package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.PerformerDisplayName

/**
 * 歌唱者 1 人のカプセル chip (色ドット + 主の名前 + あれば副の名前)。
 * iOS `PerformerChip` と 1:1。
 *
 * **どちらの名前を出すかはここで決めない。** 解決済みの [name] を受け取るだけで、
 * 規則は imas-core の `performerDisplayName` が持つ。
 *
 * @param name          解決済みの表示名 (主と、あれば副)
 * @param idolColorHex  色ドットの hex (null 可)
 */
@Composable
fun PerformerChip(
    name: PerformerDisplayName,
    idolColorHex: String? = null,
    modifier: Modifier = Modifier
) {
    Surface(
        shape = CircleShape,
        color = DS.surface2,
        modifier = modifier
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 3.dp)
        ) {
            ColorDot(hexColor = idolColorHex, size = 6.dp)

            Spacer(modifier = Modifier.width(4.dp))

            Column {
                Text(
                    text = name.primary,
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1
                )
                name.secondary?.let { sub ->
                    Text(
                        text = sub,
                        style = MaterialTheme.typography.labelSmall.copy(fontSize = 8.sp),
                        color = DS.ink2,
                        maxLines = 1
                    )
                }
            }
        }
    }
}
