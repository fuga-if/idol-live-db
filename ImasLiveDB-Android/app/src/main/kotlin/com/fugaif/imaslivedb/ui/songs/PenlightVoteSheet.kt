package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatch
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatchSize
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.hexToColor
import com.fugaif.imaslivedb.ui.theme.imasPress
import kotlinx.coroutines.launch

/**
 * ペンライトカラー投票シート (iOS `PenlightVoteSheet` の移植)。
 * サーバのパレット (/penlight/palette) から色候補を取得し、複数選択して投票する。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun PenlightVoteSheet(
    songId: String,
    onDismiss: () -> Unit,
    onVoted: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var palette by remember { mutableStateOf<List<CommunityApi.PenlightPaletteEntry>>(emptyList()) }
    var selected by remember { mutableStateOf(setOf<String>()) }
    var isLoading by remember { mutableStateOf(true) }
    var isSending by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        val api = AppModule.from(context).communityApi
        palette = runCatching { api.penlightPalette() }.getOrDefault(emptyList())
        isLoading = false
    }

    fun vote() {
        isSending = true
        scope.launch {
            val api = AppModule.from(context).communityApi
            runCatching { api.votePenlight(songId, selected.toList()) }
            isSending = false
            onVoted()
            onDismiss()
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth()) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Submit(
                    canSubmit = selected.isNotEmpty() && !isSending,
                    isSubmitting = isSending,
                    onCancel = onDismiss,
                    onSubmit = ::vote
                ),
                title = "ペンライトカラーを投票"
            )
            if (isLoading) {
                ImasLoadingState(title = "読み込み中…")
            } else {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(bottom = DS.sp8),
                    verticalArrangement = Arrangement.spacedBy(DS.sp5)
                ) {
                    ImasListSection {
                        ImasNote("ペンライトの色を選んで投票してください。複数選択できます。")
                    }
                    if (palette.isEmpty()) {
                        ImasEmptyState(
                            icon = Icons.Filled.Warning,
                            title = "カラーを取得できません",
                            message = "通信状況を確認して再度お試しください"
                        )
                    } else {
                        ImasListSection("カラーを選択") {
                            FlowRow(
                                modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV),
                                horizontalArrangement = Arrangement.spacedBy(DS.Space.card),
                                verticalArrangement = Arrangement.spacedBy(DS.Space.card)
                            ) {
                                palette.forEach { entry ->
                                    entry.colorHex?.let { hex ->
                                        PenlightColorChip(
                                            name = entry.name,
                                            hex = hex,
                                            isSelected = selected.contains(hex),
                                            onToggle = { selected = if (hex in selected) selected - hex else selected + hex }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** パレットの色 1 つ (iOS `PenlightColorChip`)。丸い色見本 + 選択時は中央に ✓、下に名前。 */
@Composable
private fun PenlightColorChip(name: String, hex: String, isSelected: Boolean, onToggle: () -> Unit) {
    Column(
        modifier = Modifier.width(72.dp).imasPress(onClickLabel = "色: $name", onClick = onToggle),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        Box(contentAlignment = Alignment.Center) {
            ImasSwatch(hex = hex, size = ImasSwatchSize.LARGE, isSelected = isSelected, isDecorative = true)
            if (isSelected) {
                // 選択は輪に加えて中央にも✓ (色の違いだけに頼らない)。WCAG で読める側の色を選ぶ。
                Icon(
                    Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = ImasTheme.onColor(hexToColor(hex))
                )
            }
        }
        ImasText(name, ImasTextRole.META, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
