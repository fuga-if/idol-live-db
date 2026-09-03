//! 無限色テーマエンジン: シード 1 色から UI トークン一式を機械的に導出する。
//!
//! ## なぜ 1 か所に置くか
//!
//! iOS `DesignSystem/ImasTheme.swift` (338 行) と Android `ui/theme/ImasTheme.kt` (213 行) は
//! 独立に書かれた同じ計算で、core 呼び出しはゼロだった。**同じシードから同じ色が出ないと
//! iOS と Android で見た目が変わる**ため、ここが二重にあること自体が事故の原因になる。
//! HSL 変換・WCAG コントラスト・トークン導出の規則だけをここへ集め、
//! `Color` 型の生成と描画は各 OS に残す (返すのは RGB の数値だけ)。
//!
//! ## 何を返すか
//!
//! すべての色は [`ThemeRgb`] = sRGB 各成分 **0.0–1.0 の f64** で返す。
//! SwiftUI `Color(.sRGB, red:green:blue:)` / Compose `Color(r, g, b)` がそのまま取る形で、
//! 原本 iOS (`clamp(v, 0, 255) / 255` を Double のまま渡す) とビット単位で一致する。
//! 8bit 整数に丸めて返すと原本より情報が落ちるので、そうしていない。
//!
//! ## 導出の考え方 (原本のコメントより)
//!
//! 集約 (一覧) では穏やか・フォーカス (詳細/担当ヒーロー) では鮮やか。色の優先順位は
//! 「アイドル色 → 所属ブランド色 → ニュートラル」のフォールバック連鎖 ([`derive`])。
//! 低彩度シード (S < 0.10) は「グレー」扱いで発色を抑える (`is_neutral`)。
//!
//! ## [`crate::domain::oshi_theme_resolution`] との関係 (重複させない)
//!
//! あちらは「**どのアイドルの色をシードにするか**」(担当の付け外し・ON/OFF に対する
//! 保存値の解決) を決める。ここは「**決まったシードからどんな色が出るか**」を決める。
//! 入口と出口の関係で、責務は重ならない。担当テーマは
//! `resolve_oshi_theme(...).color_hex` を [`derive`] の `seed` に渡す形で繋がる。
//!
//! ## hex ユーティリティを [`crate::domain::color_match`] から借りている理由
//!
//! `normalized_hex` / `hex_to_rgb` / [`Rgb`] は元をたどれば同じ Swift `ColorMath` の関数で、
//! 色当てゲームの移送 (Phase 8) の際に先に color_match へ移されている。ここで写経し直すと
//! **Rust の中に二重実装ができ**、この移送の目的そのものを裏切るので借りる。
//! 概念上の持ち主はこちら (ColorMath) なので [`normalized_hex`] / [`hex_to_rgb`] として
//! 再公開し、呼び出し側はこのモジュールだけを見ればよいようにしてある。
//!
//! ## 両 OS の乖離 (iOS を正として畳んだもの)
//!
//! 1. **hex のトリム範囲**: iOS は `.whitespaces` (改行を含まない)、Android は `trim()`
//!    (改行も落とす)。→ iOS に合わせ、`"#e22b30\n"` は**無効**として扱う
//!    (`color_match::normalized_hex` の `is_swift_whitespace` がこの規則)。
//! 1b. **U+200B (ZERO WIDTH SPACE)**: iOS の `.whitespaces` は Apple のドキュメント
//!    (「Zs + 水平タブ」= 18 文字) と違い、実装では U+200B を含む (実測 19 文字)。
//!    つまり `"\u{200b}#e22b30"` は iOS では**有効**で `"e22b30"` になる。
//!    Android の `trim()` (`Char.isWhitespace`) は U+200B を落とさないので無効。
//!    → iOS が正なので**有効**に倒した。**配線後は Android の見え方が変わる**:
//!    Web からのコピペで ZWSP が紛れ込んだ色が、今の Android では弾かれてニュートラル
//!    グレーになるところ、以後は `#E22B30` として通る (iOS と同じになる)。
//!    ここが逆向き (Rust が iOS より厳しい) だと、iOS `IdolEditView.canonicalColor` が
//!    正規化に失敗した入力を素通しする作りなので、**ZWSP 入りの生文字列がマスタの
//!    色として保存され、以後そのアイドルの色が読めなくなる**。
//! 2. **hex 桁の判定**: iOS `Character.isHexDigit` / Android `Char.isDigit()` はどちらも
//!    全角数字などを「16 進の桁」と認めてしまい、その先で iOS は黒 (`?? 0`)、Android は
//!    `toLong(16)` の例外でクラッシュする。→ ASCII 16 進数字のみ有効
//!    (color_match が既に倒している判断をそのまま継ぐ)。
//! 3. **Android に無い関数**: `derive(categoryKey:)` / `variant_hex` / `stable_hue` /
//!    `hex_string` / `on_color_over` / `ensure_contrast` は iOS にしかなかった。
//!    iOS が正なので全部ここに入れてある (配線すれば Android も同じ色を出せる)。
//! 4. **最終成分の型**: iOS は Double、Android は `toFloat() / 255f` で f32 に落としてから
//!    除算していた。ここは iOS に合わせて f64 で除算まで済ませて返す。Android 側で
//!    `.toFloat()` した結果は現行と f32 で 1 ULP ずれ得るが、8bit 表示では同一。

use crate::domain::color_match::Rgb;

// 概念上の持ち主はこちら。呼び出し側が color_match (ゲーム) を意識せずに済むよう再公開する。
pub use crate::domain::color_match::{hex_to_rgb, normalized_hex};

/// 色が無いときに使う低彩度グレーのシード (ニュートラル経路に落ちる)。
pub const NEUTRAL_SEED: &str = "#8E8E93";

/// `ensure_contrast` / `on_color` の既定コントラスト比 (WCAG AA 本文相当)。
pub const DEFAULT_MIN_CONTRAST_RATIO: f64 = 4.5;

/// 前景候補の黒。純黒ではなく僅かに青寄りの墨 (原本 `RGB(0x15, 0x16, 0x1A)`)。
const INK: Rgb = Rgb { r: 0x15 as f64, g: 0x16 as f64, b: 0x1A as f64 };
/// 前景候補の白。
const PAPER: Rgb = Rgb { r: 255.0, g: 255.0, b: 255.0 };

/// 彩度がこれ未満のシードは「グレー」扱いにして発色を抑える。
const NEUTRAL_SATURATION: f64 = 0.10;

// ---------------------------------------------------------------------------
// FFI で渡す型
// ---------------------------------------------------------------------------

/// sRGB の各成分 (0.0–1.0)。SwiftUI / Compose の `Color` にそのまま渡せる。
///
/// 0–255 ではなく 0–1 なのは、原本が `Color` を作る直前に `/255` まで済ませており、
/// その値をそのまま返すのが「1bit も変えない」最短経路だから。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct ThemeRgb {
    pub r: f64,
    pub g: f64,
    pub b: f64,
}

/// HSL 表現。`h` は **度 (0–360)**、`s` / `l` は 0.0–1.0。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct ThemeHsl {
    /// 色相 (度)。無彩色 (max == min) のときは 0。
    pub h: f64,
    pub s: f64,
    pub l: f64,
}

/// 一覧などで複数行ぶんのテーマをまとめて引くときの 1 行 (seed/brand の組)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ThemeSeedRequest {
    /// アイドル等のイメージカラー hex。無効・未設定なら `brand` へ落ちる。
    pub seed: Option<String>,
    /// ブランドカラー hex。`seed` が無いときのフォールバック。
    pub brand: Option<String>,
}

