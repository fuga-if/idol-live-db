//! 無限色テーマエンジンの FFI 面。ロジックは [`crate::domain::color_engine`]。
//!
//! 返すのは **RGB の数値だけ** ([`ThemeRgb`] = sRGB 0.0–1.0)。`SwiftUI.Color` /
//! `Compose.Color` の生成と描画は各 OS に残す。
//!
//! ## 呼び出しの粒度
//!
//! | 画面の操作 | 呼ぶもの |
//! |---|---|
//! | 詳細/ヒーローを開く (シード 1 つ) | [`theme_derive`] |
//! | 一覧を組む (行ごとにシードが違う) | [`theme_derive_batch`] (全行まとめて 1 回) |
//! | 実体色を持たない分類を塗り分ける | [`theme_derive_for_category_key`] |
//! | 任意の面の上の文字色を決める | [`theme_on_color`] / [`theme_on_color_over`] |
//!
//! **行ごとに [`theme_derive`] を呼ぶ形は禁止** (FFI 境界の規約)。一覧は必ず
//! [`theme_derive_batch`] で 1 回に畳む。
//!
//! ## メモ化は OS 側に残す
//!
//! 原本 (iOS/Android どちらも) は `[hex|dark: Theme]` のキャッシュを持っていた。
//! SwiftUI / Compose が**描画のたび**に導出を呼ぶためで、キャッシュは
//! 「描画のたびに呼ばれる」側の事情。コアは純粋な計算だけを持ち、
//! メモ化は呼び出し側 (ラッパ) に置く。distinct な色数はアイドル数 × 2 で有界。
//!
//! ## `Color` を直接シードにしたい場合
//!
//! `SwiftUI.Color` → 成分の取り出しは `UIColor` ブリッジ、`Compose.Color` → argb は
//! `toArgb()` で、どちらも OS 依存なのでコアには持ち込まない。各 OS で `#rrggbb` に
//! してから [`theme_derive`] の `seed` に渡す (原本 `derive(colorSeed:)` /
//! `derive(color:)` はその 2 行に分解される)。
//!
//! エクスポートを増減したら、共有の tests/ffi_surface.rs の一覧にも反映すること。
//! 片方だけだと抜けが Swift/Kotlin ラッパのリンク時まで表に出ない。
//! 反映漏れはこのファイルの
//! `tests::every_export_here_is_registered_in_the_shared_ffi_surface_list` が落とす。

use crate::domain::color_engine::{
    self as domain, ImasThemeColors, ThemeHsl, ThemeRgb, ThemeSeedRequest,
};

/// シード hex → テーマトークン一式。無効・未設定なら brand → ニュートラルへ落ちる。
///
/// 原本の 3 つの入口 (`derive(seed:brand:scheme:)` / `derive(hex:dark:)` /
/// `derive(colorSeed:scheme:)`) はすべてこれで足りる。
#[uniffi::export]
pub fn theme_derive(seed: Option<String>, brand: Option<String>, dark: bool) -> ImasThemeColors {
    domain::derive(seed.as_deref(), brand.as_deref(), dark)
}

/// 一覧 1 画面ぶんのテーマをまとめて導出する (入力と同じ順で返す)。
/// 行ごとに FFI を跨がせないための入口。
#[uniffi::export]
pub fn theme_derive_batch(
    requests: Vec<ThemeSeedRequest>,
    dark: bool,
) -> Vec<ImasThemeColors> {
    domain::derive_batch(&requests, dark)
}

/// 実体色を持たない「分類キー」(タグのカテゴリ名、編集フィードのレコード種別名等)
/// から安定した色を導出する。同じキーは常に同じ色。
#[uniffi::export]
pub fn theme_derive_for_category_key(key: String, dark: bool) -> ImasThemeColors {
    domain::derive_for_category_key(&key, dark)
}

/// 色が無いときに使う低彩度グレーのシード (`#8E8E93`)。
#[uniffi::export]
pub fn theme_neutral_seed() -> String {
    domain::NEUTRAL_SEED.to_string()
}

