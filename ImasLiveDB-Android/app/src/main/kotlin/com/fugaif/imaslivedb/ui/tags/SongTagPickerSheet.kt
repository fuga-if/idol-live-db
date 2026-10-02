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
import com.fugaif.imaslivedb.ui.share.TagShareCompletionPane
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch

/**
 * 曲へのタグ追加ピッカー。iOS SongTagPicker の移植。
 * 既存タグを検索して複数選択 → まとめて適用、または検索語からその場で新規タグを作成できる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongTagPickerSheet(
    songId: String,
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
    // 適用に成功したタグ。非 null になるとシート内容が「完了 + カードでシェア」へ切り替わる。
    // シートを重ねずに中身を差し替えるのは、シートが 2 枚積み上がるのを避けるため (iOS も同じ形)。
    var appliedTags by remember { mutableStateOf<List<CommunityApi.CommunityTag>?>(null) }

    val trimmedQuery = query.trim()
    val exactMatchExists = tags.any { it.name == trimmedQuery }

    LaunchedEffect(query) {
        isLoading = true
        if (trimmedQuery.isNotEmpty()) kotlinx.coroutines.delay(200)
        val api = AppModule.from(context).communityApi
        tags = runCatching { api.tags(search = trimmedQuery, sort = "popular") }.getOrDefault(emptyList())
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
                val ok = runCatching { api.applySongTags(songId, selected.toList()) }.getOrNull()
                isApplying = false
                if (ok != null) {
                    onApplied()
                    appliedTags = tags.filter { it.id in selected }
                } else {
                    errorMessage = "タグの追加に失敗しました"
                }
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        val applied = appliedTags
        if (applied != null) {
            TagShareCompletionPane(songId = songId, appliedTags = applied, onClose = onDismiss)
            return@ModalBottomSheet
        }
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

                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
                    ImasSectionHeader(title = if (trimmedQuery.isEmpty()) "よく使われるタグ" else "候補", style = ImasSectionHeaderStyle.SMALL)
                    when {
                        isLoading -> ImasInlineLoading()
                        tags.isEmpty() -> ImasNote("タグが見つかりません")
                        else -> ImasChipFlow {
                            tags.forEach { tag ->
                                val applied2 = alreadyAppliedTagIds.contains(tag.id)
                                TagSelectChip(
                                    tag = tag,
                                    isApplied = applied2,
                                    isSelected = selected.contains(tag.id),
                                    onClick = {
                                        selected = if (selected.contains(tag.id)) selected - tag.id else selected + tag.id
                                    }
                                )
                            }
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
            initialName = trimmedQuery,
            onDismiss = { showCreateSheet = false },
            onCreated = { newTag ->
                tags = listOf(newTag) + tags.filterNot { it.id == newTag.id }
                selected = selected + newTag.id
            }
        )
    }
}
