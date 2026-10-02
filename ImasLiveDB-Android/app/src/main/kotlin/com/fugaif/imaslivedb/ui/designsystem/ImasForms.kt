package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.ConfirmationNumber
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.rememberTextMeasurer
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
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import java.text.BreakIterator
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs

// =============================================================================
// 申込書 (編集シートの欄) (docs/DESIGN_SYSTEM.md §2.4・§7)。iOS `ImasForms.swift` の移植。
//
// ImasFormPage       編集シートの本体。地・左右の余白・欄のまとまりの間隔。キーボードは引いて閉じる。
// ImasFormCard       欄をまとめる 1 枚の紙。欄の間は切り取り線。
// ImasFormField      欄 1 つ。上に印字の見出し (「DATE · 日程」)、下に値。誤りは朱で。
// ImasFormTextField  1 行の入力の欄。
// ImasFormTextArea   複数行の入力の欄 (メモ・感想)。
// ImasFormToggle     オン・オフの欄。
// ImasFormLink       押して別のシート・選択へ行く欄 (会場・日程)。値と矢印。
// ImasFormAmount     金額の欄。「¥」と細長い数字。
// ImasChoiceCards    大きな札から 1 つ選ぶ (参加のしかた: 現地・配信・LV)。選んだ札は墨の縁と ✓。
//                    種類: GRID (横に並ぶ等幅の札、既定) / ROW (縦に積む全幅の行、モード選択) /
//                    NUMERAL (大きな数字 + 単位、問題数・時間の選択)。
//
// 設定画面の灰の表は `ImasListSection`。ものを編集するシートはこの申込書で組む。
// =============================================================================

// MARK: - 本体

/**
 * 編集シートの本体 (iOS `ImasFormPage`)。地・左右の余白・欄のまとまりの間隔を持つ。中身は縦に並べる。
 * 指で引いてスクロールし始めたらキーボードを閉じる (iOS `.scrollDismissesKeyboard(.interactively)`)。
 */
@Composable
fun ImasFormPage(
    modifier: Modifier = Modifier,
    scrollState: ScrollState = rememberScrollState(),
    content: @Composable ColumnScope.() -> Unit
) {
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    val dismissOnDrag = remember(keyboard, focus) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput && abs(available.y) > 0f) {
                    keyboard?.hide()
                    focus.clearFocus()
                }
                return Offset.Zero
            }
        }
    }
    CompositionLocalProvider(LocalImasBackdrop provides ImasBackdrop.GROUPED) {
        Box(modifier.fillMaxSize().background(DS.bg)) {
            ReadableWidth { readable ->
                Column(
                    Modifier
                        .fillMaxSize()
                        .nestedScroll(dismissOnDrag)
                        .verticalScroll(scrollState)
                        .padding(readable)
                        .padding(horizontal = DS.Space.screen)
                        .padding(top = DS.Space.gap, bottom = DS.Space.section),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
                    content = content
                )
            }
        }
    }
}

// MARK: - 欄のまとまり

/**
 * 欄をまとめる 1 枚の紙 (iOS `ImasFormCard`)。欄 ([ImasFormField] の仲間) を縦に並べる。欄の間は切り取り線。
 */
@Composable
fun ImasFormCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(DS.rCard)
    Column(
        modifier
            .fillMaxWidth()
            .imasSurface(shape)
            .clip(shape)
            // 欄はそれぞれ上に切り取り線を引く。1 つ目の欄の線 (紙の上端) だけを隠す。
            .drawWithContent {
                clipRect(top = 2.dp.toPx()) { this@drawWithContent.drawContent() }
            },
        content = content
    )
}

// MARK: - 欄

/**
 * 欄 1 つ (iOS `ImasFormField`)。上に印字の見出し、下に値。値は自由に組める (入力・文字・選択)。
 * 中身の文字の既定は見出しの書体 17 の太字・墨。
 *
 * @param imprint 見出しの前の英字 (「DATE」)。日本語の見出しの前に「DATE · 日程」と並ぶ。
 * @param error 欄の下の誤り (「URL の形になっていません」)。
 */
