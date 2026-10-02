package com.fugaif.imaslivedb.ui.idols

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.data.auth.AuthState
import com.fugaif.imaslivedb.data.auth.shouldPromptLogin
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.image.CustomImageStore
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.components.CopyItem
import com.fugaif.imaslivedb.ui.edit.IdolEditScreen
import com.fugaif.imaslivedb.ui.edit.RecordHistorySheet
import com.fugaif.imaslivedb.ui.components.IdolGridSection
import com.fugaif.imaslivedb.ui.components.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeSpec
import com.fugaif.imaslivedb.ui.designsystem.ImasBoardCell
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChip
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasChipStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasDisclosureRow
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasIconBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasLabeledRow
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkBar
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkTile
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasShowRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSignInPrompt
import com.fugaif.imaslivedb.ui.components.PersonalTagsSection
import com.fugaif.imaslivedb.ui.designsystem.ImasTicket
import com.fugaif.imaslivedb.ui.filtered.IdolFilterKind
import com.fugaif.imaslivedb.ui.tags.IdolTagPickerSheet
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasThemeProvider
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import kotlinx.coroutines.launch
import uniffi.imas_core.IdolProfileSource
import uniffi.imas_core.RowAction
import uniffi.imas_core.RowStyle
import uniffi.imas_core.dateLabel
import uniffi.imas_core.idolProfileRowsFromSource
import java.io.File
import com.fugaif.imaslivedb.data.local.localWrite

