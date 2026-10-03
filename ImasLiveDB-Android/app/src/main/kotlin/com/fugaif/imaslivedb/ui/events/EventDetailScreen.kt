package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.HowToReg
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.model.EventAttendance
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.AttendanceSwipeRow
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasLabeledRow
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkBar
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkTile
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasShowRow
import com.fugaif.imaslivedb.ui.designsystem.ImasStatGrid
import com.fugaif.imaslivedb.ui.designsystem.ImasStatTile
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.edit.EventEditScreen
import com.fugaif.imaslivedb.ui.edit.RecordHistorySheet
import com.fugaif.imaslivedb.ui.edit.ShowEditScreen
import com.fugaif.imaslivedb.ui.filtered.EventFilterKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.ImasThemeProvider
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.imasTheme
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.penlight
import kotlinx.coroutines.launch
import java.time.LocalDate
import com.fugaif.imaslivedb.ui.share.SocialShare
import uniffi.imas_core.shareEventText
import uniffi.imas_core.AttendanceState
import uniffi.imas_core.TicketSaleStage
import uniffi.imas_core.TicketSaleTimeline
import com.fugaif.imaslivedb.ui.designsystem.ImasTimelineAxis
import com.fugaif.imaslivedb.ui.designsystem.ImasTimelineBar
import com.fugaif.imaslivedb.ui.designsystem.ImasTimelineLegend
import com.fugaif.imaslivedb.ui.designsystem.ImasTimelineMark
import com.fugaif.imaslivedb.ui.designsystem.ImasTimelineScale
import com.fugaif.imaslivedb.ui.designsystem.ImasTimelineLane
import com.fugaif.imaslivedb.data.local.localWrite

