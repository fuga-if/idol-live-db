package com.fugaif.imaslivedb.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

// =============================================================================
// iOS の DesignTokens (DS) を移植したファウンデーション・トークン一式。
//
// 世界は「会場とチケット」(docs/DESIGN_SYSTEM.md §1)。ライトは開演前のロビー (生成りの地に
// 墨の文字)、ダークは客席の暗転 (紫がかった闇に生成りの文字)。チケットだけはダークでも紙のまま。
// 「システムクロムは墨 1 色、色は常にブランド/エンティティから供給」という方針。
//
// ライト/ダークの 2 組を値として持ち、どちらを使うかは [LocalImasColors] が決める。
// iOS 側は `UIColor { $0.userInterfaceStyle }` の動的色 1 個で同じことをしているが、
// Compose の `Color` は解決済みの値でしかないので、「現在のトレイト」に当たる物を
// CompositionLocal として持ち回す。
// =============================================================================

/** DS の色トークン 1 組 (ライトかダークのどちらか)。名前は iOS の `DS.*` と同じ。 */
@Immutable
data class ImasColors(
    /** この組がダーク側か。テーマ由来の色 ([ImasTheme]) の導出規則もこれで切り替わる。 */
    val dark: Boolean,

    // ニュートラル
    /** 画面の地。ロビーの生成り / 客席の闇。 */
    val bg: Color,
    /** 地の上に置く面 (カード・行のまとまり・シートの欄)。 */
    val surface: Color,
    /** 面の中にもう一段置く面。 */
    val surface2: Color,
    val fill: Color,
    val sep: Color,
    val ink: Color,
    val ink2: Color,
    val ink3: Color,

    // 紙面 (docs/DESIGN_SYSTEM.md §4)
    /** 線で形を取る部品 (切り替え・札・入口) の輪郭。区切り線 (`sep`) より一段濃い。 */
    val line: Color,

    // チケットの紙 (ダークでも紙のまま光る)
    /** チケット・半券の紙。ダークでも生成りのまま (暗い客席で手元のチケットだけが白く見える)。 */
    val ticket: Color,
    /** チケットの上の文字。紙は常に明るいので、ダークでも墨。 */
    val ticketInk: Color,
    val ticketSub: Color,
    /** 切り取り線 (点線)。 */
    val ticketDash: Color,
    /** 面の上の切り取り線 (ダークの面は暗いので一段明るく)。 */
    val perforation: Color,

    // 電光掲示板 (記録・出演の数)。ライトでもダークでも板は暗い。
    val board: Color,
    val boardInk: Color,
    val boardDim: Color,
    val boardLine: Color,

    // 判子・穴
    /** 判子の朱。回収・参加の印と、取り返しのつかない操作。 */
    val stamp: Color,
    /** 掲示板のランプ (暗い板の上の赤)。 */
    val lamp: Color,
    /** パンチ穴の向こう。ライトは暗い客席、ダークは照明が漏れて明るい。 */
    val hole: Color,

    // 曜日
    val saturday: Color,
    val sunday: Color,

    // セマンティック
    val success: Color,
    /**
     * 薄い塗りの上に載せる緑。`success` は塗りの上だと 11sp の札の文字に足りない
     * (WCAG AA は 4.5:1)。ダークは `success` のままで足りる。
     */
    val successInk: Color,
    val warning: Color,
    /** システムクロムは墨 1 色。色は常にエンティティ側から来る → けばけばしさ回避。 */
    val sys: Color,
    /** sys を背景にしたときの前景色 (sys の反転)。sys はモードで墨/生成りが入れ替わるので固定不可。 */
    val onSys: Color,
    val sys2: Color,
    /**
     * スイッチの ON の地。iOS の OS のスイッチはつまみが白なので、ダークでも白に沈まない濃さにしてある
     * (Material のスイッチのつまみは onPrimary なので、Android の既定のスイッチはこれを使っていない)。
     */
    val switchOn: Color,

    // マイマーク
    /** マイマーク固有色 (担当♥) */
    val pick: Color,
    /** マイマーク固有色 (お気に入り★) */
    val favorite: Color,

    // エレベーション (影) — フラット基調なので控えめ
    /** 面の影の色 (iOS `DS.elevation1(scheme)`)。 */
    val elevation1: Color
) {
    /** 一覧・詳細・ハブの地。`bg` と同じ (地は 1 種類)。 */
    val paper: Color get() = bg

    /** 地の上に置く面。`surface` と同じ。 */
    val panel: Color get() = surface

    /** 取り返しのつかない操作と失敗。判子の朱と同じ (iOS も `danger = stamp`)。 */
    val danger: Color get() = stamp
}

