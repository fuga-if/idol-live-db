package com.fugaif.imaslivedb.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.ui.designsystem.ImasPerformerChip
import uniffi.imas_core.PerformerDisplayName

/**
 * 歌唱者 1 人から組む (iOS `ImasPerformerChip(name:)` の、主副 2 段の表示名を受ける版)。
 * 見た目は DS の [ImasPerformerChip] そのもの ([ImasPerformerChip.secondary] で副の名前を添える)。
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
    ImasPerformerChip(
        name = name.primary,
        modifier = modifier,
        seed = idolColorHex,
        secondary = name.secondary
    )
}
