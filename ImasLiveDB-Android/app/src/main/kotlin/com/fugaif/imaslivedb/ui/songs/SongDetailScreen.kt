package com.fugaif.imaslivedb.ui.songs

import com.fugaif.imaslivedb.ui.designsystem.imasResetScrollOnTabChange
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.OndemandVideo
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.data.auth.AuthState
import com.fugaif.imaslivedb.data.auth.shouldPromptLogin
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.model.CoOccurringSong
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongVideo
import com.fugaif.imaslivedb.data.model.SongPerformanceEvidence
import com.fugaif.imaslivedb.data.model.SongSingerTally
import com.fugaif.imaslivedb.data.model.Vocab
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.edit.RecordHistorySheet
import com.fugaif.imaslivedb.ui.edit.SongEditScreen
import com.fugaif.imaslivedb.ui.edit.SongNoteEditScreen
import com.fugaif.imaslivedb.ui.edit.VideoEditSheet
import com.fugaif.imaslivedb.ui.designsystem.ImasBoard
import com.fugaif.imaslivedb.ui.designsystem.ImasBoardCell
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChip
import com.fugaif.imaslivedb.ui.designsystem.ImasChipStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEntryCard
import com.fugaif.imaslivedb.ui.designsystem.ImasHero
import com.fugaif.imaslivedb.ui.designsystem.ImasHeroLayout
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolRow
import com.fugaif.imaslivedb.ui.components.IdolGridSection
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkButton
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkKind
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkTile
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSignInPrompt
import com.fugaif.imaslivedb.ui.designsystem.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasStatTile
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.designsystem.ImasToolbarButton
import com.fugaif.imaslivedb.ui.designsystem.ImasValueRow
import com.fugaif.imaslivedb.ui.tags.SongTagPickerSheet
import com.fugaif.imaslivedb.ui.tags.TagDetailScreen
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.hexToColor
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.penlight
import com.fugaif.imaslivedb.ui.filtered.SongFilterKind
import uniffi.imas_core.youtubeVideoRefs
import uniffi.imas_core.kamisabiCardLabel
import uniffi.imas_core.kamisabiCompletionLabel
import uniffi.imas_core.shortYearMonth
import uniffi.imas_core.splitCreditNames

