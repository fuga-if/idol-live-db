package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormPage
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import kotlinx.coroutines.launch
import uniffi.imas_core.InputField
import uniffi.imas_core.inputClamp

/** 既存タグの説明文/カテゴリ/色を編集するシート。iOS TagEditSheet の移植。 */
@OptIn(ExperimentalMaterial3Api::class)
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
    val categoryOptions = tagCategoryOptions(domain)

    fun submit() {
        errorMessage = null
        val module = AppModule.from(context)
        // 権限判定はコア (edit_permission_rules) に集約。未ログインは誘導、
        // BAN 済みは理由を出す — このシートはタグ一覧/詳細からも開けて
        // 導線を隠しきれないので、無反応にすると原因が分からない。
        module.authService.state.value.startCommunityEdit(
            promptLogin = {
                errorMessage = "タグの編集にはサインインが必要です(設定画面からサインインしてください)"
            },
            onBanned = { errorMessage = "この操作は制限されています。" }
        ) {
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
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth()) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Edit(canSave = !isSaving, onCancel = onDismiss, onSave = ::submit),
                title = "「${tag.name}」を編集"
            )
            ImasFormPage {
                ImasFormCard {
                    ImasFormTextArea(
                        label = "説明文（任意）",
                        text = description,
                        onTextChange = { description = inputClamp(InputField.TAG_DESCRIPTION, it) },
                        prompt = "説明文（任意）",
                        imprint = "DESCRIPTION"
                    )
                    ImasFormField(label = "カテゴリ（任意）", imprint = "CATEGORY") {
                        ImasChipFlow {
                            categoryOptions.forEach { (value, label) ->
                                ImasFilterChip(label = label, selected = category == value, onClick = { category = value })
                            }
                        }
                    }
                    ImasFormField(label = "色（任意）", imprint = "COLOR") {
                        TagColorPicker(selectedHex = color, onSelect = { color = it })
                    }
                }

                if (errorMessage != null) {
                    ImasNotice(kind = ImasNoticeKind.ERROR, message = errorMessage)
                }
            }
        }
    }
}
