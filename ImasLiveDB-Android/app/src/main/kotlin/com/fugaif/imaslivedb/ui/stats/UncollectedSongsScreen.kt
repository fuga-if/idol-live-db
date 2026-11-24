package com.fugaif.imaslivedb.ui.stats

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasBoard
import com.fugaif.imaslivedb.ui.designsystem.ImasBoardCell
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasDisclosureRow
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasFullScreenDialog
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.LocalImasRowPosition
import com.fugaif.imaslivedb.ui.events.SetlistScreen
import com.fugaif.imaslivedb.ui.songs.SongDetailScreen
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import uniffi.imas_core.CollectionScope
import uniffi.imas_core.PlayFrequency
import uniffi.imas_core.SongDetailRecord
import uniffi.imas_core.songCreditLabel
import uniffi.imas_core.UncollectedListRecord
import uniffi.imas_core.UncollectedSongRecord

/** 未回収一覧が見る範囲 (iOS `UncollectedSongsView.Scope`)。 */
sealed interface UncollectedListScope {
    data object All : UncollectedListScope
    data class Brand(val id: String, val name: String, val color: String?) : UncollectedListScope
    data object MyPick : UncollectedListScope
}

/**
 * 未回収曲の一覧 (回収ダッシュボードのブランド別の回収率のバー・「すべて見る」の先)。
 * iOS Views/Stats/UncollectedSongsView.swift の移植。
 *
 * 数え方は原曲単位 (コア `uncollectedSongs`)。いま回収できる曲 (披露済み) と、まだ披露されていない曲を
 * 分けて並べ、ver 違いは原曲の行の下にたたむ。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UncollectedSongsScreen(scope: UncollectedListScope, onBack: () -> Unit) {
    val context = LocalContext.current
    val module = remember(context) { AppModule.from(context) }
    var list by remember { mutableStateOf<UncollectedListRecord?>(null) }
    var failed by remember { mutableStateOf(false) }
    var brands by remember { mutableStateOf<List<Brand>>(emptyList()) }
    var expanded by rememberSaveable { mutableStateOf(setOf<String>()) }
    var selectedSongId by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedShowId by rememberSaveable { mutableStateOf<String?>(null) }

    LaunchedEffect(scope) {
        runCatching {
            brands = module.statsRepository.fetchBrands()
            val coreScope = when (scope) {
                UncollectedListScope.All -> CollectionScope.All
                is UncollectedListScope.Brand -> CollectionScope.Brand(scope.id)
                UncollectedListScope.MyPick -> CollectionScope.MyPick(module.userMarkRepository.pickedIdolIdList())
            }
            module.statsRepository.fetchUncollectedSongs(module.songRepository.fetchCollectedSongIds(), coreScope)
        }.onSuccess { list = it; failed = false }.onFailure { failed = true }
    }

    val name = when (scope) {
        UncollectedListScope.All -> "全ブランド"
        is UncollectedListScope.Brand -> scope.name
        UncollectedListScope.MyPick -> "担当のオリ曲"
    }
    val title = list?.let { "${name}の未回収 ${it.performed.size + it.unperformed.size}曲" } ?: "${name}の未回収"

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                }
            )
        }
    ) { padding ->
        ImasPage(modifier = Modifier.padding(padding)) {
            val current = list
            when {
                current != null -> {
                    Summary(current)
                    if (current.performed.isEmpty() && current.unperformed.isEmpty()) {
                        ImasCard {
                            ImasEmptyState(
                                icon = Icons.Filled.CheckCircle,
                                title = "コンプリート！",
                                message = "ここにある曲はすべて生で聴けています。"
                            )
                        }
                    }
                    val toggle = { id: String -> expanded = if (id in expanded) expanded - id else expanded + id }
                    // ブランドで絞った一覧は歌唱者 (表記の規則はコア)、それ以外はブランド名 (iOS と同じ)。
                    val subtitle = { song: UncollectedSongRecord ->
                        val brandName = if (scope is UncollectedListScope.Brand) null
                        else brands.firstOrNull { it.id == song.song.brandId }?.shortName
                        brandName ?: creditLine(song.song)
                    }
                    if (current.performed.isNotEmpty()) {
                        ImasSection(
                            "回収できる曲",
                            count = "${current.performed.size}曲",
                            style = ImasSectionHeaderStyle.SMALL,
                            footer = "ライブで披露されたことのある曲です。披露の多い順。"
                        ) {
                            UncollectedSongList(current.performed, expanded, toggle, subtitle) { selectedSongId = it }
                        }
                    }
                    if (current.unperformed.isNotEmpty()) {
                        ImasSection(
                            "まだ披露されていない曲",
                            count = "${current.unperformed.size}曲",
                            style = ImasSectionHeaderStyle.SMALL,
                            footer = "リアルライブでまだ一度も披露されていない曲です。"
                        ) {
                            UncollectedSongList(current.unperformed, expanded, toggle, subtitle) { selectedSongId = it }
                        }
                    }
                }
                failed -> ImasCard {
                    ImasEmptyState(ImasEmptyStateKind.FAILED, title = "未回収曲を読み込めませんでした", message = "もう一度開いてください。")
                }
                else -> ImasInlineLoading()
            }
        }
    }

    selectedSongId?.let { id ->
        ImasFullScreenDialog(onDismissRequest = { selectedSongId = null }) {
            SongDetailScreen(
                songId = id,
                onBack = { selectedSongId = null },
                onUnitClick = {},
                onIdolClick = {},
                onShowClick = { showId -> selectedSongId = null; selectedShowId = showId }
            )
        }
    }
    selectedShowId?.let { id ->
        ImasFullScreenDialog(onDismissRequest = { selectedShowId = null }) {
            SetlistScreen(
                showId = id,
                onBack = { selectedShowId = null },
                onSongClick = { songId -> selectedShowId = null; selectedSongId = songId },
                onIdolClick = {}
            )
        }
    }
}

/** 曲の 1 行の歌唱者 (ユニット名 → 畳んだ名義。規則はコア `songCreditLabel`)。 */
private fun creditLine(song: SongDetailRecord): String? =
    songCreditLabel(song.unitName, song.singerLabel, "").ifEmpty { null }