/**
 * 楽曲詳細。iOS の `SongSheetContent` (D2: ジャケ左 + 題・歌唱者・配信日を先に読ませる頭、
 * `ImasBoard` の数、`ImasTabs` 3 タブ [情報・歌唱/披露履歴/コミュニティ]) の組み方を 1:1 で写す。
 * 歌詞タブは JASRAC 許諾の都合で iOS 限定 (Android にはそもそも歌詞取得が無い) なので載せない。
 *
 * 関連楽曲/似ているタグ楽曲のタップ、タグタップでのタグ詳細表示は、
 * AppNavigation.kt の NavHost を経由せず画面内のローカル状態で完結させている
 * (このスクリーンの担当範囲外であるナビゲーション配線ファイルを変更しないため)。
 * そのため戻るボタンは常に呼び出し元 (曲一覧等) に戻り、iOS のような
 * 「開いた曲ごとの push 履歴」の再現はしていない。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongDetailScreen(
    songId: String,
    onBack: () -> Unit,
    onUnitClick: (String) -> Unit,
    onIdolClick: (String) -> Unit,
    onShowClick: (String) -> Unit,
    onPollClick: (String) -> Unit = {},
    /**
     * 楽曲情報の行から「同じ条件の楽曲一覧」へ (kind, value は
     * [com.fugaif.imaslivedb.ui.filtered.SongFilterKind] の定義に従う)。
     */
    onFilteredSongsClick: (String, String) -> Unit = { _, _ -> },
    viewModel: SongDetailViewModel = viewModel(key = songId)
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    var showTagPicker by rememberSaveable { mutableStateOf(false) }
    var showPenlightSheet by rememberSaveable { mutableStateOf(false) }
    var currentSongId by rememberSaveable(songId) { mutableStateOf(songId) }
    var tagDetailId by rememberSaveable { mutableStateOf<String?>(null) }
    var showMenu by remember { mutableStateOf(false) }
    var showLoginPrompt by rememberSaveable { mutableStateOf(false) }
    var showSongEdit by remember { mutableStateOf(false) }
    // 補足だけを書く軽い画面 (利用者の投稿が主な入口なので、楽曲編集とは別に持つ)。
    var showNoteEdit by remember { mutableStateOf(false) }
    var showRecordHistory by remember { mutableStateOf(false) }
    var showVideoSheet by remember { mutableStateOf(false) }
    var editingVideo by remember { mutableStateOf<SongVideo?>(null) }
    // 曲そのものを編集した後は VM を素直に読み直す。ViewModel はこの画面の担当範囲外なので
    // 差分反映のための API を足さず、再読込のきっかけだけ画面側で持つ。
    var reloadToken by remember { mutableStateOf(0) }
    val authState by AppModule.from(context).authService.state.collectAsState()
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる。extension property は 1 回ごとに
    // JNA を跨ぐので、メニューを開くたび・再コンポーズのたびに呼ばない
    // (詳細は data/auth/EditPermission.kt のヘッダ)。
    val canEditHere = remember(authState) { authState.showEditAffordance }

    // 投稿/編集導線の共通ゲート。iOS DetailSheet.handle(intent) と同じで、
    // 「開く/書き込む」操作は全部ここを通す。
    // シート側 (VideoEditSheet / PenlightVoteSheet) に権限判定は無いので、
    // ここで止めないとフォームに入力させた末に 401/403 で落ちる。
    //
    // BAN 済みは iOS の .ignore と同じく無反応 (onBanned 既定)。この画面の編集導線は
    // showEditAffordance で全部隠れているので、押せるのはタグチップだけ。
    fun startCommunityEdit(present: () -> Unit) =
        authState.startCommunityEdit(promptLogin = { showLoginPrompt = true }, present = present)

    LaunchedEffect(currentSongId, reloadToken) { viewModel.load(context, currentSongId) }

    if (tagDetailId != null) {
        // タグ詳細をこの画面内で表示 (別 route を経由しない, 上記コメント参照)。
        TagDetailScreen(
            tagId = tagDetailId!!,
            onBack = { tagDetailId = null },
            onSongClick = { id -> tagDetailId = null; currentSongId = id }
        )
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(uiState.song?.title ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    ImasToolbarButton(icon = Icons.AutoMirrored.Filled.ArrowBack, label = "戻る", onClick = onBack)
                },
                actions = {
                    val song = uiState.song
                    ImasToolbarButton(icon = Icons.Filled.MoreVert, label = "その他", onClick = { showMenu = true })
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("歌詞を見る") },
                            onClick = {
                                showMenu = false
                                openUrl(context, lyricsUrl(song))
                            }
                        )
                        if (!song?.appleMusicId.isNullOrEmpty()) {
                            DropdownMenuItem(
                                text = { Text("Apple Musicで開く") },
                                onClick = {
                                    showMenu = false
                                    openUrl(context, "https://music.apple.com/jp/song/${song!!.appleMusicId}")
                                }
                            )
                        }
                        // 編集導線。BAN 済みには出さない (押しても 403 になるだけ)。判定はコア。
                        if (song != null && canEditHere) {
                            DropdownMenuItem(
                                text = { Text("この楽曲を編集") },
                                onClick = {
                                    showMenu = false
                                    startCommunityEdit { showSongEdit = true }
                                }
                            )
                        }
                        if (song != null && canEditHere) {
                            DropdownMenuItem(
                                text = { Text(if (song.note.isNullOrBlank()) "補足を書く" else "補足を直す") },
                                onClick = {
                                    showMenu = false
                                    startCommunityEdit { showNoteEdit = true }
                                }
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("編集履歴") },
                            onClick = {
                                showMenu = false
                                showRecordHistory = true
                            }
                        )
                    }
                }
            )
        }
    ) { padding ->
        val song = uiState.song
        if (uiState.isLoading || song == null) {
            com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState(modifier = Modifier.fillMaxSize().padding(padding))
        } else {
            SongSheetContent(
                state = uiState, song = song,
                modifier = Modifier.fillMaxSize().padding(padding),
                authState = authState,
                onIdolClick = onIdolClick, onShowClick = onShowClick,
                onSongClick = { id -> currentSongId = id },
                onToggleFavorite = viewModel::toggleFavorite,
                onToggleCardOwned = viewModel::toggleCardOwned,
                // 外す方向はゲートしない (iOS も自分が付けたタグの取り消しは contextMenu で素通し)。
                // 付ける方向だけ共通ゲートを通す — チップのタップはタグ投票の書き込みなので、
                // ボタンを隠すだけでは未ログイン/BAN 済みが投票し続けられてしまう。
                onToggleTag = { tag ->
                    if (tag.mine) viewModel.toggleTag(tag) else startCommunityEdit { viewModel.toggleTag(tag) }
                },
                onOpenTagPicker = { startCommunityEdit { showTagPicker = true } },
                onTagDetailClick = { tagDetailId = it },
                onCreateVideo = { startCommunityEdit { editingVideo = null; showVideoSheet = true } },
                onEditVideo = { video -> startCommunityEdit { editingVideo = video; showVideoSheet = true } },
                onOpenPenlightVote = { startCommunityEdit { showPenlightSheet = true } },
                onUnitClick = onUnitClick,
                onPollClick = onPollClick,
                onFilteredSongsClick = onFilteredSongsClick,
                onEditNote = if (canEditHere) ({ startCommunityEdit { showNoteEdit = true } }) else null
            )
        }
    }

    if (showTagPicker) {
        SongTagPickerSheet(
            songId = currentSongId,
            alreadyAppliedTagIds = uiState.tags.filter { it.mine }.map { it.id }.toSet(),
            onDismiss = { showTagPicker = false },
            onApplied = { viewModel.onTagsApplied() }
        )
    }

    if (showPenlightSheet) {
        PenlightVoteSheet(
            songId = currentSongId,
            onDismiss = { showPenlightSheet = false },
            onVoted = { viewModel.onPenlightVoted() }
        )
    }

    if (showVideoSheet) {
        VideoEditSheet(
            songId = currentSongId,
            existing = editingVideo,
            onDismiss = { showVideoSheet = false },
            // 参考動画は VM に差分反映の口が無いので、保存後に読み直して一覧へ載せる。
            onSaved = { reloadToken++ }
        )
    }

    // 編集フォームはフルスクリーン Dialog に載せる (RecentEditsScreen → SetlistEditScreen と同じ)。
    val editingSong = uiState.song
    if (showSongEdit && editingSong != null) {
        Dialog(
            onDismissRequest = { showSongEdit = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            SongEditScreen(
                original = editingSong,
                onDismiss = { showSongEdit = false },
                onSaved = { showSongEdit = false; reloadToken++ }
            )
        }
    }

    if (showNoteEdit && editingSong != null) {
        Dialog(
            onDismissRequest = { showNoteEdit = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            SongNoteEditScreen(
                song = editingSong,
                onDismiss = { showNoteEdit = false },
                onSaved = { showNoteEdit = false; reloadToken++ }
            )
        }
    }

    if (showRecordHistory) {
        RecordHistorySheet(
            recordType = "Song",
            recordName = currentSongId,
            onDismiss = { showRecordHistory = false }
        )
    }

    if (showLoginPrompt) {
        CommunityLoginPromptDialog(onDismiss = { showLoginPrompt = false })
    }
}

private fun lyricsUrl(song: Song?): String {
    if (song == null) return "https://www.uta-net.com"
    if (!song.lyricsUrl.isNullOrEmpty()) return song.lyricsUrl
    val encoded = java.net.URLEncoder.encode(song.title, "UTF-8")
    return "https://www.uta-net.com/search/?Keyword=$encoded"
}

private fun openUrl(context: android.content.Context, url: String) {
    runCatching {
        context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url)))
    }
}

