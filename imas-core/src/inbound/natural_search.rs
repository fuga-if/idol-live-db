//! 自然文検索 (利用者の ChatGPT プランの Responses API) の FFI。
//! 中身は agent::tools::natural_search。アプリは HTTP を運び、JSON を受け渡すだけ。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::agent::tools::natural_search as ns;

/// 1 回の検索でモデルに渡すもの一式。
#[derive(Debug, Clone, uniffi::Record)]
pub struct NaturalSearchRequest {
    pub instructions: String,
    /// 最初の input (利用者の発言 1 件)。各項目は JSON の文字列。
    pub input: Vec<String>,
    /// Responses API の `tools` (JSON)。
    pub tools_json: String,
    /// Responses API の `text.format` (JSON)。
    pub text_format_json: String,
    /// 関数呼び出しを何往復まで許すか。
    pub max_rounds: u32,
    /// 往復の上限に達したときに出す文言。
    pub too_many_rounds_message: String,
}

/// 1 往復ぶんの結末。`answer` があれば終わり、無ければ `next_input` でもう 1 往復する。
#[derive(Debug, Clone, uniffi::Record)]
pub struct NaturalSearchStep {
    pub answer: Option<NaturalSearchAnswer>,
    pub next_input: Vec<String>,
}

/// 検証を通った答え (表示順の id 列 3 本)。実体化はプラットフォーム側が自国の store で行う。
#[derive(Debug, Clone, uniffi::Record)]
pub struct NaturalSearchAnswer {
    /// 語をどう読み取ったかの 1 行。空のこともある。
    pub interpretation: String,
    pub song_ids: Vec<String>,
    pub idol_ids: Vec<String>,
    pub event_ids: Vec<String>,
    /// DB に無い id・知らない種別で落とした件数。
    pub dropped: u32,
    /// 答えが型どおりに読めなかった。
    pub unreadable: bool,
}

/// この語を自然文検索に出してよいか (長さ)。
#[uniffi::export]
pub fn natural_search_accepts(query: String) -> bool {
    ns::accepts(&query)
}

/// 1 回の検索のリクエスト。語が受けられない長さなら None。
#[uniffi::export]
pub fn natural_search_request(query: String, today_key: String) -> Option<NaturalSearchRequest> {
    ns::request(&query, &today_key).map(|r| NaturalSearchRequest {
        instructions: r.instructions,
        input: r.input,
        tools_json: r.tools.to_string(),
        text_format_json: r.text_format.to_string(),
        max_rounds: ns::MAX_ROUNDS,
        too_many_rounds_message: "調べものが長くなりすぎたので止めました。文を短くして試してください".into(),
    })
}

/// ツール実行中に出す一言 (「セトリを調べています…」)。
#[uniffi::export]
pub fn natural_search_progress_label(name: String) -> String {
    ns::progress_label(&name).to_string()
}

/// 入力欄が空のときに出す例。
#[uniffi::export]
pub fn natural_search_examples() -> Vec<String> {
    ns::example_queries().into_iter().map(String::from).collect()
}

/// 使うモデルを選ぶ。`available` は API が返した並びのまま。
#[uniffi::export]
pub fn natural_search_pick_model(available: Vec<String>, saved: Option<String>) -> Option<String> {
    ns::pick_model(&available, saved.as_deref())
}

#[uniffi::export]
impl SnapshotStore {
    /// 1 往復の応答を受けて、次にどうするかを決める (1 往復 = 1 呼び出し)。
    ///
    /// 関数呼び出しがあればここで全部実行し、次のリクエストの input を返す。無ければ
    /// 本文を答えとして検証して返す (DB に実在する id だけが通る)。
    /// `input` はこの往復で送った input、`output_items` は応答で確定した出力項目、
    /// `text` は本文の断片をつないだもの。
    pub fn natural_search_step(
        &self,
        input: Vec<String>,
        output_items: Vec<String>,
        text: String,
        today_key: String,
    ) -> Result<NaturalSearchStep, SnapshotError> {
        let snap = self.current()?;
        Ok(match ns::step(&snap, &input, &output_items, &text, &today_key) {
            ns::Step::Finished(a) => NaturalSearchStep {
                answer: Some(NaturalSearchAnswer {
                    interpretation: a.interpretation,
                    song_ids: a.song_ids,
                    idol_ids: a.idol_ids,
                    event_ids: a.event_ids,
                    dropped: a.dropped,
                    unreadable: a.unreadable,
                }),
                next_input: Vec::new(),
            },
            ns::Step::Continue(next_input) => NaturalSearchStep { answer: None, next_input },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_store;

    #[test]
    fn リクエストから答えの検証まで1往復ずつで通る() {
        let store = bundle_store();
        let req = natural_search_request("READY!!が披露されたライブ".into(), "2026-11-16".into()).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(&req.tools_json).is_ok());
        assert!(serde_json::from_str::<serde_json::Value>(&req.text_format_json).is_ok());
        assert!(req.max_rounds > 0);

        // 関数呼び出しの往復。
        let call = r#"{"type":"function_call","call_id":"c1","name":"search","arguments":"{\"query\":\"READY\"}"}"#;
        let step = store
            .natural_search_step(req.input.clone(), vec![call.into()], String::new(), "2026-11-16".into())
            .unwrap();
        assert!(step.answer.is_none());
        assert_eq!(step.next_input.len(), req.input.len() + 2);

        // 答えの往復。
        let done = store
            .natural_search_step(
                step.next_input,
                Vec::new(),
                r#"{"interpretation":"x","hits":[{"kind":"song","id":"nope"}]}"#.into(),
                "2026-11-16".into(),
            )
            .unwrap();
        let answer = done.answer.unwrap();
        assert_eq!(answer.dropped, 1);
        assert!(answer.song_ids.is_empty());
        assert!(!answer.unreadable);
    }
}
