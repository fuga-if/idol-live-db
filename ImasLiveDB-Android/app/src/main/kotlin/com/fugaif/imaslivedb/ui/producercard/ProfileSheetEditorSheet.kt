package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.producercard.ProfileSheetMaterials
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasDiscardConfirmation
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.share.ProfileSheetPreview
import com.fugaif.imaslivedb.ui.share.rememberShareCardCapture
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.launch
import uniffi.imas_core.ProfileSheet
import uniffi.imas_core.profileAutoFieldRows
import uniffi.imas_core.profileBrandMarks
import uniffi.imas_core.profileSheetLayout
import uniffi.imas_core.profileSheetSizes
import uniffi.imas_core.profileSheetStyles
import uniffi.imas_core.profileToggleBrand
import uniffi.imas_core.profileToggleField

/**
 * プロフィール帳を直す。iOS `ProfileSheetEditorView` の移植。上に出来上がりの見本 (その場で変わる)、下に欄の一覧。
 *
 * 自分で書く欄は無く、選ぶのは様式・大きさ・担当ブランドの丸・載せる記録だけ。
 * 一覧・丸の付け外し・載せる記録の行はコア (`profileSheetStyles` / `profileSheetSizes` / `profileBrandMarks` /
 * `profileToggleBrand` / `profileAutoFieldRows` / `profileToggleField`)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileSheetEditorSheet(
    card: MyProducerCard,
    materials: ProfileSheetMaterials,
    onSave: suspend (ProfileSheet) -> Unit,
    onDismiss: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val styles = remember { profileSheetStyles() }
    val sizes = remember { profileSheetSizes() }
    val original = remember(card) { card.profile }
    val previewCapture = rememberShareCardCapture()

    var sheet by remember { mutableStateOf(original) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }

    val canSave = !isSaving
    val isDirty = sheet != original

    fun cancel() {
        if (isDirty) confirmDiscard = true else onDismiss()
    }

    fun save() {
        isSaving = true
        scope.launch {
            try {
                onSave(sheet)
                onDismiss()
            } catch (e: Exception) {
                error = "保存できませんでした。${e.message.orEmpty()}"
            } finally {
                isSaving = false
            }
        }
    }

    // 書きかけを指で払って消さない (iOS `interactiveDismissDisabled(isDirty)`)。
    val dirtyNow by rememberUpdatedState(isDirty)
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = remember { { value: SheetValue -> value != SheetValue.Hidden || !dirtyNow } }
    )
    ModalBottomSheet(onDismissRequest = ::cancel, sheetState = sheetState, containerColor = DS.bg) {
        Box {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(
                    ImasSheetToolbarKind.Edit(canSave = canSave, isSaving = isSaving, onCancel = ::cancel, onSave = ::save),
                    title = "プロフィール帳を編集"
                )
                Column(
                    Modifier.padding(horizontal = DS.Space.screen),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.section)
                ) {
                    val layout = profileSheetLayout(sheet, materials.record)
                    ProfileSheetPreview(
                        layout, materials, previewCapture,
                        Modifier.semantics { contentDescription = "${layout.title}の見本" }
                    )

                    ImasSection("様式", style = ImasSectionHeaderStyle.SMALL) {
                        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                            ImasSegmented(
                                labels = styles.map { it.label },
                                selection = styles.indexOfFirst { it.style == sheet.style },
                                onSelect = { sheet = sheet.copy(style = styles[it].style) }
                            )
                            ImasSegmented(
                                labels = sizes.map { it.label },
                                captions = sizes.map { it.caption },
                                selection = sizes.indexOfFirst { it.size == sheet.size },
                                onSelect = { sheet = sheet.copy(size = sizes[it].size) }
                            )
                        }
                    }

                    ImasSection(
                        "担当ブランド", style = ImasSectionHeaderStyle.SMALL,
                        footer = "担当と参加した公演のブランドに丸が付いています。押すたびに 丸なし → 丸 → 二重丸 (メイン) の順に変わります。"
                    ) {
                        ImasChipFlow {
                            profileBrandMarks(sheet, materials.record).forEach { mark ->
                                ImasFilterChip(
                                    label = mark.label,
                                    selected = mark.checked,
                                    brand = mark.id,
                                    icon = if (mark.main) Icons.Filled.Star else null,
                                    onClick = { sheet = profileToggleBrand(sheet, materials.record, mark.id) },
                                    contentDescription = listOfNotNull(
                                        mark.label,
                                        when {
                                            mark.main -> "メイン (二重丸)"
                                            mark.checked -> "丸"
                                            else -> "丸なし"
                                        },
                                        "記録から丸が付くブランド".takeIf { mark.fromRecord }
                                    ).joinToString("、")
                                )
                            }
                        }
                    }

                    val rows = profileAutoFieldRows(sheet, materials.record)
                    if (rows.isNotEmpty()) {
                        ImasSection(
                            "載せる記録", style = ImasSectionHeaderStyle.SMALL,
                            footer = "記録のある欄だけ並びます。外した記録は画像に載りません。"
                        ) {
                            ImasCardList {
                                rows.forEach { row ->
                                    ImasToggleRow(
                                        title = row.label,
                                        subtitle = row.value.ifEmpty { null },
                                        isOn = row.shown,
                                        onCheckedChange = { sheet = profileToggleField(sheet, row.field) },
                                        position = ImasRowPosition.FOLLOWING
                                    )
                                }
                            }
                        }
                    }

                    ImasNote("名前・写真・書体・リンク・自分の QR は P名刺のものです。")
                    error?.let {
                        Text(it, style = ImasTextRole.NOTE.style, color = DS.danger)
                    }
                }
            }
            ImasSavingOverlay(isSaving = isSaving, label = "保存中")
        }
    }

    ImasDiscardConfirmation(isPresented = confirmDiscard, onDismiss = { confirmDiscard = false }, onDiscard = {
        confirmDiscard = false
        onDismiss()
    })
}
