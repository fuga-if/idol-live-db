package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress

// =============================================================================
// ナビバーの部品 (docs/DESIGN_SYSTEM.md §2.1)。iOS `ImasChromeControls.swift` の移植。
//
// ImasToolbarButton    ナビバーの記号のボタン。読み上げは言葉で。数の札 (絞り込みの件数) を付けられる。
// ImasSearchField      ナビバーの中に収める 1 行の絞り込み欄 (一覧の頭)。
// ImasScopeChip        ImasSearchField の頭に差す小さな切り替えの札 (検索対象の変更など)。押せないときは文言だけ。
// ImasNameFilterField  絞り込みシートの頭の「名前で絞り込み」欄。
// =============================================================================

// MARK: - 記号のボタン

/**
 * ナビバーの記号のボタン (iOS `ImasToolbarButton`)。文字は書かず記号 1 つ。[label] は読み上げに使う。
 * [badge] が 1 以上なら右上に朱の数の札 (効いている絞り込みの数など)。
 */
@Composable
fun ImasToolbarButton(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    badge: Int = 0,
    tint: Color = DS.ink
) {
    Box(
        modifier
            .size(DS.Size.touch)
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Button
                if (badge > 0) stateDescription = "$badge 件"
                onClick { onClick(); true }
            }
            .imasPress(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Box {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
            if (badge > 0) {
                Text(
                    "$badge",
                    style = ImasType.mono(10.sp, FontWeight.Bold),
                    // 朱の札の上の文字は白 (iOS と同じ。札の色はモードで変わらない)。
                    color = Color.White,
                    maxLines = 1,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 8.dp, y = (-7).dp)
                        .heightIn(min = 16.dp)
                        .widthIn(min = 16.dp)
                        .background(DS.stamp, RoundedCornerShape(50))
                        .padding(horizontal = 4.dp),
                )
            }
        }
    }
}

// MARK: - 絞り込みの欄

/**
 * 入力の欄の共通 (飾りの無い 1 行)。消去の ⊗ は出し入れせず常に置いて見た目だけ消す
 * (1 文字目で「空 → 非空」に組みが変わると、変換中の文字が確定されてしまう・文字が横に跳ねるため)。
 */
@Composable
private fun ChromeField(
    prompt: String,
    text: String,
    onTextChange: (String) -> Unit,
    leadingIcon: ImageVector,
    imeAction: ImeAction,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
    leading: (@Composable () -> Unit)? = null
) {
    var field by remember { mutableStateOf(TextFieldValue(text, TextRange(text.length))) }
    if (field.text != text) field = TextFieldValue(text, TextRange(text.length))
    val style: TextStyle = ImasType.text(15.sp)
    val ink = DS.ink
    val iconSize = with(LocalDensity.current) { 15.sp.toDp() }
    val keyboard = LocalSoftwareKeyboardController.current
    Row(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(DS.sp2),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(leadingIcon, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(iconSize))
        leading?.invoke()
        BasicTextField(
            value = field,
            onValueChange = {
                field = it
                if (it.text != text) onTextChange(it.text)
            },
            modifier = Modifier
                .weight(1f)
                .semantics { contentDescription = prompt },
            textStyle = style.copy(color = ink),
            singleLine = true,
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = imeAction),
            // 確定したらキーボードを閉じる (検索キーを押しても閉じないと、一覧が隠れたままになる)。
            keyboardActions = KeyboardActions(onAny = { onSubmit(); keyboard?.hide() }),
            cursorBrush = SolidColor(ink),
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (text.isEmpty()) Text(prompt, style = style, color = DS.ink3, maxLines = 1)
                    inner()
                }
            }
        )
        val hasText = text.isNotEmpty()
        Box(
            Modifier
                .size(24.dp)
                .alpha(if (hasText) 1f else 0f)
                .then(
                    if (hasText) {
                        Modifier
                            .clearAndSetSemantics {
                                contentDescription = "絞り込みを解除"
                                role = Role.Button
                                onClick { onTextChange(""); true }
                            }
                            .imasPress { onTextChange("") }
                    } else {
                        Modifier.clearAndSetSemantics { }
                    }
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Filled.Cancel, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(with(LocalDensity.current) { 16.sp.toDp() }))
        }
    }
}

