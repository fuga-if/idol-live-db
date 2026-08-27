package com.fugaif.imaslivedb.ui.filtered

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.MarkToggleAction
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 絞り込み一覧 4 種で共有する行と見出し。
 *
 * 一覧そのものは条件ごとに別画面だが、行の見た目は「その種類の一覧」としてアプリ中で
 * 一つでなければならない (ライブ一覧の行と「◯◯のライブ」の行が違って見えると、
 * 絞り込んだ先が別物のリストに見える)。曲行は [com.fugaif.imaslivedb.ui.components.SongRow]
 * をそのまま使えるのでここには無い。
 */

/** 「12曲」「8件」。iOS の Section header と同じ位置づけ (件数だけの小見出し)。 */
@Composable
fun FilteredCountHeader(text: String) {
    Text(
        text,
        fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

/** 0 件表示。画面いっぱいの中央に置く。 */
@Composable
fun FilteredEmptyState(icon: ImageVector, title: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        ImasEmptyState(icon = icon, title = title)
    }
}

/**
 * ライブ 1 件の行。ライブ一覧 (EventListScreen) の行と同じ並び
 * (ブランド色のリードバー + ライブ名 + 開催日 + お気に入り)。
 * 合同ライブはリードバーを虹色にする (どれか 1 ブランドの色を出すと嘘になるため)。
 */
@Composable
fun FilteredEventRow(item: EventWithDateRange, onClick: () -> Unit) {
    val event = item.event
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ImasLeadBar(brandId = event.brandId, height = 38.dp, rainbow = event.jointBrandIdList.isNotEmpty())
        Column(Modifier.weight(1f)) {
            Text(
                event.name,
                fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            // 種別 (ライブ/フェス等) と開催日。iOS の EventNameRow subtitle と同じ組み立て。
            val sub = listOfNotNull(event.eventType.takeIf { it.isNotEmpty() }, item.dateRange)
                .joinToString("  ")
            if (sub.isNotEmpty()) {
                Text(sub, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Spacer(Modifier.width(4.dp))
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

/** アイドル 1 人の行 (アバター + 名前 + よみ + シェブロン)。iOS `IdolNameRow` と同じ並び。 */
@Composable
fun FilteredIdolRow(idol: Idol, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 40.dp)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(
                idol.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            idol.nameKana?.takeIf { it.isNotEmpty() }?.let {
                Text(it, fontSize = 12.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
            tint = DS.ink3, modifier = Modifier.size(16.dp)
        )
    }
}

/**
 * 公演 1 本の行 (リードバー + ライブ名 + 副題 + シェブロン)。
 *
 * 主役はライブ名。公演名・日付・会場は副題にまとめる — 「この会場での公演」を年で束ねて
 * 並べたときに、行から読み取りたいのは「いつのどのライブか」だから。
 */
@Composable
fun FilteredShowRow(
    title: String,
    subtitle: String,
    brandId: String?,
    rainbow: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ImasLeadBar(brandId = brandId, height = 38.dp, rainbow = rainbow)
        Column(Modifier.weight(1f)) {
            Text(
                title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            if (subtitle.isNotEmpty()) {
                Text(subtitle, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
            tint = DS.ink3, modifier = Modifier.size(16.dp)
        )
    }
}
