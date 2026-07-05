package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 曲一覧をタグで絞り込むための複数選択シート。iOS TagFilterPicker の移植。
 * 複数選択時は AND (全タグを含む曲) で絞り込む想定 (実際の絞り込みは呼び出し側の ViewModel が行う)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagFilterSheet(
    initialSelection: List<CommunityApi.CommunityTag>,
    onDismiss: () -> Unit,
    onDone: (List<CommunityApi.CommunityTag>) -> Unit
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var query by remember { mutableStateOf("") }
    var tags by remember { mutableStateOf<List<CommunityApi.CommunityTag>>(emptyList()) }
    var selected by remember { mutableStateOf(initialSelection) }
    var isLoading by remember { mutableStateOf(true) }

    LaunchedEffect(query) {
        isLoading = true
        val api = AppModule.from(context).communityApi
        tags = runCatching { api.tags(search = query.trim(), sort = "popular", limit = 100) }.getOrDefault(emptyList())
        isLoading = false
    }

    fun toggle(tag: CommunityApi.CommunityTag) {
        selected = if (selected.any { it.id == tag.id }) selected.filterNot { it.id == tag.id } else selected + tag
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().heightIn(min = 320.dp, max = 560.dp).padding(bottom = 16.dp)) {
            Text(
                "タグで絞り込み", fontSize = 20.sp, color = DS.ink,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("タグ名で検索") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
            )
            if (selected.isNotEmpty()) {
                Text(
                    "選択中 (${selected.size}) — すべてを含む曲に絞り込み",
                    fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
                Text(
                    selected.joinToString(" ＋ ") { it.name },
                    fontSize = 12.sp, color = DS.ink2,
                    modifier = Modifier.padding(horizontal = 16.dp)
                )
                HorizontalDivider(color = DS.sep, modifier = Modifier.padding(top = 8.dp))
            }
            when {
                isLoading -> Box(Modifier.fillMaxWidth().padding(32.dp)) { CircularProgressIndicator() }
                tags.isEmpty() -> Text(
                    "タグがありません", color = DS.ink2,
                    modifier = Modifier.fillMaxWidth().padding(32.dp)
                )
                else -> LazyColumn(modifier = Modifier.weight(1f, fill = false)) {
                    itemsIndexed(tags, key = { _, tag -> tag.id }) { idx, tag ->
                        val isSelected = selected.any { it.id == tag.id }
                        val rank = if (query.isEmpty()) idx + 1 else null
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxWidth().clickable { toggle(tag) }
                                .padding(horizontal = 16.dp, vertical = 10.dp)
                        ) {
                            if (rank != null) TagRankBadge(rank)
                            TagColorDot(tag.color)
                            Text(tag.name, fontSize = 15.sp, color = DS.ink, modifier = Modifier.weight(1f))
                            if (tag.totalUses > 0) Text("${tag.totalUses}曲", fontSize = 12.sp, color = DS.ink2)
                            if (isSelected) {
                                Icon(Icons.Filled.Check, contentDescription = null, tint = DS.pick)
                            }
                        }
                    }
                }
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("キャンセル") }
                Button(onClick = { onDone(selected); onDismiss() }, modifier = Modifier.weight(1f)) { Text("完了") }
            }
        }
    }
}
