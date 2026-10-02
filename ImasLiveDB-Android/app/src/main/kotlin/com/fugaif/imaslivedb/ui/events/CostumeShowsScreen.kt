package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasLazyPage
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import uniffi.imas_core.CostumeEventRecord
import uniffi.imas_core.CostumeRecord
import uniffi.imas_core.CostumeShowRecord

/**
 * 衣装 1 着を「どの公演で着たか」で引く画面。iOS `CostumeShowsView` と対。
 *
 * イベントをまたいで着用公演を並べる (リ・プロローグ・X なら 10th の Act-1/2/4)。
 * イベントごとに束ね、イベントは新しい順・中の公演は DAY1 → DAY2 の順。
 * 束ね方と並び、曲名の 1 行は共有コアの `costume_events` が決めている。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CostumeShowsScreen(
    costumeId: String,
    onBack: () -> Unit,
    onShowClick: (String) -> Unit
) {
    val context = LocalContext.current
    var costume by remember(costumeId) { mutableStateOf<CostumeRecord?>(null) }
    var events by remember(costumeId) { mutableStateOf<List<CostumeEventRecord>>(emptyList()) }
    var isLoading by remember(costumeId) { mutableStateOf(true) }
    LaunchedEffect(costumeId) {
        val repo = AppModule.from(context).eventRepository
        costume = repo.fetchCostume(costumeId)
        events = repo.fetchCostumeEvents(costumeId)
        isLoading = false
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(costume?.name.orEmpty(), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (isLoading) {
                ImasLoadingState(Modifier.fillMaxSize())
            } else {
                ImasLazyPage {
                    costume?.let { c -> item(key = "header") { Header(c) } }
                    events.forEach { event ->
                        item(key = "event_${event.eventId}") {
                            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                                ImasSectionHeader(title = event.eventName, tight = true)
                                ImasCardList {
                                    event.shows.forEachIndexed { index, show ->
                                        if (index > 0) ImasRowDivider(inset = DS.Space.screen)
                                        ShowRow(show) { onShowClick(show.showId) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Header(costume: CostumeRecord) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasText(costume.name, ImasTextRole.HERO_TITLE)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            costume.attribution?.let { ImasBadge(text = it, kind = ImasBadgeKind.UNIT) }
            ImasText("${costume.showCount} 公演で着用", ImasTextRole.VALUE, color = DS.ink2)
        }
    }
}

@Composable
private fun ShowRow(show: CostumeShowRecord, onClick: () -> Unit) {
    ImasRow(
        title = show.showName,
        modifier = Modifier.imasRowPress(onClick = onClick),
        trailing = ImasRowTrailing.Custom {
            Row(
                horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
                verticalAlignment = Alignment.CenterVertically
            ) {
                ImasText(show.date, ImasTextRole.VALUE, color = DS.ink2)
                ImasRowChevron()
            }
        },
        density = ImasRowDensity.COMPACT,
        titleRole = ImasTextRole.ROW_LABEL,
        detail = {
            show.songsLabel?.let { ImasText(it, ImasTextRole.META) }
        }
    )
}
