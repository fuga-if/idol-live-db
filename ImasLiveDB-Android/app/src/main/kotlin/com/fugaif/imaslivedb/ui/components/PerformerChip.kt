package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.penlight
import uniffi.imas_core.PerformerDisplayName

/**
 * 歌唱者 1 人 (ペンライト + 主の名前 + あれば副の名前)。見た目は DS の `ImasPerformerChip` と同じ
 * (淡い色のカプセルは敷かず、色はペンライトにだけ出す)。主と副の 2 段を持つのが DS との違い。
 *
 * **どちらの名前を出すかはここで決めない。** 解決済みの [name] を受け取るだけで、
 * 規則は imas-core の `performerDisplayName` が持つ。
 *
 * @param name          解決済みの表示名 (主と、あれば副)
 * @param idolColorHex  ペンライトの色 hex (null なら薄い墨)
 */
@Composable
fun PerformerChip(
    name: PerformerDisplayName,
    idolColorHex: String? = null,
    modifier: Modifier = Modifier
) {
    val penlight = if (idolColorHex == null) DS.ink3 else imasThemeForBrand(idolColorHex, null).penlight
    Row(
        modifier.semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasPenlight(color = penlight, size = ImasPenlightSize.SMALL)
        Column {
            Text(text = name.primary, style = ImasType.text(13.sp), color = DS.ink2, maxLines = 1)
            name.secondary?.let { sub ->
                Text(text = sub, style = ImasType.text(10.sp), color = DS.ink3, maxLines = 1)
            }
        }
    }
}