@Composable
fun ImasFormField(
    label: String,
    modifier: Modifier = Modifier,
    imprint: String? = null,
    icon: ImageVector? = null,
    error: String? = null,
    content: @Composable () -> Unit
) {
    val perforation = DS.perforation
    Column(
        modifier
            .fillMaxWidth()
            .drawWithContent {
                drawContent()
                // 上の切り取り線 (左の余白から)。
                drawImasDash(
                    start = Offset(16.dp.toPx(), 0.5.dp.toPx()),
                    end = Offset(size.width, 0.5.dp.toPx()),
                    color = perforation,
                    width = 1.dp.toPx()
                )
            }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            Modifier.clearAndSetSemantics { },
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (icon != null) {
                Icon(icon, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(with(LocalDensity.current) { 12.sp.toDp() }))
            }
            Text(
                listOfNotNull(imprint, label).joinToString(" · "),
                style = ImasTextRole.IMPRINT.style,
                color = DS.ink2,
                maxLines = 1
            )
        }
        CompositionLocalProvider(
            LocalTextStyle provides ImasType.heading(17.sp, FontWeight.Bold),
            LocalContentColor provides DS.ink
        ) {
            content()
        }
        if (error != null) {
            Text(error, style = ImasType.text(13.sp, FontWeight.SemiBold), color = DS.danger)
        }
    }
}

/** 欄の入力の地 (飾りの無い 1 行・複数行の入力)。誘いの文は入力が空のときだけ灰色で出す。 */
@Composable
private fun FormInput(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    prompt: String,
    style: TextStyle,
    label: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    minLines: Int = 1,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default
) {
    val ink = DS.ink
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.semantics { contentDescription = label },
        textStyle = style.copy(color = ink),
        singleLine = singleLine,
        minLines = minLines,
        keyboardOptions = keyboardOptions,
        cursorBrush = SolidColor(ink),
        decorationBox = { inner ->
            Box {
                if (value.text.isEmpty()) {
                    Text(prompt, style = style, color = DS.ink3, maxLines = if (singleLine) 1 else Int.MAX_VALUE)
                }
                inner()
            }
        }
    )
}

/** 外から渡された文字と、手元の入力 (選択・変換中の文字を含む) を揃える。 */
@Composable
private fun rememberFieldValue(text: String): androidx.compose.runtime.MutableState<TextFieldValue> {
    val state = remember { mutableStateOf(TextFieldValue(text, TextRange(text.length))) }
    if (state.value.text != text) {
        state.value = TextFieldValue(text, TextRange(text.length))
    }
    return state
}

/**
 * 1 行の入力の欄 (iOS `ImasFormTextField`)。
 *
 * @param isTitle 題の欄 (ライブ名など) は大きく組み、長いときは折り返す。
 * @param limit 文字数の上限。渡すと入力の下に「N / 上限」を出し、超えたら朱にする
 *   (タグ名など、短い 1 行の値で上限を示したい欄)。
 * @param count 数え方を呼び出し側が決めるとき。null なら見た目の文字数 ([graphemeCount])。
 */
@Composable
fun ImasFormTextField(
    label: String,
    text: String,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    imprint: String? = null,
    icon: ImageVector? = null,
    prompt: String? = null,
    error: String? = null,
    keyboardType: KeyboardType = KeyboardType.Text,
    isTitle: Boolean = false,
    limit: Int? = null,
    count: Int? = null
) {
    var field by rememberFieldValue(text)
    ImasFormField(label = label, modifier = modifier, imprint = imprint, icon = icon, error = error) {
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            FormInput(
                value = field,
                onValueChange = {
                    field = it
                    if (it.text != text) onTextChange(it.text)
                },
                prompt = prompt ?: label,
                style = if (isTitle) ImasType.heading(22.sp, FontWeight.ExtraBold) else ImasType.heading(17.sp, FontWeight.Bold),
                label = label,
                modifier = Modifier.fillMaxWidth(),
                singleLine = !isTitle,
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Done)
            )
            if (limit != null) {
                val n = count ?: graphemeCount(text)
                Text("$n / $limit", style = ImasType.mono(11.sp), color = if (n > limit) DS.danger else DS.ink3)
            }
        }
    }
}

