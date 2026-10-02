package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Vocab
import com.fugaif.imaslivedb.ui.components.ImasBrandPicker
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * イベント種別 (events.kind) の値と語。並び・語はコアの vocabulary (最後が「その他」)。
 * 知らない種別は「その他」として扱う (コアの event_kind。Q-08l)。
 */
val EVENT_KINDS: List<Pair<String, String>>
    get() = Vocab.table.eventKinds.map { it.value to it.shortLabel }

fun eventKindLabel(kind: String): String = Vocab.eventKind(kind)?.shortLabel ?: kind

/**
 * 催しの性格 (events.event_type) の語。コアの vocabulary。
 *
 * 配信があったかどうかは**この軸ではない** (shows.stream_platform が持つ)。
 * 未分類 (空文字) と語彙外は null。画面は「種別を出さない」で扱う。
 */
fun eventTypeLabel(eventType: String): String? = Vocab.eventType(eventType)?.shortLabel

/** 参加状態フィルタの値。コアの EventFilterCriteria.attendanceFilter がそのまま受ける文字列。 */
private val ATTENDANCE_OPTIONS = listOf("all" to "すべて", "attended" to "参加済み", "not_attended" to "未参加")

/**
 * ライブ一覧のフィルタシート (iOS `EventFilterSheet` の移植)。見た目は DesignSystem の
 * `ImasFilterSheetToolbar` (リセット・適用) + `ImasListSection` の区画。
 *
 * 曲一覧のフィルタシートと同じ作り: 編集中の値はローカル状態に持ち、「適用」でまとめて返す。
 * 会場だけは候補が 244 件あって専用ピッカー ([VenuePickerSheet]) を持つので、
 * このシートには入れず一覧側のチップに残してある。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventFilterSheet(
    brands: List<Brand>,
    currentBrandIds: Set<String>,
    currentExcludedKinds: Set<String>,
    currentAttendanceFilter: String,
    currentRequireFavorite: Boolean,
    currentRequireNote: Boolean,
    currentShowEmptyEvents: Boolean,
    currentHideStreaming: Boolean,
    onDismiss: () -> Unit,
    onApply: (
        brandIds: Set<String>,
        excludedKinds: Set<String>,
        attendanceFilter: String,
        requireFavorite: Boolean,
        requireNote: Boolean,
        showEmptyEvents: Boolean,
        hideStreaming: Boolean
    ) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var brandIds by remember { mutableStateOf(currentBrandIds) }
    var excludedKinds by remember { mutableStateOf(currentExcludedKinds) }
    var attendance by remember { mutableStateOf(currentAttendanceFilter) }
    var requireFavorite by remember { mutableStateOf(currentRequireFavorite) }
    var requireNote by remember { mutableStateOf(currentRequireNote) }
    var showEmptyEvents by remember { mutableStateOf(currentShowEmptyEvents) }
    var hideStreaming by remember { mutableStateOf(currentHideStreaming) }

    val hasActiveFilters = brandIds.isNotEmpty() || excludedKinds.isNotEmpty() ||
        attendance != "all" || requireFavorite || requireNote || showEmptyEvents || hideStreaming

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        ImasFormBackdrop(Modifier.fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = DS.sp8)
            ) {
                ImasFilterSheetToolbar(
                    canReset = hasActiveFilters,
                    onReset = {
                        brandIds = emptySet()
                        excludedKinds = emptySet()
                        attendance = "all"
                        requireFavorite = false
                        requireNote = false
                        showEmptyEvents = false
                        hideStreaming = false
                    },
                    onApply = {
                        onApply(
                            brandIds, excludedKinds, attendance,
                            requireFavorite, requireNote, showEmptyEvents, hideStreaming
                        )
                    },
                    title = "フィルター"
                )

                // ブランド (複数選択 = OR。合同ライブは joint_brand_ids 側も見る)
                ImasListSection(title = "ブランド", footer = "複数選択可能") {
                    ImasBrandPicker(
                        brands = brands,
                        selection = brandIds,
                        onSelectionChange = { brandIds = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                    )
                }

                // 種別: チップは「表示する種別」を示す (ON = 表示)。内部では除外集合で持つ。
                // 未知 kind を除外集合に入れないことで、将来 kind が増えても勝手に消えない。
                ImasListSection(
                    title = "種別",
                    footer = if (excludedKinds.isEmpty()) {
                        "全て表示中"
                    } else {
                        "除外: " + excludedKinds.map(::eventKindLabel).sorted().joinToString(" / ")
                    }
                ) {
                    ImasChipFlow(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                    ) {
                        EVENT_KINDS.forEach { (value, label) ->
                            val shown = !excludedKinds.contains(value)
                            ImasFilterChip(
                                label = label,
                                selected = shown,
                                onClick = {
                                    excludedKinds = if (shown) excludedKinds + value else excludedKinds - value
                                }
                            )
                        }
                    }
                }

                // 参加状態
                ImasListSection(title = "参加状態") {
                    ImasSegmented(
                        labels = ATTENDANCE_OPTIONS.map { it.second },
                        selection = ATTENDANCE_OPTIONS.indexOfFirst { it.first == attendance }.coerceAtLeast(0),
                        onSelect = { attendance = ATTENDANCE_OPTIONS[it].first },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                    )
                }

                // マイマーク
                ImasListSection(title = "マイマーク") {
                    ImasToggleRow(title = "お気に入りのみ", isOn = requireFavorite, onCheckedChange = { requireFavorite = it })
                    ImasToggleRow(title = "メモがあるライブのみ", isOn = requireNote, onCheckedChange = { requireNote = it })
                }

                // 表示設定
                ImasListSection(title = "表示設定") {
                    ImasToggleRow(
                        title = "セトリ情報がないライブも表示",
                        subtitle = "公演がまだ登録されていないライブを一覧に出す",
                        isOn = showEmptyEvents,
                        onCheckedChange = { showEmptyEvents = it }
                    )
                    ImasToggleRow(
                        title = "配信を除く",
                        subtitle = "配信・番組だけのイベント (公演として開かれていないもの) を一覧から隠す",
                        isOn = hideStreaming,
                        onCheckedChange = { hideStreaming = it }
                    )
                }
            }
        }
    }
}
