package com.fugaif.imaslivedb.ui.idols

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.MusicNote
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLabeledRow
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.launch

/**
 * アイドル詳細。iOS IdolDetailView の構成を 1:1 で写す。
 * hero(アバター + 名前 + 担当/お気に入り) を上部に、その下を ImasSegmented で
 * [ライブ][楽曲・ユニット][プロフィール] に切り替える。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolDetailScreen(
    idolId: String,
    onNavigateBack: () -> Unit,
    onNavigateToUnitDetail: (String) -> Unit,
    onNavigateToSongDetail: (String) -> Unit,
    onNavigateToShowDetail: (String) -> Unit,
    viewModel: IdolDetailViewModel = viewModel(
        factory = IdolDetailViewModel.Factory(
            LocalContext.current.applicationContext as android.app.Application, idolId
        )
    )
) {
    val state by viewModel.uiState.collectAsState()
    val idol = state.idol
    val t = ImasTheme.derive(idol?.color, idol?.brandId, dark = true)
    var segment by rememberSaveable(idolId) { mutableIntStateOf(0) }

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
                Hero(idol, t)
                ImasSegmented(
                    labels = listOf("ライブ", "楽曲・ユニット", "プロフィール"),
                    selection = segment, onSelect = { segment = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
                )
                when (segment) {
                    0 -> LiveBody(state, idol, onNavigateToSongDetail, onNavigateToShowDetail)
                    1 -> SongsBody(state, idol, onNavigateToUnitDetail, onNavigateToSongDetail)
                    else -> ProfileBody(idol)
                }
                Box(Modifier.size(24.dp))
            }
        }
    }
}

@Composable
private fun Hero(idol: Idol, t: ImasTheme) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val marks = AppModule.from(context).userMarkRepository
    var pick by remember(idol.id) { mutableStateOf(false) }
    var fav by remember(idol.id) { mutableStateOf(false) }
    LaunchedEffect(idol.id) {
        pick = marks.isOn(UserMark.IDOL, idol.id, UserMark.PICK)
        fav = marks.isOn(UserMark.IDOL, idol.id, UserMark.FAVORITE)
    }
    Column(
        modifier = Modifier.fillMaxWidth().background(t.heroSurface).padding(top = 16.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 72.dp, isPick = pick)
        Text(idol.name, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink)
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
        if (state.performedSongs.isNotEmpty()) {
            Column {
                ImasSectionHeader("ライブ歌唱曲", count = "${state.performedSongs.size}", tight = true)
                state.performedSongs.forEach { SongRow(it, idol.color) { onSong(it.id) } }
            }
        }
        if (state.castShows.isNotEmpty()) {
            Column {
                ImasSectionHeader("出演履歴", count = "${state.castShows.size}", tight = true)
                state.castShows.forEach { ShowRow(it) { onShow(it.showId) } }
            }
        }
    }
}

@Composable
private fun SongsBody(state: IdolDetailUiState, idol: Idol, onUnit: (String) -> Unit, onSong: (String) -> Unit) {
    if (state.units.isEmpty() && state.originalSongs.isEmpty()) {
        ImasEmptyState(Icons.Filled.MusicNote, "楽曲・ユニットがありません",
            "原曲・所属ユニットの情報はまだ登録されていません。", seed = idol.color, brand = idol.brandId)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (state.units.isNotEmpty()) {
            Column {
                ImasSectionHeader("所属ユニット", count = "${state.units.size}", tight = true)
                state.units.forEach { unit ->
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable { onUnit(unit.id) }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(unit.displayName, fontSize = 15.sp, color = DS.ink, modifier = Modifier.weight(1f))
                    }
                    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                }
            }
        }
        if (state.originalSongs.isNotEmpty()) {
            Column {
                ImasSectionHeader("楽曲（原曲）", count = "${state.originalSongs.size}", tight = true)
                state.originalSongs.forEach { SongRow(it, idol.color) { onSong(it.id) } }
            }
        }
    }
}

@Composable
private fun ProfileBody(idol: Idol) {
    val rows = buildList {
        idol.birthday?.let { add("誕生日" to formatBirthday(it)) }
        idol.bloodType?.let { add("血液型" to it) }
        ageHeightWeight(idol)?.let { add("年齢 / 身長 / 体重" to it) }
        threeSize(idol)?.let { add("スリーサイズ" to it) }
        idol.birthPlace?.let { add("出身地" to it) }
        idol.constellation?.let { add("星座" to it) }
        idol.handedness?.let { add("利き手" to it) }
        idol.hobbies?.let { add("趣味" to it) }
        idol.talents?.let { add("特技" to it) }
        idol.nameRomaji?.let { add("ローマ字" to it) }
    }
    Column {
        ImasSectionHeader("プロフィール", tight = true)
        rows.forEach { (k, v) ->
            ImasLabeledRow(key = k, value = v)
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
        idol.description?.takeIf { it.isNotEmpty() }?.let { desc ->
            Text(desc, fontSize = 14.sp, color = DS.ink2, modifier = Modifier.padding(16.dp))
        }
    }
}

@Composable
private fun SongRow(song: Song, seed: String?, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasArtwork(title = song.title, seed = seed, brand = song.brandId, size = 44.dp, imageUrl = song.artworkUrl)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(song.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val sub = song.singerLabel ?: song.unitName
            if (!sub.isNullOrEmpty()) Text(sub, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun ShowRow(row: CastShowRow, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(row.eventName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(listOf(row.showName, row.date).filter { it.isNotEmpty() }.joinToString(" ・ "),
                fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

private fun formatBirthday(b: String): String =
    b.removePrefix("--").split("-").let { if (it.size == 2) "${it[0]}月${it[1]}日" else b }

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
