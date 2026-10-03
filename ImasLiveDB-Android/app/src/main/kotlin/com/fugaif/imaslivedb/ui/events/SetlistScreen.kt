package com.fugaif.imaslivedb.ui.events

import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.snapshotFlow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.SetlistLikeService
import com.fugaif.imaslivedb.data.auth.canEdit
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.PerformerRow
import com.fugaif.imaslivedb.data.model.SetlistRow
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowTicket
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.components.PerformerChip
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatarStack
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasNoteBadges
import com.fugaif.imaslivedb.ui.designsystem.unbreakableNote
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasMasthead
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasLabeledRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPerformer
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.edit.SetlistEditScreen
import com.fugaif.imaslivedb.ui.filtered.EventFilterKind
import com.fugaif.imaslivedb.ui.filtered.ShowFilterKind
import com.fugaif.imaslivedb.ui.share.SetlistCommentComposeSheet
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.BrandColors
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import uniffi.imas_core.PerformerNameMode
import uniffi.imas_core.RowNoteTone
import uniffi.imas_core.Lineup
import uniffi.imas_core.SetlistAbsentOriginalRecord
import uniffi.imas_core.SetlistLineupNote
import uniffi.imas_core.SetlistPerformerNoteRecord
import uniffi.imas_core.SetlistRowNoteGroupRecord
import uniffi.imas_core.SetlistRowNoteRecord
import uniffi.imas_core.setlistDisplayModeIsCompact
import uniffi.imas_core.setlistDisplayModes
import uniffi.imas_core.ShowCollectionRecord
import uniffi.imas_core.formatYen
import uniffi.imas_core.ticketKindLabel
import uniffi.imas_core.ticketPriceRanges
import uniffi.imas_core.ticketsForKind
import com.fugaif.imaslivedb.ui.theme.displayName
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.imasTheme
import com.fugaif.imaslivedb.ui.theme.joined

