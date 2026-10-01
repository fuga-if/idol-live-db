package com.fugaif.imaslivedb.ui.designsystem.catalog

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Celebration
import androidx.compose.material.icons.filled.Chair
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CurrencyYen
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Poll
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Style
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.ui.designsystem.ImasAccentCardStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRowKind
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasArtworkCell
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatarStack
import com.fugaif.imaslivedb.ui.designsystem.ImasAwardChip
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeSpec
import com.fugaif.imaslivedb.ui.designsystem.ImasBoard
import com.fugaif.imaslivedb.ui.designsystem.ImasBoardCell
import com.fugaif.imaslivedb.ui.designsystem.ImasBrandOption
import com.fugaif.imaslivedb.ui.designsystem.ImasBrandPicker
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCandidateCount
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasCardStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasChip
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasChipInputField
import com.fugaif.imaslivedb.ui.designsystem.ImasChipLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasChipRow
import com.fugaif.imaslivedb.ui.designsystem.ImasChipStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasChoice
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceCards
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceCardsStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasColorPicker
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasDateHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasDateMark
import com.fugaif.imaslivedb.ui.designsystem.ImasDisclosureRow
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasFeatureAction
import com.fugaif.imaslivedb.ui.designsystem.ImasFeatureCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFeatureMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasFeatureSurface
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterBar
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterBarItem
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasForecastAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasForecastMeasure
import com.fugaif.imaslivedb.ui.designsystem.ImasForecastRow
import com.fugaif.imaslivedb.ui.designsystem.ImasFormAmount
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormLink
import com.fugaif.imaslivedb.ui.designsystem.ImasFormPage
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormToggle
import com.fugaif.imaslivedb.ui.designsystem.ImasGridLayout
import com.fugaif.imaslivedb.ui.designsystem.ImasHero
import com.fugaif.imaslivedb.ui.designsystem.ImasHeroAction
import com.fugaif.imaslivedb.ui.designsystem.ImasHeroLayout
import com.fugaif.imaslivedb.ui.designsystem.ImasHeroSurface
import com.fugaif.imaslivedb.ui.designsystem.ImasIconBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolCell
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolGrid
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineSpinner
import com.fugaif.imaslivedb.ui.designsystem.ImasLevelCell
import com.fugaif.imaslivedb.ui.designsystem.ImasLikeButton
import com.fugaif.imaslivedb.ui.designsystem.ImasListBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasListSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkBar
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkKind
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkTile
import com.fugaif.imaslivedb.ui.designsystem.ImasMasthead
import com.fugaif.imaslivedb.ui.designsystem.ImasMediaBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasMenuRow
import com.fugaif.imaslivedb.ui.designsystem.ImasMeter
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasNameFilterField
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasPass
import com.fugaif.imaslivedb.ui.designsystem.ImasPassStats
import com.fugaif.imaslivedb.ui.designsystem.ImasPerforation
import com.fugaif.imaslivedb.ui.designsystem.ImasPerformer
import com.fugaif.imaslivedb.ui.designsystem.ImasPodium
import com.fugaif.imaslivedb.ui.designsystem.ImasPodiumEntry
import com.fugaif.imaslivedb.ui.designsystem.ImasPoint
import com.fugaif.imaslivedb.ui.designsystem.ImasPointList
import com.fugaif.imaslivedb.ui.designsystem.ImasPriceList
import com.fugaif.imaslivedb.ui.designsystem.ImasPriceRow
import com.fugaif.imaslivedb.ui.designsystem.ImasProgressBar
import com.fugaif.imaslivedb.ui.designsystem.ImasProgressRing
import com.fugaif.imaslivedb.ui.designsystem.ImasRankBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasRecordRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRemovableChip
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowEmphasis
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectionTray
import com.fugaif.imaslivedb.ui.designsystem.ImasSetlistRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSetupHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasShortcutGroup
import com.fugaif.imaslivedb.ui.designsystem.ImasShortcutTile
import com.fugaif.imaslivedb.ui.designsystem.ImasShowRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSignInPrompt
import com.fugaif.imaslivedb.ui.designsystem.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasStageAssignmentTarget
import com.fugaif.imaslivedb.ui.designsystem.ImasStageBadgeStamp
import com.fugaif.imaslivedb.ui.designsystem.ImasStageCircleButton
import com.fugaif.imaslivedb.ui.designsystem.ImasStageColorGridIcon
import com.fugaif.imaslivedb.ui.designsystem.ImasStageColorSwatch
import com.fugaif.imaslivedb.ui.designsystem.ImasStageColorSwatchStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasStageEqualizer
import com.fugaif.imaslivedb.ui.designsystem.ImasStageIconTileButton
import com.fugaif.imaslivedb.ui.designsystem.ImasStageInfoRow
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePanel
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePartialVerdictCard
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePenlightBars
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePlaybackControl
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePlaybackStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePreviewCard
import com.fugaif.imaslivedb.ui.designsystem.ImasStageProgressBar
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePulse
import com.fugaif.imaslivedb.ui.designsystem.ImasStageRushFlash
import com.fugaif.imaslivedb.ui.designsystem.ImasStageScoreChip
import com.fugaif.imaslivedb.ui.designsystem.ImasStageStatTile
import com.fugaif.imaslivedb.ui.designsystem.ImasStageVersusPlayer
import com.fugaif.imaslivedb.ui.designsystem.ImasStageVersusResult
import com.fugaif.imaslivedb.ui.designsystem.ImasStageWordmark
import com.fugaif.imaslivedb.ui.designsystem.ImasStatBar
import com.fugaif.imaslivedb.ui.designsystem.ImasStatGrid
import com.fugaif.imaslivedb.ui.designsystem.ImasStatTile
import com.fugaif.imaslivedb.ui.designsystem.ImasStep
import com.fugaif.imaslivedb.ui.designsystem.ImasStepList
import com.fugaif.imaslivedb.ui.designsystem.ImasStepperRow
import com.fugaif.imaslivedb.ui.designsystem.ImasStubDate
import com.fugaif.imaslivedb.ui.designsystem.ImasStubRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSuggestionBar
import com.fugaif.imaslivedb.ui.designsystem.ImasSuggestionBarStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipe
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeAction
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.designsystem.ImasTagHeaderCard
import com.fugaif.imaslivedb.ui.designsystem.ImasTextAreaRow
import com.fugaif.imaslivedb.ui.designsystem.ImasTextFieldRow
import com.fugaif.imaslivedb.ui.designsystem.ImasTicket
import com.fugaif.imaslivedb.ui.designsystem.ImasTicketCountdown
import com.fugaif.imaslivedb.ui.designsystem.ImasTicketRow
import com.fugaif.imaslivedb.ui.designsystem.ImasTicketStack
import com.fugaif.imaslivedb.ui.designsystem.ImasTicketStackItem
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.designsystem.ImasToolbarButton
import com.fugaif.imaslivedb.ui.designsystem.ImasUnitAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasUnitCell
import com.fugaif.imaslivedb.ui.designsystem.ImasValueRow
import com.fugaif.imaslivedb.ui.designsystem.ImasVersusBadge
import com.fugaif.imaslivedb.ui.designsystem.LocalImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.imasAccentCard
import com.fugaif.imaslivedb.ui.designsystem.imasTabSwipe
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasAlwaysDark
import com.fugaif.imaslivedb.ui.theme.ImasBackdrop
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasThemeProvider
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasBackdrop
import com.fugaif.imaslivedb.ui.theme.QS
import com.fugaif.imaslivedb.ui.theme.hexToColor
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Share
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatch
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatchSize
import kotlinx.coroutines.delay
import uniffi.imas_core.RowNoteTone
import uniffi.imas_core.SetlistRowNoteGroupRecord
import uniffi.imas_core.SetlistRowNoteRecord

// =============================================================================
// 部品カタログ (デバッグビルドだけ)。iOS `DesignSystem/Catalog/DesignCatalogView.swift` の移植。
//
// デザインシステムの全部品を、種類と状態ごとに実物で並べる。ページ割りは iOS と同じ
// (末尾の 1 ページは iOS のカタログに無い部品・操作を見るための Android の見本)。
// 開き方は DesignCatalogActivity の KDoc (adb の intent extra)。
// =============================================================================

/** カタログのページ (iOS `DesignCatalogPage`)。[id] は iOS の rawValue と同じ (adb の `page` に渡す)。 */
enum class DesignCatalogPage(val id: String, val title: String) {
    VENUE("venue", "会場の部品 (チケット・掲示板・印)"),
    VENUE_ROWS("venueRows", "半券の行・入場証・名札"),
    APPLICATION("application", "申込書 (編集シートの欄)"),
    BUTTONS("buttons", "ボタン"),
    CHIPS("chips", "チップ・札・数字"),
    ROWS("rows", "行 (実体)"),
    ROWS2("rows2", "行 (項目・入口・選択)"),
    SECTIONS("sections", "区画・面・お知らせ"),
    HERO_SONG("heroSong", "詳細の頭 (曲)"),
    HERO_IDOL("heroIdol", "詳細の頭 (アイドル)"),
    HERO_IDOL_COLOR("heroIdolColor", "詳細の頭 (アイドル・色の面)"),
    HUB("hub", "ハブ"),
    HUB_COLOR("hubColor", "ハブ (担当を色の面で)"),
    FEEDBACK("feedback", "状態・メーター"),
    SETLIST("setlist", "セトリと予想"),
    LIST("list", "一覧の型"),
    FORM("form", "編集シートの型"),
    SETUP("setup", "ゲームの設定・読みもの"),
    COMMUNITY("community", "コミュニティ (タグ・記録)"),
    CHAT("chat", "AI チャット"),
    STAGE("stage", "あそぶ (ステージ)"),

    /** Android だけ: iOS のカタログに載っていない部品 (行を引く・横に払う・値を選ぶ・絞り込みの帯ほか)。 */
    EXTRAS("extras", "指の操作・そのほか (Android の見本)");

    companion object {
        fun fromId(id: String): DesignCatalogPage? = entries.firstOrNull { it.id.equals(id, ignoreCase = true) }
    }
}

/** 見本を撮るとき、ページの途中・下を出す (adb の `scroll` = center / bottom。iOS の `DS_SCROLL`)。 */
private val LocalCatalogScroll = staticCompositionLocalOf<String?> { null }

@Composable
private fun rememberCatalogScrollState(): ScrollState {
    val state = rememberScrollState()
    val anchor = LocalCatalogScroll.current
    LaunchedEffect(anchor, state.maxValue) {
        when (anchor) {
            "bottom" -> state.scrollTo(state.maxValue)
            "center" -> state.scrollTo(state.maxValue / 2)
        }
    }
    return state
}

/**
 * 部品カタログの画面。[initialPage] が無ければ目次から。上の帯でライト/ダークを切り替えられる。
 *
 * @param scrollAnchor 見本を撮るときの位置 (center / bottom)。
 */
@Composable
fun DesignCatalogScreen(
    initialPage: DesignCatalogPage?,
    scrollAnchor: String?,
    dark: Boolean,
    onToggleTheme: () -> Unit,
    onFinish: () -> Unit
) {
    var page by rememberSaveable { mutableStateOf(initialPage) }
    BackHandler(enabled = page != null) { page = null }
    Column(
        Modifier
            .fillMaxSize()
            .background(DS.bg)
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(DS.bg)
                .statusBarsPadding()
                .heightIn(min = 52.dp)
                .padding(horizontal = DS.Space.gapTight),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (page != null) {
                ImasToolbarButton(Icons.AutoMirrored.Filled.ArrowBack, "目次へ", { page = null })
            } else {
                ImasToolbarButton(Icons.Filled.Close, "閉じる", onFinish)
            }
            Text(
                page?.title ?: "部品カタログ",
                style = ImasType.heading(17.sp, FontWeight.Bold),
                color = DS.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            ImasToolbarButton(
                if (dark) Icons.Filled.LightMode else Icons.Filled.DarkMode,
                if (dark) "ライトで見る" else "ダークで見る",
                onToggleTheme
            )
        }
        Box(
            Modifier
                .weight(1f)
                .navigationBarsPadding()
        ) {
            CompositionLocalProvider(LocalCatalogScroll provides scrollAnchor) {
                when (page) {
                    null -> CatalogIndex { page = it }
                    DesignCatalogPage.VENUE -> VenuePage()
                    DesignCatalogPage.VENUE_ROWS -> VenueRowsPage()
                    DesignCatalogPage.APPLICATION -> ApplicationFormPage()
                    DesignCatalogPage.BUTTONS -> ButtonsPage()
                    DesignCatalogPage.CHIPS -> ChipsPage()
                    DesignCatalogPage.ROWS -> EntityRowsPage()
                    DesignCatalogPage.ROWS2 -> ValueRowsPage()
                    DesignCatalogPage.SECTIONS -> SectionsPage()
                    DesignCatalogPage.HERO_SONG -> SongHeroPage()
                    DesignCatalogPage.HERO_IDOL -> IdolHeroPage(ImasHeroSurface.PAPER)
                    DesignCatalogPage.HERO_IDOL_COLOR -> IdolHeroPage(ImasHeroSurface.COLOR)
                    DesignCatalogPage.HUB -> HubPage(ImasFeatureSurface.PANEL)
                    DesignCatalogPage.HUB_COLOR -> HubPage(ImasFeatureSurface.COLOR)
                    DesignCatalogPage.FEEDBACK -> FeedbackPage()
                    DesignCatalogPage.SETLIST -> SetlistPage()
                    DesignCatalogPage.LIST -> ListTemplatePage()
                    DesignCatalogPage.FORM -> FormTemplatePage()
                    DesignCatalogPage.SETUP -> SetupPage()
                    DesignCatalogPage.COMMUNITY -> CommunityPage()
                    DesignCatalogPage.CHAT -> ChatPage()
                    DesignCatalogPage.STAGE -> StagePage()
                    DesignCatalogPage.EXTRAS -> ExtrasPage()
                }
            }
        }
    }
}

