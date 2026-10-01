package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasBackdrop
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasBackdrop
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics

// =============================================================================
// シート・フォーム・一覧のまわり (docs/DESIGN_SYSTEM.md §2.1・§2.4〜§2.7・§16)。iOS `ImasSheets.swift` の移植。
//
// ImasSheetToolbar            シートのボタンの置き場所を 1 か所で決める。文字は書かず × と ✓ の記号。
//                             読み上げは言葉で (iOS `.imasSheetToolbar(_:)`)。
// ImasFormBackdrop            編集シート・設定の地 (iOS `.imasForm()`)。
// ImasListBackdrop            「もの」の一覧の地 (iOS `.imasList()`)。
// ImasDiscardConfirmation     書きかけを閉じるときの確認。
// ImasTextFieldRow            フォームの 1 行入力 (項目名 + 入力 + 誤り)。
// ImasTextAreaRow             フォームの複数行の入力。
// ImasListSection             一覧・フォームの区画 (見出し・補足を DS の形で。行の間の線は区画が引く)。
// ImasFilterBar               一覧の頭に、効いている絞り込みを外せるチップで並べる。
// ImasListSummary             一覧の件数と並び順。
// ImasSelectionTray           複数選択で選んだものを下に並べる。
// =============================================================================

// MARK: - シートのボタン

/** シートの種類 (iOS `ImasSheetToolbarKind`)。種類ごとに左右のボタンの意味が決まっている (§16)。 */
sealed interface ImasSheetToolbarKind {
    /** 編集・追加。左 = キャンセル、右 = 保存。 */
    data class Edit(val canSave: Boolean = true, val onCancel: () -> Unit, val onSave: () -> Unit) : ImasSheetToolbarKind

    /**
     * 投稿・投票・修正リクエスト (みんなに見える)。左 = キャンセル、右 = 送信。
     * [isSubmitting] の間は送信の記号の代わりにくるくるを出し、連打できないようにする。
     */
    data class Submit(
        val canSubmit: Boolean = true,
        val isSubmitting: Boolean = false,
        val onCancel: () -> Unit,
        val onSubmit: () -> Unit
    ) : ImasSheetToolbarKind

    /** 複数を選ぶ。左 = キャンセル、右 = 完了。 */
    data class Select(val canFinish: Boolean = true, val onCancel: () -> Unit, val onFinish: () -> Unit) : ImasSheetToolbarKind

    /** 読むだけ。右 = 閉じる。 */
    data class Read(val onClose: () -> Unit) : ImasSheetToolbarKind

    /** 後で答えてよい問いかけ (チケット代の記録など)。左 = あとで、右 = 記録する (§16)。 */
    data class Prompt(val canRecord: Boolean = true, val onLater: () -> Unit, val onRecord: () -> Unit) : ImasSheetToolbarKind
}

private enum class SheetButtonRole { CANCEL, CONFIRM, CLOSE }

/**
 * シートの頭の帯 (iOS `.imasSheetToolbar(_:)`)。左右のボタンの文言と置き場所は種類が決める。
 * 画面で「閉じる」「完了」を書かない。ボタンは記号 (× / ✓) だけで、言葉は読み上げに使う。
 * iOS 26 のガラスの丸に合わせ、記号は丸の中に置く (確定は墨で塗る)。
 *
 * @param title シートの題 (iOS のナビバーの題)。真ん中に出す。
 */
