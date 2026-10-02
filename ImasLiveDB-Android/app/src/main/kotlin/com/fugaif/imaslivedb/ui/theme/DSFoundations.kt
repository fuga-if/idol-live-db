package com.fugaif.imaslivedb.ui.theme

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.exp
import kotlin.math.sqrt

// =============================================================================
// 意味で引く決まり (docs/DESIGN_SYSTEM.md §4・§10)。iOS `DSFoundations.swift` の移植。
//
// `DS.*` の色と [ImasType] の書体は「値の段」。ここはその上に「役割の名前」を付ける。
// 部品はここの名前で文字を引き、画面のコードは部品だけを使う (数字を書かない)。
// =============================================================================

// MARK: - 文字の役割

/**
 * 文字の役割。部品はこの名前で書体と色を引く ([ImasText] / [style] + [color])。
 *
 * 値は iOS の文字の段 (`Font.imas*`) と同じ大きさ・太さ。端末の文字サイズとアプリ内の
 * 文字サイズ倍率の両方に追従する (sp を [ImasLiveDBTheme] の Density が拡大する)。
 */
enum class ImasTextRole(
    /** 書体 (大きさ・太さ・字間)。色は含まない ([color])。 */
    val style: TextStyle
) {
    /** 詳細の頭の名前 (30sp 極太・詰め組み)。 */
    HERO_TITLE(ImasType.heading(30.sp, FontWeight.ExtraBold)),

    /** 区画の見出し・大 (20sp 太字・詰め組み)。詳細とハブの区画。 */
    SECTION_TITLE(ImasType.heading(20.sp, FontWeight.Bold)),

    /** 区画の見出し・小 (13sp 中太・灰)。一覧・設定・フォーム・カードの中の小分け。 */
    SECTION_LABEL(ImasType.text(13.sp, FontWeight.SemiBold)),

    /** カードの題 (19sp 太字・詰め組み)。 */
    CARD_TITLE(ImasType.heading(19.sp, FontWeight.Bold)),

    /** 行の題 (16sp 中太)。曲・アイドル・ライブなど「もの」の名前。 */
    ROW_TITLE(ImasType.text(16.sp, FontWeight.SemiBold)),

    /** 操作・設定の行の題 (16sp 標準)。入口・スイッチ・選択肢・行の形のボタン。 */
    ROW_LABEL(ImasType.text(16.sp)),

    /** 行の副題 (13sp・灰)。 */
    ROW_SUBTITLE(ImasType.text(13.sp)),

    /** 行の下段・日付・回数 (12sp・薄灰)。 */
    META(ImasType.text(12.sp)),

    /** 本文 (17sp)。 */
    BODY(ImasType.text(17.sp)),

    /** 項目と値の行の文字 (15sp)。 */
    VALUE(ImasType.text(15.sp)),

    /** 補足文 (13sp・灰)。囲まない。 */
    NOTE(ImasType.text(13.sp)),

    /** 目印 (12sp 太字)。カードの上の「担当」「あと 37 日」など。 */
    EYEBROW(ImasType.text(12.sp, FontWeight.Bold)),

    /** 札の文字 (11sp 太字)。 */
    BADGE(ImasType.text(11.sp, FontWeight.Bold)),

    /** チップの文字 (14sp 中太)。 */
    CHIP(ImasType.text(14.sp, FontWeight.SemiBold)),

    /**
     * 英字の印字 (10.5sp 等幅・字間)。チケットの「ADMIT ONE」、見出しの横の「PLAY」、
     * 頭の「PRODUCE · 2026.10.01 THU」。日本語の見出しと並べて、印刷物の手触りを出す。
     * 大文字にはしない: ブランド名 (SideM) や公演名のような値の綴りを変えないため。
     * ADMIT ONE・SETLIST のような決まった英字は、呼び出し側で大文字のまま書く (iOS と同じ)。
     */
    IMPRINT(ImasType.mono(10.5.sp, FontWeight.Medium).copy(letterSpacing = 0.6.sp)),

    /**
     * 目一杯小さい札 (8sp 中太)。月カレンダーの単日バー・受付帯・あふれ件数「+n」など、
     * 枠の高さが決まっていて文字を詰め込むしかない場所専用 (一般の文字サイズには使わない)。
     */
    MICRO(ImasType.text(8.sp, FontWeight.SemiBold));

    /** 既定の文字色。部品が明示しない限りこれを使う。 */
    val color: Color
        @Composable @ReadOnlyComposable
        get() = when (this) {
            HERO_TITLE, SECTION_TITLE, CARD_TITLE, ROW_TITLE, ROW_LABEL, BODY, VALUE -> DS.ink
            SECTION_LABEL, ROW_SUBTITLE, NOTE, CHIP -> DS.ink2
            META, MICRO -> DS.ink3
            EYEBROW, BADGE, IMPRINT -> DS.ink2
        }
}