/** カタログの目次 (iOS `DesignCatalogIndexView`)。 */
@Composable
private fun CatalogIndex(onOpen: (DesignCatalogPage) -> Unit) {
    ImasPage(scrollState = rememberCatalogScrollState()) {
        ImasCardList(DesignCatalogPage.entries, key = { it.id }) { page ->
            ImasNavRow(page.title, value = page.id, onClick = { onOpen(page) })
        }
        ImasNote(
            "adb shell am start -n site.fugaapp.imaslivedb/com.fugaif.imaslivedb.ui.designsystem.catalog.DesignCatalogActivity " +
                "--es page venue --es theme dark (scroll = center / bottom も渡せる)"
        )
    }
}

/** カタログのページの本体 (紙面の `ImasPage`。見本を撮る位置に合わせてスクロールする)。 */
@Composable
private fun CatalogPage(content: @Composable ColumnScope.() -> Unit) {
    ImasPage(scrollState = rememberCatalogScrollState(), content = content)
}

/** 2 行目以降の行 (iOS `.environment(\.imasRowPosition, .following)`)。 */
@Composable
private fun Following(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalImasRowPosition provides ImasRowPosition.FOLLOWING, content = content)
}

// MARK: - 見本の色

private object Sample {
    const val haruka = "#E22B30"
    const val chihaya = "#2743D2"
    const val miki = "#B4E04B"
    const val makoto = "#515558"
    const val yayoi = "#F39939"
    const val kanade = "#0D386D"
    const val saki = "#EA4A5B"
    const val shizuka = "#6495CF"
    const val kotoha = "#92CFBB"
    const val as765 = "#f34f6d"
    const val cg = "#2681c8"
    const val ml = "#ffc30b"
    const val gakuen = "#f39800"

    /** 見本のユニット (`ImasUnitAvatar`・`ImasUnitCell`・`ImasForecastRow(unit)`)。 */
    val unit = ImasUnit(id = "sample-765as", brandId = "765as", name = "765PRO ALLSTARS", isPermanent = true, nameAlt = null)

    /** 見本のジャケ (実際の配信の画像)。 */
    object Art {
        private fun url(s: String) = "https://is1-ssl.mzstatic.com/image/thumb/$s/600x600bb.jpg"
        val idolmaster = url("Music116/v4/2c/67/8d/2c678df3-f929-6bad-8c66-bef3c669c7e8/4540774158782.jpg")
        val ready = url("Music122/v4/9e/37/0b/9e370bf4-b073-c6f9-18b1-dc4c6a4160e6/COCX-38070.jpg")
        val jealousy = url("Music116/v4/96/80/64/96806435-086e-04ad-f2ad-eed5cf9db9ed/PA00114560_0_162943_jacket.jpg")
        val thankYou = url("Music126/v4/ec/bc/da/ecbcdafa-f3cb-f967-6b96-e75ee8272493/4540774250431.jpg")
        val onegai = url("Music124/v4/c0/0c/9a/c00c9ad7-b952-dd1d-4bc9-d38f9f343ccd/COCC_16718.jpg")
        val shirube = url("Music211/v4/d2/d0/d1/d2d0d166-6d01-5ba1-1bb3-ac7afe4f04a6/PA00185909_0_222005_jacket.jpg")
        val fightingMyWay = url("Music221/v4/33/4e/9c/334e9c4b-6ae8-55b2-7d1f-e6ab30fb2d9b/PA00153099_0_191075_jacket.jpg")
        val hajime = url("Music211/v4/e5/ca/75/e5ca7591-dac2-60fa-348c-4a850f219c68/PA00153098_0_191078_jacket.jpg")
    }
}

private val Small = ImasSectionHeaderStyle.SMALL

// MARK: - 会場の部品

@Composable
private fun VenuePage() {
    var pick by remember { mutableStateOf(true) }
    var favorite by remember { mutableStateOf(false) }
    CatalogPage {
        ImasSection("頭の印字", style = Small) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                ImasMasthead("PRODUCE", "2026.10.01 THU")
                Text("プロデュース", style = ImasType.heading(34.sp, FontWeight.ExtraBold), color = DS.ink)
            }
        }
        ImasSection("チケット", style = Small, footer = "次のライブ・次の出演。右の半券にカウントダウン。紙はダークでも明るい。") {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                ImasTicket(
                    label = "参加予定",
                    title = "学園アイドルマスター LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)",
                    metaImprint = "11.07 SAT",
                    meta = "DAY1 · Kアリーナ横浜",
                    seed = Sample.gakuen,
                    countdown = ImasTicketCountdown("37")
                )
                ImasTicket(
                    label = "次の出演",
                    imprint = "NEXT STAGE",
                    title = "765 PRODUCTION × 961 PRODUCTION IDOL ULTIMATE ONCE AND FOR ALL",
                    metaImprint = "2027.07.25 SUN",
                    meta = "第三公演 · 京王アリーナ TOKYO",
                    seed = Sample.haruka,
                    countdown = ImasTicketCountdown("297")
                )
                ImasTicket(label = "DAY2", imprint = "09.23 WED", title = "学園アイドルマスター LIVE TOUR -標- 岩手公演", seed = Sample.gakuen)
            }
        }
        ImasSection("電光掲示板", style = Small, footer = "記録や出演の数。ライトでもダークでも板は暗い。") {
            ImasBoard(
                cells = listOf(
                    ImasBoardCell("189", "出演", "公演"),
                    ImasBoardCell("42", "歌唱した曲", "曲"),
                    ImasBoardCell("12", "一緒に参加", "公演")
                ),
                title = "STATS",
                trailing = "2005 — 2026"
            )
        }
        ImasSection("料金表", style = Small, footer = "電光掲示板と同じ暗い板。価格帯は内訳行を少し下げて小さく添える。") {
            ImasPriceList(
                title = "TICKET",
                rows = listOf(
                    ImasPriceRow("general", "一般 指定席", "¥9,800"),
                    ImasPriceRow("premium", "プレミアム席", "¥15,800", note = "特典付き"),
                    ImasPriceRow("stream", "ライブ・ビューイング", "¥5,500〜¥13,200"),
                    ImasPriceRow("stream-sub", "会場による内訳あり", "推定含む", indented = true)
                )
            )
        }
        ImasSection("印", style = Small, footer = "担当・お気に入り・メモは丸いパンチ。押すと実体の色で点く。操作 (出演ライブ) は墨の丸。") {
            ImasThemeProvider(seed = Sample.haruka) {
                ImasMarkBar {
                    ImasMarkTile(Icons.Filled.Favorite, "担当", pick, { pick = !pick })
                    ImasMarkTile(if (favorite) Icons.Filled.Star else Icons.Filled.StarBorder, "お気に入り", favorite, { favorite = !favorite })
                    ImasMarkTile(Icons.AutoMirrored.Outlined.Notes, "メモ", false, {})
                    ImasMarkTile(Icons.Filled.Mic, "出演ライブ", false, {}, isAction = true)
                }
            }
        }
        ImasSection("切り取り線", style = Small) {
            ImasPerforation()
        }
    }
}

// MARK: - 半券の行・入場証・名札

