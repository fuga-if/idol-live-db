import SwiftUI

/// セトリ当てクイズの出題設定画面。
/// ブランドを絞り込んでからクイズを開始する。設定は AppStorage で次回起動まで保持する。
///
/// 出題できる公演数の見積りはゲーム本体と同じ条件で imas-core の `domain/setlist_quiz.rs` が数える。
struct SetlistQuizSetupView: View {

    /// 永続化: カンマ区切りブランドID文字列（空文字列 = 全ブランド）。
    @AppStorage("setlistQuizBrandIds") private var brandIdsRaw: String = ""

    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []
    /// 出題できる公演数 (コアがゲーム本体と同じ条件で数えた結果)。
    @State private var estimate = SetlistQuizPoolEstimate(showCount: 0, isSufficient: false)
    @State private var isEstimating = false
    @State private var navigateToGame = false

    private var canStart: Bool { isEstimating || estimate.isSufficient }

    var body: some View {
        ImasPage {
            ImasSetupHeader(systemImage: "list.number", title: "セトリ当て",
                            message: "公演のセトリの空欄に入る曲を 4 択で当てよう")
            ImasBrandPicker(brands: brands, selection: $selectedBrandIds)
            ImasCandidateCount(count: isEstimating ? nil : Int(estimate.showCount), unit: "公演", minimum: 1,
                               label: "出題候補", note: "セトリが 6 曲以上ある公演から出します")
            if !isEstimating && !canStart {
                ImasNotice(kind: .warning,
                           message: "このブランドには出題できる公演がありません。ブランドの選択を増やしてください。")
            }
            ImasButton(title: "スタート", systemImage: "play.fill", role: .primary, size: .large) {
                AppAnalytics.tap("setlist_quiz_setup.start")
                navigateToGame = true
            }
            .disabled(!canStart)
        }
        .navigationTitle("セトリ当て")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToGame) {
            SetlistQuizView(selectedBrandIds: selectedBrandIds)
        }
        .task {
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
            selectedBrandIds = decodeBrandIds(brandIdsRaw)
            await estimatePool()
        }
        .onChange(of: selectedBrandIds) { _, newValue in
            brandIdsRaw = encodeBrandIds(newValue)
            Task { await estimatePool() }
        }
        .trackScreen("setlist_quiz_setup")
    }

    // MARK: - Data

    private func estimatePool() async {
        isEstimating = true
        defer { isEstimating = false }
        if let e = try? await AppContainer.shared.setlistQuizReading.poolEstimate(brandIds: Array(selectedBrandIds)) {
            estimate = e
        }
    }

    // MARK: - Helpers

    private func decodeBrandIds(_ raw: String) -> Set<String> {
        Set(quizBrandIdsDecode(raw: raw))
    }

    private func encodeBrandIds(_ ids: Set<String>) -> String {
        quizBrandIdsEncode(brandIds: Array(ids))
    }
}
