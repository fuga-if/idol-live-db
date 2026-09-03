//! テーマトークンの表と、配布する CSS。
//!
//! アプリの「無限色テーマエンジン」(`domain::color_engine`) の出力をそのまま CSS 変数に
//! する。**色の式はここに 1 つも書かない**。書くとアプリと Web で色がずれる。
//!
//! 配るのは単一の `themes.css` で、HTML 側は `data-theme="idol:ml_kasuga_mirai"` のような
//! 属性を 1 個置くだけ。インライン style で配らないのは、CSP に `unsafe-inline` を
//! 要らなくするため (と、同じトークン列を 400 回 HTML に埋め込まないため)。

use super::dto::{ThemePair, ThemeTable, ThemeTokens, SCHEMA_VERSION};
use crate::domain::color_engine::{derive, theme_hex, ImasThemeColors};
use crate::web_export::emit::context::{BrandThemeInput, IdolThemeInput};
use std::collections::BTreeMap;

/// ニュートラル (色を持たないもの全部の受け皿)。
pub const NEUTRAL_KEY: &str = "neutral";

/// アイドルのテーマキー。
pub fn idol_key(idol_id: &str) -> String {
    format!("idol:{idol_id}")
}

/// ブランドのテーマキー。
pub fn brand_key(brand_id: &str) -> String {
    format!("brand:{brand_id}")
}

/// 1 テーマぶんのライト / ダークを導出する。
///
/// **`seed` に渡してよいのは実体の色 (`#rrggbb`) だけ。** ブランド id を渡してはいけない
/// (`color_engine::first_valid_hex` の doc: `"876"` が `#887766` として通ってしまう)。
fn pair(seed: Option<&str>, brand: Option<&str>) -> ThemePair {
    ThemePair { light: tokens(&derive(seed, brand, false)), dark: tokens(&derive(seed, brand, true)) }
}

fn tokens(c: &ImasThemeColors) -> ThemeTokens {
    ThemeTokens {
        accent: theme_hex(c.accent),
        on_accent: theme_hex(c.on_accent),
        tint: theme_hex(c.tint),
        tint_strong: theme_hex(c.tint_strong),
        chip_bg: theme_hex(c.chip_bg),
        chip_text: theme_hex(c.chip_text),
        ring: theme_hex(c.ring),
        bar: theme_hex(c.bar),
        dot: theme_hex(c.dot),
        grad_from: theme_hex(c.grad_from),
        grad_to: theme_hex(c.grad_to),
        separator: theme_hex(c.separator),
        hero_surface: theme_hex(c.hero_surface),
        is_neutral: c.is_neutral,
    }
}

/// アイドル / ブランド / ニュートラルの全テーマ。
///
/// `idol_brand_color` はアイドル id → 主ブランドの色。アイドル色が無いときの
/// 落とし先で、優先順位 (アイドル色 → ブランド色 → ニュートラル) の判断は
/// `first_valid_hex` が持っているので、ここは候補を並べて渡すだけ。
pub fn build_table(idols: &[IdolThemeInput], brands: &[BrandThemeInput]) -> ThemeTable {
    let mut themes = BTreeMap::new();
    themes.insert(NEUTRAL_KEY.to_string(), pair(None, None));
    for (id, color) in brands {
        themes.insert(brand_key(id), pair(None, color.as_deref()));
    }
    for (id, color, brand_color) in idols {
        themes.insert(idol_key(id), pair(color.as_deref(), brand_color.as_deref()));
    }
    ThemeTable { schema_version: SCHEMA_VERSION, themes }
}

/// CSS 変数名 (`ThemeTokens` のフィールド名を kebab-case にしたもの)。
///
/// `is_neutral` は色ではないので CSS には出さない (必要な出し分けは DTO 側で判断する)。
const CSS_VARS: [&str; 13] = [
    "accent",
    "on-accent",
    "tint",
    "tint-strong",
    "chip-bg",
    "chip-text",
    "ring",
    "bar",
    "dot",
    "grad-from",
    "grad-to",
    "separator",
    "hero-surface",
];

fn values(t: &ThemeTokens) -> [&str; 13] {
    [
        &t.accent,
        &t.on_accent,
        &t.tint,
        &t.tint_strong,
        &t.chip_bg,
        &t.chip_text,
        &t.ring,
        &t.bar,
        &t.dot,
        &t.grad_from,
        &t.grad_to,
        &t.separator,
        &t.hero_surface,
    ]
}

/// 単一の `themes.css`。
///
/// ライトを素で、ダークを `@media (prefers-color-scheme: dark)` の中で同じセレクタに
/// 再定義する。テーマ切替 UI は作らない (OS 設定への追従のみ) ので、`[data-theme]` の
/// 2 段組みだけで足りる。
pub fn build_css(table: &ThemeTable) -> String {
    let mut out = String::with_capacity(table.themes.len() * 700);
    out.push_str(
        "/* 自動生成 — imas-core の web-export が color_engine から出力する。手で編集しない。\n\
         \x20  アプリ (iOS/Android) と同じ導出を通しているので、ここを手で直すと色がずれる。 */\n",
    );

    let rule = |key: &str, t: &ThemeTokens, out: &mut String| {
        // キーに使う文字は id 由来なので、CSS 属性セレクタの引用符だけ守れば足りる。
        out.push_str(&format!("[data-theme=\"{}\"]{{", escape_attr(key)));
        for (name, value) in CSS_VARS.iter().zip(values(t)) {
            out.push_str(&format!("--{name}:{value};"));
        }
        out.push_str("}\n");
    };

    for (key, p) in &table.themes {
        rule(key, &p.light, &mut out);
    }
    out.push_str("@media (prefers-color-scheme: dark){\n");
    for (key, p) in &table.themes {
        rule(key, &p.dark, &mut out);
    }
    out.push_str("}\n");
    out
}

/// CSS 属性セレクタの中に置ける形にする。
fn escape_attr(key: &str) -> String {
    key.replace('\\', "\\\\").replace('"', "\\\"")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn css_defines_every_token_for_both_schemes() {
        let table = build_table(
            &[("ml_x".to_string(), Some("#f39800".to_string()), Some("#ffc30b".to_string()))],
            &[("ml".to_string(), Some("#ffc30b".to_string()))],
        );
        let css = build_css(&table);
        for key in ["neutral", "brand:ml", "idol:ml_x"] {
            let selector = format!("[data-theme=\"{key}\"]{{");
            assert_eq!(css.matches(&selector).count(), 2, "{key} がライト/ダークで 2 回出ていない");
        }
        for name in CSS_VARS {
            assert!(css.contains(&format!("--{name}:")), "{name} が出ていない");
        }
        assert!(css.contains("@media (prefers-color-scheme: dark)"));
        // is_neutral は色ではないので CSS には出さない。
        assert!(!css.contains("is-neutral"));
    }

    #[test]
    fn a_brand_id_is_never_used_as_a_color_seed() {
        // "876" のような id をシードに渡すと #887766 として通ってしまう。
        // ここでは色だけを渡していることを、id 由来の色が出ないことで確かめる。
        let with_id_as_color = build_table(&[], &[("876".to_string(), Some("#656a75".to_string()))]);
        let neutral_only = build_table(&[], &[("876".to_string(), None)]);
        assert_ne!(
            with_id_as_color.themes["brand:876"], neutral_only.themes["brand:876"],
            "色の有無でテーマが変わらないのはおかしい"
        );
        assert_eq!(neutral_only.themes["brand:876"], neutral_only.themes["neutral"]);
    }
}
