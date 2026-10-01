package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasMotion
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress

// =============================================================================
// ボタン (docs/DESIGN_SYSTEM.md §9)。iOS `ImasButton.swift` の移植。
//
// 用途      押して何かを起こすもの。画面の主な操作・カードの操作・行の中の小さい操作。
// 使わない  選択の切り替え → ImasFilterChip / 印 (担当・参加) → ImasMarkTile /
//           別の画面への入口 → ImasNavRow・ImasEntryCard
// 構成      [記号 (任意)] [文言]、形は角丸の四角 (50→12, 40→10, 32→8)。カプセルにしない。
// 種類      役割 PRIMARY / SECONDARY / PLAIN / DESTRUCTIVE × 大きさ LARGE / MEDIUM / SMALL
// 状態      通常 / 押下 (0.97 に縮む) / 無効 (薄く) / 読み込み中 (文言の代わりにくるくる)
//
// 主ボタンは 1 画面に 1 つ。色は墨 (ライトは黒・ダークは白) で、アイドルの画面でも変えない。
// アイドル・ブランドの色はペンライト・帯・選んだ印に出す (塗りのボタンを色で塗らない)。
// =============================================================================

/** ボタンの役割 (iOS `ImasButtonRole`)。 */
enum class ImasButtonRole {
    /** 画面で一番大事な操作。墨の塗り。 */
    PRIMARY,

    /** 主の隣・単独の操作。墨の線。 */
    SECONDARY,

    /** 補助の操作。地なしの文字だけ。 */
    PLAIN,

    /** 削除・取り消し。確認とセットで使う。 */
    DESTRUCTIVE
}

/** ボタンの大きさ (iOS `ImasButtonSize`)。 */
enum class ImasButtonSize(
    val height: Dp,
    internal val fontSize: TextUnit,
    internal val iconSize: TextUnit,
    internal val horizontalPadding: Dp
) {
    /** 高さ 50。画面の下に固定する主ボタン、空状態の操作、ゲームの開始。 */
    LARGE(50.dp, 16.sp, 16.sp, 24.dp),

    /** 高さ 40。カード・頭の中。 */
    MEDIUM(40.dp, 15.sp, 14.sp, 16.dp),

    /** 高さ 32。行の中、ログインの誘い。 */
    SMALL(32.dp, 13.sp, 12.sp, 12.dp);

    /** 高さに比例した角丸。 */
    val cornerRadius: Dp get() = DS.rControl(height)
}

/** ボタンの地・文字・線。 */
private data class ImasButtonColors(val bg: Color, val fg: Color, val stroke: Color?)

@Composable
private fun buttonColors(role: ImasButtonRole): ImasButtonColors = when (role) {
    ImasButtonRole.PRIMARY -> ImasButtonColors(DS.sys, DS.onSys, null)
    ImasButtonRole.SECONDARY -> ImasButtonColors(Color.Transparent, DS.ink, DS.ink)
    ImasButtonRole.PLAIN -> ImasButtonColors(Color.Transparent, DS.ink, null)
    ImasButtonRole.DESTRUCTIVE -> ImasButtonColors(Color.Transparent, DS.danger, DS.danger.copy(alpha = 0.45f))
}

/**
 * デザインシステムのボタン (iOS `ImasButton`)。読み込み中を持てる: 押してから終わるまで文言をくるくるに替え、幅は変えない。
 *
 * @param icon 文言の前の記号 (iOS の `systemImage`)。
 * @param fillsWidth 横幅いっぱいに広げる。null なら LARGE だけ広げる。
 * @param enabled false で押せない (薄い見た目)。読み込み中は押せないが薄くはしない。
 */
@Composable
fun ImasButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    role: ImasButtonRole = ImasButtonRole.PRIMARY,
    size: ImasButtonSize = ImasButtonSize.MEDIUM,
    fillsWidth: Boolean? = null,
    isLoading: Boolean = false,
    enabled: Boolean = true
) {
    val colors = buttonColors(role)
    ImasButtonFrame(
        onClick = onClick,
        modifier = modifier.clearAndSetSemantics {
            contentDescription = title
            this.role = Role.Button
            if (isLoading) stateDescription = "処理中"
            if (!enabled) disabled()
            if (enabled && !isLoading) onClick { onClick(); true }
        },
        role = role,
        size = size,
        fillsWidth = fillsWidth,
        isLoading = isLoading,
        enabled = enabled
    ) {
        Box(contentAlignment = Alignment.Center) {
            Row(
                Modifier.alpha(if (isLoading) 0f else 1f),
                horizontalArrangement = Arrangement.spacedBy(if (size == ImasButtonSize.SMALL) DS.Space.gapTight else 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (icon != null) {
                    Icon(
                        icon,
                        contentDescription = null,
                        tint = colors.fg,
                        modifier = Modifier.size(with(LocalDensity.current) { size.iconSize.toDp() })
                    )
                }
                ImasFitText(
                    title,
                    style = ImasType.heading(size.fontSize, FontWeight.Bold),
                    color = colors.fg,
                    minScale = 0.8f
                )
            }
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = if (role == ImasButtonRole.PRIMARY) DS.onSys else DS.ink2,
                    strokeWidth = 2.dp
                )
            }
        }
    }
}

