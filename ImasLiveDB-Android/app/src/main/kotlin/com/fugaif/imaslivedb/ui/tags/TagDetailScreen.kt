package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasRankBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasRankingRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowEmphasis
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasTagHeaderCard
import com.fugaif.imaslivedb.ui.theme.DS

/** 曲タグ詳細。iOS TagDetailView の移植 (説明 + 付いた曲ランキング + 編集/履歴/通報)。
 * アイドルタグは idol_tag_master に分離済みなので IdolTagDetailScreen 側にある。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagDetailScreen(
    tagId: String,
    onBack: () -> Unit,
    onSongClick: (String) -> Unit,
    viewModel: TagDetailViewModel = viewModel(key = tagId)
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    var showMenu by remember { mutableStateOf(false) }
    var showReportConfirm by remember { mutableStateOf(false) }
    var showEditSheet by remember { mutableStateOf(false) }
    var showHistorySheet by remember { mutableStateOf(false) }

    LaunchedEffect(tagId) { viewModel.load(context, tagId) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(uiState.tag?.name ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(Icons.Filled.MoreVert, contentDescription = "メニュー")
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            DropdownMenuItem(
                                text = { Text("不適切なタグを通報", color = DS.danger) },
                                leadingIcon = { Icon(Icons.Filled.Flag, contentDescription = null, tint = DS.danger) },
                                onClick = { showMenu = false; showReportConfirm = true }
                            )
                        }
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (uiState.isLoading) {
                ImasLoadingState()
            } else {
                val tag = uiState.tag
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    if (tag != null) {
                        item {
                            ImasListSection {
                                ImasTagHeaderCard(
                                    name = tag.name,
                                    colorHex = tag.color,
                                    categoryLabel = tag.category?.takeIf { it.isNotEmpty() }?.let { tagCategoryLabel(it) },
                                    description = tag.description
                                )
                            }
                        }
                        item {
                            Row(
                                Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                ImasButton(
                                    title = "説明を編集",
                                    onClick = { showEditSheet = true },
                                    role = ImasButtonRole.PLAIN,
                                    size = ImasButtonSize.SMALL
                                )
                                ImasButton(
                                    title = "編集履歴",
                                    icon = Icons.Filled.History,
                                    onClick = { showHistorySheet = true },
                                    role = ImasButtonRole.PLAIN,
                                    size = ImasButtonSize.SMALL
                                )
                            }
                        }
                        if (uiState.songs.isNotEmpty()) {
                            item {
                                ImasListSection(title = "「${tag.name}」な曲ランキング（${uiState.songs.size}曲）") {
                                    uiState.songs.forEachIndexed { idx, row -> SongRankRow(row, idx + 1, onSongClick) }
                                }
                            }
                        } else {
                            item {
                                ImasListSection {
                                    ImasEmptyState(icon = Icons.Filled.Sell, title = "まだこのタグが付いた曲はありません")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showEditSheet && uiState.tag != null) {
        TagEditSheet(
            tag = uiState.tag!!,
            onDismiss = { showEditSheet = false },
            onSaved = { viewModel.onTagUpdated(it) }
        )
    }
    if (showHistorySheet) {
        TagHistorySheet(tagId = tagId, onDismiss = { showHistorySheet = false })
    }
    ImasConfirmDestructive(
        title = "タグを通報",
        message = "不適切なコンテンツとして通報します",
        isPresented = showReportConfirm,
        onDismiss = { showReportConfirm = false },
        onConfirm = { viewModel.reportTag() },
        actionTitle = "通報する"
    )
    if (uiState.reportSubmitted) {
        ImasErrorAlert(
            message = "ご報告ありがとうございます。内容を確認します。",
            onDismiss = { viewModel.clearReportState() },
            title = "通報しました"
        )
    }
    if (uiState.reportError != null) {
        ImasErrorAlert(
            message = uiState.reportError,
            onDismiss = { viewModel.clearReportState() },
            title = "通報エラー"
        )
    }
}

/** 曲ランキング 1 行。解決済みなら曲の行 (ジャケ+曲名+歌唱者) とタップで詳細へ、
 * 未解決ならタイトルの代わりに ID を薄字で出す。 */
@Composable
private fun SongRankRow(row: TagSongRankRow, rank: Int, onSongClick: (String) -> Unit) {
    val song: Song? = row.song
    if (song != null) {
        ImasRankingRow(
            rank = rank,
            title = song.title,
            metric = "${row.voteCount}",
            unit = "票",
            sub = song.singerLabel,
            brand = song.brandId,
            onClick = { onSongClick(song.id) }
        ) {
            ImasArtwork(title = song.title, brand = song.brandId, size = 44.dp, imageUrl = song.artworkUrl)
        }
    } else {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            ImasRankBadge(rank)
            ImasRow(
                title = row.songId,
                modifier = Modifier.weight(1f),
                trailing = ImasRowTrailing.Metric("${row.voteCount}", unit = "票"),
                emphasis = ImasRowEmphasis.DIMMED
            )
        }
    }
}
