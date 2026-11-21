import UIKit

/// アプリ内の会話 1 番ぶん。往復は `ChatGPTPlanTaskRunner`、判断はコア (`agent::tools::assistant`)。
///
/// 返るのは返事と「これからやること」の一覧で、ここでは何も実行しない。
/// 実行は利用者が一覧を見て押してから (`AssistantExecutor`)。
@MainActor
enum AssistantRunner {
    /// 1 番ぶんの結果。`images` はこの番で描かれた画像 (会話には残さない)。
    struct Outcome: Sendable {
        let plan: AssistantPlan
        let images: [UIImage]
    }

    /// 往復をまたいで、描かれた画像を集める (step はメインスレッドの外で呼ばれる)。
    private actor GeneratedImages {
        private var encoded: [String] = []
        func add(_ more: [String]) { encoded.append(contentsOf: more) }
        func all() -> [String] { encoded }
    }

    /// 利用者がもう付けている記録を射影する。二重に積まないための検査と、`my_records` の答えに使う
    /// (見るのも数えるのもコア)。
    private static func userRecords() async throws -> AiUserRecords {
        let marks = UserMarkService.shared
        let attendance = marks.allMarked(kind: .attended, entity: .show).map { id in
            AiAttendanceRef(showId: id, types: marks.attendedTypes(entity: .show, id: id).map(\.rawValue))
        }
        let expenses = try await AppContainer.shared.ledgerReading.expenses().map { expense in
            AiExpenseRef(date: expense.date, category: expenseCategoryFromKey(key: expense.category),
                         amount: expense.amount, showId: expense.showId, note: expense.note)
        }
        return AiUserRecords(
            attendance: attendance,
            favoriteSongIds: marks.allMarked(kind: .favorite, entity: .song),
            myPickIdolIds: marks.allMarked(kind: .myPick, entity: .idol),
            ownedReleaseIds: marks.allMarked(kind: .owned, entity: .release),
            expenses: expenses,
            producerCard: try await producerCardRef()
        )
    }

    /// いまの自分の P名刺 (まだ作っていなければ nil)。検査と `my_records` の答えに使う。
    private static func producerCardRef() async throws -> AiProducerCardRef? {
        guard let card = try await AppContainer.shared.producerCards.myCard(), !card.name.isEmpty else { return nil }
        return AiProducerCardRef(
            name: card.name, message: card.message, sinceYear: card.sinceYear.flatMap(UInt16.init(exactly:)),
            links: card.links, design: card.cardDesign, oshiIdolIds: card.cardOshiChoice ?? [],
            hasPhoto: ProducerCardFiles.myPhotoURL != nil, stickerCount: UInt32(ProducerCardFiles.myStickers.count)
        )
    }

    /// - Parameters:
    ///   - history: 前の番の `AssistantPlan.history` (最初は空)。
    ///   - images: 発言に添える画像 (この番にだけ送る。会話には持ち越さない)。
    static func run(history: [String], order: String, images: [UIImage] = [],
                    onProgress: (String) -> Void) async throws -> Outcome {
        let today = JSTDay.today()
        // 縮めて JPEG にするのはコール表の読み取りと同じ口 (長辺の上限も同じ)。
        let encoded = images.isEmpty ? [] : await Task.detached(priority: .userInitiated) {
            images.compactMap(CallSheetRunner.jpegBase64)
        }.value
        try Task.checkCancellation()
        // 縮められなかった画像を黙って落とさない (画像だけの発言だと、別の理由の文言が出てしまう)。
        guard encoded.count == images.count else {
            throw ChatGPTPlanTaskRunner.RunnerError(message: "画像を読み込めませんでした。別の画像で試してください")
        }
        // 端末の側の事情 (足す先のプレイリスト・習熟度の段階の名前) を射影して渡す。決めるのはコア。
        let playlists = try await AppContainer.shared.playlists.summaries()
            .map { AiPlaylistRef(id: $0.playlist.id, name: $0.playlist.name) }
        let device = AiDeviceContext(playlists: playlists, masteryLabels: UserMarkService.shared.scale.labels,
                                     records: try await userRecords())
        guard let request = assistantRequest(history: history, order: order, imagesBase64: encoded, todayKey: today, device: device) else {
            throw ChatGPTPlanTaskRunner.RunnerError(message: "会話が長くなりました。新しい会話を始めてください")
        }
        let store = try await AppContainer.shared.coreSnapshot.loadedStore()
        let generated = GeneratedImages()
        let plan: AssistantPlan = try await ChatGPTPlanTaskRunner.run(request: request, onProgress: onProgress) { input, items, text in
            let step = try store.assistantStep(input: input, outputItems: items, text: text, todayKey: today,
                                               device: device)
            // 描かれた画像は往復ごとに来る (次の往復には積み直さない)。
            if !step.images.isEmpty { await generated.add(step.images) }
            if let plan = step.plan { return .finished(plan) }
            if step.fetches.isEmpty {
                // 利用者の記録を読んだ番は、残りの往復で外へ出る口 (Web 検索) を閉じる。決めるのはコア。
                return step.withoutBuiltIns ? .nextWithoutBuiltIns(step.nextInput) : .next(step.nextInput)
            }
            // X のポストは端末が取りに行く。行き先はコアが組んだものだけで、削るのもコア。
            let results = await AssistantFetcher.fetch(step.fetches)
            return .next(assistantFetched(input: step.nextInput, results: results))
        }
        let images = await generated.all().compactMap { Data(base64Encoded: $0).flatMap(UIImage.init(data:)) }
        return Outcome(plan: plan, images: images)
    }
}
