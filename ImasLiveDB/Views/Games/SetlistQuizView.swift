import SwiftUI

/// セトリ当てクイズ。公演のセトリの 1 曲を伏せ、そこに入る曲を 4 択で当てる。
/// 最初は伏せた曲の前後 2 曲ずつだけ見せ、ヒント (前後をもっと見る / 歌唱メンバー / 2択) を
/// 開くほど獲得点が下がる。
///
/// 公演の選び方・伏せる曲・誤答の選び方・見せる範囲・採点は imas-core の
/// `domain/setlist_quiz.rs` にあり、Android と同じ実装を共有する。この画面は描画とシード調達だけ。
struct SetlistQuizView: View {
    /// 出題ブランド (空 = 全ブランド)。
    let selectedBrandIds: Set<String>
    /// 途中でやめたセッションの続き (ゲーム一覧の「つづきから」)。nil なら新しく始める。
    let resume: QuizSuspended?

    init(selectedBrandIds: Set<String> = [], resume: QuizSuspended? = nil) {
        self.selectedBrandIds = selectedBrandIds
        self.resume = resume
    }

    private var sessionLength: Int { Int(quizSessionLength()) }

    @State private var questions: [SetlistQuizQuestion] = []
    @State private var index = 0
    @State private var opened: [SetlistQuizHintKind] = []
    @State private var hint: SetlistQuizHintState?
    @State private var answered = false
    @State private var tally = QuizTally(asked: 0, correct: 0, points: 0)
    @State private var isLastQuestion = false
    @State private var plays: [QuizStagePlay] = []
    @State private var verdict: QuizVerdict?
    @State private var scoreBefore = 0
    @State private var result: QuizSessionResult?
    @State private var isNewBest = false
    @State private var previousBest: Int?
    @State private var isLoading = true
    @State private var seed: UInt64 = 0
    @State private var didUseResume = false
    /// 答えの曲のジャケット (シェア画像の背景)。結果が出た時点で読み込み始める。
    @State private var shareArtwork: Task<[String: UIImage], Never>?
    @State private var isPreparingShare = false
    @Environment(\.dismiss) private var dismiss

    private var question: SetlistQuizQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    private var header: QuizStageHeader {
        if let result { return .result(total: Int(result.questions)) }
        guard question != nil, !isLoading else { return .none }
        return .question(current: min(plays.count + (verdict == nil ? 1 : 0), sessionLength),
                         total: sessionLength, points: Int(tally.points))
    }

