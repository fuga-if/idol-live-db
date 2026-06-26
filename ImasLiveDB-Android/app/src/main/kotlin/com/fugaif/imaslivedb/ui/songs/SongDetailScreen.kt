package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.OndemandVideo
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLabeledRow
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.components.ImasStatTile
import com.fugaif.imaslivedb.ui.components.MarkToggleAction
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/**
 * 楽曲詳細。iOS の SongSheetContent (大ジャケ hero + ImasSegmented 3 タブ
 * [情報・歌唱/披露履歴/コミュニティ]) の構成を 1:1 で写す。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongDetailScreen(
    songId: String,
    onBack: () -> Unit,
    onUnitClick: (String) -> Unit,
    onIdolClick: (String) -> Unit,
    onShowClick: (String) -> Unit,
    viewModel: SongDetailViewModel = viewModel(key = songId)
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    LaunchedEffect(songId) { viewModel.load(context, songId) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(uiState.song?.title ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    MarkToggleAction(
                        entityType = UserMark.SONG, entityId = songId, kind = UserMark.FAVORITE,
                        activeIcon = Icons.Filled.Favorite, inactiveIcon = Icons.Filled.FavoriteBorder,
                        activeTint = DS.favorite, contentDescription = "お気に入り"
                    )
                }
            )
        }
    ) { padding ->
        val song = uiState.song
        if (uiState.isLoading || song == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            SongSheetContent(
                state = uiState, song = song,
                modifier = Modifier.fillMaxSize().padding(padding),
                onIdolClick = onIdolClick, onShowClick = onShowClick,
                onToggleTag = viewModel::toggleTag
            )
        }
    }
}

@Composable
private fun SongSheetContent(
    state: SongDetailUiState,
    song: Song,
    modifier: Modifier,
    onIdolClick: (String) -> Unit,
    onShowClick: (String) -> Unit,
    onToggleTag: (com.fugaif.imaslivedb.data.community.CommunityApi.SongTag) -> Unit
) {
    // 配色シード: ソロ (歌唱1人) はその個人カラー、それ以外はブランド色。
    val seed = if (state.originalArtists.size == 1) state.originalArtists.first().color else null
    val t = ImasTheme.derive(seed, song.brandId, dark = true)
    var segment by rememberSaveable(song.id) { mutableIntStateOf(0) }

    Column(modifier = modifier.verticalScroll(rememberScrollState())) {
        Hero(song, state.originalArtists, t)
        ImasSegmented(
            labels = listOf("情報・歌唱", "披露履歴", "コミュニティ"),
            selection = segment, onSelect = { segment = it },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
        )
        when (segment) {
            0 -> InfoTab(song, state, seed, onIdolClick)
            1 -> HistoryTab(state.performanceHistory, seed, song.brandId, onShowClick)
            else -> CommunityTab(state, seed, song.brandId, onToggleTag)
        }
        Box(Modifier.size(24.dp))
    }
}

@Composable
private fun Hero(song: Song, originalArtists: List<Idol>, t: ImasTheme) {
    val artistLine = when {
        originalArtists.isNotEmpty() -> originalArtists.joinToString(" / ") { it.name }
        !song.singerLabel.isNullOrEmpty() -> song.singerLabel
        !song.unitName.isNullOrEmpty() -> song.unitName
        else -> null
    }
    Column(
        modifier = Modifier.fillMaxWidth().background(t.heroSurface).padding(top = 16.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ArtworkImage(url = song.artworkUrl, size = 168.dp, previewUrl = song.previewUrl, songTitle = song.title)
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 16.dp)) {
            Text(song.title, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (artistLine != null) {
                Text(artistLine, fontSize = 15.sp, color = DS.ink2, textAlign = TextAlign.Center,
                    maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
            }
        }
    }
}

@Composable
private fun InfoTab(song: Song, state: SongDetailUiState, seed: String?, onIdolClick: (String) -> Unit) {
    Column(modifier = Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // 披露統計
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ImasStatTile(Icons.Filled.Mic, "${state.performanceHistory.size}", "披露回数", unit = "回",
                seed = seed, brand = song.brandId, modifier = Modifier.weight(1f))
            ImasStatTile(Icons.Filled.CheckCircle, "${state.performanceHistory.map { it.showId }.distinct().size}",
                "披露公演", unit = "公演", seed = seed, brand = song.brandId, modifier = Modifier.weight(1f))
        }
        // 楽曲情報
        Column {
            ImasSectionHeader("楽曲情報", tight = true)
            InfoRow("リリース日", song.releaseDate)
            InfoRow("作曲", song.composer)
            InfoRow("作詞", song.lyricist)
            InfoRow("編曲", song.arranger)
            InfoRow("CDシリーズ", song.cdSeries)
            InfoRow("収録", song.cdTitle)
        }
        // 歌唱アイドル
        if (state.originalArtists.isNotEmpty()) {
            IdolGridSection("歌唱アイドル", state.originalArtists, onIdolClick)
        }
        // ライブ歌唱歴
        if (state.performerArtists.isNotEmpty()) {
            IdolGridSection("ライブ歌唱歴", state.performerArtists, onIdolClick)
        }
    }
}

@Composable
private fun InfoRow(key: String, value: String?) {
    if (value.isNullOrEmpty()) return
    ImasLabeledRow(key = key, value = value)
    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun IdolGridSection(title: String, idols: List<Idol>, onIdolClick: (String) -> Unit) {
    Column {
        ImasSectionHeader(title, count = "${idols.size}")
        FlowRow(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            idols.forEach { idol ->
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.width(64.dp).clickable { onIdolClick(idol.id) }
                ) {
                    ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 52.dp)
                    Text(idol.name, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = DS.ink2,
                        textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 6.dp))
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CommunityTab(
    state: SongDetailUiState, seed: String?, brand: String?,
    onToggleTag: (com.fugaif.imaslivedb.data.community.CommunityApi.SongTag) -> Unit
) {
    val context = LocalContext.current
    Column(modifier = Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // タグ (集計系コミュニティ・Worker D1)。タップで自分の投票をトグル。
        Column {
            ImasSectionHeader("タグ", count = "${state.tags.size}")
            if (state.tags.isEmpty()) {
                Text("タグはまだありません", fontSize = 13.sp, color = DS.ink3,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp))
            } else {
                FlowRow(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    state.tags.forEach { tag ->
                        val bg = if (tag.mine) DS.pick.copy(alpha = 0.18f) else DS.fill
                        val fg = if (tag.mine) DS.pick else DS.ink
                        Row(
                            modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(bg)
                                .clickable { onToggleTag(tag) }
                                .padding(horizontal = 12.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(tag.name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = fg)
                            if (tag.voteCount > 0) {
                                Text(" ${tag.voteCount}", fontSize = 12.sp, color = DS.ink3)
                            }
                        }
                    }
                }
            }
        }
        // ペンライト投票 (集計系・Worker D1)
        Column {
            ImasSectionHeader("ペンライト", count = state.penlight?.totalVotes?.let { "${it}票" })
            val sets = state.penlight?.topSets ?: emptyList()
            if (sets.isEmpty()) {
                Text("ペンライト投票はまだありません", fontSize = 13.sp, color = DS.ink3,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp))
            } else {
                sets.take(5).forEach { ps ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        ps.colors.take(4).forEach { hex ->
                            Box(Modifier.size(20.dp).clip(RoundedCornerShape(5.dp))
                                .background(com.fugaif.imaslivedb.ui.theme.hexToColor(hex)))
                        }
                        Box(Modifier.weight(1f))
                        Text("${ps.count}", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
                    }
                }
            }
        }
        // コーレス (構造化コミュニティ・CloudKit)
        Column {
            ImasSectionHeader("コーレス", count = "${state.songCalls.size}")
            if (state.songCalls.isEmpty()) {
                ImasEmptyState(Icons.Filled.Campaign, "コーレスはまだありません",
                    "この曲のコール&レスポンスが登録されると、ここに表示されます。", seed = seed, brand = brand)
            } else {
                state.songCalls.forEach { call ->
                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                        Text(call.callText, fontSize = 15.sp, color = DS.ink)
                        if (!call.authorDisplayName.isNullOrEmpty()) {
                            Text("by ${call.authorDisplayName}", fontSize = 12.sp, color = DS.ink3, modifier = Modifier.padding(top = 2.dp))
                        }
                    }
                    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                }
            }
        }
        // 参考動画 (構造化コミュニティ・CloudKit)
        Column {
            ImasSectionHeader("参考動画", count = "${state.songVideos.size}")
            if (state.songVideos.isEmpty()) {
                ImasEmptyState(Icons.Filled.OndemandVideo, "参考動画はまだありません",
                    "ライブ映像などの参考動画が登録されると、ここに表示されます。", seed = seed, brand = brand)
            } else {
                state.songVideos.forEach { video ->
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable {
                            runCatching {
                                context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(video.youtubeUrl)))
                            }
                        }.padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(Modifier.size(36.dp).clip(RoundedCornerShape(9.dp)).background(DS.fill), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.PlayArrow, null, tint = DS.danger, modifier = Modifier.size(22.dp))
                        }
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            Text(video.videoTitle ?: video.youtubeUrl, fontSize = 15.sp, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (!video.note.isNullOrEmpty()) {
                                Text(video.note, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                }
            }
        }
    }
}

@Composable
private fun HistoryTab(history: List<PerformanceHistoryRow>, seed: String?, brand: String?, onShowClick: (String) -> Unit) {
    if (history.isEmpty()) {
        ImasEmptyState(Icons.Filled.MusicNote, "披露履歴はまだありません",
            "この曲がライブで披露されると、ここに記録されます。", seed = seed, brand = brand)
        return
    }
    Column(modifier = Modifier.padding(top = 8.dp)) {
        history.forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth().clickable { onShowClick(row.showId) }
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f)) {
                    Text(row.eventName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(listOf(row.showName, row.date).filter { it.isNotEmpty() }.joinToString(" ・ "),
                        fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
    }
}
