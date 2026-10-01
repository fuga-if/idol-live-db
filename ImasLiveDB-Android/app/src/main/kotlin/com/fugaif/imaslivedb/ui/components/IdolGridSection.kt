package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolGrid
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasPress

/**
 * アイドルを名札の格子で並べるセクション (iOS `IdolGridSection`)。見た目は `ImasIdolCell` (DS §6.6)。
 *
 * 楽曲詳細の「歌唱アイドル」(オリジナル歌唱) と「ライブ歌唱歴」(実演者)、アイドル詳細の
 * 「タグが似ているアイドル」が同じ見た目。
 *
 * @param badge idolId -> 共有タグ数。渡すと名札の下段に「タグN個一致」を出す (metric の枠を借りる)。
 */
@Composable
fun IdolGridSection(
    title: String,
    idols: List<Idol>,
    onIdolClick: (String) -> Unit,
    badge: Map<String, Int>? = null
) {
    Column {
        ImasSectionHeader(title, count = "${idols.size}")
        ImasIdolGrid(Modifier.padding(horizontal = DS.Space.screen), columns = 4) {
            idols.forEach { idol ->
                ImasIdolCell(
                    idol = idol,
                    isPick = false,
                    metric = badge?.get(idol.id)?.let { "タグ${it}個一致" },
                    modifier = Modifier.imasPress { onIdolClick(idol.id) }
                )
            }
        }
    }
}