/**
 * アイドル詳細。iOS IdolDetailView の構成を 1:1 で写す。
 * hero(アバター + 名前 + ブランド + 担当/お気に入り) を上部に、その下を ImasSegmented で
 * [ライブ][楽曲・ユニット][プロフィール] に切り替える。
 *
 * iOS にあって Android にまだ無いもの (対応基盤が無いため未実装):
 * - メモ (UserMarkBar note) — テキスト入力 UI が Android に無い
 * - ホーム画面ウィジェット — 画像基盤 (CustomImageStore) は入ったが、ウィジェット本体は未実装
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun IdolDetailScreen(
    idolId: String,
    onNavigateBack: () -> Unit,
    onNavigateToUnitDetail: (String) -> Unit,
    onNavigateToSongDetail: (String) -> Unit,
    onNavigateToShowDetail: (String) -> Unit,
    onNavigateToIdolDetail: (String) -> Unit = {},
    onPollClick: (String) -> Unit = {},
    onIdolTagClick: (String) -> Unit = {},
    /** 誕生日の行から「同じ誕生月のアイドル」一覧へ (1..12)。押せる行かどうかはコアが決める。 */
    onNavigateToBirthMonth: (Int) -> Unit = {},
    /** ライブ歌唱曲の行から「この人がこの曲を歌った公演」へ (idolId, songId)。 */
    onNavigateToSongHistory: (String, String) -> Unit = { _, _ -> },
    /**
     * プロフィールの属性から「同じ属性のアイドル」一覧へ (kind, value は
     * [com.fugaif.imaslivedb.ui.filtered.IdolFilterKind] の定義に従う)。
     */
    onFilteredIdolsClick: (String, String) -> Unit = { _, _ -> },
    viewModel: IdolDetailViewModel = viewModel(
        factory = IdolDetailViewModel.Factory(
            LocalContext.current.applicationContext as android.app.Application, idolId
        )
    )
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsState()
    // 編集直後の姿。IdolDetailViewModel には外から呼べる再読込の口が無い (load は private) ので、
    // admin の即時反映ぶんだけ画面側で上書きして、保存した瞬間から新しい値を見せる。
    // 一般ユーザーは修正リクエスト止まりで反映されないため、ここに入ることはない。
    var editedIdol by remember(idolId) { mutableStateOf<Idol?>(null) }
    val idol = editedIdol ?: state.idol
    var segment by rememberSaveable(idolId) { mutableIntStateOf(0) }
    var showTagPicker by rememberSaveable { mutableStateOf(false) }
    var showLoginPrompt by rememberSaveable { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var showIdolEdit by remember { mutableStateOf(false) }
    var showRecordHistory by remember { mutableStateOf(false) }
    val authState by AppModule.from(context).authService.state.collectAsState()
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる (詳細は data/auth/EditPermission.kt)。
    val canEditHere = remember(authState) { authState.showEditAffordance }

    // 投稿/編集導線の共通ゲート (iOS IdolDetailView.startCommunityEdit と同じ)。優先順はコアが持つので
    // if で並べ直さない。BAN 済みは iOS の .ignore と同じく無反応 (onBanned 既定) —
    // この画面の編集導線は showEditAffordance で隠れており、押せるのはタグチップだけ。
    fun startCommunityEdit(present: () -> Unit) =
        authState.startCommunityEdit(promptLogin = { showLoginPrompt = true }, present = present)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(idol?.name ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "その他")
                    }
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        // BAN 済みには編集導線を出さない (押しても 403 になるだけ)。判定はコア。
                        if (idol != null && canEditHere) {
                            DropdownMenuItem(
                                text = { Text("編集") },
                                onClick = {
                                    showMenu = false
                                    startCommunityEdit { showIdolEdit = true }
                                }
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("編集履歴") },
                            onClick = { showMenu = false; showRecordHistory = true }
                        )
                    }
                }
            )
        }
    ) { padding ->
        if (state.isLoading || idol == null) {
            ImasLoadingState(modifier = Modifier.fillMaxSize().padding(padding))
        } else {
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
                Hero(idol, state.brand?.shortName, state.castShows.size, state.performedSongs.size)
                ImasSegmented(
                    labels = listOf("ライブ", "楽曲・ユニット", "プロフィール", "コミュニティ"),
                    selection = segment, onSelect = { segment = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
                )
                when (segment) {
                    0 -> LiveBody(state, idol, onNavigateToShowDetail) { songId ->
                        onNavigateToSongHistory(idol.id, songId)
                    }
                    1 -> SongsBody(state, idol, onNavigateToUnitDetail, onNavigateToSongDetail)
                    2 -> ProfileBody(idol, state.brand, onNavigateToBirthMonth, onFilteredIdolsClick)
                    else -> Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        CommunityBody(
                            idolId = idol.id,
                            seed = idol.color,
                            brand = idol.brandId,
                            tags = state.tags,
                            authState = authState,
                            similarTagIdols = state.similarTagIdols,
                            similarSharedTags = state.similarSharedTags,
                            // 外す方向はゲートしない (iOS も自分が付けたタグの取り消しは素通し)。
                            // 付ける方向はタグ投票の書き込みなので共通ゲートを通す。
                            onToggleTag = { tag ->
                                if (tag.mine) viewModel.toggleTag(tag)
                                else startCommunityEdit { viewModel.toggleTag(tag) }
                            },
                            onOpenTagPicker = { startCommunityEdit { showTagPicker = true } },
                            onPollClick = onPollClick,
                            onTagDetailClick = onIdolTagClick,
                            onIdolClick = onNavigateToIdolDetail
                        )
                        PersonalTagsSection(
                            tags = state.personalTags.map { it.tagName },
                            onAdd = viewModel::addPersonalTag,
                            onRemove = viewModel::removePersonalTag
                        )
                    }
                }
                Box(Modifier.size(24.dp))
            }
        }
    }

    if (showTagPicker && idol != null) {
        IdolTagPickerSheet(
            idolId = idol.id,
            alreadyAppliedTagIds = state.tags.filter { it.mine }.map { it.id }.toSet(),
            onDismiss = { showTagPicker = false },
            onApplied = { viewModel.onTagsApplied() }
        )
    }

    // 編集フォームはフルスクリーン Dialog に載せる (RecentEditsScreen → SetlistEditScreen と同じ)。
    val editingIdol = idol
    if (showIdolEdit && editingIdol != null) {
        Dialog(
            onDismissRequest = { showIdolEdit = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            IdolEditScreen(
                original = editingIdol,
                onDismiss = { showIdolEdit = false },
                onSaved = { saved -> showIdolEdit = false; editedIdol = saved }
            )
        }
    }

    if (showRecordHistory) {
        RecordHistorySheet(
            recordType = "Idol",
            recordName = idolId,
            onDismiss = { showRecordHistory = false }
        )
    }

    if (showLoginPrompt) {
        CommunityLoginPromptDialog(
            message = "タグ付け・投票にはログインが必要です。",
            onDismiss = { showLoginPrompt = false }
        )
    }
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
private fun CommunityBody(
    idolId: String,
    /** タグチップのペンライトの色 (このアイドル本人の色)。 */
    seed: String?,
    brand: String?,
    tags: List<CommunityApi.IdolTag>,
    authState: AuthState,
    similarTagIdols: List<Idol>,
    similarSharedTags: Map<String, Int>,
    onToggleTag: (CommunityApi.IdolTag) -> Unit,
    onOpenTagPicker: () -> Unit,
    onPollClick: (String) -> Unit,
    onTagDetailClick: (String) -> Unit,
    onIdolClick: (String) -> Unit
) {
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる (再コンポーズごとに
    // EditPermissionRules を RustBuffer へ詰め直して JNA を跨がないため)。
    val canEditHere = remember(authState) { authState.showEditAffordance }
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.section)) {
        com.fugaif.imaslivedb.ui.polls.PollAchievementBadges(entityId = idolId, onOpenPoll = onPollClick)
        ImasSignInPrompt(
            modifier = Modifier.padding(horizontal = DS.Space.screen),
            message = "タグ付け・投票にはログインが必要です"
        )
        Column {
            ImasSectionHeader(
                "タグ", count = "${tags.size}",
                actionTitle = if (canEditHere) "タグ" else null,
                actionIcon = if (canEditHere) Icons.Filled.Add else null,
                onAction = if (canEditHere) onOpenTagPicker else null
            )
            if (tags.isEmpty()) {
                ImasEmptyState(icon = Icons.Filled.Sell, title = "タグはまだありません")
            } else {
                ImasChipFlow(modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen)) {
                    tags.forEach { tag ->
                        val label = if (tag.voteCount > 0) "${tag.name} ${tag.voteCount}" else tag.name
                        ImasChip(
                            text = label,
                            style = if (tag.mine) ImasChipStyle.SELECTED else ImasChipStyle.THEMED,
                            seed = seed, brand = brand,
                            // タップは投票トグル、長押しでタグ詳細。
                            modifier = Modifier.combinedClickable(
                                onClick = { onToggleTag(tag) },
                                onLongClick = { onTagDetailClick(tag.id) }
                            )
                        )
                    }
                }
            }
        }
        // タグが似ているアイドル (この人が好きな人にはこの人も, サーバ算出)
        if (similarTagIdols.isNotEmpty()) {
            IdolGridSection("タグが似ているアイドル", similarTagIdols, onIdolClick, badge = similarSharedTags)
        }
    }
}