/** songs.song_type の生値 → 表示ラベル。曲一覧の絞り込みチップと絞り込み一覧のタイトルも同じラベルを出す。 */
internal fun songTypeLabel(songType: String): String = Vocab.songType(songType)?.shortLabel ?: songType

private fun formatDuration(sec: Int?): String? {
    if (sec == null || sec <= 0) return null
    return "%d:%02d".format(sec / 60, sec % 60)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SongSheetContent(
    state: SongDetailUiState,
    song: Song,
    modifier: Modifier,
    authState: AuthState,
    onIdolClick: (String) -> Unit,
    onShowClick: (String) -> Unit,
    onSongClick: (String) -> Unit,
    onToggleFavorite: () -> Unit,
    onToggleCardOwned: () -> Unit,
    onToggleTag: (com.fugaif.imaslivedb.data.community.CommunityApi.SongTag) -> Unit,
    onOpenTagPicker: () -> Unit,
    onTagDetailClick: (String) -> Unit,
    onCreateVideo: () -> Unit,
    onEditVideo: (SongVideo) -> Unit,
    onOpenPenlightVote: () -> Unit,
    onUnitClick: (String) -> Unit,
    onPollClick: (String) -> Unit,
    onFilteredSongsClick: (String, String) -> Unit,
    onEditNote: (() -> Unit)?
) {
    // 配色シード: ソロ (歌唱1人) はその個人カラー、それ以外はブランド色 (brand は各部品に別途渡す)。
    val seed = if (state.originalArtists.size == 1) state.originalArtists.first().color else null
    var segment by rememberSaveable(song.id) { mutableIntStateOf(0) }

    val scroll = rememberScrollState()
    Column(modifier = modifier.verticalScroll(scroll)) {
        Hero(song, state, seed, onToggleFavorite, onToggleCardOwned)
        ImasBoard(
            cells = boardCells(state),
            modifier = Modifier.padding(horizontal = DS.sp5, vertical = DS.sp4)
        )
        ImasTabs(
            labels = listOf("情報・歌唱", "披露履歴", "コミュニティ"),
            selection = segment, onSelect = { segment = it },
            seed = seed, brand = song.brandId,
            modifier = imasResetScrollOnTabChange(scroll, segment).fillMaxWidth().padding(horizontal = DS.sp5)
        )
        when (segment) {
            0 -> InfoTab(
                song, state, seed, onIdolClick, onUnitClick, onSongClick, onShowClick,
                onRegisterAttendance = { segment = 1 },
                onFilteredSongsClick = onFilteredSongsClick,
                onEditNote = onEditNote
            )
            1 -> HistoryTab(
                state.performanceHistory, state.performanceEvidence, seed, song.brandId,
                onShowClick, onSongClick, onIdolClick
            )
            else -> CommunityTab(
                state, seed, song.brandId, authState, onSongClick,
                onToggleTag, onOpenTagPicker, onTagDetailClick,
                onCreateVideo, onEditVideo,
                onOpenPenlightVote, onPollClick
            )
        }
        Box(Modifier.size(DS.sp9))
    }
}

/** 披露・回収・最終披露 (今ある数をそのまま電光掲示板で)。 */
private fun boardCells(state: SongDetailUiState): List<ImasBoardCell> = buildList {
    add(ImasBoardCell(value = "${state.performanceHistory.size}", unit = "回", label = "披露"))
    if (state.collectedShows.isNotEmpty()) {
        add(ImasBoardCell(value = "${state.collectedShows.size}", unit = "公演", label = "回収"))
    }
    // 並び順を仮定せず、日付の最大値を直接取る (配信順が将来変わっても壊れない)。
    state.performanceHistory.maxOfOrNull { it.date }?.let { last ->
        add(ImasBoardCell(value = shortYearMonth(date = last), label = "最終披露"))
    }
}

/**
 * 頭 (iOS `SongSheetContent.hero` / D2)。ジャケを左に置き、右に種類・題・歌唱者・配信日を
 * 先に読ませる。地は常に紙面 (色の地 `heroSurface` は使わない。DS §6.9)。
 */
@Composable
private fun Hero(
    song: Song,
    state: SongDetailUiState,
    seed: String?,
    onToggleFavorite: () -> Unit,
    onToggleCardOwned: () -> Unit
) {
    val artistLine = when {
        state.originalArtists.isNotEmpty() -> state.originalArtists.joinToString(" / ") { it.name }
        !song.singerLabel.isNullOrEmpty() -> song.singerLabel
        !song.unitName.isNullOrEmpty() -> song.unitName
        else -> null
    }
    val typeLabel = song.songType.takeIf { it.isNotEmpty() && it != "unknown" }?.let { songTypeLabel(it) }
    val eyebrow = listOfNotNull(typeLabel, state.brand?.shortName).joinToString(" ・ ").ifEmpty { null }
    val releaseMeta = listOfNotNull(
        song.releaseDate?.takeIf { it.isNotEmpty() },
        formatDuration(song.durationSec)
    ).joinToString(" ・ ").ifEmpty { null }
    val note = song.note?.takeIf { it.isNotBlank() }
    val playbackState by AudioPreviewManager.playbackState.collectAsState()
    val isPreviewing = playbackState.isPlaying(song.id)
    val canPlay = !song.previewUrl.isNullOrEmpty()
    val isCardOwned = state.isCardOwned

    ImasHero(
        title = song.title,
        layout = ImasHeroLayout.LEADING,
        eyebrow = eyebrow,
        media = {
            ArtworkImage(
                url = song.artworkUrl, size = 116.dp, previewUrl = song.previewUrl,
                songTitle = song.title, songId = song.id, seed = seed, brand = song.brandId
            )
        },
        facts = {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                if (artistLine != null) {
                    // 色の点は付けない (名前の横の点は何も伝えない)。
                    ImasText(artistLine, ImasTextRole.ROW_SUBTITLE)
                }
                if (releaseMeta != null) {
                    ImasText(releaseMeta, ImasTextRole.IMPRINT, color = DS.ink3)
                }
                // 曲の補足 (「ミリシタ 1 周年記念楽曲」など)。どのタブでも曲の位置づけが分かるよう、
                // 曲名・歌唱者のすぐ下に 1 文で添える (iOS の Hero と同じ位置)。無い曲は何も出さない。
                if (note != null) {
                    ImasText(note, ImasTextRole.NOTE, maxLines = 3)
                }
                if (song.hasKamisabiCard) {
                    ImasChip(text = kamisabiCardLabel(), style = ImasChipStyle.THEMED, seed = seed, brand = song.brandId)
                }
            }
        }
    )

    // 再生 (主ボタン 1 つ) + 印のボタン (お気に入り・KAMISABI 所持)。今ある操作だけ残す。
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.sp5, vertical = DS.sp3),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasButton(
            title = if (isPreviewing) "停止" else "再生",
            onClick = { if (canPlay) AudioPreviewManager.togglePreview(song.previewUrl!!, song.id) },
            icon = if (isPreviewing) Icons.Filled.Stop else Icons.Filled.PlayArrow,
            role = ImasButtonRole.PRIMARY,
            size = ImasButtonSize.LARGE,
            enabled = canPlay,
            modifier = Modifier.weight(1f)
        )
        ImasMarkButton(kind = ImasMarkKind.FAVORITE, isOn = state.isFavorite, onClick = onToggleFavorite)
        // KAMISABI (音楽カードゲーム) 収録曲のときだけ、カード所持のトグルを出す。
        // 未収録曲にトグルを出すと「持っていない」のか「そもそも対象外」なのか読み取れなくなる。
        if (song.hasKamisabiCard) {
            ImasMarkTile(
                icon = if (isCardOwned) Icons.Filled.Inventory2 else Icons.Outlined.Inventory2,
                label = "カード所持",
                isOn = isCardOwned,
                onClick = onToggleCardOwned,
                accessibilityText = if (isCardOwned) "カード所持済み" else "カード所持を記録"
            )
        }
    }
    // 分母はブランド (商品) 単位。KAMISABI は ML/SideM/シャニの別商品なので合算しない。
    // 言い回しも kamisabiCompletionLabel() をそのまま出す (「枚」ではなく「曲」で数える)。
    if (song.hasKamisabiCard) {
        state.kamisabiCompletion?.let { completion ->
            ImasNote(kamisabiCompletionLabel(completion), modifier = Modifier.padding(horizontal = DS.sp5))
        }
    }
}

