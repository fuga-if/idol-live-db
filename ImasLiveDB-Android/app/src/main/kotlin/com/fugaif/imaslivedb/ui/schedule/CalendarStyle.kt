package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
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
import com.fugaif.imaslivedb.ui.theme.imasTheme

// =============================================================================
// カレンダーの色とラベル (iOS `CalendarEntry+Display.swift` に対応)。
//
// 種別 1 色の対応は既存のフィルタチップ/ドットと同じものを使い、公演だけブランド色に振る。
// 公演は 1 日に別ブランドのものが並ぶことがあり、そこは行のリードバーでも既にブランド色で
// 区別しているため (青一色にすると帯にした意味が薄い)。
// =============================================================================

/**
 * 固有色を持たない種別の帯・チップ色を導くための固定シード (iOS `CalendarEntry.ThemeSeed` と同じ値)。
 * 生の hex や `DS.sys`/`DS.pick` の流用ではなく、色エンジン ([imasTheme]) に通して
 * 現在のモード (ライト/ダーク) に合った濃さ・コントラストにする。
 */
private object CalendarThemeSeed {
    /** 公演 (フィルタチップ代表色。iOS system blue 相当)。 */
    const val SHOW = "#3E6DD6"

    /** 事務員誕生日 (iOS system pink 相当)。 */
    const val STAFF_BIRTHDAY = "#FF2D55"

    /** ブランド記念日 (iOS system teal 相当)。 */
    const val ANNIVERSARY = "#30B0C7"

    /** チケット関連 (受付期間・当落発表。iOS system indigo 相当)。 */
    const val TICKET = "#5856D6"
}

/** 公演。フィルタチップの色 (帯自体は [CalendarEntry.accentColor] でブランド色を使う)。 */
val ShowColor: Color @Composable @ReadOnlyComposable get() = imasTheme(CalendarThemeSeed.SHOW).accent

// DS トークン由来の 2 色 (リリース・誕生日) は、現在のモードを合成から引く (`DS` と同じ形の @Composable プロパティ)。
val ReleaseColor: Color @Composable @ReadOnlyComposable get() = DS.warning
val BirthdayColor: Color @Composable @ReadOnlyComposable get() = DS.pick

/** 事務員誕生日。固有色が無いので色エンジン導出のピンク (iOS と同じシード、アイドル誕生日の桃とは別シード)。 */
val StaffColor: Color @Composable @ReadOnlyComposable get() = imasTheme(CalendarThemeSeed.STAFF_BIRTHDAY).accent

/** 記念日。公演(青)・リリース(橙)・誕生日(桃)と被らない色エンジン導出のティール。 */
val AnniversaryColor: Color @Composable @ReadOnlyComposable get() = imasTheme(CalendarThemeSeed.ANNIVERSARY).accent

/** チケット系 (受付期間・当落発表)。公演(青)・リリース(橙)・誕生日(桃) と被らない色エンジン導出の藍。 */
val TicketColor: Color @Composable @ReadOnlyComposable get() = imasTheme(CalendarThemeSeed.TICKET).accent

/**
 * 帯・ブロックの地色。
 *
 * 公演だけブランド色にするのは iOS と同じ (iOS は `row.brandColor`)。
 * 誕生日は iOS がアイドルのイメージカラーを使うが、Android の `CalBirthdayRow` は
 * イメージカラーを運んでいないので既存のドットと同じ桃で塗る。
 */
@Composable
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
@Composable
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
    // ライブ名が分かるように、コアが組んだ label (`"{event_name} ({sale_name})"`) をそのまま使う (M2)。
    is CalendarEntry.Ticket -> "${row.kind.label}・${row.label}"
    is CalendarEntry.TicketPeriod -> "受付・${row.label}"
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
