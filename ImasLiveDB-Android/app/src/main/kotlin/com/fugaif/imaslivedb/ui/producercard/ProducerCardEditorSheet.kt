package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.ProducerCardField
import com.fugaif.imaslivedb.data.producercard.ProducerCardMyRecord
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasDiscardConfirmation
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormToggle
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.launch
import uniffi.imas_core.CardLink
import uniffi.imas_core.CardLinkKind
import uniffi.imas_core.ProducerCardInput
import uniffi.imas_core.cardLinkKinds
import uniffi.imas_core.normalizeCardLink
import uniffi.imas_core.producerCardInputErrorMessage
import uniffi.imas_core.producerCardLimits
import uniffi.imas_core.validateProducerCard

/** 編集中のリンク 1 本。 */
private data class EditableLink(val id: String = UUID.randomUUID().toString(), val kind: CardLinkKind, val value: String)

/**
 * 自分の P名刺を作る・直す。iOS `ProducerCardEditorView` の移植。書くのは名前・ひとこと・P歴・リンクだけで、
 * 担当と記録の数はアプリの記録から入る (載せたくない項目はここで外す)。
 *
 * 入力の検査・リンクの正規化はコア (`validateProducerCard` / `normalizeCardLink`)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProducerCardEditorSheet(
    card: MyProducerCard,
    record: ProducerCardMyRecord?,
    onSave: suspend (MyProducerCard) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val limits = remember { producerCardLimits() }
    val kinds = remember { cardLinkKinds() }
    val scope = rememberCoroutineScope()

    var name by remember { mutableStateOf(card.name) }
    var message by remember { mutableStateOf(card.message) }
    var sinceYear by remember { mutableStateOf(card.sinceYear) }
    val links = remember { mutableStateListOf(*card.links.map { EditableLink(kind = it.kind, value = it.value) }.toTypedArray()) }
    var hidden by remember { mutableStateOf(card.hidden) }
    var oshi by remember { mutableStateOf<List<Idol>>(emptyList()) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }

    LaunchedEffect(record) {
        val ids = record?.oshiIds?.take(limits.maxOshi.toInt()).orEmpty()
        if (ids.isEmpty()) return@LaunchedEffect
        val byId = module.idolRepository.fetchIdolsByIds(ids).associateBy { it.id }
        oshi = ids.mapNotNull { byId[it] }
    }

    fun filled() = links.filter { it.value.isNotBlank() }
    fun draft(): MyProducerCard = card.copy(
        name = name.trim(),
        message = message.trim(),
        sinceYear = sinceYear
    ).withLinks(filled().mapNotNull { normalizeCardLink(CardLink(it.kind, it.value)) }).withHidden(hidden)

    val validation = validateProducerCard(
        ProducerCardInput(
            name = name, message = message, sinceYear = null, oshiIdolIds = emptyList(),
            links = filled().map { CardLink(it.kind, it.value) },
            showCount = null, songCount = null, nextShowId = null, attended = emptyList(),
            issuedOn = com.fugaif.imaslivedb.data.model.JstDay.today()
        )
    )
    val canSave = validation == null && !isSaving
    val isDirty = name != card.name || message != card.message || sinceYear != card.sinceYear ||
        hidden != card.hidden || draft().linksJson != card.linksJson

    fun cancel() {
        if (isDirty) confirmDiscard = true else onDismiss()
    }

    fun save() {
        if (validation != null) {
            error = producerCardInputErrorMessage(validation)
            return
        }
        isSaving = true
        scope.launch {
            try {
                onSave(draft())
                onDismiss()
            } catch (e: Exception) {
                error = "保存できませんでした。${e.message.orEmpty()}"
            } finally {
                isSaving = false
            }
        }
    }

    // 書きかけを指で払って消さない (iOS `interactiveDismissDisabled(isDirty)`)。
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { !isDirty }
    )
    ModalBottomSheet(onDismissRequest = ::cancel, sheetState = sheetState, containerColor = DS.bg) {
        Box {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(
                    ImasSheetToolbarKind.Edit(canSave = canSave, isSaving = isSaving, onCancel = ::cancel, onSave = ::save),
                    title = if (card.name.isEmpty()) "P名刺を作る" else "P名刺を編集"
                )
                Column(
                    Modifier.padding(horizontal = DS.Space.screen),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
                ) {
                    ImasFormCard {
                        ImasFormTextField(
                            label = "名前", imprint = "NAME", text = name, onTextChange = { name = it },
                            prompt = "ふがP",
                            error = if (name.length > limits.maxNameChars.toInt()) "${limits.maxNameChars}文字までです" else null,
                            isTitle = true
                        )
                        ImasFormTextArea(
                            label = "ひとこと", imprint = "MESSAGE", icon = null, text = message,
                            onTextChange = { message = it }, prompt = "現地派・ライブ皆勤目指してます",
                            limit = limits.maxMessageChars.toInt()
                        )
                        ImasFormField(label = "P歴の始まり", imprint = "SINCE") {
                            YearPicker(selected = sinceYear, onSelect = { sinceYear = it })
                        }
                    }

                    ImasFormCard {
                        ImasFormField(label = "担当 · アプリから", imprint = "OSHI") {
                            if (oshi.isEmpty()) {
                                Text("アイドル詳細で「担当」を付けると、ここに入ります", style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
                            } else {
                                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                                    oshi.forEach { idol ->
                                        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                                            ImasAvatar(
                                                label = idol.shortName, seed = idol.color, brand = idol.brandId,
                                                size = DS.Size.avatarSmall, isPick = true, entityId = idol.id
                                            )
                                            Text(idol.name, style = ImasTextRole.ROW_TITLE.style, color = DS.ink)
                                        }
                                    }
                                }
                            }
                        }
                        FieldToggle(ProducerCardField.OSHI, "担当を載せる", null, hidden) { hidden = it }
                    }

                    ImasFormCard {
                        ImasFormField(label = "リンク", imprint = "LINKS") {
                            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                                links.forEachIndexed { index, link ->
                                    val info = kinds.firstOrNull { it.kind == link.kind }
                                    LinkEditor(
                                        label = info?.label.orEmpty(),
                                        placeholder = info?.placeholder.orEmpty(),
                                        link = link,
                                        onChange = { links[index] = link.copy(value = it) },
                                        onRemove = { links.removeAll { it.id == link.id } }
                                    )
                                }
                                if (links.size < limits.maxLinks.toInt()) {
                                    AddLinkMenu(kinds.map { it.label to it.kind }) { kind -> links.add(EditableLink(kind = kind, value = "")) }
                                }
                            }
                        }
                        FieldToggle(ProducerCardField.LINKS, "リンクを載せる", null, hidden) { hidden = it }
                    }

                    val summary = record?.summary
                    ImasFormCard {
                        FieldToggle(
                            ProducerCardField.SHOW_COUNT, "参加公演数",
                            summary?.let { "${ProducerCardDisplay.number(it.showCount.toLong())} 公演" }, hidden
                        ) { hidden = it }
                        FieldToggle(
                            ProducerCardField.SONG_COUNT, "回収曲数",
                            record?.let { "${ProducerCardDisplay.number(it.songCount.toLong())} 曲" }, hidden
                        ) { hidden = it }
                        FieldToggle(
                            ProducerCardField.NEXT, "次の現場",
                            if (summary?.nextShowId == null) "参加予定なし" else null, hidden
                        ) { hidden = it }
                        FieldToggle(ProducerCardField.ATTENDED, "参加した公演の一覧", "共通点を出すのに使う", hidden) { hidden = it }
                    }

                    error?.let { Text(it, style = ImasTextRole.NOTE.style, color = DS.danger) }
                    ImasNote("名刺の中身は QR に全部入ります。サーバには何も置かないので、圏外の会場でも交換できます。後から名刺を直しても、相手の手元の名刺は交換したときのままです。")
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

@Composable
private fun FieldToggle(
    field: ProducerCardField,
    title: String,
    value: String?,
    hidden: Set<ProducerCardField>,
    onChange: (Set<ProducerCardField>) -> Unit
) {
    ImasFormToggle(
        label = value?.let { "${field.label} · $it" } ?: field.label,
        title = title,
        isOn = field !in hidden,
        onCheckedChange = { on -> onChange(if (on) hidden - field else hidden + field) }
    )
}

@Composable
private fun YearPicker(selected: Int?, onSelect: (Int?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val years = remember { (LocalDate.now().year.coerceAtLeast(2005) downTo 2005).toList() }
    Box {
        Text(
            selected?.let { "${it}年" } ?: "載せない",
            style = ImasTextRole.VALUE.style,
            color = DS.ink,
            modifier = Modifier.imasRowPress(onClick = { open = true })
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text("載せない") }, onClick = { open = false; onSelect(null) })
            years.forEach { year ->
                DropdownMenuItem(text = { Text("${year}年") }, onClick = { open = false; onSelect(year) })
            }
        }
    }
}

@Composable
private fun AddLinkMenu(kinds: List<Pair<String, CardLinkKind>>, onAdd: (CardLinkKind) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.imasRowPress(onClick = { open = true }),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = DS.ink)
            Text("リンクを足す", style = ImasTextRole.ROW_LABEL.style, color = DS.ink)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            kinds.forEach { (label, kind) ->
                DropdownMenuItem(text = { Text(label) }, onClick = { open = false; onAdd(kind) })
            }
        }
    }
}

@Composable
private fun LinkEditor(
    label: String,
    placeholder: String,
    link: EditableLink,
    onChange: (String) -> Unit,
    onRemove: () -> Unit
) {
    val invalid = link.value.isNotBlank() && normalizeCardLink(CardLink(link.kind, link.value)) == null
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = ImasTextRole.VALUE.style, color = DS.ink2)
            val ink = DS.ink
            BasicTextField(
                value = link.value,
                onValueChange = onChange,
                singleLine = true,
                textStyle = ImasTextRole.VALUE.style.copy(color = ink),
                cursorBrush = SolidColor(ink),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Uri
                ),
                modifier = Modifier.weight(1f),
                decorationBox = { inner ->
                    Box {
                        if (link.value.isEmpty()) Text(placeholder, style = ImasTextRole.VALUE.style, color = DS.ink3)
                        inner()
                    }
                }
            )
            ImasIconButton(
                icon = Icons.Filled.RemoveCircleOutline,
                label = "${label.ifEmpty { "リンク" }}を外す",
                onClick = onRemove,
                size = ImasIconButtonSize.SMALL,
                style = ImasIconButtonStyle.PLAIN
            )
        }
        if (invalid) Text("リンクの書き方を確かめてください", style = ImasTextRole.NOTE.style, color = DS.danger)
    }
}
