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
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import kotlinx.coroutines.launch
import uniffi.imas_core.InputField
import uniffi.imas_core.inputClamp
import uniffi.imas_core.inputIsAcceptable
import uniffi.imas_core.inputLength
import uniffi.imas_core.inputLimitMax

/**
 * 新規タグ作成シート。iOS TagCreateSheet の移植。
 * タグ名(1〜30文字, 必須) + 説明(任意) + カテゴリ(任意) + 色(任意)。
 * 同名タグが既にあればサーバが既存タグを返す(冪等)ので、それをそのまま採用する。
 */
@OptIn(ExperimentalMaterial3Api::class)
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
    // 上限・数え方 (サーバと同じ UTF-16 の単位)・空の可否はコアが決める。
    val isValid = inputIsAcceptable(InputField.TAG_NAME, name)
    val nameLimit = inputLimitMax(InputField.TAG_NAME)
    val categoryOptions = tagCategoryOptions(domain)

    fun submit() {
        errorMessage = null
        val module = AppModule.from(context)
        // 権限判定はコア (edit_permission_rules) に集約。未ログインは誘導、
        // BAN 済みは理由を出す — このシートはタグ一覧/詳細からも開けて
        // 導線を隠しきれないので、無反応にすると原因が分からない。
        module.authService.state.value.startCommunityEdit(
            promptLogin = {
                errorMessage = "タグの作成にはサインインが必要です(設定画面からサインインしてください)"
            },
            onBanned = { errorMessage = "この操作は制限されています。" }
        ) {
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
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth()) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Edit(canSave = isValid && !isSaving, onCancel = onDismiss, onSave = ::submit),
                title = "新規タグ作成"
            )
            ImasFormPage {
                ImasFormCard {
                    ImasFormTextField(
                        label = "タグ名",
                        text = name,
                        onTextChange = { name = inputClamp(InputField.TAG_NAME, it) },
                        imprint = "NAME",
                        limit = nameLimit.toInt(),
                        count = inputLength(InputField.TAG_NAME, name).toInt()
                    )
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
