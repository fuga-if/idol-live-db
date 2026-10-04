package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.repository.OnThisDayDigest
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolRow
import com.fugaif.imaslivedb.ui.designsystem.ImasMasthead
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeadBar
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasShowRow
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.share.SocialShareIconButton
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import java.time.LocalDate
import kotlin.math.abs

/**
 * 「今日は何の日？」— 選んだ日と同じ月日の、過去の記念日・誕生日・ライブ・リリース
 * (iOS `OnThisDaySheet` の移植)。
 *
 * 何を拾うか・何年前か・共有文 (X の文字数に収める畳み方まで) はコア (`on_this_day.rs`)。
 * ここは返ってきたものを区画に並べ、行から詳細へ進ませるだけ。
 * 左右に払うか見出しの矢印で前後の日へ送れる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnThisDaySheet(
    initialDate: LocalDate,
    onDismiss: () -> Unit,
    onNavigateToSong: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToEvent: (String) -> Unit
) {
    val repository = AppModule.from(LocalContext.current).calendarRepository
    var date by remember { mutableStateOf(initialDate) }
    var digest by remember { mutableStateOf<OnThisDayDigest?>(null) }
    LaunchedEffect(date) { digest = runCatching { repository.onThisDay(date) }.getOrNull() }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg
    ) {
        ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = onDismiss), title = "何の日")
        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(max = 640.dp)
                .verticalScroll(rememberScrollState())
                // 横に払って前後の日へ (縦のスクロールは邪魔しない)。
                .pointerInput(Unit) {
                    var total = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { total = 0f },
                        onDragEnd = { if (abs(total) > 80f) date = date.plusDays(if (total < 0) 1 else -1) },
                        onHorizontalDrag = { _, amount -> total += amount }
                    )
                }
                .padding(horizontal = DS.Space.screen)
                .padding(bottom = DS.Space.section),
            verticalArrangement = Arrangement.spacedBy(DS.Space.section)
        ) {
            Header(date, digest, onShift = { date = date.plusDays(it) })
            val current = digest ?: return@Column
            val day = current.day
            if (day.anniversaries.isEmpty() && day.birthdays.isEmpty() && day.lives.isEmpty() && day.releases.isEmpty()) {
                ImasEmptyState(
                    icon = Icons.Filled.CalendarMonth,
                    title = "記録なし",
                    message = "この日にあった記念日・ライブ・リリースはまだ記録がありません"
                )
                return@Column
            }
            Sections(current, onNavigateToSong, onNavigateToIdol, onNavigateToEvent)
        }
    }
}

@Composable
private fun Header(date: LocalDate, digest: OnThisDayDigest?, onShift: (Long) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            ImasMasthead("ON THIS DAY", date.toString().replace('-', '.'))
            ImasText(digest?.day?.title.orEmpty(), ImasTextRole.HERO_TITLE)
        }
        ImasIconButton(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "前の日", { onShift(-1) }, size = ImasIconButtonSize.SMALL)
        ImasIconButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "次の日", { onShift(1) }, size = ImasIconButtonSize.SMALL)
        digest?.day?.share?.let { SocialShareIconButton(it, contentDescription = "この日をシェア") }
    }
}

@Composable
private fun Sections(
    digest: OnThisDayDigest,
    onNavigateToSong: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToEvent: (String) -> Unit
) {
    val day = digest.day
    if (day.anniversaries.isNotEmpty()) {
        ImasSection("記念日", count = "${day.anniversaries.size}件") {
            ImasCardList {
                day.anniversaries.forEachIndexed { idx, ann ->
                    if (idx > 0) ImasRowDivider(inset = DS.Space.rowH + DS.Size.leadBar + DS.Space.rowGap)
                    ImasRow(
                        title = ann.label,
                        subtitle = yearMonthDay(ann.originDate),
                        leadBar = ImasRowLeadBar(brand = ann.brandId),
                        trailing = ImasRowTrailing.Metric("${ann.years}", unit = ann.unit, emphasized = true)
                    )
                }
            }
        }
    }
    val idols = day.birthdays.mapNotNull { digest.idols[it.idolId] }
    if (idols.isNotEmpty()) {
        ImasSection("誕生日", count = "${idols.size}人") {
            ImasCardList {
                idols.forEachIndexed { idx, idol ->
                    if (idx > 0) ImasRowDivider(inset = DS.Space.rowH + 40.dp + DS.Space.rowGap)
                    ImasIdolRow(idol, trailing = ImasRowTrailing.Chevron, onClick = { onNavigateToIdol(idol.id) })
                }
            }
        }
    }
    if (day.lives.isNotEmpty()) {
        ImasSection("ライブ", count = "${day.lives.size}件") {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                day.lives.forEach { live ->
                    ImasShowRow(
                        date = live.date,
                        title = listOfNotNull(live.eventName, live.showLabel).joinToString(" "),
                        subtitle = listOfNotNull(ago(live.years, live.date), live.venue).joinToString(" ・ "),
                        brand = live.brandId,
                        rainbow = live.isJoint,
                        showsChevron = true,
                        subtitleLineLimit = 2,
                        modifier = Modifier.imasRowPress(onClick = { onNavigateToEvent(live.eventId) })
                    )
                }
            }
        }
    }
    val releaseSongs = day.releases.flatMap { release ->
        release.songIds.mapNotNull { digest.songs[it] }.map { it to release }
    }
    if (releaseSongs.isNotEmpty()) {
        ImasSection("リリース", count = "${releaseSongs.size}曲") {
            ImasCardList {
                releaseSongs.forEachIndexed { idx, (song, release) ->
                    if (idx > 0) ImasRowDivider(inset = DS.Space.rowH + 48.dp + DS.Space.rowGap)
                    ImasSongRow(song, onClick = { onNavigateToSong(song.id) }) {
                        ImasText(ago(release.years, release.date), ImasTextRole.META)
                    }
                }
            }
        }
    }
}

/** 「2014年 ・ 12年前」。 */
private fun ago(years: UInt, date: String): String = "${date.take(4)}年 ・ ${years}年前"

/** 起点日 `2024-10-04` → 「2024年10月4日」。 */
private fun yearMonthDay(date: String): String {
    val parts = date.split('-').mapNotNull { it.toIntOrNull() }
    return if (parts.size == 3) "${parts[0]}年${parts[1]}月${parts[2]}日" else date
}