/// シード 1 色から導出されたテーマトークン一式。ライト/ダークで導出規則が変わる。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct ImasThemeColors {
    pub accent: ThemeRgb,
    /// `accent` の上に乗せる前景 (黒/白を WCAG で自動選択)。
    pub on_accent: ThemeRgb,
    pub tint: ThemeRgb,
    pub tint_strong: ThemeRgb,
    pub chip_bg: ThemeRgb,
    pub chip_text: ThemeRgb,
    pub ring: ThemeRgb,
    pub bar: ThemeRgb,
    pub dot: ThemeRgb,
    pub grad_from: ThemeRgb,
    pub grad_to: ThemeRgb,
    pub separator: ThemeRgb,
    pub hero_surface: ThemeRgb,
    /// 低彩度シード (S < 0.10) は「グレー」扱いで発色を抑える。
    pub is_neutral: bool,
}

// ---------------------------------------------------------------------------
// 数値ユーティリティ
// ---------------------------------------------------------------------------

/// 原本 Swift の `min(hi, max(lo, v))` と同じ評価順で挟む。
///
/// `f64::clamp` を使わないのは、`lo > hi` で panic する / NaN の扱いが違う等、
/// 標準の挟み込みが原本と別の関数だから。ここは原本の式をそのまま写す。
pub fn clamp(v: f64, lo: f64, hi: f64) -> f64 {
    // Swift.max(lo, v) は `v >= lo ? v : lo`、Swift.min(hi, m) は `m < hi ? m : hi`。
    let raised = if v >= lo { v } else { lo };
    if raised < hi {
        raised
    } else {
        hi
    }
}

/// 0–255 の RGB を `Color` 直前の 0.0–1.0 へ落とす (原本 `ColorMath.color(_ rgb:)`)。
fn to_theme_rgb(rgb: Rgb) -> ThemeRgb {
    ThemeRgb {
        r: clamp(rgb.r, 0.0, 255.0) / 255.0,
        g: clamp(rgb.g, 0.0, 255.0) / 255.0,
        b: clamp(rgb.b, 0.0, 255.0) / 255.0,
    }
}

/// HSL から直接 UI 色を作る (原本 `ColorMath.color(h:s:l:)`)。
/// `s` / `l` は 0–1 に挟んでから変換する。
pub fn color_from_hsl(h: f64, s: f64, l: f64) -> ThemeRgb {
    to_theme_rgb(hsl_to_rgb(h, clamp(s, 0.0, 1.0), clamp(l, 0.0, 1.0)))
}

// ---------------------------------------------------------------------------
// hex / HSL 変換
// ---------------------------------------------------------------------------

/// 最初に見つかった「有効な hex」の候補を返す (原本 `ColorMath.firstValidHex`)。
///
/// 返すのは正規化後ではなく**候補そのもの**。原本もそうで、後段の `hex_to_rgb` が
/// もう一度正規化するため結果は変わらない。
///
/// 注意: 3 文字がすべて 16 進数字なら短縮形として展開されるので、
/// `"876"` → `#887766` のように **ID 文字列が色として通ってしまう**。
/// ブランド ID をそのまま渡してはいけない (末尾「両 OS の乖離」参照)。
pub fn first_valid_hex<'a>(candidates: &[Option<&'a str>]) -> Option<&'a str> {
    candidates.iter().copied().flatten().find(|c| normalized_hex(c).is_some())
}

/// RGB (0–255) → HSL (h は度)。原本 `ColorMath.rgbToHsl` の写し。
pub fn rgb_to_hsl(rgb: Rgb) -> ThemeHsl {
    let (r, g, b) = (rgb.r / 255.0, rgb.g / 255.0, rgb.b / 255.0);
    let mx = r.max(g).max(b);
    let mn = r.min(g).min(b);
    let l = (mx + mn) / 2.0;
    let (mut h, mut s) = (0.0, 0.0);
    if mx != mn {
        let d = mx - mn;
        s = if l > 0.5 { d / (2.0 - mx - mn) } else { d / (mx + mn) };
        // 原本の `switch mx { case r / case g / default }` と同じ判定順。
        // r と g が同値のときは r 側が採られる (順序を入れ替えると色相が変わる)。
        h = if mx == r {
            (g - b) / d + if g < b { 6.0 } else { 0.0 }
        } else if mx == g {
            (b - r) / d + 2.0
        } else {
            (r - g) / d + 4.0
        };
        h /= 6.0;
    }
    ThemeHsl { h: h * 360.0, s, l }
}

/// HSL (h は度) → RGB (0–255)。原本 `ColorMath.hslToRgb` の写し。
pub fn hsl_to_rgb(h_deg: f64, s: f64, l: f64) -> Rgb {
    // 負の色相も 0–360 に畳む (`variant_hex` が h を ±16° 振るため負になり得る)。
    let h = (((h_deg % 360.0) + 360.0) % 360.0) / 360.0;
    if s == 0.0 {
        return Rgb { r: l * 255.0, g: l * 255.0, b: l * 255.0 };
    }
    let q = if l < 0.5 { l * (1.0 + s) } else { l + s - l * s };
    let p = 2.0 * l - q;
    Rgb {
        r: hue_to_rgb(p, q, h + 1.0 / 3.0) * 255.0,
        g: hue_to_rgb(p, q, h) * 255.0,
        b: hue_to_rgb(p, q, h - 1.0 / 3.0) * 255.0,
    }
}

fn hue_to_rgb(p: f64, q: f64, t_in: f64) -> f64 {
    let mut t = t_in;
    if t < 0.0 {
        t += 1.0;
    }
    if t > 1.0 {
        t -= 1.0;
    }
    if t < 1.0 / 6.0 {
        return p + (q - p) * 6.0 * t;
    }
    if t < 1.0 / 2.0 {
        return q;
    }
    if t < 2.0 / 3.0 {
        return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    }
    p
}

/// RGB (0–255) → `#rrggbb`。原本 `ColorMath.hexString(_ rgb:)` の写し。
pub fn hex_string(rgb: Rgb) -> String {
    format!("#{:02x}{:02x}{:02x}", to_byte(rgb.r), to_byte(rgb.g), to_byte(rgb.b))
}

/// 導出済みトークン (0.0–1.0 の sRGB) → `#rrggbb`。
///
/// [`hex_string`] が 0–255 の [`Rgb`] を取るのに対し、こちらは FFI で渡す
/// [`ThemeRgb`] (0–1) を取る。CSS 変数・HTML の色指定は必ずこの関数を通すこと
/// (掛け算と丸めを呼び出し側で書くと、丸め方向が 1 箇所ずれただけで
/// アプリと Web の色が食い違う)。
pub fn theme_hex(c: ThemeRgb) -> String {
    format!(
        "#{:02x}{:02x}{:02x}",
        (c.r * 255.0).round() as u32,
        (c.g * 255.0).round() as u32,
        (c.b * 255.0).round() as u32
    )
}

/// Swift `Int(clamp(v, 0, 255).rounded())` 相当。`rounded()` も `f64::round` も
/// 「0 から遠い側へ half を寄せる」なので丸め方向まで一致する。
fn to_byte(v: f64) -> u32 {
    clamp(v, 0.0, 255.0).round() as u32
}

// ---------------------------------------------------------------------------
// 文字列キー由来の色 (実体色を持たない分類のため)
// ---------------------------------------------------------------------------

/// 文字列から安定した色相 (0–360) を作る単純ハッシュ (FNV-1a)。
/// 同じ文字列は常に同じ色相になる。
pub fn stable_hue(key: &str) -> f64 {
    let mut hash: u64 = 1469598103934665603;
    for byte in key.as_bytes() {
        hash ^= *byte as u64;
        // 原本 Swift の `&*` (オーバーフロー許容乗算) と同じ。
        hash = hash.wrapping_mul(1099511628211);
    }
    (hash % 360) as f64
}

/// 安定色相から `#rrggbb` を合成する。実体色を持たない分類キーのための
/// 中彩度・中明度の基準シード。
pub fn hex_from_stable_hue(hue: f64) -> String {
    hex_string(hsl_to_rgb(hue, 0.55, 0.50))
}