@Composable
private fun Hero(idol: Idol, brandShortName: String?, castShowCount: Int, performedSongCount: Int) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val marks = AppModule.from(context).userMarkRepository
    var pick by remember(idol.id) { mutableStateOf(false) }
    var fav by remember(idol.id) { mutableStateOf(false) }
    LaunchedEffect(idol.id) {
        pick = marks.isOn(UserMark.IDOL, idol.id, UserMark.PICK)
        fav = marks.isOn(UserMark.IDOL, idol.id, UserMark.FAVORITE)
    }
    val store = remember { AppModule.from(context).customImageStore }
    // アバタータップ = 「この写真をアイコンにする」。追加してすぐ先頭 (プライマリ) へ動かす。
    // 追加だけだと末尾に積まれてアイコンが変わらず、押した結果が見えないため。
    val pickAvatar = rememberImagePicker(maxItems = 1) { uris ->
        scope.launch {
            uris.firstOrNull()?.let { uri ->
                store.addImage(uri, idol.id)?.let { store.setPrimary(it, idol.id) }
            }
        }
    }
    Column(Modifier.fillMaxWidth()) {
        // 名札の頭 (iOS `ImasIdolHeader`)。アイコンはいつも出し (写真か判子)、右下に写真を選ぶ口、
        // 右に担当の ♥。印字 (ブランド名) の上、電光掲示板に出演・歌唱曲の数。
        ImasIdolHeader(
            imprint = brandShortName ?: "",
            name = idol.name,
            isPick = pick,
            modifier = Modifier.padding(horizontal = DS.Space.screen).padding(top = DS.Space.gapLoose),
            // 現任の声優 (iOS と同じく今の 1 人)。選び方はコア。
            subtitle = idol.currentVoiceActor?.let { "CV $it" },
            seed = idol.color,
            brand = idol.brandId,
            iconLabel = idol.shortName,
            entityId = idol.id,
            onTogglePick = {
                scope.launch { localWrite("担当の切り替え") { marks.toggle(UserMark.IDOL, idol.id, UserMark.PICK) }?.let { pick = it } }
            },
            copyItems = listOf(CopyItem("アイドル名をコピー", idol.name), CopyItem("よみをコピー", idol.nameKana)),
            stats = listOf(
                ImasBoardCell(value = "${castShowCount}", label = "出演"),
                ImasBoardCell(value = "${performedSongCount}", label = "歌唱曲")
            ),
            iconAccessory = {
                ImasIconBadge(
                    icon = Icons.Filled.PhotoCamera,
                    label = "写真を選ぶ",
                    seed = idol.color,
                    brand = idol.brandId,
                    modifier = Modifier.imasRowPress(onClickLabel = "写真を選ぶ", onClick = pickAvatar)
                )
            }
        )
        // お気に入りは印のバー (担当は名札側の ♥ に既にある)。iOS `UserMarkBar(kinds: [.favorite, .note])` の
        // うちメモは Android に入力 UI が無いため対象外。
        ImasThemeProvider(seed = idol.color, brand = idol.brandId) {
            ImasMarkBar(modifier = Modifier.padding(horizontal = DS.Space.screen).padding(top = DS.Space.gap, bottom = DS.Space.gap)) {
                ImasMarkTile(
                    icon = Icons.Filled.Star,
                    label = "お気に入り",
                    isOn = fav,
                    accessibilityText = "お気に入り",
                    onClick = {
                        scope.launch { localWrite("お気に入りの切り替え") { marks.toggle(UserMark.IDOL, idol.id, UserMark.FAVORITE) }?.let { fav = it } }
                    }
                )
            }
        }
    }
}