    var body: some View {
        QuizStageScaffold(title: "セトリ当て", header: header, onClose: { dismiss() }, trailing: {
            if let result {
                QuizStageRoundButton(systemImage: isPreparingShare ? "hourglass" : "square.and.arrow.up",
                                     label: "結果を画像でシェア") { shareResultImage(result) }
            }
        }) {
            content
        }
        .task { await load() }
        .trackScreen("setlist_quiz")
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ImasInlineLoading(tint: QS.ink)
        } else if let result {
            QuizStageResultView(result: result, kind: .setlistQuiz, isNewBest: isNewBest,
                                previousBest: previousBest,
                                slots: plays.penlights(total: Int(result.questions), answering: false),
                                longestStreak: plays.longestStreak, misses: plays.misses,
                                onReplay: { startSession() }, onClose: { dismiss() })
        } else if let q = question, let hint {
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
                ticket(q, hint)
                QuizStageChoiceGrid(choices: q.choices.map { QuizStageChoice(id: $0.songId, title: $0.title) },
                                    columns: 1,
                                    eliminated: Set(hint.eliminated.compactMap {
                                        q.choices.indices.contains(Int($0)) ? q.choices[Int($0)].songId : nil
                                    })) { choice in
                    pick(choice.id, q)
                }
                .padding(.top, 4)
            }
        } else {
            ImasEmptyState(systemImage: "list.number", title: "出題できる公演がありません")
        }
    }

    // MARK: - チケット

    private func ticket(_ q: SetlistQuizQuestion, _ hint: SetlistQuizHintState) -> some View {
        QuizTicket {
            QuizTicketTitleBlock(label: "SETLIST", question: "空欄に入る曲は？",
                                 value: Int(hint.currentValue), base: Int(hint.baseValue)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(q.eventName)
                        .font(QS.text(20, weight: .black))
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([q.showName, q.date.replacingOccurrences(of: "-", with: "."), q.venue]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(QS.text(12, weight: .bold)).foregroundStyle(QS.paperSub)
                        .lineLimit(2)
                }
            }
            setlist(q, hint)
                .padding(.horizontal, 18).padding(.bottom, 12)
            if hint.showPerformers && !q.performers.isEmpty {
                performers(q).padding(.horizontal, 18).padding(.bottom, 12)
            }
            if !hint.hints.isEmpty || !opened.isEmpty {
                QuizTicketNotch()
                QuizTicketHintTiles {
                    ForEach(tileKinds(q, hint), id: \.self) { kind in
                        if let option = hint.hints.first(where: { $0.kind == kind }) {
                            QuizTicketHintTile(title: hintTitle(kind),
                                               phase: .available(cost: Int(option.cost), action: { openHint(kind, q) }))
                        } else {
                            QuizTicketHintTile(title: hintTitle(kind), phase: .open(value: openedValue(kind, q)))
                        }
                    }
                }
            }
        }
    }

    /// 見せる範囲のセトリ。隠れている分は「… 前に N 曲」と畳む。
    private func setlist(_ q: SetlistQuizQuestion, _ hint: SetlistQuizHintState) -> some View {
        let from = Int(hint.visibleFrom), to = Int(hint.visibleTo)
        let visible = q.lines.indices.contains(from) && q.lines.indices.contains(to) ? Array(q.lines[from...to]) : []
        return VStack(alignment: .leading, spacing: 0) {
            if hint.hiddenBefore > 0 { hiddenRow("前に \(hint.hiddenBefore) 曲") }
            ForEach(Array(visible.enumerated()), id: \.element.number) { offset, line in
                let previous = offset + from > 0 ? q.lines[offset + from - 1].section : nil
                if let label = setlistSectionLabel(raw: line.section),
                   offset + from == 0 || setlistSectionLabel(raw: previous) != label {
                    Text(label).font(QS.mono(11)).tracking(1.2).foregroundStyle(QS.paperSub)
                        .padding(.top, 8).padding(.bottom, 2)
                }
                lineRow(line, reveal: hint.revealAnswer)
            }
            if hint.hiddenAfter > 0 { hiddenRow("後に \(hint.hiddenAfter) 曲") }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: hint.visibleFrom)
    }

    private func hiddenRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text("⋮").font(QS.text(16, weight: .black)).frame(width: 34, alignment: .leading)
            Text(text).font(QS.text(12, weight: .bold))
        }
        .foregroundStyle(QS.paperMuted)
        .frame(minHeight: 30)
    }

    @ViewBuilder
    private func lineRow(_ line: SetlistQuizLine, reveal: Bool) -> some View {
        HStack(spacing: 10) {
            Text(String(format: "M%02d", line.number))
                .font(QS.mono(12)).foregroundStyle(line.isBlank ? QS.stamp : QS.paperSub)
                .frame(width: 34, alignment: .leading)
            if line.isBlank {
                Text(reveal ? line.songTitle : "？？？")
                    .font(QS.text(16, weight: .black))
                    .foregroundStyle(reveal ? QS.paperInk : QS.stamp)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(QS.stamp, style: StrokeStyle(lineWidth: 2, dash: reveal ? [] : [5, 4])))
                    .accessibilityLabel(reveal ? line.songTitle : "空欄")
            } else {
                Text(line.songTitle)
                    .font(QS.text(15, weight: .bold)).foregroundStyle(QS.paperInk)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 34)
    }

    private func performers(_ q: SetlistQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("歌唱メンバー").font(QS.text(11, weight: .bold)).foregroundStyle(QS.paperSub)
            Text(q.performers.map(\.name).joined(separator: "、"))
                .font(QS.text(14, weight: .bold)).foregroundStyle(QS.paperInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                ForEach(Array(q.performers.prefix(16).enumerated()), id: \.offset) { i, p in
                    Capsule().fill(p.color.map { Color(hexString: $0, default: QS.penlight(i)) } ?? QS.penlight(i))
                        .frame(width: 8, height: 20)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QS.paperTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - ヒント

    /// タイルの並び (開いたものも同じ位置に残す)。
    private func tileKinds(_ q: SetlistQuizQuestion, _ hint: SetlistQuizHintState) -> [SetlistQuizHintKind] {
        let open = Set(opened)
        let offered = Set(hint.hints.map(\.kind))
        return [.wider, .performers, .fiftyFifty].filter { open.contains($0) || offered.contains($0) }
    }

    private func hintTitle(_ kind: SetlistQuizHintKind) -> String {
        switch kind {
        case .wider: "前後をもっと見る"
        case .performers: "歌唱メンバー"
        case .fiftyFifty: "2択にする"
        }
    }

    private func openedValue(_ kind: SetlistQuizHintKind, _ q: SetlistQuizQuestion) -> String {
        switch kind {
        case .wider: "全\(q.lines.count)曲"
        case .performers: "\(q.performers.count)人"
        case .fiftyFifty: "2曲に"
        }
    }

    private func openHint(_ kind: SetlistQuizHintKind, _ q: SetlistQuizQuestion) {
        AppAnalytics.tap("setlist_quiz.hint_\(String(describing: kind))")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            opened.append(kind)
            hint = setlistQuizHintState(question: q, opened: opened, answered: false)
        }
    }

    // MARK: - 進行

    private func pick(_ songId: String, _ q: SetlistQuizQuestion) {
        guard !answered else { return }
        AppAnalytics.tap("setlist_quiz.answer")
        answered = true
        scoreBefore = Int(tally.points)
        let outcome = setlistQuizAnswer(question: q, opened: opened, pickedSongId: songId, before: tally)
        isLastQuestion = outcome.isLastQuestion
        let picked = q.choices.first { $0.songId == songId }?.title
        let number = plays.count + 1
        let slot = q.lines.indices.contains(Int(q.blankIndex)) ? q.lines[Int(q.blankIndex)].number : 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            tally = outcome.tally
            hint = setlistQuizHintState(question: q, opened: opened, answered: true)
            plays.append(QuizStagePlay(number: number, isCorrect: outcome.isCorrect,
                                       answerName: q.answer.title, answerHex: nil,
                                       pickedName: outcome.isCorrect ? nil : picked))
            verdict = QuizVerdict(isCorrect: outcome.isCorrect, number: number,
                                  answerName: q.answer.title, answerHex: nil,
                                  earned: Int(outcome.earnedPoints), base: Int(hint?.baseValue ?? 0),
                                  hints: Int(outcome.revealedHints),
                                  pickedName: outcome.isCorrect ? nil : picked,
                                  detail: "\(q.eventName) \(q.showName) · M\(String(format: "%02d", slot))",
                                  artworkURL: q.answerArtworkUrl.flatMap { URL(string: $0) })
        }
        UINotificationFeedbackGenerator().notificationOccurred(outcome.isCorrect ? .success : .error)
        QuizResumeStore.shared.save(QuizSuspended(
            kind: .setlistQuiz, seed: seed, brandIds: Array(selectedBrandIds),
            nextIndex: index + 1, asked: Int(tally.asked), correct: Int(tally.correct),
            points: Int(tally.points), plays: plays, total: sessionLength, savedAt: .now))
    }

    private func nextQuestion() {
        index += 1
        startQuestion()
    }

    private func startQuestion() {
        opened = []
        answered = false
        verdict = nil
        hint = question.map { setlistQuizHintState(question: $0, opened: [], answered: false) }
    }

    private func finish() {
        let sessionResult = setlistQuizSessionResult(tally: tally)
        previousBest = GameProgressStore.shared.previousBestScore(for: .setlistQuiz)
        let update = GameProgressStore.shared.recordResult(
            .setlistQuiz, score: Int(sessionResult.points), outOf: Int(sessionResult.outOf))
        isNewBest = update.isNewBest
        QuizResumeStore.shared.clear(.setlistQuiz)
        let urls = questions.prefix(plays.count).compactMap(\.answerArtworkUrl).filter { !$0.isEmpty }
        shareArtwork = Task { await LyricsQuizShareArtwork.load(Array(Set(urls))) }
        verdict = nil
        result = sessionResult
    }

    private func shareResultImage(_ result: QuizSessionResult) {
        guard !isPreparingShare else { return }
        AppAnalytics.tap("setlist_quiz.share_image")
        isPreparingShare = true
        Task {
            let artworks = await shareArtwork?.value ?? [:]
            isPreparingShare = false
            QuizShareCard(title: "セトリ当て", result: result, rows: plays.shareRows,
                          longestStreak: plays.longestStreak, isNewBest: isNewBest,
                          artworks: Array(artworks.values))
                .share(text: QuizShareCard.text("セトリ当てクイズ", result))
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        await startSessionAsync()
        isLoading = false
    }

    private func startSession() {
        Task { await startSessionAsync() }
    }

    /// 1 ゲーム分の出題をコアに一括生成させる。つづきからは保存したシードで作り直す。
    private func startSessionAsync() async {
        let saved = didUseResume ? nil : resume
        didUseResume = true
        if let saved {
            seed = saved.seed
        } else {
            var generator = SystemRandomNumberGenerator()
            seed = generator.next()
            QuizResumeStore.shared.clear(.setlistQuiz)
        }
        questions = (try? await AppContainer.shared.setlistQuizReading.session(
            brandIds: Array(selectedBrandIds), seed: seed)) ?? []
        index = saved?.nextIndex ?? 0
        tally = saved?.tally ?? QuizTally(asked: 0, correct: 0, points: 0)
        plays = saved?.plays ?? []
        isLastQuestion = false
        result = nil
        isNewBest = false
        previousBest = nil
        startQuestion()
        if saved != nil && index >= questions.count && !questions.isEmpty { finish() }
    }
}