/// 基準色 (ブランドカラー等) の色味を保ったまま、キーごとに少しだけ振ったバリエーション。
///
/// 「どのブランドか」は色相で伝えたいが、同じブランド内の複数系列は見分けたい、という
/// 場面のためのもの。[`derive_for_category_key`] は色相ごと変えてしまうのでブランドが
/// 混ざった一覧では所属が読めなくなる。ここでは **色相は ±16° まで**に抑え、
/// 主に明度で差を付けるので、隣り合っていても「同じブランドの別系列」に見える。
pub fn variant_hex(hex: &str, key: &str) -> String {
    let ThemeHsl { h, s, l } = rgb_to_hsl(hex_to_rgb(hex));
    let seed = stable_hue(key);
    // 5 段階 × 5 段階 = 25 通り。同じキーなら常に同じ色。
    let hue_shift = (seed % 5.0 - 2.0) * 8.0; // -16…16
    let light_shift = ((seed / 5.0).floor() % 5.0 - 2.0) * 0.07;
    hex_string(hsl_to_rgb(
        h + hue_shift,
        clamp(s, 0.35, 0.95),
        clamp(l + light_shift, 0.30, 0.68),
    ))
}

// ---------------------------------------------------------------------------
// WCAG コントラスト
// ---------------------------------------------------------------------------

/// WCAG 相対輝度。
pub fn rel_lum(rgb: Rgb) -> f64 {
    fn channel(x: f64) -> f64 {
        let c = x / 255.0;
        if c <= 0.03928 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    }
    0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
}

/// WCAG コントラスト比 (1.0–21.0)。引数の順序は結果に影響しない。
pub fn contrast(a: Rgb, b: Rgb) -> f64 {
    let (l1, l2) = (rel_lum(a), rel_lum(b));
    let hi = l1.max(l2);
    let lo = l1.min(l2);
    (hi + 0.05) / (lo + 0.05)
}

/// 複数の背景 (グラデーション停止色など) すべての上で読める黒/白を選ぶ。
///
/// 全停止色との**最小**コントラストで判定し、4.5:1 を満たす方を優先する
/// (白が満たすなら白。どちらも満たさないなら、まだマシな方)。
/// 黄色・白系・水色系の明るい背景で白文字を固定してしまう破綻を防ぐ共通入口。
pub fn on_color_over(backgrounds: &[Rgb]) -> Rgb {
    let c_ink = min_contrast(backgrounds, INK);
    let c_white = min_contrast(backgrounds, PAPER);
    if c_white >= DEFAULT_MIN_CONTRAST_RATIO {
        return PAPER;
    }
    if c_ink >= DEFAULT_MIN_CONTRAST_RATIO {
        return INK;
    }
    if c_white > c_ink {
        PAPER
    } else {
        INK
    }
}

/// 背景が空なら 0 を返す (原本の `.min() ?? 0`)。0 はどちらの閾値も満たさないので
/// 最後の比較 `c_white > c_ink` が `0 > 0` = false になり、墨が選ばれる。
fn min_contrast(backgrounds: &[Rgb], foreground: Rgb) -> f64 {
    let mut ratios = backgrounds.iter().map(|bg| contrast(*bg, foreground));
    match ratios.next() {
        None => 0.0,
        Some(first) => ratios.fold(first, |acc, v| if v < acc { v } else { acc }),
    }
}

/// 単一の面の上に乗せる前景色。原本は `onColor(over: [bg])` に委譲しており同義。
pub fn on_color(background: Rgb) -> Rgb {
    on_color_over(&[background])
}

/// `fg` の色相・彩度は保ったまま、`bg` から離れる方向へ明度を調整して
/// `min_ratio` 以上のコントラストを確保した RGB を返す。
///
/// chipText のような「着色インク」を白面に乗せる時、明るいシード (黄色等) でも
/// 読めるようにするための補正。明度が 0–1 を出たら打ち切って**その直前の色**を返すので、
/// 比率を満たせないまま返ることがある (原本と同じ。満たせない組み合わせで
/// 無限ループにも真っ黒にもしない、という判断)。
pub fn ensure_contrast(fg: Rgb, bg: Rgb, min_ratio: f64) -> Rgb {
    let ThemeHsl { h, s, l: start_l } = rgb_to_hsl(fg);
    let mut l = start_l;
    // 背景の方が明るければ暗い側へ、そうでなければ明るい側へ逃がす。
    let step = if rel_lum(bg) >= rel_lum(fg) { -0.02 } else { 0.02 };
    let mut current = fg;
    while contrast(current, bg) < min_ratio {
        l += step;
        if !(0.0..=1.0).contains(&l) {
            break;
        }
        current = hsl_to_rgb(h, s, l);
    }
    current
}

// ---------------------------------------------------------------------------
// 導出エントリポイント
// ---------------------------------------------------------------------------

/// シード hex (アイドル色) → トークン。色が無ければブランド色 → ニュートラルへ。
///
/// 原本の `derive(seed:brand:scheme:)` / `derive(hex:dark:)` / `derive(colorSeed:scheme:)`
/// はすべてこれで足りる。無効な hex は [`hex_to_rgb`] がニュートラルグレーへ倒すので、
/// 「seed だけ渡す」形と「hex を直接渡す」形の結果は一致する。
/// `Color` を直接シードにしたい場合は、各 OS で hex 化してから `seed` に渡す
/// (`Color` → 成分の取り出しは OS ブリッジなのでコアには持ち込まない)。
pub fn derive(seed: Option<&str>, brand: Option<&str>, dark: bool) -> ImasThemeColors {
    let hex = first_valid_hex(&[seed, brand]).unwrap_or(NEUTRAL_SEED);
    derive_from_hex(hex, dark)
}

/// 実体色を持たない「分類キー」(タグのカテゴリ名、編集フィードのレコード種別名等) から
/// 安定した色を導出する。同じキーは常に同じ色になる。
///
/// アイドル/ブランドの「本当の色」ではなく、3 種類以上の区分を見分けやすく塗り分けたい
/// だけの場面向け。固定パレットを手書きする代わりに使うと、区分がいくつ増えても
/// 保守なしで書き分けられる。
pub fn derive_for_category_key(key: &str, dark: bool) -> ImasThemeColors {
    derive_from_hex(&hex_from_stable_hue(stable_hue(key)), dark)
}

