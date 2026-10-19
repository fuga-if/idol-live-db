package com.fugaif.imaslivedb.ui.stats

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.repository.CommunityRanking
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasRankingRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.CommunityRankingKind

/** 順位表の種類の並び (切り替えの左から)。 */
val CommunityRankingKinds: List<CommunityRankingKind> = listOf(
    CommunityRankingKind.POPULAR,
    CommunityRankingKind.TRENDING,
    CommunityRankingKind.FAVORITES,
    CommunityRankingKind.PREVIEW,
    CommunityRankingKind.FULL
)

private fun CommunityRankingKind.label(): String = when (this) {
    CommunityRankingKind.POPULAR -> "人気"
    CommunityRankingKind.TRENDING -> "急上昇"
    CommunityRankingKind.FAVORITES -> "お気に入り"
    CommunityRankingKind.PREVIEW -> "試聴"
    CommunityRankingKind.FULL -> "フル再生"
}

/** 数の単位。人気は点、お気に入りは ♥、それ以外は回 (急上昇は行の補足に「今週」)。 */
private fun CommunityRankingKind.unit(): String = when (this) {
    CommunityRankingKind.POPULAR -> "pt"
    CommunityRankingKind.FAVORITES -> "♥"
    else -> "回"
}

/** 再生回数に関わる順位表か (「○年○月○日から集計」を添える)。 */
private fun CommunityRankingKind.countsPlays(): Boolean = this != CommunityRankingKind.FAVORITES

/** "2026-10-18" → "2026年10月18日から集計"。読めなければ null。 */
private fun playsSinceLabel(raw: String): String? {
    val c = raw.split("-")
    if (c.size < 3) return null
    val y = c[0].toIntOrNull() ?: return null
    val m = c[1].toIntOrNull() ?: return null
    val d = c[2].toIntOrNull() ?: return null
    return "${y}年${m}月${d}日から集計"
}

/**
 * みんなの順位表 (種類の切り替え + ブランドの絞り込み + 行)。統計画面の上位 10 件と、
 * [CommunityRankingScreen] の上位 100 件が同じ部品を使う。
 *
 * @param ranking null は集計を取れなかったとき。
 */
@Composable
fun CommunityRankingSection(
    title: String,
    kind: CommunityRankingKind,
    onKindChange: (CommunityRankingKind) -> Unit,
    brands: List<Brand>,
    selectedBrandId: String?,
    onBrandSelected: (String?) -> Unit,
    ranking: CommunityRanking?,
    isLoading: Boolean,
    onSongClick: (String) -> Unit,
    seeAll: (() -> Unit)? = null,
    style: ImasSectionHeaderStyle = ImasSectionHeaderStyle.SMALL
) {
    val footer = if (kind.countsPlays() && ranking != null && ranking.items.isNotEmpty()) {
        playsSinceLabel(ranking.playsSince)
    } else {
        null
    }
    ImasSection(title, style = style, footer = footer, seeAll = if (ranking?.items.isNullOrEmpty()) null else seeAll) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            ImasTabs(
                labels = CommunityRankingKinds.map { it.label() },
                selection = CommunityRankingKinds.indexOf(kind),
                onSelect = { onKindChange(CommunityRankingKinds[it]) }
            )
            BrandFilterChips(
                brands = brands.map { BrandFilterItem(it.id, it.shortName) },
                selectedBrandId = selectedBrandId,
                onBrandSelected = onBrandSelected
            )
            when {
                isLoading -> ImasInlineLoading()
                ranking == null || ranking.items.isEmpty() -> ImasCard {
                    ImasEmptyState(
                        icon = Icons.Filled.Favorite,
                        title = "まだデータがありません",
                        message = if (ranking == null) {
                            "ランキングを取得できませんでした。通信を確かめてもう一度開いてください。"
                        } else {
                            "お気に入りや再生が増えるとここにランキングが表示されます。"
                        }
                    )
                }
                else -> ImasCardList(items = ranking.items, key = { it.songId }) { item ->
                    ImasRankingRow(
                        rank = item.rank,
                        title = item.title,
                        metric = "%,d".format(item.value),
                        unit = kind.unit(),
                        sub = if (kind == CommunityRankingKind.TRENDING) "今週" else null,
                        brand = item.brandId,
                        onClick = { onSongClick(item.songId) }
                    ) {
                        ImasArtwork(title = item.title, brand = item.brandId, size = 44.dp, imageUrl = item.artworkUrl)
                    }
                }
            }
        }
    }
}

/** 順位表の全体 (上位 100 件)。統計画面の「すべて見る」から。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommunityRankingScreen(
    onBack: () -> Unit,
    onSongClick: (String) -> Unit,
    viewModel: CommunityRankingViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("みんなの曲ランキング") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                }
            )
        }
    ) { padding ->
        ImasPage(modifier = Modifier.padding(padding)) {
            CommunityRankingSection(
                title = "曲のランキング",
                kind = state.kind,
                onKindChange = viewModel::selectKind,
                brands = state.brands,
                selectedBrandId = state.brandId,
                onBrandSelected = viewModel::selectBrand,
                ranking = state.ranking,
                isLoading = state.isLoading,
                onSongClick = onSongClick
            )
        }
    }
}
