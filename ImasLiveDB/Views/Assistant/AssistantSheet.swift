import os
import SwiftUI

/// シートに渡す最初の発言 (`.sheet(item:)` 用)。空なら何も送らずに開く。
struct AssistantOrder: Identifiable {
    let id = UUID()
    let text: String
}

/// チャット。利用者の ChatGPT プランで、データベースを引いて答え、頼まれた操作を一覧にする。
///
/// 返事の事実はコアの読み取りツールで引いたもの。操作は、返事の下に「これからやること」として
/// 出て、利用者が選んで押すまで何も変わらない。一覧に出るのはコアが検査した操作だけ
/// (`domain::ai_actions`) で、サーバに届く操作・外す操作・前の中身を置き換える操作は初めは選ばれていない。
struct AssistantSheet: View {
    let initialOrder: String

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var turns: [Turn] = []
    /// ここまでの会話 (コアが組んだ input)。次の番にそのまま渡す。
    @State private var history: [String] = []
    @State private var path: [DetailDestination] = []
    @State private var runTask: Task<Void, Never>?

    private var session: ChatGPTPlanSession { .shared }

    private struct Turn: Identifiable {
        let id = UUID()
        let order: String
        var state: State

        enum State {
            case running(label: String)
            case done(Review)
            case failed(String)
        }
    }

    private enum Outcome {
        case done
        case failed(String)
    }

    /// 1 番ぶんの返事と一覧、その場の選択・実行の結果。
    private struct Review {
        var plan: AssistantPlan
        var selected: Set<Int>
        var outcomes: [Int: Outcome] = [:]
        var isExecuting = false

        var pending: [Int] { selected.filter { outcomes[$0] == nil }.sorted() }
    }

    private var isRunning: Bool {
        if case .running? = turns.last?.state { return true }
        return false
    }

    /// どれかの番が操作を実行している途中か (その間は会話を消させない)。
    private var isExecuting: Bool {
        turns.contains { turn in
            if case .done(let review) = turn.state { return review.isExecuting }
            return false
        }
    }