@Composable
private fun VenueRowsPage() {
    var pick by remember { mutableStateOf(true) }
    var brands by remember { mutableStateOf(setOf("765as", "gakuen")) }
    val brandOptions = remember {
        listOf(
            ImasBrandOption("765as", "765", Sample.as765),
            ImasBrandOption("cg", "シンデレラ", Sample.cg),
            ImasBrandOption("ml", "ミリオン", Sample.ml),
            ImasBrandOption("sidem", "SideM", "#0fbe94"),
            ImasBrandOption("sc", "シャニ", "#8dbbff"),
            ImasBrandOption("gakuen", "学マス", Sample.gakuen)
        )
    }
    CatalogPage {
        ImasSection("半券の行", style = Small, footer = "ライブ・公演・記録の一覧。参加・参加予定は事実の札で出す。右に引くと参加予定にできる。") {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasStubRow(
                    date = ImasStubDate("2026-11-07"),
                    title = "学園アイドルマスター LIVE TOUR -標- Kアリーナ横浜公演 (FINAL) DAY1",
                    subtitle = "Kアリーナ横浜 · 17:00",
                    seed = Sample.gakuen,
                    badges = listOf(ImasBadgeSpec("参加予定", ImasBadgeKind.PLANNED))
                )
                ImasStubRow(
                    date = ImasStubDate("2026-10-28"),
                    title = "灯里愛夏 BIRTHDAY ONLINE LIVE 2026",
                    subtitle = "配信 · ASOBI STAGE",
                    seed = "#656a75",
                    badges = listOf(ImasBadgeSpec("配信", ImasBadgeKind.NEUTRAL))
                )
                ImasStubRow(
                    date = ImasStubDate("2026-09-23"),
                    title = "学園アイドルマスター LIVE TOUR -標- 岩手公演 DAY2",
                    subtitle = "トーサイクラシックホール岩手",
                    seed = Sample.gakuen,
                    badges = listOf(ImasBadgeSpec("参加", ImasBadgeKind.POSITIVE))
                )
                ImasStubRow(date = ImasStubDate("2024-08"), title = "日付が月までの公演", subtitle = "会場未定")
                ImasStubRow(
                    date = ImasStubDate("2025-12-13"),
                    title = "765PRO ALLSTARS × CINDERELLA GIRLS 合同ライブ",
                    subtitle = "京セラドーム大阪",
                    badges = listOf(ImasBadgeSpec("合同", ImasBadgeKind.UNIT)),
                    rainbow = true
                )
                ImasStubRow(
                    date = ImasStubDate("2026-11-28"),
                    title = "絞り込み結果から開いた公演",
                    subtitle = "Kアリーナ横浜",
                    seed = Sample.cg,
                    showsChevron = true
                )
            }
        }
        ImasSection("半券の形の短い行", style = Small) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasTicketRow("アソビストア一般会員先行", subtitle = "抽選 · 受付中 · 当落 10.31 13:00", deadline = "10.19")
                ImasTicketRow("SideM PRODUCER MEETING", subtitle = "プレミアム会員先行 · 締切", deadline = "23:59", isUrgent = true)
                ImasTicketRow("チケット代が未記録の公演が 3 件", subtitle = "過去の参加から取り込む", onClick = {})
            }
        }
        ImasSection("入場証", style = Small) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                ImasPass(
                    leftImprint = "PRODUCER PASS",
                    title = "花海咲季",
                    rightImprint = "担当",
                    subtitle = "学マス · CV 長月あおい",
                    seed = Sample.saki,
                    trailing = { ImasPassStats(listOf("12" to "回収", "4" to "参加")) }
                )
                ImasPass(
                    leftImprint = "ACCOUNT",
                    title = "fuga",
                    rightImprint = "ログイン中",
                    subtitle = "コミュニティで表示される名前",
                    onOpen = {}
                )
            }
        }
        ImasSection("チケットの束", style = Small, footer = "横に払うと次のチケットが上に来る。") {
            ImasTicketStack(
                listOf(
                    ImasTicketStackItem("1", "11.07 SAT · 標 FINAL DAY1 · 37 DAYS") {
                        ImasTicket(
                            label = "参加予定",
                            title = "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL) DAY1",
                            metaImprint = "11.07 SAT",
                            meta = "Kアリーナ横浜 · 17:00",
                            seed = Sample.gakuen,
                            countdown = ImasTicketCountdown("37")
                        )
                    },
                    ImasTicketStackItem("2", "11.08 SUN · 標 FINAL DAY2 · 38 DAYS") {
                        ImasTicket(
                            label = "参加予定",
                            title = "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL) DAY2",
                            metaImprint = "11.08 SUN",
                            meta = "Kアリーナ横浜 · 17:00",
                            seed = Sample.gakuen,
                            countdown = ImasTicketCountdown("38")
                        )
                    },
                    ImasTicketStackItem("3", "11.28 SAT · CG 15th ANNIVERSARY PARTY!!!! · 58 DAYS") {
                        ImasTicket(
                            label = "参加予定",
                            title = "CINDERELLA GIRLS 15th ANNIVERSARY PARTY!!!! DAY1",
                            metaImprint = "11.28 SAT",
                            meta = "Kアリーナ横浜 · 17:00",
                            seed = Sample.cg,
                            countdown = ImasTicketCountdown("58")
                        )
                    }
                )
            )
        }
        ImasSection("アイドル詳細の頭", style = Small) {
            ImasIdolHeader(
                imprint = "765PRO ALLSTARS",
                name = "天海春香",
                isPick = pick,
                onImprintTap = {},
                subtitle = "あまみ はるか · CV 中村繪里子",
                seed = Sample.haruka,
                iconLabel = "春香",
                onTogglePick = { pick = !pick },
                stats = listOf(
                    ImasBoardCell("189", "出演", "公演"),
                    ImasBoardCell("42", "歌唱した曲", "曲"),
                    ImasBoardCell("12", "一緒に参加", "公演")
                ),
                iconAccessory = { ImasIconBadge(Icons.Filled.PhotoCamera, label = "写真を選ぶ", seed = Sample.haruka) }
            )
        }
        ImasSection("アイドルの名札", style = Small) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasIdolGrid {
                    ImasIdolCell("天海春香", seed = Sample.haruka, iconLabel = "春香", isPick = true, metric = "158cm")
                    ImasIdolCell("如月千早", seed = Sample.chihaya, iconLabel = "千早", metric = "162cm")
                    ImasIdolCell("星井美希", seed = Sample.miki, iconLabel = "美希", metric = "161cm")
                    ImasIdolCell("菊地真", seed = Sample.makoto, iconLabel = "真", metric = "157cm")
                }
                ImasIdolGrid {
                    ImasIdolCell("高槻やよい", kana = "たかつきやよい", seed = Sample.yayoi, iconLabel = "やよい", isSelected = true)
                    ImasIdolCell("速水奏", kana = "はやみかなで", seed = Sample.kanade, iconLabel = "奏", isSelected = false)
                }
            }
        }
        ImasSection("ブランドを選ぶ", style = Small) {
            ImasBrandPicker(options = brandOptions, selection = brands, onSelectionChange = { brands = it })
        }
        ImasSection("ユニットの名札", style = Small, footer = "登録画像があれば画像、無ければブランド色 + 人の集まりの記号。") {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose), verticalAlignment = Alignment.Top) {
                ImasUnitAvatar(Sample.unit, size = 52.dp)
                ImasUnitCell(Sample.unit, Modifier.width(120.dp), metric = "タグ 3 個一致")
            }
        }
        ImasSection("日付の印", style = Small, footer = "月カレンダー・週ビューの日の枠。当日=塗り、選択日(当日以外)=線。") {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                listOf(Triple(true, false, "7"), Triple(false, true, "12"), Triple(false, false, "20")).forEach { (today, selected, day) ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        ImasDateMark(isToday = today, isSelected = selected)
                        ImasText(day, ImasTextRole.META)
                    }
                }
            }
        }
        ImasSection("写真の角の印", style = Small, footer = "写真サムネイルの角の小さな印。地の色に関わらず読めるよう半透明の黒 + 白。") {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                Box(
                    Modifier
                        .size(72.dp)
                        .background(DS.fill, RoundedCornerShape(DS.rArtwork(72.dp)))
                ) {
                    ImasMediaBadge(Icons.Filled.Star, Modifier.align(Alignment.BottomEnd), accessibilityLabel = "アイコンに設定中")
                }
                Box(
                    Modifier
                        .size(72.dp)
                        .background(DS.fill, RoundedCornerShape(DS.rArtwork(72.dp)))
                ) {
                    ImasMediaBadge(Icons.Filled.VisibilityOff, Modifier.align(Alignment.BottomEnd), label = "対象外")
                }
            }
        }
    }
}

// MARK: - 申込書

private enum class How { VENUE, STREAM, VIEWING }
private enum class Mode { NORMAL, HARD, ENDLESS }

@Composable
private fun ApplicationFormPage() {
    var how by remember { mutableStateOf(How.VENUE) }
    var mode by remember { mutableStateOf(Mode.NORMAL) }
    var questionCount by remember { mutableIntStateOf(20) }
    var seat by remember { mutableStateOf("1階 C列 24番") }
    var price by remember { mutableStateOf<Int?>(9900) }
    var notify by remember { mutableStateOf(true) }
    var memo by remember { mutableStateOf("") }
    var reply by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("htps://example") }
    var tagText by remember { mutableStateOf("") }
    var tags by remember { mutableStateOf(listOf("ソロ曲好き", "初参戦")) }
    ImasFormPage(scrollState = rememberCatalogScrollState()) {
        ImasTicket(label = "DAY2", imprint = "09.23 WED", title = "学園アイドルマスター LIVE TOUR -標- 岩手公演", seed = Sample.gakuen)
        ImasSection("参加のしかた (横に並ぶ札: grid)", style = Small) {
            ImasChoiceCards(
                choices = listOf(
                    ImasChoice(How.VENUE, "現地", Icons.Filled.Chair),
                    ImasChoice(How.STREAM, "配信", Icons.Filled.Sensors),
                    ImasChoice(How.VIEWING, "LV", Icons.Filled.Movie)
                ),
                selection = how,
                onSelect = { how = it }
            )
        }
        ImasSection("遊び方 (縦に積む行: row)", style = Small) {
            ImasChoiceCards(
                choices = listOf(
                    ImasChoice(Mode.NORMAL, "ノーマル", Icons.Filled.MusicNote, "よく流れる曲だけ出題"),
                    ImasChoice(Mode.HARD, "ハード", Icons.AutoMirrored.Filled.QueueMusic, "登録曲すべてから出題"),
                    ImasChoice(Mode.ENDLESS, "エンドレス", Icons.Filled.AllInclusive, "正解し続ける限り続く")
                ),
                selection = mode,
                onSelect = { mode = it },
                style = ImasChoiceCardsStyle.ROW
            )
        }
        ImasSection("問題数 (数字だけの札: numeral)", style = Small) {
            ImasChoiceCards(
                choices = listOf(ImasChoice(10, "10", subtitle = "問"), ImasChoice(20, "20", subtitle = "問"), ImasChoice(30, "30", subtitle = "問")),
                selection = questionCount,
                onSelect = { questionCount = it },
                style = ImasChoiceCardsStyle.NUMERAL
            )
        }
        ImasFormCard {
            ImasFormTextField("席", seat, { seat = it }, imprint = "SEAT", icon = Icons.Filled.Chair)
            ImasFormAmount("チケット代", price, { price = it }, note = "一般 指定席")
            ImasFormLink("会場", "トーサイクラシックホール岩手", {}, imprint = "VENUE", icon = Icons.Filled.Place)
            ImasFormTextField(
                "特設ページ",
                url,
                { url = it },
                imprint = "URL",
                icon = Icons.Filled.Link,
                error = "URL の形になっていません",
                keyboardType = KeyboardType.Uri
            )
            ImasFormToggle("通知", "開演 1 時間前に知らせる", notify, { notify = it }, imprint = "NOTIFY", icon = Icons.Outlined.Notifications)
            ImasFormTextArea("メモ", memo, { memo = it }, prompt = "座席・同行者・感想など")
        }
        ImasSection("返信 (開いたら自動でキーボードを出す: autofocus)", style = Small) {
            ImasFormCard {
                ImasFormTextArea(
                    "返信",
                    reply,
                    { reply = it },
                    prompt = "コメントへの返信",
                    imprint = "REPLY",
                    icon = Icons.AutoMirrored.Filled.Reply,
                    autofocus = true
                )
            }
        }
        ImasSection("マイタグ", style = Small, footer = "押すと増える、手元だけのタグ。") {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasChipFlow {
                    tags.forEach { tag -> ImasRemovableChip(tag, onRemove = { tags = tags - tag }) }
                }
                ImasChipInputField(
                    text = tagText,
                    onTextChange = { tagText = it },
                    prompt = "マイタグを追加",
                    submitAccessibilityLabel = "マイタグを追加",
                    onSubmit = {
                        if (tagText.isNotEmpty()) {
                            tags = tags + tagText
                            tagText = ""
                        }
                    }
                )
            }
        }
        ImasNote("チケット代は収支に入ります。この端末にだけ保存されます。")
        ImasButton("この記録を削除", {}, icon = Icons.Filled.Delete, role = ImasButtonRole.DESTRUCTIVE, size = ImasButtonSize.LARGE)
    }
}

// MARK: - ボタン

@Composable
private fun ButtonsPage() {
    CatalogPage {
        ImasSection("主ボタン (大)", style = Small, footer = "画面で一番大事な操作。1 画面に 1 つ。色は墨で、アイドルの画面でも変えない。") {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasButton("はじめる", {}, size = ImasButtonSize.LARGE)
                ImasThemeProvider(seed = Sample.gakuen) {
                    ImasButton("セトリを予想", {}, icon = Icons.Filled.AutoAwesome, size = ImasButtonSize.LARGE)
                }
            }
        }
        ImasSection("役割", style = Small) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                RoleRow()
                ImasThemeProvider(seed = Sample.haruka) { RoleRow() }
            }
        }
        ImasSection("大きさ", style = Small) {
            ImasThemeProvider(seed = Sample.chihaya) {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                    ImasButton("大 50", {}, size = ImasButtonSize.LARGE, fillsWidth = false)
                    ImasButton("中 40", {}, size = ImasButtonSize.MEDIUM)
                    ImasButton("小 32", {}, size = ImasButtonSize.SMALL)
                }
            }
        }
        ImasSection("状態", style = Small) {
            ImasThemeProvider(seed = Sample.saki) {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                    ImasButton("保存", {}, role = ImasButtonRole.PRIMARY, enabled = false)
                    ImasButton("送信", {}, role = ImasButtonRole.PRIMARY, isLoading = true)
                    ImasButton("予想する", {}, icon = Icons.Outlined.ThumbUp, role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL)
                }
            }
        }
        ImasSection("記号のボタン", style = Small) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose), verticalAlignment = Alignment.CenterVertically) {
                ImasIconButton(Icons.Filled.KeyboardArrowLeft, "前の月", {}, size = ImasIconButtonSize.REGULAR)
                ImasIconButton(Icons.Filled.KeyboardArrowRight, "次の月", {}, size = ImasIconButtonSize.SMALL)
                ImasThemeProvider(seed = Sample.haruka) {
                    ImasIconButton(Icons.Filled.PlayArrow, "再生", {}, style = ImasIconButtonStyle.FILLED)
                }
                ImasIconButton(Icons.Filled.MoreHoriz, "その他", {}, style = ImasIconButtonStyle.PLAIN)
                ImasIconButton(Icons.Filled.Delete, "削除中", {}, style = ImasIconButtonStyle.FILLED, isLoading = true)
            }
        }
    }
}

@Composable
private fun RoleRow() {
    Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        ImasButton("主", {}, role = ImasButtonRole.PRIMARY)
        ImasButton("副", {}, role = ImasButtonRole.SECONDARY)
        ImasButton("文字", {}, role = ImasButtonRole.PLAIN)
        ImasButton("削除", {}, role = ImasButtonRole.DESTRUCTIVE)
    }
}

// MARK: - チップ・札・数字