@Composable
private fun InfoTab(
    song: Song,
    state: SongDetailUiState,
    seed: String?,
    onIdolClick: (String) -> Unit,
    onUnitClick: (String) -> Unit,
    onSongClick: (String) -> Unit,
    onShowClick: (String) -> Unit,
    onRegisterAttendance: () -> Unit,
    onFilteredSongsClick: (String, String) -> Unit,
    onEditNote: (() -> Unit)?
) {
    val artistLine = when {
        state.originalArtists.isNotEmpty() -> state.originalArtists.joinToString(" / ") { it.name }
        !song.singerLabel.isNullOrEmpty() -> song.singerLabel
        !song.unitName.isNullOrEmpty() -> song.unitName
        else -> null
    }
    Column(
        modifier = Modifier.padding(horizontal = DS.sp5, vertical = DS.sp4),
        verticalArrangement = Arrangement.spacedBy(DS.sp5)
    ) {
        // 披露 / 現地回収
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp4)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.sp3)) {
                ImasStatTile(Icons.Filled.Mic, "${state.performanceHistory.size}", "披露回数", unit = "回",
                    seed = seed, brand = song.brandId, modifier = Modifier.weight(1f))
                ImasStatTile(Icons.Filled.CheckCircle, "${state.collectedShows.size}", "現地回収", unit = "公演",
                    seed = seed, brand = song.brandId, modifier = Modifier.weight(1f))
            }
            ImasButton(
                title = "参加ライブを登録して現地回収",
                onClick = onRegisterAttendance,
                icon = Icons.Filled.Add,
                role = ImasButtonRole.SECONDARY,
                size = ImasButtonSize.MEDIUM,
                fillsWidth = true
            )
            if (state.collectedShows.isNotEmpty()) {
                ImasCardList {
                    state.collectedShows.forEachIndexed { idx, show ->
                        if (idx > 0) ImasRowDivider(inset = DS.sp5)
                        ImasRow(
                            title = AppPreferences.eventDisplayName(show.eventName),
                            subtitle = listOf(show.name, show.date).filter { it.isNotEmpty() }.joinToString(" ・ "),
                            leading = ImasRowLeading.Icon(Icons.Filled.CheckCircle, tone = ImasIconTileTone.POSITIVE),
                            trailing = ImasRowTrailing.Chevron,
                            density = ImasRowDensity.COMPACT,
                            modifier = Modifier.imasRowClick { onShowClick(show.id) }
                        )
                    }
                }
            }
        }
        // 楽曲情報
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
            ImasSectionHeader("楽曲情報", tight = true)
            val rows = buildList<@Composable () -> Unit> {
                // 「よみ」は検索で使う値。画面に出しておかないと、間違っていても
                // 「この曲が出てこない」としか思われず直しようがない (機械生成ぶんが混ざっている)。
                song.titleKana?.takeIf { it.isNotEmpty() }?.let { v -> add { FieldRow(key = "よみ", value = v) } }
                artistLine?.takeIf { it.isNotEmpty() }?.let { v -> add { FieldRow(key = "アーティスト", value = v) } }
                // 以降、値そのものが「同じ条件の曲の集合」を指す行は一覧へ抜けられるようにする。
                // ここが唯一の入口の条件もある (シリーズや作家は一覧の絞り込み UI に無い)。
                state.brand?.let { brand ->
                    add { FieldRow(key = "ブランド", value = brand.shortName, onClick = { onFilteredSongsClick(SongFilterKind.BRAND, brand.id) }) }
                }
                if (song.songType.isNotEmpty() && song.songType != "unknown") {
                    add { FieldRow(key = "タイプ", value = songTypeLabel(song.songType), onClick = { onFilteredSongsClick(SongFilterKind.SONG_TYPE, song.songType) }) }
                }
                // 「YYYY-...」から年だけ取れたときにリリース年の一覧へ。年が読めない表記
                // (未定・年だけ等) は押せない普通の行に落とす — 行き先が作れないため。
                val releaseYear = song.releaseDate?.take(4)?.takeIf { it.length == 4 && it.toIntOrNull() != null }
                song.releaseDate?.takeIf { it.isNotEmpty() }?.let { date ->
                    if (releaseYear != null) {
                        add { FieldRow(key = "リリース日", value = date, onClick = { onFilteredSongsClick(SongFilterKind.RELEASE_YEAR, releaseYear) }) }
                    } else {
                        add { FieldRow(key = "リリース日", value = date) }
                    }
                }
                formatDuration(song.durationSec)?.let { v -> add { FieldRow(key = "再生時間", value = v) } }
                // クレジットは 1 欄に複数名が入るので、行ごとではなく名前ごとに押せるようにする。
                // 欄の割り方はコア (splitCreditNames) が唯一の正。
                song.composer?.let { v -> add { CreditRow("作曲", v, seed, song.brandId, onFilteredSongsClick) } }
                song.lyricist?.let { v -> add { CreditRow("作詞", v, seed, song.brandId, onFilteredSongsClick) } }
                song.arranger?.let { v -> add { CreditRow("編曲", v, seed, song.brandId, onFilteredSongsClick) } }
                song.seriesGroup?.takeIf { it.isNotEmpty() }?.let { series ->
                    add { FieldRow(key = "シリーズ", value = series, onClick = { onFilteredSongsClick(SongFilterKind.SERIES_GROUP, series) }) }
                }
                song.cdSeries?.takeIf { it.isNotEmpty() }?.let { cdSeries ->
                    add { FieldRow(key = "CDシリーズ", value = cdSeries, onClick = { onFilteredSongsClick(SongFilterKind.CD_SERIES, cdSeries) }) }
                }
                song.cdTitle?.takeIf { it.isNotEmpty() }?.let { v -> add { FieldRow(key = "収録", value = v) } }
                state.unit?.let { unit ->
                    add { FieldRow(key = "ユニット", value = unit.name, onClick = { onUnitClick(unit.id) }) }
                }
            }
            ImasCardList {
                rows.forEachIndexed { idx, row ->
                    if (idx > 0) ImasRowDivider(inset = DS.sp5)
                    row()
                }
            }
            // 補足の入口。補足は利用者の投稿で増やしたいので、楽曲情報のすぐ下に置く (iOS と同じ)。
            // 補足がある曲は本文は Hero に出ているので「直す」だけ、無い曲は何を書くかの例を添える。
            NoteEntry(song.note?.takeIf { it.isNotBlank() }, seed, song.brandId, onEditNote)
        }
        // 歌唱アイドル
        if (state.originalArtists.isNotEmpty()) {
            IdolGridSection("歌唱アイドル", state.originalArtists, onIdolClick)
        }
        // ライブ歌唱歴
        if (state.performerArtists.isNotEmpty()) {
            IdolGridSection("ライブ歌唱歴", state.performerArtists, onIdolClick)
        }
        // 関連楽曲 (同シリーズ/ユニット/原唱共有)
        if (state.relatedSongs.isNotEmpty()) {
            RelatedSongsSection("関連楽曲", state.relatedSongs, seed, song.brandId, badge = null, onSongClick = onSongClick)
        }
    }
}

