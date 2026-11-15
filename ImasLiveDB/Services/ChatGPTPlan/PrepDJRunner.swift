import Foundation

/// 予習 DJ。コアだけで組んだ流れと、ChatGPT プランで語りを付けた流れの 2 つの口。
///
/// 並べ方・語りの検証・注文の上限は全部コア (`domain::prep_dj` / `agent::tools::prep_dj`)。
@MainActor
enum PrepDJRunner {
    /// 入口に出す名前 (「予習 DJ」「復習 DJ」)。nil なら入口を出さない (どの公演に出すかはコアが決める)。
    static func entryLabel(showId: String) async -> String? {
        guard let store = try? await AppContainer.shared.coreSnapshot.loadedStore() else { return nil }
        return (try? store.prepDjEntryLabel(showId: showId)) ?? nil
    }

    /// コアだけで組んだ流れ (つないでいなくても出る)。組めない公演は nil。
    static func basePlan(showId: String) async throws -> PrepDjPlan? {
        let store = try await AppContainer.shared.coreSnapshot.loadedStore()
        // 初回は予測の下ごしらえで重いので、メインスレッドの外で呼ぶ。
        return try await Task.detached(priority: .userInitiated) {
            try store.prepDjPlan(showId: showId)
        }.value
    }

    /// ChatGPT プランで語りつきの流れを組む。使える流れにならなければ、コアの文言で失敗を投げる。
    static func modelPlan(showId: String, order: String, onProgress: (String) -> Void) async throws -> PrepDjPlan {
        let today = JSTDay.today()
        let store = try await AppContainer.shared.coreSnapshot.loadedStore()
        let request = try await Task.detached(priority: .userInitiated) {
            try store.prepDjRequest(showId: showId, order: order, todayKey: today)
        }.value
        guard let request else {
            throw ChatGPTPlanTaskRunner.RunnerError(message: "この公演の流れは組めません")
        }
        return try await ChatGPTPlanTaskRunner.run(request: request, onProgress: onProgress) { input, items, text in
            let step = try store.prepDjStep(showId: showId, input: input, outputItems: items, text: text, todayKey: today)
            if !step.nextInput.isEmpty { return .next(step.nextInput) }
            if let plan = step.plan { return .finished(plan) }
            throw ChatGPTPlanTaskRunner.RunnerError(message: step.failureMessage ?? "うまく組めませんでした")
        }
    }
}
