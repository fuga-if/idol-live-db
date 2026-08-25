package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.text.selection.SelectionContainer
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.OndemandVideo
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.data.auth.AuthState
import com.fugaif.imaslivedb.data.auth.shouldPromptLogin
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongCall
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.IdolGridSection
import com.fugaif.imaslivedb.ui.components.ImasLabeledRow
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.components.ImasStatTile
import com.fugaif.imaslivedb.ui.tags.SongTagPickerSheet
import com.fugaif.imaslivedb.ui.tags.TagDetailScreen
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.hexToColor
import uniffi.imas_core.shortYearMonth

/**
 * 楽曲詳細。iOS の SongSheetContent (大ジャケ hero + ImasSegmented 3 タブ
 * [情報・歌唱/披露履歴/コミュニティ]) の構成を 1:1 で写す。
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
    viewModel: SongDetailViewModel = viewModel(key = songId)
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    var showTagPicker by rememberSaveable { mutableStateOf(false) }
    var showCallSheet by rememberSaveable { mutableStateOf(false) }
    var showPenlightSheet by rememberSaveable { mutableStateOf(false) }
    var editingCall by remember { mutableStateOf<SongCall?>(null) }
    var currentSongId by rememberSaveable(songId) { mutableStateOf(songId) }
    var tagDetailId by rememberSaveable { mutableStateOf<String?>(null) }
    var showMenu by remember { mutableStateOf(false) }
    var showLoginPrompt by rememberSaveable { mutableStateOf(false) }
    val authState by AppModule.from(context).authService.state.collectAsState()

    // 投稿/編集導線の共通ゲート。iOS DetailSheet.handle(intent) と同じで、
    // 「開く/書き込む」操作は全部ここを通す。
    // シート側 (CallEditSheet / PenlightVoteSheet) に権限判定は無いので、
    // ここで止めないとフォームに入力させた末に 401/403 で落ちる。
    //
    // BAN 済みは iOS の .ignore と同じく無反応 (onBanned 既定)。この画面の編集導線は
    // showEditAffordance で全部隠れているので、押せるのはタグチップだけ。
    fun startCommunityEdit(present: () -> Unit) =
        authState.startCommunityEdit(promptLogin = { showLoginPrompt = true }, present = present)

    LaunchedEffect(currentSongId) { viewModel.load(context, currentSongId) }

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
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    val song = uiState.song
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "その他")
                    }
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
                    }
                }
            )
        }
    ) { padding ->
        val song = uiState.song
        if (uiState.isLoading || song == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            SongSheetContent(
                state = uiState, song = song,
                modifier = Modifier.fillMaxSize().padding(padding),
                authState = authState,
                onIdolClick = onIdolClick, onShowClick = onShowClick,
                onSongClick = { id -> currentSongId = id },
                onToggleFavorite = viewModel::toggleFavorite,
                // 外す方向はゲートしない (iOS も自分が付けたタグの取り消しは contextMenu で素通し)。
                // 付ける方向だけ共通ゲートを通す — チップのタップはタグ投票の書き込みなので、
                // ボタンを隠すだけでは未ログイン/BAN 済みが投票し続けられてしまう。
                onToggleTag = { tag ->
                    if (tag.mine) viewModel.toggleTag(tag) else startCommunityEdit { viewModel.toggleTag(tag) }
                },
                onOpenTagPicker = { startCommunityEdit { showTagPicker = true } },
                onTagDetailClick = { tagDetailId = it },
                onCreateCall = { startCommunityEdit { editingCall = null; showCallSheet = true } },
                onEditCall = { call -> startCommunityEdit { editingCall = call; showCallSheet = true } },
                onOpenPenlightVote = { startCommunityEdit { showPenlightSheet = true } },
                onUnitClick = onUnitClick,
                onPollClick = onPollClick
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

    if (showCallSheet) {
        CallEditSheet(
            songId = currentSongId,
            existing = editingCall,
            onDismiss = { showCallSheet = false },
            onSaved = { viewModel.onCallSaved(it) }
        )
    }

    if (showPenlightSheet) {
        PenlightVoteSheet(
            songId = currentSongId,
            onDismiss = { showPenlightSheet = false },
            onVoted = { viewModel.onPenlightVoted() }
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
    onToggleTag: (com.fugaif.imaslivedb.data.community.CommunityApi.SongTag) -> Unit,
    onOpenTagPicker: () -> Unit,
    onTagDetailClick: (String) -> Unit,
    onCreateCall: () -> Unit,
    onEditCall: (SongCall) -> Unit,
    onOpenPenlightVote: () -> Unit,
    onUnitClick: (String) -> Unit,
    onPollClick: (String) -> Unit
) {
    // 配色シード: ソロ (歌唱1人) はその個人カラー、それ以外はブランド色。
    val seed = if (state.originalArtists.size == 1) state.originalArtists.first().color else null
    val t = ImasTheme.derive(seed, song.brandId, dark = true)
    var segment by rememberSaveable(song.id) { mutableIntStateOf(0) }

    Column(modifier = modifier.verticalScroll(rememberScrollState())) {
        Hero(song, state.originalArtists, state.isFavorite, t, onToggleFavorite)
        ImasSegmented(
            labels = listOf("情報・歌唱", "披露履歴", "コミュニティ"),
            selection = segment, onSelect = { segment = it },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
        )
        when (segment) {
            0 -> InfoTab(song, state, seed, onIdolClick, onUnitClick, onSongClick, onShowClick, onRegisterAttendance = { segment = 1 })
            1 -> HistoryTab(state.performanceHistory, seed, song.brandId, onShowClick)
            else -> CommunityTab(
                state, seed, song.brandId, authState, onSongClick,
                onToggleTag, onOpenTagPicker, onTagDetailClick,
                onCreateCall, onEditCall, onOpenPenlightVote, onPollClick
            )
        }
        Box(Modifier.size(24.dp))
    }
}

@Composable
private fun Hero(
    song: Song,
    originalArtists: List<Idol>,
    isFavorite: Boolean,
    t: ImasTheme,
    onToggleFavorite: () -> Unit
) {
    val artistLine = when {
        originalArtists.isNotEmpty() -> originalArtists.joinToString(" / ") { it.name }
        !song.singerLabel.isNullOrEmpty() -> song.singerLabel
        !song.unitName.isNullOrEmpty() -> song.unitName
        else -> null
    }
    val playbackState by AudioPreviewManager.playbackState.collectAsState()
    val isPreviewing = playbackState.isPlaying && playbackState.nowPlayingTitle == song.title
    Column(
        modifier = Modifier.fillMaxWidth().background(t.heroSurface).padding(top = 16.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ArtworkImage(url = song.artworkUrl, size = 168.dp, previewUrl = song.previewUrl, songTitle = song.title)
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 16.dp)) {
            Text(song.title, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (artistLine != null) {
                Text(artistLine, fontSize = 15.sp, color = DS.ink2, textAlign = TextAlign.Center,
                    maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            val canPlay = !song.previewUrl.isNullOrEmpty()
            Row(
                modifier = Modifier.weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(if (canPlay) t.accent else t.accent.copy(alpha = 0.5f))
                    .then(if (canPlay) Modifier.clickable {
                        AudioPreviewManager.togglePreview(song.previewUrl!!, song.title)
                    } else Modifier)
                    .padding(vertical = 11.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    if (isPreviewing) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                    contentDescription = null, tint = t.onAccent, modifier = Modifier.size(18.dp)
                )
                Text(
                    if (isPreviewing) "停止" else "再生", fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    color = t.onAccent, modifier = Modifier.padding(start = 6.dp)
                )
            }
            Row(
                modifier = Modifier.weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(t.chipBg)
                    .clickable(onClick = onToggleFavorite)
                    .padding(vertical = 11.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Filled.Star, contentDescription = null,
                    tint = if (isFavorite) DS.favorite else t.accent, modifier = Modifier.size(18.dp)
                )
                Text(
                    if (isFavorite) "お気に入り済み" else "お気に入り", fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    color = if (isFavorite) DS.favorite else t.accent, modifier = Modifier.padding(start = 6.dp)
                )
            }
        }
    }
}

private fun songTypeLabel(songType: String): String = when (songType) {
    "solo" -> "ソロ"
    "unit", "group" -> "ユニット"
    "all" -> "全体曲"
    "original" -> "オリジナル"
    "unknown" -> "不明"
    else -> songType
}

private fun formatDuration(sec: Int?): String? {
    if (sec == null || sec <= 0) return null
    return "%d:%02d".format(sec / 60, sec % 60)
}

/**
 * 除去対象の作品名プレフィックス。長いものを先に置く —
 * 「THE IDOLM@STER 」が先に当たると「THE IDOLM@STER SideM 」を落とし切れないため、
 * 前方一致は上から順に 1 つだけ適用する。
 */
