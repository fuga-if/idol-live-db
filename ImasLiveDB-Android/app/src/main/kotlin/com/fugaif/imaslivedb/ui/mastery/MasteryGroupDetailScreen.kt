package com.fugaif.imaslivedb.ui.mastery

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.ui.components.*
import com.fugaif.imaslivedb.ui.designsystem.*
import com.fugaif.imaslivedb.ui.theme.*
import uniffi.imas_core.MasteryBulkScope
import uniffi.imas_core.MasteryGroup
import uniffi.imas_core.nextMasteryLevel

/**
 * 群の中の曲一覧。**段階を変えるのはここ**。iOS `MasteryGroupDetailView` の移植。
 *
 * ⚠️ 曲一覧は [LazyColumn]。最大の群は 650 曲 (ユニット軸の「その他」) あり、
 * 非遅延だとジャケ写つきの行を全部一度に組んで開いた瞬間に固まる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MasteryGroupDetailScreen(
    group: MasteryGroup,
    scale: MasteryScale,
    songs: List<Song>,
    collectedIds: Set<String>,
    onBack: () -> Unit,
    onOpenSong: (String) -> Unit,
    onSetLevel: (String, UByte) -> Unit,
    onBulk: (MasteryBulkScope, UByte) -> Unit,
) {
    var levelFilter by remember { mutableStateOf<UByte?>(null) }
    var heardOnly by remember { mutableStateOf(false) }
    var showBulk by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Song?>(null) }

    // 段・「聴いたのに未設定」・数はコアが群に入れて返す (group.songIds と同じ並び)。
    // 画面で marks から数え直さない。
    val indexById = remember(group) { group.songIds.withIndex().associate { it.value to it.index } }
    val levelOf: (Song) -> UByte = { song -> indexById[song.id]?.let { group.levels[it].toUByte() } ?: 0u }
    val heardButUnset: (Song) -> Boolean = { song -> indexById[song.id]?.let { group.heardButUnset[it] } == true }
    val shown = songs.filter { song ->
        when {
            heardOnly -> heardButUnset(song)
            levelFilter != null -> levelOf(song) == levelFilter
            else -> true
        }
    }
    val heardUnset = group.heardButUnsetCount.toInt()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { ImasText(group.label, ImasTextRole.ROW_TITLE, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                },
                actions = {
                    ImasToolbarButton(Icons.Filled.MoreHoriz, "まとめて変える", onClick = { showBulk = true })
                }
            )
        }
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding)) {
            item {
                Column {
                    ImasSectionHeader("このグループの習熟度", tight = true)
                    ImasCard(modifier = Modifier.padding(horizontal = DS.sp5)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(DS.sp5),
                        ) {
                            ImasProgressRing(group.percent.toInt() / 100.0)
                            Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
                                ImasMetric("${group.setCount}", unit = "/ ${group.total}曲", size = ImasNumeralSize.LARGE, emphasized = true)
                                ImasText("段階を付けた曲", ImasTextRole.NOTE)
                                ImasText("${scale.label(scale.steps)} ${group.doneCount} 曲", ImasTextRole.EYEBROW, color = DS.ink3)
                            }
                        }
                    }
                    Spacer(Modifier.height(DS.sp4))

                    ImasChipRow {
                        if (heardUnset > 0) {
                            ImasFilterChip("聴いたのに未設定 $heardUnset", heardOnly, {
                                heardOnly = !heardOnly
                                if (heardOnly) levelFilter = null
                            }, icon = Icons.Filled.Check)
                        }
                        for (i in 0..scale.steps.toInt()) {
                            val level = i.toUByte()
                            val count = group.levelCounts.getOrElse(i) { 0u }
                            ImasFilterChip("${scale.shortLabel(level)} $count",
                                           levelFilter == level, {
                                levelFilter = if (levelFilter == level) null else level
                                if (levelFilter != null) heardOnly = false
                            })
                        }
                    }
                    Spacer(Modifier.height(DS.sp4))
                    ImasSectionHeader("収録曲",
                        count = if (levelFilter == null && !heardOnly) "${songs.size}曲"
                                else "${shown.size} / ${songs.size}曲",
                        tight = true)
                }
            }

            items(shown.size) { index ->
                val song = shown[index]
                val level = levelOf(song)
                val next = nextMasteryLevel(level, scale.steps)
                // 左スワイプは割り当てない。**端から引くと OS の「戻る」に取られる**ので
                // (エミュで実測。画面ごと閉じてしまう)、逆向きは信用できない。
                // 未設定に戻すのは長押しのピッカーが受け持つ。
                MasterySwipeRow(
                    onStart = { onSetLevel(song.id, next) },
                    startLabel = scale.label(next),
                    startColor = MasteryPalette.fill(next, scale.steps),
                ) {
                    SongMasteryRow(song, level, scale, song.id in collectedIds,
                                   onClick = { onOpenSong(song.id) },
                                   onLongClick = { editing = song },
                                   onCycle = { onSetLevel(song.id, next) })
                }
                if (index < shown.size - 1) {
                    HorizontalDivider(Modifier.padding(start = 70.dp), color = DS.sep)
                }
            }
            item { Spacer(Modifier.height(DS.sp7)) }
        }
    }

    editing?.let { song ->
        MasteryLevelPickerSheet(song.title, levelOf(song), scale,
                         onPick = { onSetLevel(song.id, it); editing = null },
                         onDismiss = { editing = null })
    }

    if (showBulk) {
        BulkSheet(group, scale, onPick = { scope, level -> onBulk(scope, level); showBulk = false },
                  onDismiss = { showBulk = false })
    }
}

/**
 * 曲 1 行。的を 2 つに分ける: 行は曲の詳細へ、**末尾の段階チップは押すたびに 1 段上がる**。
 *
 * ピッカーだけだと、続けて付けていく作業が 1 曲ごとに (長押し→待つ→選ぶ→閉じる) で止まる。
 * 上げるのが一番多い操作なので 1 タップに置き、下げる/特定の段へ飛ぶのは長押しに残した。
 * iOS の行スワイプに当たる手つきは Android の一覧に無いので
 * (`SwipeToDismissBox` は消す操作の合図になる)、そこは長押しが受け持つ。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SongMasteryRow(
    song: Song, level: UByte, scale: MasteryScale, collected: Boolean,
    onClick: () -> Unit, onLongClick: () -> Unit, onCycle: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().background(DS.surface)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = DS.sp5, vertical = DS.sp3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.sp4),
    ) {
        ImasArtwork(title = song.title, brand = song.brandId, size = 36.dp, imageUrl = song.artworkUrl)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            ImasText(song.title, ImasTextRole.ROW_LABEL, maxLines = 1)
            val sub = song.unitName ?: song.singerLabel
            if (!sub.isNullOrEmpty()) ImasText(sub, ImasTextRole.META, maxLines = 1)
        }
        if (collected) {
            // 現地で聴いた曲。既存の一覧と同じ ✓ の意味で揃える。
            Icon(Icons.Filled.Check, "現地で聴いた", tint = DS.success, modifier = Modifier.size(14.dp))
        }
        // チップだけを別の的にする。最上段では上がらない (連打で記録が飛ばないのはコアの規則)。
        Box(
            Modifier.combinedClickable(onClick = onCycle, onLongClick = onLongClick)
                .padding(start = DS.sp2, top = DS.sp3, bottom = DS.sp3)
        ) {
            MasteryChip(level, scale, showsUnset = true)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MasteryLevelPickerSheet(title: String, current: UByte, scale: MasteryScale,
                            onPick: (UByte) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = DS.bg) {
        Column(Modifier.padding(horizontal = DS.sp5).padding(bottom = DS.sp7)) {
            ImasText(title, ImasTextRole.CARD_TITLE, maxLines = 2)
            Spacer(Modifier.height(DS.sp4))
            for (i in 0..scale.steps.toInt()) {
                val level = i.toUByte()
                Row(
                    Modifier.fillMaxWidth().clickable { onPick(level) }.padding(vertical = DS.sp4),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(DS.sp4),
                ) {
                    Box(Modifier.size(14.dp).clip(RoundedCornerShape(DS.rTag))
                            .background(MasteryPalette.fill(level, scale.steps)))
                    ImasText(scale.label(level), ImasTextRole.VALUE, modifier = Modifier.weight(1f))
                    if (level == current) Icon(Icons.Filled.Check, null, tint = DS.ink2)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BulkSheet(group: MasteryGroup, scale: MasteryScale,
                      onPick: (MasteryBulkScope, UByte) -> Unit, onDismiss: () -> Unit) {
    val unset = group.levelCounts.firstOrNull()?.toInt() ?: 0
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = DS.bg) {
        Column(Modifier.padding(horizontal = DS.sp5).padding(bottom = DS.sp7)) {
            if (unset > 0) {
                ImasText("未設定の $unset 曲だけ", ImasTextRole.META)
                Spacer(Modifier.height(DS.sp2))
                ImasChipRow(contentPadding = 0.dp) {
                    for (i in 1..scale.steps.toInt()) {
                        ImasFilterChip(scale.label(i.toUByte()), false,
                            { onPick(MasteryBulkScope.UNSET_ONLY, i.toUByte()) })
                    }
                }
                Spacer(Modifier.height(DS.sp5))
            }
            ImasText("この ${group.total} 曲すべて", ImasTextRole.META)
            Spacer(Modifier.height(DS.sp2))
            ImasChipRow(contentPadding = 0.dp) {
                for (i in 1..scale.steps.toInt()) {
                    ImasFilterChip(scale.label(i.toUByte()), false,
                        { onPick(MasteryBulkScope.ALL, i.toUByte()) })
                }
                ImasFilterChip("未設定に戻す", false, { onPick(MasteryBulkScope.ALL, 0u) })
            }
        }
    }
}

/** 行に出す現在の段階。未設定は既定では出さない (一覧が段階の色でうるさくならないように)。 */
@Composable
fun MasteryChip(level: UByte, scale: MasteryScale, showsUnset: Boolean = false) {
    if (level.toInt() == 0 && !showsUnset) return
    val bg = MasteryPalette.fill(level, scale.steps)
    Text(
        scale.shortLabel(level),
        style = ImasType.text(10.sp, FontWeight.Bold),
        color = MasteryPalette.ink(level, scale.steps),
        modifier = Modifier.clip(RoundedCornerShape(DS.rTag)).background(bg)
            .padding(horizontal = DS.sp3, vertical = 3.dp),
    )
}