@Composable
private fun ChipsPage() {
    var brand by remember { mutableStateOf("765as") }
    var picked by remember { mutableStateOf(setOf("haruka", "miki")) }
    CatalogPage {
        ImasSection("絞り込み (押すと切り替わる)", style = Small) {
            ImasChipFlow {
                ImasFilterChip("すべて", brand == "all", { brand = "all" })
                ImasFilterChip("765AS", brand == "765as", { brand = "765as" }, seed = Sample.as765, leading = ImasChipLeading.Dot)
                ImasFilterChip("デレマス", brand == "cg", { brand = "cg" }, seed = Sample.cg, leading = ImasChipLeading.Dot)
                ImasFilterChip("ミリオン", brand == "ml", { brand = "ml" }, seed = Sample.ml, leading = ImasChipLeading.Dot)
                ImasFilterChip("学マス", brand == "gakuen", { brand = "gakuen" }, seed = Sample.gakuen, leading = ImasChipLeading.Dot)
            }
        }
        ImasSection("歌唱メンバーの予想 (写真が無ければ判子)", style = Small) {
            ImasChipFlow {
                listOf(
                    listOf("haruka", "天海春香", "春香", Sample.haruka),
                    listOf("chihaya", "如月千早", "千早", Sample.chihaya),
                    listOf("miki", "星井美希", "美希", Sample.miki),
                    listOf("makoto", "菊地真", "真", Sample.makoto),
                    listOf("yayoi", "高槻やよい", "やよい", Sample.yayoi)
                ).forEach { (id, name, short, color) ->
                    ImasFilterChip(
                        name,
                        id in picked,
                        { picked = if (id in picked) picked - id else picked + id },
                        seed = color,
                        leading = ImasChipLeading.Avatar(label = short)
                    )
                }
            }
        }
        ImasSection("効いている絞り込み・情報の札", style = Small) {
            ImasChipFlow {
                ImasRemovableChip("765AS", {}, seed = Sample.as765)
                ImasRemovableChip("ソロ曲", {})
                ImasChip("全体曲")
                ImasChip("765AS", style = ImasChipStyle.THEMED, seed = Sample.as765)
                ImasAwardChip("夏に聴きたい曲", 1)
            }
        }
        ImasSection("状態の札 (押せない)", style = Small) {
            ImasChipFlow {
                ImasBadge("ユニット", kind = ImasBadgeKind.UNIT, seed = Sample.chihaya)
                ImasBadge("全員", kind = ImasBadgeKind.ALL)
                ImasBadge("カバー", kind = ImasBadgeKind.COVER)
                ImasBadge("一部", kind = ImasBadgeKind.PARTIAL)
                ImasBadge("主演", kind = ImasBadgeKind.LEAD, seed = Sample.haruka)
                ImasBadge("ゲスト", kind = ImasBadgeKind.GUEST)
                ImasBadge("参加済", kind = ImasBadgeKind.POSITIVE, icon = Icons.Filled.Check)
                ImasBadge("受付中", kind = ImasBadgeKind.ATTENTION)
                ImasBadge("落選", kind = ImasBadgeKind.NEGATIVE)
                ImasBadge("LV", kind = ImasBadgeKind.NEUTRAL)
                ImasBadge("NEW", kind = ImasBadgeKind.NEW, seed = Sample.saki)
                ImasBadge("12", kind = ImasBadgeKind.THEMED, icon = Icons.Filled.Sell, seed = Sample.ml)
            }
        }
        ImasSection(
            "数字",
            style = Small,
            footer = "MICRO (8sp) は枠の高さが決まっていて文字を詰め込むしかない場所専用 (月カレンダーの単日バー・あふれ件数など)。"
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                ImasMetric("89", Modifier.alignByBaseline(), unit = "回", size = ImasNumeralSize.LARGE)
                ImasThemeProvider(seed = Sample.haruka) {
                    ImasMetric("42", Modifier.alignByBaseline(), unit = "%", size = ImasNumeralSize.MEDIUM, emphasized = true)
                }
                ImasMetric("2,051", Modifier.alignByBaseline(), unit = "件", size = ImasNumeralSize.SMALL)
                Box(
                    Modifier
                        .alignByBaseline()
                        .sizeIn(minWidth = 18.dp, minHeight = 14.dp)
                        .background(DS.fill, RoundedCornerShape(3.dp))
                        .padding(horizontal = 4.dp),
                    contentAlignment = Alignment.Center
                ) {
                    ImasText("+12", ImasTextRole.MICRO)
                }
            }
        }
        ImasSection("1 段で横スクロール (続きは端を透かす: fades)", style = Small) {
            ImasChipRow(fades = true) {
                listOf("すべて", "765AS", "シンデレラ", "ミリオン", "SideM", "シャニ", "学マス", "ALSTREAM", "シャッフル").forEach { text ->
                    ImasFilterChip(text, text == "すべて", {})
                }
            }
        }
    }
}

// MARK: - 行 (実体)

@Composable
private fun EntityRowsPage() {
    CatalogPage {
        ImasSection("曲", count = "3曲") {
            ImasCardList(style = ImasCardListStyle.PLAIN) {
                ImasRow(
                    title = "THE IDOLM@STER",
                    subtitle = "765PRO ALLSTARS",
                    leading = ImasRowLeading.Artwork("THE IDOLM@STER", seed = Sample.as765, imageUrl = Sample.Art.idolmaster),
                    trailing = ImasRowTrailing.Metric("89", "回", emphasized = true)
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight), verticalAlignment = Alignment.CenterVertically) {
                        ImasText("2005年7月26日", ImasTextRole.META)
                        ImasBadge("回収 3", kind = ImasBadgeKind.POSITIVE, icon = Icons.Filled.Check)
                    }
                }
                ImasRow(
                    title = "Thank You!",
                    subtitle = "MILLIONSTARS",
                    leading = ImasRowLeading.Artwork("Thank You!", seed = Sample.ml, imageUrl = Sample.Art.thankYou),
                    trailing = ImasRowTrailing.Metric("74", "回", emphasized = true),
                    position = ImasRowPosition.FOLLOWING
                )
                ImasRow(
                    title = "お願い！シンデレラ",
                    subtitle = "CINDERELLA GIRLS",
                    leading = ImasRowLeading.Artwork("お願い！シンデレラ", seed = Sample.cg, imageUrl = Sample.Art.onegai),
                    trailing = ImasRowTrailing.Metric("120", "回", emphasized = true),
                    position = ImasRowPosition.FOLLOWING
                )
            }
        }
        ImasSection("アイドル") {
            ImasCardList(style = ImasCardListStyle.PLAIN) {
                ImasRow(
                    title = "天海春香",
                    subtitle = "765AS · CV 中村繪里子",
                    leading = ImasRowLeading.Avatar("春香", seed = Sample.haruka, isPick = true),
                    trailing = ImasRowTrailing.Badge("担当", ImasBadgeKind.LEAD)
                )
                ImasRow(
                    title = "如月千早",
                    subtitle = "765AS · CV 今井麻美",
                    leading = ImasRowLeading.Avatar("千早", seed = Sample.chihaya),
                    position = ImasRowPosition.FOLLOWING
                )
            }
        }
        ImasSection("歌唱者のアイコン", style = Small, footer = "写真があれば写真、無ければ判子。入り切らない人数は +N。") {
            ImasAvatarStack(
                people = listOf(
                    ImasPerformer("a", "天海春香", Sample.haruka, iconLabel = "春香"),
                    ImasPerformer("b", "如月千早", Sample.chihaya, iconLabel = "千早"),
                    ImasPerformer("c", "星井美希", Sample.miki, iconLabel = "美希"),
                    ImasPerformer("d", "菊地真", Sample.makoto, iconLabel = "真"),
                    ImasPerformer("e", "高槻やよい", Sample.yayoi, iconLabel = "やよい"),
                    ImasPerformer("f", "萩原雪歩", "#D3DDE9", iconLabel = "雪歩")
                ),
                maxVisible = 4,
                size = 26.dp
            )
        }
        ImasSection("ライブ・公演") {
            ImasCardList(style = ImasCardListStyle.PLAIN) {
                ImasRow(
                    title = "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)",
                    subtitle = "11月7日(土)〜8日(日) · Kアリーナ横浜",
                    leading = ImasRowLeading.Bar(seed = Sample.gakuen),
                    trailing = ImasRowTrailing.Chevron
                ) {
                    ImasBadge("参加予定", kind = ImasBadgeKind.ATTENTION)
                }
                ImasRow(
                    title = "M@STERS OF IDOL WORLD 2025",
                    subtitle = "2025年12月13日(土)〜14日(日) · 京セラドーム大阪",
                    leading = ImasRowLeading.Bar(rainbow = true),
                    trailing = ImasRowTrailing.Chevron,
                    emphasis = ImasRowEmphasis.DIMMED,
                    position = ImasRowPosition.FOLLOWING
                )
            }
        }
        ImasSection("ジャケの格子 (アルバム・シリーズ)", style = Small) {
            ImasGridLayout(columns = 3, spacing = DS.Space.gap) {
                ImasArtworkCell("THE IDOLM@STER", subtitle = "2005年7月26日", seed = Sample.as765, imageUrl = Sample.Art.idolmaster)
                ImasArtworkCell("READY!!", subtitle = "2008年2月27日", seed = Sample.as765, imageUrl = Sample.Art.ready)
                ImasArtworkCell("ジャケ未登録のシリーズ", seed = Sample.ml, fallbackIcon = Icons.Filled.Layers)
            }
        }
        ImasSection("記録 (編集履歴・お知らせ)", style = Small, footer = "先頭は種類ごとの記号 (地は敷かない)。自由な中身 (diff 本文など) は detail で足す。") {
            ImasCardList {
                ImasRecordRow(
                    "「THE IDOLM@STER」の歌唱者を直した",
                    icon = Icons.Filled.Edit,
                    tone = ImasIconTileTone.THEMED,
                    subtitle = "よ〜だ · 3分前",
                    badges = listOf(ImasBadgeSpec("変更", ImasBadgeKind.NEUTRAL))
                ) {
                    ImasText("歌唱者: 5人 → 6人", ImasTextRole.NOTE)
                }
                Following {
                    ImasRecordRow(
                        "「お願い！シンデレラ」の追加を差し戻した",
                        icon = Icons.AutoMirrored.Filled.Undo,
                        tone = ImasIconTileTone.NEGATIVE,
                        subtitle = "fuga · 1時間前",
                        badges = listOf(ImasBadgeSpec("差し戻し", ImasBadgeKind.NEGATIVE))
                    )
                    ImasRecordRow(
                        "天海春香のプロフィールが直された",
                        leading = ImasRowLeading.Avatar("春香", seed = Sample.haruka),
                        subtitle = "よ〜だ · 昨日",
                        badges = listOf(ImasBadgeSpec("変更", ImasBadgeKind.NEUTRAL))
                    )
                }
            }
        }
    }
}

// MARK: - 行 (項目・入口・選択)