/** ダーク側のトークン (客席の暗転)。値は iOS `DesignTokens.swift` の dark 列と 1:1。 */
val ImasColorsDark = ImasColors(
    dark = true,
    bg = Color(0xFF15131C),
    surface = Color(0xFF1F1C28),
    surface2 = Color(0xFF2A2633),
    fill = Color(0xFFF6F1E7).copy(alpha = 0.10f),   // rgba(246,241,231,0.10) = 生成りの 10%
    sep = Color(0xFF2F2A3A),
    ink = Color(0xFFF6F1E7),
    ink2 = Color(0xFFA7A1B5),
    ink3 = Color(0xFF7E7890),
    line = Color(0xFF3A3547),
    ticket = Color(0xFFF6F1E7),
    ticketInk = Color(0xFF1B1822),
    ticketSub = Color(0xFF6B6478),
    ticketDash = Color(0xFFC9C0B0),
    perforation = Color(0xFF4A4458),
    board = Color(0xFF24212E),
    boardInk = Color(0xFFF6F1E7),
    boardDim = Color(0xFFA7A1B5),
    boardLine = Color(0xFF3A3547),
    stamp = Color(0xFFE0546A),
    lamp = Color(0xFFFF4D5E),
    hole = Color(0xFFE9E2D3),
    saturday = Color(0xFF7EA6FF),
    sunday = Color(0xFFFF6B7D),
    success = Color(0xFF4CC97A),
    successInk = Color(0xFF4CC97A),
    warning = Color(0xFFF2A83B),
    sys = Color(0xFFF6F1E7),
    onSys = Color(0xFF1B1822),
    sys2 = Color(0xFFA7A1B5),
    switchOn = Color(0xFF5E5675),
    pick = Color(0xFFFF5A8C),
    favorite = Color(0xFFFFC83E),
    elevation1 = Color.Black.copy(alpha = 0.5f)
)

/** ライト側のトークン (開演前のロビー)。値は iOS `DesignTokens.swift` の light 列と 1:1。 */
val ImasColorsLight = ImasColors(
    dark = false,
    bg = Color(0xFFF4F0E8),
    surface = Color(0xFFFFFDF8),
    surface2 = Color(0xFFF1EBDF),
    fill = Color(0xFF1B1822).copy(alpha = 0.06f),   // rgba(27,24,34,0.06) = 墨の 6%
    sep = Color(0xFFE4DBCB),
    ink = Color(0xFF1B1822),
    ink2 = Color(0xFF6B6478),
    ink3 = Color(0xFFA49B8C),
    line = Color(0xFFDCD2C0),
    ticket = Color(0xFFFFFDF8),
    ticketInk = Color(0xFF1B1822),
    ticketSub = Color(0xFF6B6478),
    ticketDash = Color(0xFFCEC3B0),
    perforation = Color(0xFFCEC3B0),
    board = Color(0xFF1F1C28),
    boardInk = Color(0xFFF6F1E7),
    boardDim = Color(0xFFA7A1B5),
    boardLine = Color(0xFF3A3547),
    stamp = Color(0xFFB42335),
    lamp = Color(0xFFFF4D5E),
    hole = Color(0xFF2A2633),
    saturday = Color(0xFF2E6BD8),
    sunday = Color(0xFFC8293F),
    success = Color(0xFF2F8F4E),
    successInk = Color(0xFF1F6B39),
    warning = Color(0xFFC27200),
    sys = Color(0xFF1B1822),
    onSys = Color(0xFFF6F1E7),
    sys2 = Color(0xFF6B6478),
    switchOn = Color(0xFF1B1822),
    pick = Color(0xFFFF2D78),
    favorite = Color(0xFFE8A800),
    elevation1 = Color(red = 0.07f, green = 0.07f, blue = 0.08f, alpha = 0.06f)
)

