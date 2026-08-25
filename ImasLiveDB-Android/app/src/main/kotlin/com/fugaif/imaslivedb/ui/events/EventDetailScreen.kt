package com.fugaif.imaslivedb.ui.events

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLabeledRow
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.components.ImasStatTile
import com.fugaif.imaslivedb.ui.components.ImasTagChip
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * イベント詳細。iOS EventDetailView の構成を 1:1 で写す。
 * hero(アクセントバー + イベント名 + お気に入り/参加 + 参加予定チップ) の下を
 * ImasSegmented で [公演・セトリ][出演][情報] に切り替える。
 *
 * 披露ユニット表示 (unit 被覆判定) は Setlist 側の担当範囲と重複するため対象外。
 * ブランド/年度行はタップ遷移なし (Android 側にブランド絞り込み付き遷移経路が未整備)。
 * チケット編集・イベント編集・BD/DVD所有チェックは Android に対応する基盤 (編集権限/event_releases 同期) が
 * まだ無いため対象外。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventDetailScreen(
    eventId: String,
    onBack: () -> Unit,
    onShowClick: (String) -> Unit,
    onIdolClick: (String) -> Unit,
    viewModel: EventDetailViewModel = viewModel(key = eventId)
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(eventId) { viewModel.load(context, eventId) }

    var segment by rememberSaveable(eventId) { mutableIntStateOf(0) }
    val seed: String? = if (uiState.isJoint) null else uiState.brandColorHex
    val brand = uiState.brandColorHex
    val t = ImasTheme.derive(seed, brand, dark = true)

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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(uiState.eventName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    IconButton(onClick = {
                        val text = buildString {
                            append(uiState.eventName)
                            if (uiState.heroSub.isNotEmpty()) {
                                append("\n")
                                append(uiState.heroSub)
                            }
                        }
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        context.startActivity(Intent.createChooser(intent, null))
                    }) {
                        Icon(Icons.Filled.Share, contentDescription = "このイベントをシェア")
                    }
                }
            )
        }
    ) { innerPadding ->
        if (uiState.isLoading) {
            Box(
                modifier = Modifier.fillMaxSize().padding(innerPadding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            Column(Modifier.fillMaxSize().padding(innerPadding)) {
                Hero(
                    state = uiState, t = t, favOn = favOn, attendOn = attendOn,
                    attendedShowIds = attendedShowIds,
                    onFavToggle = { scope.launch { favOn = marks.toggle(UserMark.EVENT, eventId, UserMark.FAVORITE) } },
                    onAttendToggle = { showAttendanceSheet = true }
                )
                ImasSegmented(
                    labels = listOf("公演・セトリ", "出演", "情報"),
                    selection = segment,
                    onSelect = { segment = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)
                )
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    when (segment) {
                        0 -> showsSection(uiState, seed, brand, onShowClick)
                        1 -> castSection(uiState, seed, brand, onIdolClick)
                        else -> infoSection(uiState, seed, brand)
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
}

// MARK: - Hero

private data class AttendanceStatusUi(val label: String, val planned: Boolean)

/**
 * 参加マークの付いた公演の日付から「参加予定 (あとN日) / 参加済み」を導く。
 * iOS `AttendanceStatus.derive(attendedShowDates:)` と同じ判定。
 * 公演単位のマークが無く旧いイベント単位のマークだけある場合は、全公演を対象にする。
 */
private fun attendanceStatus(
    state: EventDetailUiState,
    marked: Boolean,
    attendedShowIds: Set<String>
): AttendanceStatusUi? {
    if (!marked) return null
    val today = JstDay.date()
    val targets = if (attendedShowIds.isEmpty()) state.shows
    else state.shows.filter { it.id in attendedShowIds }
    val futureDates = targets.map { it.date }
        .filter { it.isNotEmpty() }
        .mapNotNull { runCatching { LocalDate.parse(it) }.getOrNull() }
        .filter { !it.isBefore(today) }
    val nearest = futureDates.minOrNull()
    return if (nearest != null) {
        val days = ChronoUnit.DAYS.between(today, nearest)
        AttendanceStatusUi(if (days <= 0) "参加予定・今日" else "参加予定・あと${days}日", planned = true)
    } else {
        AttendanceStatusUi("参加済み", planned = false)
    }
}

@Composable
private fun Hero(
    state: EventDetailUiState,
    t: ImasTheme,
    favOn: Boolean,
    attendOn: Boolean,
    attendedShowIds: Set<String>,
    onFavToggle: () -> Unit,
    onAttendToggle: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 16.dp)
    ) {
        val barModifier = Modifier.width(44.dp).height(6.dp).clip(RoundedCornerShape(50.dp))
        if (state.isJoint) {
            Box(
                barModifier.background(
                    Brush.horizontalGradient(
                        listOf(
                            Color(0xFFFF0000), Color(0xFFFFA500), Color(0xFFFFFF00),
                            Color(0xFF00FF00), Color(0xFF0000FF), Color(0xFF800080)
                        )
                    )
                )
            )
        } else {
            Box(barModifier.background(t.accent))
        }
        Spacer(Modifier.height(10.dp))
        Text(state.eventName, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        if (state.heroSub.isNotEmpty()) {
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.CalendarMonth, null, tint = DS.ink2, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text(state.heroSub, fontSize = 13.sp, color = DS.ink2)
                if (state.isJoint) Text(" ・ 合同", fontSize = 13.sp, color = t.accent)
            }
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            HeroToggle("お気に入り", favOn, DS.favorite, onFavToggle)
            HeroToggle("参加", attendOn, t.accent, onAttendToggle)
        }
        attendanceStatus(state, attendOn, attendedShowIds)?.let { status ->
            Spacer(Modifier.height(10.dp))
            Row(
                modifier = Modifier.clip(RoundedCornerShape(50.dp))
                    .background(if (status.planned) t.accent else DS.fill)
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    if (status.planned) Icons.Filled.Schedule else Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = if (status.planned) t.onAccent else DS.ink2,
                    modifier = Modifier.size(13.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    status.label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                    color = if (status.planned) t.onAccent else DS.ink2
                )
            }
        }
    }
}

@Composable
private fun HeroToggle(label: String, on: Boolean, activeColor: Color, onClick: () -> Unit) {
    Row(
        modifier = Modifier.clip(RoundedCornerShape(999.dp))
            .then(
                if (on) Modifier.background(activeColor)
                else Modifier.background(DS.fill)
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (on) DS.onSys else DS.ink2)
    }
}

// MARK: - Panel 0: 公演・セトリ

private fun LazyListScope.showsSection(
    state: EventDetailUiState,
    seed: String?,
    brand: String?,
    onShowClick: (String) -> Unit
) {
    item { ImasSectionHeader(title = "公演 ・ ${state.shows.size} 公演 → セトリへ", tight = true) }
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
            ShowRow(show, seed, brand, state.isJoint) { onShowClick(show.id) }
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
    }
}

@Composable
private fun ShowRow(show: Show, seed: String?, brand: String?, rainbow: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ImasLeadBar(seedHex = seed ?: brand, height = 36.dp, rainbow = rainbow)
        Column(Modifier.weight(1f)) {
            Text(
                show.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(
                listOfNotNull(show.venue, show.date).joinToString(" ・ "),
                fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis
            )
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink3, modifier = Modifier.size(16.dp))
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

    if (attendance.leadIdols.isNotEmpty()) {
        item {
            Column {
                ImasSectionHeader(
                    title = if (attendance.leadIdols.size > 1) "主演 ・ ${attendance.leadIdols.size}名" else "主演",
                    tight = true
                )
                RoleSection(attendance, attendance.leadByShow, attendance.leadIdols, "主演", seed, brand, onIdolClick)
            }
        }
    }
    if (attendance.guestIdols.isNotEmpty()) {
        item {
            Column {
                ImasSectionHeader(
                    title = if (attendance.guestIdols.size > 1) "ゲスト ・ ${attendance.guestIdols.size}名" else "ゲスト",
                    tight = true
                )
                RoleSection(attendance, attendance.guestByShow, attendance.guestIdols, "ゲスト", seed, brand, onIdolClick)
            }
        }
    }
    if (attendance.isFullAttendance) {
        item { FullAttendanceBanner(attendance) }
    }
    items(attendance.grouped(), key = { it.id }) { group ->
        Column {
            ImasSectionHeader(title = "${group.label} ・ ${group.idols.size}名", tight = true)
            AvatarGrid(
                idols = group.idols, chipText = null, seed = seed, brand = brand,
                onClick = onIdolClick, dim = { group.label == "欠席" }
            )
        }
    }
}

@Composable
private fun RoleSection(
    attendance: EventAttendance,
    byShow: Map<String, Set<String>>,
    allIdols: List<Idol>,
    chipText: String,
    seed: String?,
    brand: String?,
    onIdolClick: (String) -> Unit
) {
    val t = ImasTheme.derive(seed, brand, dark = true)
    if (attendance.shows.size > 1) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            attendance.shows.forEachIndexed { idx, show ->
                val ids = byShow[show.id] ?: emptySet()
                val dayIdols = allIdols.filter { it.id in ids }
                if (dayIdols.isNotEmpty()) {
                    Column {
                        DayHeader(idx, show, t)
                        AvatarGrid(dayIdols, chipText, seed, brand, onIdolClick)
                    }
                }
            }
        }
    } else {
        AvatarGrid(allIdols, chipText, seed, brand, onIdolClick)
    }
}

@Composable
private fun DayHeader(index: Int, show: Show, t: ImasTheme) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 6.dp)) {
        Text(
            "DAY${index + 1}", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = t.onAccent,
            modifier = Modifier.clip(RoundedCornerShape(50.dp)).background(t.accent)
                .padding(horizontal = 8.dp, vertical = 3.dp)
        )
        shortDate(show.date)?.let {
            Spacer(Modifier.width(6.dp))
            Text(it, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = DS.ink2)
        }
        if (show.name.isNotEmpty() && show.name != "DAY${index + 1}") {
            Spacer(Modifier.width(6.dp))
            Text(show.name, fontSize = 12.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
private fun FullAttendanceBanner(attendance: EventAttendance) {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.surface)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Filled.AutoAwesome, null, tint = DS.warning, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text("全員集合！", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink, modifier = Modifier.weight(1f))
        Text("${attendance.brandIdols.size}/${attendance.brandIdols.size} 名", fontSize = 13.sp, color = DS.ink2)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AvatarGrid(
    idols: List<Idol>,
    chipText: String?,
    seed: String?,
    brand: String?,
    onClick: (String) -> Unit,
    dim: (Idol) -> Boolean = { false }
) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        idols.forEach { idol ->
            val faded = dim(idol)
            Column(
                modifier = Modifier.width(64.dp).clickable { onClick(idol.id) }.alpha(if (faded) 0.45f else 1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                ImasAvatar(label = idol.shortName, seed = idol.color, brand = idol.brandId, size = 52.dp)
                if (!chipText.isNullOrEmpty()) ImasTagChip(chipText, seed = seed, brand = brand)
                Text(
                    idol.shortName, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

// MARK: - Panel 2: 情報

private fun LazyListScope.infoSection(state: EventDetailUiState, seed: String?, brand: String?) {
    state.stats?.let { stats ->
        item { StatsGrid(stats, seed, brand) }
    }
    if (state.ticketDeadline != null || state.ticketLotteryDate != null || state.ticketUrl != null || state.isFutureEvent) {
        item { TicketInfoSection(state, seed, brand) }
    }
    if (state.brandShortName != null || firstShowYear(state) != null) {
        item { MetaSection(state, seed, brand) }
    }
}

@Composable
private fun StatsGrid(stats: EventStats, seed: String?, brand: String?) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ImasStatTile(Icons.Filled.Mic, "${stats.showCount}", "公演", seed = seed, brand = brand, modifier = Modifier.weight(1f))
            ImasStatTile(Icons.Filled.LibraryMusic, "${stats.totalSongs}", "曲（延べ）", seed = seed, brand = brand, modifier = Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ImasStatTile(Icons.Filled.MusicNote, "${stats.uniqueSongs}", "ユニーク曲", seed = seed, brand = brand, modifier = Modifier.weight(1f))
            ImasStatTile(Icons.Filled.Groups, "${stats.castCount}", "キャスト", seed = seed, brand = brand, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun TicketInfoSection(state: EventDetailUiState, seed: String?, brand: String?) {
    val uriHandler = LocalUriHandler.current
    val t = ImasTheme.derive(seed, brand, dark = true)
    val hasAny = state.ticketDeadline != null || state.ticketLotteryDate != null || state.ticketUrl != null
    Column {
        ImasSectionHeader(title = "チケット情報", tight = true)
        Column(
            Modifier.padding(horizontal = 16.dp).fillMaxWidth()
                .clip(RoundedCornerShape(14.dp)).background(DS.surface)
        ) {
            var shown = false
            state.ticketDeadline?.let {
                ImasLabeledRow(key = "申込期限", value = it, seed = seed, brand = brand)
                shown = true
            }
            state.ticketLotteryDate?.let {
                if (shown) HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                ImasLabeledRow(key = "当落発表", value = it, seed = seed, brand = brand)
                shown = true
            }
            state.ticketUrl?.let { url ->
                if (shown) HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { uriHandler.openUri(url) }
                        .padding(horizontal = 16.dp, vertical = 11.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Filled.ConfirmationNumber, null, tint = t.accent, modifier = Modifier.size(16.dp))
                    Text("公式チケットページを開く", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = t.accent)
                }
                shown = true
            }
            if (!hasAny) {
                Text(
                    "チケット情報は未登録です", fontSize = 13.sp, color = DS.ink3,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp)
                )
            }
        }
    }
}

@Composable
private fun MetaSection(state: EventDetailUiState, seed: String?, brand: String?) {
    Column(
        Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth()
            .clip(RoundedCornerShape(14.dp)).background(DS.surface)
    ) {
        var shown = false
        state.brandShortName?.let {
            ImasLabeledRow(key = "ブランド", value = it, seed = seed, brand = brand)
            shown = true
        }
        firstShowYear(state)?.let { year ->
            if (shown) HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
            ImasLabeledRow(key = "年度", value = "${year}年", seed = seed, brand = brand)
        }
    }
}

private fun firstShowYear(state: EventDetailUiState): Int? {
    val date = state.shows.firstOrNull()?.date ?: return null
    return if (date.length >= 4) date.take(4).toIntOrNull() else null
}