/**
 * 値だけの「項目: 値」行。値が押せる (他画面へ抜ける) ときだけ [onClick] を渡す。
 * 名前を `ImasRow` (DS の行の素の形) と分けているのは、同じファイルで両方使うため。
 */
@Composable
private fun FieldRow(key: String, value: String, onClick: (() -> Unit)? = null) {
    ImasValueRow(key = key, value = value, isLink = onClick != null, onClick = onClick)
}

/**
 * クレジット行 (作曲 / 作詞 / 編曲)。欄を人ごとに割って、名前 1 つずつを
 * 「その人が関わった楽曲」へのリンクにする。
 *
 * 欄の割り方はコア (`splitCreditNames`) が唯一の正 — 括弧の外は 5 種類の区切りで割り、
 * 括弧の中は `・` と `、` だけで割る (`,` `/` は社名の一部)。ここで書き直すと
 * 一覧側の突き合わせ (コアの songsByCreator) とずれて、同じ人が二通りに分かれるか一覧が 0 件になる。
 * 複数名が独立してタップできる行は `ImasValueRow` では表現できないため据え置き
 * (寸法だけ DS のトークンに揃える)。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CreditRow(
    key: String,
    value: String,
    seed: String?,
    brand: String?,
    onFilteredSongsClick: (String, String) -> Unit
) {
    // 空白だけの断片 (欄が "/" だけ等) は人名ではないので落とす。ルート引数が空になると
    // 行き先のパスが組み立たず、押した瞬間に落ちる。
    val names = remember(value) { splitCreditNames(value).filter { it.isNotBlank() } }
    if (names.isEmpty()) return
    val t = imasThemeForBrand(seed, brand)
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap)
    ) {
        ImasText(key, ImasTextRole.VALUE, color = DS.ink2)
        Box(Modifier.weight(1f))
        // 名前は右寄せで「A / B」と並べる。区切りの "/" は押せない (人ではないので)。
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
            verticalArrangement = Arrangement.spacedBy(DS.sp1)
        ) {
            names.forEachIndexed { index, name ->
                if (index > 0) ImasText("/", ImasTextRole.VALUE, color = DS.ink3)
                ImasText(
                    name, ImasTextRole.VALUE, color = t.accent,
                    modifier = Modifier.clickable { onFilteredSongsClick(SongFilterKind.CREATOR, name) }
                )
            }
        }
    }
}

/** 関連 / おすすめ楽曲の一覧節。「関連楽曲」(ローカル算出)・「この曲が好きな人にはこれも」(タグ類似) が同じ見た目を使う。 */
@Composable
private fun RelatedSongsSection(
    title: String,
    songs: List<Song>,
    seed: String?,
    brand: String?,
    badge: Map<String, Int>?,
    onSongClick: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
        ImasSectionHeader(title, count = "${songs.size}")
        ImasCardList {
            songs.forEachIndexed { idx, s ->
                if (idx > 0) ImasRowDivider(inset = DS.sp5 + 44.dp)
                RelatedSongRow(s, seed, brand, badge?.get(s.id), onClick = { onSongClick(s.id) })
            }
        }
    }
}