/**
 * 現在の配色。[ImasLiveDBTheme] が端末のライト/ダーク設定から供給する。
 *
 * `static` なのは、この値が変わったとき (= モード切替) は画面全体を描き直すのが正しいから。
 * 通常の CompositionLocal だと読み手だけを賢く無効化しようとするが、色は全域で読まれるので
 * その追跡コストが毎回の再コンポーズに乗るだけで得が無い。
 *
 * 既定をダークにしてあるのは、[ImasLiveDBTheme] の外 (Glance ウィジェット、プレビュー) から
 * 引かれても破綻しないようにするため。アプリ本体は必ずテーマの内側で読む。
 */
val LocalImasColors = staticCompositionLocalOf { ImasColorsDark }

/**
 * トークンの読み出し口。`DS.ink` と書けば現在のモードの ink が返る。
 *
 * プロパティが `@Composable` なのは、iOS の DS が動的 `UIColor` であるのと同じ理由 —
 * 「今どちらのモードか」を知っているのは呼ばれた場所であって、定義した場所ではない。
 * 合成の外 (Glance、DrawScope、非 Composable なヘルパ) から要る場合は、合成の中で
 * `LocalImasColors.current` を値にして渡すか、[ImasColorsDark] / [ImasColorsLight] を名指しで使うこと。
 */
object DS {
    // ニュートラル
    val bg: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.bg
    val surface: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.surface
    val surface2: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.surface2
    val fill: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.fill
    val sep: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.sep
    val ink: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ink
    val ink2: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ink2
    val ink3: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ink3

    // 紙面 (docs/DESIGN_SYSTEM.md §4)
    val paper: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.paper
    val panel: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.panel
    val line: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.line

    // チケットの紙
    val ticket: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ticket
    val ticketInk: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ticketInk
    val ticketSub: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ticketSub
    val ticketDash: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ticketDash
    val perforation: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.perforation

    // 電光掲示板
    val board: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.board
    val boardInk: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.boardInk
    val boardDim: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.boardDim
    val boardLine: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.boardLine

    // 判子・穴
    val stamp: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.stamp
    val lamp: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.lamp
    val hole: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.hole

    // 曜日
    val saturday: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.saturday
    val sunday: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.sunday

    // セマンティック
    val success: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.success
    val successInk: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.successInk
    val warning: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.warning
    val danger: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.danger
    val sys: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.sys
    val onSys: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.onSys
    val sys2: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.sys2
    val switchOn: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.switchOn

    // マイマーク
    val pick: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.pick
    val favorite: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.favorite

    // エレベーション
    val elevation1: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.elevation1

    // MARK: - スペーシング (4dp グリッド)。iOS `DS.sp1`〜`sp9` と同じ値の段。
    // 部品は下の役割の名前 ([Space]) で引く。値の段を直接使うのは役割に名前の無い所だけ。
    val sp1: Dp = 2.dp
    val sp2: Dp = 4.dp
    val sp3: Dp = 8.dp
    val sp4: Dp = 12.dp
    val sp5: Dp = 16.dp
    val sp6: Dp = 20.dp
    val sp7: Dp = 24.dp
    val sp8: Dp = 32.dp
    val sp9: Dp = 44.dp

    // MARK: - 角丸 (値の段)。iOS `DS.rXS`〜`rPill`。
    val rXS: Dp = 6.dp
    val rSM: Dp = 10.dp
    val rMD: Dp = 14.dp
    val rLG: Dp = 18.dp
    val rXL: Dp = 24.dp
    val rPill: Dp = 999.dp

    // MARK: - 面の角丸 (docs/DESIGN_SYSTEM.md §4)。iOS `DSFoundations.swift` の `DS.rCard` ほか。