@Composable
private fun ValueRowsPage() {
    var notify by remember { mutableStateOf(true) }
    var selected by remember { mutableStateOf(setOf(0)) }
    var scope by remember { mutableStateOf("現地のみ") }
    var count by remember { mutableIntStateOf(10) }
    var pick by remember { mutableStateOf(true) }
    var favorite by remember { mutableStateOf(false) }
    var owned by remember { mutableStateOf(true) }
    var query by remember { mutableStateOf("") }
    var expanded by remember { mutableStateOf(true) }
    fun toggle(i: Int) {
        selected = if (i in selected) selected - i else selected + i
    }
    CatalogPage {
        ImasSection("選ぶ・設定する行", style = Small, footer = "選べる行は行のどこを押しても切り替わる。値を選ぶ行はその場にメニューが出る。") {
            ImasCardList {
                ImasSelectableRow("天海春香", 0 in selected, { toggle(0) }, subtitle = "765PRO ALLSTARS", seed = Sample.haruka)
                ImasSelectableRow(
                    "READY!!",
                    1 in selected,
                    { toggle(1) },
                    leading = ImasRowLeading.Artwork("READY!!", imageUrl = Sample.Art.ready),
                    position = ImasRowPosition.FOLLOWING
                )
                ImasMenuRow(
                    "回収に数える",
                    listOf("現地のみ", "現地と配信"),
                    scope,
                    { scope = it },
                    { it },
                    icon = Icons.Outlined.Verified,
                    position = ImasRowPosition.FOLLOWING
                )
                ImasStepperRow(
                    "問題数",
                    count,
                    { count = it },
                    5..30,
                    icon = Icons.Filled.Tag,
                    step = 5,
                    unit = "問",
                    position = ImasRowPosition.FOLLOWING
                )
            }
        }
        ImasSection("行の末尾の印", style = Small) {
            ImasThemeProvider(seed = Sample.haruka) {
                ImasCardList {
                    ImasRow(
                        title = "天海春香",
                        subtitle = "あまみ はるか",
                        leading = ImasRowLeading.Avatar("春香", seed = Sample.haruka),
                        trailing = ImasRowTrailing.Mark(ImasMarkKind.PICK, pick) { pick = !pick }
                    )
                    ImasRow(
                        title = "READY!!",
                        leading = ImasRowLeading.Artwork("READY!!", imageUrl = Sample.Art.ready),
                        trailing = ImasRowTrailing.Mark(ImasMarkKind.FAVORITE, favorite) { favorite = !favorite },
                        position = ImasRowPosition.FOLLOWING
                    )
                    ImasRow(
                        title = "KAMISABI SR 「THE IDOLM@STER」",
                        leading = ImasRowLeading.Icon(Icons.Filled.Style, tone = ImasIconTileTone.THEMED),
                        trailing = ImasRowTrailing.Mark(ImasMarkKind.OWNED, owned) { owned = !owned },
                        position = ImasRowPosition.FOLLOWING
                    )
                }
            }
        }
        ImasSection("開閉トグルの行", style = Small, footer = "押すたびに矢印が回転する。中身の開閉は呼び出し側が isExpanded を見て出し分ける。") {
            ImasCardList {
                ImasDisclosureRow("個別衣装", expanded, { expanded = !expanded }, count = "4着")
                if (expanded) {
                    ImasChipFlow(
                        Modifier
                            .padding(horizontal = DS.Space.rowH)
                            .padding(bottom = DS.Space.gap)
                    ) {
                        ImasChip("制服")
                        ImasChip("ライブ衣装")
                        ImasChip("私服")
                        ImasChip("サンタ衣装")
                    }
                }
            }
        }
        ImasSection("一覧の頭", style = Small) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                    ImasToolbarButton(Icons.Filled.Settings, "設定", {})
                    ImasSearchField("曲名・歌詞・アイドル", query, { query = it }, Modifier.weight(1f))
                    ImasToolbarButton(Icons.Filled.FilterList, "絞り込み", {}, badge = 2)
                }
                ImasDateHeader("11", imprint = "NOV 2026 · 4 公演")
                ImasDateHeader("09", imprint = "SEP 2026 · 終わった", isPast = true)
            }
        }
        ImasSection("項目と値", style = Small) {
            ImasThemeProvider(seed = Sample.as765) {
                ImasCardList {
                    ImasValueRow("よみ", "あいどるますたー")
                    ImasValueRow("ブランド", "765AS", isLink = true, position = ImasRowPosition.FOLLOWING)
                    ImasValueRow("キャパ", "55,000人", monospaced = true, position = ImasRowPosition.FOLLOWING)
                }
            }
        }
        ImasSection("入口・設定", style = Small) {
            ImasCardList {
                ImasNavRow("デフォルトブランド", icon = Icons.Filled.GridView, value = "すべて", onClick = {})
                ImasNavRow("使い方を見る", icon = Icons.AutoMirrored.Outlined.HelpOutline, position = ImasRowPosition.FOLLOWING, onClick = {})
                ImasToggleRow(
                    "ライブ名を省略表示",
                    notify,
                    { notify = it },
                    subtitle = "「THE IDOLM@STER」を省いて短く出す",
                    position = ImasRowPosition.FOLLOWING
                )
                ImasActionRow("曲を追加", {}, icon = Icons.Filled.Add, position = ImasRowPosition.FOLLOWING)
                ImasActionRow("このライブを削除", {}, kind = ImasActionRowKind.DESTRUCTIVE, position = ImasRowPosition.FOLLOWING)
            }
        }
        ImasSection("選ぶ (複数・1 つ)", style = Small) {
            ImasCardList {
                listOf("天海春香", "如月千早", "星井美希").forEachIndexed { i, name ->
                    ImasRow(
                        title = name,
                        modifier = Modifier.imasRowPress { toggle(i) },
                        leading = ImasRowLeading.Selection(i in selected),
                        density = ImasRowDensity.COMPACT,
                        position = if (i == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                    )
                }
                ImasRow(
                    title = "京セラドーム大阪",
                    subtitle = "大阪府",
                    leading = ImasRowLeading.Selection(true, single = true),
                    density = ImasRowDensity.COMPACT,
                    position = ImasRowPosition.FOLLOWING
                )
            }
        }
    }
}

// MARK: - 区画・面・お知らせ

@Composable
private fun SectionsPage() {
    CatalogPage {
        ImasSection("区画の見出し (大)", count = "42曲", seeAll = {}) {
            ImasCard { ImasText("カードの中身。行でない中身 (説明・グラフ・プレビュー) を 1 枚にまとめる。", ImasTextRole.BODY) }
        }
        ImasSection("区画の見出し (文脈アクション)", actionTitle = "＋ タグ", actionIcon = Icons.Filled.Add, onAction = {}) {
            ImasCard {
                ImasText("「すべて見る」(別画面へ) とは見え方が違う。その場で何かを始める操作のときに使い、同時には出さない。", ImasTextRole.BODY)
            }
        }
        ImasSection("区画の見出し (小)", style = Small, footer = "補足文は区画の下に灰色で置き、囲まない。") {
            ImasCard {
                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                    ImasText("次の出演", ImasTextRole.EYEBROW)
                    ImasText("15th ANNIVERSARY PARTY!!!! ~ for your ONE ~", ImasTextRole.CARD_TITLE)
                    ImasCard(style = ImasCardStyle.INSET) { ImasText("カードの中の囲み (inset)", ImasTextRole.NOTE) }
                }
            }
        }
        ImasSection("行のまとまり (面)", style = Small) {
            ImasCardList {
                ImasNavRow("クイズ・ゲーム", icon = Icons.Filled.SportsEsports, onClick = {})
                ImasNavRow("みんなの投票", icon = Icons.Filled.Poll, position = ImasRowPosition.FOLLOWING, onClick = {})
            }
        }
        ImasSection("お知らせの帯", style = Small) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasNotice(ImasNoticeKind.WARNING, "出題に必要な 10 曲に届いていません。ブランドを増やしてください。", title = "候補が足りません")
                ImasNotice(ImasNoticeKind.ERROR, "タグを読み込めませんでした。", actionTitle = "もう一度", onAction = {})
                ImasNotice(ImasNoticeKind.SUCCESS, "コールガイドを保存しました。")
                ImasNotice(ImasNoticeKind.INFO, "5 分前時点の情報です。")
                ImasNotice(ImasNoticeKind.INFO, "オフラインです。記録はこの端末に保存され、次につながったときに同期します。", icon = Icons.Filled.WifiOff)
            }
        }
        ImasSection(
            "提案バー",
            style = Small,
            footer = "一覧の絞り込み結果から、その場限りの単発の提案を 1 本の全幅バーで出す。恒常的な入口は ImasEntryCard、読まないと困る注意は ImasNotice。"
        ) {
            Column(
                Modifier.clip(RoundedCornerShape(DS.rCard)),
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
            ) {
                ImasSuggestionBar(
                    Icons.Filled.AutoAwesome,
                    "この 12 曲でイントロドンを始める",
                    {},
                    detail = "12曲",
                    style = ImasSuggestionBarStyle.PROMINENT,
                    showsChevron = true
                )
                ImasSuggestionBar(Icons.Filled.AutoAwesome, "あと 4 曲必要です", {}, style = ImasSuggestionBarStyle.PROMINENT, isEnabled = false)
                ImasSuggestionBar(Icons.Filled.SwapVert, "披露回数順に並べ替える", {}, style = ImasSuggestionBarStyle.SUBTLE, onDismiss = {})
            }
        }
    }
}

// MARK: - 詳細の頭

/** 詳細の画面の地 (紙面のスクロール)。頭は端まで、本文は左右に余白。 */
@Composable
private fun DetailPage(seed: String, content: @Composable ColumnScope.() -> Unit) {
    ImasThemeProvider(seed = seed) {
        CompositionLocalProvider(LocalImasBackdrop provides ImasBackdrop.PAPER) {
            Column(
                Modifier
                    .fillMaxSize()
                    .background(DS.paper)
                    .verticalScroll(rememberCatalogScrollState()),
                content = content
            )
        }
    }
}

@Composable
private fun SongHeroPage() {
    var tab by remember { mutableIntStateOf(0) }
    var favorite by remember { mutableStateOf(false) }
    var previewing by remember { mutableStateOf(false) }
    DetailPage(Sample.as765) {
        ImasHero(
            title = "THE IDOLM@STER",
            layout = ImasHeroLayout.CENTERED,
            eyebrow = "765PRO ALLSTARS",
            onEyebrowTap = {},
            subtitle = "天海春香 / 如月千早 / 星井美希 / 菊地真 / 高槻やよい",
            primary = ImasHeroAction("Apple Music で再生", Icons.Filled.PlayArrow) {},
            facts = {
                ImasBadge("全体曲", kind = ImasBadgeKind.ALL)
                ImasBadge("2005年7月26日", kind = ImasBadgeKind.NEUTRAL)
            }
        ) {
            ImasArtwork("THE IDOLM@STER", size = 200.dp, imageUrl = Sample.Art.idolmaster)
        }
        ImasMarkBar(
            Modifier
                .padding(horizontal = DS.Space.screen)
                .padding(bottom = DS.Space.section)
        ) {
            ImasMarkTile(if (favorite) Icons.Filled.Star else Icons.Filled.StarBorder, "お気に入り", favorite, { favorite = !favorite })
            ImasMarkTile(Icons.AutoMirrored.Outlined.Notes, "メモ", false, {})
            ImasMarkTile(Icons.Filled.Verified, "習熟度", true, {})
        }
        ImasTabs(
            labels = listOf("情報・歌唱", "歌詞", "披露履歴", "コミュニティ"),
            selection = tab,
            onSelect = { tab = it },
            modifier = Modifier.padding(horizontal = DS.Space.screen)
        )
        Column(
            Modifier
                .padding(horizontal = DS.Space.screen)
                .padding(top = DS.Space.card, bottom = DS.Space.section)
                .imasTabSwipe(tab, listOf(0, 1, 2, 3)) { tab = it },
            verticalArrangement = Arrangement.spacedBy(DS.Space.section)
        ) {
            ImasStatGrid(columns = 3) {
                ImasStatTile(Icons.Filled.Mic, "89", "披露", unit = "回")
                ImasStatTile(Icons.Filled.Verified, "3", "現地で回収", unit = "公演", tappable = true)
                ImasStatTile(Icons.Filled.CalendarMonth, "2005", "初披露", unit = "年")
            }
            ImasSection("ジャケの状態", style = Small, footer = "画像が無ければブランド色の面 + 曲名。試聴の音源を渡すと再生/停止が乗る。") {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                    ImasArtwork("THE IDOLM@STER", size = 64.dp, imageUrl = Sample.Art.idolmaster)
                    ImasArtwork("ジャケ未登録の曲", seed = Sample.ml, size = 64.dp)
                    ImasArtwork(
                        "READY!!",
                        size = 64.dp,
                        imageUrl = Sample.Art.ready,
                        previewUrl = "https://example.com/preview.m4a",
                        isPreviewing = previewing,
                        onPreview = { previewing = !previewing }
                    )
                }
            }
            ImasSection("最近の披露", count = "89回") {
                ImasCardList(style = ImasCardListStyle.PLAIN) {
                    ImasRow(
                        title = "M@STERS OF IDOL WORLD 2025",
                        subtitle = "12月13日(土) · 京セラドーム大阪",
                        leading = ImasRowLeading.Bar(rainbow = true),
                        trailing = ImasRowTrailing.Value("M24"),
                        density = ImasRowDensity.COMPACT
                    )
                    ImasRow(
                        title = "765PRO ALLSTARS LIVE 20th",
                        subtitle = "7月26日(土) · 横浜アリーナ",
                        leading = ImasRowLeading.Bar(seed = Sample.as765),
                        trailing = ImasRowTrailing.Value("M01"),
                        density = ImasRowDensity.COMPACT,
                        position = ImasRowPosition.FOLLOWING
                    )
                }
            }
        }
    }
}

