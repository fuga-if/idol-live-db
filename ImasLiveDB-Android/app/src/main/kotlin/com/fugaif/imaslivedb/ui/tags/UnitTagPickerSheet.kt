package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch

/**
 * ユニットへのタグ追加ピッカー。`IdolTagPickerSheet` と同じ見た目・操作感 (タグはユニット専用のマスタ)。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun UnitTagPickerSheet(
    unitId: String,
    alreadyAppliedTagIds: Set<String>,
    onDismiss: () -> Unit,
    onApplied: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var query by remember { mutableStateOf("") }
    var tags by remember { mutableStateOf<List<CommunityApi.CommunityTag>>(emptyList()) }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var isLoading by remember { mutableStateOf(true) }
    var isApplying by remember { mutableStateOf(false) }
    var showCreateSheet by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val trimmedQuery = query.trim()
    val exactMatchExists = tags.any { it.name == trimmedQuery }

    LaunchedEffect(query) {
        isLoading = true
        if (trimmedQuery.isNotEmpty()) kotlinx.coroutines.delay(200)
        val api = AppModule.from(context).communityApi
        tags = runCatching { api.unitTagCatalog(search = trimmedQuery, sort = "popular") }.getOrDefault(emptyList())
        isLoading = false
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier.fillMaxWidth().heightIn(min = 320.dp).verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("タグを追加", fontSize = 20.sp, color = DS.ink)

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("タグを検索 / 新規作成") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            if (trimmedQuery.isNotEmpty() && !exactMatchExists) {
                TextButton(onClick = { showCreateSheet = true }) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text("「$trimmedQuery」を作成")
                }
            }

            Text(
                if (trimmedQuery.isEmpty()) "よく使われるタグ" else "候補",
                fontSize = 12.sp, color = DS.ink2
            )

            when {
                isLoading -> Box(Modifier.fillMaxWidth().padding(16.dp)) { CircularProgressIndicator() }
                tags.isEmpty() -> Text("タグが見つかりません", fontSize = 13.sp, color = DS.ink3)
                else -> FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    tags.forEach { tag ->
                        val applied = alreadyAppliedTagIds.contains(tag.id)
                        val on = applied || selected.contains(tag.id)
                        UnitPickerTagChip(tag = tag, on = on, applied = applied, onClick = {
                            selected = if (selected.contains(tag.id)) selected - tag.id else selected + tag.id
                        })
                    }
                }
            }

            TextButton(onClick = { showCreateSheet = true }) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Text("色やカテゴリを付けて新規作成")
            }

            if (errorMessage != null) {
                Text(errorMessage!!, color = DS.danger, fontSize = 13.sp)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("キャンセル") }
                Button(
                    onClick = {
                        errorMessage = null
                        val module = AppModule.from(context)
                        if (!module.authService.state.value.isSignedIn) {
                            errorMessage = "タグの追加にはサインインが必要です(設定画面からサインインしてください)"
                            return@Button
                        }
                        isApplying = true
                        scope.launch {
                            val api = module.communityApi
                            val ok = runCatching { api.applyUnitTags(unitId, selected.toList()) }.getOrNull()
                            isApplying = false
                            if (ok != null) {
                                onApplied()
                                onDismiss()
                            } else {
                                errorMessage = "タグの追加に失敗しました"
                            }
                        }
                    },
                    enabled = selected.isNotEmpty() && !isApplying,
                    modifier = Modifier.weight(1f)
                ) {
                    if (isApplying) {
                        CircularProgressIndicator(modifier = Modifier.padding(2.dp))
                    } else {
                        Text("追加")
                    }
                }
            }
        }
    }

    if (showCreateSheet) {
        TagCreateSheet(
            domain = TagDomain.UNIT,
            initialName = trimmedQuery,
            onDismiss = { showCreateSheet = false },
            onCreated = { newTag ->
                tags = listOf(newTag) + tags.filterNot { it.id == newTag.id }
                selected = selected + newTag.id
            }
        )
    }
}

@Composable
private fun UnitPickerTagChip(tag: CommunityApi.CommunityTag, on: Boolean, applied: Boolean, onClick: () -> Unit) {
    val bg = if (on) DS.pick.copy(alpha = 0.18f) else DS.fill
    val fg = if (on) DS.pick else DS.ink2
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(bg)
            .clickable(enabled = !applied, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        if (on) Icon(Icons.Filled.Check, contentDescription = null, tint = fg, modifier = Modifier.size(14.dp))
        Text(tag.name, fontSize = 13.sp, color = fg)
        if (tag.totalUses > 0) {
            Text(" ${tag.totalUses}", fontSize = 11.sp, color = DS.ink3)
        }
    }
}
