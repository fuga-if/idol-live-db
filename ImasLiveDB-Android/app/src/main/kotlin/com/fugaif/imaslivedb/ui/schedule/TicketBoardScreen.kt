package com.fugaif.imaslivedb.ui.schedule

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ReadableWidth
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.OpenArchive
import uniffi.imas_core.OpenTicketSale
import uniffi.imas_core.TicketApplication
import uniffi.imas_core.TicketBoard
import uniffi.imas_core.TicketBoardSale
import uniffi.imas_core.ticketApplicationLabel

/**
 * チケット画面 (iOS `TicketBoardView` の移植)。
 *
 * カレンダーの帯に出していたチケットの受付期間・配信アーカイブ期間を、カレンダーから外して
 * ここに集約する (カレンダーには期限日の単日点だけ残す)。段階ごとに区切り、席種だけ違う
 * 受付は 1 行にまとめてある (コアの `ticket_board`)。
 */
class TicketBoardViewModel(app: Application) : AndroidViewModel(app) {
    private val module = AppModule.from(app)

    private val _board = MutableStateFlow<TicketBoard?>(null)
    val board: StateFlow<TicketBoard?> = _board.asStateFlow()

    private val _applications = MutableStateFlow<Map<String, TicketApplication>>(emptyMap())
    val applications: StateFlow<Map<String, TicketApplication>> = _applications.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _board.value = module.eventRepository.fetchTicketBoard()
            _applications.value = module.userMarkRepository.ticketApplications()
        }
    }

    /** 記録だけ読み直す (詳細で付け替えて戻ってきたとき)。段階の組み直しまでは要らない。 */
    fun reloadApplications() {
        viewModelScope.launch { _applications.value = module.userMarkRepository.ticketApplications() }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketBoardScreen(
    onBack: () -> Unit,
    onEventClick: (String) -> Unit,
    viewModel: TicketBoardViewModel = viewModel()
) {
    val context = LocalContext.current
    val board by viewModel.board.collectAsStateWithLifecycle()
    val applications by viewModel.applications.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { viewModel.load() }
    // 詳細で記録を付け替えて戻ってきたときに読み直す (戻るだけでは一覧が変わらない)。
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { viewModel.reloadApplications() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("チケット") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        val current = board
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                current == null -> ImasLoadingState(modifier = Modifier.fillMaxSize())
                current.isEmpty() -> ImasEmptyState(
                    kind = ImasEmptyStateKind.EMPTY,
                    title = "チケットの予定はありません",
                    message = "いま受付中・これから受付・結果待ち・見られるアーカイブのいずれもありません。"
                )
                else -> ReadableWidth { readable ->
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = readable
                    ) {
                        if (current.open.isNotEmpty()) {
                            item(key = "open") {
                                OpenTicketSection(
                                    sales = current.open,
                                    applications = applications,
                                    onEventClick = onEventClick,
                                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                                )
                            }
                        }
                        if (current.upcoming.isNotEmpty()) {
                            item(key = "upcoming") {
                                UpcomingSection(
                                    sales = current.upcoming,
                                    onEventClick = onEventClick,
                                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                                )
                            }
                        }
                        if (current.awaiting.isNotEmpty()) {
                            item(key = "awaiting") {
                                AwaitingSection(
                                    sales = current.awaiting,
                                    applications = applications,
                                    onEventClick = onEventClick,
                                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                                )
                            }
                        }
                        if (current.archives.isNotEmpty()) {
                            item(key = "archives") {
                                ArchivesSection(
                                    archives = current.archives,
                                    onEventClick = onEventClick,
                                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun TicketBoard.isEmpty(): Boolean =
    open.isEmpty() && upcoming.isEmpty() && awaiting.isEmpty() && archives.isEmpty()

/** 受付中: 締切までの残り、申込済みなら記録を見せる (未申込ほど目立つ ATTENTION 札)。 */
@Composable
private fun OpenTicketSection(
    sales: List<OpenTicketSale>,
    applications: Map<String, TicketApplication>,
    onEventClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    ImasSection("受付中", modifier = modifier, count = "${sales.size}件", style = ImasSectionHeaderStyle.SMALL) {
        ImasCardList {
            sales.forEachIndexed { index, open ->
                val application = open.saleIds.firstNotNullOfOrNull { applications[it] }
                ImasRow(
                    title = open.sale.eventName,
                    modifier = Modifier.imasRowPress(onClick = { onEventClick(open.sale.eventId) }),
                    subtitle = listOfNotNull(open.nameLabel, open.deadlineLabel).joinToString(" ・ "),
                    leading = ImasRowLeading.Bar(seed = open.brandColor),
                    trailing = application?.let { ImasRowTrailing.Badge(ticketApplicationLabel(open.sale.kind, it), ImasBadgeKind.GUEST) }
                        ?: open.remainingLabel?.let { ImasRowTrailing.Badge(it, ImasBadgeKind.ATTENTION) }
                        ?: ImasRowTrailing.None,
                    density = ImasRowDensity.COMPACT,
                    subtitleLineLimit = 2,
                    position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                )
            }
        }
    }
}

/** これから受付: まだ始まっていないので、締切前の ATTENTION より落ち着いた札にする。 */
@Composable
private fun UpcomingSection(
    sales: List<TicketBoardSale>,
    onEventClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    ImasSection("これから受付", modifier = modifier, count = "${sales.size}件", style = ImasSectionHeaderStyle.SMALL) {
        ImasCardList {
            sales.forEachIndexed { index, sale ->
                ImasRow(
                    title = sale.sale.eventName,
                    modifier = Modifier.imasRowPress(onClick = { onEventClick(sale.sale.eventId) }),
                    subtitle = listOfNotNull(sale.nameLabel, sale.dateLabel).joinToString(" ・ "),
                    leading = ImasRowLeading.Bar(seed = sale.brandColor),
                    trailing = ImasRowTrailing.Badge(sale.remainingLabel, ImasBadgeKind.NEUTRAL),
                    density = ImasRowDensity.COMPACT,
                    subtitleLineLimit = 2,
                    position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                )
            }
        }
    }
}

/** 結果待ち: 申込済みの記録 (当選/落選/申込) が付いていればそれを、無ければ発表までの残り。 */
@Composable
private fun AwaitingSection(
    sales: List<TicketBoardSale>,
    applications: Map<String, TicketApplication>,
    onEventClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    ImasSection("結果待ち", modifier = modifier, count = "${sales.size}件", style = ImasSectionHeaderStyle.SMALL) {
        ImasCardList {
            sales.forEachIndexed { index, sale ->
                val application = sale.saleIds.firstNotNullOfOrNull { applications[it] }
                ImasRow(
                    title = sale.sale.eventName,
                    modifier = Modifier.imasRowPress(onClick = { onEventClick(sale.sale.eventId) }),
                    subtitle = listOfNotNull(sale.nameLabel, sale.dateLabel).joinToString(" ・ "),
                    leading = ImasRowLeading.Bar(seed = sale.brandColor),
                    trailing = application?.let { ImasRowTrailing.Badge(ticketApplicationLabel(sale.sale.kind, it), ImasBadgeKind.GUEST) }
                        ?: ImasRowTrailing.Badge(sale.remainingLabel, ImasBadgeKind.NEUTRAL),
                    density = ImasRowDensity.COMPACT,
                    subtitleLineLimit = 2,
                    position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                )
            }
        }
    }
}

/** 見られるアーカイブ: ライブ一覧の `OpenArchivesSection` と同じ行の形。 */
@Composable
private fun ArchivesSection(
    archives: List<OpenArchive>,
    onEventClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    ImasSection("見られるアーカイブ", modifier = modifier, count = "${archives.size}件", style = ImasSectionHeaderStyle.SMALL) {
        ImasCardList {
            archives.forEachIndexed { index, archive ->
                ImasRow(
                    title = archive.eventName,
                    modifier = Modifier.imasRowPress(onClick = { onEventClick(archive.eventId) }),
                    subtitle = listOf(archive.showLabels.joinToString("・"), archive.endsLabel)
                        .filter { it.isNotEmpty() }
                        .joinToString(" ・ "),
                    leading = ImasRowLeading.Bar(seed = archive.brandColor),
                    trailing = ImasRowTrailing.Badge(archive.remainingLabel, ImasBadgeKind.ATTENTION),
                    density = ImasRowDensity.COMPACT,
                    subtitleLineLimit = 2,
                    position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                )
            }
        }
    }
}