/** 関連/おすすめ楽曲・共起曲が共有する行の見た目 (iOS `RelatedSongRow`)。見た目は DS の [ImasSongRow]。 */
@Composable
private fun RelatedSongRow(song: Song, seed: String?, brand: String?, badge: Int?, subtitle: String? = null, onClick: () -> Unit) {
    ImasSongRow(
        title = song.title,
        subtitle = subtitle ?: (song.singerLabel ?: song.unitName),
        artworkUrl = song.artworkUrl,
        seed = seed,
        brand = brand,
        density = ImasRowDensity.COMPACT,
        trailing = if (badge != null) {
            ImasRowTrailing.Custom {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight), verticalAlignment = Alignment.CenterVertically) {
                    ImasText("タグ${badge}個一致", ImasTextRole.META)
                    com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron()
                }
            }
        } else {
            ImasRowTrailing.Chevron
        },
        onClick = onClick
    )
}

/** 楽曲情報の下の補足 (iOS `SongInfoTab.noteEntry` と同じ見た目と文言)。 */
@Composable
private fun NoteEntry(note: String?, seed: String?, brandId: String?, onEdit: (() -> Unit)?) {
    val t = imasThemeForBrand(seed, brandId)
    if (note != null) {
        // ある曲は本文が主役。直す導線は見出しの右に小さく添える (iOS SongInfoTab と同じ)。
        ImasCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ImasText("この曲の補足", ImasTextRole.SECTION_LABEL, modifier = Modifier.weight(1f))
                if (onEdit != null) {
                    ImasText(
                        "直す", ImasTextRole.EYEBROW, color = t.accent,
                        modifier = Modifier.clickable(onClick = onEdit)
                    )
                }
            }
            SelectionContainer {
                ImasText(note, ImasTextRole.VALUE, modifier = Modifier.padding(top = DS.Space.gapTight))
            }
        }
        return
    }
    if (onEdit == null) return
    ImasEntryCard(
        icon = Icons.Filled.Edit,
        title = "補足を書く",
        preview = "「◯周年記念楽曲」「アニメ◯話の挿入歌」など、この曲の由来を 1 文で",
        seed = seed,
        brand = brandId,
        onClick = onEdit
    )
}

/**
 * 「披露履歴」タブ。総披露 / 初披露 / 最終披露、披露実績から出した歌唱者と共起曲、
 * そして公演ごとの履歴一覧。
 *
 * 節の並びは「数の要約 → 公演の一覧 → 歌った人 → 同じ公演の曲」。開いて最初に見たいのは
 * どのライブで歌われたかなので、一覧を要約のすぐ下に置く (iOS の SongHistoryTab と同じ並び)。
 */
@Composable
private fun HistoryTab(
    history: List<PerformanceHistoryRow>,
    evidence: SongPerformanceEvidence,
    seed: String?,
    brand: String?,
    onShowClick: (String) -> Unit,
    onSongClick: (String) -> Unit,
    onIdolClick: (String) -> Unit
) {
    if (history.isEmpty()) {
        ImasEmptyState(Icons.Filled.MusicNote, "披露履歴はまだありません",
            "この曲がライブで披露されると、ここに記録されます。", seed = seed, brand = brand,
            modifier = Modifier.padding(top = DS.sp4))
        return
    }
    Column(
        modifier = Modifier.padding(horizontal = DS.sp5, vertical = DS.sp4),
        verticalArrangement = Arrangement.spacedBy(DS.sp5)
    ) {
        val sortedByDateAsc = history.sortedBy { it.date }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.sp3)) {
            ImasStatTile(Icons.Filled.Mic, "${history.size}", "総披露", unit = "回", seed = seed, brand = brand, modifier = Modifier.weight(1f))
            ImasStatTile(Icons.Filled.CalendarMonth, shortYearMonth(date = sortedByDateAsc.first().date), "初披露", seed = seed, brand = brand, modifier = Modifier.weight(1f))
            ImasStatTile(Icons.Filled.CalendarMonth, shortYearMonth(date = sortedByDateAsc.last().date), "最終披露", seed = seed, brand = brand, modifier = Modifier.weight(1f))
        }
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
            ImasSectionHeader("ライブ披露履歴", count = "${history.size}回", tight = true)
            ImasCardList {
                history.forEachIndexed { idx, row ->
                    if (idx > 0) ImasRowDivider(inset = DS.sp4)
                    ImasRow(
                        title = AppPreferences.eventDisplayName(row.eventName),
                        subtitle = listOf(row.showName, row.date).filter { it.isNotEmpty() }.joinToString(" ・ "),
                        leading = ImasRowLeading.Bar(seed = seed, brand = brand),
                        trailing = ImasRowTrailing.Chevron,
                        density = ImasRowDensity.COMPACT,
                        modifier = Modifier.imasRowClick { onShowClick(row.showId) }
                    )
                }
            }
        }
        // 披露実績がまだ 1 度も無い曲でだけ中身が空になり、節ごと消える。
        SingersSection(evidence.singers, onIdolClick)
        CoOccurringSection(evidence.coOccurring, seed, brand, onSongClick)
    }
}