private val eventNamePrefixes = listOf(
    "THE IDOLM@STER CINDERELLA GIRLS ",
    "THE IDOLM@STER MILLION LIVE! ",
    "THE IDOLM@STER MILLION LIVE!",
    "THE IDOLM@STER SideM ",
    "THE IDOLM@STER SHINY COLORS ",
    "THE IDOLM@STER ",
    "アイドルマスター シンデレラガールズ ",
    "アイドルマスター ミリオンライブ! ",
    "アイドルマスター シャイニーカラーズ ",
    "アイドルマスター SideM ",
    "学園アイドルマスター ",
    "アイドルマスター ",
)

/**
 * ライブ名の先頭を埋める作品名プレフィックスを表示時だけ落とし、公演を識別しやすくする。
 * ブランドはリードバーの色で示しているので、行頭の作品名は冗長なだけ。
 * iOS `Extensions/EventDisplayName.swift` の移植で、iOS は同じ整形を披露履歴・
 * 現地回収一覧の行ラベルに掛けている。
 *
 * core に持たせない理由: これは永続化された表示設定 (iOS `event_name_abbreviate`) に
 * 依存する表示整形で、core は正式名称を返す責務に留める、と生成バインディングの
 * `timelineBars` doc が明示している (「呼び出し側は表示用省略を適用すること」)。
 * Android にはまだ省略 ON/OFF のトグルが無いので iOS の既定値 (ON = 省略) に固定する。
 * トグルを足すときはここへ設定値を渡す。
 *
 * 除去後が短くなりすぎる場合は元の名前を返す — 「THE IDOLM@STER」のような
 * プレフィックスだけのイベント名を空ラベルにしないため。
 * 正式名称が要る箇所 (詳細タイトル・共有文・カレンダー保存名) では使わないこと。
 */