/// 単一の hex からトークンを導出する (原本 `compute`)。
///
/// メモ化は入れていない。原本がキャッシュを持っていたのは SwiftUI/Compose が
/// **描画のたび**に呼ぶからで、キャッシュは呼び出し側 (OS) に残す方が正しい。
/// FFI を要素数ぶん跨がせないための一括版が [`derive_batch`]。
pub fn derive_from_hex(hex: &str, dark: bool) -> ImasThemeColors {
    let ThemeHsl { h, s, l } = rgb_to_hsl(hex_to_rgb(hex));
    let neutral = s < NEUTRAL_SATURATION;
    let col = |hh: f64, ss: f64, ll: f64| color_from_hsl(hh, ss, ll);

    if !dark {
        let a_s = if neutral { clamp(s, 0.0, 0.10) } else { clamp(s, 0.42, 0.92) };
        let a_l = clamp(l, 0.30, 0.54);
        let accent = hsl_to_rgb(h, clamp(a_s, 0.0, 1.0), clamp(a_l, 0.0, 1.0));
        ImasThemeColors {
            accent: to_theme_rgb(accent),
            on_accent: to_theme_rgb(on_color(accent)),
            tint: col(h, if neutral { 0.04 } else { clamp(s * 0.5, 0.08, 0.34) }, 0.965),
            tint_strong: col(h, if neutral { 0.05 } else { clamp(s * 0.55, 0.10, 0.42) }, 0.910),
            chip_bg: col(h, if neutral { 0.05 } else { clamp(s * 0.5, 0.10, 0.34) }, 0.935),
            chip_text: col(
                h,
                if neutral { clamp(s, 0.0, 0.12) } else { clamp(s, 0.50, 0.95) },
                clamp(l, 0.24, 0.40),
            ),
            ring: col(h, a_s, clamp(a_l + 0.06, 0.0, 0.62)),
            bar: to_theme_rgb(accent),
            dot: to_theme_rgb(accent),
            grad_from: col(h, a_s, clamp(a_l + 0.05, 0.0, 0.60)),
            grad_to: col(h, clamp(a_s + 0.05, 0.0, 1.0), clamp(a_l - 0.10, 0.16, 1.0)),
            separator: col(h, if neutral { 0.04 } else { clamp(s * 0.4, 0.06, 0.24) }, 0.86),
            hero_surface: col(h, if neutral { 0.05 } else { clamp(s * 0.5, 0.10, 0.40) }, 0.955),
            is_neutral: neutral,
        }
    } else {
        let a_s = if neutral { clamp(s, 0.0, 0.14) } else { clamp(s, 0.45, 0.88) };
        let a_l = clamp(l, 0.56, 0.74);
        let accent = hsl_to_rgb(h, clamp(a_s, 0.0, 1.0), clamp(a_l, 0.0, 1.0));
        ImasThemeColors {
            accent: to_theme_rgb(accent),
            on_accent: to_theme_rgb(on_color(accent)),
            tint: col(h, if neutral { 0.06 } else { clamp(s * 0.5, 0.10, 0.42) }, 0.175),
            tint_strong: col(h, if neutral { 0.07 } else { clamp(s * 0.55, 0.12, 0.48) }, 0.235),
            chip_bg: col(h, if neutral { 0.07 } else { clamp(s * 0.5, 0.12, 0.42) }, 0.225),
            chip_text: col(h, a_s, clamp(a_l + 0.06, 0.0, 0.84)),
            ring: col(h, a_s, clamp(a_l, 0.0, 0.70)),
            bar: to_theme_rgb(accent),
            dot: to_theme_rgb(accent),
            grad_from: col(h, a_s, clamp(a_l, 0.0, 0.66)),
            grad_to: col(h, clamp(a_s + 0.04, 0.0, 1.0), clamp(a_l - 0.14, 0.30, 1.0)),
            separator: col(h, if neutral { 0.05 } else { clamp(s * 0.4, 0.08, 0.30) }, 0.30),
            hero_surface: col(h, if neutral { 0.06 } else { clamp(s * 0.5, 0.10, 0.45) }, 0.20),
            is_neutral: neutral,
        }
    }
}