/// `#RGB` / `#RRGGBB` を 6 桁小文字 hex に正規化する。無効なら `None`。
/// 入力欄の正規化 (iOS `IdolEditView`) の判断はこれ 1 本に寄せる。
#[uniffi::export]
pub fn theme_normalized_hex(hex: String) -> Option<String> {
    domain::normalized_hex(&hex)
}

/// 候補を先頭から見て、最初の「有効な hex」を**そのまま**返す (正規化しない)。
///
/// 未設定は空文字で渡す (空文字は常に無効なので、原本の `nil` と同じ挙動になる)。
#[uniffi::export]
pub fn theme_first_valid_hex(candidates: Vec<String>) -> Option<String> {
    let refs: Vec<Option<&str>> = candidates.iter().map(|c| Some(c.as_str())).collect();
    domain::first_valid_hex(&refs).map(str::to_string)
}

/// 基準色の色味を保ったまま、キーごとに少しだけ振ったバリエーション hex。
/// 色相は ±16° までなので「同じブランドの別系列」に見える。
#[uniffi::export]
pub fn theme_variant_hex(hex: String, key: String) -> String {
    domain::variant_hex(&hex, &key)
}

/// hex → HSL (h は度)。共有カード等、独自の配色規則を持つ画面のための素の変換。
#[uniffi::export]
pub fn theme_hex_to_hsl(hex: String) -> ThemeHsl {
    domain::rgb_to_hsl(domain::hex_to_rgb(&hex))
}

/// HSL (h は度) → UI 色。`s` / `l` は 0–1 に挟んでから変換する。
#[uniffi::export]
pub fn theme_color_from_hsl(h: f64, s: f64, l: f64) -> ThemeRgb {
    domain::color_from_hsl(h, s, l)
}

/// 面の上に乗せる前景色を WCAG コントラストで黒/白から選ぶ。
/// 黄色・白系・水色系の明るい面での白文字固定の破綻を防ぐ共通入口。
#[uniffi::export]
pub fn theme_on_color(background: ThemeRgb) -> ThemeRgb {
    to_theme_rgb(domain::on_color(to_rgb255(background)))
}

/// 複数の面 (グラデーションの停止色など) すべての上で読める黒/白を選ぶ。
/// 全停止色との最小コントラストで判定する。空なら墨。
#[uniffi::export]
pub fn theme_on_color_over(backgrounds: Vec<ThemeRgb>) -> ThemeRgb {
    let rgbs: Vec<_> = backgrounds.into_iter().map(to_rgb255).collect();
    to_theme_rgb(domain::on_color_over(&rgbs))
}

/// `foreground` の色相・彩度は保ったまま、`background` から離れる方向へ明度を調整して
/// `min_ratio` 以上のコントラストを確保する。
///
/// 明度が 0–1 を出たら打ち切ってその直前の色を返すので、**比率を満たせないまま
/// 返ることがある** (到達不能な組み合わせで固まらないための原本の判断)。
/// 既定の比率は [`crate::domain::color_engine::DEFAULT_MIN_CONTRAST_RATIO`] (4.5)。
#[uniffi::export]
pub fn theme_ensure_contrast(
    foreground: ThemeRgb,
    background: ThemeRgb,
    min_ratio: f64,
) -> ThemeRgb {
    to_theme_rgb(domain::ensure_contrast(
        to_rgb255(foreground),
        to_rgb255(background),
        min_ratio,
    ))
}

/// 境界の 0–1 表現を、内部計算の 0–255 表現へ戻す。
///
/// 原本 iOS `ColorMath.rgb(of:)` が `Double(component) * 255` で作っていたものと
/// 同じ値になる。各 OS は `Color` の生成にも取り出しにも 0–1 の成分を使うので、
/// FFI 面は 0–1 に統一し、255 倍はここだけで行う。
fn to_rgb255(c: ThemeRgb) -> crate::domain::color_match::Rgb {
    crate::domain::color_match::Rgb { r: c.r * 255.0, g: c.g * 255.0, b: c.b * 255.0 }
}