private fun eventDisplayName(name: String): String {
    val prefix = eventNamePrefixes.firstOrNull { name.startsWith(it) } ?: return name
    val stripped = name.removePrefix(prefix).trim()
    return if (stripped.length >= 2) stripped else name
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
    onRegisterAttendance: () -> Unit
) {
    val artistLine = when {
        state.originalArtists.isNotEmpty() -> state.originalArtists.joinToString(" / ") { it.name }
        !song.singerLabel.isNullOrEmpty() -> song.singerLabel
        !song.unitName.isNullOrEmpty() -> song.unitName
        else -> null
    }
    Column(modifier = Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // 披露統計
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ImasStatTile(Icons.Filled.Mic, "${state.performanceHistory.size}", "披露回数", unit = "回",
                    seed = seed, brand = song.brandId, modifier = Modifier.weight(1f))
                ImasStatTile(Icons.Filled.CheckCircle, "${state.collectedShows.size}", "現地回収", unit = "公演",
                    seed = seed, brand = song.brandId, modifier = Modifier.weight(1f))
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                    .clip(RoundedCornerShape(12.dp)).background(DS.fill)
                    .clickable(onClick = onRegisterAttendance)
                    .padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.Add, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(16.dp))
                Text("参加ライブを登録して現地回収", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
                    modifier = Modifier.padding(start = 6.dp))
            }
            if (state.collectedShows.isNotEmpty()) {
                Column(Modifier.padding(horizontal = 16.dp)) {
                    state.collectedShows.forEachIndexed { idx, show ->
                        if (idx > 0) HorizontalDivider(color = DS.sep)
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable { onShowClick(show.showId) }
                                .padding(vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = DS.success, modifier = Modifier.size(16.dp))
                            Column(Modifier.weight(1f).padding(start = 10.dp)) {
                                Text(eventDisplayName(show.eventName), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(listOf(show.showName, show.date).filter { it.isNotEmpty() }.joinToString(" ・ "),
                                    fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
            }
        }
        // 楽曲情報
        Column {
            ImasSectionHeader("楽曲情報", tight = true)
            InfoRow("アーティスト", artistLine)
            InfoRow("ブランド", state.brand?.shortName)
            if (song.songType.isNotEmpty() && song.songType != "unknown") {
                InfoRow("タイプ", songTypeLabel(song.songType))
            }
            InfoRow("リリース日", song.releaseDate)
            InfoRow("再生時間", formatDuration(song.durationSec))
            InfoRow("作曲", song.composer)
            InfoRow("作詞", song.lyricist)
            InfoRow("編曲", song.arranger)
            InfoRow("CDシリーズ", song.cdSeries)
            InfoRow("収録", song.cdTitle)
            if (state.unit != null) {
                ImasLabeledRow(key = "ユニット", value = state.unit.name, tappable = true, seed = seed, brand = song.brandId,
                    onClick = { onUnitClick(state.unit.id) })
                HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
            }
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

@Composable
private fun InfoRow(key: String, value: String?) {
    if (value.isNullOrEmpty()) return
    ImasLabeledRow(key = key, value = value)
    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
}

@Composable
private fun RelatedSongsSection(
    title: String,
    songs: List<Song>,
    seed: String?,
    brand: String?,
    badge: Map<String, Int>?,
    onSongClick: (String) -> Unit
) {
    Column {
        ImasSectionHeader(title, count = "${songs.size}")
        Column(Modifier.padding(horizontal = 16.dp)) {
            songs.forEachIndexed { idx, s ->
                if (idx > 0) HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 44.dp))
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onSongClick(s.id) }.padding(vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ImasArtwork(title = s.title, seed = seed, brand = brand, size = 44.dp, imageUrl = s.artworkUrl)
                    Column(Modifier.weight(1f).padding(start = 12.dp)) {
                        Text(s.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val sub = s.singerLabel ?: s.unitName
                        if (!sub.isNullOrEmpty()) {
                            Text(sub, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    val b = badge?.get(s.id)
                    if (b != null) {
                        Text("タグ${b}個一致", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3,
                            modifier = Modifier.padding(end = 4.dp))
                    }
                }
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
    onCreateCall: () -> Unit,
    onEditCall: (SongCall) -> Unit,
    onOpenPenlightVote: () -> Unit,
    onPollClick: (String) -> Unit
) {
    val context = LocalContext.current
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる。
    // extension property は毎回 EditPermissionRules を RustBuffer に詰めて JNA を跨ぐので、
    // コーレス 1 件ごと・再コンポーズごとに呼ぶと (要素数ぶんの FFI) スクロール中ずっと積み上がる。
    val canEditHere = remember(authState) { authState.showEditAffordance }
    val needsLogin = remember(authState) { authState.shouldPromptLogin }
    Column(modifier = Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        state.song?.let { song ->
            com.fugaif.imaslivedb.ui.polls.PollAchievementBadges(entityId = song.id, onOpenPoll = onPollClick)
        }
        if (needsLogin) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                    .clip(RoundedCornerShape(12.dp)).background(DS.fill).padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("タグ・コーレス・投票にはログインが必要です", fontSize = 12.5.sp, color = DS.ink2)
            }
        }
        // タグ (集計系コミュニティ・Worker D1)。タップで自分の投票をトグル、長押しでタグ詳細、+ で全タグから追加。
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ImasSectionHeader("タグ", count = "${state.tags.size}", modifier = Modifier.weight(1f))
                if (canEditHere) {
                    IconButton(onClick = onOpenTagPicker, modifier = Modifier.padding(end = 8.dp)) {
                        Icon(Icons.Filled.Add, contentDescription = "タグを追加", tint = DS.ink2)
                    }
                }
            }
            if (state.tags.isEmpty()) {
                Text("タグはまだありません", fontSize = 13.sp, color = DS.ink3,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp))
            } else {
                FlowRow(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    state.tags.forEach { tag ->
                        val bg = if (tag.mine) DS.pick.copy(alpha = 0.18f) else DS.fill
                        val fg = if (tag.mine) DS.pick else DS.ink
                        Row(
                            modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(bg)
                                .combinedClickable(
                                    onClick = { onToggleTag(tag) },
                                    onLongClick = { onTagDetailClick(tag.id) }
                                )
                                .padding(horizontal = 12.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(tag.name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = fg)
                            if (tag.voteCount > 0) {
                                Text(" ${tag.voteCount}", fontSize = 12.sp, color = DS.ink3)
                            }
                        }
                    }
                }
            }
        }
        // この曲が好きな人にはこれも (タグが似ている楽曲, サーバ算出)
        if (state.similarTagSongs.isNotEmpty()) {
            RelatedSongsSection("この曲が好きな人にはこれも", state.similarTagSongs, seed, brand, state.similarSharedTags, onSongClick)
        }
        // ペンライト投票 (集計系・Worker D1)
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ImasSectionHeader("ペンライト", count = state.penlight?.totalVotes?.let { "${it}票" }, modifier = Modifier.weight(1f))
                if (canEditHere) {
                    IconButton(onClick = onOpenPenlightVote, modifier = Modifier.padding(end = 8.dp)) {
                        Icon(Icons.Filled.Add, contentDescription = "投票する", tint = DS.ink2)
                    }
                }
            }
            val sets = state.penlight?.topSets ?: emptyList()
            if (sets.isEmpty()) {
                ImasEmptyState(Icons.Filled.Star, "まだ投票がありません",
                    "あなたが思うこの曲のペンライト色を投票しませんか？", seed = seed, brand = brand)
            } else {
                sets.take(5).forEach { ps ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        ps.colors.take(4).forEach { hex ->
                            Box(Modifier.size(20.dp).clip(RoundedCornerShape(5.dp))
                                .background(hexToColor(hex)))
                        }
                        Box(Modifier.weight(1f))
                        Text("${ps.count}", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
                    }
                }
            }
        }
        // コーレス (構造化コミュニティ・CloudKit 直書き。POST /edits 経由で全ユーザーが投稿/編集可能)
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ImasSectionHeader("コーレス", count = "${state.songCalls.size}", modifier = Modifier.weight(1f))
                if (canEditHere) {
                    IconButton(onClick = onCreateCall, modifier = Modifier.padding(end = 8.dp)) {
                        Icon(Icons.Filled.Add, contentDescription = "コーレスを投稿", tint = DS.ink2)
                    }
                }
            }
            if (state.songCalls.isEmpty()) {
                ImasEmptyState(Icons.Filled.Campaign, "コーレスはまだありません",
                    "サビ前のコールなど、現地の盛り上げ方を共有しませんか？", seed = seed, brand = brand)
            } else {
                state.songCalls.forEach { call ->
                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                        // コーレスは長文で「サビ前のここだけ引用したい」需要があるので、
                        // 全文一括ではなく標準の選択メニューで部分コピーできるようにする。
                        SelectionContainer {
                            Text(call.callText, fontSize = 15.sp, color = DS.ink)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 4.dp)) {
                            if (!call.sourceUrl.isNullOrEmpty()) {
                                Text(
                                    "出典", fontSize = 12.sp, color = DS.ink2,
                                    modifier = Modifier.clickable { openUrl(context, call.sourceUrl) }
                                )
                            }
                            if (!call.authorDisplayName.isNullOrEmpty()) {
                                Text("投稿者: ${call.authorDisplayName}", fontSize = 12.sp, color = DS.ink3)
                            }
                            Box(Modifier.weight(1f))
                            if (canEditHere) {
                                IconButton(onClick = { onEditCall(call) }, modifier = Modifier.size(28.dp)) {
                                    Icon(Icons.Filled.Edit, contentDescription = "コーレスを編集", tint = DS.ink2, modifier = Modifier.size(16.dp))
                                }
                            }
                        }
                    }
                    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                }
            }
        }
        // 参考動画 (構造化コミュニティ・CloudKit)
        Column {
            ImasSectionHeader("参考動画", count = "${state.songVideos.size}")
            if (state.songVideos.isEmpty()) {
                ImasEmptyState(Icons.Filled.OndemandVideo, "参考動画はまだありません",
                    "ライブ映像などの参考動画が登録されると、ここに表示されます。", seed = seed, brand = brand)
            } else {
                state.songVideos.forEach { video ->
                    val videoId = youTubeVideoId(video.youtubeUrl)
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable {
                            openUrl(context, video.youtubeUrl)
                        }.padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(Modifier.size(56.dp).clip(RoundedCornerShape(9.dp)).background(DS.fill), contentAlignment = Alignment.Center) {
                            if (videoId != null) {
                                SubcomposeAsyncImage(
                                    model = "https://i.ytimg.com/vi/$videoId/mqdefault.jpg",
                                    contentDescription = video.videoTitle,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.size(56.dp).clip(RoundedCornerShape(9.dp))
                                )
                            }
                            Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(22.dp))
                        }
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            Text(video.videoTitle ?: video.youtubeUrl, fontSize = 15.sp, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (!video.note.isNullOrEmpty()) {
                                Text(video.note, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            if (!video.authorDisplayName.isNullOrEmpty()) {
                                Text("投稿者: ${video.authorDisplayName}", fontSize = 11.sp, color = DS.ink3)
                            }
                        }
                    }
                    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                }
            }
        }
    }
}