/**
 * 「この曲を歌った人」。歌った回数の多い順。副題が根拠 (「よく歌う人」ではなく「何回歌ったか」)。
 * 先頭のアイコンは歌唱者本人の色 ([ImasIdolRow] が `idol.color`/`idol.brandId` を直に読む)。
 */
@Composable
private fun SingersSection(rows: List<SongSingerTally>, onIdolClick: (String) -> Unit) {
    if (rows.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
        ImasSectionHeader("この曲を歌った人", tight = true)
        // 分母 (全 N 回) は上のサマリタイル「総披露」と同じ数え方。同じ画面に単位の違う
        // 数字 (共起節は公演数) が並ぶので、どちらなのかを言っておく。
        ImasNote("セトリに残っている歌唱の集計です。分母は上の「総披露」と同じ回数です。")
        ImasCardList {
            rows.forEachIndexed { idx, row ->
                if (idx > 0) ImasRowDivider(inset = DS.sp5 + 36.dp)
                ImasIdolRow(
                    idol = row.idol,
                    subtitle = "${row.times}回 ／ 全${row.total}回",
                    density = ImasRowDensity.COMPACT,
                    onClick = { onIdolClick(row.idol.id) }
                )
            }
        }
    }
}

/**
 * 「同じ公演で歌われた曲」。一緒に来た**公演数**の多い順。
 * 行の形は [RelatedSongRow] と同じだが、副題は歌唱表記ではなく**根拠の回数**。
 */
