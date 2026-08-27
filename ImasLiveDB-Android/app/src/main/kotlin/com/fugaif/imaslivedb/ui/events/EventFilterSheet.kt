package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor

/**
 * イベント種別 (events.kind) の内部値と表示ラベル。iOS `EventKind` と同じ 5 種。
 *
 * DB の kind は生文字列で、この 5 種以外 ('other' 等) も入っている。コアの
 * `normalize_kind` はそれらを **"live" 扱い**にするので (新しい kind が増えても旧
 * クライアントから消えないためのフォールバック)、「ライブ」を除外すると未知 kind の
 * イベントも一緒に落ちる。iOS と同じ挙動なので揃えてある。
 */
val EVENT_KINDS: List<Pair<String, String>> = listOf(
    "live" to "ライブ",
    "festival" to "フェス",
    "release_event" to "リリイベ",
    "radio" to "ラジオ",
    "stream" to "配信"
)

fun eventKindLabel(kind: String): String = EVENT_KINDS.firstOrNull { it.first == kind }?.second ?: kind

/** 参加状態フィルタの値。コアの EventFilterCriteria.attendanceFilter がそのまま受ける文字列。 */
private val ATTENDANCE_OPTIONS = listOf("all" to "すべて", "attended" to "参加済み", "not_attended" to "未参加")

/**
 * ライブ一覧のフィルタシート (iOS `EventFilterSheet` の移植)。
 *
 * 曲一覧のフィルタシートと同じ作り: 編集中の値はローカル状態に持ち、「適用」でまとめて返す。
 * 会場だけは候補が 244 件あって専用ピッカー ([VenuePickerSheet]) を持つので、
 * このシートには入れず一覧側のチップに残してある。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
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

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 32.dp)
        ) {
            Text(
                text = "フィルター",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )
            HorizontalDivider()

            // ブランド (複数選択 = OR。合同ライブは joint_brand_ids 側も見る)
            SectionLabel("ブランド")
            FlowRow(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ImasFilterChip(label = "全て", selected = brandIds.isEmpty(), onClick = { brandIds = emptySet() })
                brands.forEach { brand ->
                    ImasFilterChip(
                        label = brand.shortName,
                        selected = brandIds.contains(brand.id),
                        tintColor = brandColor(brand.id),
                        onClick = {
                            brandIds = if (brandIds.contains(brand.id)) brandIds - brand.id else brandIds + brand.id
                        }
                    )
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider()

            // 種別: チップは「表示する種別」を示す (ON = 表示)。内部では除外集合で持つ。
            // 未知 kind を除外集合に入れないことで、将来 kind が増えても勝手に消えない。
            SectionLabel("種別")
            FlowRow(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
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
            Text(
                text = if (excludedKinds.isEmpty()) {
                    "全て表示中"
                } else {
                    "除外: " + excludedKinds.map(::eventKindLabel).sorted().joinToString(" / ")
                },
                style = MaterialTheme.typography.bodySmall,
                color = DS.ink3,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )
            HorizontalDivider()

            // 参加状態
            SectionLabel("参加状態")
            ImasSegmented(
                labels = ATTENDANCE_OPTIONS.map { it.second },
                selection = ATTENDANCE_OPTIONS.indexOfFirst { it.first == attendance }.coerceAtLeast(0),
                onSelect = { attendance = ATTENDANCE_OPTIONS[it].first },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider()

            // マイマーク
            SectionLabel("マイマーク")
            SwitchRow(
                title = "お気に入りのみ",
                checked = requireFavorite,
                tint = DS.favorite,
                onCheckedChange = { requireFavorite = it }
            )
            SwitchRow(
                title = "メモがあるライブのみ",
                checked = requireNote,
                tint = DS.warning,
                onCheckedChange = { requireNote = it }
            )
            HorizontalDivider()

            // 表示設定
            SectionLabel("表示設定")
            SwitchRow(
                title = "セトリ情報がないライブも表示",
                subtitle = "公演がまだ登録されていないライブを一覧に出す",
                checked = showEmptyEvents,
                tint = DS.success,
                onCheckedChange = { showEmptyEvents = it }
            )
            SwitchRow(
                title = "配信を除く",
                subtitle = "配信のみのイベント (旧 is_streaming) を一覧から隠す",
                checked = hideStreaming,
                onCheckedChange = { hideStreaming = it }
            )

            HorizontalDivider()
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TextButton(
                    onClick = {
                        brandIds = emptySet()
                        excludedKinds = emptySet()
                        attendance = "all"
                        requireFavorite = false
                        requireNote = false
                        showEmptyEvents = false
                        hideStreaming = false
                    },
                    modifier = Modifier.weight(1f)
                ) { Text("リセット") }
                Button(
                    onClick = {
                        onApply(
                            brandIds, excludedKinds, attendance,
                            requireFavorite, requireNote, showEmptyEvents, hideStreaming
                        )
                    },
                    modifier = Modifier.weight(1f)
                ) { Text("適用") }
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        color = DS.ink2,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
    )
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String? = null,
    checked: Boolean,
    tint: Color? = null,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = MaterialTheme.typography.bodyMedium)
            if (subtitle != null) {
                Text(text = subtitle, style = MaterialTheme.typography.bodySmall, color = DS.ink2)
            }
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = if (tint != null) {
                SwitchDefaults.colors(checkedTrackColor = tint, checkedThumbColor = DS.surface)
            } else {
                SwitchDefaults.colors()
            }
        )
    }
}
