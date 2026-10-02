package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.model.AlbumSummary
import com.fugaif.imaslivedb.data.model.SeriesSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasArtworkCell
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasPress

/**
 * 曲一覧の「アルバム」表示 (iOS `AlbumGridView`)。CD シリーズ単位のカードを並べる。
 * カードを押すと曲一覧へ戻り、その CD シリーズで絞り込む。
 */
@Composable
fun AlbumGrid(albums: List<AlbumSummary>, onSelect: (AlbumSummary) -> Unit) {
    if (albums.isEmpty()) {
        ImasEmptyState(icon = Icons.Filled.LibraryMusic, title = "アルバムが見つかりません")
        return
    }
    SummaryGrid(items = albums, key = { it.cdSeries }) { album ->
        ImasArtworkCell(
            title = album.cdSeries,
            subtitle = listOfNotNull("${album.songCount}曲", album.yearDisplay).joinToString(" / "),
            brand = album.brandIds.firstOrNull(),
            imageUrl = album.artworkUrl,
            modifier = Modifier.imasPress { onSelect(album) }
        )
    }
}

/**
 * 曲一覧の「シリーズ」表示 (iOS `SeriesGridView`)。series_group 単位のカードを並べる。
 */
@Composable
fun SeriesGrid(series: List<SeriesSummary>, onSelect: (SeriesSummary) -> Unit) {
    if (series.isEmpty()) {
        ImasEmptyState(icon = Icons.Filled.LibraryMusic, title = "シリーズが見つかりません")
        return
    }
    SummaryGrid(items = series, key = { it.name }) { s ->
        ImasArtworkCell(
            title = s.name,
            subtitle = listOfNotNull("${s.cdCount}枚 / ${s.songCount}曲", s.yearDisplay).joinToString(" · "),
            brand = s.brandIds.firstOrNull(),
            imageUrl = s.artworkUrl,
            modifier = Modifier.imasPress { onSelect(s) }
        )
    }
}

@Composable
private fun <T> SummaryGrid(
    items: List<T>,
    key: (T) -> String,
    card: @Composable (T) -> Unit
) {
    LazyVerticalGrid(
        // カード幅を固定列数でなく最小幅で決める。端末幅と文字サイズで 2〜3 列に落ち着く。
        columns = GridCells.Adaptive(minSize = 150.dp),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(DS.Space.screen),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
        verticalArrangement = Arrangement.spacedBy(DS.Space.screen)
    ) {
        items(items, key = key) { card(it) }
    }
}