    /**
     * カードの角丸。チケットや入場証と同じ、紙を切り抜いた程度の丸み。
     * 「会場とチケット」では面を紙として見せるので、OS の表より角を立てる。
     */
    val rCard: Dp = 18.dp

    /** カードの中に入れる面の角丸。外の角丸から内側の余白を引いて同心円にする (下限 6)。 */
    val rInner: Dp = maxOf(6.dp, rCard - Space.card)

    /**
     * 札の角丸。札は「印刷された小さな見出し」なので、ほぼ角のある四角にする。
     * カプセルにすると、淡い色の丸い札が並ぶ「よくある見た目」になる (v1 の反省)。
     */
    val rTag: Dp = 4.dp

    /**
     * 押せる部品 (ボタン・切り替え・入口) の角丸。高さに比例させる (50→12, 40→10, 32→8)。
     * 中身の部品はカプセルにしない。カプセルは OS の枠 (タブバー・ツールバー) だけが使う形。
     */
    fun rControl(height: Dp): Dp = (height.value * 0.24f).roundToInt().dp

    /** 記号を入れる角丸四角の角丸。設定の行の頭など、OS の形に合わせる所だけで使う。 */
    fun rIconTile(size: Dp): Dp = (size.value * 0.28f).roundToInt().dp

    /** ジャケの角丸。CD のジャケは角のある四角なので小さく (下限 3・上限 10)。 */
    fun rArtwork(size: Dp): Dp = (size.value * 0.08f).roundToInt().coerceIn(3, 10).dp

    /** 広い画面 (タブレット) で一覧の本文が伸びきらない幅。Web の本文段と揃える (iOS と同じ値)。 */
    val readableContentWidth: Dp = 880.dp

    /** 役割で引く余白 (iOS `DS.Space`)。値は 4dp の段 (`sp*`) から選んでいる。 */
    object Space {
        /** 画面の左右。 */
        val screen: Dp = 16.dp
        /** 区画どうしの間。 */
        val section: Dp = 28.dp
        /** 見出しと中身の間。 */
        val header: Dp = 8.dp
        /** 中身と補足文の間。 */
        val note: Dp = 6.dp
        /** カードの内側。 */
        val card: Dp = 16.dp
        /** 行の左右。 */
        val rowH: Dp = 16.dp
        /** 行の上下 (一覧)。 */
        val rowV: Dp = 12.dp
        /** 行の上下 (カードの中の短い一覧・ピッカー)。 */
        val rowVCompact: Dp = 8.dp
        /** 行の中の、先頭・本文・末尾の間。 */
        val rowGap: Dp = 12.dp
        /** 並んだもの同士 (チップ・ボタン・タイル)。 */
        val gap: Dp = 8.dp
        /** 詰めて並べるもの同士 (題と副題、記号と文字)。 */
        val gapTight: Dp = 4.dp
        /** ゆったり並べるもの同士。 */
        val gapLoose: Dp = 12.dp
    }

    /** 部品の大きさの段 (iOS `DS.Size`)。画面からは部品の種類として選ぶ (数字は書かない)。 */
    object Size {
        /** 押せる所の最小。 */
        val touch: Dp = 44.dp
        /** チップの高さ。 */
        val chip: Dp = 32.dp
        /** 札の高さ。 */
        val badge: Dp = 20.dp
        /** リードバーの幅。 */
        val leadBar: Dp = 3.dp
    }
}

/**
 * Convert a hex color string (with or without leading #) to a Compose Color.
 * Returns Color.Gray on parse failure.
 */
fun hexToColor(hex: String): Color {
    val cleaned = hex.trimStart('#')
    return try {
        val value = cleaned.toLong(16)
        when (cleaned.length) {
            6 -> Color(0xFF000000 or value)
            8 -> Color(value)
            else -> Color.Gray
        }
    } catch (e: NumberFormatException) {
        Color.Gray
    }
}

/** Return the brand color for a given brandId string, or Gray if unknown. */
fun brandColor(brandId: String?): Color =
    BrandColors.hex(brandId)?.let(::hexToColor) ?: Color.Gray
