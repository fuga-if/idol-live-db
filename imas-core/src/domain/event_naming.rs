//! ライブ名の行表示: 先頭の作品名 (`THE IDOLM@STER MILLION LIVE! ` 等) を落とした短い名前。
//!
//! 一覧・履歴・ピッカーの行ではブランドをリードバーの色で示すので、行頭の作品名は
//! 冗長なだけ。iOS (`EventDisplayName.swift`) と Android (`SongDetailScreen.eventDisplayName`) に
//! 同じ表が写経されていた。**詳細画面のタイトル・共有文・端末カレンダーの予定名など、
//! 正式名称が要る所では使わない**。省略するかどうかの設定 (既定は省略する) は OS が持つ。

/// 落とす作品名。**長いものを先に**置く — 「THE IDOLM@STER 」が先に当たると
/// 「THE IDOLM@STER SideM 」を落とし切れない。上から順に 1 つだけ適用する。
pub const EVENT_NAME_PREFIXES: [&str; 12] = [
    "THE IDOLM@STER CINDERELLA GIRLS ",
    "THE IDOLM@STER MILLION LIVE! ",
    "THE IDOLM@STER MILLION LIVE!",
    "THE IDOLM@STER SideM ",
    "THE IDOLM@STER SHINY COLORS ",
    "THE IDOLM@STER ",
    "アイドルマスター シンデレラガールズ ",
    "アイドルマスター ミリオンライブ! ",
    "アイドルマスター シャイニーカラーズ ",
    "アイドルマスター SideM ",
    "学園アイドルマスター ",
    "アイドルマスター ",
];

/// 落とした後がこれより短くなるなら落とさない (作品名だけのライブ名を空の行にしない)。
const MIN_SHORT_NAME_CHARS: usize = 2;

/// 残りがこれで始まるなら、落とした作品名は合同ライブの片側。落とすと
/// 「× MILLION LIVE! CLASH M@TCH!!」のように相手ブランドだけが残るので落とさない。
const JOINT_CONNECTORS: [char; 4] = ['×', '✕', '＆', '&'];

/// 行に出す短いライブ名。最初に一致した作品名を 1 つ落とし、前後の空白を除く。
/// 残りが 2 文字未満か、合同ライブの片側を落とすことになるなら元の名前のまま。
pub fn event_short_name(name: &str) -> &str {
    let Some(rest) = EVENT_NAME_PREFIXES.iter().find_map(|p| name.strip_prefix(p)) else {
        return name;
    };
    let stripped = rest.trim();
    if stripped.chars().count() < MIN_SHORT_NAME_CHARS || stripped.starts_with(JOINT_CONNECTORS) {
        return name;
    }
    stripped
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_the_longest_matching_work_name_once() {
        assert_eq!(event_short_name("THE IDOLM@STER SideM 7th STAGE"), "7th STAGE");
        assert_eq!(event_short_name("THE IDOLM@STER MILLION LIVE! 11thLIVE"), "11thLIVE");
        assert_eq!(event_short_name("THE IDOLM@STER MILLION LIVE!12thLIVE"), "12thLIVE");
        assert_eq!(event_short_name("アイドルマスター ミリオンライブ! 感謝祭"), "感謝祭");
        assert_eq!(event_short_name("学園アイドルマスター LIVE TOUR"), "LIVE TOUR");
        // 1 つだけ。残りに別の作品名があっても落とさない。
        assert_eq!(
            event_short_name("THE IDOLM@STER THE IDOLM@STER CINDERELLA GIRLS 合同"),
            "THE IDOLM@STER CINDERELLA GIRLS 合同"
        );
    }

    #[test]
    fn keeps_names_that_would_become_too_short_or_have_no_prefix() {
        assert_eq!(event_short_name("THE IDOLM@STER X"), "THE IDOLM@STER X");
        assert_eq!(event_short_name("THE IDOLM@STER   "), "THE IDOLM@STER   ");
        assert_eq!(event_short_name("MOIW2023"), "MOIW2023");
        assert_eq!(event_short_name(""), "");
    }

    #[test]
    fn keeps_joint_event_names_whole() {
        // 片側だけ落とすと相手ブランドが先頭に残り、どちらの合同か読めなくなる。
        for name in [
            "THE IDOLM@STER CINDERELLA GIRLS × MILLION LIVE! CLASH M@TCH!!",
            "THE IDOLM@STER SideM × SHINY COLORS SPARKLE SHOWDOWN",
            "THE IDOLM@STER ＆ CINDERELLA GIRLS TALK ＆ LIVE STAGE",
        ] {
            assert_eq!(event_short_name(name), name);
        }
    }
}