/**
 * イベント詳細。iOS EventDetailView の構成を 1:1 で写す。
 * hero(ペンライト + イベント名 + 会場・日付 + 参加/お気に入りの印 + 参加予定チップ) の下を
 * ImasTabs で [公演・セトリ][出演][情報] に切り替える。
 *
 * 披露ユニット表示 (unit 被覆判定) は Setlist 側の担当範囲と重複するため対象外。
 * BD/DVD所有チェックは Android に event_releases の同期が無いため対象外。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventDetailScreen(
    eventId: String,
    onBack: () -> Unit,
    onShowClick: (String) -> Unit,
    onIdolClick: (String) -> Unit,
    /**
     * 情報タブのブランド/年度行から「同じ条件のライブ一覧」へ (kind, value は
     * [com.fugaif.imaslivedb.ui.filtered.EventFilterKind] の定義に従う)。
     */
    onFilteredEventsClick: (String, String) -> Unit = { _, _ -> },
    /** 情報タブの衣装行から、その衣装の着用公演一覧へ (引数は costume id)。 */
    onCostumeClick: (String) -> Unit = {},
    viewModel: EventDetailViewModel = viewModel(key = eventId)
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()

    // 編集後の読み直しトリガ。編集は「保存中…」の裏で DB を書き換えるので、
    // 画面に残っている旧値を捨てて引き直す (VM の load は public なのでそのまま呼べる)。
    var reloadToken by remember(eventId) { mutableIntStateOf(0) }

    LaunchedEffect(eventId, reloadToken) { viewModel.load(context, eventId) }

    var segment by rememberSaveable(eventId) { mutableIntStateOf(0) }
    val seed: String? = if (uiState.isJoint) null else uiState.brandColorHex
    // 画面の部品に渡す brand はブランド ID (部品がマスタの色へ引く)。
    val brand = uiState.brandId
    val t = imasTheme(seed, uiState.brandColorHex)

    // ブランド行の行き先には brand_id が要るが、UiState が持つのは表示名と色だけ。
    // この画面の担当範囲外である ViewModel を変えずに済ませるため、ここで 1 回だけ引く
    // (スナップショット経路なのでメモリ内の参照で終わる)。
    // 編集フォームには Event レコードそのものが要るので、同じ 1 回で受けておく。
    var eventRecord by remember(eventId) { mutableStateOf<Event?>(null) }
    var brandId by remember(eventId) { mutableStateOf<String?>(null) }
    LaunchedEffect(eventId, reloadToken) {
        val event = AppModule.from(context).eventRepository.fetchEvent(eventId)
        eventRecord = event
        brandId = event?.brandId?.takeIf { it.isNotEmpty() }
    }

    var showMenu by remember { mutableStateOf(false) }
    var showEventEdit by remember { mutableStateOf(false) }
    var showEventHistory by remember { mutableStateOf(false) }
    var showCreate by remember { mutableStateOf(false) }
    var editingShow by remember { mutableStateOf<Show?>(null) }
    var historyShow by remember { mutableStateOf<Show?>(null) }
    var showLoginPrompt by remember { mutableStateOf(false) }
    val authState by AppModule.from(context).authService.state.collectAsState()
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる (詳細は data/auth/EditPermission.kt)。
    val canEditHere = remember(authState) { authState.showEditAffordance }

    // 投稿/編集導線の共通ゲート。未ログインはログイン誘導へ、BAN 済みは無反応 (優先順はコアが持つ)。
    fun startEdit(present: () -> Unit) =
        authState.startCommunityEdit(promptLogin = { showLoginPrompt = true }, present = present)

    val marks = remember { AppModule.from(context).userMarkRepository }
    val scope = rememberCoroutineScope()
    var favOn by remember(eventId) { mutableStateOf(false) }
    // 参加は公演単位で持つ (行っていない公演まで回収率に数えないため)。
    // イベント単位の attended は旧データの互換としてだけ見る。
    var attendedShowIds by remember(eventId) { mutableStateOf<Set<String>>(emptySet()) }
    var legacyEventAttended by remember(eventId) { mutableStateOf(false) }
    var showAttendanceSheet by remember(eventId) { mutableStateOf(false) }
    val attendOn = attendedShowIds.isNotEmpty() || legacyEventAttended

    suspend fun reloadAttendance() {
        attendedShowIds = marks.attendedShowIds(uiState.shows.map { it.id })
    }

    LaunchedEffect(eventId) {
        favOn = marks.isOn(UserMark.EVENT, eventId, UserMark.FAVORITE)
        legacyEventAttended = marks.isOn(UserMark.EVENT, eventId, UserMark.ATTENDED)
    }
    LaunchedEffect(uiState.shows) { reloadAttendance() }
    // 参加の札・開催期間はマークに依るので、マークが変わるたびにコアへ問い直す。
    LaunchedEffect(eventId, attendedShowIds, legacyEventAttended, reloadToken) {
        viewModel.refreshHero(context, eventId, attendedShowIds, legacyEventAttended)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                // ヒーローは固定で常に全文を出すので、バーには出さない (iOS と同じ)。
                // 1 行に詰めると合同ライブ名の先頭ブランドが省略で消えるだけになる。
                title = {},
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    IconButton(onClick = {
                        // 文面と URL はコアが作る (iOS と同じ: イベント名 + イベントへのリンク)。
                        SocialShare.shareText(context, shareEventText(eventId, uiState.eventName))
                    }) {
                        Icon(Icons.Filled.Share, contentDescription = "このイベントをシェア")
                    }
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "その他")
                    }
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        // BAN 済みには編集導線を出さない (押しても 403 になるだけ)。判定はコア。
                        if (canEditHere) {
                            DropdownMenuItem(
                                text = { Text("このライブを編集") },
                                onClick = { showMenu = false; startEdit { showEventEdit = true } },
                                enabled = eventRecord != null
                            )
                            DropdownMenuItem(
                                text = { Text("公演を追加") },
                                onClick = { showMenu = false; startEdit { showCreate = true } }
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("編集履歴") },
                            onClick = { showMenu = false; showEventHistory = true }
                        )
                    }
                }
            )
        }
    ) { innerPadding ->
        if (uiState.isLoading) {
            ImasLoadingState(Modifier.fillMaxSize().padding(innerPadding))
        } else {
            Column(Modifier.fillMaxSize().padding(innerPadding)) {
                Hero(
                    state = uiState, t = t, favOn = favOn, attendOn = attendOn, seed = seed, brand = brand,
                    onFavToggle = {
                        scope.launch {
                            localWrite("お気に入りの切り替え") { marks.toggle(UserMark.EVENT, eventId, UserMark.FAVORITE) }
                                ?.let { favOn = it }
                        }
                    },
                    onAttendToggle = { showAttendanceSheet = true }
                )
                ImasTabs(
                    labels = listOf("公演・セトリ", "出演", "情報"),
                    selection = segment,
                    onSelect = { segment = it },
                    seed = seed,
                    brand = brand,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
                )
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    when (segment) {
                        0 -> showsSection(
                            uiState, seed, brand, onShowClick,
                            canEdit = canEditHere,
                            onEditShow = { show -> startEdit { editingShow = show } },
                            onShowHistory = { show -> historyShow = show },
                            onAttendanceChange = { scope.launch { reloadAttendance() } }
                        )
                        1 -> castSection(uiState, seed, brand, onIdolClick)
                        else -> infoSection(uiState, seed, brand, brandId, onFilteredEventsClick, onCostumeClick)
                    }
                }
            }
        }
    }

    if (showAttendanceSheet) {
        EventAttendanceSheet(
            shows = uiState.shows,
            seed = seed,
            brand = brand,
            onDismiss = { showAttendanceSheet = false },
            onChange = { scope.launch { reloadAttendance() } }
        )
    }

    // 編集フォームはフルスクリーン Dialog に載せる (RecentEditsScreen → SetlistEditScreen と同じ)。
    val editingEvent = eventRecord
    if (showEventEdit && editingEvent != null) {
        Dialog(
            onDismissRequest = { showEventEdit = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            EventEditScreen(
                original = editingEvent,
                onDismiss = { showEventEdit = false },
                onSaved = { showEventEdit = false; reloadToken++ }
            )
        }
    }

    if (showCreate) {
        Dialog(
            onDismissRequest = { showCreate = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            ShowEditScreen(
                eventId = eventId,
                // 既存公演数を初期の並び順にする (末尾に足すのが普通なので)。
                suggestedSortOrder = uiState.shows.size,
                onDismiss = { showCreate = false },
                onSaved = { showCreate = false; reloadToken++ }
            )
        }
    }

    val currentEditingShow = editingShow
    if (currentEditingShow != null) {
        Dialog(
            onDismissRequest = { editingShow = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            ShowEditScreen(
                original = currentEditingShow,
                eventId = currentEditingShow.eventId,
                onDismiss = { editingShow = null },
                onSaved = { editingShow = null; reloadToken++ }
            )
        }
    }

    if (showEventHistory) {
        RecordHistorySheet(
            recordType = "Event",
            recordName = eventId,
            onDismiss = { showEventHistory = false }
        )
    }

    val currentHistoryShow = historyShow
    if (currentHistoryShow != null) {
        RecordHistorySheet(
            recordType = "Show",
            recordName = currentHistoryShow.id,
            onDismiss = { historyShow = null }
        )
    }

    if (showLoginPrompt) {
        CommunityLoginPromptDialog(
            message = "ライブ・公演の編集にはログインが必要です。",
            onDismiss = { showLoginPrompt = false }
        )
    }
}

// MARK: - Hero

@Composable
private fun Hero(
    state: EventDetailUiState,
    t: ImasTheme,
    favOn: Boolean,
    attendOn: Boolean,
    seed: String?,
    brand: String?,
    onFavToggle: () -> Unit,
    onAttendToggle: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)) {
        // 色の点は何も伝えないので置かない (合同は下の行の「合同」で示す)。
        ImasText(state.eventName, role = ImasTextRole.HERO_TITLE)
        val subLine = state.hero?.subLine.orEmpty()
        val heroSub = if (state.isJoint && subLine.isNotEmpty()) "$subLine ・ 合同" else subLine
        if (heroSub.isNotEmpty()) {
            ImasNote(heroSub, icon = Icons.Filled.CalendarMonth, modifier = Modifier.padding(top = DS.Space.gapTight))
        }
        Spacer(Modifier.height(DS.Space.gap))
        ImasThemeProvider(seed = seed, brand = brand) {
            ImasMarkBar {
                ImasMarkTile(
                    icon = if (favOn) Icons.Filled.Star else Icons.Filled.StarBorder,
                    label = "お気に入り",
                    isOn = favOn,
                    onClick = onFavToggle
                )
                ImasMarkTile(
                    icon = Icons.Filled.HowToReg,
                    label = "参加",
                    isOn = attendOn,
                    onClick = onAttendToggle
                )
            }
        }
        // 参加の札 (参加予定・あと N 日 / 参加済み) の判定と文言はコア。
        state.hero?.attendance?.takeIf { it.state != AttendanceState.NONE }?.let { attendance ->
            val planned = attendance.state == AttendanceState.PLANNED
            ImasBadge(
                text = attendance.label,
                kind = if (planned) ImasBadgeKind.PLANNED else ImasBadgeKind.POSITIVE,
                icon = if (planned) Icons.Filled.Schedule else Icons.Filled.CheckCircle,
                modifier = Modifier.padding(top = DS.Space.gap)
            )
        }
    }
}