/** 公演の画面の内部タブ。セットリスト (未来の公演でまだ無ければ出さない)・予想 (未来だけ)・情報。 */
private enum class ShowTab(val label: String) {
    SETLIST("セットリスト"), PREDICTION("予想"), INFO("情報")
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun SetlistScreen(
    showId: String,
    onBack: () -> Unit,
    onSongClick: (String) -> Unit,
    onIdolClick: (String) -> Unit,
    /**
     * 会場/日付の行から「同じ会場・同じ日の公演一覧」へ (kind, value は
     * [com.fugaif.imaslivedb.ui.filtered.ShowFilterKind] の定義に従う)。
     */
    onFilteredShowsClick: (String, String) -> Unit = { _, _ -> },
    /** パンくずの「イベント名」から、そのイベントの詳細へ (同じイベントの他公演もそこから)。 */
    onEventClick: (String) -> Unit = {},
    /**
     * パンくずの「ブランド」から、そのブランドのライブ一覧へ (kind は
     * [com.fugaif.imaslivedb.ui.filtered.EventFilterKind] の定義に従う。ここでは常に `BRAND`)。
     */
    onFilteredEventsClick: (String, String) -> Unit = { _, _ -> },
    /** true なら予想タブで開く (プロデュースの「次のライブ」→「セトリを予想」)。 */
    opensPrediction: Boolean = false,
    viewModel: SetlistViewModel = viewModel(key = showId, factory = SetlistViewModel.factory(showId))
) {
    val uiState by viewModel.uiState.collectAsState()
    val marks by viewModel.showMarks.collectAsState()
    val likes by viewModel.likes.collectAsState()
    val authState by viewModel.authState.collectAsState()
    val showLoginPrompt by viewModel.loginPrompt.collectAsState()
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる (data/auth/EditPermission.kt のヘッダ参照)。
    val canShowEditActions = remember(authState) { authState.showEditAffordance }
    val isSignedIn = remember(authState) { authState.canEdit }

    // 歌唱者をどの名前で出すか。設定画面と同じ 1 箇所から読む。
    // **行の添え物 (名義) の中身がこれで変わる**ので、読み込みの鍵に入れて
    // 設定変更に画面を開き直さずに追従させる。
    val performerName = AppPreferences.performerName

    // 表示の詳しさ。公演をまたいで保持する (ViewModel が端末に残す)。
    val displayMode by viewModel.displayMode.collectAsState()
    // 曲名と歌唱者だけに絞る形か。どのモードがそれに当たるかもコアが決める。
    val simpleMode = setlistDisplayModeIsCompact(displayMode)

    // 「配信も回収に含める」設定でも回収の札と要約が変わるので、歌唱者の設定と同じ扱いで
    // 読み直しの鍵に入れる。表示の詳しさの切り替えと参加の付け外しは ViewModel が自分で読み直す。
    LaunchedEffect(showId, performerName, AppPreferences.includeStreamInCollection) {
        viewModel.load(performerName, AppPreferences.includeStreamInCollection)
    }

    // --- 「良かった」投票 (post-vote)。セトリが埋まっている公演だけ取りに行く ---
    val hasSetlist = uiState.setlist.isNotEmpty()
    LaunchedEffect(showId, hasSetlist) {
        if (hasSetlist) viewModel.refreshLikes()
    }

    var menuOpen by remember { mutableStateOf(false) }
    // 公演の画面の内部タブ。「次のライブ」の「セトリを予想」からは予想で開く。
    var selectedTab by rememberSaveable(showId) {
        mutableStateOf(if (opensPrediction) ShowTab.PREDICTION else ShowTab.SETLIST)
    }
    var showAttendanceDialog by remember { mutableStateOf(false) }
    var showEditDialog by remember { mutableStateOf(false) }
    var showHistorySheet by remember { mutableStateOf(false) }

    /** 編集導線の共通ゲート。未ログインならログイン誘導、BAN は無反応 (導線自体を隠している)。 */
    fun startEdit() {
        authState.startCommunityEdit(promptLogin = viewModel::requestLogin) { showEditDialog = true }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(uiState.show?.name ?: "") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "その他")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        // 3 値なのでトグルではなく選ぶ形にする。メニューの中なので
                        // 画面の行は 1 行も増えず、いま選んでいるものにチェックが付く。
                        // 並びも文言もコア (setlistDisplayModes) が持つ。
                        setlistDisplayModes().forEach { option ->
                            DropdownMenuItem(
                                text = { Text(option.label) },
                                leadingIcon = {
                                    Icon(
                                        if (option.mode == displayMode) Icons.Filled.Check
                                        else Icons.AutoMirrored.Filled.List,
                                        null
                                    )
                                },
                                onClick = {
                                    menuOpen = false
                                    viewModel.setDisplayMode(option)
                                }
                            )
                        }
                        if (canShowEditActions) {
                            DropdownMenuItem(
                                text = { Text("セトリを編集") },
                                leadingIcon = { Icon(Icons.Filled.Edit, null) },
                                onClick = { menuOpen = false; startEdit() }
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("セトリの編集履歴") },
                            leadingIcon = { Icon(Icons.Filled.History, null) },
                            onClick = { menuOpen = false; showHistorySheet = true }
                        )
                    }
                }
            )
        }
    ) { innerPadding ->
        if (uiState.isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            val isCharacterLive = uiState.isCharacterLive
            val seedHex = BrandColors.hex(uiState.brandId)
            // 公演前か。「今日」は JST 固定 (JstDay) — 端末ローカルの TZ で判定すると
            // 海外にいるユーザーだけ 1 日ずれる。
            val isFuture = uiState.show?.date?.let { JstDay.isTodayOrLater(it) } ?: false

            // 出すタブ。セトリのある公演・過去の公演はセットリスト、未来の公演は予想、どの公演にも情報。
            val tabs = remember(hasSetlist, isFuture) {
                buildList {
                    if (hasSetlist || !isFuture) add(ShowTab.SETLIST)
                    if (isFuture) add(ShowTab.PREDICTION)
                    add(ShowTab.INFO)
                }
            }
            // いま中身を出すタブ。選んでいたタブが出せないとき (未来の公演でセトリがまだ無い等) は先頭。
            // シンプル表示はタブ自体を畳むので、情報ではなくセットリスト (無ければ予想) を出す。
            val candidates = if (simpleMode) tabs.filter { it != ShowTab.INFO } else tabs
            val currentTab = if (selectedTab in candidates) selectedTab else candidates.firstOrNull() ?: ShowTab.SETLIST

            val listState = rememberLazyListState()
            // タブの見出しが何番目の行か (見えている間に覚えておく。上へ流れると見える行から消えるため)。
            var tabsIndex by remember { mutableIntStateOf(-1) }
            LaunchedEffect(listState) {
                snapshotFlow { listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == "tabs" }?.index }
                    .collect { if (it != null) tabsIndex = it }
            }
            // タブを替えたら、前のタブで下まで流していても次のタブは頭 (タブの見出しの下) から見せる。
            LaunchedEffect(currentTab) {
                val idx = tabsIndex
                if (idx >= 0 && (idx < listState.firstVisibleItemIndex ||
                        (idx == listState.firstVisibleItemIndex && listState.firstVisibleItemScrollOffset > 0))
                ) listState.scrollToItem(idx)
            }
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
            ) {
                item(key = "head") {
                    // 上の階層 (ブランド → イベント) へのパンくず。ナビの戻るは「どこから来たか」
                    // しか辿れない (深リンクや検索から直接開くと戻り先が無い)。この画面がライブの
                    // 木のどこに居るのかを示して、上の階層へ直接行けるようにする。
                    // 現在地 (公演) はすぐ下の大見出しが言うので、ここには出さない。
                    // 会場の詳しいこと (キャパ・配信) とチケットは情報タブへ。
                    Column(
                        Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap),
                        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
                    ) {
                        uiState.show?.eventId?.let { eventId ->
                            if (uiState.eventName.isNotEmpty()) {
                                SetlistBreadcrumb(
                                    brandName = uiState.brandShortName,
                                    eventName = uiState.eventName,
                                    accent = imasTheme(seedHex, null).accent,
                                    onBrandClick = {
                                        uiState.brandId?.let {
                                            onFilteredEventsClick(EventFilterKind.BRAND, it)
                                        }
                                    },
                                    onEventClick = { onEventClick(eventId) }
                                )
                            }
                        }
                        ImasText(uiState.show?.name ?: "", role = ImasTextRole.HERO_TITLE)
                        uiState.show?.let { show ->
                            val sub = listOfNotNull(
                                uiState.venues.displayName(show) ?: show.venue?.takeIf { it.isNotBlank() },
                                show.date.takeIf { it.isNotBlank() }
                            ).joinToString(" ・ ")
                            if (sub.isNotEmpty()) {
                                ImasNote(sub, modifier = Modifier.padding(top = 2.dp))
                            }
                        }
                    }
                }

                if (!simpleMode) {
                    item(key = "mark_bar") {
                        UserMarkBar(
                            attendedLabel = marks.attendance?.let { "参加 (${it.label})" } ?: "参加",
                            attendedOn = marks.attendance != null,
                            onAttendedClick = { showAttendanceDialog = true },
                            favoriteOn = marks.favoriteOn,
                            onFavoriteClick = viewModel::toggleFavorite,
                            note = marks.note,
                            onNoteChange = viewModel::setNote,
                            seat = marks.seat,
                            onSeatChange = viewModel::setSeat,
                            seed = seedHex,
                            modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
                        )
                    }
                    item(key = "tabs") {
                        ImasTabs(
                            labels = tabs.map { it.label },
                            selection = tabs.indexOf(currentTab).coerceAtLeast(0),
                            onSelect = { index -> tabs.getOrNull(index)?.let { selectedTab = it } },
                            seed = seedHex,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
                        )
                    }
                }

                when (currentTab) {
                    ShowTab.SETLIST -> setlistTabContent(
                        uiState = uiState,
                        hasSetlist = hasSetlist,
                        simpleMode = simpleMode,
                        isSignedIn = isSignedIn,
                        onLoginClick = viewModel::requestLogin,
                        canShowEditActions = canShowEditActions,
                        seedHex = seedHex,
                        onStartEdit = { startEdit() },
                        performerName = performerName,
                        isCharacterLive = isCharacterLive,
                        likes = likes,
                        viewModel = viewModel,
                        onSongClick = onSongClick,
                        onIdolClick = onIdolClick
                    )
                    ShowTab.PREDICTION -> {
                        item(key = "prediction") {
                            SetlistPredictionSection(showId = showId, seed = seedHex)
                        }
                        if (!hasSetlist) {
                            item(key = "prediction_empty") {
                                ImasEmptyState(
                                    icon = Icons.Filled.Schedule,
                                    title = "公演前です",
                                    message = "セトリは公演後に登録されます",
                                    seed = seedHex
                                )
                            }
                        }
                    }
                    ShowTab.INFO -> {
                        uiState.show?.let { show ->
                            item(key = "venue_date") {
                                VenueDateCard(
                                    show = show,
                                    venues = uiState.venues,
                                    brandId = uiState.brandId,
                                    onFilteredShowsClick = onFilteredShowsClick
                                )
                            }
                        }
                        if (uiState.tickets.isNotEmpty()) {
                            item(key = "tickets") {
                                TicketCard(tickets = uiState.tickets, brandId = uiState.brandId)
                            }
                        }
                    }
                }
            }
        }
    }

    if (showAttendanceDialog) {
        AttendanceDialog(
            current = marks.attendance,
            onDismiss = { showAttendanceDialog = false },
            onSelect = { type ->
                showAttendanceDialog = false
                viewModel.setAttendance(type)
            }
        )
    }

    if (showLoginPrompt) {
        CommunityLoginPromptDialog(
            message = "セトリの編集や 👍 での投票にはログインが必要です。",
            onDismiss = viewModel::dismissLoginPrompt
        )
    }

    val editingShow = uiState.show
    if (showEditDialog && editingShow != null) {
        Dialog(
            onDismissRequest = { showEditDialog = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            SetlistEditScreen(
                show = editingShow,
                eventName = uiState.eventName,
                onDismiss = { showEditDialog = false },
                onSaved = {
                    showEditDialog = false
                    viewModel.reload()
                }
            )
        }
    }

    if (showHistorySheet) {
        SetlistEditHistorySheet(
            showId = showId,
            showName = uiState.show?.name.orEmpty(),
            onDismiss = { showHistorySheet = false }
        )
    }
}