@Composable
private fun CoOccurringSection(rows: List<CoOccurringSong>, seed: String?, brand: String?, onSongClick: (String) -> Unit) {
    if (rows.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
        ImasSectionHeader("同じ公演で歌われた曲", tight = true)
        // ⚠️ ここだけ単位が「公演」。1 公演で 2 回演奏されても 1 と数えるため、相手の曲を
        // 開いた先の「総披露 N 回」(セトリ行数) より小さい数になる。単位を書かないと
        // 「どちらが本当の回数か」が読み手に判断できない。
        ImasNote("同じ公演に両方あった公演数です (1 公演で 2 回歌っても 1 公演)。次のライブで一緒に来るとは限りません。")
        ImasCardList {
            rows.forEachIndexed { idx, row ->
                if (idx > 0) ImasRowDivider(inset = DS.sp5 + 44.dp)
                RelatedSongRow(
                    song = row.song, seed = seed, brand = brand, badge = null,
                    subtitle = "いっしょに${row.together}公演 ／ 全${row.performances}公演",
                    onClick = { onSongClick(row.song.id) }
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
private fun CommunityTab(
    state: SongDetailUiState, seed: String?, brand: String?, authState: AuthState,
    onSongClick: (String) -> Unit,
    onToggleTag: (com.fugaif.imaslivedb.data.community.CommunityApi.SongTag) -> Unit,
    onOpenTagPicker: () -> Unit,
    onTagDetailClick: (String) -> Unit,
    onCreateVideo: () -> Unit,
    onEditVideo: (SongVideo) -> Unit,
    onOpenPenlightVote: () -> Unit,
    onPollClick: (String) -> Unit
) {
    val context = LocalContext.current
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる。
    val canEditHere = remember(authState) { authState.showEditAffordance }
    val needsLogin = remember(authState) { authState.shouldPromptLogin }
    Column(
        modifier = Modifier.padding(horizontal = DS.sp5, vertical = DS.sp4),
        verticalArrangement = Arrangement.spacedBy(DS.sp5)
    ) {
        state.song?.let { song ->
            com.fugaif.imaslivedb.ui.polls.PollAchievementBadges(entityId = song.id, onOpenPoll = onPollClick)
        }
        // shouldPromptLogin は BAN 済みを「無反応」に倒す (iOS の .ignore と同じ)。
        // ImasSignInPrompt 自身の isSignedIn チェックはこのゲートの内側でだけ働く。
        if (needsLogin) {
            ImasSignInPrompt(message = "タグ・動画・投票にはログインが必要です")
        }
        // タグ (集計系コミュニティ・Worker D1)。タップで自分の投票をトグル、長押しでタグ詳細、+ で全タグから追加。
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
            ImasSectionHeader(
                "タグ", count = "${state.tags.size}",
                actionTitle = if (canEditHere) "タグを追加" else null,
                actionIcon = if (canEditHere) Icons.Filled.Add else null,
                onAction = if (canEditHere) onOpenTagPicker else null
            )
            if (state.tags.isEmpty()) {
                ImasEmptyState(Icons.Filled.Sell, "タグはまだありません", seed = seed, brand = brand)
            } else {
                com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow {
                    state.tags.forEach { tag ->
                        val label = if (tag.voteCount > 0) "${tag.name} ${tag.voteCount}" else tag.name
                        ImasChip(
                            text = label,
                            style = if (tag.mine) ImasChipStyle.SELECTED else ImasChipStyle.THEMED,
                            seed = seed,
                            brand = brand,
                            modifier = Modifier.combinedClickable(
                                onClick = { onToggleTag(tag) },
                                onLongClick = { onTagDetailClick(tag.id) }
                            )
                        )
                    }
                }
            }
        }
        // この曲が好きな人にはこれも (タグが似ている楽曲, サーバ算出)
        if (state.similarTagSongs.isNotEmpty()) {
            RelatedSongsSection("この曲が好きな人にはこれも", state.similarTagSongs, seed, brand, state.similarSharedTags, onSongClick)
        }
        // ペンライト投票 (集計系・Worker D1)
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
            ImasSectionHeader(
                "ペンライト", count = state.penlight?.totalVotes?.let { "${it}票" },
                actionTitle = if (canEditHere) "投票する" else null,
                actionIcon = if (canEditHere) Icons.Filled.Add else null,
                onAction = if (canEditHere) onOpenPenlightVote else null
            )
            val sets = state.penlight?.topSets ?: emptyList()
            if (sets.isEmpty()) {
                ImasEmptyState(Icons.Filled.Star, "まだ投票がありません",
                    "あなたが思うこの曲のペンライト色を投票しませんか？", seed = seed, brand = brand)
            } else {
                ImasCardList {
                    sets.take(5).forEachIndexed { idx, ps ->
                        if (idx > 0) ImasRowDivider(inset = DS.sp5)
                        PenlightRow(ps)
                    }
                }
            }
        }
        // 参考動画 (構造化コミュニティ・CloudKit 直書き。POST /edits 経由で全ユーザーが投稿/編集可能)
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
            ImasSectionHeader(
                "参考動画", count = "${state.songVideos.size}",
                actionTitle = if (canEditHere) "参考動画を追加" else null,
                actionIcon = if (canEditHere) Icons.Filled.Add else null,
                onAction = if (canEditHere) onCreateVideo else null
            )
            if (state.songVideos.isEmpty()) {
                ImasEmptyState(Icons.Filled.OndemandVideo, "参考動画はまだありません",
                    "ライブ映像などの参考動画を共有しませんか？", seed = seed, brand = brand)
            } else {
                // id とサムネイルの URL はコアが読む (一覧で 1 回)。
                val refs = remember(state.songVideos) { youtubeVideoRefs(state.songVideos.map { it.youtubeUrl }) }
                ImasCardList {
                    state.songVideos.forEachIndexed { index, video ->
                        if (index > 0) ImasRowDivider(inset = DS.sp5)
                        VideoRow(video, refs.getOrNull(index), canEditHere, onEditVideo) { openUrl(context, video.youtubeUrl) }
                    }
                }
            }
        }
    }
}

@Composable
private fun VideoRow(
    video: SongVideo,
    ref: uniffi.imas_core.YouTubeVideoRef?,
    canEditHere: Boolean,
    onEditVideo: (SongVideo) -> Unit,
    onOpenVideo: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpenVideo).padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(56.dp).clip(RoundedCornerShape(DS.rSM)).background(DS.fill),
            contentAlignment = Alignment.Center
        ) {
            ref?.thumbnailUrl?.let { thumbnail ->
                // 高解像度 (maxresdefault) が無い動画は mqdefault に落とす (iOS と同じ)。
                SubcomposeAsyncImage(
                    model = thumbnail,
                    contentDescription = video.videoTitle,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(56.dp).clip(RoundedCornerShape(DS.rSM)),
                    error = {
                        ref.fallbackThumbnailUrl?.let { fallback ->
                            SubcomposeAsyncImage(
                                model = fallback,
                                contentDescription = video.videoTitle,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.size(56.dp).clip(RoundedCornerShape(DS.rSM))
                            )
                        }
                    }
                )
            }
            // 下の写真は何色か分からないので、記号は実体色でなく固定の白にする
            // (ImasMediaBadge と同じ考え方。写真の上に乗せる記号だけの例外)。
            androidx.compose.material3.Icon(
                Icons.Filled.PlayArrow, contentDescription = null,
                tint = androidx.compose.ui.graphics.Color.White,
                modifier = Modifier.size(22.dp)
            )
        }
        Column(Modifier.weight(1f).padding(start = DS.Space.rowGap), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            ImasText(video.videoTitle ?: video.youtubeUrl, ImasTextRole.VALUE, maxLines = 1, overflow = TextOverflow.Ellipsis)
            video.note?.takeIf { it.isNotEmpty() }?.let { note -> ImasText(note, ImasTextRole.META, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            video.authorDisplayName?.takeIf { it.isNotEmpty() }?.let { author -> ImasText("投稿者: $author", ImasTextRole.META, color = DS.ink3) }
        }
        if (canEditHere) {
            ImasIconButton(
                icon = Icons.Filled.Edit, label = "参考動画を編集", size = ImasIconButtonSize.SMALL,
                style = ImasIconButtonStyle.PLAIN, onClick = { onEditVideo(video) }
            )
        }
    }
}

@Composable
private fun PenlightRow(set: com.fugaif.imaslivedb.data.community.CommunityApi.PenlightSet) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowVCompact),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.sp3)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.sp1)) {
            set.colors.take(4).forEach { hex ->
                Box(Modifier.size(20.dp).clip(RoundedCornerShape(DS.rXS)).background(hexToColor(hex)))
            }
        }
        Box(Modifier.weight(1f))
        com.fugaif.imaslivedb.ui.designsystem.ImasMetric("${set.count}", size = com.fugaif.imaslivedb.ui.theme.ImasNumeralSize.SMALL)
    }
}

/** 行の全体を押せるようにする (`ImasNavRow` 等が内部で使うのと同じ押し心地)。 */
@Composable
private fun Modifier.imasRowClick(onClick: () -> Unit): Modifier = imasRowPress(onClick = onClick)