// MARK: - Panel 0: 公演・セトリ

private fun LazyListScope.showsSection(
    state: EventDetailUiState,
    seed: String?,
    brand: String?,
    onShowClick: (String) -> Unit,
    canEdit: Boolean,
    onEditShow: (Show) -> Unit,
    onShowHistory: (Show) -> Unit,
    onAttendanceChange: () -> Unit
) {
    item { ImasSectionHeader(title = "公演", count = "${state.shows.size} 公演 → セトリへ", tight = true) }
    if (state.shows.isEmpty()) {
        item {
            ImasEmptyState(
                icon = Icons.Filled.Mic,
                title = "公演がまだありません",
                seed = seed, brand = brand
            )
        }
    } else {
        items(state.shows, key = { it.id }) { show ->
            // 行の右スワイプで参加登録 (EventListScreen・カレンダーと同じ規則)。
            AttendanceSwipeRow(showId = show.id, showName = show.name, onChange = onAttendanceChange) {
                ShowRow(
                    show, seed, brand, state.isJoint,
                    canEdit = canEdit,
                    onEdit = { onEditShow(show) },
                    onHistory = { onShowHistory(show) },
                    onClick = { onShowClick(show.id) }
                )
            }
        }
    }
}

@Composable
private fun ShowRow(
    show: Show,
    seed: String?,
    brand: String?,
    rainbow: Boolean,
    canEdit: Boolean,
    onEdit: () -> Unit,
    onHistory: () -> Unit,
    onClick: () -> Unit
) {
    // 公演そのものの編集はセトリ画面ではなくこの行から入る (セトリ画面は別担当)。
    // 行タップはこれまで通りセトリへ。編集/履歴は ⋯ に畳んで誤爆を避ける。
    var menuOpen by remember { mutableStateOf(false) }
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasShowRow(
            date = show.date,
            title = show.name,
            modifier = Modifier.weight(1f).imasRowPress(onClick = onClick),
            subtitle = listOfNotNull(show.venue, show.date).joinToString(" ・ "),
            // 色の点は付けない (このライブの公演はみな同じブランドで、点は何も伝えない)。
            showsChevron = true
        )
        Box {
            IconButton(onClick = { menuOpen = true }) {
                Icon(
                    Icons.Filled.MoreVert, contentDescription = "公演の操作", tint = DS.ink3,
                    modifier = Modifier.size(18.dp)
                )
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                if (canEdit) {
                    DropdownMenuItem(
                        text = { Text("公演を編集") },
                        onClick = { menuOpen = false; onEdit() }
                    )
                }
                DropdownMenuItem(
                    text = { Text("編集履歴") },
                    onClick = { menuOpen = false; onHistory() }
                )
            }
        }
    }
}

