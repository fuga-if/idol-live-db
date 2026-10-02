package com.fugaif.imaslivedb.ui.mypage

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.repository.AttendedEventTypeSets
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEventRow
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
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
    private val module = AppModule.from(app)
    private val marks = module.userMarkRepository

    private val _uiState = MutableStateFlow(AttendedEventsUiState())
    val uiState: StateFlow<AttendedEventsUiState> = _uiState.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _uiState.value = AttendedEventsUiState(
                events = module.eventRepository.fetchAttendedEvents(),
                typeSets = module.eventRepository.fetchAttendedEventTypeSets(),
                isLoading = false
            )
        }
    }
}

private enum class AttendanceFilter(private val type: AttendanceType?) {
    ALL(null), LIVE(AttendanceType.LIVE), STREAM(AttendanceType.STREAM), LIVE_VIEWING(AttendanceType.LIVE_VIEWING);

    /** 形態の語はコアの vocabulary ([AttendanceType.label])。 */
    val label: String get() = type?.label ?: "すべて"
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
                title = { Text("参加したライブ") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            ImasTabs(
                labels = filters.map { it.label },
                selection = safeIndex,
                onSelect = { filterIndex = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
            )

            if (state.isLoading) {
                ImasLoadingState()
            } else {
                Box(Modifier.fillMaxSize()) {
                    ImasFormBackdrop(modifier = Modifier.fillMaxSize()) {
                        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                            ImasListSection(if (filteredEvents.isEmpty()) null else "${filteredEvents.size}件") {
                                filteredEvents.forEach { ew ->
                                    ImasEventRow(
                                        event = ew.event,
                                        date = ew.firstDate,
                                        subtitle = ew.dateRange,
                                        rainbow = ew.isJoint,
                                        onClick = { onEventClick(ew.event.id) }
                                    )
                                }
                            }
                        }
                    }
                    if (filteredEvents.isEmpty()) {
                        ImasEmptyState(
                            icon = Icons.Filled.EventBusy,
                            title = when (filter) {
                                AttendanceFilter.STREAM -> "配信参加のライブがありません"
                                AttendanceFilter.LIVE_VIEWING -> "ライブビューイング参加のライブがありません"
                                else -> "現地参加のライブがありません"
                            },
                            modifier = Modifier.align(Alignment.Center)
                        )
                    }
                }
            }
        }
    }
}
