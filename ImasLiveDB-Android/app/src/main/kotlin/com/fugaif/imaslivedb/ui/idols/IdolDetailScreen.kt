package com.fugaif.imaslivedb.ui.idols

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
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
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.image.CustomImageStore
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolPerformedSong
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.IdolGridSection
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLabeledRow
import com.fugaif.imaslivedb.ui.components.PersonalTagsSection
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.components.MarkToggleAction
import com.fugaif.imaslivedb.ui.tags.IdolTagPickerSheet
import com.fugaif.imaslivedb.ui.theme.BrandPalette
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.launch
import uniffi.imas_core.IdolProfileInput
import uniffi.imas_core.RowAction
import uniffi.imas_core.RowStyle
import uniffi.imas_core.idolProfileRows
import java.io.File

/**
 * アイドル詳細。iOS IdolDetailView の構成を 1:1 で写す。
 * hero(アバター + 名前 + ブランド + 担当/お気に入り) を上部に、その下を ImasSegmented で
 * [ライブ][楽曲・ユニット][プロフィール] に切り替える。
 *
 * iOS にあって Android にまだ無いもの (対応基盤が無いため未実装):
 * - CV (声優) 表示 — idols テーブルに voice_actors 列が無く、CloudKit マッパー側の追加が必要
 * - メモ (UserMarkBar note) — テキスト入力 UI が Android に無い
 * - ホーム画面ウィジェット — 画像基盤 (CustomImageStore) は入ったが、ウィジェット本体は未実装
 * - 編集導線・編集履歴 — Android に編集フロー自体が無い
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
    viewModel: IdolDetailViewModel = viewModel(
        factory = IdolDetailViewModel.Factory(
            LocalContext.current.applicationContext as android.app.Application, idolId
        )
    )
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsState()
    val idol = state.idol
    val t = ImasTheme.derive(idol?.color, BrandPalette.hex(idol?.brandId), dark = true)
    var segment by rememberSaveable(idolId) { mutableIntStateOf(0) }
    var showTagPicker by rememberSaveable { mutableStateOf(false) }
    var showLoginPrompt by rememberSaveable { mutableStateOf(false) }
    val authState by AppModule.from(context).authService.state.collectAsState()

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
                }
            )
        }
    ) { padding ->
        if (state.isLoading || idol == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
                Hero(idol, state.brand?.shortName, t)
                ImasSegmented(
                    labels = listOf("ライブ", "楽曲・ユニット", "プロフィール", "コミュニティ"),
                    selection = segment, onSelect = { segment = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
                )
                when (segment) {
                    0 -> LiveBody(state, idol, onNavigateToSongDetail, onNavigateToShowDetail)
                    1 -> SongsBody(state, idol, onNavigateToUnitDetail, onNavigateToSongDetail)
                    2 -> ProfileBody(idol, onNavigateToBirthMonth)
                    else -> Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        CommunityBody(
                            idolId = idol.id,
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
    val needsLogin = remember(authState) { authState.shouldPromptLogin }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        com.fugaif.imaslivedb.ui.polls.PollAchievementBadges(entityId = idolId, onOpenPoll = onPollClick)
        if (needsLogin) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                    .clip(RoundedCornerShape(12.dp)).background(DS.fill).padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("タグ付け・投票にはログインが必要です", fontSize = 12.5.sp, color = DS.ink2)
            }
        }
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ImasSectionHeader("タグ", count = "${tags.size}", modifier = Modifier.weight(1f))
                if (canEditHere) {
                    IconButton(onClick = onOpenTagPicker, modifier = Modifier.padding(end = 8.dp)) {
                        Icon(Icons.Filled.Add, contentDescription = "タグを追加", tint = DS.ink2)
                    }
                }
            }
            if (tags.isEmpty()) {
                Text("タグはまだありません", fontSize = 13.sp, color = DS.ink3,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp))
            } else {
                FlowRow(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    tags.forEach { tag ->
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
        // タグが似ているアイドル (この人が好きな人にはこの人も, サーバ算出)
        if (similarTagIdols.isNotEmpty()) {
            IdolGridSection("タグが似ているアイドル", similarTagIdols, onIdolClick, badge = similarSharedTags)
        }
    }
}

@Composable
private fun Hero(idol: Idol, brandShortName: String?, t: ImasTheme) {
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
    Column(
        modifier = Modifier.fillMaxWidth().background(t.heroSurface).padding(top = 16.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(contentAlignment = Alignment.BottomEnd) {
            Box(Modifier.clickable(onClick = pickAvatar)) {
                ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 72.dp,
                    isPick = pick, entityId = idol.id)
            }
            // 「押せる」ことが分かるカメラバッジ (iOS の PhotosPicker バッジと対)。
            Box(
                modifier = Modifier.size(26.dp).clip(CircleShape).background(t.accent)
                    .clickable(onClick = pickAvatar),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Filled.PhotoCamera, contentDescription = "アイコン写真を変更",
                    tint = t.onAccent, modifier = Modifier.size(14.dp))
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(idol.name, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            if (!brandShortName.isNullOrEmpty()) {
                Text(brandShortName, fontSize = 13.sp, color = DS.ink2)
            }
            voiceActorLabel(idol.voiceActors)?.let { cv ->
                Text(cv, fontSize = 12.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            HeroToggle("担当", pick, DS.pick, t) {
                scope.launch { pick = marks.toggle(UserMark.IDOL, idol.id, UserMark.PICK) }
            }
            HeroToggle("お気に入り", fav, DS.favorite, t) {
                scope.launch { fav = marks.toggle(UserMark.IDOL, idol.id, UserMark.FAVORITE) }
            }
        }
    }
}

@Composable
private fun HeroToggle(label: String, on: Boolean, activeColor: Color, t: ImasTheme, onClick: () -> Unit) {
    Row(
        modifier = Modifier.clip(RoundedCornerShape(999.dp))
            .then(if (on) Modifier.background(activeColor) else Modifier.border(1.dp, DS.sep, RoundedCornerShape(999.dp)))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (on) Color.White else DS.ink2)
    }
}

@Composable
private fun LiveBody(state: IdolDetailUiState, idol: Idol, onSong: (String) -> Unit, onShow: (String) -> Unit) {
    if (state.performedSongs.isEmpty() && state.castShows.isEmpty()) {
        ImasEmptyState(Icons.Filled.MusicNote, "ライブ記録はまだありません",
            "このアイドルのライブ出演・歌唱記録はまだ登録されていません。", seed = idol.color, brand = idol.brandId)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        state.nextShow?.let { next ->
            UpcomingCard(next, idol, onClick = onShow, modifier = Modifier.padding(horizontal = 16.dp))
        }
        if (state.performedSongs.isNotEmpty()) {
            Column {
                ImasSectionHeader("ライブ歌唱曲", count = "${state.performedSongs.size}", tight = true)
                state.performedSongs.forEach { item ->
                    SongRow(item.song, idol.color, performCount = item.performCount) { onSong(item.song.id) }
                }
            }
        }
        if (state.castShows.isNotEmpty()) {
            Column {
                ImasSectionHeader("出演履歴", count = "${state.castShows.size}", tight = true)
                state.castShows.forEach { ShowRow(it, idol) { onShow(it.showId) } }
            }
        }
    }
}

/** 次の出演カード。今日以降で最も近い公演 (state.nextShow) をタップで公演詳細へ。 */
@Composable
private fun UpcomingCard(row: CastShowRow, idol: Idol, onClick: (String) -> Unit, modifier: Modifier = Modifier) {
    val t = ImasTheme.derive(idol.color, BrandPalette.hex(idol.brandId), dark = true)
    Row(
        modifier = modifier.fillMaxWidth().height(IntrinsicSize.Min)
            .clip(RoundedCornerShape(14.dp))
            .background(t.heroSurface)
            .clickable { onClick(row.showId) }
    ) {
        Box(Modifier.width(4.dp).fillMaxHeight().background(t.accent))
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("次の出演 ・ ${monthDay(row.date)}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = t.accent)
            Text(row.eventName, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(Icons.Filled.LocationOn, null, tint = DS.ink2, modifier = Modifier.size(12.dp))
                Text(
                    listOfNotNull(row.venue, row.showName).filter { it.isNotEmpty() }.joinToString(" ・ "),
                    fontSize = 13.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SongsBody(state: IdolDetailUiState, idol: Idol, onUnit: (String) -> Unit, onSong: (String) -> Unit) {
    if (state.unitsWithSongs.isEmpty() && state.unitsWithoutSongs.isEmpty() && state.originalSongs.isEmpty()) {
        ImasEmptyState(Icons.Filled.MusicNote, "楽曲・ユニットがありません",
            "原曲・所属ユニットの情報はまだ登録されていません。", seed = idol.color, brand = idol.brandId)
        return
    }
    var showEmptyUnits by rememberSaveable(idol.id) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (state.unitsWithSongs.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ImasSectionHeader("所属ユニット", count = "${state.unitsWithSongs.size}", tight = true)
                FlowRow(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    state.unitsWithSongs.forEach { unit -> UnitChip(unit, idol) { onUnit(unit.id) } }
                }
            }
        }
        if (state.unitsWithoutSongs.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(horizontal = 16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { showEmptyUnits = !showEmptyUnits },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text("曲なしユニット", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
                    Text("${state.unitsWithoutSongs.size}", fontSize = 12.sp, color = DS.ink3)
                    Box(Modifier.weight(1f))
                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink3,
                        modifier = Modifier.size(14.dp)
                    )
                }
                if (showEmptyUnits) {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        state.unitsWithoutSongs.forEach { unit -> UnitChip(unit, idol) { onUnit(unit.id) } }
                    }
                }
            }
        }
        if (state.originalSongs.isNotEmpty()) {
            Column {
                ImasSectionHeader("楽曲（原曲）", count = "${state.originalSongs.size}", tight = true)
                state.originalSongs.forEach { song -> SongRow(song, idol.color) { onSong(song.id) } }
            }
        }
    }
}

@Composable
private fun UnitChip(unit: ImasUnit, idol: Idol, onClick: () -> Unit) {
    val t = ImasTheme.derive(idol.color, BrandPalette.hex(idol.brandId), dark = true)
    Text(
        unit.displayName,
        fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = t.chipText,
        modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(t.chipBg)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp)
    )
}

