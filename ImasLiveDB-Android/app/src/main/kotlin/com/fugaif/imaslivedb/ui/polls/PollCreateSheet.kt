package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.ui.components.ImasBrandPicker
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasChoice
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceCards
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormPage
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasRemovableChip
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import uniffi.imas_core.InputField
import uniffi.imas_core.inputClamp
import uniffi.imas_core.inputIsAcceptable
import uniffi.imas_core.inputLength
import uniffi.imas_core.inputLimitMax
import uniffi.imas_core.voteLimitPerTarget

/** 投票対象。index はセグメントの並びと 1:1 (曲 / アイドル / ユニット)。 */
private val TARGET_TYPES = listOf("song", "idol", "unit")
private val TARGET_LABELS = listOf("曲", "アイドル", "ユニット")
private val TARGET_ICONS = listOf(Icons.Filled.MusicNote, Icons.Filled.Person, Icons.Filled.Groups)
private val DAY_OPTIONS = listOf(7, 14, 30)
private val SCOPES = listOf(
    CommunityApi.PollCandidateScope.ALL,
    CommunityApi.PollCandidateScope.BRAND,
    CommunityApi.PollCandidateScope.MANUAL
)

/** 候補指定スコープの上限 (サーバの scope_entity_ids と同じ値)。超える分はピッカー側で切る。 */
private const val MAX_MANUAL_CANDIDATES = 500

