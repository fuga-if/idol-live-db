package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasTagChip
import com.fugaif.imaslivedb.ui.theme.DS
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
                CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    costume?.let { c -> item(key = "header") { Header(c) } }
                    events.forEach { event ->
                        item(key = "event_${event.eventId}") {
                            Column(Modifier.padding(bottom = 8.dp)) {
                                ImasSectionHeader(title = event.eventName, tight = true)
                                Column(
                                    Modifier.padding(horizontal = 16.dp).fillMaxWidth()
                                        .clip(RoundedCornerShape(14.dp)).background(DS.surface)
                                ) {
                                    event.shows.forEachIndexed { index, show ->
                                        if (index > 0) {
                                            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                                        }
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
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(costume.name, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            costume.attribution?.let { ImasTagChip(text = it, brand = costume.brandId) }
            Text("${costume.showCount} 公演で着用", fontSize = 14.sp, color = DS.ink2)
        }
    }
}

@Composable
private fun ShowRow(show: CostumeShowRecord, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(show.showName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
                Text(show.date, fontSize = 13.sp, color = DS.ink2)
            }
            show.songsLabel?.let { Text(it, fontSize = 12.sp, color = DS.ink2) }
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = DS.ink3, modifier = Modifier.size(18.dp)
        )
    }
}
