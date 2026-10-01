package com.fugaif.imaslivedb.ui.theme

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
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

/** ダークの光の滲みのぼかし半径 (iOS の `.blur(radius: 3.5)`)。 */
private val PenlightGlowBlur = 3.5.dp

/**
 * 色の目印。名前・見出しの前に置く小さな点。iOS `ImasPenlight` の移植。
 *
 * アイドル・ブランドの色は、文字の後ろに淡く敷かず、この点 (と帯・選んだ印) だけで見せる。
 * ライトは点の周りに淡い輪、ダークは客席のペンライトのように光る。
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
    val dark = LocalImasColors.current.dark
    // iOS の @ScaledMetric(relativeTo: .footnote) と同じく、文字の大きさの設定に合わせて点も大きくする
    // (dp ではなく sp で測ると、端末の文字サイズとアプリ内の倍率の両方が掛かる)。
    val diameter = with(LocalDensity.current) { size.diameter.value.sp.toDp() }
    Box(
        modifier
            .size(diameter)
            .drawWithCache {
                // `size` は引数 (点の大きさの段) と名前が重なるので、描く面の大きさは this から引く。
                val radius = this.size.minDimension / 2f
                val fill = if (rainbow) Brush.verticalGradient(ImasRainbow) else SolidColor(color)
                if (dark) {
                    val (glow, reach) = penlightGlow(color, radius, PenlightGlowBlur.toPx())
                    onDrawBehind {
                        drawCircle(glow, radius = reach)
                        drawCircle(fill, radius = radius)
                    }
                } else {
                    val halo = color.copy(alpha = color.alpha * 0.22f)
                    val haloRadius = radius + 2.dp.toPx()
                    onDrawBehind {
                        drawCircle(halo, radius = haloRadius)
                        drawCircle(fill, radius = radius)
                    }
                }
            }
    )
}

/**
 * ダークの光の滲みの塗りと届く半径 (iOS は同じ大きさの円を `.blur(radius: 3.5).opacity(0.9)` で敷く)。
 *
 * Compose のぼかし (`Modifier.blur`) は Android 12 未満で効かないので、ぼかした円の濃さの広がりを
 * 放射状のグラデーションで描く。円 (半径 r) をガウスぼかし (σ) した広がりは、分散 σ² + r²/4 の
 * ガウス分布でよく近似でき、中心の濃さは r² / (2(σ² + r²/4))。3 標準偏差でほぼ消えるので、そこまで描く。
 */
private fun penlightGlow(color: Color, radius: Float, sigma: Float): Pair<Brush, Float> {
    val variance = sigma * sigma + radius * radius / 4f
    val peak = (radius * radius / (2f * variance)).coerceAtMost(1f) * 0.9f
    val reach = 3f * sqrt(variance)
    // 位置 t (0 = 中心, 1 = reach) の濃さは exp(-(3t)²/2)。
    val stops = PenlightGlowStops.map { t ->
        t to color.copy(alpha = color.alpha * peak * exp(-4.5f * t * t))
    }.toTypedArray()
    return Brush.radialGradient(*stops, radius = reach) to reach
}

private val PenlightGlowStops = listOf(0f, 0.2f, 0.4f, 0.6f, 0.8f, 1f)

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