/**
 * セットリストタブの中身: 👍 の案内 (シンプル表示では出さない) → 自分の回収の要約 →
 * セトリ本体 (未登録なら「セトリ未登録」の空状態)。
 */
@OptIn(ExperimentalFoundationApi::class)
private fun LazyListScope.setlistTabContent(
    uiState: SetlistUiState,
    hasSetlist: Boolean,
    simpleMode: Boolean,
    isSignedIn: Boolean,
    onLoginClick: () -> Unit,
    canShowEditActions: Boolean,
    seedHex: String?,
    onStartEdit: () -> Unit,
    performerName: PerformerNameMode,
    isCharacterLive: Boolean,
    likes: Map<String, SetlistLikeService.LikeEntry>,
    viewModel: SetlistViewModel,
    onSongClick: (String) -> Unit,
    onIdolClick: (String) -> Unit
) {
    if (!hasSetlist) {
        item(key = "empty") {
            // セットリストタブは過去の公演かセトリのある公演だけに出るので、ここに来る時点で
            // 必ず過去の公演 (未来でセトリ未登録なら予想タブに回る)。
            ImasEmptyState(
                icon = Icons.Filled.MusicNote,
                title = "セトリ未登録",
                message = "このライブのセトリはまだ登録されていません。ログインして編集に参加できます",
                seed = seedHex,
                actionTitle = if (canShowEditActions) "セトリを追加" else null,
                onAction = if (canShowEditActions) onStartEdit else null
            )
        }
        return
    }

    // 投票導線。シンプル表示では出さない — 行に 👍 自体が無く、スクショに誘導文が写り込むだけになる。
    if (!simpleMode) {
        item(key = "vote_note") {
            VoteHintRow(isSignedIn = isSignedIn, onLoginClick = onLoginClick)
        }
    }

    // 自分の回収の要約。セトリの真上に置いて、この下の並びの読み方を先に言う。
    // 出すかどうかも文言も共有コアが決める (null なら何も出さない)。
    uiState.collectionSummary?.let { summary ->
        item(key = "collection_summary") {
            CollectionSummaryRow(summary = summary)
        }
    }

    uiState.sections.forEachIndexed { sectionIndex, section ->
        // 同じ見出しが 2 度来ても鍵がぶつからないよう、塊の順番を鍵にする。
        stickyHeader(key = "section_$sectionIndex") {
            Surface(color = DS.surface2, modifier = Modifier.fillMaxWidth()) {
                ImasSectionHeader(title = section.sectionName, tight = true)
            }
        }
        item(key = "section_items_$sectionIndex") {
            // セクションの曲を 1 枚の紙にまとめ、切り取り線で区切る (セトリ・申込書と同じ紙面)。
            ImasCardList(
                style = ImasCardListStyle.SHEET,
                modifier = Modifier.padding(horizontal = DS.Space.screen)
            ) {
                section.items.forEachIndexed { index, item ->
                    if (index > 0) ImasRowDivider(inset = if (simpleMode) 38.dp else 72.dp)
                    val performers = uiState.performersByItemId[item.id] ?: emptyList()
                    val meta = uiState.rowMetaByItemId[item.id]
                    if (simpleMode) {
                        SetlistSimpleRow(
                            item = item,
                            displayNumber = index + 1,
                            performerLabel = meta?.performerLabel.orEmpty(),
                            brandHex = BrandColors.hex(item.songBrandId) ?: seedHex,
                            onClick = { onSongClick(item.songId) }
                        )
                    } else {
                        SetlistItemRow(
                            item = item,
                            displayNumber = index + 1,
                            performers = performers,
                            idolsById = uiState.idolsById,
                            unitNames = meta?.unitNames.orEmpty(),
                            isFullCast = meta?.isFullCast == true,
                            lineup = meta?.lineup,
                            performerNotes = meta?.performerNotes.orEmpty(),
                            absentOriginals = meta?.absentOriginals.orEmpty(),
                            absentHeading = meta?.absentOriginalsHeading.orEmpty(),
                            noteGroups = meta?.noteGroups.orEmpty(),
                            performerName = performerName,
                            isCharacterLive = isCharacterLive,
                            showName = uiState.show?.name,
                            showDate = uiState.show?.date,
                            // 感想カードの差し色。公演のブランドカラーを hex で渡す
                            // (ブランド ID のままだと色エンジンがニュートラルへ落ちる)。
                            seed = seedHex,
                            likeEntry = likes[item.songId],
                            onToggleLike = { viewModel.toggleLike(item.songId) },
                            onSongClick = { onSongClick(item.songId) },
                            onIdolClick = { idolId -> onIdolClick(idolId) }
                        )
                    }
                }
            }
        }
    }
}

