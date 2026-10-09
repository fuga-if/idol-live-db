package com.fugaif.imaslivedb.ui.playlists

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import com.fugaif.imaslivedb.data.spotify.SpotifyException
import com.fugaif.imaslivedb.data.spotify.SpotifyService
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasProgressBar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasValueRow
import com.fugaif.imaslivedb.ui.settings.SpotifySettingsContent
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import uniffi.imas_core.spotifyExportSummary

/** 書き出す 1 曲 (曲 id と、見つからなかったときに出す曲名)。 */
data class SpotifyExportSong(val songId: String, val title: String)

private sealed interface ExportPhase {
    data object Idle : ExportPhase
    data object Setup : ExportPhase
    data class Running(val done: Int, val total: Int) : ExportPhase
    data class Finished(val result: SpotifyService.ExportResult) : ExportPhase
    data class Failed(val message: String) : ExportPhase
}

/**
 * 曲の並びを Spotify のプレイリストに書き出すシート (セトリ・自分のプレイリスト)。iOS `SpotifyExportSheet`。
 *
 * 連携していればすぐ始める。していなければ、同じシートの中で連携の案内を出す (終えたら始められる)。
 * 見つからなかった曲は必ず名前で出す (黙って抜けると、欠けたプレイリストのまま気付かない)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SpotifyExportSheet(name: String, songs: List<SpotifyExportSong>, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val service = remember { AppModule.from(context).spotifyService }
    val state by service.state.collectAsState()
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var phase by remember { mutableStateOf<ExportPhase>(ExportPhase.Idle) }
    var job by remember { mutableStateOf<Job?>(null) }

    fun start() {
        job?.cancel()
        phase = ExportPhase.Running(0, songs.size)
        job = scope.launch {
            phase = try {
                val result = service.exportPlaylist(name, songs.map { it.songId }) { done, total ->
                    phase = ExportPhase.Running(done, total)
                }
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                ExportPhase.Finished(result)
            } catch (e: SpotifyException) {
                ExportPhase.Failed(e.message ?: "")
            }
        }
    }

    LaunchedEffect(Unit) { if (state.isConnected) start() }

    ModalBottomSheet(
        onDismissRequest = { job?.cancel(); onDismiss() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg,
    ) {
        ImasFormBackdrop {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = { job?.cancel(); onDismiss() }), title = "Spotify に書き出す")
                when (val p = phase) {
                    ExportPhase.Idle -> if (state.isConnected) {
                        ImasListSection(footer = "非公開のプレイリストとして作ります。") {
                            ImasValueRow(key = "プレイリスト名", value = name)
                            ImasValueRow(key = "曲", value = "${songs.size} 曲", monospaced = true)
                            StartButton(::start)
                        }
                    } else {
                        ImasListSection(footer = "自分の Spotify アカウントで作った「アプリ」の Client ID を使います。最初の 1 回だけ設定が要ります。") {
                            ImasNavRow(
                                title = "Spotify と連携する",
                                icon = Icons.AutoMirrored.Filled.QueueMusic,
                                onClick = { phase = ExportPhase.Setup },
                            )
                        }
                    }
                    // 連携の案内をシートの中で出す。ログインを終えて戻ると、ここで始められる。
                    ExportPhase.Setup -> if (state.isConnected) {
                        ImasListSection(footer = "非公開のプレイリストとして作ります。") {
                            ImasValueRow(key = "プレイリスト名", value = name)
                            StartButton(::start)
                        }
                    } else {
                        SpotifySettingsContent()
                    }
                    is ExportPhase.Running -> ImasListSection("Spotify で曲を探しています") {
                        Column(
                            Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapLoose),
                            verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
                        ) {
                            ImasProgressBar(fraction = if (p.total == 0) 0.0 else p.done.toDouble() / p.total)
                            ImasText("${p.done} / ${p.total} 曲", role = ImasTextRole.META)
                        }
                    }
                    is ExportPhase.Finished -> Finished(p.result, songs) { url ->
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    }
                    is ExportPhase.Failed -> ImasListSection {
                        ImasNotice(
                            kind = ImasNoticeKind.ERROR,
                            title = "書き出せませんでした",
                            message = p.message,
                            modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
                        )
                        if (state.isConnected) {
                            StartButton(::start)
                        } else {
                            ImasNavRow(
                                title = "Spotify にログインし直す",
                                icon = Icons.AutoMirrored.Filled.QueueMusic,
                                onClick = { phase = ExportPhase.Setup },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StartButton(onClick: () -> Unit) {
    ImasButton(
        title = "Spotify に書き出す",
        onClick = onClick,
        modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
        icon = Icons.Filled.IosShare,
        size = ImasButtonSize.LARGE,
    )
}

@Composable
private fun Finished(result: SpotifyService.ExportResult, songs: List<SpotifyExportSong>, open: (String) -> Unit) {
    ImasListSection {
        ImasNotice(
            kind = if (result.added > 0) ImasNoticeKind.SUCCESS else ImasNoticeKind.WARNING,
            message = spotifyExportSummary(result.added.toUInt(), result.missingSongIds.size.toUInt()),
            modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
        )
        result.playlistUrl?.let { url ->
            ImasButton(
                title = "Spotify で開く",
                onClick = { open(url) },
                modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
                icon = Icons.AutoMirrored.Filled.OpenInNew,
                size = ImasButtonSize.LARGE,
            )
        }
    }
    if (result.missingSongIds.isNotEmpty()) {
        // 元の順で、同じ曲は 1 回だけ。
        val missing = result.missingSongIds.toSet()
        val titles = songs.filter { it.songId in missing }.distinctBy { it.songId }
        ImasListSection(
            "見つからなかった曲",
            count = "${titles.size}",
            footer = "Spotify で配信されていないか、名義が違って見分けられなかった曲です。",
        ) {
            titles.forEach {
                ImasText(it.title, role = ImasTextRole.ROW_LABEL, modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap))
            }
        }
    }
}