/**
 * 文字の役割を当てた Text (iOS の `.imasText(role, color:)`)。部品の中で使う。
 * 色を替えるときは [color] で渡す。印字 ([ImasTextRole.IMPRINT]) も文字列はそのまま組む (大文字にしない)。
 */
@Composable
fun ImasText(
    text: String,
    role: ImasTextRole,
    modifier: Modifier = Modifier,
    color: Color = role.color,
    textAlign: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Clip
) {
    Text(
        text = text,
        modifier = modifier,
        color = color,
        textAlign = textAlign,
        maxLines = maxLines,
        overflow = overflow,
        style = role.style
    )
}

// MARK: - 数字

/**
 * 数字の書体の大きさ。ゲームのステージ (`QS.num`) と同じ「細長い太字・等幅」の系統。
 * 会場の電光掲示板とチケットの日付の数字。数字はこれだけで組む (本文の書体で大きくしない)。
 *
 * iOS は大きい数字を Compressed、小さい数字を Condensed で組み分けているが、Android は
 * どちらも端末の `sans-serif-condensed` ([ImasType.condensedFamily])。大きさと太さは iOS と同じ。
 */
enum class ImasNumeralSize(
    /** 数字の書体 (細長い太字・等幅数字)。 */
    val style: TextStyle,
    /** 単位の書体。 */
    val unitStyle: TextStyle
) {
    /** 大きいチケットのカウントダウン (76sp)。画面に 1 つだけ。 */
    POSTER(ImasType.numeral(76.sp, FontWeight.Black), ImasType.mono(10.5.sp, FontWeight.Medium)),

    /** チケットの半券のカウントダウン・月の見出し (54sp)。 */
    COUNTDOWN(ImasType.numeral(54.sp, FontWeight.Black), ImasType.mono(10.5.sp, FontWeight.Medium)),

    /** 半券の日付・年の見出し (28sp)。 */
    DATE(ImasType.numeral(28.sp, FontWeight.ExtraBold), ImasType.text(13.sp, FontWeight.SemiBold)),

    /** 統計タイル・回収率・掲示板 (30sp)。 */
    LARGE(ImasType.numeral(30.sp, FontWeight.ExtraBold), ImasType.text(13.sp, FontWeight.SemiBold)),

    /** 行の末尾の票・確率・回数 (20sp)。 */
    MEDIUM(ImasType.numeral(20.sp, FontWeight.Bold), ImasType.text(12.sp, FontWeight.SemiBold)),

    /** 曲順・下段の回数 (15sp)。 */
    SMALL(ImasType.numeral(15.sp, FontWeight.SemiBold), ImasType.text(11.sp, FontWeight.SemiBold))
}

// MARK: - ペンライト

/**
 * 合同ライブなど、単色で表せない目印に塗る虹 (アプリアイコンの帯の色)。
 * ゲームのステージで答えの色が無いときに灯すペンライトの色 (`QS.penlights`) もこれ。
 */
val ImasRainbow: List<Color> = listOf(
    Color(0xFFE5484D), Color(0xFFF08C2E), Color(0xFFF2C12E), Color(0xFF3FB27F),
    Color(0xFF3A8EE6), Color(0xFF7A5AE0), Color(0xFFD65DB1)
)

/** ペンライトの点の大きさ。 */
enum class ImasPenlightSize(val diameter: Dp) {
    /** 13sp の文字の前 (歌唱者・チップ)。並べて人数を見せるときも。 */
    SMALL(6.dp),

    /** 15〜16sp の文字の前 (目印・行)。 */
    REGULAR(7.dp),

    /** 見出し・ヒーローの前。 */
    LARGE(10.dp)
}