@Composable
private fun IdolHeroPage(surface: ImasHeroSurface) {
    var tab by remember { mutableIntStateOf(0) }
    var pick by remember { mutableStateOf(true) }
    DetailPage(Sample.haruka) {
        ImasHero(
            title = "天海春香",
            layout = ImasHeroLayout.LEADING,
            surface = surface,
            eyebrow = "765PRO ALLSTARS",
            subtitle = "あまみ はるか · CV 中村繪里子",
            primary = ImasHeroAction("出演ライブ", Icons.Filled.Mic) {}
        ) {
            // アイドルのアイコンはいつも出す (写真が無ければ判子)。
            ImasAvatar(label = "春香", seed = Sample.haruka, size = 72.dp, isPick = pick)
        }
        ImasMarkBar(
            Modifier
                .padding(horizontal = DS.Space.screen)
                .padding(top = if (surface == ImasHeroSurface.COLOR) DS.Space.card else 0.dp)
                .padding(bottom = DS.Space.section)
        ) {
            ImasMarkTile(if (pick) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, "担当", pick, { pick = !pick })
            ImasMarkTile(Icons.Filled.StarBorder, "お気に入り", false, {})
            ImasMarkTile(Icons.AutoMirrored.Outlined.Notes, "メモ", false, {})
        }
        ImasTabs(
            labels = listOf("ライブ", "楽曲", "プロフィール", "コミュニティ"),
            selection = tab,
            onSelect = { tab = it },
            modifier = Modifier.padding(horizontal = DS.Space.screen)
        )
        Column(
            Modifier
                .padding(horizontal = DS.Space.screen)
                .padding(top = DS.Space.card, bottom = DS.Space.section)
                .imasTabSwipe(tab, listOf(0, 1, 2, 3)) { tab = it },
            verticalArrangement = Arrangement.spacedBy(DS.Space.section)
        ) {
            ImasFeatureCard(
                title = "15th ANNIVERSARY PARTY!!!! ~ for your ONE ~",
                eyebrow = "次の出演",
                subtitle = "11月28日(土) · Kアリーナ横浜 · DAY1",
                seed = Sample.haruka,
                metric = ImasFeatureMetric("58", prefix = "あと", unit = "日"),
                onOpen = {}
            )
            ImasStatGrid(columns = 3) {
                ImasStatTile(Icons.Filled.Mic, "189", "出演", unit = "公演")
                ImasStatTile(Icons.Filled.MusicNote, "42", "歌唱した曲", unit = "曲")
                ImasStatTile(Icons.Filled.People, "12", "一緒に参加", unit = "公演", tappable = true)
            }
            ImasSection("ライブ歌唱曲", count = "42曲", seeAll = {}) {
                ImasCardList(style = ImasCardListStyle.PLAIN) {
                    listOf(
                        Triple("THE IDOLM@STER", Sample.Art.idolmaster, "71"),
                        Triple("READY!!", Sample.Art.ready, "56"),
                        Triple("太陽のジェラシー", Sample.Art.jealousy, "48")
                    ).forEachIndexed { i, (title, art, n) ->
                        ImasRow(
                            title = title,
                            leading = ImasRowLeading.Artwork(title, seed = Sample.as765, imageUrl = art),
                            trailing = ImasRowTrailing.Metric(n, "回", emphasized = true),
                            density = ImasRowDensity.COMPACT,
                            position = if (i == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                        )
                    }
                }
            }
        }
    }
}

// MARK: - ハブ

@Composable
private fun HubPage(oshiSurface: ImasFeatureSurface) {
    CatalogPage {
        ImasFeatureCard(
            title = "花海咲季",
            eyebrow = "担当",
            subtitle = "学マス · CV 長月あおい",
            seed = Sample.saki,
            surface = oshiSurface,
            onOpen = {}
        )
        ImasFeatureCard(
            title = "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)",
            eyebrow = "参加予定",
            subtitle = "11月7日(土) · DAY1",
            seed = Sample.gakuen,
            metric = ImasFeatureMetric("37", prefix = "あと", unit = "日"),
            primary = ImasFeatureAction("セトリを予想する", Icons.Filled.AutoAwesome) {},
            secondary = ImasFeatureAction("コールを見る", Icons.Filled.Celebration) {}
        )
        ImasFeatureCard(
            title = "お化け屋敷に一緒に行きたいアイドルは？",
            eyebrow = "お題",
            subtitle = "42票 · 21候補",
            metric = ImasFeatureMetric("28", prefix = "あと", unit = "日"),
            primary = ImasFeatureAction("投票する", Icons.Outlined.ThumbUp) {},
            secondary = ImasFeatureAction("ほかのお題", Icons.AutoMirrored.Filled.List) {}
        )
        ImasShortcutGroup("あそぶ") {
            ImasShortcutTile(Icons.Filled.PlayArrow, "つづきから", detail = "歌詞クイズ Q.02", seed = Sample.saki, onClick = {})
            ImasShortcutTile(Icons.AutoMirrored.Filled.QueueMusic, "イントロドン", seed = Sample.saki, onClick = {})
            ImasShortcutTile(Icons.Filled.FormatQuote, "歌詞クイズ", seed = Sample.saki, onClick = {})
            ImasShortcutTile(Icons.Filled.SportsEsports, "すべてのゲーム", seed = Sample.saki, onClick = {})
        }
        ImasSection("あなたの記録") {
            ImasStatGrid(columns = 4) {
                ImasStatTile(Icons.Filled.Mic, "24", "参加ライブ", seed = Sample.saki, tappable = true)
                ImasStatTile(Icons.Filled.AutoAwesome, "3", "予想", seed = Sample.saki, tappable = true)
                ImasStatTile(Icons.Filled.Star, "112", "お気に入り", seed = Sample.saki, tappable = true)
                ImasStatTile(Icons.Filled.EditNote, "12", "投稿", seed = Sample.saki, tappable = true)
                ImasStatTile(Icons.Filled.Poll, "5", "投票", seed = Sample.saki, tappable = true)
                ImasStatTile(Icons.Filled.MusicNote, "39", "回収", seed = Sample.saki, tappable = true)
                ImasStatTile(Icons.Filled.BarChart, "18", "習熟度", seed = Sample.saki, tappable = true)
                ImasStatTile(Icons.Filled.CurrencyYen, "¥184,300", "収支", seed = Sample.saki, tappable = true)
            }
        }
    }
}

// MARK: - 状態・メーター

@Composable
private fun FeedbackPage() {
    val sys = DS.sys
    CatalogPage {
        ImasCard {
            ImasEmptyState(
                ImasEmptyStateKind.EMPTY,
                title = "まだ参加したライブがありません",
                message = "ライブの一覧で右に引くと参加を付けられます。",
                actionTitle = "ライブを見る",
                onAction = {}
            )
        }
        ImasCard {
            ImasEmptyState(
                ImasEmptyStateKind.NO_RESULTS,
                title = "見つかりません",
                message = "「春香」に合う曲はありません。",
                actionTitle = "絞り込みを解除",
                onAction = {}
            )
        }
        ImasSignInPrompt(message = "セトリ予想の投票にはログインが必要です")
        ImasSection("画面全体の読み込み中", style = Small) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.card)) {
                ImasCard(Modifier.weight(1f)) { ImasLoadingState(Modifier.height(100.dp)) }
                ImasCard(Modifier.weight(1f)) { ImasLoadingState(Modifier.height(100.dp), title = "読み込み中…") }
            }
        }
        ImasSection(
            "メーター (習熟度・進み具合)",
            style = Small,
            footer = "ImasLevelCell は段階のマス (色は呼び出し側のドメインが決める)。ImasProgressBar はラベル無しの線 (対戦の進み具合・つづきからの達成率)。"
        ) {
            ImasCard {
                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        repeat(10) { i ->
                            ImasLevelCell(i.toUByte(), 10.toUByte()) { level, steps ->
                                sys.copy(alpha = 0.35f + 0.65f * level.toFloat() / steps.toFloat())
                            }
                        }
                    }
                    ImasProgressBar(0.42, seed = Sample.saki)
                }
            }
        }
        ImasSection("割合", style = Small) {
            ImasCard {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.card), verticalAlignment = Alignment.CenterVertically) {
                    ImasProgressRing(0.39, seed = Sample.kanade)
                    Column(Modifier.weight(1f)) {
                        val pad = PaddingValues(vertical = DS.Space.gapTight)
                        ImasStatBar("765AS", "7/446", 1.6, seed = Sample.as765, contentPadding = pad)
                        ImasStatBar("ミリオン", "31/1,075", 2.9, seed = Sample.ml, contentPadding = pad)
                        ImasStatBar("学マス", "60/125", 48.0, seed = Sample.gakuen, contentPadding = pad)
                    }
                }
            }
        }
    }
}

// MARK: - セトリと予想

@Composable
private fun SetlistPage() {
    var voted by remember { mutableStateOf(setOf(1)) }
    var previewingSetlist by remember { mutableStateOf(false) }
    fun toggle(i: Int) {
        voted = if (i in voted) voted - i else voted + i
    }
    CatalogPage {
        ImasSection("セトリ", count = "24曲", footer = "紙に入れて切り取り線で区切る。歌唱者はアイコンを重ねる (写真か判子)。回収は事実の札 (初回収)。") {
            ImasCardList(style = ImasCardListStyle.SHEET) {
                ImasSetlistRow(
                    number = "01",
                    title = "THE IDOLM@STER",
                    artworkUrl = Sample.Art.idolmaster,
                    seed = Sample.as765,
                    performers = listOf(
                        ImasPerformer("a", "天海春香", Sample.haruka, iconLabel = "春香"),
                        ImasPerformer("b", "如月千早", Sample.chihaya, iconLabel = "千早"),
                        ImasPerformer("c", "星井美希", Sample.miki, iconLabel = "美希"),
                        ImasPerformer("d", "菊地真", Sample.makoto, iconLabel = "真"),
                        ImasPerformer("e", "高槻やよい", Sample.yayoi, iconLabel = "やよい"),
                        ImasPerformer("f", "萩原雪歩", "#D3DDE9", iconLabel = "雪歩"),
                        ImasPerformer("g", "水瀬伊織", "#FD99E1", iconLabel = "伊織")
                    ),
                    badges = listOf(ImasBadgeSpec("全体", ImasBadgeKind.ALL)),
                    facts = listOf("初披露", "初回収"),
                    onSelectPerformers = {},
                    highlightsPick = true,
                    trailing = ImasRowTrailing.Custom { ImasLikeButton(isOn = true, count = 42, onClick = {}) }
                )
                ImasSetlistRow(
                    number = "02",
                    title = "READY!!",
                    seed = Sample.as765,
                    customArtwork = {
                        ImasArtwork(
                            "READY!!",
                            size = 44.dp,
                            imageUrl = Sample.Art.ready,
                            previewUrl = "https://example.com/preview.m4a",
                            isPreviewing = previewingSetlist,
                            onPreview = { previewingSetlist = !previewingSetlist }
                        )
                    },
                    performers = listOf(ImasPerformer("b", "如月千早", Sample.chihaya, iconLabel = "千早")),
                    badges = listOf(ImasBadgeSpec("ソロ", ImasBadgeKind.UNIT)),
                    facts = listOf("12 回目"),
                    trailing = ImasRowTrailing.Custom { ImasLikeButton(isOn = false, count = 0, onClick = {}) },
                    position = ImasRowPosition.FOLLOWING
                )
                ImasSetlistRow(
                    number = "03",
                    title = "Thank You!",
                    artworkUrl = Sample.Art.thankYou,
                    seed = Sample.ml,
                    performers = (0 until 13).map { ImasPerformer("m$it", "", listOf(Sample.ml, Sample.shizuka, Sample.kotoha)[it % 3]) },
                    performerSummary = "MILLIONSTARS 13 人",
                    badges = listOf(ImasBadgeSpec("カバー", ImasBadgeKind.COVER)),
                    facts = listOf("未回収"),
                    trailing = ImasRowTrailing.Custom { ImasLikeButton(isOn = false, count = 3, onClick = {}, isBusy = true) },
                    position = ImasRowPosition.FOLLOWING
                )
                ImasSetlistRow(
                    number = "04",
                    title = "ジャケの無い曲",
                    seed = Sample.ml,
                    performers = listOf(ImasPerformer("d", "田中琴葉", Sample.kotoha)),
                    noteGroups = listOf(
                        SetlistRowNoteGroupRecord(
                            "披露",
                            listOf(SetlistRowNoteRecord("3回目", RowNoteTone.VALUE), SetlistRowNoteRecord("1年ぶり", RowNoteTone.DETAIL))
                        ),
                        SetlistRowNoteGroupRecord("回収", listOf(SetlistRowNoteRecord("未回収", RowNoteTone.MISSING)))
                    ),
                    note = "この公演だけアレンジ違い",
                    position = ImasRowPosition.FOLLOWING
                )
            }
        }
        ImasSection("機械予測", footer = "過去のセトリと出演者から計算した確率です。") {
            ImasThemeProvider(seed = Sample.gakuen) {
                ImasCardList(style = ImasCardListStyle.PLAIN) {
                    ImasForecastRow(
                        rank = 1,
                        title = "標",
                        measure = ImasForecastMeasure.Probability(0.82),
                        artworkUrl = Sample.Art.shirube,
                        reasonLabel = "オリメン",
                        performers = listOf(
                            ImasPerformer("s", "花海咲季", Sample.saki),
                            ImasPerformer("t", "月村手毬", "#3D5BA8"),
                            ImasPerformer("k", "藤田ことね", "#F5C900", isAbsent = true)
                        )
                    )
                    ImasForecastRow(
                        rank = 2,
                        title = "Fighting My Way",
                        measure = ImasForecastMeasure.Probability(0.64),
                        subtitle = "ソロ曲",
                        artworkUrl = Sample.Art.fightingMyWay,
                        reasonLabel = "理由",
                        reason = "ソロの代表曲"
                    )
                }
            }
        }
        ImasSection("みんなの予想", count = "11票") {
            ImasThemeProvider(seed = Sample.gakuen) {
                ImasCardList(style = ImasCardListStyle.PLAIN) {
                    ImasForecastRow(
                        rank = 1,
                        title = "標",
                        measure = ImasForecastMeasure.Votes(5, 1.0),
                        artworkUrl = Sample.Art.shirube,
                        isMine = 1 in voted,
                        onVote = { toggle(1) }
                    )
                    ImasForecastRow(
                        rank = 2,
                        title = "初",
                        measure = ImasForecastMeasure.Votes(3, 0.6),
                        artworkUrl = Sample.Art.hajime,
                        isMine = 2 in voted,
                        onVote = { toggle(2) }
                    )
                    ImasForecastRow(
                        rank = 3,
                        title = "太陽のジェラシー",
                        measure = ImasForecastMeasure.Votes(2, 0.4),
                        artworkUrl = Sample.Art.jealousy,
                        onVote = {},
                        voteDisabled = true
                    )
                    ImasForecastRow(
                        rank = 4,
                        title = "Fighting My Way",
                        measure = ImasForecastMeasure.Votes(1, 0.2),
                        artworkUrl = Sample.Art.fightingMyWay,
                        onVote = {},
                        isVoteLoading = true
                    )
                    ImasForecastRow(
                        rank = 5,
                        title = "次に新ユニット曲が出るなら",
                        measure = ImasForecastMeasure.Votes(1, 0.2),
                        unit = Sample.unit,
                        onVote = {}
                    )
                    ImasForecastRow(
                        rank = 6,
                        title = "天海春香",
                        measure = ImasForecastMeasure.Votes(1, 0.2),
                        avatar = ImasForecastAvatar(label = "春香", seed = Sample.haruka),
                        showsProportionLine = false,
                        onVote = {},
                        voteLabel = "投票する",
                        votedLabel = "投票した"
                    )
                }
            }
        }
    }
}

