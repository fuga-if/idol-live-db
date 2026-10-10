package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
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
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasFormPage
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import uniffi.imas_core.TagCategoryInput
import uniffi.imas_core.idolTagCategoryGroups

/**
 * アイドルへのタグ追加ピッカー。SongTagPickerSheet と同じ見た目・操作感 (タグは曲と共有のマスタ)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolTagPickerSheet(
    idolId: String,
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
        tags = runCatching { api.idolTagCatalog(search = trimmedQuery, sort = "popular") }.getOrDefault(emptyList())
        isLoading = false
    }

    fun submit() {
        errorMessage = null
        val module = AppModule.from(context)
        // 権限判定はコア (edit_permission_rules) に集約。未ログインは誘導、
        // BAN 済みは何も起きない (押せる導線自体が出ていない)。
        module.authService.state.value.startCommunityEdit(
            promptLogin = {
                errorMessage = "タグの追加にはサインインが必要です(設定画面からサインインしてください)"
            }
        ) {
            isApplying = true
            scope.launch {
                val api = module.communityApi
                val ok = runCatching { api.applyIdolTags(idolId, selected.toList()) }.getOrNull()
                isApplying = false
                if (ok != null) {
                    onApplied()
                    onDismiss()
                } else {
                    errorMessage = "タグの追加に失敗しました"
                }
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth()) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Submit(
                    canSubmit = selected.isNotEmpty() && !isApplying,
                    isSubmitting = isApplying,
                    onCancel = onDismiss,
                    onSubmit = ::submit
                ),
                title = "タグを追加"
            )
            ImasFormPage {
                ImasSearchField(prompt = "タグを検索 / 新規作成", text = query, onTextChange = { query = it })

                if (trimmedQuery.isNotEmpty() && !exactMatchExists) {
                    ImasCardList {
                        ImasActionRow(title = "「$trimmedQuery」を作成", icon = Icons.Filled.Add, onClick = { showCreateSheet = true })
                    }
                }

                @Composable
                fun chips(list: List<CommunityApi.CommunityTag>) = ImasChipFlow {
                    list.forEach { tag ->
                        TagSelectChip(
                            tag = tag,
                            isApplied = alreadyAppliedTagIds.contains(tag.id),
                            isSelected = selected.contains(tag.id),
                            onClick = {
                                selected = if (selected.contains(tag.id)) selected - tag.id else selected + tag.id
                            }
                        )
                    }
                }

                if (trimmedQuery.isEmpty() && !isLoading && tags.isNotEmpty()) {
                    // 検索していないときはカテゴリ (性格・容姿 …) ごとに見出しを分ける。中はよく使われる順。まとめ方はコア。
                    val byId = remember(tags) { tags.associateBy { it.id } }
                    val groups = remember(tags) { idolTagCategoryGroups(tags.map { TagCategoryInput(it.id, it.category) }) }
                    groups.forEach { group ->
                        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
                            ImasSectionHeader(title = group.label, style = ImasSectionHeaderStyle.SMALL)
                            chips(group.tagIds.mapNotNull { byId[it] })
                        }
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
                        ImasSectionHeader(title = if (trimmedQuery.isEmpty()) "よく使われるタグ" else "候補", style = ImasSectionHeaderStyle.SMALL)
                        when {
                            isLoading -> ImasInlineLoading()
                            tags.isEmpty() -> ImasNote("タグが見つかりません")
                            else -> chips(tags)
                        }
                    }
                }

                ImasActionRow(title = "色やカテゴリを付けて新規作成", icon = Icons.Filled.Add, onClick = { showCreateSheet = true })

                if (errorMessage != null) {
                    ImasNotice(kind = ImasNoticeKind.ERROR, message = errorMessage)
                }
            }
        }
    }

    if (showCreateSheet) {
        TagCreateSheet(
            domain = TagDomain.IDOL,
            initialName = trimmedQuery,
            onDismiss = { showCreateSheet = false },
            onCreated = { newTag ->
                tags = listOf(newTag) + tags.filterNot { it.id == newTag.id }
                selected = selected + newTag.id
            }
        )
    }
}