@Composable
fun ImasSheetToolbar(kind: ImasSheetToolbarKind, modifier: Modifier = Modifier, title: String? = null) {
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .padding(horizontal = DS.Space.gap)
    ) {
        if (title != null) {
            Text(
                title,
                style = ImasType.heading(17.sp, FontWeight.Bold),
                color = DS.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(horizontal = 56.dp)
                    .semantics { heading() }
            )
        }
        val leading: (@Composable () -> Unit)?
        val trailing: @Composable () -> Unit
        when (kind) {
            is ImasSheetToolbarKind.Edit -> {
                leading = { SheetButton("キャンセル", SheetButtonRole.CANCEL, onClick = kind.onCancel) }
                trailing = { SheetButton("保存", SheetButtonRole.CONFIRM, enabled = kind.canSave, onClick = kind.onSave) }
            }
            is ImasSheetToolbarKind.Submit -> {
                leading = { SheetButton("キャンセル", SheetButtonRole.CANCEL, onClick = kind.onCancel) }
                trailing = {
                    SheetButton(
                        "送信",
                        SheetButtonRole.CONFIRM,
                        enabled = kind.canSubmit && !kind.isSubmitting,
                        isLoading = kind.isSubmitting,
                        onClick = kind.onSubmit
                    )
                }
            }
            is ImasSheetToolbarKind.Select -> {
                leading = { SheetButton("キャンセル", SheetButtonRole.CANCEL, onClick = kind.onCancel) }
                trailing = { SheetButton("完了", SheetButtonRole.CONFIRM, enabled = kind.canFinish, onClick = kind.onFinish) }
            }
            is ImasSheetToolbarKind.Read -> {
                leading = null
                trailing = { SheetButton("閉じる", SheetButtonRole.CLOSE, onClick = kind.onClose) }
            }
            is ImasSheetToolbarKind.Prompt -> {
                leading = { SheetButton("あとで", SheetButtonRole.CANCEL, onClick = kind.onLater) }
                trailing = { SheetButton("記録する", SheetButtonRole.CONFIRM, enabled = kind.canRecord, onClick = kind.onRecord) }
            }
        }
        if (leading != null) Box(Modifier.align(Alignment.CenterStart)) { leading() }
        Box(Modifier.align(Alignment.CenterEnd)) { trailing() }
    }
}

/** シートのボタン 1 つ。文字は書かず記号 (× / ✓) だけ。[title] は読み上げに使う。 */
@Composable
private fun SheetButton(
    title: String,
    role: SheetButtonRole,
    enabled: Boolean = true,
    isLoading: Boolean = false,
    onClick: () -> Unit
) {
    val confirm = role == SheetButtonRole.CONFIRM
    val fill = when {
        confirm && enabled -> DS.sys
        else -> DS.fill
    }
    val tint = when {
        confirm && enabled -> DS.onSys
        !enabled -> DS.ink3
        else -> DS.ink
    }
    Box(
        Modifier
            .size(DS.Size.touch)
            .clearAndSetSemantics {
                contentDescription = title
                this.role = Role.Button
                if (!enabled) disabled()
                if (enabled) onClick { onClick(); true }
            }
            .imasPress(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Box(
            Modifier
                .size(38.dp)
                .background(fill, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (isLoading) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), color = DS.ink2, strokeWidth = 2.dp)
            } else {
                Icon(
                    if (confirm) Icons.Filled.Check else Icons.Filled.Close,
                    contentDescription = null,
                    tint = tint,
                    modifier = Modifier.size(with(LocalDensity.current) { 19.sp.toDp() })
                )
            }
        }
    }
}

// MARK: - 地

/**
 * 編集シート・設定の地 (iOS `.imasForm()`)。地の色と、中の部品に「フォームの上」を伝える。
 * 中に [ImasListSection] を並べる (行の面と線は区画が持つ)。
 */
@Composable
fun ImasFormBackdrop(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    CompositionLocalProvider(LocalImasBackdrop provides ImasBackdrop.GROUPED) {
        Box(modifier.background(DS.bg), content = content)
    }
}

/**
 * 曲・ライブ・アイドルなど「もの」の一覧の地 (iOS `.imasList()`)。白い紙面に行を並べ、線は本文の頭から。
 */
@Composable
fun ImasListBackdrop(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    CompositionLocalProvider(LocalImasBackdrop provides ImasBackdrop.PAPER) {
        Box(modifier.background(DS.paper), content = content)
    }
}

/**
 * 書きかけのまま閉じようとしたときに確かめる (iOS `.imasDiscardConfirmation`)。
 * [isPresented] が true の間だけ出る。閉じる操作 (× と戻る) を、書きかけがあるときだけここへ回す。
 */
@Composable
fun ImasDiscardConfirmation(isPresented: Boolean, onDismiss: () -> Unit, onDiscard: () -> Unit) {
    ImasConfirmDestructive(
        title = "変更を破棄しますか？",
        isPresented = isPresented,
        onDismiss = onDismiss,
        onConfirm = onDiscard,
        actionTitle = "変更を破棄",
        dismissTitle = "編集を続ける"
    )
}

// MARK: - フォームの行

