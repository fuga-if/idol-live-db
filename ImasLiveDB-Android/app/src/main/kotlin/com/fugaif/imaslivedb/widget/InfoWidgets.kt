package com.fugaif.imaslivedb.widget

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.Text
import com.fugaif.imaslivedb.MainActivity
import com.fugaif.imaslivedb.data.model.JstDay
import java.time.LocalDate
import java.time.temporal.ChronoUnit

// =============================================================================
// 情報ウィジェット 3 種。iOS `ImasLiveDBWidget/InfoWidgets.swift` の移植。
//
// タップ先はどれもアプリの起動 (iOS の imaslivedb://open 相当)。iOS はイベント詳細へ
// 直接飛ばしているが、Android 側にはまだアプリ内画面を URL で開く口が無い。
// ナビゲーションに受け口を作るのはウィジェットの担当範囲を越えるので、
// ここでは起動までにとどめてある。
// =============================================================================

// MARK: - 共通ユーティリティ

/** "YYYY-MM-DD" を "M/d" に。曜日や年は入れない (幅が無い)。 */
private fun shortDate(date: String): String {
    val parsed = runCatching { LocalDate.parse(date) }.getOrNull() ?: return date
    return "${parsed.monthValue}/${parsed.dayOfMonth}"
}

/**
 * 今日から [date] までの日数。今日が 0、明日が 1。
 * 基準は JST の今日 ([JstDay]) — 公演日は日本時間の日付なので端末ローカル日で数えるとずれる。
 */
private fun daysUntil(date: String): Long? {
    val target = runCatching { LocalDate.parse(date) }.getOrNull() ?: return null
    return ChronoUnit.DAYS.between(JstDay.date(), target)
}

/** カウントダウンの文言。アプリ内 (イベント詳細の参加予定バッジ) と同じ言い回しに揃える。 */
private fun countdownLabel(days: Long?): String? = when {
    days == null -> null
    days <= 0L -> "今日"
    else -> "あと${days}日"
}

/** 小サイズ (1 列ぶんの幅) か。文字量とレイアウトを切り替える境目。 */
private const val MEDIUM_WIDTH_THRESHOLD_DP = 200

/** small / medium の 2 段階。iOS の systemSmall / systemMedium に対応する。 */
private val INFO_WIDGET_SIZES = setOf(DpSize(140.dp, 110.dp), DpSize(250.dp, 110.dp))

// MARK: - 次のライブ

object NextLiveWidget : GlanceAppWidget() {

    override val sizeMode = SizeMode.Responsive(INFO_WIDGET_SIZES)

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val info = InfoWidgetData.nextShow(context)
        provideContent { NextLiveContent(info) }
    }
}

@Composable
private fun NextLiveContent(info: NextShowInfo?) {
    if (info == null) {
        WidgetPlaceholder("次のライブ情報なし")
        return
    }
    val accent = WidgetTheme.brandAccent(info.brandColorHex)
    val small = LocalSize.current.width.value < MEDIUM_WIDTH_THRESHOLD_DP
    WidgetSurface {
        Row(modifier = GlanceModifier.fillMaxSize().clickable(actionStartActivity<MainActivity>())) {
            // ブランド色のリードバー。アプリの一覧 (ImasLeadBar) と同じ「色は左の細帯で示す」
            // 作法。面全体を塗ると壁紙の上でうるさく、文字色の確保も難しくなる。
            Box(
                modifier = GlanceModifier
                    .width(4.dp)
                    .fillMaxHeight()
                    .background(accent.accent)
                    .cornerRadius(2.dp)
            ) {}
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Text(text = "次のライブ", style = WidgetTheme.caption(accent.accent), maxLines = 1)
                Spacer(GlanceModifier.defaultWeight())
                Text(
                    text = info.eventName,
                    style = WidgetTheme.title(small = small),
                    maxLines = if (small) 3 else 2
                )
                Spacer(GlanceModifier.height(4.dp))
                Row(verticalAlignment = Alignment.Vertical.CenterVertically) {
                    countdownLabel(daysUntil(info.firstDate))?.let { label ->
                        Text(text = label, style = WidgetTheme.body(accent.accent, bold = true), maxLines = 1)
                        Spacer(GlanceModifier.width(6.dp))
                    }
                    Text(text = shortDate(info.firstDate), style = WidgetTheme.body(), maxLines = 1)
                }
            }
        }
    }
}