/**
 * この公演への参加形態を選ぶダイアログ。
 *
 * 現地 / 配信 / LV の 3 形態を常に出す (`AttendanceType.options`)。開催情報の
 * has_streaming / has_live_viewing でフィルタしないのは、その列が欠落しやすく、
 * 「過去に LV 参加したのに記録できない」ほうが体験上の損失が大きいから
 * (iOS `AttendanceAvailability` と同じ判断)。選択中の形態をもう一度押すと不参加に戻る。
 */
@Composable
private fun AttendanceDialog(
    current: AttendanceType?,
    onDismiss: () -> Unit,
    onSelect: (AttendanceType?) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("この公演への参加") },
        text = {
            Column {
                AttendanceType.options().forEach { type ->
                    val on = current == type
                    Text(
                        if (on) "${type.label}で参加 (取り消す)" else "${type.label}で参加",
                        fontSize = 15.sp,
                        fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                        color = if (on) DS.ink else DS.ink2,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(if (on) null else type) }
                            .padding(vertical = 12.dp)
                    )
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("キャンセル") } }
    )
}

/**
 * ブランド → イベント のパンくず。現在地 (公演) はすぐ下の大見出しが言うので、
 * ここには出さない (同じ名前を 2 度書かない)。
 *
 * 名前が長いイベント (「THE IDOLM@STER MILLION LIVE! 14thLIVE」等) があるので、
 * 1 行に収めて末尾を詰める。畳んだ先は見出しと会場カードが補う。
 */
@Composable
private fun SetlistBreadcrumb(
    brandName: String?,
    eventName: String,
    accent: Color,
    onBrandClick: () -> Unit,
    onEventClick: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        if (brandName != null) {
            Text(
                text = brandName,
                fontSize = 12.sp,
                color = accent,
                maxLines = 1,
                modifier = Modifier.clickable(onClick = onBrandClick)
            )
            Text(text = "›", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
        }
        Text(
            text = eventName,
            fontSize = 12.sp,
            color = accent,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).clickable(onClick = onEventClick)
        )
    }
}

/** 「👍 で投票しよう」の案内 (未ログインならログイン導線)。 */
@Composable
private fun VoteHintRow(isSignedIn: Boolean, onLoginClick: () -> Unit) {
    ImasNote(
        text = if (isSignedIn) "良かったと思った曲に 👍 で投票しよう！" else "👍 で投票するにはログインが必要です",
        icon = Icons.Filled.ThumbUp,
        modifier = Modifier
            .fillMaxWidth()
            .then(if (isSignedIn) Modifier else Modifier.clickable(onClick = onLoginClick))
            .padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
    )
}

/**
 * **この披露についての事実**の段 (詳細表示のときだけ中身が来る)。
 *
 * ```text
 * ────────────────────────
 * 披露   3 回目   2 年 6 か月ぶり
 * 回収   初回収
 * ```
 *
 * 歌唱者との間にヘアラインを 1 本引いて、「この曲が何か」と「この披露がどうだったか」を
 * 別のブロックとして読ませる。軸の名前は固定幅で左に置くので、39 曲のセトリでも
 * 同じ位置に同じ軸が来る (縦に流し読みできる)。軸の分け方・ラベル・順・強調は
 * すべて共有コアが決める (`setlist_row_note_groups`) — ここは並べるだけ。
 */
@Composable
private fun NoteGroupsBlock(
    noteGroups: List<SetlistRowNoteGroupRecord>,
    seed: String?,
    onOpenPerformers: () -> Unit
) {
    if (noteGroups.isEmpty()) return
    val accent = imasTheme(seed, null).accent
    Column(
        modifier = Modifier.padding(top = 1.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        // 行の境目の切り取り線とは別物 (前と同じ 0.5dp の一本線)。ImasRowDivider は
        // 周りの ImasCardList(SHEET) の切り取り線スタイルを継いでしまい、行の境目と見分けが付かない。
        Box(
            Modifier
                .padding(bottom = 2.dp)
                .fillMaxWidth()
                .height(0.5.dp)
                .background(DS.sep)
        )
        noteGroups.forEach { group ->
            // 「13 人 初歌唱」のように人数でしか言えない段は、押すと歌唱者の一覧 (1 人ずつの札つき) を開く。
            // 押せるかは共有コアが決める (`opensPerformers`)。押せる段は末尾に矢印を添える。
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = if (group.opensPerformers) {
                    Modifier.imasPress(onClickLabel = "歌唱者の一覧を開く", onClick = onOpenPerformers)
                } else {
                    Modifier
                }
            ) {
                // 軸ラベル。固定幅・字間を少し開けて沈める (本文と張り合わない)。
                Text(
                    text = group.label,
                    fontSize = 11.sp,
                    letterSpacing = 0.4.sp,
                    color = DS.ink3,
                    modifier = Modifier.width(26.dp)
                )
                NoteGroupValues(notes = group.notes, accent = accent, modifier = Modifier.weight(1f), opens = group.opensPerformers)
            }
        }
    }
}

