package com.fugaif.imaslivedb.ui.polls

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.components.ImasRemovableChip
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor

/** 投票対象。index はセグメントの並びと 1:1 (曲 / アイドル / ユニット)。 */
private val TARGET_TYPES = listOf("song", "idol", "unit")
private val TARGET_LABELS = listOf("曲", "アイドル", "ユニット")
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
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
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
    val canSubmit = trimmedTitle.isNotEmpty() && !state.isSubmitting && when (scope) {
        CommunityApi.PollCandidateScope.ALL -> true
        CommunityApi.PollCandidateScope.BRAND -> selectedBrandIds.isNotEmpty()
        CommunityApi.PollCandidateScope.MANUAL -> state.candidates.size >= 2
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text("お題を投稿", fontSize = 20.sp, color = DS.ink)
            Text(
                "お題を作って、みんなに推しを投票してもらおう。期間中は誰でも3票まで投票できます。",
                fontSize = 13.sp, color = DS.ink2
            )

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value = title,
                    // 80 文字はサーバの上限。超えた入力はここで切って、送信してから弾かれるのを防ぐ。
                    onValueChange = { title = it.take(80) },
                    label = { Text("タイトル") },
                    placeholder = { Text("例: 夏に聴きたい曲は？") },
                    minLines = 1,
                    maxLines = 3,
                    modifier = Modifier.fillMaxWidth()
                )
                Text("${title.length} / 80文字", fontSize = 12.sp, color = DS.ink2)
            }

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it.take(280) },
                    label = { Text("説明(任意)") },
                    placeholder = { Text("補足やルールがあれば") },
                    minLines = 2,
                    maxLines = 5,
                    modifier = Modifier.fillMaxWidth()
                )
                Text("${description.length} / 280文字", fontSize = 12.sp, color = DS.ink2)
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("投票対象", fontSize = 13.sp, color = DS.ink2)
                ImasSegmented(
                    labels = TARGET_LABELS,
                    selection = targetIndex,
                    onSelect = {
                        targetIndex = it
                        // 種類をまたいだ候補は作れないので、切り替えたら選択済み候補は捨てる。
                        viewModel.clearCandidates()
                    },
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("投票候補", fontSize = 13.sp, color = DS.ink2)
                ImasSegmented(
                    labels = listOf("全て", "ブランド限定", "候補指定"),
                    selection = scopeIndex,
                    onSelect = { scopeIndex = it },
                    modifier = Modifier.fillMaxWidth()
                )
                when (scope) {
                    CommunityApi.PollCandidateScope.ALL ->
                        Text("全${targetNoun}から自由に投票できます。", fontSize = 12.sp, color = DS.ink3)

                    CommunityApi.PollCandidateScope.BRAND -> {
                        Text(
                            "選んだブランドの${targetNoun}だけが候補になります。複数選択可。",
                            fontSize = 12.sp, color = DS.ink3
                        )
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            state.brands.forEach { brand ->
                                ImasFilterChip(
                                    label = brand.shortName,
                                    selected = selectedBrandIds.contains(brand.id),
                                    tintColor = brandColor(brand.id),
                                    onClick = {
                                        selectedBrandIds = if (selectedBrandIds.contains(brand.id)) {
                                            selectedBrandIds - brand.id
                                        } else {
                                            selectedBrandIds + brand.id
                                        }
                                    }
                                )
                            }
                        }
                        if (selectedBrandIds.isEmpty()) {
                            Text("1つ以上選択してください", fontSize = 12.sp, color = DS.danger)
                        }
                    }

                    CommunityApi.PollCandidateScope.MANUAL -> {
                        Row(modifier = Modifier.fillMaxWidth()) {
                            Text("候補は2件以上必要です。", fontSize = 12.sp, color = DS.ink3, modifier = Modifier.weight(1f))
                            Text(
                                "${state.candidates.size}件選択中",
                                fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                                color = if (state.candidates.size >= 2) DS.ink2 else DS.danger
                            )
                        }
                        if (state.candidates.isNotEmpty()) {
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                state.candidates.forEach { candidate ->
                                    ImasRemovableChip(
                                        text = candidate.displayName,
                                        onRemove = { viewModel.removeCandidate(candidate.entityId) }
                                    )
                                }
                            }
                        }
                        Button(
                            onClick = { showCandidatePicker = true },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Icon(Icons.Filled.AddCircle, contentDescription = null, modifier = Modifier.size(18.dp))
                            Text("候補を追加", fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.padding(start = 6.dp))
                        }
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("募集期間", fontSize = 13.sp, color = DS.ink2)
                ImasSegmented(
                    labels = DAY_OPTIONS.map { "${it}日間" },
                    selection = dayIndex,
                    onSelect = { dayIndex = it },
                    modifier = Modifier.fillMaxWidth()
                )
            }

            if (state.errorMessage != null) {
                Text(state.errorMessage!!, color = DS.danger, fontSize = 13.sp)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("キャンセル") }
                Button(
                    onClick = {
                        viewModel.submit(
                            title = trimmedTitle,
                            description = description.trim().ifEmpty { null },
                            targetType = targetType,
                            days = DAY_OPTIONS[dayIndex],
                            scope = scope,
                            brandIds = selectedBrandIds,
                            onCreated = { poll -> onCreated(poll); onDismiss() }
                        )
                    },
                    enabled = canSubmit,
                    modifier = Modifier.weight(1f)
                ) {
                    if (state.isSubmitting) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), color = DS.ink)
                    } else {
                        Text("作成")
                    }
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
