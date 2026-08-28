package com.fugaif.imaslivedb.ui.events

import android.content.Context
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.auth.canEdit
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.PerformerRow
import com.fugaif.imaslivedb.data.model.SetlistRow
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.components.GradientHeader
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLabeledRow
import com.fugaif.imaslivedb.ui.components.PerformerChip
import com.fugaif.imaslivedb.ui.edit.SetlistEditScreen
import com.fugaif.imaslivedb.ui.filtered.ShowFilterKind
import com.fugaif.imaslivedb.ui.share.SetlistCommentComposeSheet
import com.fugaif.imaslivedb.ui.theme.BrandPalette
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.brandColor
import kotlinx.coroutines.launch

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
    viewModel: SetlistViewModel = viewModel(key = showId)
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    val module = remember(context) { AppModule.from(context) }
    val marks = module.userMarkRepository
    val likeService = remember(context) { SetlistLikeService.get(context) }
    val authState by module.authService.state.collectAsState()
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる (data/auth/EditPermission.kt のヘッダ参照)。
    val canShowEditActions = remember(authState) { authState.showEditAffordance }
    val isSignedIn = remember(authState) { authState.canEdit }
    val scope = rememberCoroutineScope()

    // 会場名は「公演日時点の名前」で出す (改名前の公演は当時名)。解決には会場マスタが要るが、
    // この画面の担当範囲外である ViewModel は変えないのでここで 1 回だけ読む
    // (244 施設ぶんの小さなマスタで、公演ごとの引き直しはしない)。
    var venues by remember { mutableStateOf(VenueDirectory.EMPTY) }
    LaunchedEffect(Unit) { venues = module.eventRepository.fetchVenueDirectory() }

    LaunchedEffect(showId) { viewModel.load(context, showId) }

    // シンプル表示は公演をまたいで保持する。「1 枚のスクショに収めたい」人は
    // 次の公演でも同じ見方をするので、画面を離れるたびに戻ると毎回押し直しになる。
    var simpleMode by remember { mutableStateOf(SetlistViewPrefs.simpleMode(context)) }

    // --- マーク (参加 / お気に入り / メモ / 座席)。実体は Room なのでここで読み書きする ---
    var attendance by remember(showId) { mutableStateOf<AttendanceType?>(null) }
    var favoriteOn by remember(showId) { mutableStateOf(false) }
    var note by remember(showId) { mutableStateOf<String?>(null) }
    var seat by remember(showId) { mutableStateOf<String?>(null) }

    suspend fun reloadMarks() {
        attendance = marks.attendance(UserMark.SHOW, showId)
        favoriteOn = marks.isOn(UserMark.SHOW, showId, UserMark.FAVORITE)
        note = marks.note(UserMark.SHOW, showId)
        seat = marks.seat(UserMark.SHOW, showId)
    }
    LaunchedEffect(showId) { reloadMarks() }

    // --- 「良かった」投票 (post-vote)。セトリが埋まっている公演だけ取りに行く ---
    var likes by remember(showId) { mutableStateOf<Map<String, SetlistLikeService.LikeEntry>>(emptyMap()) }
    val hasSetlist = uiState.setlist.isNotEmpty()
    LaunchedEffect(showId, hasSetlist) {
        if (hasSetlist) likes = likeService.fetch(showId).associateBy { it.songId }
    }

    // セトリ編集シートに渡すイベント名 (編集画面の見出し)。
    var eventName by remember(showId) { mutableStateOf("") }
    LaunchedEffect(uiState.show?.eventId) {
        val id = uiState.show?.eventId ?: return@LaunchedEffect
        eventName = module.eventRepository.fetchEvent(id)?.name.orEmpty()
    }

    var menuOpen by remember { mutableStateOf(false) }
    var showAttendanceDialog by remember { mutableStateOf(false) }
    var showEditDialog by remember { mutableStateOf(false) }
    var showHistorySheet by remember { mutableStateOf(false) }
    var showLoginPrompt by remember { mutableStateOf(false) }

    /** 編集導線の共通ゲート。未ログインならログイン誘導、BAN は無反応 (導線自体を隠している)。 */
    fun startEdit() {
        authState.startCommunityEdit(promptLogin = { showLoginPrompt = true }) { showEditDialog = true }
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
                        DropdownMenuItem(
                            text = { Text(if (simpleMode) "通常表示に戻す" else "シンプル表示") },
                            leadingIcon = { Icon(Icons.AutoMirrored.Filled.List, null) },
                            onClick = {
                                menuOpen = false
                                simpleMode = !simpleMode
                                SetlistViewPrefs.setSimpleMode(context, simpleMode)
                            }
                        )
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
            val isCharacterLive = uiState.show?.isCharacterLive ?: false
            val seedHex = BrandPalette.hex(uiState.brandId)
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
            ) {
                item {
                    if (simpleMode) {
                        // シンプル表示ではヒーローと会場カードを畳み、会場・日付の 1 行に落とす。
                        // ここが 250dp 前後あり、残したままだと 20 曲超のセトリが 1 枚の
                        // スクショに収まらない (シンプル表示を作った意味が無くなる)。
                        Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp)) {
                            Text(
                                uiState.show?.name ?: "",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = DS.ink
                            )
                            uiState.show?.let { show ->
                                val sub = listOfNotNull(
                                    venues.displayName(show) ?: show.venue?.takeIf { it.isNotBlank() },
                                    show.date.takeIf { it.isNotBlank() }
                                ).joinToString(" ・ ")
                                if (sub.isNotEmpty()) {
                                    Text(sub, style = MaterialTheme.typography.bodySmall, color = DS.ink2)
                                }
                            }
                        }
                    } else {
                        Box(modifier = Modifier.fillMaxWidth()) {
                            GradientHeader(color = brandColor(uiState.brandId), height = 88.dp)
                            Column(modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 40.dp, bottom = 8.dp)) {
                                Text(
                                    uiState.show?.name ?: "",
                                    style = MaterialTheme.typography.titleLarge,
                                    fontWeight = FontWeight.Bold,
                                    color = DS.ink
                                )
                                uiState.show?.date?.let { d ->
                                    Text(d, style = MaterialTheme.typography.bodySmall, color = DS.ink2)
                                }
                            }
                        }
                    }
                }
                if (!simpleMode) {
                    uiState.show?.let { show ->
                        item(key = "venue_date") {
                            VenueDateCard(
                                show = show,
                                venues = venues,
                                brandId = uiState.brandId,
                                onFilteredShowsClick = onFilteredShowsClick
                            )
                        }
                        item(key = "mark_bar") {
                            UserMarkBar(
                                attendedLabel = attendance?.let { "参加 (${it.label})" } ?: "参加",
                                attendedOn = attendance != null,
                                onAttendedClick = { showAttendanceDialog = true },
                                favoriteOn = favoriteOn,
                                onFavoriteClick = {
                                    scope.launch {
                                        favoriteOn = marks.toggle(UserMark.SHOW, showId, UserMark.FAVORITE)
                                    }
                                },
                                note = note,
                                onNoteChange = { text ->
                                    scope.launch {
                                        marks.setNote(UserMark.SHOW, showId, text)
                                        note = marks.note(UserMark.SHOW, showId)
                                    }
                                },
                                seat = seat,
                                onSeatChange = { text ->
                                    scope.launch {
                                        marks.setSeat(UserMark.SHOW, showId, text)
                                        seat = marks.seat(UserMark.SHOW, showId)
                                    }
                                },
                                seed = seedHex,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                            )
                        }
                    }
                }

                if (!hasSetlist) {
                    item(key = "empty") {
                        // 公演前かどうかで文言と導線を変える。「今日」は JST 固定 (JstDay) —
                        // 端末ローカルの TZ で判定すると海外にいるユーザーだけ 1 日ずれる。
                        // 未来の公演に「セトリを追加」を出しても、まだ書ける中身が無い。
                        val isFuture = uiState.show?.date?.let { JstDay.isTodayOrLater(it) } ?: false
                        val canAdd = canShowEditActions && !isFuture
                        ImasEmptyState(
                            icon = Icons.Filled.MusicNote,
                            title = if (isFuture) "公演前です" else "セトリ未登録",
                            message = if (isFuture) "セトリは公演後に登録されます"
                            else "このライブのセトリはまだ登録されていません。ログインして編集に参加できます",
                            seed = seedHex,
                            actionTitle = if (canAdd) "セトリを追加" else null,
                            onAction = if (canAdd) ({ startEdit() }) else null
                        )
                    }
                }

                // 投票導線。シンプル表示では出さない — 行に 👍 自体が無く、
                // スクショに誘導文が写り込むだけになる。
                if (hasSetlist && !simpleMode) {
                    item(key = "vote_note") {
                        VoteHintRow(isSignedIn = isSignedIn, onLoginClick = { showLoginPrompt = true })
                    }
                }

                uiState.sections.forEach { section ->
                    stickyHeader(key = section.sectionName) {
                        Surface(
                            color = DS.surface2,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = section.sectionName,
                                style = MaterialTheme.typography.labelLarge,
                                color = DS.ink2,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
                            )
                        }
                    }

                    section.items.forEachIndexed { index, item ->
                        item(key = item.id) {
                            val performers = uiState.performersByItemId[item.id] ?: emptyList()
                            if (simpleMode) {
                                SetlistSimpleRow(
                                    item = item,
                                    displayNumber = index + 1,
                                    performerLabel = performerLabel(item, performers),
                                    brandHex = BrandPalette.hex(item.songBrandId) ?: seedHex,
                                    onClick = { onSongClick(item.songId) }
                                )
                            } else {
                                SetlistItemRow(
                                    item = item,
                                    displayNumber = index + 1,
                                    performers = performers,
                                    isCharacterLive = isCharacterLive,
                                    showName = uiState.show?.name,
                                    showDate = uiState.show?.date,
                                    // 感想カードの差し色。公演のブランドカラーを hex で渡す
                                    // (ブランド ID のままだと色エンジンがニュートラルへ落ちる)。
                                    seed = seedHex,
                                    likeEntry = likes[item.songId],
                                    onToggleLike = {
                                        toggleLike(
                                            scope = scope,
                                            likeService = likeService,
                                            showId = showId,
                                            songId = item.songId,
                                            current = likes[item.songId],
                                            onResult = { likes = likes + (it.songId to it) },
                                            onRequireLogin = { showLoginPrompt = true }
                                        )
                                    },
                                    onSongClick = { onSongClick(item.songId) },
                                    onIdolClick = { idolId -> onIdolClick(idolId) }
                                )
                            }
                            HorizontalDivider(modifier = Modifier.padding(start = if (simpleMode) 38.dp else 72.dp))
                        }
                    }
                }
            }
        }
    }

    if (showAttendanceDialog) {
        AttendanceDialog(
            current = attendance,
            onDismiss = { showAttendanceDialog = false },
            onSelect = { type ->
                showAttendanceDialog = false
                scope.launch {
                    marks.setAttendance(UserMark.SHOW, showId, type)
                    reloadMarks()
                }
            }
        )
    }

    if (showLoginPrompt) {
        CommunityLoginPromptDialog(
            message = "セトリの編集や 👍 での投票にはログインが必要です。",
            onDismiss = { showLoginPrompt = false }
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
                eventName = eventName,
                onDismiss = { showEditDialog = false },
                onSaved = {
                    showEditDialog = false
                    viewModel.load(context, showId)
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
 * 👍 のトグル。押した瞬間の状態から反転を決め、サーバが返した確定値で行を更新する。
 *
 * 送信前に「ログインしているか」を見て弾かないのは意図的 — セッション更新中の一瞬に
 * トークンが空になることがあり、そこで先回りして落とすと投票が無言で失敗する。
 * 認証が要るという判断はサーバの 401 に任せ、返ってきたときだけログイン誘導を出す。
 */
private fun toggleLike(
    scope: kotlinx.coroutines.CoroutineScope,
    likeService: SetlistLikeService,
    showId: String,
    songId: String,
    current: SetlistLikeService.LikeEntry?,
    onResult: (SetlistLikeService.LikeEntry) -> Unit,
    onRequireLogin: () -> Unit
) {
    scope.launch {
        try {
            val liked = current?.hasUserLiked == true
            val result = if (liked) likeService.unlike(showId, songId)
            else likeService.like(showId, songId)
            onResult(result)
        } catch (e: SetlistLikeService.Unauthorized) {
            onRequireLogin()
        } catch (e: Exception) {
            // 通信断などは黙る。次回 fetch で正しい状態に戻る。
        }
    }
}

/**
 * シンプル表示の演者ラベル。iOS の `performerLabel` と同じ優先順で決める:
 * ユニット単独曲ならユニット名 → それ以外は名前を「／」で連結。
 * 区切りが全角スラッシュなのは公式のセトリ画像に合わせているため。
 *
 * iOS にある「出演者全員なら『全員』」は、その判定に要る show_cast の集合を
 * Android のセトリ画面が読んでいないので出さない (名前が並ぶだけで壊れはしない)。
 */
private fun performerLabel(item: SetlistRow, performers: List<PerformerRow>): String {
    item.unitName?.takeIf { it.isNotBlank() }?.let { return it }
    return performers.joinToString("／") { it.idolName ?: it.name }
}

/** シンプル表示のオン/オフを端末に残す。画面をまたいで見方を保つためだけの 1 bit。 */
private object SetlistViewPrefs {
    private const val PREFS_NAME = "setlist_view_prefs"
    private const val KEY_SIMPLE = "simple_mode"

    fun simpleMode(context: Context): Boolean =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_SIMPLE, false)

    fun setSimpleMode(context: Context, value: Boolean) {
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_SIMPLE, value).apply()
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

/** 「👍 で投票しよう」の案内 (未ログインならログイン導線)。 */
@Composable
private fun VoteHintRow(isSignedIn: Boolean, onLoginClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (isSignedIn) Modifier else Modifier.clickable(onClick = onLoginClick))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(Icons.Filled.ThumbUp, contentDescription = null, tint = DS.pick, modifier = Modifier.size(14.dp))
        Text(
            if (isSignedIn) "良かったと思った曲に 👍 で投票しよう！"
            else "👍 で投票するにはログインが必要です",
            style = MaterialTheme.typography.bodySmall,
            color = DS.ink2
        )
    }
}

/**
 * 会場 / 日付のカード。どちらも「同じ条件の公演」への入口になる。
 *
 * 会場は ID で持つ (表記ゆれで同じ会場が分断されないように) ので、ID を持たない古い公演では
 * 押せない普通の行に落とす — 生の会場文字列でも引けはするが、押した先が表記ゆれで
 * 分断された一部だけになり、「この会場での公演」という約束を守れないため。
 */
@Composable
private fun VenueDateCard(
    show: Show,
    venues: VenueDirectory,
    brandId: String?,
    onFilteredShowsClick: (String, String) -> Unit
) {
    Column(
        Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth()
            .clip(RoundedCornerShape(14.dp)).background(DS.surface)
    ) {
        val venueId = show.venueId?.takeIf { it.isNotEmpty() }
        val venueLabel = venues.displayName(show) ?: show.venue
        if (!venueLabel.isNullOrEmpty()) {
            ImasLabeledRow(
                key = "会場", value = venueLabel, brand = brandId,
                tappable = venueId != null,
                onClick = venueId?.let { id -> { onFilteredShowsClick(ShowFilterKind.VENUE, id) } }
            )
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
        if (show.date.isNotEmpty()) {
            ImasLabeledRow(
                key = "日付", value = show.date, brand = brandId, tappable = true,
                onClick = { onFilteredShowsClick(ShowFilterKind.DATE, show.date) }
            )
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
    val titleColor = brandHex?.let { ImasTheme.derive(it, null, dark = true).accent } ?: DS.ink
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
            songTitle = item.songTitle
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

            // Unit name capsule
            if (item.unitName != null) {
                Surface(
                    shape = RoundedCornerShape(50),
                    color = DS.sys.copy(alpha = 0.1f)
                ) {
                    Text(
                        text = item.unitName,
                        style = MaterialTheme.typography.labelSmall,
                        color = DS.sys,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
                    )
                }
            }

            // Performer chips in FlowRow
            if (performers.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    performers.forEach { performer ->
                        PerformerChip(
                            name = performer.name,
                            idolName = performer.idolName,
                            idolColorHex = performer.idolColor,
                            isCharacterLive = isCharacterLive,
                            modifier = Modifier.clickable(enabled = performer.idolId != null) {
                                performer.idolId?.let { onIdolClick(it) }
                            }
                        )
                    }
                }
            }

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