/**
 * 1 つの軸の値を 1 本の [Text] に連結する。連結した `Text` は普通の文として折り返すので、
 * 幅が足りなくても語の途中で割れない (「1 年 1 か月 / ぶり」のような割れ方をしない)。
 *
 * 強調は共有コアが付けた [RowNoteTone] の対応表だけで決める。**判断はしない** — 色だけに
 * 意味を持たせず、自分の記録 (`MINE` / `MISSING`) には印 (チェック / 点線の丸) を添える。
 */
@Composable
private fun NoteGroupValues(
    notes: List<SetlistRowNoteRecord>,
    accent: Color,
    modifier: Modifier = Modifier,
    opens: Boolean = false
) {
    val text = buildAnnotatedString {
        notes.forEachIndexed { index, note ->
            if (index > 0) append("  ")
            when (note.tone) {
                RowNoteTone.VALUE ->
                    withStyle(SpanStyle(color = DS.ink, fontWeight = FontWeight.Medium)) { append(unbreakableNote(note.text)) }
                RowNoteTone.DETAIL ->
                    withStyle(SpanStyle(color = DS.ink3)) { append(unbreakableNote(note.text)) }
                RowNoteTone.DEBUT ->
                    withStyle(SpanStyle(color = accent, fontWeight = FontWeight.Bold)) { append(unbreakableNote(note.text)) }
                RowNoteTone.MINE -> {
                    appendInlineContent(MINE_MARK_ID, "[v]")
                    append(" ")
                    withStyle(SpanStyle(color = DS.success, fontWeight = FontWeight.SemiBold)) { append(unbreakableNote(note.text)) }
                }
                RowNoteTone.MISSING -> {
                    appendInlineContent(MISSING_MARK_ID, "[o]")
                    append(" ")
                    withStyle(SpanStyle(color = DS.ink2)) { append(unbreakableNote(note.text)) }
                }
            }
        }
        if (opens) withStyle(SpanStyle(color = DS.ink3, fontWeight = FontWeight.SemiBold)) { append(" ›") }
    }
    Text(
        text = text,
        fontSize = 12.sp,
        modifier = modifier,
        inlineContent = mapOf(
            MINE_MARK_ID to InlineTextContent(
                Placeholder(10.sp, 10.sp, PlaceholderVerticalAlign.TextCenter)
            ) { Icon(Icons.Filled.Check, contentDescription = null, tint = DS.success, modifier = Modifier.fillMaxSize()) },
            MISSING_MARK_ID to InlineTextContent(
                Placeholder(10.sp, 10.sp, PlaceholderVerticalAlign.TextCenter)
            ) {
                Icon(
                    Icons.Outlined.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = DS.ink3,
                    modifier = Modifier.fillMaxSize()
                )
            }
        )
    )
}

private const val MINE_MARK_ID = "mine_mark"
private const val MISSING_MARK_ID = "missing_mark"

/**
 * 公演の頭に出す「自分の回収」の要約 (「この公演で 12 曲回収・初回収 4 曲」
 * 「このセトリに未回収 7 曲」)。**出すかどうかも文言も共有コアが決める** — ここは
 * `summary.attended` でアイコンを選ぶだけ (文言を組み立てない)。
 *
 * 札 (`ImasBadge`) は 1 行の短い値向けで、長い文だと大きい文字設定で切れる。
 * ここは文なので折り返す `ImasNote` を使う (iOS 版と同じ判断)。
 */
@Composable
private fun CollectionSummaryRow(summary: ShowCollectionRecord) {
    ImasNote(
        text = summary.label,
        icon = if (summary.attended) Icons.Filled.Verified else Icons.Outlined.RadioButtonUnchecked,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
    )
}

/**
 * 会場 / キャパ / 配信 / 日付 のカード。会場と日付は「同じ条件の公演」への入口になる。
 *
 * 会場は ID で持つ (表記ゆれで同じ会場が分断されないように) ので、ID を持たない古い公演では
 * 押せない普通の行に落とす — 生の会場文字列でも引けはするが、押した先が表記ゆれで
 * 分断された一部だけになり、「この会場での公演」という約束を守れないため。
 * キャパはホール指定があればホール側を優先 ([VenueDirectory.capacity])。
 */