/** 行の入力 (飾りの無い入力。誘いの文は空のときだけ灰色で)。 */
@Composable
private fun RowInput(
    text: String,
    onTextChange: (String) -> Unit,
    prompt: String,
    label: String,
    modifier: Modifier = Modifier,
    textAlign: TextAlign = TextAlign.Start,
    singleLine: Boolean = true,
    minLines: Int = 1,
    maxLines: Int = Int.MAX_VALUE,
    keyboardType: KeyboardType = KeyboardType.Text,
    style: TextStyle
) {
    var field by remember { mutableStateOf(TextFieldValue(text, TextRange(text.length))) }
    if (field.text != text) field = TextFieldValue(text, TextRange(text.length))
    val ink = DS.ink
    BasicTextField(
        value = field,
        onValueChange = {
            field = it
            if (it.text != text) onTextChange(it.text)
        },
        modifier = modifier.semantics { contentDescription = label },
        textStyle = style.copy(color = ink, textAlign = textAlign),
        singleLine = singleLine,
        minLines = minLines,
        maxLines = if (singleLine) 1 else maxLines,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        cursorBrush = SolidColor(ink),
        decorationBox = { inner ->
            Box(contentAlignment = if (textAlign == TextAlign.End) Alignment.CenterEnd else Alignment.TopStart) {
                if (text.isEmpty()) {
                    Text(prompt, style = style.copy(textAlign = textAlign), color = DS.ink3, modifier = Modifier.fillMaxWidth())
                }
                inner()
            }
        }
    )
}

/**
 * フォームの 1 行入力 (iOS `ImasTextFieldRow`)。項目名 + 入力 (右寄せ) + 誤りの文。
 *
 * @param error 入力の下に出す誤り (「URL の形になっていません」)。null なら出さない。
 */
@Composable
fun ImasTextFieldRow(
    title: String,
    text: String,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    prompt: String? = null,
    error: String? = null,
    keyboardType: KeyboardType = KeyboardType.Text
) {
    Column(
        modifier
            .fillMaxWidth()
            .heightIn(min = DS.Size.touch)
            .padding(horizontal = DS.Space.rowH, vertical = 11.dp),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap), verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = ImasTextRole.VALUE.style, color = DS.ink2, maxLines = 1, modifier = Modifier.clearAndSetSemantics { })
            RowInput(
                text = text,
                onTextChange = onTextChange,
                prompt = prompt ?: title,
                label = title,
                modifier = Modifier.weight(1f),
                textAlign = TextAlign.End,
                keyboardType = keyboardType,
                style = ImasTextRole.VALUE.style
            )
        }
        if (error != null) {
            Text(error, style = ImasType.text(13.sp), color = DS.danger)
        }
    }
}

/**
 * 複数行の入力 (iOS `ImasTextAreaRow`。メモ・説明・補足)。
 *
 * @param minLines 行数の下限。既定は 4 行分の高さを確保する (メモ・感想などの長文)。
 * @param maxLines 行数の上限。null なら上限なし (打つだけ伸びる)。座席のような短い欄は上限を決める。
 * @param limit 文字数の上限。null なら数えない。数えるときは前後の空白・改行を除く
 *   (送信を止める条件と同じ数え方。生の数だと改行だけ打った分でずれる)。
 * @param count 数え方を呼び出し側が決めるとき (サーバと同じ数え方はコアの `inputLength`)。
 */
@Composable
fun ImasTextAreaRow(
    text: String,
    onTextChange: (String) -> Unit,
    prompt: String,
    modifier: Modifier = Modifier,
    minHeight: Dp = 120.dp,
    minLines: Int = 4,
    maxLines: Int? = null,
    limit: Int? = null,
    count: Int? = null
) {
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = DS.Space.rowH, vertical = 11.dp),
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        RowInput(
            text = text,
            onTextChange = onTextChange,
            prompt = prompt,
            label = prompt,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = minHeight),
            singleLine = false,
            minLines = minLines,
            maxLines = maxLines ?: Int.MAX_VALUE,
            style = ImasTextRole.BODY.style
        )
        if (limit != null) {
            val n = count ?: graphemeCount(text.trim())
            Text(
                "$n / $limit",
                style = ImasType.text(12.sp).copy(fontFeatureSettings = "tnum"),
                color = if (n > limit) DS.danger else DS.ink3
            )
        }
    }
}

// MARK: - 一覧・フォームの区画

/**
 * 一覧・フォームの区画 (iOS `ImasListSection`)。見出しは DS の小さい見出し、補足は [ImasNote]。
 * 行の面と行の間の線は区画が持つ (iOS の List と同じ。中の行は位置を気にしない)。
 *
 * フォームの地 ([ImasFormBackdrop]・既定) では角の丸い面に入れ、一覧の地 ([ImasListBackdrop]) では
 * 紙面にそのまま並べる。
 */