// MARK: - Panel 1: 出演

private fun LazyListScope.castSection(
    state: EventDetailUiState,
    seed: String?,
    brand: String?,
    onIdolClick: (String) -> Unit
) {
    val attendance = state.attendance
    if (attendance == null || attendance.brandIdols.isEmpty()) {
        item {
            ImasEmptyState(
                icon = Icons.Filled.Groups,
                title = "出演情報がありません",
                message = "セトリ・出演者が登録されると表示されます",
                seed = seed, brand = brand
            )
        }
        return
    }

    // ImasSectionHeader は左右の余白を自分で持つので、見出しを含む Column には重ねて
    // padding を足さない (足すと二重になる)。見出しの下に置く中身の側だけ screen 幅を与える。
    if (attendance.leadIdols.isNotEmpty()) {
        item {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasSectionHeader(
                    title = "主演",
                    count = if (attendance.leadIdols.size > 1) "${attendance.leadIdols.size}名" else null,
                    tight = true
                )
                RoleSection(
                    attendance, attendance.leadByShow, attendance.leadIdols, ImasBadgeKind.LEAD, "主演", seed, brand, onIdolClick,
                    modifier = Modifier.padding(horizontal = DS.Space.screen)
                )
            }
        }
    }
    if (attendance.guestIdols.isNotEmpty()) {
        item {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasSectionHeader(
                    title = "ゲスト",
                    count = if (attendance.guestIdols.size > 1) "${attendance.guestIdols.size}名" else null,
                    tight = true
                )
                RoleSection(
                    attendance, attendance.guestByShow, attendance.guestIdols, ImasBadgeKind.GUEST, "ゲスト", seed, brand, onIdolClick,
                    modifier = Modifier.padding(horizontal = DS.Space.screen)
                )
            }
        }
    }
    if (attendance.isFullAttendance) {
        item { FullAttendanceBanner(attendance, Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen)) }
    }
    // 出演者の塊。複数日は日付ごと (DAY の見出し)、単日は「出演」、最後に「欠席」。
    // 塊の切り方・並びはコア (attendance_groups)。日付ごとの塊だけ、主演・ゲストと同じ
    // DAY の見出し (札 + 日付 + 公演名) にして人数を添える。
    items(attendance.groups, key = { it.id }) { group ->
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            val show = group.showId?.let { id -> attendance.shows.firstOrNull { it.id == id } }
            if (show != null) {
                val index = attendance.shows.indexOf(show)
                Row(
                    modifier = Modifier.padding(horizontal = DS.Space.screen),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
                ) {
                    DayHeader(index, show, Modifier.weight(1f, fill = true))
                    ImasText("${group.idols.size}名", role = ImasTextRole.META)
                }
            } else {
                ImasSectionHeader(title = group.label, count = "${group.idols.size}名", tight = true)
            }
            ImasCard(modifier = Modifier.padding(horizontal = DS.Space.screen)) {
                AvatarGrid(
                    idols = group.idols, chipKind = null, chipText = null, seed = seed, brand = brand,
                    onClick = onIdolClick, dim = { group.label == "欠席" }
                )
            }
        }
    }
}