@Composable
private fun VenueDateCard(
    show: Show,
    venues: VenueDirectory,
    brandId: String?,
    onFilteredShowsClick: (String, String) -> Unit
) {
    ImasCardList(modifier = Modifier.padding(horizontal = DS.Space.screen)) {
        var shown = false
        val venueId = show.venueId?.takeIf { it.isNotEmpty() }
        val venueLabel = venues.displayName(show) ?: show.venue
        if (!venueLabel.isNullOrEmpty()) {
            ImasLabeledRow(
                key = "会場", value = venueLabel, brand = brandId,
                tappable = venueId != null,
                onClick = venueId?.let { id -> { onFilteredShowsClick(ShowFilterKind.VENUE, id) } }
            )
            shown = true
        }
        // キャパが分かる会場では規模も出す (ホール指定があればホール側を優先)。
        venues.capacity(show)?.let { cap ->
            if (shown) ImasRowDivider(inset = DS.Space.rowH)
            ImasLabeledRow(key = "キャパ", value = "%,d人".format(cap), mono = true, brand = brandId)
            shown = true
        }
        show.streamPlatform?.takeIf { it.isNotBlank() }?.let { stream ->
            if (shown) ImasRowDivider(inset = DS.Space.rowH)
            ImasLabeledRow(key = "配信", value = stream, brand = brandId)
            shown = true
        }
        if (show.date.isNotEmpty()) {
            if (shown) ImasRowDivider(inset = DS.Space.rowH)
            ImasLabeledRow(
                key = "日付", value = show.date, brand = brandId, tappable = true,
                onClick = { onFilteredShowsClick(ShowFilterKind.DATE, show.date) }
            )
        }
    }
}

/**
 * この公演のチケット価格。iOS `SetlistView` の情報タブのチケット区画と対。
 *
 * 券種の絞り込み・並び・価格帯・推定の札は共有コア (`domain/ticket_prices.rs`) が
 * 一本で決める。ここは受け取ったものをそのまま並べるだけ。
 */
@Composable
private fun TicketCard(tickets: List<ShowTicket>, brandId: String?) {
    val coreTickets = remember(tickets) { tickets.map { it.toCore() } }
    val ranges = remember(coreTickets) { ticketPriceRanges(coreTickets) }
    Column(
        Modifier.fillMaxWidth().padding(top = DS.Space.gap),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        ImasSectionHeader(title = "チケット", tight = true)
        ImasCardList(modifier = Modifier.padding(horizontal = DS.Space.screen)) {
            ranges.forEachIndexed { rangeIndex, range ->
                if (rangeIndex > 0) ImasRowDivider(inset = DS.Space.rowH)
                val kindTickets = ticketsForKind(coreTickets, range.kind)
                // 券種が 1 つだけの形態は帯を出さない (「配信 ¥6,500」が 2 行並んで、
                // 同じ数字を 2 回読ませることになる)。
                val showsBand = range.count.toInt() > 1
                if (showsBand) {
                    ImasLabeledRow(
                        key = ticketKindLabel(range.kind),
                        value = if (range.hasEstimate) "${range.label} (推定含む)" else range.label,
                        brand = brandId
                    )
                }
                kindTickets.forEachIndexed { index, ticket ->
                    if (showsBand || index > 0) {
                        ImasRowDivider(inset = if (showsBand) DS.Space.rowH + 16.dp else DS.Space.rowH)
                    }
                    ImasLabeledRow(
                        key = if (showsBand) {
                            if (ticket.isEstimate) "${ticket.name} (推定)" else ticket.name
                        } else {
                            "${ticketKindLabel(range.kind)}・${ticket.name}"
                        },
                        value = formatYen(ticket.price),
                        brand = brandId
                    )
                }
            }
        }
    }
}

/**
 * セトリの「シンプル表示」1 行。iOS `SetlistSimpleRowView` の移植。
 *
 * 通常行はジャケ写・👍・出演者チップを載せて 1 曲 80dp 前後になり、20 曲超のライブでは
 * 3 画面ぶんスクロールが要る。この行は公式のセトリ画像と同じ **番号・曲名・演者名だけ**に
 * 絞って 1 曲 40dp 前後に収める。曲名をブランド色で出すので、色だけで所属が読み取れる。
 */