@Composable
fun ImasListSection(
    title: String? = null,
    modifier: Modifier = Modifier,
    count: String? = null,
    footer: String? = null,
    content: @Composable () -> Unit
) {
    val paper = LocalImasBackdrop.current == ImasBackdrop.PAPER
    val sep = DS.sep
    val inset = DS.Space.rowH
    val rows: @Composable (Modifier) -> Unit = { m ->
        // 行の位置は区画が線を引くので伝えない (行は自分で線を引かない)。
        CompositionLocalProvider(LocalImasRowPosition provides ImasRowPosition.STANDALONE) {
            SeparatedColumn(m, sep, inset, content)
        }
    }
    if (paper) {
        Column(modifier.fillMaxWidth()) {
            if (title != null) ImasSectionHeader(title, count = count, style = ImasSectionHeaderStyle.SMALL)
            rows(Modifier.fillMaxWidth().background(DS.paper))
            if (footer != null) {
                ImasNote(footer, Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.note))
            }
        }
    } else {
        val shape = RoundedCornerShape(DS.rCard)
        Column(
            modifier
                .fillMaxWidth()
                .padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
        ) {
            if (title != null) {
                ImasSectionHeader(
                    title,
                    count = count,
                    style = ImasSectionHeaderStyle.SMALL,
                    contentPadding = PaddingValues(start = DS.Space.rowH, end = DS.Space.rowH, bottom = DS.Space.header)
                )
            }
            rows(Modifier.fillMaxWidth().imasSurface(shape).clip(shape))
            if (footer != null) {
                ImasNote(footer, Modifier.padding(start = DS.Space.rowH, end = DS.Space.rowH, top = DS.Space.note))
            }
        }
    }
}

/** 子を縦に並べ、2 つ目からの上に細い線を引く (線は左の [inset] から)。 */
@Composable
private fun SeparatedColumn(modifier: Modifier, color: Color, inset: Dp, content: @Composable () -> Unit) {
    // 置いた行の上端。並べるたびに書き、描くときに読む (変わったときだけ描き直す)。
    var tops by remember { mutableStateOf(IntArray(0)) }
    Layout(
        content = content,
        modifier = modifier.drawWithContent {
            drawContent()
            val x = inset.toPx()
            for (i in 1 until tops.size) {
                drawRect(color, topLeft = Offset(x, tops[i].toFloat()), size = Size(size.width - x, 1f))
            }
        }
    ) { measurables, constraints ->
        val loose = constraints.copy(minHeight = 0)
        val placeables = measurables.map { it.measure(loose) }
        val height = placeables.sumOf { it.height }.coerceIn(constraints.minHeight, constraints.maxHeight)
        layout(constraints.maxWidth, height) {
            val next = IntArray(placeables.size)
            var y = 0
            placeables.forEachIndexed { i, p ->
                next[i] = y
                p.placeRelative(0, y)
                y += p.height
            }
            if (!next.contentEquals(tops)) tops = next
        }
    }
}

// MARK: - 一覧の頭

/** 効いている絞り込み 1 つ (iOS `ImasFilterBar.Item`)。 */
@Immutable
data class ImasFilterBarItem(
    val id: String,
    val title: String,
    val seed: String? = null,
    val brand: String? = null,
    val onRemove: () -> Unit
)

/**
 * 効いている絞り込みを外せるチップで 1 段に並べる (iOS `ImasFilterBar`)。何も効いていなければ何も出さない。
 *
 * @param onClearAll 2 つ以上効いているときに「すべて解除」を出す。
 */
@Composable
fun ImasFilterBar(items: List<ImasFilterBarItem>, modifier: Modifier = Modifier, onClearAll: (() -> Unit)? = null) {
    if (items.isEmpty()) return
    ImasChipRow(modifier.padding(vertical = DS.Space.gapTight)) {
        items.forEach { item ->
            ImasRemovableChip(text = item.title, onRemove = item.onRemove, seed = item.seed, brand = item.brand)
        }
        if (items.size >= 2 && onClearAll != null) {
            ImasButton(title = "すべて解除", onClick = onClearAll, role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL)
        }
    }
}

/**
 * 一覧の件数と並び順 (iOS `ImasListSummary`)。並び順は押すと出るメニューで選ぶ。
 *
 * @param sortAscending 昇順・降順の向き (任意)。渡すとメニューに「方向」が増え、ボタンの記号もその向きになる。
 *   渡さなければ軸の切り替えだけ (上下の矢印)。
 */