/// 一覧 1 画面ぶんのテーマをまとめて導出する (入力と同じ順で返す)。
///
/// 行ごとに FFI を跨ぐ設計は禁止なので、行数ぶんの seed/brand を 1 回で渡す。
pub fn derive_batch(requests: &[ThemeSeedRequest], dark: bool) -> Vec<ImasThemeColors> {
    requests
        .iter()
        .map(|r| derive(r.seed.as_deref(), r.brand.as_deref(), dark))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// テーマ 1 件を `#rrggbb` 13 個 + isNeutral の 1 行に畳む。
    /// 基準値 (Swift 原本の出力) と同じ書式なので、そのまま突き合わせられる。
    fn row(t: &ImasThemeColors) -> String {
        let cells: Vec<String> = [
            t.accent,
            t.on_accent,
            t.tint,
            t.tint_strong,
            t.chip_bg,
            t.chip_text,
            t.ring,
            t.bar,
            t.dot,
            t.grad_from,
            t.grad_to,
            t.separator,
            t.hero_surface,
        ]
        .iter()
        .map(|c| theme_hex(*c))
        .chain(std::iter::once(if t.is_neutral { "1" } else { "0" }.to_string()))
        .collect();
        cells.join(",")
    }

    /// 基準値 (Swift 原本の出力) と突き合わせる書式。本体の `theme_hex` に委譲するので、
    /// 以下の一致テストがそのまま `theme_hex` の正しさの証明になる。
    fn hex_of(c: ThemeRgb) -> String {
        theme_hex(c)
    }

    // =======================================================================
    // 原本 (iOS ImasTheme.swift) との一致
    //
    // 以下の基準値は、ImasTheme.swift の該当行を **そのまま** 抜き出して
    // (SwiftUI/UIKit ブリッジ 3 関数だけ除去) ビルドしたオラクルの実出力。
    // 手で書き写した値ではないので、規則を写し損ねればここが落ちる。
    // =======================================================================

    /// master.sqlite の実データに入っている全シード色 (idols.color ∪ brands.color)。
    /// 397 色。`F0E68C` のように `#` 無し・`#fe0000` のように小文字のものも実在するため、
    /// 表記ゆれの吸収もこの掃き出しで一緒に検証される。
    const REAL_SEEDS: &str = "#006047 #006AB6 #006DB2 #009CBD #00A578 #00A878 #00ADB9 #01A860 #01AAA5 #01ADB9 \
         #02946C #0830A8 #0D386D #0E0C9F #0F0C9F #0F7BF8 #0fbe94 #111721 #144384 #171C8F \
         #1845B9 #1858B0 #1945BA #1A4FA8 #1B24C2 #1C23AA #1C90CD #1D9ADD #1F1451 #1FC1DD \
         #202449 #23CD7A #24130D #24CAD2 #2681c8 #274079 #2743D2 #276E4E #2943CB #2B5CD5 \
         #2E347E #33A8FF #375637 #38BAB8 #3A75BB #3B91C4 #3BAF29 #3D5AC8 #3F3538 #3F3C8B \
         #3F59A6 #436CA9 #43A0AB #454341 #45BDB4 #45F05B #471C87 #477525 #47D7AC #48C6DA \
         #4FA0CE #4FD962 #50D0D0 #515558 #520000 #521078 #52C6C3 #552A7C #554171 #55565A \
         #56CCF2 #5756D8 #57B3E5 #5881C1 #58A6DC #58EABD #59B7DB #5A2B8D #5ABFB7 #5C068F \
         #5CE626 #5FBEEC #606CB2 #606EB2 #618D75 #633AA1 #6495CF #653A2A #656a75 #69B64C \
         #6AC4E9 #6BB6B0 #6DBCDB #6bb6b9 #7048A0 #7090C0 #71D448 #7271B3 #7278A8 #74C2D5 \
         #74D1EA #75BBAE #75DED5 #760E10 #7664A0 #781000 #78853A #788BC5 #7967C3 #79A5DF \
         #7A508F #7ADAD6 #7C8EA2 #7D0837 #7E6CA8 #7F6575 #80C260 #80C8B0 #80D0F0 #819832 \
         #84329B #86DBFF #88D080 #88E060 #89C3EB #8BDC63 #8D75B3 #8D8696 #8E8E93 #90E667 \
         #9238BE #92CFBB #93256C #94D509 #97D3D3 #99B7DC #99E3FC #9B274A #9B58C2 #9BCE92 \
         #9CD0F0 #9E1861 #9E40C8 #9F25B6 #9FE1FD #A01B50 #A088C0 #A093F3 #A0B6DC #A21D3C \
         #A2D55E #A2FD47 #A42678 #A453A6 #A5CFB6 #A6126A #A80826 #A846FB #A85FCF #A8D880 \
         #A8D8F0 #A90582 #A9A3E1 #AAC5E2 #AC162A #ACC0E6 #AD1E66 #ADE5F6 #AEB49C #AFA690 \
         #B04EC5 #B0B0B0 #B0C5E4 #B2D468 #B4E04B #B54461 #B63B40 #B6DDE4 #B72089 #BB68FE \
         #BC1212 #BE1E3E #BEE3E3 #C2E189 #C3396C #C4D673 #C58E31 #C5A6E2 #C5DD7F #C64796 \
         #C7B83C #C7BAB4 #C82F7F #C8C8D0 #C8E8E0 #C90F74 #C9870F #C9C9C9 #CA113A #CA9111 \
         #CB78B0 #CBFC9F #CC252D #CCAACF #CF142B #CF9E51 #D02850 #D0303C #D06447 #D1197B \
         #D13037 #D1342C #D162CB #D1F9E6 #D30D85 #D3161C #D3DDE9 #D42E38 #D72630 #D7385F \
         #D7A96B #D7F930 #D8002A #D8076B #D83C6A #D8843E #D95E25 #D967A3 #D9F2FF #DE2F4D \
         #DEE2EB #E0B5D3 #E0E101 #E22B30 #E25A9B #E31C1A #E31C93 #E40C28 #E41C1A #E44E8E \
         #E5461C #E56F66 #E5E1E6 #E5F9E4 #E63950 #E63C2E #E75BEC #E7CBEE #E85786 #E87487 \
         #E89070 #E89B55 #E89CDC #E8BAD6 #E8E8E8 #E94047 #E9425C #E9463D #E94D1A #E95B64 \
         #E9739B #E9870C #EA495B #EA4A5B #EA4F21 #EA5B76 #EA8A91 #EAD7A4 #EADC62 #EAE28D \
         #EB306D #EB3249 #EB613F #EB6174 #EBE1FF #EC4B6E #EC5800 #EC7092 #ECCCCD #ECEB70 \
         #ED0829 #ED3767 #ED90BA #EE7220 #EE7602 #EE762E #EF4A81 #EF8472 #EF93BC #EFB817 \
         #EFB864 #EFD7E5 #EFFDFF #F09079 #F098B8 #F0A040 #F0C420 #F0F0F0 #F125C1 #F14FEE \
         #F16029 #F19557 #F19591 #F196FF #F1BECB #F2C0C1 #F30100 #F32333 #F39939 #F4A6D7 \
         #F4ABB4 #F4D059 #F4D956 #F54275 #F567C6 #F5AD3B #F5C400 #F5D24B #F5D6FF #F6303F \
         #F6B128 #F6BD30 #F743A6 #F7A1BA #F7B5C4 #F7BD05 #F7D30D #F7DE8C #F7E78E #F84CAD \
         #F851A7 #F8A3BC #F8AC5E #F8B500 #F8B7C8 #F8C112 #F8C559 #F8C5C1 #F8C715 #F93B90 \
         #F97F4B #F994C4 #F9C4D6 #F9C584 #FA7EB4 #FA9063 #FA90A2 #FBC0D0 #FBE890 #FBE983 \
         #FBFAFA #FC6E2E #FC87BF #FCA538 #FCC138 #FD9286 #FD99E1 #FDFF4E #FE6B02 #FE85C7 \
         #FEC520 #FED552 #FEE806 #FEEA9C #FF00FF #FF3DE5 #FF4554 #FF4F8B #FF5D14 #FF68B5 \
         #FF6F61 #FF7B2C #FF8800 #FF8FB0 #FF9E1B #FFB0B8 #FFB888 #FFBAD6 #FFBE60 #FFC1BD \
         #FFC602 #FFC639 #FFCB49 #FFD9DB #FFDA7B #FFDC00 #FFE012 #FFE058 #FFE13C #FFE43F \
         #FFF03C #FFFB4E #FFFFFF #f39800 #fe0000 #ffc30b F0E68C";

    /// 397 色 × light/dark の全 13 トークンを掃き出したものの FNV-1a ダイジェスト。
    ///
    /// 1 色でも 1 トークンでも規則がずれれば値が変わる。個別の期待値を 794 行並べる
    /// 代わりに、実データ全域の一致を 1 個の数値で押さえている。
    /// 基準値は Swift オラクルの出力 (SWEEP_DIGEST)。
    #[test]
    fn matches_ios_over_every_real_seed_color() {
        // NOTE: REAL_SEEDS は読みやすさのため空白区切りで畳んである。
        // オラクル側は 1 行 1 色だったので、同じ順序で復元して突き合わせる。
        let seeds: Vec<&str> = REAL_SEEDS.split_whitespace().collect();
        assert_eq!(seeds.len(), 397, "実データのシード数");

        let mut sweep = String::new();
        for seed in &seeds {
            for dark in [false, true] {
                sweep.push_str(seed);
                sweep.push('|');
                sweep.push(if dark { 'd' } else { 'l' });
                sweep.push('|');
                sweep.push_str(&row(&derive_from_hex(seed, dark)));
                sweep.push('\n');
            }
        }
        assert_eq!(fnv1a(&sweep), 641_723_774_608_162_219, "実データ全色の掃き出しが原本と一致");
    }

    /// ダイジェストと同じハッシュ (原本 `stable_hue` と同じ FNV-1a)。
    fn fnv1a(s: &str) -> u64 {
        let mut h: u64 = 1469598103934665603;
        for b in s.as_bytes() {
            h ^= *b as u64;
            h = h.wrapping_mul(1099511628211);
        }
        h
    }

    /// 境界を踏む代表色の全トークン。ダイジェストが落ちたとき「どこがずれたか」を
    /// 読めるようにするための、人が目で追える基準値。
    #[test]
    fn matches_ios_token_by_token_for_representative_seeds() {
        // (シード, dark, 13 トークン + isNeutral)
        let cases: &[(&str, bool, &str)] = &[
            ("#E22B30", false, "#e22b30,#ffffff,#f9f3f3,#f2dedf,#f4e9e9,#b3191d,#e6464a,#e22b30,#e22b30,#e54146,#c5151a,#e4d3d3,#f8efef,0"),
            ("#E22B30", true, "#e43a3e,#15161a,#3e1c1d,#552324,#4f2425,#e85559,#e43a3e,#e43a3e,#e43a3e,#e43a3e,#c1151a,#633637,#462021,0"),
            // 黄色: accent が明るく onAccent が白では読めない → 墨に倒れる代表例。
            ("#FFE43F", false, "#f6d71e,#15161a,#f9f8f3,#f2efde,#f4f2e9,#c7ac05,#f7dc3b,#f6d71e,#f6d71e,#f7dc36,#ddbe03,#e4e1d3,#f8f7ef,0"),
            ("#FFE43F", true, "#f3dc4b,#15161a,#3f3a1a,#59511f,#514b21,#f5e167,#f3dc4b,#f3dc4b,#f3dc4b,#f3dc4b,#edcd0a,#635d36,#4a431c,0"),
            ("#2743D2", false, "#2743d2,#ffffff,#f3f4f9,#dfe2f1,#e9ebf4,#2037ac,#3d57db,#2743d2,#2743d2,#3853da,#1a32ac,#d3d6e4,#f0f1f7,0"),
            ("#2743D2", true, "#425bdc,#ffffff,#1d223c,#252d53,#262c4d,#5c71e1,#425bdc,#425bdc,#425bdc,#425bdc,#1d37b9,#373e62,#212745,0"),
        ];
        for (seed, dark, expected) in cases {
            assert_eq!(row(&derive_from_hex(seed, *dark)), *expected, "seed={seed} dark={dark}");
        }
    }

    /// 8bit に丸めると隠れてしまう差を捕まえるため、成分を f64 のまま突き合わせる。
    ///
    /// 基準値は Swift オラクルの `%.17g` 出力を、同じ f64 に戻る最短表記へ縮めたもの
    /// (ビット単位で同値。`0.78000000000000003` と `0.78` は同じ Double)。
    #[test]
    fn matches_ios_at_full_double_precision() {
        let t = derive_from_hex("#FFE43F", false);
        assert_eq!(t.accent.r, 0.9631999999999998);
        assert_eq!(t.accent.g, 0.8441749999999999);
        assert_eq!(t.accent.b, 0.11680000000000024);
        assert_eq!(t.grad_to.r, 0.8668000000000002);
        assert_eq!(t.grad_to.g, 0.7467625000000002);
        assert_eq!(t.grad_to.b, 0.013199999999999878);
        assert_eq!(t.chip_text.r, 0.78);
        assert_eq!(t.chip_text.g, 0.6731250000000001);
        assert_eq!(t.chip_text.b, 0.02000000000000002);

        let d = derive_from_hex("#01ADB9", true);
        assert_eq!(d.accent.r, 0.1728000000000003);
        assert_eq!(d.accent.g, 0.8966956521739124);
        assert_eq!(d.accent.b, 0.9471999999999998);
        assert_eq!(d.hero_surface.r, 0.11000000000000004);
        assert_eq!(d.hero_surface.g, 0.2782608695652173);
        assert_eq!(d.hero_surface.b, 0.29);
    }

    // --- seed → brand → ニュートラル のフォールバック連鎖 ---

    /// 基準値は Swift オラクルの FALLBACK 行 (accent と isNeutral)。
    #[test]
    fn falls_back_from_seed_to_brand_to_neutral() {
        let accent = |s: Option<&str>, b: Option<&str>| {
            let t = derive(s, b, false);
            (hex_of(t.accent), t.is_neutral)
        };
        // seed が有効なら brand は見ない。
        assert_eq!(accent(Some("#E22B30"), Some("#fe0000")), ("#e22b30".into(), false));
        // seed 無し → brand。
        assert_eq!(accent(None, Some("#fe0000")), ("#f40a0a".into(), false));
        // どちらも無し → ニュートラル (is_neutral が立つ)。
        assert_eq!(accent(None, None), ("#87878c".into(), true));
        // 3 桁短縮も有効な seed。
        assert_eq!(accent(Some("#f0a"), Some("#fe0000")), ("#f50aa7".into(), false));
    }

    /// 無効な hex を直接 `derive_from_hex` に渡した結果と、seed/brand 両方欠けた
    /// `derive` の結果は一致する (どちらもニュートラルグレーに落ちる)。
    /// 原本の 3 つの derive 入口を 1 本に畳める根拠。
    #[test]
    fn invalid_hex_and_missing_seed_land_on_the_same_neutral() {
        assert_eq!(derive_from_hex("not-a-color", true), derive(None, None, true));
        assert_eq!(derive_from_hex("not-a-color", false), derive_from_hex(NEUTRAL_SEED, false));
    }

    /// **移送時に見つけた事故のガード**: 3 文字がすべて 16 進数字の ID は
    /// 短縮 hex として展開され、色として通ってしまう。
    /// Android がブランド ID をそのまま `brand` に渡していたため、`876` / `961` の
    /// ユニット・楽曲だけ実ブランド色ではないテーマになっていた (レポート参照)。
    /// 規則自体は原本どおりなので変えない。踏んだら気付けるようテストで明文化する。
    #[test]
    fn three_hex_digit_ids_are_silently_valid_colors() {
        assert_eq!(normalized_hex("876").as_deref(), Some("887766"));
        assert_eq!(normalized_hex("961").as_deref(), Some("996611"));
        // 実ブランド色 (#656a75 / #520000) とは別物になる。
        assert_ne!(derive(None, Some("876"), true), derive(None, Some("#656a75"), true));
        assert_ne!(derive(None, Some("961"), true), derive(None, Some("#520000"), true));
        // 16 進にならない ID はきちんと無効 → ニュートラルへ。
        for id in ["765as", "cg", "ml", "sc", "sidem", "gakuen", "other"] {
            assert!(normalized_hex(id).is_none(), "{id} は色として通ってはいけない");
        }
    }

    // --- 分類キー由来の色 ---

    /// 基準値は Swift オラクルの CATEGORY 行 (stable_hue / hex_from_stable_hue / accent)。
    #[test]
    fn matches_ios_for_category_keys() {
        let cases: &[(&str, f64, &str, &str, &str)] = &[
            ("idol", 133.0, "#39c658", "#51cd6c", "#39c658"),
            ("song", 338.0, "#c6396d", "#cd517f", "#c6396d"),
            ("unit", 41.0, "#c69939", "#cda551", "#c69939"),
            ("event", 17.0, "#c66139", "#cd7451", "#c66139"),
            ("setlist_item", 325.0, "#c6398b", "#cd5199", "#c6398b"),
            ("tag", 137.0, "#39c661", "#51cd74", "#39c661"),
            ("poll", 18.0, "#c66339", "#cd7651", "#c66339"),
            ("", 43.0, "#c69e39", "#cdaa51", "#c69e39"),
            // 非 ASCII キーも UTF-8 バイト列で同じハッシュになる。
            ("アイドル", 183.0, "#39bfc6", "#51c7cd", "#39bfc6"),
            ("876", 68.0, "#b3c639", "#bccd51", "#b3c639"),
            ("765as", 281.0, "#9939c6", "#a551cd", "#9939c6"),
            ("a", 6.0, "#c64739", "#cd5d51", "#c64739"),
        ];
        for (key, hue, seed_hex, dark_accent, light_accent) in cases {
            assert_eq!(stable_hue(key), *hue, "stable_hue({key})");
            assert_eq!(hex_from_stable_hue(stable_hue(key)), *seed_hex, "seed hex ({key})");
            assert_eq!(hex_of(derive_for_category_key(key, true).accent), *dark_accent, "dark ({key})");
            assert_eq!(hex_of(derive_for_category_key(key, false).accent), *light_accent, "light ({key})");
        }
    }

    /// 同じキーは何度呼んでも同じ色 (決定的)。分類色が描画のたびに変わらない根拠。
    #[test]
    fn category_key_color_is_deterministic() {
        assert_eq!(derive_for_category_key("idol", true), derive_for_category_key("idol", true));
        assert_ne!(derive_for_category_key("idol", true), derive_for_category_key("song", true));
    }

    // --- variant_hex ---

    /// 基準値は Swift オラクルの VARIANT 行。
    #[test]
    fn matches_ios_for_variant_hex() {
        let cases: &[(&str, &str, &str)] = &[
            ("#fe0000", "live", "#d5053d"),
            ("#fe0000", "release", "#d5053d"),
            ("#fe0000", "anniversary", "#b20505"),
            ("#fe0000", "birthday", "#d5053d"),
            ("#fe0000", "cd", "#fa624b"),
            ("#fe0000", "bd", "#f84706"),
            ("#fe0000", "", "#f94428"),
            ("#2681c8", "live", "#2092aa"),
            ("#2681c8", "anniversary", "#1b5a8c"),
            ("#2681c8", "cd", "#5691df"),
            ("#2681c8", "bd", "#2656c8"),
            ("#2681c8", "", "#387dd9"),
            // 低彩度の基準色でも彩度は 0.35 まで持ち上がる (clamp(s, 0.35, 0.95))。
            ("#8e8e93", "live", "#526aab"),
            ("#8e8e93", "anniversary", "#474793"),
            ("#8e8e93", "cd", "#9891ca"),
        ];
        for (hex, key, expected) in cases {
            assert_eq!(variant_hex(hex, key), *expected, "variant_hex({hex}, {key})");
        }
    }

    /// 色相のブレは ±16° に収まる (同じブランドの別系列に見せるための制約)。
    /// 25 通りの全組み合わせを踏むだけのキーを回して確かめる。
    #[test]
    fn variant_hex_keeps_hue_within_sixteen_degrees() {
        let base = rgb_to_hsl(hex_to_rgb("#2681c8")).h;
        for i in 0..200u32 {
            let key = format!("k{i}");
            let got = rgb_to_hsl(hex_to_rgb(&variant_hex("#2681c8", &key))).h;
            // 8bit へ丸めた hex から読み直すので、丸め由来の 1° 弱を許容する。
            let delta = (got - base).abs().min(360.0 - (got - base).abs());
            assert!(delta <= 17.0, "key={key} hue delta={delta}");
        }
    }

    // --- WCAG ---

    /// 基準値は Swift オラクルの ONCOLOR 行 (前景 / 相対輝度 / 白とのコントラスト)。
    #[test]
    fn matches_ios_for_contrast_and_on_color() {
        let cases: &[(&str, &str, f64, f64)] = &[
            ("#E22B30", "#ffffff", 0.18109905186754757, 4.5435063082898255),
            // 黄色や水色の明るい面は白文字が読めないので墨に倒れる。
            ("#FFE43F", "#15161a", 0.7710568646046753, 1.2788395606503538),
            ("#ffffff", "#15161a", 1.0, 1.0),
            ("#000000", "#ffffff", 0.0, 21.0),
            ("#01ADB9", "#15161a", 0.33396375817933865, 2.734633093963974),
            ("#8E8E93", "#15161a", 0.27203369141874856, 3.260528410471992),
            ("#520000", "#ffffff", 0.017938382574286038, 15.45518100687628),
            ("#f39800", "#15161a", 0.4151115923336822, 2.2575227478886504),
        ];
        for (hex, on, lum, vs_white) in cases {
            let rgb = hex_to_rgb(hex);
            assert_eq!(hex_string(on_color(rgb)), *on, "on_color({hex})");
            assert_eq!(rel_lum(rgb), *lum, "rel_lum({hex})");
            assert_eq!(contrast(rgb, hex_to_rgb("#ffffff")), *vs_white, "contrast({hex}, white)");
        }
    }

    /// 複数背景版。空配列は `.min() ?? 0` の経路で墨になる (原本と同じ)。
    #[test]
    fn matches_ios_for_on_color_over_multiple_backgrounds() {
        assert_eq!(hex_string(on_color_over(&[])), "#15161a");
        // 白と黒の両方の上で 4.5 を満たす色は無い → 「まだマシな方」= 墨。
        let white_black = [hex_to_rgb("#ffffff"), hex_to_rgb("#000000")];
        assert_eq!(hex_string(on_color_over(&white_black)), "#15161a");
        // 黄→橙のグラデーションはどちらも明るいので墨。
        let warm = [hex_to_rgb("#FFE43F"), hex_to_rgb("#f39800")];
        assert_eq!(hex_string(on_color_over(&warm)), "#15161a");
        // 単色版は 1 要素版と同義 (原本が `onColor(over: [bg])` へ委譲している)。
        assert_eq!(on_color(hex_to_rgb("#E22B30")), on_color_over(&[hex_to_rgb("#E22B30")]));
    }

    /// 基準値は Swift オラクルの ENSURE 行 (補正後の hex と、そのコントラスト比)。
    #[test]
    fn matches_ios_for_ensure_contrast() {
        let cases: &[(&str, &str, &str, f64)] = &[
            // 明るい黄色を白面に乗せる代表例。明度を下げて 4.5 を超えるまで歩く。
            ("#FFE43F", "#ffffff", "#867300", 4.671425327721268),
            // 既に満たしていれば 1 歩も動かさない。
            ("#E22B30", "#ffffff", "#e22b30", 4.5435063082898255),
            // 黒面では明るい側へ逃がす。
            ("#2743D2", "#000000", "#566de0", 4.659379525105646),
            ("#ffffff", "#ffffff", "#757575", 4.587807276493158),
            ("#8e8e93", "#8e8e93", "#252526", 4.720388891125163),
            ("#000000", "#ffffff", "#000000", 21.0),
        ];
        for (fg, bg, expected, ratio) in cases {
            let got = ensure_contrast(hex_to_rgb(fg), hex_to_rgb(bg), DEFAULT_MIN_CONTRAST_RATIO);
            assert_eq!(hex_string(got), *expected, "ensure_contrast({fg} on {bg})");
            assert_eq!(contrast(got, hex_to_rgb(bg)), *ratio);
        }
    }

    /// 明度が 0–1 を出たら打ち切り、**その直前の色**を返す (比率未達で返り得る)。
    /// 無限ループにも真っ黒にもしない、という原本の判断を固定する。
    /// 基準値は Swift オラクルの ENSURE_R 行 (minRatio を明示した呼び出し)。
    #[test]
    fn ensure_contrast_gives_up_instead_of_looping_forever() {
        let white = hex_to_rgb("#ffffff");
        // 白面に白を乗せて 21:1 を要求しても到達できない。`l` を 0.02 ずつ下げる途中で
        // 累積誤差により 0.0 を僅かに下回って打ち切られるため、真っ黒ではなく
        // その 1 歩手前 (#050505 / 20.37:1) が返る。原本と同じ値。
        let got = ensure_contrast(white, white, 21.0);
        assert_eq!(hex_string(got), "#050505");
        assert_eq!(contrast(got, white), 20.369369369369387);
        assert!(contrast(got, white) < 21.0, "満たせないまま返る");

        // 黒面に黒: 暗い側へ逃がそうとして即座に範囲外 → 1 歩も動かず fg のまま返る。
        let black = hex_to_rgb("#000000");
        assert_eq!(hex_string(ensure_contrast(black, black, 21.0)), "#000000");
        assert_eq!(contrast(ensure_contrast(black, black, 21.0), black), 1.0);

        // 到達可能なら要求比率を満たすまで歩く。
        assert_eq!(hex_string(ensure_contrast(hex_to_rgb("#8e8e93"), white, 7.0)), "#56565a");
        assert_eq!(
            hex_string(ensure_contrast(hex_to_rgb("#E22B30"), hex_to_rgb("#E22B30"), 4.5)),
            "#0c0202"
        );
    }

    // --- hex 正規化 (両 OS の乖離を畳んだ規則) ---

    /// 基準値は Swift オラクルの NORM 行。
    #[test]
    fn matches_ios_for_hex_normalization() {
        let cases: &[(&str, Option<&str>)] = &[
            ("#E22B30", Some("e22b30")),
            ("e22b30", Some("e22b30")),
            ("#f0a", Some("ff00aa")),
            ("f0a", Some("ff00aa")),
            ("  #E22B30  ", Some("e22b30")),
            ("#E22B3", None),
            ("#E22B300", None),
            ("", None),
            ("#GGGGGG", None),
            // iOS の `.whitespaces` は改行を含まない。Android の `trim()` は落とすので
            // ここが乖離点。iOS を正として「無効」に倒してある。
            ("#e22b30\n", None),
            // 逆に iOS の `.whitespaces` は U+200B を含む (Android の `trim()` は含まない)。
            // iOS を正として「有効」に倒してある (全走査は
            // `hex_trim_matches_the_ios_whitespace_set_exactly`)。
            ("\u{200b}#E22B30", Some("e22b30")),
            ("##e22b30", None),
            ("F0E68C", Some("f0e68c")),
            ("#FFF", Some("ffffff")),
        ];
        for (input, expected) in cases {
            assert_eq!(normalized_hex(input).as_deref(), *expected, "normalized_hex({input:?})");
        }
    }

    /// トリムの境界が iOS と 1 文字も違わないこと。
    ///
    /// 基準値は macOS の Foundation を 0..=0x10FFFF まで走査した**実測**の
    /// `CharacterSet.whitespaces` (19 文字)。Apple のドキュメントの「Zs + 水平タブ」
    /// (18 文字) には U+200B が無く、そちらを信じると 1 文字ぶん厳しくなる。
    ///
    /// 厳しすぎる側に倒れると `IdolEditView.canonicalColor` が正規化できない入力を
    /// 素通しするため、**ZWSP 入りの生文字列がマスタの色として保存され、以後その
    /// アイドルの色が読めなくなる** (モジュール冒頭の乖離 1b)。
    #[test]
    fn hex_trim_matches_the_ios_whitespace_set_exactly() {
        // iOS `CharacterSet.whitespaces` の実メンバ。U+200B は Zs ではなく Cf だが入っている。
        const TRIMMED: &[char] = &[
            '\u{9}', '\u{20}', '\u{a0}', '\u{1680}', '\u{2000}', '\u{2001}', '\u{2002}',
            '\u{2003}', '\u{2004}', '\u{2005}', '\u{2006}', '\u{2007}', '\u{2008}',
            '\u{2009}', '\u{200a}', '\u{200b}', '\u{202f}', '\u{205f}', '\u{3000}',
        ];
        // 空白に見えるが `.whitespaces` の外にあるもの。改行類 7 文字は「原本が
        // `.whitespacesAndNewlines` を使っていない」ことの、幅ゼロ 4 文字は
        // 「U+200B だけが例外扱いされている」ことの押さえ。
        const KEPT: &[char] = &[
            '\u{a}', '\u{b}', '\u{c}', '\u{d}', '\u{85}', '\u{2028}', '\u{2029}',
            '\u{180e}', '\u{feff}', '\u{200c}', '\u{2060}',
        ];
        assert_eq!(TRIMMED.len(), 19, "iOS の実測メンバ数");

        for c in TRIMMED {
            for input in [format!("{c}#e22b30"), format!("#e22b30{c}"), format!("{c}#e22b30{c}")] {
                assert_eq!(
                    normalized_hex(&input).as_deref(),
                    Some("e22b30"),
                    "U+{:04X} は iOS ではトリムされる",
                    *c as u32
                );
            }
            // 3 桁短縮もトリム後に展開されること (桁数を数える前に落とす順序の確認)。
            assert_eq!(normalized_hex(&format!("{c}#f0a")).as_deref(), Some("ff00aa"));
        }

        for c in KEPT {
            for input in [format!("{c}#e22b30"), format!("#e22b30{c}"), format!("{c}#e22b30{c}")] {
                assert_eq!(
                    normalized_hex(&input),
                    None,
                    "U+{:04X} は iOS ではトリムされない",
                    *c as u32
                );
            }
        }

        // 内側の空白は原本もトリムしない (前後だけを落とす)。
        assert_eq!(normalized_hex("#e2 2b30"), None);
        assert_eq!(normalized_hex("#e2\u{200b}2b30"), None);
    }

    /// トリムの取りこぼしは `normalized_hex` だけでなく**導出色そのもの**を変える。
    /// `hex_to_rgb` が読めない hex をニュートラルグレーへ倒すため、ZWSP 入りのシードは
    /// 「無彩色のテーマ」になって一覧ごと色が消える。
    #[test]
    fn zero_width_space_seed_derives_the_same_theme_as_the_bare_hex() {
        for dark in [false, true] {
            let bare = derive(Some("#E22B30"), None, dark);
            assert_eq!(derive(Some("\u{200b}#E22B30"), None, dark), bare);
            assert_eq!(derive(Some("#E22B30\u{200b}"), None, dark), bare);
            // ニュートラル落ちしていないこと (取りこぼすとこちらと一致してしまう)。
            assert_ne!(bare, derive(None, None, dark));
            assert!(!bare.is_neutral);
            // 改行はトリムしないので、こちらは今まで通りニュートラルへ落ちる。
            assert_eq!(derive(Some("#E22B30\n"), None, dark), derive(None, None, dark));
        }
    }

    /// `first_valid_hex` は候補を先頭から見て、最初の有効なものを**そのまま**返す
    /// (正規化しない)。nil はスキップして次を見る。
    #[test]
    fn first_valid_hex_returns_the_first_usable_candidate_verbatim() {
        assert_eq!(first_valid_hex(&[Some("#E22B30"), Some("#fe0000")]), Some("#E22B30"));
        assert_eq!(first_valid_hex(&[None, Some("#fe0000")]), Some("#fe0000"));
        assert_eq!(first_valid_hex(&[Some("nope"), Some("#fe0000")]), Some("#fe0000"));
        assert_eq!(first_valid_hex(&[None, None]), None);
        assert_eq!(first_valid_hex(&[Some(""), Some("bad!")]), None);
        assert_eq!(first_valid_hex(&[]), None);
    }

    // --- HSL 変換の往復 ---

    /// 実データ全色で `hex → HSL → RGB` が元の 8bit に戻る (変換が情報を落とさない)。
    #[test]
    fn hsl_round_trip_preserves_every_real_seed() {
        for seed in REAL_SEEDS.split_whitespace() {
            let rgb = hex_to_rgb(seed);
            let hsl = rgb_to_hsl(rgb);
            assert_eq!(
                hex_string(hsl_to_rgb(hsl.h, hsl.s, hsl.l)),
                hex_string(rgb),
                "round trip: {seed}"
            );
        }
    }

    /// 無彩色は色相 0・彩度 0 に落ち、`hsl_to_rgb` の s == 0 の近道を通る。
    #[test]
    fn achromatic_seeds_take_the_saturation_zero_shortcut() {
        for gray in ["#000000", "#7f7f7f", "#ffffff"] {
            let hsl = rgb_to_hsl(hex_to_rgb(gray));
            assert_eq!(hsl.h, 0.0);
            assert_eq!(hsl.s, 0.0);
            assert_eq!(hex_string(hsl_to_rgb(hsl.h, hsl.s, hsl.l)), gray);
        }
    }

    /// 色相は 0–360 の外でも畳まれる (`variant_hex` が負の色相を作り得るため)。
    #[test]
    fn hue_wraps_outside_zero_to_three_sixty() {
        let base = hsl_to_rgb(20.0, 0.6, 0.5);
        assert_eq!(hsl_to_rgb(380.0, 0.6, 0.5), base);
        assert_eq!(hsl_to_rgb(-340.0, 0.6, 0.5), base);
    }

    // --- ニュートラル判定 ---

    /// 彩度 0.10 が境界。下回ればグレー扱いで発色を抑える。
    #[test]
    fn neutral_flag_follows_the_saturation_threshold() {
        // #8e8e93 は s ≒ 0.02 → ニュートラル。
        assert!(derive_from_hex("#8e8e93", false).is_neutral);
        assert!(derive_from_hex("#000000", false).is_neutral);
        assert!(derive_from_hex("#ffffff", true).is_neutral);
        // 実アイドル色はいずれも十分に彩度がある。
        assert!(!derive_from_hex("#E22B30", false).is_neutral);
        assert!(!derive_from_hex("#01ADB9", true).is_neutral);
        // ニュートラルは light/dark を問わず同じ判定 (シードの彩度だけで決まる)。
        for seed in ["#8e8e93", "#E22B30"] {
            assert_eq!(
                derive_from_hex(seed, false).is_neutral,
                derive_from_hex(seed, true).is_neutral
            );
        }
    }

    // --- 一括版 ---

    /// 一括版は 1 件ずつ呼んだ結果と同じものを、同じ順で返す。
    #[test]
    fn batch_matches_one_by_one_and_keeps_input_order() {
        let requests = vec![
            ThemeSeedRequest { seed: Some("#E22B30".into()), brand: Some("#fe0000".into()) },
            ThemeSeedRequest { seed: None, brand: Some("#fe0000".into()) },
            ThemeSeedRequest { seed: None, brand: None },
            ThemeSeedRequest { seed: Some("bogus".into()), brand: None },
        ];
        let batched = derive_batch(&requests, true);
        let expected: Vec<_> = requests
            .iter()
            .map(|r| derive(r.seed.as_deref(), r.brand.as_deref(), true))
            .collect();
        assert_eq!(batched, expected);
        assert_eq!(batched.len(), 4);
        // 同じ入力が並んでも取り違えない (順序が保たれる)。
        assert_eq!(batched[0], derive(Some("#E22B30"), Some("#fe0000"), true));
        assert_eq!(batched[2], derive(None, None, true));
    }

    #[test]
    fn batch_of_nothing_is_nothing() {
        assert!(derive_batch(&[], false).is_empty());
    }

    // --- clamp の評価順 ---

    /// 原本の `min(hi, max(lo, v))` と同じ挟み方 (境界値は境界そのものを返す)。
    #[test]
    fn clamp_matches_the_swift_expression() {
        assert_eq!(clamp(0.5, 0.0, 1.0), 0.5);
        assert_eq!(clamp(-1.0, 0.0, 1.0), 0.0);
        assert_eq!(clamp(2.0, 0.0, 1.0), 1.0);
        assert_eq!(clamp(0.0, 0.0, 1.0), 0.0);
        assert_eq!(clamp(1.0, 0.0, 1.0), 1.0);
        // lo > hi のとき Swift は hi を返す (max が先、min が後)。panic しない。
        assert_eq!(clamp(0.5, 1.0, 0.0), 0.0);
    }
}
