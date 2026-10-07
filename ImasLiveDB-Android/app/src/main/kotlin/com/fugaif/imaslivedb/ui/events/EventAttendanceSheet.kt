package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.local.localWrite
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import kotlinx.coroutines.launch

/**
 * イベントの「参加」を公演 (show) 単位で管理するシート。iOS `EventAttendanceSheet` の移植。
 * 見た目は DesignSystem の `ImasListSection` (区画) + `ImasSelectableRow` (全公演トグル) +
 * `ImasFilterChip` (公演ごとの参加形態)。
 *
 * 参加マークは公演単位 (`entity_type = show` / `kind = attended` / `text_value = 参加形態`) で
 * 持つ。イベント全体に付けてしまうと、行っていない公演まで回収率の対象になってしまう。
 * 形態は複数付けられ (現地 + 配信)、チップを押すたびに付け外しする。最後の 1 つを外すと不参加。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventAttendanceSheet(
    shows: List<Show>,
    seed: String? = null,
    brand: String? = null,
    onDismiss: () -> Unit,
    onChange: () -> Unit
) {
    val context = LocalContext.current
    val marks = remember { AppModule.from(context).userMarkRepository }
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var attendance by remember { mutableStateOf<Map<String, List<AttendanceType>>>(emptyMap()) }

    suspend fun reload() {
        attendance = shows.associate { show -> show.id to marks.attendedTypes(UserMark.SHOW, show.id) }
            .filterValues { it.isNotEmpty() }
    }

    LaunchedEffect(shows) { reload() }

    val allLive = shows.isNotEmpty() && shows.all { attendance[it.id]?.contains(AttendanceType.LIVE) == true }

    fun set(showId: String, type: AttendanceType, on: Boolean) {
        scope.launch {
            localWrite("参加の記録") { marks.setAttendance(UserMark.SHOW, showId, type, on) }
            reload()
            onChange()
        }
    }

    /** 全公演に現地を付ける / 外す。ほかの形態 (配信など) はそのまま残す。 */
    fun toggleAllLive() {
        val on = !allLive
        scope.launch {
            localWrite("参加の記録") { shows.forEach { marks.setAttendance(UserMark.SHOW, it.id, AttendanceType.LIVE, on) } }
            reload()
            onChange()
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        ImasFormBackdrop(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
                Text(
                    "参加した公演",
                    style = ImasType.heading(17.sp, FontWeight.Bold),
                    color = DS.ink,
                    modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                )

                ImasListSection(footer = "公演ごとに参加形態を選べます。現地と配信のように複数付けられます。回収率には現地参加だけが数えられます。") {
                    ImasSelectableRow(
                        title = "全公演に現地参加",
                        trailing = ImasRowTrailing.Value("${shows.size}公演"),
                        isSelected = allLive,
                        seed = seed,
                        brand = brand,
                        onClick = ::toggleAllLive
                    )
                }

                ImasListSection {
                    shows.forEach { show ->
                        ShowAttendanceRow(show, attendance[show.id].orEmpty(), seed, brand) { type, on -> set(show.id, type, on) }
                    }
                }
            }
        }
    }
}

@Composable
private fun ShowAttendanceRow(
    show: Show,
    current: List<AttendanceType>,
    seed: String?,
    brand: String?,
    onSet: (AttendanceType, Boolean) -> Unit
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowVCompact),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            ImasText(show.name, role = ImasTextRole.ROW_LABEL)
            val sub = listOfNotNull(
                show.venue?.takeIf { it.isNotBlank() },
                show.date.takeIf { it.isNotBlank() }
            ).joinToString(" ・ ")
            if (sub.isNotEmpty()) {
                ImasText(sub, role = ImasTextRole.META)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            AttendanceType.options().forEach { type ->
                val on = type in current
                ImasFilterChip(
                    label = type.label,
                    selected = on,
                    onClick = { onSet(type, !on) },
                    seed = seed,
                    brand = brand
                )
            }
        }
    }
}