// MARK: - 一覧の型

private enum class SortOrder(val label: String) { RELEASE("リリース日順"), PERFORMANCES("披露回数順") }

@Composable
private fun ListTemplatePage() {
    var sort by remember { mutableStateOf(SortOrder.PERFORMANCES) }
    var ascending by remember { mutableStateOf(false) }
    var filters by remember { mutableStateOf(listOf("765AS", "全体曲")) }
    var previewingSong by remember { mutableStateOf(false) }
    ImasListBackdrop(Modifier.fillMaxSize()) {
        Column(Modifier.verticalScroll(rememberCatalogScrollState())) {
            ImasFilterBar(
                items = filters.map { f ->
                    ImasFilterBarItem(f, f, seed = if (f == "765AS") Sample.as765 else null) { filters = filters - f }
                },
                onClearAll = { filters = emptyList() }
            )
            ImasListSummary(
                count = 2051,
                unit = "件",
                sortOptions = SortOrder.entries,
                sortSelection = sort,
                onSortChange = { sort = it },
                sortLabel = { it.label },
                sortAscending = ascending,
                onSortAscendingChange = { ascending = it }
            )
            ImasListSection("2005年") {
                ImasSongRow(
                    title = "THE IDOLM@STER",
                    subtitle = "765PRO ALLSTARS",
                    artworkUrl = Sample.Art.idolmaster,
                    seed = Sample.as765,
                    showsBrandBar = true,
                    previewUrl = "https://example.com/preview.m4a",
                    isPreviewing = previewingSong,
                    onPreviewTap = { previewingSong = !previewingSong },
                    trailing = ImasRowTrailing.Metric("89", "回", emphasized = true)
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight), verticalAlignment = Alignment.CenterVertically) {
                        ImasText("7月26日", ImasTextRole.META)
                        ImasBadge("回収 3", kind = ImasBadgeKind.POSITIVE, icon = Icons.Filled.Check)
                    }
                }
                ImasSongRow(
                    title = "ジャケ未登録の曲",
                    subtitle = "765PRO ALLSTARS",
                    seed = Sample.as765,
                    showsBrandBar = true,
                    trailing = ImasRowTrailing.Metric("56", "回", emphasized = true)
                )
            }
            ImasListSection("ライブ") {
                ImasShowRow(
                    "2025-12-13",
                    "DAY1",
                    subtitle = "京セラドーム大阪 · 17:00 開演",
                    seed = Sample.as765,
                    badges = listOf(ImasBadgeSpec("参加", ImasBadgeKind.POSITIVE))
                )
                ImasShowRow("2025-12-14", "DAY2", subtitle = "京セラドーム大阪 · 16:00 開演", seed = Sample.as765)
            }
        }
    }
}

// MARK: - 編集シートの型

private enum class SavingDemo { SPINNER, PROGRESS }

@Composable
private fun FormTemplatePage() {
    var name by remember { mutableStateOf("LIVE TOUR -標-") }
    var url by remember { mutableStateOf("htps://example") }
    var memo by remember { mutableStateOf("") }
    var notify by remember { mutableStateOf(true) }
    var confirmDelete by remember { mutableStateOf(false) }
    var toolbarKind by remember { mutableIntStateOf(0) }
    var savingDemo by remember { mutableStateOf<SavingDemo?>(null) }
    LaunchedEffect(savingDemo) {
        if (savingDemo != null) {
            delay(1500)
            savingDemo = null
        }
    }
    val kind = when (toolbarKind) {
        0 -> ImasSheetToolbarKind.Edit(canSave = true, onCancel = {}, onSave = {})
        1 -> ImasSheetToolbarKind.Submit(canSubmit = true, isSubmitting = false, onCancel = {}, onSubmit = {})
        2 -> ImasSheetToolbarKind.Select(canFinish = true, onCancel = {}, onFinish = {})
        3 -> ImasSheetToolbarKind.Read(onClose = {})
        else -> ImasSheetToolbarKind.Prompt(canRecord = true, onLater = {}, onRecord = {})
    }
    Box(Modifier.fillMaxSize()) {
        ImasFormBackdrop(Modifier.fillMaxSize()) {
            Column {
                ImasSheetToolbar(kind, title = "ライブを編集")
                Column(Modifier.verticalScroll(rememberCatalogScrollState())) {
                    ImasListSection(
                        "ツールバーの種類 (見本切り替え)",
                        footer = "編集=キャンセル/保存、送信=キャンセル/送信、選択=キャンセル/完了、閲覧=閉じる、後で=あとで/記録する。"
                    ) {
                        ImasSegmented(
                            labels = listOf("編集", "送信", "選択", "閲覧", "後で"),
                            selection = toolbarKind,
                            onSelect = { toolbarKind = it },
                            modifier = Modifier.padding(DS.Space.gap)
                        )
                    }
                    ImasListSection("基本") {
                        ImasTextFieldRow("ライブ名", name, { name = it })
                        ImasTextFieldRow("特設ページ", url, { url = it }, error = "URL の形になっていません")
                        ImasToggleRow("開演前に知らせる", notify, { notify = it }, subtitle = "開演 1 時間前に通知します")
                    }
                    ImasListSection("メモ", footer = "メモはこの端末にだけ保存されます。") {
                        ImasTextAreaRow(memo, { memo = it }, prompt = "座席・同行者・感想など", limit = 400)
                    }
                    ImasListSection("保存中のオーバーレイ (見本。触ると 1.5 秒で消える)") {
                        ImasActionRow("保存中 (くるくる) を試す", { savingDemo = SavingDemo.SPINNER }, icon = Icons.Filled.Replay)
                        ImasActionRow("送信中 (進み具合) を試す", { savingDemo = SavingDemo.PROGRESS }, icon = Icons.Filled.ArrowUpward)
                    }
                    ImasListSection {
                        ImasActionRow("このライブを削除", { confirmDelete = true }, kind = ImasActionRowKind.DESTRUCTIVE)
                    }
                }
            }
        }
        ImasSavingOverlay(
            isSaving = savingDemo != null,
            label = if (savingDemo == SavingDemo.PROGRESS) "送信中" else "保存中",
            progress = if (savingDemo == SavingDemo.PROGRESS) 0.6 else null
        )
    }
    ImasConfirmDestructive(
        "このライブを削除しますか？",
        isPresented = confirmDelete,
        onDismiss = { confirmDelete = false },
        onConfirm = {},
        message = "公演とセトリもいっしょに削除されます。"
    )
}

// MARK: - ゲームの設定・読みもの

@Composable
private fun SetupPage() {
    CatalogPage {
        ImasSetupHeader(Icons.Filled.LibraryMusic, "歌詞クイズ", message = "歌詞の一節から曲名を当てます。")
        ImasCandidateCount(7, minimum = 10)
        ImasCandidateCount(null, minimum = 10, isLoading = true, loadingText = "候補を計算中…")
        ImasCandidateCount(null, minimum = 10, note = "読み込みに失敗しました")
        ImasNotice(ImasNoticeKind.WARNING, "出題に必要な 10 曲に届いていません。ブランドを増やしてください。", title = "候補が足りません")
        ImasSection("習熟度", style = Small) {
            ImasCard {
                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                    ImasText("覚えた", ImasTextRole.ROW_TITLE)
                    ImasThemeProvider(seed = Sample.chihaya) { ImasMeter(7, 10) }
                }
            }
        }
        ImasSection("使い方 (写真・図解を添えた手順)", style = Small) {
            ImasCard {
                ImasStepList(
                    listOf(
                        ImasStep("ホーム画面を長押しする", "アイコンが揺れたら左上の ＋ を押します。"),
                        ImasStep("「アイドルライブDB」を探す"),
                        ImasStep("担当画像を選ぶ", "ウィジェットを長押しして編集します。") {
                            ImasArtwork("担当画像の見本", size = 120.dp, imageUrl = Sample.Art.idolmaster)
                        }
                    )
                )
            }
        }
        ImasSection("できること (番号の無い列挙)", style = Small) {
            ImasCard {
                ImasPointList(
                    listOf(
                        ImasPoint(Icons.Outlined.Verified, "現地で聴いた曲を記録する"),
                        ImasPoint(Icons.Outlined.BarChart, "ブランドごとの回収率を見る"),
                        ImasPoint(Icons.Filled.AutoAwesome, "次のセトリをみんなで予想する")
                    )
                )
            }
        }
        ImasButton("はじめる", {}, size = ImasButtonSize.LARGE)
    }
}

// MARK: - コミュニティ (タグ・記録)

