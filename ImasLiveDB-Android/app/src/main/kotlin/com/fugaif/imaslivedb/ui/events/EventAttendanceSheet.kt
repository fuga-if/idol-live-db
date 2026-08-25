package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.launch

/**
 * イベントの「参加」を公演 (show) 単位で管理するシート。iOS `EventAttendanceSheet` の移植。
 *
 * 参加マークは公演単位 (`entity_type = show` / `kind = attended` / `text_value = 参加形態`) で
 * 持つ。イベント全体に付けてしまうと、行っていない公演まで回収率の対象になってしまう。
 * 選択中の形態をもう一度押すと不参加に戻る。
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
    val t = ImasTheme.derive(seed, brand, dark = true)

    var attendance by remember { mutableStateOf<Map<String, AttendanceType>>(emptyMap()) }

    suspend fun reload() {
        attendance = shows.mapNotNull { show ->
            marks.attendance(UserMark.SHOW, show.id)?.let { show.id to it }
        }.toMap()
    }

    LaunchedEffect(shows) { reload() }

    val allLive = shows.isNotEmpty() && shows.all { attendance[it.id] == AttendanceType.LIVE }

    fun set(showId: String, type: AttendanceType?) {
        scope.launch {
            marks.setAttendance(UserMark.SHOW, showId, type)
            reload()
            onChange()
        }
    }

    fun toggleAllLive() {
        val target = if (allLive) null else AttendanceType.LIVE
        scope.launch {
            shows.forEach { marks.setAttendance(UserMark.SHOW, it.id, target) }
            reload()
            onChange()
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 32.dp)
        ) {
            Text(
                "参加した公演",
                fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )
            HorizontalDivider(color = DS.sep)

            Row(
                modifier = Modifier.fillMaxWidth().clickable { toggleAllLive() }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    if (allLive) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = if (allLive) t.accent else DS.ink3,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(12.dp))
                Text("全公演に現地参加", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
                Spacer(Modifier.weight(1f))
                Text("${shows.size}公演", fontSize = 12.sp, color = DS.ink2)
            }
            Text(
                "公演ごとに参加形態を選べます。回収率には現地参加だけが数えられます。",
                fontSize = 12.sp, color = DS.ink2,
                modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp)
            )
            HorizontalDivider(color = DS.sep)

            shows.forEach { show ->
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                    Text(show.name, fontSize = 15.sp, color = DS.ink)
                    val sub = listOfNotNull(show.venue?.takeIf { it.isNotBlank() },
                        show.date.takeIf { it.isNotBlank() }).joinToString(" ・ ")
                    if (sub.isNotEmpty()) {
                        Spacer(Modifier.height(2.dp))
                        Text(sub, fontSize = 12.sp, color = DS.ink2)
                    }
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AttendanceType.options().forEach { type ->
                            val on = attendance[show.id] == type
                            Text(
                                type.label,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (on) t.onAccent else DS.ink2,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(50.dp))
                                    .background(if (on) t.accent else DS.fill)
                                    .clickable { set(show.id, if (on) null else type) }
                                    .padding(horizontal = 13.dp, vertical = 7.dp)
                            )
                        }
                    }
                }
                HorizontalDivider(color = DS.sep)
            }
        }
    }
}