/**
 * 複数行の入力の欄 (iOS `ImasFormTextArea`。メモ・感想・説明)。
 *
 * @param limit 文字数の上限。渡すと「N / 上限」を右下に出し、超えたら朱にする。
 * @param count 数え方を呼び出し側が決めるとき (サーバと同じ数え方はコアの `inputLength`)。null なら文字の数。
 * @param autofocus 開いたら自動でキーボードを出す (返信シートなど、すぐ打ち始めてほしい欄)。
 */
@Composable
fun ImasFormTextArea(
    label: String,
    text: String,
    onTextChange: (String) -> Unit,
    prompt: String,
    modifier: Modifier = Modifier,
    imprint: String? = "MEMO",
    icon: ImageVector? = Icons.AutoMirrored.Outlined.Notes,
    limit: Int? = null,
    count: Int? = null,
    autofocus: Boolean = false
) {
    var field by rememberFieldValue(text)
    val focus = remember { FocusRequester() }
    LaunchedEffect(autofocus) { if (autofocus) focus.requestFocus() }
    val minHeight = with(LocalDensity.current) { 88.sp.toDp() }
    ImasFormField(label = label, modifier = modifier, imprint = imprint, icon = icon) {
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            FormInput(
                value = field,
                onValueChange = {
                    field = it
                    if (it.text != text) onTextChange(it.text)
                },
                prompt = prompt,
                style = ImasTextRole.BODY.style,
                label = label,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = minHeight)
                    .focusRequester(focus),
                singleLine = false,
                minLines = 3
            )
            if (limit != null) {
                val n = count ?: graphemeCount(text)
                Text(
                    "$n / $limit",
                    style = ImasType.mono(11.sp),
                    color = if (n > limit) DS.danger else DS.ink3
                )
            }
        }
    }
}

/** 見た目の文字の数 (絵文字や結合文字も 1 つ。iOS の `String.count` と同じ数え方)。 */
internal fun graphemeCount(text: String): Int {
    if (text.isEmpty()) return 0
    val iterator = BreakIterator.getCharacterInstance()
    iterator.setText(text)
    var n = 0
    while (iterator.next() != BreakIterator.DONE) n++
    return n
}

/**
 * オン・オフの欄 (iOS `ImasFormToggle`)。欄のどこを押しても切り替わる。
 *
 * @param title 値の文言 (「開演 1 時間前に知らせる」)。
 */
@Composable
fun ImasFormToggle(
    label: String,
    title: String,
    isOn: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    imprint: String? = null,
    icon: ImageVector? = null
) {
    val haptics = rememberImasHaptics()
    ImasFormField(
        label = label,
        modifier = modifier.toggleable(value = isOn, role = Role.Switch) {
            haptics.selection()
            onCheckedChange(it)
        },
        imprint = imprint,
        icon = icon
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = ImasType.heading(15.sp, FontWeight.SemiBold), color = DS.ink, modifier = Modifier.weight(1f))
            ImasSwitch(checked = isOn, onCheckedChange = null)
        }
    }
}

/**
 * 押して選択・別のシートへ行く欄 (iOS `ImasFormLink`)。値と矢印。値が無いときは灰色の誘い。
 */
@Composable
fun ImasFormLink(
    label: String,
    value: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    imprint: String? = null,
    icon: ImageVector? = null,
    placeholder: String = "選ぶ"
) {
    val shown = value ?: placeholder
    ImasFormField(
        label = label,
        modifier = modifier
            .clearAndSetSemantics {
                contentDescription = "$label、$shown"
                role = Role.Button
                onClick { onClick(); true }
            }
            .imasRowPress(onClick = onClick),
        imprint = imprint,
        icon = icon
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
            Text(shown, color = if (value == null) DS.ink3 else DS.ink, modifier = Modifier.weight(1f))
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = DS.ink3,
                modifier = Modifier.size(with(LocalDensity.current) { 16.sp.toDp() })
            )
        }
    }
}

