package com.fugaif.imaslivedb.ui.filtered

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEventRow
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasShowRow
import com.fugaif.imaslivedb.ui.components.MarkToggleAction
import com.fugaif.imaslivedb.ui.events.eventTypeLabel
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasRowPress

/**
 * 絞り込み一覧 4 種で共有する行と空状態。
 *
 * 一覧そのものは条件ごとに別画面だが、行の見た目は「その種類の一覧」としてアプリ中で
 * 一つでなければならない (ライブ一覧の行と「◯◯のライブ」の行が違って見えると、
 * 絞り込んだ先が別物のリストに見える)。曲行は [com.fugaif.imaslivedb.ui.components.SongRow]
 * をそのまま使えるのでここには無い。件数の見出しは各画面で `ImasListSummary` を直接使う。
 */

/** 0 件表示。画面いっぱいの中央に置く。 */
@Composable
fun FilteredEmptyState(icon: ImageVector, title: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        ImasEmptyState(icon = icon, title = title)
    }
}

/**
 * ライブ 1 件の行。ライブ一覧 (EventListScreen) の行と同じ半券 ([ImasEventRow])。
 * 合同ライブはリードバーを虹色にする (どれか 1 ブランドの色を出すと嘘になるため)。
 * 絞り込み結果一覧は NavigationLink に包まない行なので矢印を足す (DESIGN_SYSTEM §5.4)。
 */
@Composable
fun FilteredEventRow(item: EventWithDateRange, onClick: () -> Unit) {
    val event = item.event
    Row(verticalAlignment = Alignment.CenterVertically) {
        // 種別は生の内部値ではなくラベルで出す。未分類なら日付だけ。
        val sub = listOfNotNull(eventTypeLabel(event.eventType), item.dateRange).joinToString("  ")
        ImasEventRow(
            event = event,
            modifier = Modifier.weight(1f),
            date = item.firstDate,
            subtitle = sub.ifEmpty { null },
            rainbow = item.isJoint,
            showsChevron = true,
            onClick = onClick
        )
        MarkToggleAction(
            entityType = UserMark.EVENT,
            entityId = event.id,
            kind = UserMark.FAVORITE,
            activeIcon = Icons.Filled.Star,
            inactiveIcon = Icons.Filled.StarBorder,
            activeTint = DS.favorite,
            contentDescription = "お気に入り"
        )
    }
}

/** アイドル 1 人の行 (iOS `IdolNameRow` と同じ並び)。見た目は一覧と同じ [ImasIdolRow]。 */
@Composable
fun FilteredIdolRow(idol: Idol, onClick: () -> Unit) {
    ImasIdolRow(
        idol = idol,
        subtitle = idol.nameKana?.takeIf { it.isNotEmpty() },
        trailing = ImasRowTrailing.Chevron,
        onClick = onClick
    )
}

/**
 * 公演 1 本の行 (半券 [ImasShowRow])。
 *
 * 主役はライブ名。公演名・日付・会場は副題にまとめる — 「この会場での公演」を年で束ねて
 * 並べたときに、行から読み取りたいのは「いつのどのライブか」だから。
 */
@Composable
fun FilteredShowRow(
    date: String,
    title: String,
    subtitle: String,
    brandId: String?,
    rainbow: Boolean,
    onClick: () -> Unit
) {
    ImasShowRow(
        date = date,
        title = title,
        modifier = Modifier.imasRowPress(onClick = onClick),
        subtitle = subtitle.ifEmpty { null },
        brand = brandId,
        rainbow = rainbow,
        showsChevron = true
    )
}
