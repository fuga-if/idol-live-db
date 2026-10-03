package com.fugaif.imaslivedb.ui.playlists

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.model.PlaylistSummary
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasTextInputDialog
import kotlinx.coroutines.launch

/**
 * 曲をプレイリストに足すシート (曲の詳細から)。既に入っているプレイリストには印を付ける。
 * iOS `AddToPlaylistSheet` と対。
 */
@Composable
fun AddToPlaylistSheet(song: Song, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val repository = AppModule.from(context).playlistRepository
    val scope = rememberCoroutineScope()

    var summaries by remember { mutableStateOf<List<PlaylistSummary>>(emptyList()) }
    var containing by remember { mutableStateOf<Set<String>>(emptySet()) }
    var isNaming by remember { mutableStateOf(false) }

    suspend fun load() {
        val all = repository.summaries()
        summaries = all
        containing = all.filter { repository.songIds(it.id).contains(song.id) }.map { it.id }.toSet()
    }

    LaunchedEffect(Unit) { load() }

    fun add(playlistId: String) {
        scope.launch {
            repository.append(playlistId, listOf(song.id))
            onDismiss()
        }
    }

    Surface {
        Column(Modifier.fillMaxWidth()) {
            ImasSheetToolbar(kind = ImasSheetToolbarKind.Read(onClose = onDismiss), title = "プレイリストに追加")
            LazyColumn(Modifier.fillMaxWidth()) {
                item {
                    ImasNavRow(
                        title = "新しいプレイリスト",
                        icon = Icons.Filled.Add,
                        showsChevron = false,
                        onClick = { isNaming = true }
                    )
                }
                items(summaries, key = { it.id }) { summary ->
                    val added = summary.id in containing
                    ImasSelectableRow(
                        title = summary.playlist.name,
                        subtitle = "${summary.songCount}曲",
                        isSelected = added,
                        isDisabled = added,
                        onClick = { add(summary.id) }
                    )
                }
            }
        }
    }

    if (isNaming) {
        ImasTextInputDialog(
            title = "新しいプレイリスト",
            confirmLabel = "作って足す",
            onDismiss = { isNaming = false },
            onConfirm = { name ->
                isNaming = false
                val trimmed = name.trim()
                if (trimmed.isNotEmpty()) {
                    scope.launch {
                        val playlist = repository.create(trimmed)
                        add(playlist.id)
                    }
                }
            }
        )
    }
}