/** 金額の桁区切り (「9,900」)。 */
private fun formatAmount(amount: Int?): String =
    amount?.let { NumberFormat.getIntegerInstance(Locale.JAPAN).format(it) } ?: ""

/**
 * 金額の欄 (iOS `ImasFormAmount`)。「¥」と細長い数字。入力は数字のキーボード。欄のどこを押しても入力できる。
 * 外から [amount] が書き換わったとき (券種の選び直しなど) も欄が追う。
 *
 * @param note 右に添える補足 (「一般 指定席」)。
 */
@Composable
fun ImasFormAmount(
    label: String,
    amount: Int?,
    onAmountChange: (Int?) -> Unit,
    modifier: Modifier = Modifier,
    imprint: String? = "PRICE",
    icon: ImageVector? = Icons.Outlined.ConfirmationNumber,
    note: String? = null
) {
    var field by remember { mutableStateOf(formatAmount(amount).let { TextFieldValue(it, TextRange(it.length)) }) }
    // 外から amount が変わったら欄を追わせる。自分の入力で既に揃っているときは書き直さない。
    LaunchedEffect(amount) {
        val formatted = formatAmount(amount)
        if (formatted != field.text) field = TextFieldValue(formatted, TextRange(formatted.length))
    }
    val focus = remember { FocusRequester() }
    val style = ImasNumeralSize.LARGE.style
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    // 数字の幅だけの欄にする (iOS `.fixedSize()`)。空なら「0」の幅。
    val width: Dp = with(density) { measurer.measure(field.text.ifEmpty { "0" }, style).size.width.toDp() } + 2.dp
    ImasFormField(label = label, modifier = modifier, imprint = imprint, icon = icon) {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    focus.requestFocus()
                },
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("¥", style = ImasType.heading(18.sp, FontWeight.Bold), color = DS.ink2, modifier = Modifier.alignByBaseline())
            FormInput(
                value = field,
                onValueChange = { next ->
                    val digits = next.text.filter(Char::isDigit)
                    val parsed = digits.toIntOrNull()
                    val formatted = formatAmount(parsed)
                    field = TextFieldValue(formatted, TextRange(formatted.length))
                    if (parsed != amount) onAmountChange(parsed)
                },
                prompt = "0",
                style = style,
                label = label,
                modifier = Modifier
                    .width(width)
                    .alignByBaseline()
                    .focusRequester(focus),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done)
            )
            Spacer(Modifier.weight(1f).widthIn(min = DS.Space.gap))
            if (note != null) {
                Text(note, style = ImasType.text(13.sp), color = DS.ink2, maxLines = 1, modifier = Modifier.alignByBaseline())
            }
        }
    }
}

// MARK: - 大きな札から選ぶ

/** 札の並べ方 (iOS `ImasChoiceCards.Style`)。 */
enum class ImasChoiceCardsStyle {
    /** 横に並ぶ等幅の札 (2〜4 個)。 */
    GRID,

    /** 縦に積む全幅の行 (4 個以上・説明が長いモード選択)。 */
    ROW,

    /** 大きな数字 + 単位だけの札 (問題数・時間の選択)。 */
    NUMERAL
}

/** 札 1 枚 (iOS `ImasChoiceCards.Choice`)。 */
@Immutable
data class ImasChoice<T>(
    val value: T,
    val title: String,
    val icon: ImageVector? = null,
    val subtitle: String? = null
)

/**
 * 大きな札から 1 つ選ぶ (iOS `ImasChoiceCards`。参加のしかた・遊び方の種類)。
 * 選んだ札は紙の面に墨の縁で囲み、右上に ✓。
 *
 * @param hapticsOnExternalChange 既定は true (選択値が変わるたびに触覚、札を押した時も含む)。
 * スライダーなど部品の外から [selection] が連続して変わる画面では false を渡し、
 * 札を押した時だけ触覚を鳴らす (値が動くたびに鳴るのを防ぐ)。
 */
