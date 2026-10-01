//! キャラとのトーク (アプリ内のオプトイン機能) の指示文。
//!
//! 人格の材料は DB のプロフィール (`get_idol` と同じ形) と、同梱した話し方 ([`super::speech`]:
//! 出典付きの一人称・呼び方・語尾と im@sparql の呼称)。話し方のデータがある子は指示文の先頭で
//! 必ず守らせ、無い子は公式の話し方をモデルの知識に任せる。あわせて「非公式のなりきり」で
//! あることと、事実はツールで引くことを縛る。

use super::{call_tool, speech, ToolError};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// キャラ 1 人とのトークの指示文。アイドルが見つからなければ `NotFound`。
///
/// `recent_replies` はそのキャラの直近の返信。ここに出た口癖は今回は使わないよう添える
/// (口癖の連打は不自然になる)。
pub fn talk_instructions(
    snap: &Snapshot,
    idol_id: &str,
    today_key: &str,
    recent_replies: &[String],
) -> Result<String, ToolError> {
    let profile = profile(snap, idol_id, today_key)?;
    let name = profile["name"].as_str().unwrap_or(idol_id).to_string();
    let brand = profile["brand"]["short_name"].as_str().unwrap_or("アイドルマスター").to_string();
    // 出典付きの話し方があれば先頭に置き、必ず守らせる (モデルの記憶は口調がぶれる)。
    let others: Vec<(String, String)> = speech::call_names_from(idol_id)
        .into_iter()
        .filter_map(|(id, _)| snap.idol(&id).map(|i| (id, i.name.clone())))
        .take(40)
        .collect();
    let avoid = speech::used_catchphrases(idol_id, recent_replies);
    let speech_rule = match speech::speech_block(idol_id, &others, &avoid) {
        Some(block) => format!("## 「{name}」の話し方\n{block}\n\n"),
        None => String::new(),
    };
    Ok(format!(
        "\
{speech_rule}あなたは『{brand}』のアイドル「{name}」です。プロデューサー (このアプリの利用者) と、
メッセージアプリでやりとりしています。

- これはファンが楽しむための、AI による非公式のなりきりです。公式の発言・設定ではありません。
  公式の発表・未発表の情報・今後の予定をでっち上げない。
- 一人称・プロデューサーの呼び方・仲間の呼び方は「話し方」の「必ず守る」のとおりに書く
  (無ければ「{name}」の公式の呼び方)。口調は性格と話し方の要約から自然に寄せる。
- {catchphrase_rule}
- キャラ紹介文のような誇張や、お約束の言い回しの羅列をしない。LINE の普通の返信として、
  相手の話の中身に反応し、短く自然に返す (1〜3 文)。長文や箇条書きにしない。
- キャラの外に出て解説しない。
- ライブ・曲・共演者の事実を話すときは、ツールで DB を引いてから話す。記憶で作らない。
  プロデューサーの参戦記録は my_attended_shows で分かる。
- 性的な話題・誰かを傷つける話題・実在の人物 (声優さんを含む) の私生活の話には乗らず、
  キャラのまま穏やかにかわす。
- 今日は {today_key} (日本時間)。

以下はデータベースにある「{name}」のプロフィール (JSON)。
{profile}",
        catchphrase_rule = speech::CATCHPHRASE_RULE,
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
        let text = talk_instructions(&snap, &idol.id, "2026-10-01", &[]).unwrap();
        assert!(text.contains(&idol.name));
        assert!(text.contains("非公式"));
        assert!(text.contains("\"description\""));
        assert!(!text.contains("first_show"));
    }

    #[test]
    fn 話し方データのある子は指示文の先頭で一人称と呼び方を縛る() {
        let snap = bundle_snapshot();
        let text = talk_instructions(&snap, "765as_我那覇響", "2026-10-01", &[]).unwrap();
        assert!(text.starts_with("## 「我那覇響」の話し方\n必ず守る"), "{text}");
        assert!(text.contains("一人称: 自分"), "{text}");
        assert!(text.contains("仲間の呼び方:"), "{text}");
    }

    #[test]
    fn 口癖は参考扱いで連打させず普通の返信にさせる() {
        let snap = bundle_snapshot();
        let text = talk_instructions(&snap, "765as_天海春香", "2026-10-01", &[]).unwrap();
        assert!(text.contains(speech::CATCHPHRASE_RULE), "{text}");
        assert!(text.contains("お約束の言い回しの羅列をしない"), "{text}");
        assert!(text.contains("相手の話の中身に反応"), "{text}");
    }

    #[test]
    fn 直近の返信で使った口癖は今回使わないと添える() {
        let snap = bundle_snapshot();
        let recent = vec!["プロデューサーさん、本番ですよ、本番！".to_string()];
        let text = talk_instructions(&snap, "765as_天海春香", "2026-10-01", &recent).unwrap();
        assert!(text.contains("今回は使わない"), "{text}");
    }

    #[test]
    fn 知らないアイドルはエラー() {
        let snap = bundle_snapshot();
        assert!(talk_instructions(&snap, "no-such-idol", "2026-10-01", &[]).is_err());
    }
}
