package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
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
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.producercard.ProfileSheetMaterials
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasDiscardConfirmation
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipe
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeAction
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.share.ProfileSheetPreview
import com.fugaif.imaslivedb.ui.share.rememberShareCardCapture
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.launch
import uniffi.imas_core.ProfileAutoField
import uniffi.imas_core.ProfileSheet
import uniffi.imas_core.profileAutoFields
import uniffi.imas_core.profileBrandMarks
import uniffi.imas_core.profileSheetErrorMessage
import uniffi.imas_core.profileSheetLayout
import uniffi.imas_core.profileSheetLimits
import uniffi.imas_core.profileSheetSizes
import uniffi.imas_core.profileSheetStyles
import uniffi.imas_core.profileToggleBrand
import uniffi.imas_core.validateProfileSheet

/**
 * プロフィール帳を直す。iOS `ProfileSheetEditorView` の移植。上に出来上がりの見本 (その場で変わる)、下に欄の一覧。
 *
 * 様式・大きさ・好きな曲・担当ブランドの丸の付け外し・アプリの記録の付け外し。
 * 一覧・上限・丸の付け外しはコア (`profileSheetStyles` / `profileSheetSizes` / `profileBrandMarks` /
 * `profileToggleBrand` / `validateProfileSheet`)。
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
    val limits = remember { profileSheetLimits() }
    val styles = remember { profileSheetStyles() }
    val sizes = remember { profileSheetSizes() }
    val autoFields = remember { profileAutoFields() }
    val original = remember(card) { card.profile }
    val previewCapture = rememberShareCardCapture()

    var sheet by remember { mutableStateOf(original) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var pickingSongs by remember { mutableStateOf(false) }

    val validation = validateProfileSheet(sheet)
    val canSave = validation == null && !isSaving
    val isDirty = sheet != original

    fun cancel() {
        if (isDirty) confirmDiscard = true else onDismiss()
    }

    fun save() {
        validation?.let {
            error = profileSheetErrorMessage(it)
            return
        }
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
                    val current = materials.withFavoriteSongIds(sheet.favoriteSongIds)
                    val layout = profileSheetLayout(sheet, current.record)
                    ProfileSheetPreview(
                        layout, current, previewCapture,
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
                        "好きな曲", style = ImasSectionHeaderStyle.SMALL,
                        count = "${sheet.favoriteSongIds.size} / ${limits.maxSongs}",
                        footer = "お気に入りの曲から選びます。左に引いて外します。"
                    ) {
                        ImasCardList {
                            sheet.favoriteSongIds.forEach { id ->
                                ImasSwipe(
                                    trailing = listOf(
                                        ImasSwipeAction(kind = ImasSwipeKind.DELETE, title = "外す", action = {
                                            sheet = sheet.copy(favoriteSongIds = sheet.favoriteSongIds - id)
                                        })
                                    ),
                                    background = DS.surface
                                ) {
                                    ImasRow(
                                        title = materials.songTitles[id] ?: "見つからない曲",
                                        density = ImasRowDensity.COMPACT,
                                        titleRole = ImasTextRole.ROW_LABEL,
                                        position = ImasRowPosition.FOLLOWING,
                                        modifier = Modifier.background(DS.surface)
                                    )
                                }
                            }
                            ImasNavRow(
                                title = "曲を選ぶ",
                                subtitle = if (materials.favoriteCandidates.isEmpty()) "曲の詳細で ★ を付けると、ここから選べます" else null,
                                icon = Icons.AutoMirrored.Filled.QueueMusic,
                                position = ImasRowPosition.FOLLOWING,
                                onClick = if (materials.favoriteCandidates.isEmpty()) null else ({ pickingSongs = true })
                            )
                        }
                    }

                    ImasSection(
                        "担当ブランド", style = ImasSectionHeaderStyle.SMALL,
                        footer = "担当と参加した公演のブランドに丸が付いています。押すと付け外しできます。"
                    ) {
                        ImasChipFlow {
                            profileBrandMarks(sheet, materials.record).forEach { mark ->
                                ImasFilterChip(
                                    label = mark.label,
                                    selected = mark.checked,
                                    brand = mark.id,
                                    onClick = { sheet = profileToggleBrand(sheet, materials.record, mark.id) },
                                    contentDescription = if (mark.fromRecord) "${mark.label}、記録から丸が付くブランド" else null
                                )
                            }
                        }
                    }

                    ImasSection(
                        "アプリの記録から", style = ImasSectionHeaderStyle.SMALL,
                        footer = "外した記録は画像に載りません。"
                    ) {
                        ImasCardList {
                            autoFields.forEach { info ->
                                ImasToggleRow(
                                    title = info.label,
                                    isOn = info.field !in sheet.hidden,
                                    onCheckedChange = { on -> sheet = sheet.copy(hidden = shown(sheet.hidden, info.field, on)) },
                                    position = ImasRowPosition.FOLLOWING
                                )
                            }
                        }
                    }

                    ImasNote("名前・写真・書体・リンク・自分の QR は P名刺のものです。")
                    (error ?: validation?.let { profileSheetErrorMessage(it) })?.let {
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
    if (pickingSongs) {
        ProfileSongPicker(
            candidates = materials.favoriteCandidates,
            selection = sheet.favoriteSongIds,
            limit = limits.maxSongs.toInt(),
            onChange = { sheet = sheet.copy(favoriteSongIds = it) },
            onDismiss = { pickingSongs = false }
        )
    }
}

/** 載せる記録の付け外し (外したものを [hidden] に持つ)。 */
private fun shown(hidden: List<ProfileAutoField>, field: ProfileAutoField, on: Boolean): List<ProfileAutoField> =
    hidden.filter { it != field } + if (on) emptyList() else listOf(field)

/** 好きな曲を選ぶ (お気に入りの曲から、上限まで。選んだ順に並ぶ)。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileSongPicker(
    candidates: List<Song>,
    selection: List<String>,
    limit: Int,
    onChange: (List<String>) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg
    ) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
            ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = onDismiss), title = "好きな曲")
            ImasSection(
                count = "${selection.size} / $limit", style = ImasSectionHeaderStyle.SMALL,
                footer = "選んだ順に載ります。",
                modifier = Modifier.padding(horizontal = DS.Space.screen)
            ) {
                ImasCardList {
                    candidates.forEach { song ->
                        val selected = song.id in selection
                        ImasSelectableRow(
                            title = song.title,
                            isSelected = selected,
                            isDisabled = !selected && selection.size >= limit,
                            position = ImasRowPosition.FOLLOWING,
                            onClick = {
                                if (selected) onChange(selection - song.id)
                                else if (selection.size < limit) onChange(selection + song.id)
                            }
                        )
                    }
                }
            }
        }
    }
}
