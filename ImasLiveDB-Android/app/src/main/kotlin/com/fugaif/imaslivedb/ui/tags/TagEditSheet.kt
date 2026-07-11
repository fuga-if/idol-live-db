package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch

/** 既存タグの説明文/カテゴリ/色を編集するシート。iOS TagEditSheet の移植。 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun TagEditSheet(
    tag: CommunityApi.CommunityTag,
    domain: TagDomain = TagDomain.SONG,
    onDismiss: () -> Unit,
    onSaved: (CommunityApi.CommunityTag) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var description by remember { mutableStateOf(tag.description ?: "") }
    var category by remember { mutableStateOf(tag.category ?: "") }
    var color by remember { mutableStateOf(tag.color ?: "") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text("「${tag.name}」を編集", fontSize = 20.sp, color = DS.ink)

            OutlinedTextField(
                value = description,
                onValueChange = { description = it },
                label = { Text("説明文") },
                minLines = 4,
                modifier = Modifier.fillMaxWidth()
            )

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("カテゴリ", fontSize = 13.sp, color = DS.ink2)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    CategoryChip(label = "なし", selected = category.isEmpty()) { category = "" }
                    tagCategoryOptions(domain).filter { it.first.isNotEmpty() }.forEach { (value, label) ->
                        CategoryChip(label = label, selected = category == value) { category = value }
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("色", fontSize = 13.sp, color = DS.ink2)
                TagColorPicker(selectedHex = color, onSelect = { color = it })
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
                            errorMessage = "タグの編集にはサインインが必要です(設定画面からサインインしてください)"
                            return@Button
                        }
                        isSaving = true
                        scope.launch {
                            val api = module.communityApi
                            val updated = when (domain) {
                                TagDomain.SONG -> api.updateTag(id = tag.id, description = description, category = category, color = color)
                                TagDomain.IDOL -> api.updateIdolTagOption(id = tag.id, description = description, category = category, color = color)
                                TagDomain.UNIT -> api.updateUnitTagOption(id = tag.id, description = description, category = category, color = color)
                            }
                            isSaving = false
                            if (updated != null) {
                                onSaved(updated)
                                onDismiss()
                            } else {
                                errorMessage = "保存に失敗しました"
                            }
                        }
                    },
                    enabled = !isSaving,
                    modifier = Modifier.weight(1f)
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), color = DS.ink)
                    } else {
                        Text("保存")
                    }
                }
            }
        }
    }
}
