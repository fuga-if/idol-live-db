//! アプリ内の会話の FFI 口。中身は `agent::tools::assistant`、操作の語彙と検査は `domain::ai_actions`。
//! アプリは HTTP を運び、返事と一覧を見せ、押されたら既存の書き込み口を呼ぶ。会話の続きは
//! `AssistantPlan::history` を次の `assistant_request` に渡す。

use super::natural_search::PlanTaskRequest;
use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::agent::tools::assistant as a;
use crate::domain::ai_actions::{AiDeviceContext, AiPlannedAction};

/// 1 番ぶんの結果: 返事と、検証を通った「これからやること」。
#[derive(Debug, Clone, uniffi::Record)]
pub struct AssistantPlan {
    /// モデルの返事。
    pub message: String,
    /// この番で積まれた操作。
    pub actions: Vec<AiPlannedAction>,
    /// 検査で落とした操作の件数。
    pub rejected: u32,
    /// ここまでの会話。次の番の `assistant_request` に渡す。
    pub history: Vec<String>,
}

/// 1 往復ぶんの結末。`plan` があれば終わり、無ければ `next_input` でもう 1 往復する。
#[derive(Debug, Clone, uniffi::Record)]
pub struct AssistantStep {
    pub plan: Option<AssistantPlan>,
    pub next_input: Vec<String>,
}

/// この頼みを受けてよいか (長さ)。
#[uniffi::export]
pub fn assistant_accepts(order: String) -> bool {
    a::accepts(&order)
}

/// この発言を送ってよいか。画像があれば、字は無くてもよい。
#[uniffi::export]
pub fn assistant_accepts_message(order: String, image_count: u32) -> bool {
    a::accepts_message(&order, image_count as usize)
}

/// 1 回の発言に添えられる画像の上限。
#[uniffi::export]
pub fn assistant_max_images() -> u32 {
    a::MAX_IMAGES as u32
}

/// 入力欄の上限 (文字数)。
#[uniffi::export]
pub fn assistant_max_order_chars() -> u32 {
    a::MAX_ORDER_CHARS as u32
}

/// 1 番ぶんのリクエスト。`history` は前の番の `AssistantPlan::history` (最初は空)。
/// `images_base64` は発言に添える画像 (JPEG の base64。無ければ空)。
/// 発言が受けられない長さ・会話が長くなりすぎた、なら None (新しい会話を促す)。
#[uniffi::export]
pub fn assistant_request(
    history: Vec<String>,
    order: String,
    images_base64: Vec<String>,
    today_key: String,
    device: AiDeviceContext,
) -> Option<PlanTaskRequest> {
    a::request(&history, &order, &images_base64, device.plan_context(&today_key)).map(|r| PlanTaskRequest {
        too_many_rounds_message: "調べものが長くなりすぎたので止めました。短く分けて試してください".into(),
        ..r.into()
    })
}

/// 入力欄が空のときに出す例。
#[uniffi::export]
pub fn assistant_examples() -> Vec<String> {
    a::example_orders().into_iter().map(String::from).collect()
}

#[uniffi::export]
impl SnapshotStore {
    /// 1 往復の応答を受けて、次にどうするかを決める (1 往復 = 1 呼び出し)。
    ///
    /// 読み取りツールはここで実行する。操作ツールは検査だけして積み、往復が終わったら
    /// 一覧にして返す (実行はしない)。`device` は端末の側の事情 (プレイリスト・習熟度の段階)。リクエストに渡したものと同じ。
    pub fn assistant_step(
        &self,
        input: Vec<String>,
        output_items: Vec<String>,
        text: String,
        today_key: String,
        device: AiDeviceContext,
    ) -> Result<AssistantStep, SnapshotError> {
        let snap = self.current()?;
        let ctx = device.plan_context(&today_key);
        Ok(match a::step(&snap, &input, &output_items, &text, ctx) {
            a::Step::Finished(p) => AssistantStep {
                plan: Some(AssistantPlan { message: p.message, actions: p.actions, rejected: p.rejected, history: p.history }),
                next_input: Vec::new(),
            },
            a::Step::Continue(next_input) => AssistantStep { plan: None, next_input },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_store;

    #[test]
    fn 頼みから一覧まで1往復ずつで通る() {
        let store = bundle_store();
        let req = assistant_request(Vec::new(), "お気に入りに入れて".into(), Vec::new(), "2026-11-16".into(), AiDeviceContext::default()).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(&req.tools_json).is_ok());
        let call = r#"{"type":"function_call","call_id":"c1","name":"set_favorite_song","arguments":"{\"song_id\":\"nope\"}"}"#;
        let step = store.assistant_step(req.input.clone(), vec![call.into()], String::new(), "2026-11-16".into(), AiDeviceContext::default()).unwrap();
        assert!(step.plan.is_none());
        let done = store
            .assistant_step(step.next_input, Vec::new(), r#"{"message":"曲が見つかりませんでした"}"#.into(), "2026-11-16".into(), AiDeviceContext::default())
            .unwrap();
        let plan = done.plan.unwrap();
        assert!(plan.actions.is_empty());
        assert_eq!(plan.rejected, 1);
        assert!(assistant_request(plan.history, "ほかには？".into(), Vec::new(), "2026-11-16".into(), AiDeviceContext::default()).is_some());
        assert!(!assistant_examples().is_empty() && assistant_accepts("参加を付けて".into()));
    }
}
