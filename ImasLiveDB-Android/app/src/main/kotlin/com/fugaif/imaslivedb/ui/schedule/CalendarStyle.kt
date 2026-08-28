package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.data.model.TicketDateKind
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.brandColor

// =============================================================================
// カレンダーの色とラベル (iOS `CalendarEntry+Display.swift` に対応)。
//
// 種別 1 色の対応は既存のフィルタチップ/ドットと同じものを使い、公演だけブランド色に振る。
// 公演は 1 日に別ブランドのものが並ぶことがあり、そこは行のリードバーでも既にブランド色で
// 区別しているため (青一色にすると帯にした意味が薄い)。
// =============================================================================

/** 公演。フィルタチップの色 (帯自体はブランド色を使う)。 */
val ShowColor = Color(0xFF3E6DD6)
val ReleaseColor = DS.warning
val BirthdayColor = DS.pick
val StaffColor = DS.pick
val AnniversaryColor = DS.sys

/** チケット系 (受付期間・当落発表)。公演(青)・リリース(橙)・誕生日(桃) と被らない藍 (iOS と同じ色域)。 */
val TicketColor = Color(0xFF5856D6)

/** ドット・チップの色。種別 1 つに 1 色 (申込締切だけ行側で緊急色に振る)。 */
fun categoryColor(category: CalendarCategory): Color = when (category) {
    CalendarCategory.SHOW -> ShowColor
    CalendarCategory.RELEASE -> ReleaseColor
    CalendarCategory.BIRTHDAY -> BirthdayColor
    CalendarCategory.STAFF_BIRTHDAY -> StaffColor
    CalendarCategory.ANNIVERSARY -> AnniversaryColor
    CalendarCategory.TICKET -> TicketColor
}

/**
 * 帯・ブロックの地色。
 *
 * 公演だけブランド色にするのは iOS と同じ (iOS は `row.brandColor`)。
 * 誕生日は iOS がアイドルのイメージカラーを使うが、Android の `CalBirthdayRow` は
 * イメージカラーを運んでいないので既存のドットと同じ桃で塗る。
 */
fun CalendarEntry.accentColor(): Color = when (this) {
    is CalendarEntry.Show -> brandColor(row.brandId)
    is CalendarEntry.Release -> ReleaseColor
    is CalendarEntry.Birthday -> BirthdayColor
    is CalendarEntry.StaffBirthday -> StaffColor
    is CalendarEntry.Anniversary -> AnniversaryColor
    is CalendarEntry.Ticket -> if (row.kind == TicketDateKind.DEADLINE) DS.danger else TicketColor
    is CalendarEntry.TicketPeriod -> TicketColor
}

/**
 * 地色の上に乗せる文字色。
 * ブランド色には黄色 (#F5C900 系) や白系も普通にあるので、白固定にせず
 * 色エンジンの WCAG コントラスト判定で黒/白を選ばせる (iOS `accentInk` と同じ)。
 */
fun CalendarEntry.accentInk(): Color = ImasTheme.onColor(accentColor())

/**
 * 帯 1 本に載せる短いラベル。狭いので修飾は最小限にする。
 * ライブ名は「省略表示」設定に従う (フルネームだと帯の幅では作品名しか読めない)。
 */
fun CalendarEntry.barLabel(): String = when (this) {
    is CalendarEntry.Show -> AppPreferences.eventDisplayName(row.eventName)
    is CalendarEntry.Release -> songs.firstOrNull()?.title ?: "リリース"
    is CalendarEntry.Birthday -> row.name
    is CalendarEntry.StaffBirthday -> row.name
    // 月セルは狭いので「ラベル」だけ。N周年は日詳細で見せる。
    is CalendarEntry.Anniversary -> row.label
    is CalendarEntry.Ticket -> "${row.kind.label}・${AppPreferences.eventDisplayName(row.eventName)}"
    is CalendarEntry.TicketPeriod -> "受付・${AppPreferences.eventDisplayName(row.eventName)}"
}

/**
 * 1 エントリの色帯。月グリッドの日セルと週ビューの終日レーンで共有する
 * (iOS `CalendarEntryBar` と 1:1)。
 */
@Composable
fun CalendarEntryBar(
    entry: CalendarEntry,
    height: Dp = 11.dp,
    fontSize: androidx.compose.ui.unit.TextUnit = 8.sp,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(2.dp))
            .background(entry.accentColor())
            .padding(horizontal = 3.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        Text(
            entry.barLabel(),
            color = entry.accentInk(),
            fontSize = fontSize,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/** "2026-06-13" → "6/13"。解釈できない値は null。 */
fun monthDay(ymd: String): String? {
    val parts = ymd.split("-")
    if (parts.size != 3) return null
    val m = parts[1].toIntOrNull() ?: return null
    val d = parts[2].toIntOrNull() ?: return null
    return "$m/$d"
}