@Composable
private fun LiveBody(
    state: IdolDetailUiState,
    idol: Idol,
    onShow: (String) -> Unit,
    /**
     * 「ライブ歌唱曲」の行き先は曲詳細ではなく **この人 × この曲の披露履歴**。
     * 曲詳細へ飛ばすと全歌唱者ぶんの履歴に混ざり、「この人がいつ歌ったか」が読めなくなる。
     */
    onSongHistory: (String) -> Unit
) {
    if (state.performedSongs.isEmpty() && state.castShows.isEmpty()) {
        ImasEmptyState(Icons.Filled.MusicNote, "ライブ記録はまだありません",
            "このアイドルのライブ出演・歌唱記録はまだ登録されていません。", seed = idol.color, brand = idol.brandId)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.section / 2)) {
        // 次の出演。紙のチケットで見せる (iOS `ImasTicket` と同じ)。
        state.nextShow?.let { next ->
            ImasTicket(
                label = "次の出演",
                imprint = null,
                title = AppPreferences.eventDisplayName(next.eventName),
                metaImprint = dateLabel(next.date, JstDay.today()),
                meta = listOfNotNull(next.venue, next.showName).filter { it.isNotEmpty() }.joinToString(" ・ "),
                seed = idol.color,
                brand = idol.brandId,
                modifier = Modifier.padding(horizontal = DS.Space.screen),
                onOpen = { onShow(next.showId) }
            )
        }
        if (state.performedSongs.isNotEmpty()) {
            Column {
                ImasSectionHeader("ライブ歌唱曲", count = "${state.performedSongs.size}", tight = true)
                ImasCardList(
                    items = state.performedSongs,
                    modifier = Modifier.padding(horizontal = DS.Space.screen),
                    key = { it.song.id }
                ) { item ->
                    ImasSongRow(
                        song = item.song,
                        subtitle = item.song.singerLabel?.takeIf { it.isNotEmpty() } ?: item.song.unitName,
                        density = ImasRowDensity.COMPACT,
                        onClick = { onSongHistory(item.song.id) }
                    ) {
                        if (item.performCount != null) ImasMetric("${item.performCount}", unit = "回", size = ImasNumeralSize.SMALL)
                    }
                }
            }
        }
        if (state.castShows.isNotEmpty()) {
            Column {
                ImasSectionHeader("出演履歴", count = "${state.castShows.size}", tight = true)
                ImasCardList(
                    items = state.castShows,
                    modifier = Modifier.padding(horizontal = DS.Space.screen),
                    key = { it.showId }
                ) { row ->
                    ImasShowRow(
                        date = row.date,
                        title = AppPreferences.eventDisplayName(row.eventName),
                        subtitle = listOf(row.venue, row.showName).mapNotNull { it?.takeIf { s -> s.isNotEmpty() } }.joinToString(" ・ "),
                        seed = idol.color,
                        brand = idol.brandId,
                        badges = if (row.isLead) listOf(ImasBadgeSpec("主演", kind = ImasBadgeKind.LEAD))
                            else if (row.isGuest) listOf(ImasBadgeSpec("ゲスト", kind = ImasBadgeKind.GUEST))
                            else emptyList(),
                        modifier = Modifier.imasRowPress(onClick = { onShow(row.showId) })
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SongsBody(state: IdolDetailUiState, idol: Idol, onUnit: (String) -> Unit, onSong: (String) -> Unit) {
    if (state.unitsWithSongs.isEmpty() && state.unitsWithoutSongs.isEmpty() && state.originalSongSections.isEmpty()) {
        ImasEmptyState(Icons.Filled.MusicNote, "楽曲・ユニットがありません",
            "原曲・所属ユニットの情報はまだ登録されていません。", seed = idol.color, brand = idol.brandId)
        return
    }
    var showEmptyUnits by rememberSaveable(idol.id) { mutableStateOf(false) }
    // 楽曲タブの小タブ (節) の選択。節の並びは originalSongSections が既にソロ→ユニット→
    // 全体曲→カバー→その他の固定順・0 件節なしで返すので、初期値 0 がそのまま
    // 「曲がある最初の枠」になる。
    var selectedSongSectionIndex by rememberSaveable(idol.id) { mutableStateOf(0) }
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.section / 2)) {
        if (state.unitsWithSongs.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasSectionHeader("所属ユニット", count = "${state.unitsWithSongs.size}", tight = true)
                ImasChipFlow(modifier = Modifier.padding(horizontal = DS.Space.screen)) {
                    state.unitsWithSongs.forEach { unit ->
                        ImasChip(text = unit.displayName, style = ImasChipStyle.THEMED, seed = idol.color, brand = idol.brandId, onClick = { onUnit(unit.id) })
                    }
                }
            }
        }
        if (state.unitsWithoutSongs.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap), modifier = Modifier.padding(horizontal = DS.Space.screen)) {
                ImasDisclosureRow(
                    title = "曲なしユニット",
                    isExpanded = showEmptyUnits,
                    onToggle = { showEmptyUnits = !showEmptyUnits },
                    count = "${state.unitsWithoutSongs.size}"
                )
                if (showEmptyUnits) {
                    ImasChipFlow {
                        state.unitsWithoutSongs.forEach { unit ->
                            ImasChip(text = unit.displayName, style = ImasChipStyle.THEMED, seed = idol.color, brand = idol.brandId, onClick = { onUnit(unit.id) })
                        }
                    }
                }
            }
        }
        if (state.originalSongSections.isNotEmpty()) {
            // 枠が 1 つしか無いときは小タブを出さず一覧だけを出す。
            val safeIndex = selectedSongSectionIndex.coerceIn(0, state.originalSongSections.lastIndex)
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                if (state.originalSongSections.size > 1) {
                    ImasSegmented(
                        labels = state.originalSongSections.map { "${it.shortHeading} ${it.songs.size}" },
                        selection = safeIndex,
                        onSelect = { selectedSongSectionIndex = it },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen)
                    )
                }
                ImasCardList(
                    items = state.originalSongSections[safeIndex].songs,
                    modifier = Modifier.padding(horizontal = DS.Space.screen),
                    key = { it.id }
                ) { song ->
                    ImasSongRow(
                        song = song,
                        subtitle = song.singerLabel?.takeIf { it.isNotEmpty() } ?: song.unitName,
                        density = ImasRowDensity.COMPACT,
                        onClick = { onSong(song.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun ProfileBody(
    idol: Idol,
    brand: Brand?,
    onNavigateToBirthMonth: (Int) -> Unit,
    onFilteredIdolsClick: (String, String) -> Unit
) {
    val clipboard = LocalClipboardManager.current
    // 行の組み立て (どの行が・どの順で・押せるか) は共有コアが唯一の正。
    // iOS と同じ条件を二重に書くと必ずいつかズレるので、ここは整形済みの値を渡すだけにする。
    // 1 画面 = 1 呼び出し。idol が変わらない限り作り直さない。
    val rows = remember(idol) {
        idolProfileRowsFromSource(
            IdolProfileSource(
                nameKana = idol.nameKana,
                nameRomaji = idol.nameRomaji,
                birthday = idol.birthday,
                age = idol.age?.toLong(),
                height = idol.height,
                weight = idol.weight,
                bust = idol.bust,
                waist = idol.waist,
                hip = idol.hip,
                bloodType = idol.bloodType,
                constellation = idol.constellation,
                birthPlace = idol.birthPlace,
                handedness = idol.handedness,
                hobbies = idol.hobbies,
                talents = idol.talents,
                color = idol.color
            )
        )
    }
    Column {
        ImasSectionHeader("プロフィール", tight = true)
        // ImasLabeledRow に位置 (position) を渡さなければ ImasCardList(items) が 2 行目以降の
        // 区切り線を自動で引く (ImasValueRow と同じ仕組みを足した。DESIGN_SYSTEM.md §15)。
        ImasCardList(items = rows, modifier = Modifier.padding(horizontal = DS.Space.screen), key = { it.label }) { row ->
            val action = row.action
            // コアが返すのは「何をしたいか」の種類だけ。実行はこちらの責務。
            // when は網羅にしてある — コアが操作を増やしたらここがコンパイルエラーで気付ける。
            val onClick: (() -> Unit)? = when (action) {
                // 誕生日は同じ誕生月のアイドル一覧へ (iOS の filteredIdols(.birthMonth) と同じ行先)。
                is RowAction.FilterByBirthMonth -> {
                    val month = action.month.toInt()
                    ({ onNavigateToBirthMonth(month) })
                }
                // カラーは押すと写せる (配信や実況で色コードを使う人が居る)。
                RowAction.CopyValue -> ({ clipboard.setText(AnnotatedString(row.value)) })
                // 全文展開は ImasLabeledRow が未対応なので、行の onClick には載せない
                // (値の全文は行の長押しコピーで取れる)。
                RowAction.ToggleExpansion, RowAction.None -> null
            }
            ImasLabeledRow(
                key = row.label,
                value = row.value,
                showSwatch = row.style == RowStyle.COLOR_SWATCH,
                // 色コードは桁を揃えたいので ColorSwatch も等幅で出す。
                mono = row.style == RowStyle.MONOSPACED || row.style == RowStyle.COLOR_SWATCH,
                // 押せる見た目 (accent 文字 + 矢印) を出すのは onClick ではなく tappable。
                // 「別画面へ行く」行だけ立てる — 複写は押せるが行先が無いので矢印は嘘になる
                // (iOS ImasLabeledRow の showChevron/tappable と同じ切り分け)。
                tappable = action is RowAction.FilterByBirthMonth,
                seed = idol.color, brand = idol.brandId, onClick = onClick
            )
        }
        idol.description?.takeIf { it.isNotEmpty() }?.let { desc ->
            Text(desc, fontSize = 14.sp, color = DS.ink2, modifier = Modifier.padding(16.dp))
        }
        SameProfileSection(idol, brand, onFilteredIdolsClick)
        // iOS も profileBody の末尾にギャラリーを置いている (プロフィールの一部という位置づけ)。
        GallerySection(idol.id)
    }
}

/**
 * 「同じ属性のアイドル」への入口 (ブランド / 星座 / 出身地 / 血液型)。
 *
 * プロフィールの行そのものを押させないのは、行の組み立て — どの行が・どの順で・押せるか —
 * を共有コア (`idolProfileRowsFromSource`) が持っているため。血液型と星座は 1 行に同居していて
 * 行き先が 2 つあり、コアの `RowAction` では表現できない。行の内訳ではなくチップで
 * 「この属性で辿れる」ことを示す方が、どこを押すと何が起きるかも明快になる。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SameProfileSection(idol: Idol, brand: Brand?, onFilteredIdolsClick: (String, String) -> Unit) {
    val chips = buildList {
        brand?.let { add(Triple(IdolFilterKind.BRAND, it.id, it.shortName)) }
        idol.constellation?.takeIf { it.isNotEmpty() }?.let { add(Triple(IdolFilterKind.CONSTELLATION, it, it)) }
        idol.birthPlace?.takeIf { it.isNotEmpty() }?.let { add(Triple(IdolFilterKind.BIRTH_PLACE, it, "${it}出身")) }
        idol.bloodType?.takeIf { it.isNotEmpty() }?.let { add(Triple(IdolFilterKind.BLOOD_TYPE, it, "${it}型")) }
    }
    if (chips.isEmpty()) return
    Column {
        ImasSectionHeader("同じプロフィールのアイドル", tight = true)
        FlowRow(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            chips.forEach { (kind, value, label) ->
                ImasChip(
                    text = label, style = ImasChipStyle.THEMED,
                    seed = idol.color, brand = idol.brandId,
                    onClick = { onFilteredIdolsClick(kind, value) }
                )
            }
        }
    }
}

// =============================================================================
// 画像ギャラリー (ユーザーが端末に取り込む複数画像)
// iOS IdolDetailView.gallerySection / CustomImageService と対。
// 画像は端末内にだけ置く — サーバにも CloudKit にも上げない。
// =============================================================================

/** 1 回の追加で選べる枚数の上限 (iOS の PhotosPicker maxSelectionCount と同じ)。 */
private const val MAX_GALLERY_PICK = 10

/**
 * 端末のフォトピッカーを開くランチャ。
 *
 * Android 13+ / Play システム更新済みの端末は権限不要のシステムフォトピッカーを使う。
 * 未対応端末では [ActivityResultContracts.PickVisualMedia] が解決できないので、
 * SAF の `GetMultipleContents` に落とす (READ_MEDIA_IMAGES 権限を要求しないため)。
 */
@Composable
private fun rememberImagePicker(maxItems: Int, onPicked: (List<Uri>) -> Unit): () -> Unit {
    val context = LocalContext.current
    // PickMultipleVisualMedia は maxItems >= 2 が前提なので、1 枚選択は単数版を使う。
    val multiple = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(maxItems.coerceAtLeast(2))
    ) { uris -> onPicked(uris.take(maxItems)) }
    val single = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri -> onPicked(listOfNotNull(uri)) }
    val fallback = rememberLauncherForActivityResult(
        ActivityResultContracts.GetMultipleContents()
    ) { uris -> onPicked(uris.take(maxItems)) }
    return {
        val request = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
        when {
            !ActivityResultContracts.PickVisualMedia.isPhotoPickerAvailable(context) ->
                fallback.launch("image/*")
            maxItems <= 1 -> single.launch(request)
            else -> multiple.launch(request)
        }
    }
}

/**
 * 横スクロールのギャラリー。長押しで「アイコンにする / スライドショー切替 / 削除」。
 *
 * スライドショーのフラグはホーム画面ウィジェットが読む値で、この画面が唯一の入力口になる
 * (ウィジェット本体は別途実装)。
 */
@Composable
private fun GallerySection(idolId: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { AppModule.from(context).customImageStore }
    // 追加/削除/並べ替えのたびに引き直す (iOS が galleryVersion を読んで再描画するのと同じ)。
    val version by store.galleryVersion.collectAsState()
    val files = remember(idolId, version) { store.imageFiles(idolId) }
    val addImages = rememberImagePicker(MAX_GALLERY_PICK) { uris ->
        scope.launch { uris.forEach { store.addImage(it, idolId) } }
    }

    Column {
        ImasSectionHeader(
            "ギャラリー", count = "${files.size}", tight = true,
            actionTitle = "追加", actionIcon = Icons.Filled.Add, onAction = addImages
        )
        if (files.isEmpty()) {
            Text(
                "画像を追加すると、先頭の1枚がアイコンになります。画像はこの端末の中だけに保存され、どこにも送信されません。",
                fontSize = 12.sp, color = DS.ink2,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
            )
        } else {
            LazyRow(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // ファイル名は UUID なので、並べ替えても同一性が壊れない安定キーになる。
                items(files, key = { it.name }) { file ->
                    GalleryThumb(
                        file = file,
                        isPrimary = file.name == files.first().name,
                        inSlideshow = remember(file, version) { store.isInSlideshow(file, idolId) },
                        store = store,
                        idolId = idolId,
                        scope = scope
                    )
                }
            }
            Text(
                "長押しでアイコン設定・ウィジェットのスライドショー対象・削除を切り替えられます。",
                fontSize = 11.sp, color = DS.ink3,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GalleryThumb(
    file: File,
    isPrimary: Boolean,
    inSlideshow: Boolean,
    store: CustomImageStore,
    idolId: String,
    scope: kotlinx.coroutines.CoroutineScope
) {
    var menuOpen by remember(file) { mutableStateOf(false) }
    Box {
        SubcomposeAsyncImage(
            model = file,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(96.dp).clip(RoundedCornerShape(10.dp)).background(DS.fill)
                // タップも長押しも同じメニューを出す。削除以外に「アイコンにする」等もあるので、
                // 誤爆しない形 (即実行ではなくメニュー) に寄せている。
                .combinedClickable(onClick = { menuOpen = true }, onLongClick = { menuOpen = true })
                // スライドショー対象外は淡く落として一目で分かるようにする。
                .then(if (inSlideshow) Modifier else Modifier.alpha(0.45f)),
            loading = { Box(Modifier.size(96.dp).background(DS.fill)) },
            error = { Box(Modifier.size(96.dp).background(DS.fill)) }
        )
        if (isPrimary) {
            Row(
                modifier = Modifier.padding(5.dp).clip(RoundedCornerShape(999.dp))
                    .background(Color.Black.copy(alpha = 0.55f))
                    .padding(horizontal = 6.dp, vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.Star, contentDescription = null, tint = Color.White,
                    modifier = Modifier.size(9.dp))
                Text("アイコン", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = Color.White,
                    modifier = Modifier.padding(start = 3.dp))
            }
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            if (!isPrimary) {
                DropdownMenuItem(
                    text = { Text("アイコンにする") },
                    onClick = {
                        menuOpen = false
                        scope.launch { store.setPrimary(file, idolId) }
                    }
                )
            }
            DropdownMenuItem(
                text = { Text(if (inSlideshow) "スライドショーから外す" else "スライドショーに入れる") },
                onClick = {
                    menuOpen = false
                    scope.launch { store.setInSlideshow(!inSlideshow, file, idolId) }
                }
            )
            DropdownMenuItem(
                text = { Text("削除", color = DS.danger) },
                onClick = {
                    menuOpen = false
                    scope.launch { store.deleteImage(file, idolId) }
                }
            )
        }
    }
}