fn to_theme_rgb(rgb: crate::domain::color_match::Rgb) -> ThemeRgb {
    ThemeRgb {
        r: domain::clamp(rgb.r, 0.0, 255.0) / 255.0,
        g: domain::clamp(rgb.g, 0.0, 255.0) / 255.0,
        b: domain::clamp(rgb.b, 0.0, 255.0) / 255.0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex_of(c: ThemeRgb) -> String {
        format!(
            "#{:02x}{:02x}{:02x}",
            (c.r * 255.0).round() as u32,
            (c.g * 255.0).round() as u32,
            (c.b * 255.0).round() as u32
        )
    }

    /// このモジュールの `#[uniffi::export]` が、共有の tests/ffi_surface.rs の
    /// checksum 一覧に全部載っていること。
    ///
    /// あちらのリンク検査は「消えた・改名された」しか捕まえず、**足したのに載せ忘れた**分は
    /// 件数比較でしか出ない。件数比較は他モジュールの増減と混ざるため、
    /// 「どのモジュールが載せ忘れたか」は分からないまま全体が赤になる
    /// (回帰: Phase 8 sync の 20 関数、Phase 9 のこの 12 関数)。
    /// 一覧は共有ファイルで各担当が直接は触れないので、**自分の分は自分で名指しで**
    /// 確かめ、落ちたときに貼るべき行をそのままメッセージに出す。
    #[test]
    fn every_export_here_is_registered_in_the_shared_ffi_surface_list() {
        // このモジュールが公開している FFI の全量。増やしたらここにも足す
        // (足しただけでは通らない = tests/ffi_surface.rs への登録を強制する)。
        const EXPORTS: &[&str] = &[
            "theme_color_from_hsl",
            "theme_derive",
            "theme_derive_batch",
            "theme_derive_for_category_key",
            "theme_ensure_contrast",
            "theme_first_valid_hex",
            "theme_hex_to_hsl",
            "theme_neutral_seed",
            "theme_normalized_hex",
            "theme_on_color",
            "theme_on_color_over",
            "theme_variant_hex",
        ];

        // 上の一覧がソースと食い違っていたら、以降の照合は無意味になる。まず自分を検算する。
        let own_source = include_str!("color_engine.rs");
        let attribute = concat!("#[uniffi", "::export]");
        let mut declared: Vec<&str> = Vec::new();
        let mut lines = own_source.lines();
        while let Some(line) = lines.next() {
            if !line.trim_start().starts_with(attribute) {
                continue;
            }
            let signature = lines.clone().find(|l| l.trim_start().starts_with("pub fn "));
            let name = signature
                .and_then(|l| l.trim_start().strip_prefix("pub fn "))
                .and_then(|l| l.split(&['(', '<'][..]).next())
                .expect("#[uniffi::export] の直後に pub fn がある");
            declared.push(name);
        }
        declared.sort_unstable();
        assert_eq!(declared, EXPORTS, "このテストの EXPORTS がソースの実態と合っていない");

        let list = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/ffi_surface.rs"),
        )
        .expect("tests/ffi_surface.rs を読める");
        let missing: Vec<String> = EXPORTS
            .iter()
            .map(|name| format!("uniffi_imas_core_checksum_func_{name}"))
            .filter(|symbol| !list.contains(symbol.as_str()))
            .collect();
        assert!(
            missing.is_empty(),
            "tests/ffi_surface.rs の declare_and_call_checksums! に未登録:\n\
             {},\n\
             この行をそのまま足すこと。登録しないと、改名も削除も\n\
             Swift/Kotlin ラッパのリンク時まで発覚しない。",
            missing.join(",\n")
        );
    }

    /// 引数の並び (seed, brand) を取り違えていないこと。どちらも `Option<String>` なので
    /// 入れ替えてもコンパイルは通り、seed の無い行だけ色が変わる形で壊れる。
    #[test]
    fn derive_does_not_swap_seed_and_brand() {
        let t = theme_derive(Some("#E22B30".into()), Some("#fe0000".into()), false);
        assert_eq!(t, domain::derive(Some("#E22B30"), Some("#fe0000"), false));
        // seed が優先されること (入れ替わっていれば #fe0000 由来の色になる)。
        assert_eq!(hex_of(t.accent), "#e22b30");
        assert_eq!(hex_of(theme_derive(None, Some("#fe0000".into()), false).accent), "#f40a0a");
    }

    /// `dark` を落としたり反転したりしていないこと。
    #[test]
    fn derive_passes_the_scheme_through() {
        assert_ne!(
            theme_derive(Some("#E22B30".into()), None, true),
            theme_derive(Some("#E22B30".into()), None, false)
        );
        assert_eq!(
            theme_derive(Some("#E22B30".into()), None, true),
            domain::derive(Some("#E22B30"), None, true)
        );
    }

    /// 一括版が入力順を保ち、1 件ずつ呼んだ結果と一致すること。
    #[test]
    fn batch_delegates_and_keeps_order() {
        let requests = vec![
            ThemeSeedRequest { seed: Some("#E22B30".into()), brand: None },
            ThemeSeedRequest { seed: None, brand: Some("#2681c8".into()) },
            ThemeSeedRequest { seed: None, brand: None },
        ];
        let got = theme_derive_batch(requests.clone(), true);
        assert_eq!(got, domain::derive_batch(&requests, true));
        assert_eq!(got[0], theme_derive(Some("#E22B30".into()), None, true));
        assert_eq!(got[2], theme_derive(None, None, true));
        assert!(got[2].is_neutral);
    }

    #[test]
    fn category_key_delegates() {
        assert_eq!(
            theme_derive_for_category_key("idol".into(), true),
            domain::derive_for_category_key("idol", true)
        );
        assert_eq!(hex_of(theme_derive_for_category_key("idol".into(), true).accent), "#51cd6c");
    }

    #[test]
    fn neutral_seed_is_the_documented_grey() {
        assert_eq!(theme_neutral_seed(), "#8E8E93");
        // ニュートラルシードから導いたテーマは、色が一つも無いときの結果と同じ。
        assert_eq!(theme_derive(Some(theme_neutral_seed()), None, false), theme_derive(None, None, false));
    }

    #[test]
    fn normalized_hex_delegates() {
        assert_eq!(theme_normalized_hex("#F0A".into()).as_deref(), Some("ff00aa"));
        assert_eq!(theme_normalized_hex("nope".into()), None);
    }

    /// 入力欄の正規化はこの 1 本に寄せてあるので、境界での取りこぼしがそのまま
    /// 「保存された色が読めない」になる。iOS `.whitespaces` の実装どおり
    /// U+200B は落とし、改行は落とさない (モジュール冒頭の乖離 1b / 1)。
    #[test]
    fn normalized_hex_trims_like_ios_at_the_boundary() {
        assert_eq!(theme_normalized_hex("\u{200b}#E22B30".into()).as_deref(), Some("e22b30"));
        assert_eq!(theme_normalized_hex("  #E22B30\u{3000}".into()).as_deref(), Some("e22b30"));
        assert_eq!(theme_normalized_hex("#E22B30\n".into()), None);
    }

    /// 空文字は原本の `nil` と同じく「候補なし」として飛ばされる
    /// (`Option<String>` の列を渡さずに済ませるための約束)。
    #[test]
    fn first_valid_hex_treats_empty_string_as_absent() {
        assert_eq!(
            theme_first_valid_hex(vec!["".into(), "#fe0000".into()]).as_deref(),
            Some("#fe0000")
        );
        assert_eq!(theme_first_valid_hex(vec!["".into(), "".into()]), None);
        assert_eq!(theme_first_valid_hex(vec![]), None);
        // 有効な候補はそのまま (正規化せずに) 返る。
        assert_eq!(
            theme_first_valid_hex(vec!["#E22B30".into(), "#fe0000".into()]).as_deref(),
            Some("#E22B30")
        );
    }

    #[test]
    fn variant_hex_delegates_without_swapping_hex_and_key() {
        assert_eq!(theme_variant_hex("#fe0000".into(), "live".into()), "#d5053d");
        // 入れ替わっていれば "live" を色として読もうとして別の結果になる。
        assert_ne!(
            theme_variant_hex("#fe0000".into(), "live".into()),
            theme_variant_hex("live".into(), "#fe0000".into())
        );
    }

    /// 0–1 ↔ 0–255 の往復で色が変わらないこと (境界の単位換算のガード)。
    #[test]
    fn rgb_unit_conversion_round_trips() {
        for hex in ["#E22B30", "#FFE43F", "#000000", "#ffffff", "#01ADB9"] {
            let rgb255 = domain::hex_to_rgb(hex);
            let boundary = to_theme_rgb(rgb255);
            assert_eq!(to_rgb255(boundary), rgb255, "{hex}");
        }
    }

    /// hex → HSL → 色 の経路が domain と一致すること。
    #[test]
    fn hsl_helpers_delegate() {
        let hsl = theme_hex_to_hsl("#E22B30".into());
        assert_eq!(hsl, domain::rgb_to_hsl(domain::hex_to_rgb("#E22B30")));
        // 引数 (h, s, l) の順序を取り違えていないこと。全部 f64 なので型では守れない。
        assert_eq!(hex_of(theme_color_from_hsl(hsl.h, hsl.s, hsl.l)), "#e22b30");
        assert_ne!(theme_color_from_hsl(hsl.h, hsl.s, hsl.l), theme_color_from_hsl(hsl.h, hsl.l, hsl.s));
    }

    /// WCAG 判定が境界を跨いで正しく委譲されること。
    #[test]
    fn on_color_picks_readable_foreground() {
        let of = |hex: &str| hex_of(theme_on_color(to_theme_rgb(domain::hex_to_rgb(hex))));
        // 暗い赤の上は白、明るい黄の上は墨。
        assert_eq!(of("#E22B30"), "#ffffff");
        assert_eq!(of("#FFE43F"), "#15161a");
        assert_eq!(of("#ffffff"), "#15161a");
        assert_eq!(of("#000000"), "#ffffff");
    }

    #[test]
    fn on_color_over_delegates_and_handles_empty() {
        let bg = |hex: &str| to_theme_rgb(domain::hex_to_rgb(hex));
        assert_eq!(hex_of(theme_on_color_over(vec![])), "#15161a");
        // 1 要素版は単色版と同義。
        assert_eq!(theme_on_color_over(vec![bg("#E22B30")]), theme_on_color(bg("#E22B30")));
        // 白と黒の両方の上で 4.5 を満たす色は無い → まだマシな方 (墨)。
        assert_eq!(hex_of(theme_on_color_over(vec![bg("#ffffff"), bg("#000000")])), "#15161a");
    }

    /// `min_ratio` が素通しされていること (既定値を埋め込んでいないこと)。
    #[test]
    fn ensure_contrast_honours_the_requested_ratio() {
        let fg = to_theme_rgb(domain::hex_to_rgb("#8e8e93"));
        let bg = to_theme_rgb(domain::hex_to_rgb("#ffffff"));
        assert_eq!(hex_of(theme_ensure_contrast(fg, bg, 7.0)), "#56565a");
        // 要求が緩ければ歩数も減る = 別の色になる。
        assert_ne!(
            theme_ensure_contrast(fg, bg, 7.0),
            theme_ensure_contrast(fg, bg, domain::DEFAULT_MIN_CONTRAST_RATIO)
        );
        // 引数 (foreground, background) を取り違えていないこと。
        assert_ne!(
            theme_ensure_contrast(fg, bg, 7.0),
            theme_ensure_contrast(bg, fg, 7.0)
        );
    }
}
