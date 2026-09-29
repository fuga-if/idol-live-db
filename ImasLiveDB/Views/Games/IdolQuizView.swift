import SwiftUI

/// アイドル当てクイズ。最初はシルエット＋曖昧なプロフィール1項目だけで出題し、
/// 並んだヒントの属性をユーザがどれから開けるか選ぶ (戦略性)。
/// 素点は 10pt で、ヒントを 1 つ開くごとに獲得点が下がる (CV/メンバーカラーは -2pt)。
/// CV枠は常設し、声優未発表キャラは開封して初めて「声優未発表」と分かる
/// (CV枠の有無で不在が無料でバレないようにする)。全 sessionLength 問のセッション制。
///
/// 出題の生成・選択肢の作り方・採点・母集団の条件は imas-core の
/// `domain/quiz_generation.rs` にあり、Android と同じ実装を共有する。素点 10pt や
/// 出題数といった規則の定数もコア側にあり、ここからは指定しない。
/// この画面が担うのは描画と、シード調達 (`SystemRandomNumberGenerator`) だけ。
struct IdolQuizView: View {

    /// 出題ブランド絞り込み（空集合 = 全ブランド対象）。IdolQuizSetupView から渡す。
    let selectedBrandIds: Set<String>

    /// 途中でやめたセッションの続き (ゲーム一覧の「つづきから」)。nil なら新しく始める。
    let resume: QuizSuspended?

    init(selectedBrandIds: Set<String> = [], resume: QuizSuspended? = nil) {
        self.selectedBrandIds = selectedBrandIds
        self.resume = resume
    }

    /// 1 セッションの出題数 (規則本体はコア。UI は総問数の表示にだけ使う)。
    private var sessionLength: Int { Int(quizSessionLength()) }

    /// 出題の index 参照元。コアが返す `answer` / `choices` はこの配列の位置を指す。
    @State private var idols: [Idol] = []
    /// 1 ゲーム分の出題 (コアが 1 回でまとめて生成)。
    @State private var questions: [IdolQuizQuestion] = []
    @State private var index = 0
    @State private var selectedId: String?
    @State private var opened: [UInt32] = []   // 開いたヒントの facts インデックス (1...)
    /// 開示範囲と残りヒント (コアが算出)。
    @State private var hint = IdolQuizHintState(currentValue: 0, shownFactIndices: [], hints: [])
    /// ヒントを開く前の獲得点 (出題ごとに記録。メーターの「100」側)。
    @State private var baseValue = 0
    /// 解答済み問題数・正解数・累計ポイント (コアが積み上げる)。
    @State private var tally = QuizTally(asked: 0, correct: 0, points: 0)
    @State private var isLastQuestion = false
    /// 各問の記録 (ペンライト・連続正解・見直す)。
    @State private var plays: [QuizStagePlay] = []
    /// 直前の問題の判定 (解答後に出す大きなカード)。
    @State private var verdict: QuizVerdict?
    @State private var scoreBefore = 0
    @State private var result: QuizSessionResult?
    @State private var isNewBest = false
    @State private var previousBest: Int?
    @State private var isLoading = true
    /// このセッションの出題シード (つづきからで同じ出題を作り直す)。
    @State private var seed: UInt64 = 0
    /// `resume` は最初の 1 回だけ使う (「もう一度」は新しいセッション)。
    @State private var didUseResume = false
    @Environment(\.dismiss) private var dismiss

    private var question: IdolQuizQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    private var header: QuizStageHeader {
        if let result { return .result(total: Int(result.questions)) }
        guard question != nil, !isLoading else { return .none }
        return .question(current: min(plays.count + (verdict == nil ? 1 : 0), sessionLength),
                         total: sessionLength, points: Int(tally.points))
    }