@Composable
private fun RoleSection(
    attendance: EventAttendance,
    byShow: Map<String, Set<String>>,
    allIdols: List<Idol>,
    chipKind: ImasBadgeKind,
    chipText: String,
    seed: String?,
    brand: String?,
    onIdolClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    if (attendance.shows.size > 1) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(DS.Space.card)) {
            attendance.shows.forEachIndexed { idx, show ->
                val ids = byShow[show.id] ?: emptySet()
                val dayIdols = allIdols.filter { it.id in ids }
                if (dayIdols.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                        DayHeader(idx, show)
                        ImasCard {
                            AvatarGrid(dayIdols, chipKind, chipText, seed, brand, onIdolClick)
                        }
                    }
                }
            }
        }
    } else {
        ImasCard(modifier = modifier) {
            AvatarGrid(allIdols, chipKind, chipText, seed, brand, onIdolClick)
        }
    }
}

/** DAY 見出し: 「DAYn」札 (墨塗り) + 日付(M/D(曜)) + 公演名。 */
@Composable
private fun DayHeader(index: Int, show: Show, modifier: Modifier = Modifier) {
    Row(
        modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        ImasBadge(text = "DAY${index + 1}", kind = ImasBadgeKind.LEAD)
        shortDate(show.date)?.let { ImasText(it, role = ImasTextRole.META) }
        if (show.name.isNotEmpty() && show.name != "DAY${index + 1}") {
            ImasText(show.name, role = ImasTextRole.META, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** "2026-09-19" → "9/19(土)"。パース不能なら null。 */
private fun shortDate(ymd: String): String? {
    val date = runCatching { LocalDate.parse(ymd) }.getOrNull() ?: return null
    val wd = listOf("月", "火", "水", "木", "金", "土", "日")[date.dayOfWeek.value - 1]
    return "${date.monthValue}/${date.dayOfMonth}(${wd})"
}

@Composable
private fun FullAttendanceBanner(attendance: EventAttendance, modifier: Modifier = Modifier) {
    ImasCard(modifier = modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = DS.warning, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(DS.Space.gap))
            ImasText("全員集合！", role = ImasTextRole.CARD_TITLE, modifier = Modifier.weight(1f))
            ImasText("${attendance.brandIdols.size}/${attendance.brandIdols.size} 名", role = ImasTextRole.NOTE)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AvatarGrid(
    idols: List<Idol>,
    chipKind: ImasBadgeKind?,
    chipText: String?,
    seed: String?,
    brand: String?,
    onClick: (String) -> Unit,
    dim: (Idol) -> Boolean = { false }
) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(DS.Space.card), verticalArrangement = Arrangement.spacedBy(DS.Space.card)) {
        idols.forEach { idol ->
            val faded = dim(idol)
            Column(
                modifier = Modifier.width(64.dp).clickable { onClick(idol.id) }.alpha(if (faded) 0.45f else 1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
            ) {
                ImasAvatar(label = idol.shortName, seed = idol.color, brand = idol.brandId, size = 52.dp, entityId = idol.id)
                if (chipKind != null && !chipText.isNullOrEmpty()) {
                    ImasBadge(chipText, kind = chipKind, seed = seed, brand = brand)
                }
                ImasText(
                    idol.shortName, role = ImasTextRole.META, color = DS.ink,
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

// MARK: - Panel 2: 情報

private fun LazyListScope.infoSection(
    state: EventDetailUiState,
    seed: String?,
    brand: String?,
    brandId: String?,
    onFilteredEventsClick: (String, String) -> Unit,
    onCostumeClick: (String) -> Unit
) {
    state.stats?.let { stats ->
        item { StatsGrid(stats, seed, brand) }
    }
    if (state.ticketTimeline != null || state.ticketUrl != null || state.isFutureEvent) {
        item { TicketInfoSection(state, seed, brand) }
    }
    // 衣装。行は衣装単位で、押すとイベントをまたいだ着用公演へ。
    state.costumes?.let { costumes ->
        item(key = "costumes") { EventCostumesSection(costumes, brandId, onCostumeClick) }
    }
    if (state.brandShortName != null || firstShowYear(state) != null) {
        item { MetaSection(state, seed, brand, brandId, onFilteredEventsClick) }
    }
}

@Composable
private fun StatsGrid(stats: EventStats, seed: String?, brand: String?) {
    ImasStatGrid(modifier = Modifier.padding(horizontal = DS.Space.screen), columns = 2) {
        ImasStatTile(Icons.Filled.Mic, "${stats.showCount}", "公演", seed = seed, brand = brand)
        ImasStatTile(Icons.Filled.LibraryMusic, "${stats.totalSongs}", "曲（延べ）", seed = seed, brand = brand)
        ImasStatTile(Icons.Filled.MusicNote, "${stats.uniqueSongs}", "ユニーク曲", seed = seed, brand = brand)
        ImasStatTile(Icons.Filled.Groups, "${stats.castCount}", "キャスト", seed = seed, brand = brand)
    }
}

@Composable
private fun TicketInfoSection(state: EventDetailUiState, seed: String?, brand: String?) {
    val uriHandler = LocalUriHandler.current
    val timeline = state.ticketTimeline
    val hasAny = timeline != null || state.ticketUrl != null
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
        // ImasSectionHeader は左右の余白を自分で持つので、追加の padding は付けない (二重になる)。
        ImasSectionHeader(title = "チケット情報", tight = true)
        // 全受付を 1 枚の帯の表に重ねて「いつ何が受付中か」を一目で見せ、
        // 期間・当落・対象・申込リンクの詳細はその下の一覧に並べる (iOS と同じ組み方)。
        if (timeline != null) {
            val scale = timelineScale(timeline)
            ImasCard(modifier = Modifier.padding(horizontal = DS.Space.screen)) {
                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                    ImasTimelineAxis(scale)
                    timeline.rows.forEach { row ->
                        ImasTimelineLane(
                            title = row.sale.name,
                            trailing = row.sale.stageLabel,
                            scale = scale,
                            bar = row.span?.let { span ->
                                ImasTimelineBar(span.start, span.end, span.startOpen, span.endOpen, timelineBarStyle(row.sale.stage))
                            },
                            result = row.resultAt,
                            resultPending = row.sale.stage != TicketSaleStage.ENDED
                        )
                    }
                }
            }
            ImasTimelineLegend(Modifier.padding(horizontal = DS.Space.screen))
        }
        ImasCardList(modifier = Modifier.padding(horizontal = DS.Space.screen)) {
            var shown = false
            timeline?.rows?.forEach { row ->
                if (shown) ImasRowDivider(inset = DS.Space.rowH)
                TicketSaleRow(row.sale, seed, brand)
                shown = true
            }
            state.ticketUrl?.let { url ->
                if (shown) ImasRowDivider(inset = DS.Space.rowH)
                TicketUrlRow(url, seed, brand) { uriHandler.openUri(url) }
                shown = true
            }
            if (!hasAny) {
                ImasNote(
                    "チケット情報は未登録です",
                    modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowVCompact)
                )
            }
        }
    }
}

@Composable
private fun TicketUrlRow(url: String, seed: String?, brand: String?, onClick: () -> Unit) {
    val t = imasThemeForBrand(seed, brand)
    Row(
        Modifier.fillMaxWidth().imasRowPress(onClick = onClick)
            .padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowVCompact),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)
    ) {
        Icon(Icons.Filled.ConfirmationNumber, contentDescription = null, tint = t.accent, modifier = Modifier.size(16.dp))
        ImasText("公式チケットページを開く", role = ImasTextRole.ROW_LABEL, color = t.accent)
    }
}

/**
 * チケット受付 1 件の行。種別・段階・期間・当落・申込リンクをまとめて出す。
 * 表示文字列 (kindLabel / stageLabel / periodLabel / resultLabel) は共有コアが確定させた
 * ものをそのまま出す (画面で組み立て直さない)。
 */
@Composable
private fun TicketSaleRow(sale: uniffi.imas_core.TicketSale, seed: String?, brand: String?) {
    val uriHandler = LocalUriHandler.current
    val t = imasThemeForBrand(seed, brand)
    Column(
        Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowVCompact),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            // 段階 (受付中・結果待ち・受付前・終了) は状態なので札に、種別 (最速先行・一般 等) は
            // 添え字にする (§10.1: 札は状態を表す)。stage は今回 Android の binding に加わった値。
            ImasBadge(sale.stageLabel, kind = stageBadgeKind(sale.stage))
            ImasText(sale.name, role = ImasTextRole.ROW_LABEL, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            ImasText(sale.kindLabel, role = ImasTextRole.META)
        }
        if (sale.showLabels.isNotEmpty()) {
            ImasText(sale.showLabels.joinToString(" / "), role = ImasTextRole.META)
        }
        sale.periodLabel?.let { ImasText(it, role = ImasTextRole.NOTE) }
        sale.resultLabel?.let { ImasText("当落発表 $it", role = ImasTextRole.NOTE) }
        sale.url?.let { url ->
            Row(
                modifier = Modifier.imasRowPress(onClick = { uriHandler.openUri(url) }),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
            ) {
                Icon(Icons.Filled.ConfirmationNumber, contentDescription = null, tint = t.accent, modifier = Modifier.size(14.dp))
                ImasText("申込ページを開く", role = ImasTextRole.NOTE, color = t.accent)
            }
        }
    }
}

private fun timelineScale(timeline: TicketSaleTimeline) = ImasTimelineScale(
    ticks = timeline.ticks.map { ImasTimelineMark(it.at, it.label) },
    today = timeline.today,
    shows = timeline.shows.map { ImasTimelineMark(it.at, it.label) }
)

/** 帯の見え方。受付中は墨の塗り、受付前は墨の線、締切後 (結果待ち・終了) は灰 (iOS と同じ対応)。 */
private fun timelineBarStyle(stage: TicketSaleStage): ImasTimelineBar.Style = when (stage) {
    TicketSaleStage.OPEN -> ImasTimelineBar.Style.ACTIVE
    TicketSaleStage.UPCOMING -> ImasTimelineBar.Style.AHEAD
    TicketSaleStage.AWAITING_RESULT, TicketSaleStage.ENDED -> ImasTimelineBar.Style.PAST
}

/**
 * 段階の札の種類。受付中/結果待ちは「墨の線」(§10.1 `.attention` が受付中を例示)、
 * 受付前/終了は「灰」(`.neutral` が終了・未定を例示)。色の数を増やさない (iOS と同じ対応)。
 */
private fun stageBadgeKind(stage: TicketSaleStage): ImasBadgeKind = when (stage) {
    TicketSaleStage.OPEN, TicketSaleStage.AWAITING_RESULT -> ImasBadgeKind.ATTENTION
    TicketSaleStage.UPCOMING, TicketSaleStage.ENDED -> ImasBadgeKind.NEUTRAL
}

@Composable
private fun MetaSection(
    state: EventDetailUiState,
    seed: String?,
    brand: String?,
    brandId: String?,
    onFilteredEventsClick: (String, String) -> Unit
) {
    ImasCardList(modifier = Modifier.padding(horizontal = DS.Space.screen)) {
        var shown = false
        state.brandShortName?.let { name ->
            if (shown) ImasRowDivider(inset = DS.Space.rowH)
            // brand_id がまだ解決できていない間は押せない普通の行にしておく
            // (押せる見た目だけ出して何も起きない方が悪い)。
            ImasLabeledRow(
                key = "ブランド", value = name, seed = seed, brand = brand,
                tappable = brandId != null,
                onClick = brandId?.let { id -> { onFilteredEventsClick(EventFilterKind.BRAND, id) } }
            )
            shown = true
        }
        firstShowYear(state)?.let { year ->
            if (shown) ImasRowDivider(inset = DS.Space.rowH)
            ImasLabeledRow(
                key = "年度", value = "${year}年", seed = seed, brand = brand,
                tappable = true,
                onClick = { onFilteredEventsClick(EventFilterKind.YEAR, year.toString()) }
            )
        }
    }
}

private fun firstShowYear(state: EventDetailUiState): Int? {
    val date = state.shows.firstOrNull()?.date ?: return null
    return if (date.length >= 4) date.take(4).toIntOrNull() else null
}