@Composable
fun <T> ImasListSummary(
    count: Int,
    modifier: Modifier = Modifier,
    unit: String = "件",
    sortOptions: List<T> = emptyList(),
    sortSelection: T? = null,
    onSortChange: ((T) -> Unit)? = null,
    sortLabel: (T) -> String = { it.toString() },
    sortAscending: Boolean? = null,
    onSortAscendingChange: ((Boolean) -> Unit)? = null
) {
    val haptics = rememberImasHaptics()
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasMetric("$count", unit = unit, size = ImasNumeralSize.SMALL)
        Spacer(Modifier.weight(1f).widthIn(min = DS.Space.gap))
        if (sortSelection != null && onSortChange != null && sortOptions.isNotEmpty()) {
            var open by remember { mutableStateOf(false) }
            val spoken = buildString {
                append("並び替え: ").append(sortLabel(sortSelection))
                if (sortAscending != null) append("、").append(if (sortAscending) "昇順" else "降順")
            }
            Box {
                val shape = RoundedCornerShape(DS.rControl(DS.Size.chip))
                Row(
                    Modifier
                        .clearAndSetSemantics {
                            contentDescription = spoken
                            role = Role.Button
                            onClick { open = true; true }
                        }
                        .imasPress { open = true }
                        .heightIn(min = DS.Size.chip)
                        .border(1.dp, DS.line, shape)
                        .padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val icon: ImageVector = when (sortAscending) {
                        null -> Icons.Filled.SwapVert
                        true -> Icons.Filled.ArrowUpward
                        false -> Icons.Filled.ArrowDownward
                    }
                    Icon(icon, contentDescription = null, tint = DS.ink, modifier = Modifier.size(with(LocalDensity.current) { 14.sp.toDp() }))
                    Text(sortLabel(sortSelection), style = ImasType.text(13.sp, FontWeight.SemiBold), color = DS.ink, maxLines = 1)
                }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    sortOptions.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(sortLabel(option), color = DS.ink) },
                            trailingIcon = if (option == sortSelection) {
                                { Icon(Icons.Filled.Check, contentDescription = null, tint = DS.ink) }
                            } else null,
                            onClick = {
                                open = false
                                if (option != sortSelection) {
                                    haptics.selection()
                                    onSortChange(option)
                                }
                            }
                        )
                    }
                    if (sortAscending != null && onSortAscendingChange != null) {
                        HorizontalDivider(color = DS.sep)
                        listOf(true to "昇順", false to "降順").forEach { (asc, text) ->
                            DropdownMenuItem(
                                text = { Text(text, color = DS.ink) },
                                leadingIcon = {
                                    Icon(
                                        if (asc) Icons.Filled.ArrowUpward else Icons.Filled.ArrowDownward,
                                        contentDescription = null,
                                        tint = DS.ink2
                                    )
                                },
                                trailingIcon = if (asc == sortAscending) {
                                    { Icon(Icons.Filled.Check, contentDescription = null, tint = DS.ink) }
                                } else null,
                                onClick = {
                                    open = false
                                    if (asc != sortAscending) {
                                        haptics.selection()
                                        onSortAscendingChange(asc)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 選んだもの

/**
 * 複数選択のシートの下に、選んだものを外せるチップで並べる (iOS `ImasSelectionTray`)。
 */
@Composable
fun <T> ImasSelectionTray(
    items: List<T>,
    title: (T) -> String,
    onRemove: (T) -> Unit,
    modifier: Modifier = Modifier,
    seed: (T) -> String? = { null }
) {
    if (items.isEmpty()) return
    val sep = DS.sep
    Column(
        modifier
            .fillMaxWidth()
            .background(DS.surface)
            .drawWithContent {
                drawContent()
                drawRect(sep, size = Size(size.width, 1f))
            }
            .padding(vertical = DS.Space.gap),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        Text(
            "選んだもの ${items.size}",
            style = ImasTextRole.SECTION_LABEL.style,
            color = ImasTextRole.SECTION_LABEL.color,
            modifier = Modifier.padding(horizontal = DS.Space.screen)
        )
        ImasChipRow {
            items.forEach { item ->
                ImasRemovableChip(text = title(item), onRemove = { onRemove(item) }, seed = seed(item))
            }
        }
    }
}
