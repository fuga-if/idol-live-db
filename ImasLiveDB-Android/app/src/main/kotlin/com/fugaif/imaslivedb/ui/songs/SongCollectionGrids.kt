package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.AlbumSummary
import com.fugaif.imaslivedb.data.model.SeriesSummary
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS

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
        SummaryCard(
            title = album.cdSeries,
            subtitle = listOfNotNull("${album.songCount}曲", album.displayYear).joinToString(" / "),
            artworkUrl = album.artworkUrl,
            brandId = album.brandIds.firstOrNull(),
            onClick = { onSelect(album) }
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
        SummaryCard(
            title = s.name,
            subtitle = listOfNotNull("${s.cdCount}枚 / ${s.songCount}曲", s.yearRange).joinToString(" · "),
            artworkUrl = s.artworkUrl,
            brandId = s.brandIds.firstOrNull(),
            onClick = { onSelect(s) }
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
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        items(items, key = key) { card(it) }
    }
}

/** ジャケット + 名前 + 副題のカード 1 枚 (iOS `GridCardView` 相当)。 */
@Composable
private fun SummaryCard(
    title: String,
    subtitle: String,
    artworkUrl: String?,
    brandId: String?,
    onClick: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        horizontalAlignment = Alignment.Start
    ) {
        // ImasArtwork は Dp 指定の正方形しか描けない。列幅は端末幅で変わるので、
        // 実測した幅をそのまま辺の長さとして渡してカードいっぱいに敷く。
        BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
            ImasArtwork(
                title = title,
                brand = brandId,
                size = maxWidth,
                imageUrl = artworkUrl
            )
        }
        Text(
            text = title,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = DS.ink,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 6.dp)
        )
        Text(text = subtitle, fontSize = 11.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