@Composable
private fun ProfileBody(idol: Idol, onNavigateToBirthMonth: (Int) -> Unit) {
    val clipboard = LocalClipboardManager.current
    // 行の組み立て (どの行が・どの順で・押せるか) は共有コアが唯一の正。
    // iOS と同じ条件を二重に書くと必ずいつかズレるので、ここは整形済みの値を渡すだけにする。
    // 1 画面 = 1 呼び出し。idol が変わらない限り作り直さない。
    val rows = remember(idol) {
        idolProfileRows(
            IdolProfileInput(
                nameKana = idol.nameKana,
                nameRomaji = idol.nameRomaji,
                birthdayDisplay = idol.birthday?.let { formatBirthday(it) },
                birthMonth = birthMonth(idol.birthday),
                ageHeightWeight = ageHeightWeight(idol),
                threeSize = threeSize(idol),
                bloodConstellation = bloodConstellation(idol),
                birthplaceHandedness = birthplaceHand(idol),
                hobbyTalent = hobbyTalent(idol),
                color = idol.color
            )
        )
    }
    Column {
        ImasSectionHeader("プロフィール", tight = true)
        rows.forEach { row ->
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
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
        idol.description?.takeIf { it.isNotEmpty() }?.let { desc ->
            Text(desc, fontSize = 14.sp, color = DS.ink2, modifier = Modifier.padding(16.dp))
        }
        // iOS も profileBody の末尾にギャラリーを置いている (プロフィールの一部という位置づけ)。
        GallerySection(idol.id)
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
        Row(verticalAlignment = Alignment.CenterVertically) {
            ImasSectionHeader("ギャラリー", count = "${files.size}", tight = true, modifier = Modifier.weight(1f))
            TextButton(onClick = addImages) {
                Icon(Icons.Filled.Add, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(16.dp))
                Text("追加", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DS.ink2,
                    modifier = Modifier.padding(start = 4.dp))
            }
        }
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

@Composable
private fun SongRow(song: Song, seed: String?, performCount: Int? = null, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasArtwork(title = song.title, seed = seed, brand = song.brandId, size = 44.dp, imageUrl = song.artworkUrl)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(song.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val sub = song.singerLabel ?: song.unitName
            if (!sub.isNullOrEmpty()) Text(sub, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (performCount != null) {
                Text("${performCount}回", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
            }
        }
        MarkToggleAction(
            entityType = UserMark.SONG, entityId = song.id, kind = UserMark.FAVORITE,
            activeIcon = Icons.Filled.Star, inactiveIcon = Icons.Filled.StarBorder,
            activeTint = DS.favorite, contentDescription = "お気に入り"
        )
    }
}

@Composable
private fun ShowRow(row: CastShowRow, idol: Idol, onClick: () -> Unit) {
    val t = ImasTheme.derive(idol.color, BrandPalette.hex(idol.brandId), dark = true)
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(row.eventName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (row.isLead) {
                    RoleTag("主演", t)
                } else if (row.isGuest) {
                    RoleTag("ゲスト", t)
                }
            }
            Text(listOf(row.date, row.venue, row.showName).mapNotNull { it?.takeIf { s -> s.isNotEmpty() } }.joinToString(" ・ "),
                fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun RoleTag(text: String, t: ImasTheme) {
    Text(
        text, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = t.chipText,
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(t.chipBg).padding(horizontal = 6.dp, vertical = 2.dp)
    )
}

/** "CV 声優A / 声優B" 形式のラベル (voice_actors はカンマ区切りで先頭が現役)。iOS voiceActorList の移植。 */
private fun voiceActorLabel(voiceActors: String?): String? {
    val names = voiceActors?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
    return names.takeIf { it.isNotEmpty() }?.joinToString(" / ")?.let { "CV $it" }
}

private fun formatBirthday(b: String): String =
    b.removePrefix("--").split("-").let { if (it.size == 2) "${it[0]}月${it[1]}日" else b }

/**
 * "--MM-DD" から誕生月を取り出す (iOS `Idol.birthMonth` と同じ判定)。
 *
 * "--" で始まらない値は年入りの日付なので月を名乗らせない。範囲外の月はコア側で弾かれる。
 */
private fun birthMonth(birthday: String?): UInt? {
    if (birthday == null || !birthday.startsWith("--")) return null
    return birthday.removePrefix("--").split("-").firstOrNull()?.toUIntOrNull()
}

/** "2026-06-21" → "6/21" */
private fun monthDay(date: String): String {
    val parts = date.split("-")
    if (parts.size != 3) return date
    val m = parts[1].toIntOrNull() ?: return date
    val d = parts[2].toIntOrNull() ?: return date
    return "$m/$d"
}

private fun ageHeightWeight(i: Idol): String? {
    val parts = buildList {
        i.age?.let { add("${it}歳") }
        i.height?.let { add("${it.toInt()}cm") }
        i.weight?.let { add("${it.toInt()}kg") }
    }
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" / ")
}

private fun threeSize(i: Idol): String? {
    val b = i.bust; val w = i.waist; val h = i.hip
    return if (b != null && w != null && h != null) "B${b.toInt()} / W${w.toInt()} / H${h.toInt()}" else null
}

private fun bloodConstellation(i: Idol): String? {
    val parts = buildList {
        i.bloodType?.let { add("${it}型") }
        i.constellation?.let { add(it) }
    }
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" ・ ")
}

private fun birthplaceHand(i: Idol): String? {
    val parts = buildList {
        i.birthPlace?.let { add(it) }
        i.handedness?.let { add(if (it == "right") "右" else if (it == "left") "左" else it) }
    }
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" ・ ")
}

private fun hobbyTalent(i: Idol): String? {
    val parts = buildList {
        i.hobbies?.let { add(it) }
        i.talents?.let { add(it) }
    }
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" ・ ")
}