/**
 * フィルタシート先頭に置く「名前で絞り込み」の欄 (iOS `ImasNameFilterField`)。
 *
 * これは検索ではなく **フィルタ** である (ブランド絞り込み・並び順と合成され、一覧の並びを保つ)。
 * 虫眼鏡でなくフィルタの記号にして、ツールバーの検索 (詳細へ飛ぶ) と区別する。
 */
@Composable
fun ImasNameFilterField(prompt: String, text: String, onTextChange: (String) -> Unit, modifier: Modifier = Modifier) {
    ChromeField(
        prompt = prompt,
        text = text,
        onTextChange = onTextChange,
        leadingIcon = Icons.Filled.FilterList,
        imeAction = ImeAction.Done,
        onSubmit = {},
        modifier = modifier
            .fillMaxWidth()
            .background(DS.fill, CircleShape)
            .padding(horizontal = DS.sp4, vertical = DS.sp3)
    )
}

/** 同じバーに並ぶツールバーボタンの高さ (iOS `imasSearchFieldHeight`)。入力欄をボタンと同じ高さにする。 */
private val SearchFieldHeight = 44.dp

/**
 * ナビバーの中に収める、1 行ぶんの絞り込みの欄 (iOS `ImasSearchField`)。高さは隣のツールバーボタンに合わせる。
 * 文字の大きさは一定で頭打ちにする (バーの高さは中身では伸びないので、際限なく拡大すると欄が切れる)。
 *
 * @param onSubmit 確定 (キーボードの検索キー)。歌詞のようにサーバへ投げるものだけが使う。
 * @param leading 入力欄の頭に差す小物。検索対象の切り替えなど。
 */
@Composable
fun ImasSearchField(
    prompt: String,
    text: String,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    onSubmit: () -> Unit = {},
    leading: (@Composable () -> Unit)? = null
) {
    val density = LocalDensity.current
    // iOS `.dynamicTypeSize(...accessibility1)` 相当。
    CompositionLocalProvider(LocalDensity provides Density(density.density, density.fontScale.coerceAtMost(1.6f))) {
        ChromeField(
            prompt = prompt,
            text = text,
            onTextChange = onTextChange,
            leadingIcon = Icons.Filled.Search,
            imeAction = ImeAction.Search,
            onSubmit = onSubmit,
            leading = leading,
            modifier = modifier
                .fillMaxWidth()
                .heightIn(min = SearchFieldHeight)
                .background(DS.fill, CircleShape)
                .padding(horizontal = DS.sp4)
        )
    }
}

/**
 * [ImasSearchField] の頭に差す小さな切り替えの札 (iOS の searchModeChip 相当)。
 * 押せるときは文言 + 下向き矢印の丸いカプセル、押せない (切り替え先が無い) ときは文言だけにする。
 * メニューの開閉は呼び出し側が持つ (何を並べるかは画面ごとに違うため)。
 */
@Composable
fun ImasScopeChip(
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClickLabel: String? = null,
    onClick: () -> Unit
) {
    Surface(shape = CircleShape, color = DS.fill, modifier = modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clearAndSetSemantics {
                    contentDescription = label
                    if (enabled) {
                        role = Role.Button
                        onClick(label = onClickLabel) { onClick(); true }
                    }
                }
                .then(if (enabled) Modifier.imasPress(onClick = onClick) else Modifier)
                .padding(
                    start = DS.sp3,
                    end = if (enabled) DS.sp1 else DS.sp3,
                    top = DS.sp2,
                    bottom = DS.sp2
                )
        ) {
            Text(label, style = ImasType.text(13.sp, FontWeight.Medium), color = DS.ink2, maxLines = 1)
            if (enabled) {
                Icon(
                    Icons.Filled.ArrowDropDown,
                    contentDescription = null,
                    tint = DS.ink2,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    }
}
