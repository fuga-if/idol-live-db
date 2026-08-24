//! 担当(推し)カラーをアプリ全体テーマに使うときの、保存すべき値の解決。
//!
//! 設定画面で担当カラー ON/OFF や担当の付け外しが起きるたびに、
//! 「保存し直す担当 ID」と「ContentView が参照するテーマ色 hex」を引き直す。
//!
//! 非自明なのは次の 2 点なので純粋関数に切り出してある:
//!
//! 1. **OFF のときは色だけ消し、選択した担当 ID は残す。**
//!    消してしまうと、ユーザーが後で ON に戻したときに選び直しになる。
//!    「残す」は結果の `idol_id: None` (= 現在の選択を変更しない) で表現する。
//! 2. **選択中の担当が担当から外れていたら、先頭の担当へ黙って寄せる。**
//!    担当を解除したのにテーマ色だけ残り続ける状態を防ぐ。担当が 0 人なら空にする。
//!
//! FFI 境界ではアイドルのエンティティ全体は渡さず、判定に要る 2 フィールド
//! (`id` / `color`) の射影 `OshiThemePickIdol` を渡す (1 ユーザー操作 = 1 呼び出し)。

/// 「担当」としてマークされているアイドル 1 件の射影。
/// テーマ解決に必要な id と色だけを持つ (エンティティ全体を FFI に通さない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct OshiThemePickIdol {
    pub id: String,
    /// イメージカラー hex。マスタ未設定のアイドルは `None` (結果では空文字に落ちる)。
    pub color: Option<String>,
}

/// 担当カラーをテーマに使うときの、保存すべき値の解決結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct OshiThemeResolution {
    /// 保存し直す担当アイドル ID。
    /// `None` は「現在の選択を変更しない」の意味 (テーマ機能が OFF のとき)。
    pub idol_id: Option<String>,
    /// `ContentView` が参照する解決済みテーマ色 hex。無効・該当なしは空文字。
    pub color_hex: String,
}

