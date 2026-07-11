package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** タグの説明文編集履歴。iOS TagHistoryView の移植。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagHistorySheet(tagId: String, domain: TagDomain = TagDomain.SONG, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var isLoading by remember { mutableStateOf(true) }
    var history by remember { mutableStateOf<List<CommunityApi.TagHistoryEntry>>(emptyList()) }

    LaunchedEffect(tagId) {
        val api = AppModule.from(context).communityApi
        history = runCatching {
            when (domain) {
                TagDomain.SONG -> api.tagHistory(tagId)
                TagDomain.IDOL -> api.idolTagOptionHistory(tagId)
                TagDomain.UNIT -> api.unitTagOptionHistory(tagId)
            }
        }.getOrDefault(emptyList())
        isLoading = false
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().heightIn(min = 200.dp).padding(bottom = 24.dp)) {
            Text(
                "編集履歴", fontSize = 20.sp, color = DS.ink,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )
            when {
                isLoading -> Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                history.isEmpty() -> Text(
                    "編集履歴はありません", color = DS.ink2, fontSize = 14.sp,
                    modifier = Modifier.fillMaxWidth().padding(32.dp)
                )
                else -> LazyColumn {
                    items(history) { entry ->
                        Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
                            Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                                Text(formatEditedAt(entry.editedAt), fontSize = 12.sp, color = DS.ink2)
                                Text(entry.editedBy.take(8) + "...", fontSize = 11.sp, color = DS.ink3)
                            }
                            Text(
                                entry.descriptionAfter?.ifEmpty { null } ?: "(説明なし)",
                                fontSize = 15.sp,
                                color = if (entry.descriptionAfter.isNullOrEmpty()) DS.ink3 else DS.ink,
                                modifier = Modifier.padding(top = 4.dp)
                            )
                        }
                        HorizontalDivider(color = DS.sep)
                    }
                }
            }
        }
    }
}

private fun formatEditedAt(epochSeconds: Long): String {
    if (epochSeconds <= 0) return ""
    val fmt = SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.getDefault())
    return fmt.format(Date(epochSeconds * 1000))
}