    private static let bottomID = "assistant.bottom"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ImasPage {
                    content
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: turns.count) { scrollToBottom(proxy) }
                .onChange(of: isRunning) { scrollToBottom(proxy) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if session.canUsePlan { composer }
            }
            .navigationTitle("チャット")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .navigationDestination(for: DetailDestination.self) { dest in
                DetailContentView(destination: dest) { path.append($0) }
            }
        }
        .onAppear {
            guard turns.isEmpty, text.isEmpty, session.canUsePlan, assistantAccepts(order: initialOrder) else { return }
            send(initialOrder)
        }
        .onChange(of: text) { _, new in
            let limit = Int(assistantMaxOrderChars())
            if new.count > limit { text = String(new.prefix(limit)) }
        }
        .onDisappear { runTask?.cancel() }
        .trackScreen("assistant")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
    }

    // MARK: - 中身

    @ViewBuilder
    private var content: some View {
        if !session.canUsePlan {
            ImasEmptyState(
                systemImage: "bubble.left.and.text.bubble.right",
                title: "ChatGPT とつなぐと使えます",
                message: "マイページの「ChatGPT とつなぐ」から、ChatGPT Plus / Pro のアカウントでログインしてください"
            )
        } else if turns.isEmpty {
            examples
        } else {
            ForEach(turns) { turn in
                turnView(turn)
            }
            if !isRunning, !isExecuting {
                ImasButton(title: "新しい会話にする", systemImage: "square.and.pencil", role: .plain, size: .small) {
                    reset()
                }
            }
        }
    }

    private var examples: some View {
        ImasSection("たとえば", style: .small) {
            ImasCardList(assistantExamples(), id: \.self) { example in
                Button {
                    AppAnalytics.tap("assistant.example")
                    send(example)
                } label: {
                    ImasNavRow(title: example, systemImage: "text.bubble", iconTone: .neutral, showsChevron: false)
                }
                .buttonStyle(.imasRow)
            }
            ImasNote("答えはデータベースを引いて作ります。頼んだ操作は、一覧で確かめて押すまで実行しません。", systemImage: "hand.raised")
        }
    }

    @ViewBuilder
    private func turnView(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            ImasChatBubble(turn.order)

            switch turn.state {
            case .running(let label):
                HStack(spacing: DS.Space.gap) {
                    ImasInlineLoading(tint: DS.sys)
                    Text(label).imasText(.note)
                    Spacer(minLength: 0)
                    ImasButton(title: "やめる", systemImage: "xmark", role: .secondary, size: .small) { cancel() }
                }
            case .done(let review):
                reviewView(review, turnID: turn.id)
            case .failed(let message):
                ImasNotice(kind: .error, title: "答えられませんでした", message: message,
                           actionTitle: "もう一度", action: { retry(turn) })
            }
        }
    }

    @ViewBuilder
    private func reviewView(_ review: Review, turnID: UUID) -> some View {
        let plan = review.plan
        if !plan.message.isEmpty {
            Text(plan.message)
                .imasText(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !plan.actions.isEmpty {
            ImasSection("これからやること", count: "\(plan.actions.count)件", style: .small) {
                ImasCardList(Array(plan.actions.enumerated()), id: \.offset) { index, item in
                    ImasSelectableRow(
                        title: item.title,
                        subtitle: item.target,
                        trailing: .value(trailingLabel(item, outcome: review.outcomes[index])),
                        isSelected: review.selected.contains(index),
                        isDisabled: review.isExecuting || review.outcomes[index] != nil
                    ) {
                        toggle(index, in: turnID)
                    }
                }
                if plan.actions.contains(where: { $0.reach == .shared }) {
                    ImasNote("「サーバ」と付いたものは送信され、数が他の人にも見えます。やるものだけ選んでください。",
                             systemImage: "arrow.up.circle")
                }
                if plan.actions.contains(where: { !$0.preselected && $0.reach != .shared }) {
                    ImasNote("外す・消す・置き換える操作は、初めは選ばれていません。", systemImage: "hand.raised")
                }
                ForEach(failures(review), id: \.self) { message in
                    ImasNote(message, systemImage: "exclamationmark.triangle")
                }
                if review.isExecuting {
                    ImasInlineLoading(tint: DS.sys).frame(maxWidth: .infinity)
                } else if !review.pending.isEmpty {
                    ImasButton(title: "選んだ \(review.pending.count) 件を実行する", systemImage: "checkmark",
                               role: .primary, size: .medium) { execute(turnID) }
                }
            }
        }
        if plan.rejected > 0 {
            ImasNote("\(plan.rejected) 件の操作は、データベースで確かめられなかったので外しました。", systemImage: "exclamationmark.circle")
        }
    }

    private var composer: some View {
        ImasChatComposer(prompt: "聞きたいこと・やってほしいこと", text: $text, canSend: canSend) { send(text) }
    }

    private var canSend: Bool {
        !isRunning && assistantAccepts(order: text)
    }

    private func trailingLabel(_ item: AiPlannedAction, outcome: Outcome?) -> String {
        switch outcome {
        case .done?: return "済み"
        case .failed?: return "失敗"
        case nil:
            switch item.reach {
            case .device: return "端末"
            case .shared: return "サーバ"
            case .screen: return "表示"
            }
        }
    }

    private func failures(_ review: Review) -> [String] {
        review.outcomes.keys.sorted().compactMap { index in
            guard case .failed(let message)? = review.outcomes[index] else { return nil }
            return "\(review.plan.actions[index].title): \(message)"
        }
    }

    // MARK: - 処理

    private func send(_ order: String) {
        guard session.canUsePlan, !isRunning, assistantAccepts(order: order) else { return }
        AppAnalytics.tap("assistant.send")
        text = ""
        let turn = Turn(order: order.trimmingCharacters(in: .whitespacesAndNewlines), state: .running(label: "考えています…"))
        turns.append(turn)
        start(turn)
    }

    private func retry(_ turn: Turn) {
        guard !isRunning, turns.last?.id == turn.id else { return }
        update(turn.id) { $0.state = .running(label: "考えています…") }
        start(turn)
    }

    private func start(_ turn: Turn) {
        runTask?.cancel()
        let before = history
        runTask = Task {
            do {
                let plan = try await AssistantRunner.run(history: before, order: turn.order) { label in
                    update(turn.id) { $0.state = .running(label: label) }
                }
                if Task.isCancelled { return }
                history = plan.history
                // 初めから選んでおくかはコアが決める (サーバに届く・外す・置き換える操作は選ばない)。
                let selected = Set(plan.actions.indices.filter { plan.actions[$0].preselected })
                update(turn.id) { $0.state = .done(Review(plan: plan, selected: selected)) }
            } catch is CancellationError {
                // やめた。発言は cancel() が消している。
            } catch {
                if Task.isCancelled { return }
                Logger.database.error("assistant_failed: \(error.localizedDescription)")
                update(turn.id) { $0.state = .failed(error.localizedDescription) }
            }
        }
    }

    /// 考えている途中の番をやめる。発言は入力欄に戻す。
    private func cancel() {
        runTask?.cancel()
        runTask = nil
        guard isRunning, let last = turns.popLast() else { return }
        text = last.order
    }

    private func reset() {
        runTask?.cancel()
        runTask = nil
        turns = []
        history = []
    }

    private func update(_ id: UUID, _ change: (inout Turn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }

    private func review(_ id: UUID) -> Review? {
        guard case .done(let review)? = turns.first(where: { $0.id == id })?.state else { return nil }
        return review
    }

    private func toggle(_ index: Int, in turnID: UUID) {
        guard var review = review(turnID), !review.isExecuting, review.outcomes[index] == nil else { return }
        if review.selected.contains(index) {
            review.selected.remove(index)
        } else {
            review.selected.insert(index)
        }
        update(turnID) { $0.state = .done(review) }
    }

    /// 選んだ操作を上から順に 1 件ずつ実行する。1 件の失敗で残りを止めない。
    private func execute(_ turnID: UUID) {
        guard var review = review(turnID), !review.isExecuting else { return }
        let targets = review.pending
        guard !targets.isEmpty else { return }
        AppAnalytics.tap("assistant.execute")
        review.isExecuting = true
        update(turnID) { $0.state = .done(review) }
        Task {
            var opened: AssistantExecutor.Opened?
            for index in targets {
                do {
                    let result = try await AssistantExecutor.perform(review.plan.actions[index].action)
                    opened = opened ?? result
                    review.outcomes[index] = .done
                } catch {
                    Logger.database.error("assistant_action_failed: \(error.localizedDescription)")
                    review.outcomes[index] = .failed(error.localizedDescription)
                }
                update(turnID) { $0.state = .done(review) }
            }
            review.isExecuting = false
            update(turnID) { $0.state = .done(review) }
            switch opened {
            case .detail(let destination)?: path.append(destination)
            // 一覧のタブへ移ったので、上に被さっているこのシートは閉じる。
            case .list?: dismiss()
            case nil: break
            }
        }
    }
}