@Composable
private fun Summary(list: UncollectedListRecord) {
    val percent = { got: UInt, total: UInt -> if (total > 0u) Math.round(got.toDouble() / total.toDouble() * 100).toInt() else 0 }
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        ImasBoard(
            cells = listOf(
                ImasBoardCell(value = "${list.collected}/${list.total}", unit = "曲", label = "全曲（${percent(list.collected, list.total)}%）"),
                ImasBoardCell(
                    value = "${list.performedCollected}/${list.performedTotal}",
                    unit = "曲",
                    label = "披露済み（${percent(list.performedCollected, list.performedTotal)}%）"
                )
            )
        )
        ImasNote("ユニットVer.・Game Size などの ver 違いは原曲にまとめて数えます。どれか 1 つを生で聴けば回収です。")
    }
}

@Composable
private fun UncollectedSongList(
    rows: List<UncollectedSongRecord>,
    expanded: Set<String>,
    onToggle: (String) -> Unit,
    subtitle: (UncollectedSongRecord) -> String?,
    onSongClick: (String) -> Unit
) {
    ImasCardList(items = rows, key = { it.song.id }) { item ->
        Column {
            ImasSongRow(
                title = item.song.title,
                subtitle = subtitle(item),
                artworkUrl = item.song.artworkUrl,
                brand = item.song.brandId,
                trailing = ImasRowTrailing.Custom { UncollectedFrequencyBadge(item) },
                onClick = { onSongClick(item.song.id) }
            )
            if (item.variants.isNotEmpty()) {
                val isOpen = item.song.id in expanded
                ImasRowDivider(inset = DS.Space.rowH)
                ImasDisclosureRow(
                    title = "ver違い",
                    count = "${item.variants.size}曲・すべて未回収",
                    isExpanded = isOpen,
                    onToggle = { onToggle(item.song.id) }
                )
                if (isOpen) {
                    CompositionLocalProvider(LocalImasRowPosition provides ImasRowPosition.FOLLOWING) {
                        item.variants.forEach { variant ->
                            ImasSongRow(
                                title = variant.song.title,
                                subtitle = creditLine(variant.song),
                                artworkUrl = variant.song.artworkUrl,
                                brand = variant.song.brandId,
                                trailing = if (variant.playCount > 0u) ImasRowTrailing.Metric("${variant.playCount}", unit = "回披露")
                                else ImasRowTrailing.Badge("未披露", kind = ImasBadgeKind.NEGATIVE),
                                density = ImasRowDensity.COMPACT,
                                onClick = { onSongClick(variant.song.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

/** 未回収曲の披露頻度の札と披露回数 (回収ダッシュボードと未回収一覧で共有。閾値はコア)。 */
@Composable
internal fun UncollectedFrequencyBadge(item: UncollectedSongRecord) {
    val kind = when (item.frequency) {
        PlayFrequency.STAPLE -> ImasBadgeKind.ATTENTION
        PlayFrequency.SOMETIMES -> ImasBadgeKind.NEUTRAL
        PlayFrequency.RARE, PlayFrequency.NEVER -> ImasBadgeKind.NEGATIVE
    }
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasBadge(item.frequencyLabel, kind = kind)
        if (item.playCount > 0u) ImasMetric("${item.playCount}", unit = "回披露", size = ImasNumeralSize.SMALL)
    }
}

/** ダッシュボードから一覧を全画面で開く (iOS の push と同じ役割。統計画面は画面内 Dialog で完結させている)。 */
@Composable
internal fun UncollectedSongsDialog(scope: UncollectedListScope, onDismiss: () -> Unit) {
    ImasFullScreenDialog(onDismissRequest = onDismiss) {
        UncollectedSongsScreen(scope = scope, onBack = onDismiss)
    }
}