@Composable
private fun CommunityPage() {
    var tagColor by remember { mutableStateOf("#FF8C42") }
    CatalogPage {
        ImasSection("タグ詳細の頭", style = Small) {
            ImasCard {
                ImasTagHeaderCard("夏に聴きたい曲", colorHex = "#FF8C42", categoryLabel = "雰囲気", description = "海・花火・浴衣が似合う曲。")
            }
        }
        ImasSection("タグ詳細の頭 (説明なし・色なし)", style = Small) {
            ImasCard { ImasTagHeaderCard("ソロ曲好き", categoryLabel = "好み") }
        }
        ImasSection("タグの色を選ぶ", style = Small) {
            ImasCard { ImasColorPicker(selectedHex = tagColor, onSelect = { tagColor = it }) }
        }
        ImasSection("色そのものを見せる丸", style = Small, footer = "タグの色・ペンライトの色そのもの (導出を通さない数少ない部品)。読み上げは色名。") {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose), verticalAlignment = Alignment.CenterVertically) {
                ImasSwatch("#FF6B6B", size = ImasSwatchSize.DOT)
                ImasSwatch("#4D96FF", size = ImasSwatchSize.SMALL)
                ImasSwatch("#1DD1A1", size = ImasSwatchSize.LARGE, isSelected = true)
                ImasSwatch("#9B5DE5", size = ImasSwatchSize.LARGE)
            }
        }
        ImasSection(
            "順位の小さい札 (文中に差し込む)",
            style = Small,
            footer = "行の先頭いっぱいに置く大きな順位は ImasRankNumber。こちらは名前と同じ行に添える小さい版。"
        ) {
            ImasCard {
                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                    listOf(Triple(1, "天海春香", "42票"), Triple(12, "萩原雪歩", "3票")).forEach { (rank, name, votes) ->
                        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                            ImasRankBadge(rank)
                            ImasText(name, ImasTextRole.ROW_TITLE, modifier = Modifier.weight(1f))
                            ImasText(votes, ImasTextRole.META)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AI チャット

@Composable
private fun ChatPage() {
    CatalogPage {
        ImasNotice(
            ImasNoticeKind.INFO,
            "AI チャット (ChatGPT 連携・キャラとのトーク) の画面は Android にまだ無いので、吹き出し・入力欄 " +
                "(iOS の ImasChatBubble・ImasChatComposer・ImasChatToolChip) は写していない。機能を Android に持ってくるときに写す。",
            title = "Android には無い部品"
        )
    }
}

// MARK: - あそぶ (ステージ)

@Composable
private fun StagePage() {
    var playing by remember { mutableStateOf(false) }
    CompositionLocalProvider(LocalImasBackdrop provides ImasBackdrop.PAPER) {
        Column(
            Modifier
                .fillMaxSize()
                .background(DS.paper)
                .verticalScroll(rememberCatalogScrollState())
                .padding(top = DS.Space.gapLoose, bottom = DS.Space.section),
            verticalArrangement = Arrangement.spacedBy(DS.Space.section)
        ) {
            Column(Modifier.padding(horizontal = DS.Space.screen), verticalArrangement = Arrangement.spacedBy(DS.Space.section)) {
                ImasSection(
                    "表彰台・対戦の結果",
                    style = Small,
                    footer = "ImasPodium・ImasVersusBadge・imasAccentCard は地が紙面のまま (QS の固定色は使わない)。ソートメーカー・ティアー表の結果で使う。"
                ) {
                    ImasPodium(
                        listOf(
                            ImasPodiumEntry("1", 1, "天海春香", seed = Sample.haruka, visual = {
                                ImasAvatar(label = "春香", seed = Sample.haruka, size = 64.dp)
                            }, onClick = {}),
                            ImasPodiumEntry("2", 2, "如月千早", seed = Sample.chihaya, visual = {
                                ImasAvatar(label = "千早", seed = Sample.chihaya, size = 52.dp)
                            }, onClick = {}),
                            ImasPodiumEntry("3", 3, "星井美希", seed = Sample.miki, visual = {
                                ImasAvatar(label = "美希", seed = Sample.miki, size = 52.dp)
                            }, onClick = {})
                        )
                    )
                }
                ImasSection("対戦カードの間・選べるカードの縁", style = Small) {
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            ImasAvatar(label = "春香", seed = Sample.haruka, size = 44.dp)
                            ImasVersusBadge()
                            ImasAvatar(label = "千早", seed = Sample.chihaya, size = 44.dp)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                            Column(
                                Modifier
                                    .weight(1f)
                                    .imasAccentCard(seed = Sample.haruka, isSelected = true, style = ImasAccentCardStyle.CARD)
                                    .padding(vertical = DS.Space.gap),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                ImasText("対戦相手", ImasTextRole.ROW_LABEL)
                                ImasText("765AS", ImasTextRole.META)
                            }
                            Box(
                                Modifier
                                    .imasAccentCard(seed = Sample.gakuen, isSelected = false, style = ImasAccentCardStyle.CHIP)
                                    .heightIn(min = DS.Size.chip)
                                    .padding(horizontal = 12.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                ImasText("学マス", ImasTextRole.CHIP)
                            }
                        }
                    }
                }
                ImasSection(
                    "ハブからステージへの入口",
                    style = Small,
                    footer = "ImasStageWordmark・ImasStagePreviewCard は QS の固定色のまま、明るい一覧に埋め込む窓。"
                ) {
                    ImasStagePreviewCard {
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            ImasStageWordmark("Q")
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text("QUIZ STAGE", style = QS.mono(11), color = QS.dim)
                                Text("歌詞クイズ Q.04 / 10", style = QS.text(13, FontWeight.Bold), color = QS.ink)
                            }
                        }
                    }
                }
            }
            ImasAlwaysDark {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(QS.bg)
                        .padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp)
                ) {
                    StageLabel("メンバーカラークイズ")
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        ImasStageColorSwatch("#E54B4D", Modifier.weight(1f), letter = "A", isSelected = true, onClick = {})
                        ImasStageColorSwatch("#3A8EE6", Modifier.weight(1f), letter = "B", onClick = {})
                        ImasStageColorSwatch("#7A5AE0", Modifier.weight(1f), letter = "C", isEliminated = true, onClick = {})
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        ImasStageColorSwatch("#F2C12E", Modifier.width(56.dp), style = ImasStageColorSwatchStyle.PALETTE)
                        ImasStageColorSwatch("#3FB27F", Modifier.width(56.dp), style = ImasStageColorSwatchStyle.PALETTE, isUsed = true)
                        ImasStageAssignmentTarget(assignedHex = null)
                        ImasStageAssignmentTarget(assignedHex = "#E54B4D", verdict = true)
                        ImasStageAssignmentTarget(assignedHex = "#3A8EE6", verdict = false)
                        ImasStageColorGridIcon()
                    }

                    StageLabel("再生中の表示・案内行")
                    ImasStageEqualizer(columns = 20, rows = 4, dotSize = 8.dp)
                    ImasStageInfoRow(Icons.Filled.Info, "正解すると次の問題に進みます", detail = "残り 12 問", showsChevron = true, onClick = {})
                    ImasStageInfoRow(Icons.Filled.Replay, "次の問題を読み込み中", isLoading = true)

                    StageLabel("判定カード")
                    ImasStagePartialVerdictCard(number = 4, isPerfect = true, headline = "全員正解！", score = 120)
                    ImasStagePartialVerdictCard(number = 5, isPerfect = false, headline = "2 / 3 正解", score = 60)

                    StageLabel("再生・操作のボタン")
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        ImasStageIconTileButton(Icons.Filled.Replay, "もう一度", {}, Modifier.weight(1f))
                        ImasStagePlaybackControl(isPlaying = false, onTap = {}, onHoldBegin = {}, onHoldEnd = {}, modifier = Modifier.weight(1f))
                        ImasStagePlaybackControl(isPlaying = true, onTap = {}, onHoldBegin = {}, onHoldEnd = {}, modifier = Modifier.weight(1f))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
                        ImasStagePlaybackControl(
                            isPlaying = playing,
                            onTap = { playing = !playing },
                            onHoldBegin = { playing = true },
                            onHoldEnd = { playing = false },
                            style = ImasStagePlaybackStyle.CIRCLE
                        )
                        ImasStageCircleButton("!", 88.dp, {})
                    }

                    StageLabel("進捗・数・達成")
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        ImasStageProgressBar(0.6)
                        ImasStageProgressBar(0.92, isUrgent = true)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        ImasStageStatTile("SCORE", Modifier.weight(1f)) {
                            Text("820", style = QS.num(26))
                        }
                        ImasStageStatTile(
                            "ハイスコア",
                            Modifier.weight(1f),
                            trailing = { ImasStageBadgeStamp("自己ベスト更新", detail = "700 → 755") }
                        ) {
                            Text("755", style = QS.num(26))
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                        ImasStageScoreChip(Sample.haruka, "春香P", 420)
                        ImasStageScoreChip(Sample.chihaya, "千早P", 380)
                    }

                    StageLabel("聴取中・判定中・正誤")
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        ImasStagePenlightBars(listOf(hexToColor(Sample.haruka), hexToColor(Sample.chihaya), hexToColor(Sample.miki)))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            ImasStagePulse()
                            Text("聴取中", style = QS.text(12, FontWeight.SemiBold), color = QS.dim)
                        }
                    }
                    ImasStagePanel {
                        Text("判定中…", style = QS.text(13, FontWeight.Bold), color = QS.ink)
                    }
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .height(110.dp),
                        horizontalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        ImasStageRushFlash(isCorrect = true)
                        ImasStageRushFlash(isCorrect = false)
                    }

                    StageLabel("1 対 1 対戦の結果")
                    Box(Modifier.height(260.dp)) {
                        ImasStageVersusResult(
                            winnerColorHex = Sample.haruka,
                            headline = "春香P の勝ち！",
                            players = ImasStageVersusPlayer("春香P", Sample.haruka, 820) to ImasStageVersusPlayer("千早P", Sample.chihaya, 640)
                        ) {
                            ImasStageIconTileButton(Icons.Filled.Replay, "もう一度", {})
                            ImasStageIconTileButton(Icons.Filled.Share, "シェア", {})
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StageLabel(text: String) {
    Text(text, style = QS.text(12, FontWeight.Bold), color = QS.dim)
}

// MARK: - 指の操作・そのほか (Android の見本)

@Composable
private fun ExtrasPage() {
    var segment by remember { mutableIntStateOf(0) }
    var tab by remember { mutableIntStateOf(0) }
    var nameFilter by remember { mutableStateOf("") }
    var tray by remember { mutableStateOf(listOf("天海春香", "如月千早", "星井美希")) }
    var attended by remember { mutableStateOf(setOf<Int>()) }
    var favorites by remember { mutableStateOf(setOf<Int>()) }
    CatalogPage {
        ImasSection(
            "行を引く操作",
            style = Small,
            footer = "右に引く = 記録を付ける (1 つなら引き切りで実行)。左に引く = 手元に置く・削除。行の中ほどから引く。読み上げでは行の「操作」から選べる。"
        ) {
            ImasCardList {
                listOf("THE IDOLM@STER", "READY!!", "太陽のジェラシー").forEachIndexed { i, title ->
                    ImasSwipe(
                        leading = listOf(
                            ImasSwipeAction(
                                if (i in attended) ImasSwipeKind.UNDO else ImasSwipeKind.ATTEND,
                                if (i in attended) "取り消す" else "参加した"
                            ) { attended = if (i in attended) attended - i else attended + i }
                        ),
                        trailing = listOf(
                            ImasSwipeAction(ImasSwipeKind.FAVORITE, if (i in favorites) "外す" else "お気に入り") {
                                favorites = if (i in favorites) favorites - i else favorites + i
                            },
                            ImasSwipeAction(ImasSwipeKind.DELETE, "削除") {}
                        )
                    ) {
                        ImasRow(
                            title = title,
                            leading = ImasRowLeading.Artwork(title, seed = Sample.as765),
                            trailing = when {
                                i in attended -> ImasRowTrailing.Badge("参加", ImasBadgeKind.POSITIVE, icon = Icons.Filled.Check)
                                i in favorites -> ImasRowTrailing.Badge("お気に入り", ImasBadgeKind.NEUTRAL, icon = Icons.Filled.Star)
                                else -> ImasRowTrailing.None
                            },
                            density = ImasRowDensity.COMPACT,
                            position = if (i == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                        )
                    }
                }
            }
        }
        ImasSection("タブと横に払う操作", style = Small, footer = "下の面を横に払うとタブが隣へ移る (縦のスクロールは邪魔しない)。") {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasTabs(labels = listOf("セットリスト", "予想", "コール"), selection = tab, onSelect = { tab = it }, seed = Sample.saki)
                ImasCard(Modifier.imasTabSwipe(tab, listOf(0, 1, 2)) { tab = it }) {
                    ImasText(listOf("セットリストの中身", "予想の中身", "コールの中身")[tab], ImasTextRole.BODY)
                }
            }
        }
        ImasSection("値を 1 つ選ぶ", style = Small) {
            ImasSegmented(labels = listOf("1か月", "半年", "1年", "すべて"), selection = segment, onSelect = { segment = it })
        }
        ImasSection("フィルタシートの頭の帯", style = Small, footer = "リセットはこの帯にだけ置く。条件が無いときは押せない。") {
            Box(
                Modifier
                    .clip(RoundedCornerShape(DS.rCard))
                    .background(DS.surface)
            ) {
                ImasFilterSheetToolbar(canReset = false, onReset = {}, onApply = {})
            }
        }
        ImasSection("名前で絞り込む欄", style = Small) {
            ImasNameFilterField("アイドル名で絞り込み", nameFilter, { nameFilter = it })
        }
        ImasSection("選んだものの帯", style = Small) {
            ImasSelectionTray(tray, { it }, { removed -> tray = tray - removed })
        }
        ImasSection("小さなくるくる", style = Small) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                ImasInlineSpinner()
                ImasText("送信中", ImasTextRole.NOTE)
            }
        }
    }
}