@Composable
fun <T> ImasChoiceCards(
    choices: List<ImasChoice<T>>,
    selection: T,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    style: ImasChoiceCardsStyle = ImasChoiceCardsStyle.GRID,
    hapticsOnExternalChange: Boolean = true
) {
    val haptics = rememberImasHaptics()
    if (hapticsOnExternalChange) {
        var last by remember { mutableStateOf(selection) }
        LaunchedEffect(selection) {
            if (selection != last) {
                last = selection
                haptics.selection()
            }
        }
    }
    val density = LocalDensity.current
    val height = with(density) { 76.sp.toDp() }
    val rowHeight = with(density) { 56.sp.toDp() }
    val onCardSelect: (T) -> Unit = { value ->
        if (!hapticsOnExternalChange) haptics.selection()
        onSelect(value)
    }
    when (style) {
        ImasChoiceCardsStyle.GRID, ImasChoiceCardsStyle.NUMERAL -> Row(
            modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
            verticalAlignment = Alignment.CenterVertically
        ) {
            choices.forEach { choice ->
                ChoiceCard(choice, choice.value == selection, style, height, Modifier.weight(1f)) { onCardSelect(choice.value) }
            }
        }
        ImasChoiceCardsStyle.ROW -> Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            choices.forEach { choice ->
                ChoiceCard(choice, choice.value == selection, style, rowHeight, Modifier.fillMaxWidth()) { onCardSelect(choice.value) }
            }
        }
    }
}

@Composable
private fun <T> ChoiceCard(
    choice: ImasChoice<T>,
    on: Boolean,
    style: ImasChoiceCardsStyle,
    minHeight: Dp,
    modifier: Modifier,
    onClick: () -> Unit
) {
    val shape = RoundedCornerShape(DS.rControl(minHeight) - 6.dp)
    val fg = if (on) DS.ink else DS.ink2
    Box(
        modifier
            .semantics { selected = on }
            .imasPress(onClick = onClick)
            .heightIn(min = minHeight)
            .background(if (on) DS.surface else Color.Transparent, shape)
            .border(if (on) 2.dp else 1.5.dp, if (on) DS.ink else DS.line, shape),
        contentAlignment = Alignment.Center
    ) {
        CompositionLocalProvider(LocalContentColor provides fg) {
            ChoiceLabel(choice, on, style)
        }
        if (on) {
            Icon(
                Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = DS.ink,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .size(with(LocalDensity.current) { 20.sp.toDp() })
            )
        }
    }
}

@Composable
private fun <T> ChoiceLabel(choice: ImasChoice<T>, on: Boolean, style: ImasChoiceCardsStyle) {
    val fg = LocalContentColor.current
    when (style) {
        ImasChoiceCardsStyle.GRID -> Column(
            Modifier.padding(vertical = DS.Space.gap, horizontal = DS.Space.gapTight),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (choice.icon != null) {
                Icon(choice.icon, contentDescription = null, tint = fg, modifier = Modifier.size(with(LocalDensity.current) { 22.sp.toDp() }))
            }
            Text(choice.title, style = ImasType.heading(14.sp, FontWeight.ExtraBold), color = DS.ink, maxLines = 1)
            if (choice.subtitle != null) {
                Text(choice.subtitle, style = ImasType.text(11.sp), color = DS.ink2, maxLines = 1)
            }
        }
        ImasChoiceCardsStyle.NUMERAL -> Column(
            Modifier.padding(vertical = DS.Space.gap),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(choice.title, style = ImasNumeralSize.MEDIUM.style, color = fg, maxLines = 1)
            if (choice.subtitle != null) {
                Text(choice.subtitle, style = ImasType.text(11.sp, FontWeight.Bold), color = fg, maxLines = 1)
            }
        }
        ImasChoiceCardsStyle.ROW -> Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = DS.Space.card, vertical = DS.Space.gap),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (choice.icon != null) {
                ImasIconTile(choice.icon, size = ImasIconTileSize.S36, tone = if (on) ImasIconTileTone.SOLID else ImasIconTileTone.THEMED)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(choice.title, style = ImasType.heading(15.sp, FontWeight.Bold), color = fg)
                if (choice.subtitle != null) {
                    Text(choice.subtitle, style = ImasType.text(12.sp), color = if (on) DS.ink2 else DS.ink3, maxLines = 2)
                }
            }
        }
    }
}
