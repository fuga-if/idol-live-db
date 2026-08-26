package com.fugaif.imaslivedb.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import uniffi.imas_core.ImasThemeColors
import uniffi.imas_core.ThemeRgb
import uniffi.imas_core.ThemeSeedRequest
import uniffi.imas_core.themeDerive
import uniffi.imas_core.themeDeriveBatch
import uniffi.imas_core.themeOnColor

// =============================================================================
// ImasLiveDB — 無限色テーマエンジンの Compose 側の入口。
//
// 導出規則そのもの (hex 正規化 / HSL 変換 / WCAG コントラスト / トークン導出) は
// 共有コア imas-core (domain::color_engine) が正本。iOS も同じ関数を呼ぶので、
// 同じシードからは必ず同じ色が出る。ここに残すのは OS 側の事情だけ:
//   - コアが返す ThemeRgb (0.0–1.0) → Compose Color の変換
//   - Compose が再コンポーズのたびに呼ぶ分を止めるメモ化
// =============================================================================

/** シード1色から導出されたテーマトークン一式。ライト/ダークで導出規則が変わる。 */
data class ImasTheme(
    val accent: Color,
    val onAccent: Color,
    val tint: Color,
    val tintStrong: Color,
    val chipBg: Color,
    val chipText: Color,
    val ring: Color,
    val bar: Color,
    val dot: Color,
    val gradFrom: Color,
    val gradTo: Color,
    val separator: Color,
    val heroSurface: Color,
    /** 低彩度シード (S < 0.10) は「グレー」扱いで発色を抑える。 */
    val isNeutral: Boolean
) {
    companion object {
        /**
         * 導出結果のメモ。Compose は再コンポーズのたびに行の色を引き直すので、
         * 境界を跨ぐ手前で止める。
         *
         * キーが**解決前**の seed/brand なのは、解決 (`first_valid_hex` 相当) を持っているのが
         * コア側だから。解決後の hex をキーにするには 1 組ごとにコアへ問い合わせる必要があり、
         * それは [prewarm] が避けようとしている「1 行 1 回 FFI」そのものになる。
         * 代わりに**値**を [shared] で畳むので、無効シードが並ぶ一覧 (ユニット一覧の
         * `seed = unit.id` など、全件がニュートラルグレーへ落ちる) でも実体は 1 個しか持たない。
         * 残るのはキーの分だけで、件数はデータ件数で頭打ち (セッション長では増えない)。
         */
        private val cache = HashMap<Key, ImasTheme>()

        /** 同じトークン一式は 1 インスタンスに畳む。別々のキーが同じ色に解決される分の実体を持たないため。 */
        private val shared = HashMap<ImasTheme, ImasTheme>()

        private data class Key(val seed: String?, val brand: String?, val dark: Boolean)

        /**
         * シード hex (アイドル色) → トークン。無ければ [brand] → ニュートラルへフォールバック。
         *
         * [brand] の契約は**ブランドカラーの hex** ([BrandPalette.hex] で引いた値)。
         * ただし現状の呼び出し元の多くはブランド ID をそのまま渡しており、ID は hex として
         * 無効なのでニュートラルグレーに落ちている (例外は `"876"` / `"961"` で、3 桁 hex として
         * 通ってしまい #887766 / #996611 という偶然の色になる)。
         *
         * この配線を hex 解決へ直すと 1500 以上のユニットと 1400 以上の曲の配色が一斉に
         * 変わるため、色エンジンのコア移送とは切り離して単独で判断する。移送では 1bit も変えない。
         */
        fun derive(seed: String?, brand: String? = null, dark: Boolean = true): ImasTheme =
            memoized(Key(seed, brand, dark))

        /**
         * 実体色 (`Color`) からトークンを導出する。
         *
         * 素の `Color` をそのまま塗るのではなく、通常の seed/brand と同じ WCAG コントラスト
         * 計算を経由するので、選択色がどんな明るさでも前景色が自動で読める側に倒れる。
         */
        fun derive(color: Color, dark: Boolean = true): ImasTheme =
            derive(seed = color.toSeedHex(), brand = null, dark = dark)

        /** 単一の有効な hex からトークンを導出。無効な hex はコアがニュートラルへ倒す。 */
        fun derive(hex: String, dark: Boolean): ImasTheme =
            derive(seed = hex, brand = null, dark = dark)

        /** 任意の背景 Color の上に乗せる前景色を WCAG で黒/白から選ぶ。 */
        fun onColor(background: Color): Color =
            themeOnColor(background.toThemeRgb()).toColor()

        /**
         * 一覧 1 画面ぶんのテーマを **1 回の FFI** でまとめて温める。
         *
         * 行の Composable が個別に [derive] を呼ぶと、LazyColumn / LazyVerticalGrid の
         * 初回スクロール中に**行数ぶん FFI を跨ぐ**。行が組まれる前にここでメモを埋めておけば、
         * 以後の [derive] はメモに当たるだけで済む。
         *
         * 呼び出し側は「行が実際に引く組」をそのまま渡すこと。行が [BrandPalette.hex] で
         * 解決してから渡すコンポーネント (ImasLeadBar) と、ID をそのまま渡すコンポーネント
         * (ImasAvatar) が同居する画面では**両方**の組が要る。片方だけ温めても残りは行が跨ぐ。
         *
         * @param seeds 行ごとの (seed hex, ブランド hex) の組。[derive] に渡すのと同じ形。
         */
        @Synchronized
        fun prewarm(seeds: List<Pair<String?, String?>>, dark: Boolean = true) {
            // 重複と既出を落としてから 1 往復。順序を保つのは、結果を同じ並びで受けるため。
            val missing = LinkedHashSet<Key>()
            for ((seed, brand) in seeds) {
                val key = Key(seed, brand, dark)
                if (key !in cache) missing.add(key)
            }
            if (missing.isEmpty()) return

            val keys = missing.toList()
            val derived = themeDeriveBatch(keys.map { ThemeSeedRequest(it.seed, it.brand) }, dark)
            keys.forEachIndexed { index, key -> cache[key] = derived[index].toSharedTheme() }
        }

        @Synchronized
        private fun memoized(key: Key): ImasTheme =
            cache.getOrPut(key) { themeDerive(key.seed, key.brand, key.dark).toSharedTheme() }

        /** 同じ内容なら既出の実体を返す。呼び出しは cache への書き込みと同じロックの内側。 */
        private fun ImasThemeColors.toSharedTheme(): ImasTheme {
            val theme = toTheme()
            return shared.getOrPut(theme) { theme }
        }
    }
}

private fun ImasThemeColors.toTheme(): ImasTheme = ImasTheme(
    accent = accent.toColor(),
    onAccent = onAccent.toColor(),
    tint = tint.toColor(),
    tintStrong = tintStrong.toColor(),
    chipBg = chipBg.toColor(),
    chipText = chipText.toColor(),
    ring = ring.toColor(),
    bar = bar.toColor(),
    dot = dot.toColor(),
    gradFrom = gradFrom.toColor(),
    gradTo = gradTo.toColor(),
    separator = separator.toColor(),
    heroSurface = heroSurface.toColor(),
    isNeutral = isNeutral
)

/** コアは sRGB 各成分を 0.0–1.0 にクランプ済みで返すので、そのまま Compose Color にできる。 */
private fun ThemeRgb.toColor(): Color = Color(r.toFloat(), g.toFloat(), b.toFloat())

private fun Color.toThemeRgb(): ThemeRgb =
    ThemeRgb(red.toDouble(), green.toDouble(), blue.toDouble())

/** `Color` 直指定の入口を、コアが受け取る hex 1 本に寄せるための橋。 */
private fun Color.toSeedHex(): String = "#%06X".format(toArgb() and 0xFFFFFF)