/**
 * 色の目印。名前・見出しの前に置く小さな点。iOS `ImasPenlight` の移植。
 *
 * アイドル・ブランドの色は、文字の後ろに淡く敷かず、この点 (と帯・選んだ印) だけで見せる。
 * 平らな点だけ (輪も光も付けない。ぼんやり光って見えるため)。
 * 読み上げには出さない (飾り。色の意味は隣の名前が言う)。
 *
 * @param color 点の色。実体の色は `imasTheme(...).penlight` から引く (hex を直接書かない)。
 * @param rainbow 合同ライブなど、単色で表せない目印は虹色にする (輪と光は [color] のまま)。
 */
@Composable
fun ImasPenlight(
    color: Color,
    modifier: Modifier = Modifier,
    size: ImasPenlightSize = ImasPenlightSize.REGULAR,
    rainbow: Boolean = false
) {
    // iOS の @ScaledMetric(relativeTo: .footnote) と同じく、文字の大きさの設定に合わせて点も大きくする
    // (dp ではなく sp で測ると、端末の文字サイズとアプリ内の倍率の両方が掛かる)。
    val diameter = with(LocalDensity.current) { size.diameter.value.sp.toDp() }
    Box(
        modifier
            .size(diameter)
            .drawWithCache {
                // `size` は引数 (点の大きさの段) と名前が重なるので、描く面の大きさは this から引く。
                val radius = this.size.minDimension / 2f
                val fill = if (rainbow) imasStripesVertical(ImasRainbow, this.size.height) else SolidColor(color)
                onDrawBehind { drawCircle(fill, radius = radius) }
            }
    )
}

/**
 * 単色で表せない目印 (合同ライブ) の虹色。色は溶かさず、くっきり区切った縞にする
 * (ぼんやり移ろうグラデーションは使わない。iOS `ImasStripes`)。[height] は塗る高さ (px)。
 */
fun imasStripesVertical(colors: List<Color>, height: Float): Brush {
    if (colors.isEmpty()) return SolidColor(Color.Transparent)
    val n = colors.size.toFloat()
    val stops = colors.flatMapIndexed { i, c -> listOf(i / n to c, (i + 1) / n to c) }.toTypedArray()
    return Brush.verticalGradient(*stops, startY = 0f, endY = height)
}

// MARK: - 実体の色が環境にあるか

/** 主ボタン・選択の塗りに使う色。実体の色が無い (ニュートラルな) 画面では墨 (`DS.sys`)。 */
val ImasTheme.actionFill: Color
    @Composable @ReadOnlyComposable get() = if (isNeutral) DS.sys else accent

/** [actionFill] の上の文字色。 */
val ImasTheme.onActionFill: Color
    @Composable @ReadOnlyComposable get() = if (isNeutral) DS.onSys else onAccent

/** ペンライトの色。実体の色が無ければ墨。 */
val ImasTheme.penlight: Color
    @Composable @ReadOnlyComposable get() = if (isNeutral) DS.ink else dot

// MARK: - 地

/**
 * 部品が置かれている地 (iOS `ImasBackdrop`)。
 *
 * 「会場とチケット」では地は 1 種類 (ロビーの生成り / 客席の闇) で、面はどこでも `DS.surface`。
 * 一覧・詳細・ハブ (`ImasPage`) とフォーム・設定 (`ImasFormPage`) の区別は残しておく
 * (面の影や線の出し方を地ごとに変えたくなったときの受け口)。
 */
enum class ImasBackdrop {
    /** 一覧・詳細・ハブの地。 */
    PAPER,

    /** フォーム・設定の地。 */
    GROUPED
}

/** 今の地。`ImasPage` / `ImasFormPage` が配下に伝える (iOS の `@Environment(\.imasBackdrop)`)。 */
val LocalImasBackdrop = staticCompositionLocalOf { ImasBackdrop.GROUPED }

// MARK: - 実体の色の環境

/**
 * 祖先が与えた実体の色 (iOS の `@Environment(\.imasTheme)`)。null はニュートラル。
 * 読むときは [imasEnvTheme] を通す (null のときに今のモードのニュートラルを返す)。
 */
val LocalImasTheme = staticCompositionLocalOf<ImasTheme?> { null }