/// 担当テーマ色を、現在の選択と担当一覧から解決する。
///
/// - `is_enabled`: 担当カラーをテーマに使う設定 (`theme_use_oshi_color`)。
/// - `current_idol_id`: 現在保存されている担当 ID (`theme_oshi_idol_id`)。
/// - `pick_idols`: 「担当」としてマークされているアイドル (射影)。
pub fn resolve_oshi_theme(
    is_enabled: bool,
    current_idol_id: &str,
    pick_idols: &[OshiThemePickIdol],
) -> OshiThemeResolution {
    if !is_enabled {
        return OshiThemeResolution { idol_id: None, color_hex: String::new() };
    }

    // 選択が空、または担当から外れていたら先頭の担当に寄せる。
    let resolved_id: &str = if current_idol_id.is_empty()
        || !pick_idols.iter().any(|i| i.id == current_idol_id)
    {
        pick_idols.first().map(|i| i.id.as_str()).unwrap_or("")
    } else {
        current_idol_id
    };

    // 同 id が重複していても最初の 1 件を採る (find は入力順で安定)。
    let color_hex = pick_idols
        .iter()
        .find(|i| i.id == resolved_id)
        .and_then(|i| i.color.clone())
        .unwrap_or_default();

    OshiThemeResolution { idol_id: Some(resolved_id.to_string()), color_hex }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn idol(id: &str, color: Option<&str>) -> OshiThemePickIdol {
        OshiThemePickIdol { id: id.to_string(), color: color.map(str::to_string) }
    }

    /// 実データを模した担当 2 人 (色あり)。
    fn picks() -> Vec<OshiThemePickIdol> {
        vec![idol("amami_haruka", Some("#e22b30")), idol("kisaragi_chihaya", Some("#2743d2"))]
    }

    // --- OFF: 色だけ消して選択は残す ---

    /// OFF なら担当や選択がどうあれ「id は変更しない (None)・色は空」。
    /// id まで消すと ON に戻したとき選び直しになる (原本コメントの意図)。
    #[test]
    fn disabled_clears_color_but_keeps_selection() {
        let r = resolve_oshi_theme(false, "amami_haruka", &picks());
        assert_eq!(r, OshiThemeResolution { idol_id: None, color_hex: String::new() });
    }

    /// OFF は空入力でも同じ結果 (分岐が入力に依存しない)。
    #[test]
    fn disabled_with_empty_inputs() {
        let r = resolve_oshi_theme(false, "", &[]);
        assert_eq!(r, OshiThemeResolution { idol_id: None, color_hex: String::new() });
    }

    // --- ON: 空入力の境界 ---

    /// 担当 0 人なら id も色も空にする (Some("") = 「空を保存し直す」)。
    #[test]
    fn enabled_with_no_picks_resolves_to_empty() {
        let r = resolve_oshi_theme(true, "", &[]);
        assert_eq!(r, OshiThemeResolution { idol_id: Some(String::new()), color_hex: String::new() });
    }

    /// 選択が残っていても担当 0 人なら空へ寄せる (解除後にテーマ色が残らない)。
    #[test]
    fn enabled_with_stale_selection_and_no_picks_resolves_to_empty() {
        let r = resolve_oshi_theme(true, "amami_haruka", &[]);
        assert_eq!(r, OshiThemeResolution { idol_id: Some(String::new()), color_hex: String::new() });
    }

    // --- ON: 単一要素・通常系 ---

    /// 選択が空なら (2 人以上いても) 先頭の担当を既定にする。
    #[test]
    fn empty_selection_falls_back_to_first_pick() {
        let r = resolve_oshi_theme(true, "", &picks());
        assert_eq!(r.idol_id.as_deref(), Some("amami_haruka"));
        assert_eq!(r.color_hex, "#e22b30");
    }

    /// 選択中の担当がまだ担当なら、そのまま維持して色もその人のものを返す。
    #[test]
    fn current_selection_is_kept_when_still_picked() {
        let r = resolve_oshi_theme(true, "kisaragi_chihaya", &picks());
        assert_eq!(r.idol_id.as_deref(), Some("kisaragi_chihaya"));
        assert_eq!(r.color_hex, "#2743d2");
    }

    /// 選択中の担当が担当から外れていたら先頭へ黙って寄せる。
    /// 色も (旧選択ではなく) 寄せた後の先頭の色になることまで確認する。
    #[test]
    fn removed_selection_falls_back_to_first_pick() {
        let r = resolve_oshi_theme(true, "hoshii_miki", &picks());
        assert_eq!(r.idol_id.as_deref(), Some("amami_haruka"));
        assert_eq!(r.color_hex, "#e22b30");
    }

    // --- 色未設定 ---

    /// 色未設定 (None) のアイドルに解決されたら hex は空文字 (Swift の `?? ""` と同じ)。
    #[test]
    fn missing_color_resolves_to_empty_hex() {
        let no_color = vec![idol("julia", None)];
        let r = resolve_oshi_theme(true, "julia", &no_color);
        assert_eq!(r.idol_id.as_deref(), Some("julia"));
        assert_eq!(r.color_hex, "");
    }

    // --- 同値の順序安定性 ---

    /// 同じ id が重複して並んでいても、最初の 1 件の色を採る (入力順で安定)。
    #[test]
    fn duplicate_ids_take_first_occurrence() {
        let dup = vec![idol("dup", Some("#111111")), idol("dup", Some("#222222"))];
        let r = resolve_oshi_theme(true, "dup", &dup);
        assert_eq!(r.color_hex, "#111111");
    }

    /// 先頭寄せも常に「先頭」で安定 (2 回呼んでも同じ結果 = 決定的)。
    #[test]
    fn fallback_is_deterministic() {
        let r1 = resolve_oshi_theme(true, "gone", &picks());
        let r2 = resolve_oshi_theme(true, "gone", &picks());
        assert_eq!(r1, r2);
    }

    // --- Unicode ---

    /// id は ASCII slug 想定だが、非 ASCII が来ても文字列一致で正しく解決される。
    #[test]
    fn unicode_ids_match_exactly() {
        let uni = vec![idol("双海_亜美", Some("#ffe43f")), idol("双海_真美", Some("#ffe43f"))];
        let r = resolve_oshi_theme(true, "双海_真美", &uni);
        assert_eq!(r.idol_id.as_deref(), Some("双海_真美"));
    }

    /// Rust の比較はバイト同値。NFC/NFD の正規化差は別 id 扱いになり先頭へ寄る
    /// (Swift の String == は正規化同値なのでここは仕様差。DB 由来の id は同一表現
    /// なので実データでは踏まない。挙動を固定するためにテストで明文化しておく)。
    #[test]
    fn unicode_normalization_is_not_applied() {
        let nfc = "ガ"; // U+30AC (合成済み)
        let nfd = "カ\u{3099}"; // U+30AB + 濁点 (結合文字)
        let picks = vec![idol(nfc, Some("#aaaaaa")), idol("second", Some("#bbbbbb"))];
        let r = resolve_oshi_theme(true, nfd, &picks);
        // NFD の選択は NFC の担当と一致せず、先頭 (NFC の方) へ寄る。
        assert_eq!(r.idol_id.as_deref(), Some(nfc));
        assert_eq!(r.color_hex, "#aaaaaa");
    }
}