@Composable
private fun SetlistSimpleRow(
    item: SetlistRow,
    displayNumber: Int,
    performerLabel: String,
    brandHex: String?,
    onClick: () -> Unit
) {
    val titleColor = brandHex?.let { imasTheme(it, null).accent } ?: DS.ink
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top
    ) {
        // 番号は幅を固定して曲名の頭を揃える (等幅数字。二桁で桁が動くと読みにくい)。
        Text(
            text = displayNumber.toString().padStart(2, '0'),
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace,
            color = DS.ink3,
            textAlign = TextAlign.End,
            modifier = Modifier.width(22.dp).padding(top = 2.dp)
        )
        Column(Modifier.weight(1f)) {
            Text(
                text = item.songTitle,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = titleColor,
                maxLines = 2
            )
            if (performerLabel.isNotEmpty()) {
                // 公式のセトリ画像に倣って ♪ を頭に置く。演者を横に並べると長い名前で
                // 曲名が潰れるので下段に置く。
                //
                // 披露の履歴と自分の回収はこの行には出ない (コアがシンプル表示では
                // 空を返す)。1 枚のスクショに収めるための形なので、行を増やさない。
                Text(
                    text = "♪ $performerLabel",
                    fontSize = 11.sp,
                    color = DS.ink2,
                    maxLines = 2
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
private fun SetlistItemRow(
    item: SetlistRow,
    displayNumber: Int,
    performers: List<PerformerRow>,
    /** 歌唱者のアイコン (写真か判子) に要る略称・実体。id → Idol。 */
    idolsById: Map<String, Idol>,
    /**
     * ユニット名の札に出す名前。**どのユニット名を出すかはコアが決める**
     * (その披露の名義 → 曲の名義 → 顔ぶれ推論)。空なら札を出さない。
     */
    unitNames: List<String>,
    /** 出演者全員で歌う行 (「全員」の札)。判定は共有コア。 */
    isFullCast: Boolean,
    /**
     * 原唱者 (オリメン) との関係の札。**付けるか・文言は共有コアが決める**
     * (`SetlistRowMetaRecord.lineup`)。null なら付けない。
     */
    lineup: SetlistLineupNote?,
    /**
     * 歌唱者 1 人ずつの札 (`オリメン` / `初歌唱`)。歌唱者の一覧シートで名前の下に出す。
     * 付けるか・言葉は共有コア (`SetlistRowMetaRecord.performerNotes`)。
     */
    performerNotes: List<SetlistPerformerNoteRecord> = emptyList(),
    /** この行で歌っていないオリメンと見出し。歌唱者の一覧シートの下に並べる (共有コアが決める)。 */
    absentOriginals: List<SetlistAbsentOriginalRecord> = emptyList(),
    absentHeading: String = "",
    /**
     * この披露についての事実を、軸 (`披露` / `回収`) ごとにまとめたもの。
     * **軸の分け方も、ラベルも、順も、どれを強く見せるか (`tone`) も共有コアが決める**
     * ので、ここは受け取った順に並べるだけ。詳細表示以外では必ず空で来る。
     *
     * 丸い札にはしない。曲の属性 (カバー・ユニット名) と同じ形で並べると 1 行に丸が
     * 何個も並び、構造にならない。軸の名前を左に固定幅で置き、値を右に流す
     * ([`NoteGroupsBlock`])。
     */
    noteGroups: List<SetlistRowNoteGroupRecord> = emptyList(),
    performerName: PerformerNameMode,
    isCharacterLive: Boolean,
    showName: String?,
    showDate: String?,
    seed: String?,
    likeEntry: SetlistLikeService.LikeEntry?,
    onToggleLike: () -> Unit,
    onSongClick: () -> Unit,
    onIdolClick: (String) -> Unit
) {
    // 長押し → 感想カード (曲名 + コメントのシェア画像) を作る。
    // 曲名タップは従来どおり曲詳細なので、行そのものの長押しに逃がしている。
    var showCommentShare by remember { mutableStateOf(false) }
    // 歌唱者のアイコンを重ねた束を押したときに開く一覧 (人ごとの遷移はここから)。
    var showPerformersSheet by remember { mutableStateOf(false) }
    // セトリ・DS の「歌唱者はアイコンを重ねる」の素 (写真か判子。略称は Idol.shortName)。
    val rowPerformers = remember(performers, idolsById, performerName, isCharacterLive) {
        performers.map { p ->
            ImasPerformer(
                id = p.id,
                name = p.displayName(performerName, isCharacterLive).joined(),
                color = p.idolColor,
                iconLabel = p.idolId?.let { idolsById[it]?.shortName },
                entityId = p.idolId
            )
        }
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                // 空タップにリップルだけ出て何も起きないのを避けるため、
                // 行のどこを押しても曲名タップと同じ挙動にしておく。
                onClick = onSongClick,
                onLongClick = { showCommentShare = true }
            )
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top
    ) {
        // Position number
        Text(
            text = "$displayNumber",
            style = MaterialTheme.typography.bodySmall,
            color = DS.ink2.copy(alpha = 0.6f),
            modifier = Modifier
                .width(28.dp)
                .padding(top = 2.dp),
            textAlign = TextAlign.End
        )

        // Artwork with preview
        ArtworkImage(
            url = item.artworkUrl,
            size = 44.dp,
            previewUrl = item.previewUrl,
            songTitle = item.songTitle, songId = item.songId
        )

        // Content column
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            // Song title — tap navigates to SongDetail
            Text(
                text = item.songTitle,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clickable(onClick = onSongClick)
            )

            // 「この曲が何か」の札 (ユニット名)。名前はコアが決めた文字列で、ここは並べるだけ。
            //
            // 披露の履歴と自分の回収はここに入れない ([`NoteGroupsBlock`])。同じ形の札で
            // 混ぜると「ユニット名」と「4 回目」が同じ重みに見えて、行が札の羅列になる。
            // オリメンの札・ユニット名 (無ければ「全員」) を 1 列に回り込ませる。
            val tagNames = unitNames.ifEmpty { if (isFullCast) listOf("全員") else emptyList() }
            if (lineup != null || tagNames.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    lineup?.let { ImasBadge(it.label, kind = it.kind.toBadgeKind()) }
                    val tagKind = if (unitNames.isNotEmpty()) ImasBadgeKind.UNIT else ImasBadgeKind.ALL
                    tagNames.forEach { name -> ImasBadge(name, kind = tagKind) }
                }
            }

            // 歌唱者。アイドルが分かる人がいればアイコンを重ねて見せる (ユーザーの決まり
            // 「セトリの歌唱者はアイコンを重ねる」。iOS ImasSetlistRow/PerformerLine と同じ出し方)。
            // 重ねた束は人ごとに押せないので、タップで一覧を開いて個別の遷移はそこに残す。
            if (performers.isNotEmpty()) {
                if (rowPerformers.any { it.iconLabel != null || it.imageUrl != null || it.entityId != null }) {
                    ImasAvatarStack(
                        people = rowPerformers,
                        onTap = { showPerformersSheet = true }
                    )
                } else {
                    // アイドルに結び付かない歌唱者だけの行 (アイコンの手がかりが無い)。前と同じ名前チップ。
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        performers.forEach { performer ->
                            PerformerChip(
                                name = performer.displayName(performerName, isCharacterLive),
                                idolColorHex = performer.idolColor,
                                modifier = Modifier.clickable(enabled = performer.idolId != null) {
                                    performer.idolId?.let { onIdolClick(it) }
                                }
                            )
                        }
                    }
                }
            }

            // 「この披露はどうだったか」(披露の履歴・自分の回収) の段。
            NoteGroupsBlock(noteGroups = noteGroups, seed = seed, onOpenPerformers = { showPerformersSheet = true })

            // Notes
            if (item.notes != null) {
                Text(
                    text = item.notes,
                    style = MaterialTheme.typography.bodySmall,
                    color = DS.ink2
                )
            }
        }

        LikeButton(entry = likeEntry, onClick = onToggleLike)
    }

    if (showCommentShare) {
        SetlistCommentComposeSheet(
            songTitle = item.songTitle,
            showName = showName,
            showDate = showDate,
            seed = seed,
            artworkUrl = item.artworkUrl,
            onDismiss = { showCommentShare = false }
        )
    }
    if (showPerformersSheet) {
        PerformerListSheet(
            songTitle = item.songTitle,
            performers = performers,
            idolsById = idolsById,
            notesByIdolId = performerNotes.associate { it.idolId to it.notes },
            // 札のある人をコアの順 (初歌唱 → オリメン) で頭に寄せ、札の無い人は元の並びで続ける
            // (「13 人 初歌唱」を押して開いたとき、その 13 人が先頭に来る。iOS `sheetPerformers`)。
            noteOrder = performerNotes.mapIndexed { i, n -> n.idolId to i }.toMap(),
            absentOriginals = absentOriginals,
            absentHeading = absentHeading,
            performerName = performerName,
            isCharacterLive = isCharacterLive,
            onSelectIdol = { idolId ->
                showPerformersSheet = false
                onIdolClick(idolId)
            },
            onDismiss = { showPerformersSheet = false }
        )
    }
}