    var body: some View {
        QuizStageScaffold(title: "アイドル当て", header: header, onClose: { dismiss() }, trailing: {
            if let result {
                QuizStageRoundButton(systemImage: "square.and.arrow.up", label: "結果を画像でシェア") {
                    AppAnalytics.tap("idol_quiz.share_image")
                    QuizShareCard(title: "アイドル当て", result: result, rows: plays.shareRows,
                                  longestStreak: plays.longestStreak, isNewBest: isNewBest)
                        .share(text: QuizShareCard.text("アイドル当てクイズ", result))
                }
            }
        }) {
            content
        }
        .task { await load() }
        .trackScreen("idol_quiz")
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ImasInlineLoading(tint: QS.ink)
        } else if let result {
            QuizStageResultView(result: result, kind: .idolQuiz, isNewBest: isNewBest,
                                previousBest: previousBest,
                                slots: plays.penlights(total: Int(result.questions), answering: false),
                                longestStreak: plays.longestStreak, misses: plays.misses,
                                onReplay: { restart() }, onClose: { dismiss() })
        } else if let q = question {
            QuizStageProgress(slots: plays.penlights(total: sessionLength, answering: verdict == nil),
                              caption: plays.setlistCaption(total: sessionLength),
                              streak: plays.streak, streakBrokeAt: plays.streakBrokeAt)
                .padding(.bottom, 2)
            if let verdict {
                QuizVerdictCard(verdict: verdict).id(verdict.number)
                QuizVerdictStats(before: scoreBefore, after: Int(tally.points), streak: plays.streak)
                if !verdict.isCorrect { QuizVerdictFootnote() }
                QuizStageNextButton(isLastQuestion: isLastQuestion, onNext: nextQuestion, onFinish: finish)
                    .padding(.top, 4)
            } else {
                QuizValueMeter(value: Int(hint.currentValue), base: baseValue, note: meterNote)
                ticket(q)
                QuizStageChoiceGrid(choices: choices(q).map { QuizStageChoice(id: $0.id, title: $0.name) }) { choice in
                    if let idol = idols.first(where: { $0.id == choice.id }) { pick(idol) }
                }
                .padding(.top, 4)
            }
        } else {
            ImasEmptyState(systemImage: "person.fill.questionmark", title: "出題できる候補が不足しています")
        }
    }

    private var meterNote: String {
        opened.isEmpty ? "ヒントを開くと減ります" : "ヒント \(opened.count) 枚で −\(baseValue - Int(hint.currentValue))"
    }

    // MARK: - チケット (無料の事実 + ヒント)

    private func ticket(_ q: IdolQuizQuestion) -> some View {
        // 最初から見えている事実 = 公開済みのうち、ヒントで開いたもの以外。
        let free = hint.shownFactIndices.filter { !opened.contains($0) }
        let hintTotal = opened.count + hint.hints.count
        return QuizTicket {
            QuizTicketHeading(label: "PROFILE", question: "このアイドルはだれ？")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(free, id: \.self) { idx in
                    let f = q.facts[Int(idx)]
                    QuizTicketFactTile(label: f.label, value: f.value)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 12)
            if hintTotal > 0 {
                QuizTicketNotch()
                QuizTicketHintHeader(opened: opened.count, total: hintTotal)
                // 開いた順 → 未開封 の順に並べる。CV 枠はコアが常設しているので、
                // ラベルの有無で声優未発表キャラがバレることはない。
                ForEach(Array(opened.enumerated()), id: \.element) { pos, idx in
                    let f = q.facts[Int(idx)]
                    QuizTicketHintRow(number: pos + 1, label: f.label, cost: Int(f.cost), isOpen: true,
                                      isNew: pos == opened.count - 1, isFirst: pos == 0, onOpen: {}) {
                        factValue(f)
                    }
                }
                ForEach(Array(hint.hints.enumerated()), id: \.element.factIndex) { pos, option in
                    QuizTicketHintRow(number: opened.count + pos + 1, label: option.label,
                                      cost: Int(hint.currentValue) - Int(option.nextValue),
                                      isOpen: false, isFirst: opened.isEmpty && pos == 0,
                                      onOpen: { openHint(option) }) { EmptyView() }
                }
                Color.clear.frame(height: 6)
            }
        }
    }

    @ViewBuilder
    private func factValue(_ f: IdolQuizFact) -> some View {
        // 色そのものが答えになる項目だけ色チップで見せる (文言ではなく種別で分岐)。
        if f.kind == .memberColor {
            QuizTicketColorValue(hex: f.value)
        } else {
            QuizTicketHintValue(text: f.value)
        }
    }

    private func openHint(_ option: IdolQuizHintOption) {
        AppAnalytics.tap("idol_quiz.hint")
        withAnimation(.easeInOut(duration: 0.2)) {
            opened.append(option.factIndex)
            refreshHint()
        }
    }

    // MARK: - 進行

    /// 選択肢に並べるアイドル (コアが返す index を引き当てる)。
    private func choices(_ q: IdolQuizQuestion) -> [Idol] {
        q.choices.compactMap { idols.indices.contains(Int($0)) ? idols[Int($0)] : nil }
    }

    private func pick(_ idol: Idol) {
        guard selectedId == nil, let q = question else { return }
        AppAnalytics.tap("idol_quiz.answer")
        selectedId = idol.id
        let answer = idols[Int(q.answer)]
        scoreBefore = Int(tally.points)
        // 正誤判定・獲得点・積み上げはコアがまとめて返す (加点式なので不正解でも減点しない)。
        let outcome = idolQuizAnswer(facts: q.facts, openedFactIndices: opened,
                                     pickedIdolId: idol.id, answerIdolId: answer.id, before: tally)
        isLastQuestion = outcome.isLastQuestion
        refreshHint()
        let number = plays.count + 1
        // 解答後は全部の事実が公開されるので、正解の補足としてプロフィールを 1 行で添える。
        let summary = hint.shownFactIndices
            .map { q.facts[Int($0)] }
            .filter { $0.kind != .memberColor }
            .prefix(4).map(\.value).joined(separator: " · ")
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            tally = outcome.tally
            plays.append(QuizStagePlay(number: number, isCorrect: outcome.isCorrect,
                                       answerName: answer.name, answerHex: answer.color,
                                       pickedName: outcome.isCorrect ? nil : idol.name))
            verdict = QuizVerdict(isCorrect: outcome.isCorrect, number: number,
                                  answerName: answer.name, answerHex: answer.color,
                                  earned: Int(outcome.earnedPoints), base: baseValue,
                                  hints: Int(outcome.revealedHints),
                                  pickedName: outcome.isCorrect ? nil : idol.name,
                                  detail: summary)
        }
        if outcome.isCorrect { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        saveProgress()
    }

    /// 1 問答えるたびに途中経過を残す (× で閉じても「つづきから」で戻れる)。
    private func saveProgress() {
        QuizResumeStore.shared.save(QuizSuspended(
            kind: .idolQuiz, seed: seed, brandIds: Array(selectedBrandIds),
            nextIndex: index + 1, asked: Int(tally.asked), correct: Int(tally.correct),
            points: Int(tally.points), plays: plays, total: sessionLength, savedAt: .now))
    }

    private func nextQuestion() {
        selectedId = nil
        opened = []
        verdict = nil
        index += 1
        refreshHint()
        baseValue = Int(hint.currentValue)
    }

    private func restart() {
        startSession()
    }

    private func finish() {
        let sessionResult = idolQuizSessionResult(tally: tally)
        previousBest = GameProgressStore.shared.previousBestScore(for: .idolQuiz)
        // 保存と「自己ベスト更新！」の判定は進捗ストア (コアの game_progress) が 1 回で返す。
        let update = GameProgressStore.shared.recordResult(
            .idolQuiz, score: Int(sessionResult.points), outOf: Int(sessionResult.outOf))
        isNewBest = update.isNewBest
        QuizResumeStore.shared.clear(.idolQuiz)
        verdict = nil
        result = sessionResult
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        idols = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
        startSession()
    }

    /// 1 ゲーム分の出題をコアに一括生成させる (問題ごとに FFI を呼ばない)。
    /// 母集団の条件は IdolQuizSetupView の見積りと同じ関数が持つので、
    /// 「開始できるのに候補不足」というズレが起きない。
    private func startSession() {
        // つづきからは保存したシードで同じ出題を作り直し、答えた所まで進める。
        let saved = didUseResume ? nil : resume
        didUseResume = true
        if let saved {
            seed = saved.seed
        } else {
            var generator = SystemRandomNumberGenerator()
            seed = generator.next()
            QuizResumeStore.shared.clear(.idolQuiz)
        }
        questions = idolQuizSession(idols: idolQuizRefs(idols),
                                    selectedBrandIds: Array(selectedBrandIds),
                                    seed: seed)
        index = saved?.nextIndex ?? 0
        selectedId = nil
        opened = []
        tally = saved?.tally ?? QuizTally(asked: 0, correct: 0, points: 0)
        isLastQuestion = false
        plays = saved?.plays ?? []
        verdict = nil
        result = nil
        isNewBest = false
        previousBest = nil
        refreshHint()
        baseValue = Int(hint.currentValue)
        // 最後の問題まで答えてから閉じていたら、そのまま結果へ。
        if saved != nil && index >= questions.count && !questions.isEmpty { finish() }
    }

    /// 開示範囲と残りヒントを引き直す (出題が変わった / ヒントを開いた / 解答した とき)。
    private func refreshHint() {
        hint = idolQuizHintState(facts: question?.facts ?? [],
                                 openedFactIndices: opened,
                                 answered: selectedId != nil)
    }
}
