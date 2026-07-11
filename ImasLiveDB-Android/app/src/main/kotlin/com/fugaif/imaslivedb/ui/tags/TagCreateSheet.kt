package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch

/**
 * 新規タグ作成シート。iOS TagCreateSheet の移植。
 * タグ名(1〜30文字, 必須) + 説明(任意) + カテゴリ(任意) + 色(任意)。
 * 同名タグが既にあればサーバが既存タグを返す(冪等)ので、それをそのまま採用する。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun TagCreateSheet(
    domain: TagDomain = TagDomain.SONG,
    initialName: String = "",
    onDismiss: () -> Unit,
    onCreated: (CommunityApi.CommunityTag) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var name by remember { mutableStateOf(initialName) }
    var description by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("") }
    var color by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val trimmedName = name.trim()
    val isValid = trimmedName.isNotEmpty() && trimmedName.length <= 30

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text("新規タグ作成", fontSize = 20.sp, color = DS.ink)

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("タグ名(1〜30文字)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    isError = name.isNotEmpty() && !isValid
                )
                Text("${trimmedName.length} / 30文字", fontSize = 12.sp, color = if (isValid) DS.ink2 else DS.danger)
            }

            OutlinedTextField(
                value = description,
                onValueChange = { description = it },
                label = { Text("説明文(任意)") },
                minLines = 3,
                modifier = Modifier.fillMaxWidth()
            )

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("カテゴリ(任意)", fontSize = 13.sp, color = DS.ink2)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    CategoryChip(label = "なし", selected = category.isEmpty()) { category = "" }
                    tagCategoryOptions(domain).filter { it.first.isNotEmpty() }.forEach { (value, label) ->
                        CategoryChip(label = label, selected = category == value) { category = value }
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("色(任意)", fontSize = 13.sp, color = DS.ink2)
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
                            errorMessage = "タグの作成にはサインインが必要です(設定画面からサインインしてください)"
                            return@Button
                        }
                        isSaving = true
                        scope.launch {
                            val api = module.communityApi
                            val createResult = when (domain) {
                                TagDomain.SONG -> api.createTag(
                                    name = trimmedName,
                                    description = description.ifBlank { null },
                                    category = category.ifEmpty { null },
                                    color = color.ifEmpty { null }
                                )
                                TagDomain.IDOL -> api.createIdolTagOption(
                                    name = trimmedName,
                                    description = description.ifBlank { null },
                                    category = category.ifEmpty { null },
                                    color = color.ifEmpty { null }
                                )
                                TagDomain.UNIT -> api.createUnitTagOption(
                                    name = trimmedName,
                                    description = description.ifBlank { null },
                                    category = category.ifEmpty { null },
                                    color = color.ifEmpty { null }
                                )
                            }
                            when (val result = createResult) {
                                is CommunityApi.TagCreateResult.Success -> {
                                    isSaving = false
                                    onCreated(result.tag)
                                    onDismiss()
                                }
                                is CommunityApi.TagCreateResult.RateLimited -> {
                                    isSaving = false
                                    errorMessage = "1日10件まで作成できます。明日試してください"
                                }
                                is CommunityApi.TagCreateResult.Error -> {
                                    isSaving = false
                                    errorMessage = result.message ?: "作成に失敗しました"
                                }
                            }
                        }
                    },
                    enabled = isValid && !isSaving,
                    modifier = Modifier.weight(1f)
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), color = DS.ink)
                    } else {
                        Text("作成")
                    }
                }
            }
        }
    }
}
