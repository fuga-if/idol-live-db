package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.local.localWrite
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.events.EventAttendanceSheet
import com.fugaif.imaslivedb.ui.mastery.MasterySwipeRow
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch

/**
 * 公演の行をスワイプすると出る参加登録アクション (iOS `AttendanceSwipeActions` の移植)。
 *
 * 選択肢と取り消しの出し分けは [AttendanceType.options] を呼ぶだけ。これは SetlistScreen の
 * 参加確認ダイアログ (`AttendanceDialog`) が使う規則と同じもので、ここで新しい判定を
 * 書き足すと、ダイアログ版とスワイプ版で規則が二重管理になる。
 *
 * Compose の [androidx.compose.material3.SwipeToDismissBox] は向きしか区別できないので、
 * iOS のように現地/配信/LV のボタンをスワイプ直下に並べられない。右スワイプでシートを開き、
 * そこで形態を選ぶ (習熟度画面の群一覧が右スワイプでシートを出しているのと同じ作り)。
 * 左スワイプは使わない — 端から引くと OS の「戻る」に取られて画面ごと閉じる
 * (エミュで実測済み)。取り消しはシートの中に置く。
 *
 * 一覧行数は公演単位 (多くて数十件) なので、行ごとに現在値を読んでも習熟度一覧
 * (数千曲) のような再評価コストにはならない (iOS の実装コメントと同じ判断)。
 */
@Composable
fun AttendanceSwipeRow(
    showId: String,
    showName: String? = null,
    onChange: () -> Unit = {},
    content: @Composable () -> Unit
) {
    val context = LocalContext.current
    val marks = remember { AppModule.from(context).userMarkRepository }
    val scope = rememberCoroutineScope()
    var current by remember(showId) { mutableStateOf<AttendanceType?>(null) }
    var showSheet by remember { mutableStateOf(false) }

    LaunchedEffect(showId) { current = marks.attendance(UserMark.SHOW, showId) }

    MasterySwipeRow(
        onStart = { showSheet = true },
        startLabel = current?.let { "${it.label}で参加中" } ?: "参加を登録",
        startColor = DS.success,
    ) {
        content()
    }

    if (showSheet) {
        AttendancePickerSheet(
            showName = showName,
            current = current,
            onSelect = { type ->
                showSheet = false
                scope.launch {
                    localWrite("参加の記録") { marks.setAttendance(UserMark.SHOW, showId, type) } ?: return@launch
                    current = type
                    onChange()
                }
            },
            onDismiss = { showSheet = false }
        )
    }
}

/**
 * イベントの行をスワイプすると出る参加登録アクション (iOS `EventAttendanceSwipeActions` の移植)。
 *
 * イベントは公演 (show) を複数束ねることがあり、参加は show 単位でしか保存できない。
 * 「1 公演だけなら直接登録」のような出し分けをここで新設すると、[EventAttendanceSheet] が
 * 既に持つ「公演ごとに選ぶ / 全公演に現地参加」の規則と二重管理になる。そのため公演数に
 * よらず、常に同じ [EventAttendanceSheet] (EventDetailScreen と共有) を開く。
 */
@Composable
fun EventAttendanceSwipeRow(
    eventId: String,
    seed: String? = null,
    brand: String? = null,
    onChange: () -> Unit = {},
    content: @Composable () -> Unit
) {
    val context = LocalContext.current
    val eventRepository = remember { AppModule.from(context).eventRepository }
    val scope = rememberCoroutineScope()
    var shows by remember(eventId) { mutableStateOf<List<Show>>(emptyList()) }
    var showSheet by remember { mutableStateOf(false) }

    MasterySwipeRow(
        onStart = {
            scope.launch {
                shows = eventRepository.fetchShows(eventId)
                showSheet = true
            }
        },
        startLabel = "参加を登録",
        startColor = DS.success,
    ) {
        content()
    }

    if (showSheet) {
        EventAttendanceSheet(
            shows = shows,
            seed = seed,
            brand = brand,
            onDismiss = { showSheet = false },
            onChange = onChange
        )
    }
}

/**
 * 公演への参加形態を選ぶシート。現地 / 配信 / LV の 3 形態を常に出す
 * ([AttendanceType.options]) — 開催情報の欠落で選べなくなるより、選び間違いのほうが
 * 実害が小さいという判断 (iOS `AttendanceAvailability` と同じ)。選択中の形態をもう一度
 * 押すと不参加に戻る。取り消しはここに置く (行のスワイプには乗せない)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AttendancePickerSheet(
    showName: String?,
    current: AttendanceType?,
    onSelect: (AttendanceType?) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Text(
                showName ?: "この公演への参加",
                fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink, maxLines = 2
            )
            Spacer(Modifier.height(4.dp))
            Text("参加形態を選ぶ", fontSize = 12.sp, color = DS.ink2)
            Spacer(Modifier.height(8.dp))
            AttendanceType.options().forEach { type ->
                val on = current == type
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onSelect(if (on) null else type) }
                        .padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(
                        if (on) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (on) DS.success else DS.ink3,
                        modifier = Modifier.size(20.dp)
                    )
                    Text(
                        "${type.label}で参加",
                        fontSize = 15.sp,
                        fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                        color = DS.ink
                    )
                }
            }
            if (current != null) {
                HorizontalDivider(color = DS.sep, modifier = Modifier.padding(vertical = 4.dp))
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onSelect(null) }.padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(Icons.Filled.Cancel, contentDescription = null, tint = DS.danger, modifier = Modifier.size(20.dp))
                    Text("参加を取り消す", fontSize = 15.sp, color = DS.danger)
                }
            }
        }
    }
}