/**
 * お題作成シート。iOS PollCreateSheet の移植。
 * タイトル / 説明 / 対象種別 / 募集期間 / 候補スコープ を指定して新しいお題を投稿する。
 * 候補指定スコープのピッカーは、お題詳細の「候補を追加」と同じものを使い回す。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PollCreateSheet(
    onDismiss: () -> Unit,
    onCreated: (CommunityApi.PollSummary) -> Unit,
    viewModel: PollCreateViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var title by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var targetIndex by remember { mutableIntStateOf(0) }
    var dayIndex by remember { mutableIntStateOf(1) }   // 既定は 14 日間 (iOS と同じ)
    var scopeIndex by remember { mutableIntStateOf(0) }
    var selectedBrandIds by remember { mutableStateOf(emptySet<String>()) }
    var showCandidatePicker by remember { mutableStateOf(false) }

    val targetType = TARGET_TYPES[targetIndex]
    val targetNoun = TARGET_LABELS[targetIndex]
    val scope = SCOPES[scopeIndex]
    val trimmedTitle = title.trim()

    // iOS canSubmit と同じ条件。ブランド限定は 1 つ以上、候補指定は 2 件以上ないとサーバが弾く。
    val canSubmit = inputIsAcceptable(InputField.POLL_TITLE, title) && !state.isSubmitting && when (scope) {
        CommunityApi.PollCandidateScope.ALL -> true
        CommunityApi.PollCandidateScope.BRAND -> selectedBrandIds.isNotEmpty()
        CommunityApi.PollCandidateScope.MANUAL -> state.candidates.size >= 2
    }

    fun submit() {
        viewModel.submit(
            title = trimmedTitle,
            description = description.trim().ifEmpty { null },
            targetType = targetType,
            days = DAY_OPTIONS[dayIndex],
            scope = scope,
            brandIds = selectedBrandIds,
            onCreated = { poll -> onCreated(poll); onDismiss() }
        )
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth()) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Submit(canSubmit = canSubmit, isSubmitting = state.isSubmitting, onCancel = onDismiss, onSubmit = ::submit),
                title = "お題を投稿"
            )
            ImasFormPage {
                ImasNote("お題を作って、みんなに推しを投票してもらおう。期間中は誰でも${voteLimitPerTarget()}票まで投票できます。")

                ImasFormCard {
                    ImasFormTextField(
                        label = "タイトル",
                        text = title,
                        onTextChange = { title = inputClamp(InputField.POLL_TITLE, it) },
                        imprint = "TITLE",
                        prompt = "例: 夏に聴きたい曲は？",
                        limit = inputLimitMax(InputField.POLL_TITLE).toInt(),
                        count = inputLength(InputField.POLL_TITLE, title).toInt()
                    )
                    ImasFormTextArea(
                        label = "説明(任意)",
                        text = description,
                        onTextChange = { description = inputClamp(InputField.POLL_DESCRIPTION, it) },
                        prompt = "補足やルールがあれば",
                        imprint = "DESCRIPTION",
                        limit = inputLimitMax(InputField.POLL_DESCRIPTION).toInt(),
                        count = inputLength(InputField.POLL_DESCRIPTION, description).toInt()
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
                    ImasSectionHeader(title = "投票対象", style = ImasSectionHeaderStyle.SMALL)
                    ImasChoiceCards(
                        choices = TARGET_LABELS.indices.map { i -> ImasChoice(value = i, title = TARGET_LABELS[i], icon = TARGET_ICONS[i]) },
                        selection = targetIndex,
                        onSelect = {
                            targetIndex = it
                            // 種類をまたいだ候補は作れないので、切り替えたら選択済み候補は捨てる。
                            viewModel.clearCandidates()
                        }
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
                    ImasSectionHeader(title = "投票候補", style = ImasSectionHeaderStyle.SMALL)
                    ImasSegmented(labels = listOf("全て", "ブランド限定", "候補指定"), selection = scopeIndex, onSelect = { scopeIndex = it })
                    when (scope) {
                        CommunityApi.PollCandidateScope.ALL ->
                            ImasNote("全${targetNoun}から自由に投票できます。")

                        CommunityApi.PollCandidateScope.BRAND -> Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                            ImasNote("チェックしたブランドの${targetNoun}だけが候補になります。複数選択可。")
                            ImasBrandPicker(
                                brands = state.brands,
                                selection = selectedBrandIds,
                                onSelectionChange = { selectedBrandIds = it },
                                includesAll = false
                            )
                            if (selectedBrandIds.isEmpty()) {
                                ImasNote("1つ以上選択してください")
                            }
                        }

                        CommunityApi.PollCandidateScope.MANUAL -> Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                            Row(modifier = Modifier.fillMaxWidth()) {
                                ImasNote("候補は2件以上必要です。", modifier = Modifier.weight(1f))
                                Text(
                                    "${state.candidates.size}件選択中",
                                    style = ImasTextRole.META.style,
                                    color = if (state.candidates.size >= 2) DS.ink2 else DS.danger
                                )
                            }
                            if (state.candidates.isNotEmpty()) {
                                ImasChipFlow {
                                    state.candidates.forEach { candidate ->
                                        ImasRemovableChip(text = candidate.displayName, onRemove = { viewModel.removeCandidate(candidate.entityId) })
                                    }
                                }
                            }
                            ImasActionRow(
                                title = "候補を追加",
                                icon = Icons.Filled.AddCircle,
                                onClick = { showCandidatePicker = true }
                            )
                        }
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
                    ImasSectionHeader(title = "募集期間", style = ImasSectionHeaderStyle.SMALL)
                    ImasSegmented(labels = DAY_OPTIONS.map { "${it}日間" }, selection = dayIndex, onSelect = { dayIndex = it })
                }

                if (state.errorMessage != null) {
                    ImasNotice(kind = ImasNoticeKind.ERROR, message = state.errorMessage)
                }
            }
        }
    }

    if (showCandidatePicker) {
        val alreadySelected = state.candidates.map { it.entityId }.toSet()
        // ピッカーは「追加分」だけを返すので、既存の並びの末尾に足して選択順を保つ。
        val appendCandidates: (List<String>) -> Unit = { newIds ->
            viewModel.setCandidates(targetType, state.candidates.map { it.entityId } + newIds)
            showCandidatePicker = false
        }
        val remaining = (MAX_MANUAL_CANDIDATES - alreadySelected.size).coerceAtLeast(0)
        when (targetType) {
            "idol" -> IdolPollCandidatePicker(
                alreadySelected = alreadySelected,
                remaining = remaining,
                onDismiss = { showCandidatePicker = false },
                onConfirm = appendCandidates
            )
            "unit" -> UnitPollCandidatePicker(
                alreadySelected = alreadySelected,
                remaining = remaining,
                onDismiss = { showCandidatePicker = false },
                onConfirm = appendCandidates
            )
            else -> SongPollCandidatePicker(
                alreadySelected = alreadySelected,
                remaining = remaining,
                // ブランド限定は「候補指定」と排他なので、ここでは曲の絞り込みを掛けない。
                restrictedBrandIds = null,
                onDismiss = { showCandidatePicker = false },
                onConfirm = appendCandidates
            )
        }
    }
}