/**
 * 歌唱者の一覧シート (iOS `PerformerDetailSheet`)。アイコンの束は人数ぶん重なって個別に押せないので、
 * ここから名前を選んで個別のアイドル詳細へ遷移する (人ごとの遷移はこの一覧に残す)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PerformerListSheet(
    songTitle: String,
    performers: List<PerformerRow>,
    idolsById: Map<String, Idol>,
    /** idol_id → その人の札 (`オリメン` / `初歌唱`)。付けるか・言葉・強さは共有コア。 */
    notesByIdolId: Map<String, List<SetlistRowNoteRecord>>,
    /** idol_id → 一覧で先に出す順。入っていない人は元の並びで後ろ。 */
    noteOrder: Map<String, Int>,
    /** この行で歌っていないオリメン。一覧の下に [absentHeading] の見出しで並べる (行には書かない)。 */
    absentOriginals: List<SetlistAbsentOriginalRecord>,
    absentHeading: String,
    performerName: PerformerNameMode,
    isCharacterLive: Boolean,
    onSelectIdol: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
            verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
        ) {
            // 頭: 印字 (何の一覧か・何人か) と曲名 (iOS `PerformerDetailSheet.header`)。
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                ImasMasthead("SINGERS", "${performers.size} 名")
                ImasText(songTitle, role = ImasTextRole.SECTION_TITLE)
            }
            val ordered = remember(performers, noteOrder) {
                performers.sortedBy { p -> p.idolId?.let { noteOrder[it] } ?: Int.MAX_VALUE }
            }
            // 刷られた紙 (行の間は切り取り線)。セトリと同じ紙で並べる。
            ImasCardList(items = ordered, key = { it.id }, style = ImasCardListStyle.SHEET) { performer ->
                val name = performer.displayName(performerName, isCharacterLive)
                val idol = performer.idolId?.let { idolsById[it] }
                val notes = performer.idolId?.let { notesByIdolId[it] }.orEmpty()
                ImasRow(
                    title = name.primary,
                    subtitle = name.secondary,
                    leading = ImasRowLeading.Avatar(
                        label = idol?.shortName ?: name.primary,
                        seed = performer.idolColor,
                        entityId = performer.idolId
                    ),
                    trailing = ImasRowTrailing.Chevron,
                    density = ImasRowDensity.COMPACT,
                    titleLineLimit = 1,
                    modifier = Modifier.imasRowPress(enabled = performer.idolId != null) {
                        performer.idolId?.let(onSelectIdol)
                    },
                    detail = if (notes.isNotEmpty()) ({ ImasNoteBadges(notes) }) else null
                )
            }
            // 歌っていないオリメン。歌唱者と同じ紙に並べ、見出しで分ける (iOS `absentSection`)。
            if (absentOriginals.isNotEmpty()) {
                ImasText(absentHeading, role = ImasTextRole.SECTION_LABEL)
                ImasCardList(items = absentOriginals, key = { it.idolId }, style = ImasCardListStyle.SHEET) { original ->
                    ImasRow(
                        title = original.name,
                        leading = ImasRowLeading.Avatar(
                            label = original.shortName,
                            seed = original.color,
                            entityId = original.idolId
                        ),
                        trailing = ImasRowTrailing.Chevron,
                        density = ImasRowDensity.COMPACT,
                        titleLineLimit = 1,
                        modifier = Modifier.imasRowPress { onSelectIdol(original.idolId) }
                    )
                }
            }
        }
    }
}

/** オリメンの札の色区分。`ImasBadgeKind.ALL/COVER/PARTIAL` は iOS 版の対応と同じ (色では分けない)。 */
private fun Lineup.toBadgeKind(): ImasBadgeKind = when (this) {
    Lineup.ORIGINAL, Lineup.ORIGINAL_PLUS -> ImasBadgeKind.ALL
    Lineup.PARTIAL -> ImasBadgeKind.PARTIAL
    Lineup.COVER -> ImasBadgeKind.COVER
}

/**
 * 1 曲ぶんの「良かった」ボタン + 票数。
 *
 * 票が 0 の曲でも数字を出さないだけでボタンは常に出す — 押せる曲と押せない曲が
 * 混ざると「この曲には投票できない」と読めてしまうため。
 */
@Composable
private fun LikeButton(entry: SetlistLikeService.LikeEntry?, onClick: () -> Unit) {
    val liked = entry?.hasUserLiked == true
    val count = entry?.likeCount ?: 0
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.padding(top = 2.dp)
    ) {
        IconButton(onClick = onClick, modifier = Modifier.size(40.dp)) {
            Icon(
                if (liked) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
                contentDescription = if (liked) "Good を取り消す" else "この曲が良かった",
                tint = if (liked) DS.pick else DS.ink3,
                modifier = Modifier.size(18.dp)
            )
        }
        if (count > 0) {
            Text("$count", fontSize = 10.sp, color = DS.ink3)
        }
    }
}
