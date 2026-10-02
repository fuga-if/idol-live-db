//! 曲の一覧の行に出す名義 (歌唱者の表記) を 1 つに決める。
//!
//! 全体曲は歌唱者が 50 人を超えることがあり、個人名を連ねると行が画面を埋める。
//! ユニット名・名義があればそれを出し、無いときだけ個人名を連ねる。
//!
//! 優先: `unit_name` → `singer_label` → 個人名の並びの括弧前 (「MILLIONSTARS（…）」) → 個人名の並び。

/// 行に出す名義。どれも無ければ空文字。
pub fn song_credit_label(unit_name: Option<&str>, singer_label: Option<&str>, artist_names: &str) -> String {
    for v in [unit_name, singer_label].into_iter().flatten() {
        let t = v.trim();
        if !t.is_empty() {
            return t.to_string();
        }
    }
    let names = artist_names.trim();
    for sep in ['（', '('] {
        if let Some(i) = names.find(sep) {
            let prefix = names[..i].trim();
            if !prefix.is_empty() {
                return prefix.to_string();
            }
        }
    }
    names.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unit_name_first_then_singer_label() {
        assert_eq!(song_credit_label(Some("トライアドプリムス"), Some("渋谷凛"), "渋谷凛・神谷奈緒"), "トライアドプリムス");
        assert_eq!(song_credit_label(Some(" "), Some("765 MILLION ALLSTARS"), "天海春香・如月千早"), "765 MILLION ALLSTARS");
    }

    #[test]
    fn falls_back_to_prefix_then_names() {
        assert_eq!(song_credit_label(None, None, "MILLIONSTARS（春日未来、最上静香）"), "MILLIONSTARS");
        assert_eq!(song_credit_label(None, Some(""), "天海春香・如月千早"), "天海春香・如月千早");
        assert_eq!(song_credit_label(None, None, ""), "");
    }
}