// MARK: - 今日の1曲

object TodaySongWidget : GlanceAppWidget() {

    override val sizeMode = SizeMode.Responsive(INFO_WIDGET_SIZES)

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val info = InfoWidgetData.todaySong(context)
        // ジャケ写は外部 CDN にあるので、取れなければ無しで描く (音符の面で代替)。
        val artwork = info?.let { WidgetImages.artwork(context, it.songId, it.artworkUrl) }
        provideContent { TodaySongContent(info, artwork) }
    }
}

@Composable
private fun TodaySongContent(info: TodaySongInfo?, artwork: Bitmap?) {
    if (info == null) {
        WidgetPlaceholder("今日の1曲を準備中", "データの取得が終わると出ます")
        return
    }
    val accent = WidgetTheme.brandAccent(info.brandColorHex)
    val small = LocalSize.current.width.value < MEDIUM_WIDTH_THRESHOLD_DP
    val artworkSize = if (small) 48.dp else 56.dp
    WidgetSurface {
        Row(
            modifier = GlanceModifier.fillMaxSize().clickable(actionStartActivity<MainActivity>()),
            verticalAlignment = Alignment.Vertical.CenterVertically
        ) {
            Box(
                modifier = GlanceModifier
                    .size(artworkSize)
                    .background(accent.tint)
                    .cornerRadius(10.dp),
                contentAlignment = Alignment.Center
            ) {
                if (artwork != null) {
                    Image(
                        provider = ImageProvider(artwork),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = GlanceModifier.fillMaxSize().cornerRadius(10.dp)
                    )
                } else {
                    Text(text = "♪", style = WidgetTheme.title(accent.accent, small = false))
                }
            }
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(text = "今日の1曲", style = WidgetTheme.caption(accent.accent), maxLines = 1)
                Spacer(GlanceModifier.height(2.dp))
                Text(text = info.title, style = WidgetTheme.title(small = small), maxLines = 2)
                if (!info.artistLabel.isNullOrEmpty()) {
                    Text(text = info.artistLabel, style = WidgetTheme.body(), maxLines = 1)
                }
            }
        }
    }
}

// MARK: - チケット締切

object TicketDeadlineWidget : GlanceAppWidget() {

    // 「日付 + イベント名」を 3 行なので、小サイズでは名前が読めない。medium 以上のみ。
    override val sizeMode = SizeMode.Responsive(setOf(DpSize(250.dp, 110.dp)))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val deadlines = InfoWidgetData.ticketDeadlines(context, limit = MAX_DEADLINE_ROWS)
        provideContent { TicketDeadlineContent(deadlines) }
    }

    /** iOS と同じく最大 3 件。これ以上はウィジェットの高さに入らない。 */
    private const val MAX_DEADLINE_ROWS = 3
}

@Composable
private fun TicketDeadlineContent(deadlines: List<TicketDeadlineInfo>) {
    if (deadlines.isEmpty()) {
        WidgetPlaceholder("締切近いチケットなし")
        return
    }
    WidgetSurface {
        Column(modifier = GlanceModifier.fillMaxSize().clickable(actionStartActivity<MainActivity>())) {
            Text(text = "チケット締切", style = WidgetTheme.caption(WidgetTheme.warning), maxLines = 1)
            Spacer(GlanceModifier.height(6.dp))
            deadlines.forEach { item ->
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Vertical.CenterVertically
                ) {
                    Text(
                        text = shortDate(item.deadline),
                        style = WidgetTheme.body(WidgetTheme.warning, bold = true),
                        maxLines = 1,
                        modifier = GlanceModifier.width(40.dp)
                    )
                    Spacer(GlanceModifier.width(6.dp))
                    Text(
                        text = item.eventName,
                        style = WidgetTheme.body(WidgetTheme.ink),
                        maxLines = 1,
                        modifier = GlanceModifier.defaultWeight()
                    )
                }
                Spacer(GlanceModifier.height(4.dp))
            }
        }
    }
}

// MARK: - Receiver

class NextLiveWidgetReceiver : ImasWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget get() = NextLiveWidget
}

class TodaySongWidgetReceiver : ImasWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget get() = TodaySongWidget
}

class TicketDeadlineWidgetReceiver : ImasWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget get() = TicketDeadlineWidget
}
