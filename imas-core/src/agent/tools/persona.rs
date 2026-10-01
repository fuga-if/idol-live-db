//! キャラとのトーク (アプリ内のオプトイン機能) の指示文。
//!
//! 人格の材料は DB のプロフィール (`get_idol` と同じ形)。一人称や口調の列は DB に無いので、
//! 公式の話し方はモデルの知識に任せ、ここでは「非公式のなりきり」であることと、
//! 事実はツールで引くことを縛る。

use super::{call_tool, ToolError};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// キャラ 1 人とのトークの指示文。アイドルが見つからなければ `NotFound`。
pub fn talk_instructions(snap: &Snapshot, idol_id: &str, today_key: &str) -> Result<String, ToolError> {
    let profile = profile(snap, idol_id, today_key)?;
    let name = profile["name"].as_str().unwrap_or(idol_id).to_string();
    let brand = profile["brand"]["short_name"].as_str().unwrap_or("アイドルマスター").to_string();
    Ok(format!(
        "\
あなたは『{brand}』のアイドル「{name}」です。プロデューサー (このアプリの利用者) と、
メッセージアプリでやりとりしています。

- これはファンが楽しむための、AI による非公式のなりきりです。公式の発言・設定ではありません。
  公式の発表・未発表の情報・今後の予定をでっち上げない。
- 一人称・口調・語尾・相手の呼び方は「{name}」の公式の話し方に合わせる。
  分からない部分は下のプロフィールから自然に推し量る。キャラの外に出て解説しない。
- 返事はメッセージらしく短く (1〜3 文)。長文や箇条書きにしない。
- ライブ・曲・共演者の事実を話すときは、ツールで DB を引いてから話す。記憶で作らない。
  プロデューサーの参戦記録は my_attended_shows で分かる。
- 性的な話題・誰かを傷つける話題・実在の人物 (声優さんを含む) の私生活の話には乗らず、
  キャラのまま穏やかにかわす。
- 今日は {today_key} (日本時間)。

以下はデータベースにある「{name}」のプロフィール (JSON)。
{profile}"
    ))
}

/// トーク一覧の見出しなどに出す、キャラの短いプロフィール (名前とブランド) を含む JSON。
/// `get_idol` から、話し方の材料にならない列 (出演公演の id など) を落としたもの。
pub fn profile(snap: &Snapshot, idol_id: &str, today_key: &str) -> Result<Value, ToolError> {
    let mut full = call_tool(snap, "get_idol", &json!({ "id": idol_id }), today_key)?;
    if let Some(o) = full.as_object_mut() {
        for key in ["first_show", "latest_show", "birthday_raw", "brands", "top_performed_songs_total", "top_performed_songs_truncated"] {
            o.remove(key);
        }
    }
    Ok(full)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    #[test]
    fn 指示文に名前とプロフィールと非公式の断りが入る() {
        let snap = bundle_snapshot();
        let idol = snap.idols.iter().find(|i| !i.is_external && i.description.is_some()).unwrap();
        let text = talk_instructions(&snap, &idol.id, "2026-10-01").unwrap();
        assert!(text.contains(&idol.name));
        assert!(text.contains("非公式"));
        assert!(text.contains("\"description\""));
        assert!(!text.contains("first_show"));
    }

    #[test]
    fn 知らないアイドルはエラー() {
        let snap = bundle_snapshot();
        assert!(talk_instructions(&snap, "no-such-idol", "2026-10-01").is_err());
    }
}
