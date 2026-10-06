import SwiftUI

/// 質問と答えの欄 (プロフィール帳の「自分で書く欄」1 つ)。
///
/// - **用途** 用意した質問に答えを書く欄を、List の 1 行に置く。質問文も書き換えられる。
///   行は List の `onMove` (長押しで並べ替え) と `onDelete` (左に引いて外す) と組む。
/// - **使わない** 質問の無い長文 → `ImasTextAreaRow` / 1 行の値 → `ImasTextFieldRow`。
/// - **構成** 上に設問番号の印字 (`Q1`) と質問 (空なら用意した質問文を薄く出す)、
///   下に答え (複数行、打つだけ伸びる)、右下に文字数。
/// - **状態** 上限を超えたら文字数を朱に (保存を止めるのは画面の検査)。
struct ImasQuestionField: View {
    /// 設問番号 (1 から)。
    let number: Int
    @Binding var prompt: String
    /// 質問を空にしたときに使う用意した質問文。
    let defaultPrompt: String
    @Binding var answer: String
    /// 答えの書き方の例。
    var placeholder: String = ""
    var promptLimit: Int? = nil
    var answerLimit: Int? = nil
    /// 上限と比べる数え方 (検査と同じ数え方を画面から渡す。既定は前後の空白を除いた字数)。
    var measure: (String) -> Int = { $0.trimmingCharacters(in: .whitespacesAndNewlines).count }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
                Text(verbatim: "Q\(number)").imasText(.imprint, color: DS.ink3)
                TextField(defaultPrompt, text: $prompt)
                    .imasText(.rowLabel)
                    .accessibilityLabel("質問 \(number)")
                if let promptLimit, measure(prompt) > promptLimit {
                    Text("\(measure(prompt)) / \(promptLimit)").imasText(.note, color: DS.danger)
                }
            }
            TextField(placeholder, text: $answer, axis: .vertical)
                .lineLimit(2...)
                .imasText(.body)
                .accessibilityLabel(prompt.isEmpty ? defaultPrompt : prompt)
            if let answerLimit {
                let count = measure(answer)
                Text("\(count) / \(answerLimit)")
                    .imasText(.note, color: count > answerLimit ? DS.danger : DS.ink3)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, DS.Space.gapTight)
        .listRowBackground(DS.surface)
    }
}
