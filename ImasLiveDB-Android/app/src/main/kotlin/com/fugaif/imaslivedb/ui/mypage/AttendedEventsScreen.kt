package com.fugaif.imaslivedb.ui.mypage

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.repository.AttendedEventTypeSets
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 参加したライブ一覧。iOS AttendedEventsListView 相当。
 * 参加マーク (event/show 単位) が付いた event を公演日降順で表示し、現地/配信/LVでフィルタできる。
 * LV参加が1件も無ければLVタブは出さない (データ駆動)。
 */
data class AttendedEventsUiState(
    val events: List<EventWithDateRange> = emptyList(),
    val typeSets: AttendedEventTypeSets = AttendedEventTypeSets(emptySet(), emptySet(), emptySet()),
    val isLoading: Boolean = true
)

class AttendedEventsViewModel(app: Application) : AndroidViewModel(app) {
    private val marks = AppModule.from(app).userMarkRepository

    private val _uiState = MutableStateFlow(AttendedEventsUiState())
    val uiState: StateFlow<AttendedEventsUiState> = _uiState.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _uiState.value = AttendedEventsUiState(
                events = marks.attendedEvents(),
                typeSets = marks.attendedEventTypeSets(),
                isLoading = false
            )
        }
    }
}

private enum class AttendanceFilter(val label: String) {
    ALL("すべて"), LIVE("現地"), STREAM("配信"), LIVE_VIEWING("LV")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AttendedEventsScreen(
    onBack: () -> Unit,
    onEventClick: (String) -> Unit,
    viewModel: AttendedEventsViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var filterIndex by rememberSaveable { mutableIntStateOf(0) }

    val showsLiveViewingTab = state.typeSets.liveViewing.isNotEmpty()
    val filters = remember(showsLiveViewingTab) {
        if (showsLiveViewingTab) {
            listOf(AttendanceFilter.ALL, AttendanceFilter.LIVE, AttendanceFilter.STREAM, AttendanceFilter.LIVE_VIEWING)
        } else {
            listOf(AttendanceFilter.ALL, AttendanceFilter.LIVE, AttendanceFilter.STREAM)
        }
    }
    val safeIndex = filterIndex.coerceIn(0, filters.lastIndex)
    val filter = filters[safeIndex]

    val filteredEvents by remember(state.events, state.typeSets, filter) {
        derivedStateOf {
            when (filter) {
                AttendanceFilter.ALL -> state.events
                AttendanceFilter.LIVE -> state.events.filter { state.typeSets.live.contains(it.event.id) }
                AttendanceFilter.STREAM -> state.events.filter { state.typeSets.stream.contains(it.event.id) }
                AttendanceFilter.LIVE_VIEWING -> state.events.filter { state.typeSets.liveViewing.contains(it.event.id) }
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("参加したライブ", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).background(DS.bg)) {
            ImasSegmented(
                labels = filters.map { it.label },
                selection = safeIndex,
                onSelect = { filterIndex = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)
            )

            if (state.isLoading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else if (filteredEvents.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    ImasEmptyState(
                        icon = Icons.Filled.EventBusy,
                        title = when (filter) {
                            AttendanceFilter.STREAM -> "配信参加のライブがありません"
                            AttendanceFilter.LIVE_VIEWING -> "ライブビューイング参加のライブがありません"
                            else -> "現地参加のライブがありません"
                        }
                    )
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 4.dp)) {
                    items(filteredEvents, key = { it.event.id }) { ew ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            modifier = Modifier.fillMaxWidth()
                                .clickable { onEventClick(ew.event.id) }
                                .padding(horizontal = 16.dp, vertical = 10.dp)
                        ) {
                            ImasLeadBar(brand = ew.event.brandId, height = 38.dp)
                            Column(Modifier.weight(1f)) {
                                Text(
                                    text = ew.event.name,
                                    fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                                    maxLines = 2, overflow = TextOverflow.Ellipsis
                                )
                                ew.dateRange?.let { d ->
                                    Text(text = d, fontSize = 12.sp, color = DS.ink2)
                                }
                            }
                        }
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}
