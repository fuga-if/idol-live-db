package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.theme.DS

/** タグ詳細。iOS TagDetailView の移植 (説明 + 付いた曲ランキング + 編集/履歴/通報)。 */
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
                                text = { Text("不適切なタグを通報") },
                                leadingIcon = { Icon(Icons.Filled.Flag, contentDescription = null) },
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
                CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
            } else {
                val tag = uiState.tag
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    if (tag != null) {
                        item {
                            Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    TagColorDot(tag.color, size = 16.dp)
                                    Text(tag.name, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                                    Box(Modifier.weight(1f))
                                    if (!tag.category.isNullOrEmpty()) {
                                        Text(
                                            tagCategoryLabel(tag.category), fontSize = 12.sp,
                                            color = tagCategoryColor(tag.category)
                                        )
                                    }
                                }
                                Text(
                                    tag.description?.ifEmpty { null } ?: "説明なし",
                                    fontSize = 15.sp,
                                    color = if (tag.description.isNullOrEmpty()) DS.ink3 else DS.ink,
                                    modifier = Modifier.padding(top = 8.dp)
                                )
                                Row(
                                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                                    modifier = Modifier.padding(top = 10.dp)
                                ) {
                                    TextButton(onClick = { showEditSheet = true }) { Text("説明を編集") }
                                    TextButton(onClick = { showHistorySheet = true }) {
                                        Icon(Icons.Filled.History, contentDescription = null, modifier = Modifier.padding(end = 4.dp))
                                        Text("編集履歴")
                                    }
                                }
                            }
                            HorizontalDivider(color = DS.sep)
                        }
                        item {
                            Text(
                                "「${tag.name}」な曲ランキング (${uiState.songs.size}曲)",
                                fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
                            )
                        }
                    }
                    if (uiState.songs.isEmpty()) {
                        item {
                            Text(
                                "まだこのタグが付いた曲はありません", color = DS.ink2, fontSize = 13.sp,
                                modifier = Modifier.fillMaxWidth().padding(16.dp)
                            )
                        }
                    } else {
                        itemsIndexed(uiState.songs) { idx, row ->
                            val song = row.song
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                modifier = Modifier.fillMaxWidth()
                                    .clickable(enabled = song != null) { song?.let { onSongClick(it.id) } }
                                    .padding(horizontal = 16.dp, vertical = 4.dp)
                            ) {
                                TagRankBadge(idx + 1)
                                if (song != null) {
                                    SongRow(
                                        title = song.title,
                                        artistNames = song.singerLabel ?: "",
                                        unitName = song.unitName,
                                        artworkUrl = song.artworkUrl,
                                        previewUrl = song.previewUrl,
                                        brandId = song.brandId,
                                        modifier = Modifier.weight(1f)
                                    )
                                } else {
                                    Text(row.songId, fontSize = 13.sp, color = DS.ink2, modifier = Modifier.weight(1f))
                                }
                                Text("${row.voteCount}票", fontSize = 12.sp, color = DS.ink2)
                            }
                            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
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
    if (showReportConfirm) {
        AlertDialog(
            onDismissRequest = { showReportConfirm = false },
            title = { Text("タグを通報") },
            text = { Text("不適切なコンテンツとして通報します") },
            confirmButton = {
                TextButton(onClick = { showReportConfirm = false; viewModel.reportTag() }) { Text("通報する") }
            },
            dismissButton = {
                TextButton(onClick = { showReportConfirm = false }) { Text("キャンセル") }
            }
        )
    }
    if (uiState.reportSubmitted) {
        AlertDialog(
            onDismissRequest = { viewModel.clearReportState() },
            title = { Text("通報しました") },
            text = { Text("ご報告ありがとうございます。内容を確認します。") },
            confirmButton = { TextButton(onClick = { viewModel.clearReportState() }) { Text("OK") } }
        )
    }
    if (uiState.reportError != null) {
        AlertDialog(
            onDismissRequest = { viewModel.clearReportState() },
            title = { Text("通報エラー") },
            text = { Text(uiState.reportError ?: "") },
            confirmButton = { TextButton(onClick = { viewModel.clearReportState() }) { Text("OK") } }
        )
    }
}