/**
 * ボタンの枠だけ (iOS の `.buttonStyle(.imas(role, size:))`)。中身 (文言・記号) は呼び出し側が組む。
 * 文字の色は `LocalContentColor` で引ける。押下で 0.97 に縮み、無効は薄く、読み込み中は押せない。
 */
@Composable
fun ImasButtonFrame(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    role: ImasButtonRole = ImasButtonRole.PRIMARY,
    size: ImasButtonSize = ImasButtonSize.MEDIUM,
    fillsWidth: Boolean? = null,
    isLoading: Boolean = false,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit
) {
    val colors = buttonColors(role)
    val shape = RoundedCornerShape(size.cornerRadius)
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val active = enabled && !isLoading
    val scale by animateFloatAsState(if (pressed && active) 0.97f else 1f, ImasMotion.standard(), label = "imasButtonScale")
    val dim by animateFloatAsState(if (pressed && active) 0.85f else 1f, ImasMotion.standard(), label = "imasButtonDim")
    val wide = fillsWidth ?: (size == ImasButtonSize.LARGE)
    Row(
        modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                alpha = dim * if (enabled) 1f else 0.45f
            }
            .then(if (wide) Modifier.fillMaxWidth() else Modifier)
            .heightIn(min = size.height)
            .background(colors.bg, shape)
            .then(if (colors.stroke != null) Modifier.border(1.5.dp, colors.stroke, shape) else Modifier)
            .clickable(
                interactionSource = source,
                indication = null,
                enabled = active,
                role = Role.Button,
                onClick = onClick
            )
            .padding(horizontal = if (role == ImasButtonRole.PLAIN) 0.dp else size.horizontalPadding),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // 中の Text / Icon の既定の色を役割の色にする (呼び出し側は LocalContentColor で引ける)。
        CompositionLocalProvider(LocalContentColor provides colors.fg) { content() }
    }
}

// MARK: - 記号だけのボタン

/** 記号だけのボタンの大きさ (iOS `ImasIconButton.Size`)。 */
enum class ImasIconButtonSize(val diameter: Dp, internal val glyph: Dp) {
    /** 32 の丸。行・カードの中。 */
    SMALL(32.dp, 16.dp),

    /** 44 の丸。画面の中の独立した操作。 */
    REGULAR(44.dp, 20.dp)
}

/** 記号だけのボタンの見え方 (iOS `ImasIconButton.Style`)。 */
enum class ImasIconButtonStyle {
    /** 灰の地 (既定)。 */
    TINTED,

    /** 墨の塗り (再生など、その画面の主の操作)。 */
    FILLED,

    /** 地なし。 */
    PLAIN
}

/**
 * 記号だけの丸いボタン (iOS `ImasIconButton`)。月の送り・再生など、文言が無くても分かる操作。
 * 読み上げ用の [label] は必ず渡す。丸は OS のツールバーの記号ボタンと同じ形 (中身のボタンで丸いのはこれだけ)。
 *
 * @param isLoading 押してから終わるまで記号をくるくるに替える (削除中など)。
 */
@Composable
fun ImasIconButton(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: ImasIconButtonSize = ImasIconButtonSize.REGULAR,
    style: ImasIconButtonStyle = ImasIconButtonStyle.TINTED,
    isLoading: Boolean = false,
    enabled: Boolean = true
) {
    val bg = when (style) {
        ImasIconButtonStyle.TINTED -> DS.fill
        ImasIconButtonStyle.FILLED -> DS.sys
        ImasIconButtonStyle.PLAIN -> Color.Transparent
    }
    val fg = when (style) {
        ImasIconButtonStyle.TINTED -> DS.ink
        ImasIconButtonStyle.FILLED -> DS.onSys
        ImasIconButtonStyle.PLAIN -> DS.ink2
    }
    Box(
        modifier
            .sizeIn(minWidth = DS.Size.touch, minHeight = DS.Size.touch)
            .clearAndSetSemantics {
                contentDescription = label
                this.role = Role.Button
                if (isLoading) stateDescription = "処理中"
                if (!enabled) disabled()
                if (enabled && !isLoading) onClick { onClick(); true }
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            Modifier
                .imasPress(enabled = enabled && !isLoading, onClick = onClick)
                .alpha(if (enabled) 1f else 0.45f)
                .size(size.diameter)
                .background(bg, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (isLoading) {
                CircularProgressIndicator(Modifier.size(16.dp), color = fg, strokeWidth = 2.dp)
            } else {
                Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(size.glyph))
            }
        }
    }
}
