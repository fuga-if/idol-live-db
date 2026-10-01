import SwiftUI

/// アイドル当てクイズの出題設定画面。
/// ブランドを絞り込んでからクイズを開始する。設定は AppStorage で次回起動まで保持する。
///
/// 候補数の見積りと「4 択を組めるか」の判定は imas-core の `domain/quiz_generation.rs` が
/// ゲーム本体と共有する (別条件にすると「開始できるのに候補不足」というズレが起きる)。
/// 保存文字列とブランド id 列の変換規則もコア側。
struct IdolQuizSetupView: View {

    /// 永続化: カンマ区切りブランドID文字列（空文字列 = 全ブランド）。
    @AppStorage("idolQuizBrandIds") private var brandIdsRaw: String = ""

    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []
    /// 出題候補数と「4 択を組めるか」(コアが同じ母集団条件で数えた結果)。
    @State private var estimate = IdolQuizPoolEstimate(count: 0, isSufficient: false)
    @State private var isEstimating = false
    @State private var navigateToGame = false

    private var estimatedCount: Int { Int(estimate.count) }

    /// スタート可能かどうか（推計中は暫定的に許可して二重ロードを防ぐ）。
    private var canStart: Bool { isEstimating || estimate.isSufficient }

    var body: some View {
        ImasPage {
            ImasSetupHeader(systemImage: "person.fill.questionmark", title: "アイドル当てクイズ",
                            message: "プロフィールのヒントを手がかりに誰かを 4 択で当てよう")
            ImasSection("出題ブランド", style: .small, footer: "複数選択可 · 空=全ブランド対象",
                       actionTitle: selectedBrandIds.isEmpty ? nil : "全てに戻す",
                       onAction: selectedBrandIds.isEmpty ? nil : {
                           withAnimation(.easeInOut(duration: 0.15)) { selectedBrandIds = [] }
                       }) {
                ImasBrandPicker(brands: brands, selection: $selectedBrandIds)
            }
            ImasCandidateCount(count: estimatedCount, unit: "名", label: "出題候補",
                               isLoading: isEstimating, loadingText: "候補を計算中…")
            if !isEstimating && !estimate.isSufficient {
                ImasNotice(kind: .warning,
                           message: "4 択を出すにはアイドルが最低 4 名必要です。ブランドの選択を増やしてください。")
            }
            ImasButton(title: "スタート", systemImage: "play.fill", role: .primary, size: .large) {
                AppAnalytics.tap("idol_quiz_setup.start")
                navigateToGame = true
            }
            .disabled(!canStart)
        }
        .navigationTitle("アイドル当てクイズ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToGame) {
            IdolQuizView(selectedBrandIds: selectedBrandIds)
        }
        .task {
            // ブランド一覧の取得と、永続化データの復元を同時に実行。
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
            selectedBrandIds = decodeBrandIds(brandIdsRaw)
            await estimatePool()
        }
        .onChange(of: selectedBrandIds) { _, newValue in
            // 変更のたびに AppStorage へ書き戻して候補数を再計算する。
            brandIdsRaw = encodeBrandIds(newValue)
            Task { await estimatePool() }
        }
        .trackScreen("idol_quiz_setup")
    }

    // MARK: - Data

    /// 選択ブランドで絞り込んだときの出題候補アイドル数を計算する。
    /// IdolQuizView の出題生成 (`idolQuizSession`) と同じ母集団条件をコアが持つので、
    /// ここでの見積りと実際の出題プールは必ず一致する
    /// (以前は facts (プロフィール事実3件以上) チェックを省いた近似値だったため、
    /// 見積り上は開始可能でも実際は候補不足で始まってしまうことがあった)。
    private func estimatePool() async {
        isEstimating = true
        defer { isEstimating = false }
        let all = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
        estimate = idolQuizPoolEstimate(idols: idolQuizRefs(all), selectedBrandIds: Array(selectedBrandIds))
    }

    // MARK: - Helpers

    private func decodeBrandIds(_ raw: String) -> Set<String> {
        Set(quizBrandIdsDecode(raw: raw))
    }

    private func encodeBrandIds(_ ids: Set<String>) -> String {
        quizBrandIdsEncode(brandIds: Array(ids))
    }
}