/**
 * このサブツリーに実体の色を与える (iOS の `.imasTheme(seed:brand:)`)。
 * 配下の部品は `seed` / `brand` を渡さなければこの色を使う (部品ごとに seed を渡さない)。
 *
 * @param seed アイドル等のイメージカラー hex。
 * @param brand ブランド ID (Android の部品は brand をいつも ID で受ける。色はマスタから引く)。
 */
@Composable
fun ImasThemeProvider(seed: String?, brand: String? = null, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalImasTheme provides imasThemeForBrand(seed, brand), content = content)
}

/** 環境の実体の色。祖先が [ImasThemeProvider] を置いていなければ、今のモードのニュートラル。 */
val imasEnvTheme: ImasTheme
    @Composable @ReadOnlyComposable get() = LocalImasTheme.current ?: imasTheme(seed = null)

// MARK: - 動き

/** 状態が切り替わるときの動き (iOS `Animation.imasStandard` = `.snappy(duration: 0.22)`)。 */
object ImasMotion {
    /** 選択・開閉など、状態が切り替わるときの標準の動き。 */
    fun <T> standard(): AnimationSpec<T> = spring(dampingRatio = 0.86f, stiffness = 800f)

    /**
     * 画面の読み込みを始めるまでの待ち (押し込みの動きが終わってから。iOS `imasLoadAfterTransition`)。
     * 動きの最中に重い読み込みと再描画が重なると、出る動きがカクつく (中身は読み込み中の表示で先に出す)。
     */
    const val LOAD_AFTER_TRANSITION_MS = 380L
}

// MARK: - 押し心地

/**
 * 押せるカード・セル・ボタンの押し心地 (iOS `ImasPressStyle`)。押すと少し縮んで (0.97) 暗くなる (0.88)。
 * 波紋 (リップル) は出さない: 紙の面に灰色の波紋が乗ると安っぽく見えるため (ゲームの `quizPress` と同じ判断)。
 */
@Composable
fun Modifier.imasPress(
    enabled: Boolean = true,
    role: Role? = Role.Button,
    onClickLabel: String? = null,
    onClick: () -> Unit
): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && enabled) 0.97f else 1f, ImasMotion.standard(), label = "imasPressScale")
    val dim by animateFloatAsState(if (pressed && enabled) 0.88f else 1f, ImasMotion.standard(), label = "imasPressDim")
    return this
        .graphicsLayer { scaleX = scale; scaleY = scale; alpha = dim }
        .clickable(
            interactionSource = source,
            indication = null,
            enabled = enabled,
            onClickLabel = onClickLabel,
            role = role,
            onClick = onClick
        )
}

/**
 * カードの中の行を押せるようにする (iOS `.buttonStyle(.imasRow)`)。押している間だけ面が `DS.fill` になる。
 * 縮めない (行は面の一部なので)。
 */
@Composable
fun Modifier.imasRowPress(
    enabled: Boolean = true,
    role: Role? = Role.Button,
    onClickLabel: String? = null,
    onClick: () -> Unit
): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    return this
        .background(if (pressed && enabled) DS.fill else Color.Transparent)
        .clickable(
            interactionSource = source,
            indication = null,
            enabled = enabled,
            onClickLabel = onClickLabel,
            role = role,
            onClick = onClick
        )
}

// MARK: - 手応え

/**
 * 印を押す・選ぶ・切り替えるときの触覚 (iOS `sensoryFeedback`)。部品が返す (画面で足さない)。
 * Compose の `HapticFeedbackType` は 2 種類しか無いので、View の触覚の定数で段を分ける。
 */
@Stable
class ImasHaptics internal constructor(private val view: View) {
    /** 選ぶ・切り替える (iOS `.selection`)。 */
    fun selection() {
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }

    /** 軽い手応え (iOS `.impact(weight: .light)`)。行の末尾の印。 */
    fun impactLight() {
        view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
    }

    /** はっきりした手応え (iOS `.impact(weight: .medium)`)。印を点ける・判子を押す。 */
    fun impactMedium() {
        view.performHapticFeedback(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM
            else HapticFeedbackConstants.VIRTUAL_KEY
        )
    }
}

/** 部品の中で触覚を返す口。 */
@Composable
fun rememberImasHaptics(): ImasHaptics {
    val view = LocalView.current
    return remember(view) { ImasHaptics(view) }
}