/** YouTube URL から videoId (11文字) を抽出。iOS YouTube.videoID の簡易移植。 */
private fun youTubeVideoId(urlString: String): String? {
    val uri = runCatching { android.net.Uri.parse(urlString) }.getOrNull() ?: return null
    val host = uri.host?.lowercase() ?: return null
    val candidate = when {
        host.contains("youtu.be") -> uri.pathSegments.firstOrNull()
        host.contains("youtube.com") -> uri.getQueryParameter("v")
            ?: uri.pathSegments.let { segs ->
                val idx = segs.indexOfFirst { it in listOf("embed", "shorts", "live") }
                if (idx >= 0 && idx + 1 < segs.size) segs[idx + 1] else null
            }
        else -> null
    } ?: return null
    val id = candidate.takeWhile { it.isLetterOrDigit() || it == '_' || it == '-' }
    return id.takeIf { it.length == 11 }
}

@Composable
private fun HistoryTab(history: List<PerformanceHistoryRow>, seed: String?, brand: String?, onShowClick: (String) -> Unit) {
    if (history.isEmpty()) {
        ImasEmptyState(Icons.Filled.MusicNote, "披露履歴はまだありません",
            "この曲がライブで披露されると、ここに記録されます。", seed = seed, brand = brand)
        return
    }
    Column(modifier = Modifier.padding(top = 8.dp)) {
        val sortedByDateAsc = history.sortedBy { it.date }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ImasStatTile(Icons.Filled.Mic, "${history.size}", "総披露", unit = "回", seed = seed, brand = brand, modifier = Modifier.weight(1f))
            ImasStatTile(Icons.Filled.CalendarMonth, shortYearMonth(date = sortedByDateAsc.first().date), "初披露", seed = seed, brand = brand, modifier = Modifier.weight(1f))
            ImasStatTile(Icons.Filled.CalendarMonth, shortYearMonth(date = sortedByDateAsc.last().date), "最終披露", seed = seed, brand = brand, modifier = Modifier.weight(1f))
        }
        ImasSectionHeader("ライブ披露履歴", count = "${history.size}回", tight = true)
        history.forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth().clickable { onShowClick(row.showId) }
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                ImasLeadBar(seedHex = seed, brandId = brand, height = 34.dp)
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(eventDisplayName(row.eventName), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(listOf(row.showName, row.date).filter { it.isNotEmpty() }.joinToString(" ・ "),
                        fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
    }
}
