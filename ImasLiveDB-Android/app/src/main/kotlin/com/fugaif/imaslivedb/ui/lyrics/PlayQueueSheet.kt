package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.LyricsPlayback
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.theme.BrandColors
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

/**
 * 歌詞プレイヤーの「次に流れる曲」シート。積んだ曲の残りを並べ、∞ で「自動再生」(終わったら似た
 * 曲を足して流し続ける) を入れ切りする (Apple Music の自動再生と同じ置き場所)。既定は切。
 * iOS `PlayQueueSheet` の移植。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayQueueSheet(playback: LyricsPlayback, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val upcoming by playback.upcomingQueue.collectAsState()
    val autoplayNext by playback.autoplayNext.collectAsState()
    var songs by remember { mutableStateOf<Map<String, Song>>(emptyMap()) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    LaunchedEffect(upcoming) {
        val missing = upcoming.map { it.first }.filter { it !in songs }
        if (missing.isEmpty()) return@LaunchedEffect
        val repository = AppModule.from(context).songRepository
        val fetched = missing.mapNotNull { id -> repository.fetchSong(id)?.let { id to it } }
        if (fetched.isNotEmpty()) songs = songs + fetched
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        ImasFormBackdrop(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
                ImasText(
                    "次に流れる曲",
                    role = ImasTextRole.CARD_TITLE,
                    modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                )

                ImasListSection {
                    ImasRow(
                        title = "自動再生",
                        subtitle = if (autoplayNext) "終わったら似た曲を続けて流します" else "積んだ曲で終わります",
                        leading = ImasRowLeading.Icon(icon = Icons.Filled.AllInclusive, tone = ImasIconTileTone.NEUTRAL),
                        trailing = ImasRowTrailing.Custom {
                            ImasIconButton(
                                icon = Icons.Filled.AllInclusive,
                                label = if (autoplayNext) "自動再生: オン" else "自動再生: オフ",
                                size = ImasIconButtonSize.SMALL,
                                style = if (autoplayNext) ImasIconButtonStyle.FILLED else ImasIconButtonStyle.PLAIN,
                                onClick = { playback.setAutoplayNext(!autoplayNext) }
                            )
                        },
                        density = ImasRowDensity.COMPACT
                    )
                }

                if (upcoming.isNotEmpty()) {
                    ImasListSection(title = "次に流れる曲") {
                        upcoming.forEachIndexed { index, (id, label) ->
                            val song = songs[id]
                            val row = ImasRowLeading.Artwork(
                                title = song?.title.orEmpty(),
                                seed = BrandColors.hex(song?.brandId),
                                imageUrl = song?.artworkUrl
                            )
                            ImasRow(
                                title = song?.title ?: "次の曲",
                                subtitle = label,
                                leading = row,
                                density = ImasRowDensity.COMPACT,
                                modifier = if (index == 0) Modifier.clickable { playback.skipNext() } else Modifier
                            )
                        }
                    }
                }
            }
        }
    }
}
