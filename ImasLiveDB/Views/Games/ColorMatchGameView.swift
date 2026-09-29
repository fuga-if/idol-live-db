import SwiftUI

/// メンバーカラー合わせ。出題対象ブランドをトグルで選び、遊び方・難易度・問題数を決めて
/// 全N問のセッションを遊ぶ。遊び方は 2 つ:
/// - 4択: 名前を見て、その子のイメージカラーを 4 色から選ぶ (ヒントを開くほど点が下がる)。
/// - 並べる: 色チップをドラッグ&ドロップ(タップ割当も可)で複数人に紐づけ、
/// 判定で正誤＋正解色を表示。最後に正答率を出す。判定前は本人の色を見せない
/// (アバターは画像があれば画像・無ければ中立モノグラムで、色をネタバレしない)。
///
/// 出題母集団の決定 (外部演者・コラボ枠・色未設定の除外、色の一意化、ブランド 4 人閾値)、
/// 難易度ごとの出題の作り方、答え合わせ、正答率は imas-core の `domain/color_match.rs`
/// (4択は `domain/color_quiz.rs`) にあり、
/// Android と同じ実装を共有する。この画面が担うのは描画・ドラッグ操作・シード調達だけ。
struct ColorMatchGameView: View {
    /// 途中でやめたセッションの続き (ゲーム一覧の「つづきから」)。nil なら設定画面から。
    private let resume: QuizSuspended?

    init(resume: QuizSuspended? = nil) {
        self.resume = resume
    }

    @State private var imageService = CustomImageService.shared
    /// このセッションの出題シード (つづきからで同じ出題を作り直す)。
    @State private var seed: UInt64 = 0
    /// `resume` は最初の 1 回だけ使う (「もう一度」は新しいセッション)。
    @State private var didUseResume = false

    /// 画面ロード時に 1 回だけ組む母集団一式 (コア)。
    @State private var pools = ColorMatchPools(allColored: [], brandPools: [], selectableBrandIds: [])
    /// 名前・ニックネーム等の表示情報を引くための対応表 (コアは id と色しか返さない)。
    @State private var idolById: [String: Idol] = [:]
    @State private var brands: [Brand] = []

    // 設定
    @State private var selectedBrandIds: Set<String> = []
    /// 遊び方: 0=4択 / 1=並べる。
    @State private var playMode = 0
    private let playModeLabels = ["4択", "並べる"]
    private var isChoiceMode: Bool { playMode == 0 }
    /// 難度: 0=やさしい(色を散らす) / 1=ふつう(ランダム) / 2=むずい(最も近い色・人数増)。
    /// セグメントの index はコアの `ColorMatchDifficulty` の並びにそのまま対応する。
    @State private var difficulty = 1
    @State private var questionCount = 5
    private let levelLabels = ["やさしい", "ふつう", "むずい"]
    private let questionCountOptions = [5, 10]
    /// 「合わせる」が成立する最低人数。コアの `MIN_POOL_SIZE` (=2) と同値だが、
    /// 開始ボタンを塞ぐ判定は呼び出し側の責務なので定数だけここに置く。
    private let minimumPool = 2

    // セッション状態
    /// 選択ブランドから引いた出題母集団 (ブランドを切り替えた時だけ引き直す)。
    @State private var pool: [ColorMatchIdol] = []
    /// 1 ゲーム分の出題 (「はじめる」1 回でコアがまとめて生成)。
    @State private var rounds: [ColorMatchRound] = []
    @State private var inGame = false
    @State private var sessionDone = false
    @State private var roundIndex = 0          // 0-based
    @State private var totalCorrect = 0
    @State private var totalAnswered = 0

    // 1問の状態
    @State private var assignments: [String: String] = [:]
    @State private var selectedHex: String?
    @State private var dropTargetId: String?
    /// 答え合わせの結果 (nil = まだ判定していない)。行の正誤・正解色の表示文字列も含む。
    @State private var judgement: ColorMatchJudgement?
    @State private var isLoading = true
    /// 各問の記録 (全員当てたらペンライト点灯)。
    @State private var plays: [QuizStagePlay] = []
    @State private var sessionResult: QuizSessionResult?

    // 4択の状態
    /// 1 ゲーム分の 4 択 (「はじめる」1 回でコアがまとめて生成)。
    @State private var choiceQuestions: [ColorQuizQuestion] = []
    /// この問題で開いたヒント。
    @State private var choiceOpened: [ColorQuizHintKind] = []
    /// いまの獲得点・色の系統・2択で消した色・まだ開けるヒント (コアが算出)。
    @State private var choiceHint = ColorQuizHintState(currentValue: 0, baseValue: 0, familyLabel: nil,
                                                       eliminated: [], hints: [])
    @State private var choiceTally = QuizTally(asked: 0, correct: 0, points: 0)
    /// 直前の問題の判定 (解答後に出す大きなカード)。
    @State private var choiceVerdict: QuizVerdict?
    @State private var choiceScoreBefore = 0
    @State private var isNewBest = false
    @State private var previousBest: Int?
    @Environment(\.dismiss) private var dismiss

    /// 現在の問題 (出題メンバーと色チップの並び)。
    private var round: ColorMatchRound {
        rounds.indices.contains(roundIndex) ? rounds[roundIndex] : ColorMatchRound(members: [], palette: [])
    }

    private var judged: Bool { judgement != nil }

    var body: some View {
        Group {
            if inGame || sessionDone {
                stage
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.sp5) {
                        if isLoading {
                            ImasInlineLoading(tint: DS.sys)
                        } else {
                            setup
                        }
                    }
                    .padding(DS.sp5)
                }
                .background(DS.bg.ignoresSafeArea())
                .scrollContentBackground(.hidden)
                .navigationTitle("メンバーカラー合わせ")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await load() }
        // 母集団の引き直しはブランドを切り替えたときだけ (描画のたびには呼ばない)。
        .onChange(of: selectedBrandIds) { _, _ in refreshPool() }
        .trackScreen("color_match_game")
    }

    // MARK: - 設定画面

    private var setup: some View {
        VStack(alignment: .leading, spacing: DS.sp5) {
            Text("出題ブランドを選んで、似た色のメンバーの色を当てよう。")
                .font(.imasFootnote).foregroundStyle(DS.ink2)

            VStack(alignment: .leading, spacing: DS.sp2) {
                ImasSectionHeader(title: "遊び方", tight: true)
                ImasSegmented(labels: playModeLabels, selection: $playMode)
                Text(isChoiceMode ? "名前を見て、その子のイメージカラーを 4 色から選ぶ"
                                  : "何人かの名前に、色をドラッグで割り当てる")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
            }

            VStack(alignment: .leading, spacing: DS.sp2) {
                ImasSectionHeader(title: "難易度", tight: true)
                ImasSegmented(labels: levelLabels, selection: $difficulty)
            }

            VStack(alignment: .leading, spacing: DS.sp2) {
                ImasSectionHeader(title: "問題数", tight: true)
                ImasSegmented(labels: questionCountOptions.map { "\($0)問" },
                              selection: Binding(
                                get: { questionCountOptions.firstIndex(of: questionCount) ?? 0 },
                                set: { questionCount = questionCountOptions[$0] }))
            }

            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "出題ブランド", tight: true)
                Text("未選択なら全ブランドから出題")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
                brandGrid
            }

            let canStart = pool.count >= requiredPool
            primaryButton("はじめる（全\(questionCount)問）") { AppAnalytics.tap("color_match_game.start"); startSession() }
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.5)
        }
    }

    /// 他のクイズ (アイドル当て・ソロ曲) と共通の BrandIconCell 丸アイコングリッド。
    /// メンバーカラーチップを並べるとそれ自体が問題のヒント(版権キャラの色)になり得るため、
    /// 共通UIに揃えてヒント漏れも防ぐ。
    private var brandGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 10)]
        return LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
            BrandIconCell(
                brandId: nil, label: "全て", iconText: "全", color: nil,
                isSelected: selectedBrandIds.isEmpty
            ) {
                withAnimation(.easeInOut(duration: 0.15)) { selectedBrandIds = [] }
            }
            ForEach(brands) { brand in
                BrandIconCell(
                    brandId: brand.id, label: brand.shortName,
                    iconText: brand.iconText, color: brand.color,
                    isSelected: selectedBrandIds.contains(brand.id)
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if !selectedBrandIds.insert(brand.id).inserted {
                            selectedBrandIds.remove(brand.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - ゲーム (ステージ)

    private var header: QuizStageHeader {
        if let sessionResult { return .result(total: Int(sessionResult.questions)) }
        if isChoiceMode {
            return .question(current: min(plays.count + (choiceVerdict == nil ? 1 : 0), questionCount),
                             total: questionCount, points: Int(choiceTally.points))
        }
        return .question(current: min(plays.count + (judged ? 0 : 1), questionCount),
                         total: questionCount, points: totalCorrect)
    }

    private var stage: some View {
        QuizStageScaffold(title: "メンバーカラー", header: header,
                          onClose: { if sessionResult == nil { resetToSetup() } else { dismiss() } },
                          trailing: {
            if let sessionResult {
                QuizStageRoundButton(systemImage: "square.and.arrow.up", label: "結果を画像でシェア") {
                    AppAnalytics.tap("color_match_game.share_image")
                    QuizShareCard(title: "メンバーカラー合わせ",
                                  subtitle: "\(isChoiceMode ? "4択" : "並べる") · \(levelLabels[difficulty])",
                                  result: sessionResult, rows: plays.shareRows,
                                  longestStreak: plays.longestStreak, isNewBest: isNewBest)
                        .share(text: QuizShareCard.text("メンバーカラー合わせ", sessionResult))
                }
            }
        }) {
            if let sessionResult {
                QuizStageResultView(result: sessionResult, kind: .colorMatch, isNewBest: isNewBest,
                                    previousBest: previousBest,
                                    slots: plays.penlights(total: questionCount, answering: false),
                                    longestStreak: plays.longestStreak, misses: plays.misses,
                                    onReplay: { startSession() }, onClose: { dismiss() })
            } else if isChoiceMode {
                choiceStage
            } else {
                QuizStageProgress(slots: plays.penlights(total: questionCount, answering: !judged),
                                  caption: "全員当てると点灯 · \(levelLabels[difficulty])",
                                  streak: plays.streak, streakBrokeAt: plays.streakBrokeAt)
                    .padding(.bottom, 2)
                if let judgement { roundVerdict(judgement) }
                ticket
                if !judged { palette }
                footer.padding(.top, 4)
            }
        }
    }

    // MARK: - 4択

    private var choiceQuestion: ColorQuizQuestion? {
        choiceQuestions.indices.contains(roundIndex) ? choiceQuestions[roundIndex] : nil
    }

    @ViewBuilder
    private var choiceStage: some View {
        QuizStageProgress(slots: plays.penlights(total: questionCount, answering: choiceVerdict == nil),
                          caption: plays.setlistCaption(total: questionCount),
                          streak: plays.streak, streakBrokeAt: plays.streakBrokeAt)
            .padding(.bottom, 2)
        if let choiceVerdict {
            QuizVerdictCard(verdict: choiceVerdict).id(choiceVerdict.number)
            QuizVerdictStats(before: choiceScoreBefore, after: Int(choiceTally.points), streak: plays.streak)
            if !choiceVerdict.isCorrect { QuizVerdictFootnote() }
            QuizStageNextButton(isLastQuestion: roundIndex + 1 >= questionCount, onNext: advance, onFinish: advance)
                .padding(.top, 4)
        } else if let q = choiceQuestion {
            choiceTicket(q)
            choiceSwatches(q).padding(.top, 4)
        }
    }

    private func choiceTicket(_ q: ColorQuizQuestion) -> some View {
        let idol = idolById[q.answer.id]
        return QuizTicket {
            QuizTicketTitleBlock(label: "IMAGE COLOR", question: "この子のイメージカラーはどれ？",
                                 value: Int(choiceHint.currentValue), base: Int(choiceHint.baseValue)) {
                HStack(spacing: 14) {
                    ImasAvatar(label: idol?.shortName ?? "", seed: nil, size: 56,
                               imageURL: imageService.imageURL(for: q.answer.id))
                    VStack(alignment: .leading, spacing: 2) {
                        if isCrossBrand, let b = idol.flatMap({ brandShort($0.brandId) }) {
                            Text(b).font(QS.text(12, weight: .bold)).foregroundStyle(QS.paperSub)
                        }
                        Text(idol?.name ?? "")
                            .font(QS.text(34, weight: .black))
                            .lineLimit(2).minimumScaleFactor(0.5)
                    }
                }
                .padding(.top, 2)
            }
            QuizTicketNotch()
            QuizTicketHintTiles {
                if let family = choiceHint.familyLabel {
                    QuizTicketHintTile(title: "色の系統", phase: .open(value: family))
                }
                ForEach(choiceHint.hints, id: \.kind) { option in
                    QuizTicketHintTile(title: option.kind == .family ? "色の系統" : "2択にする",
                                       phase: .available(cost: Int(option.cost), action: { openChoiceHint(option.kind, q) }))
                }
                if choiceOpened.contains(.fiftyFifty) {
                    QuizTicketHintTile(title: "2択にする", phase: .open(value: "2色に"))
                }
            }
        }
    }

    /// 色の選択肢 (2×2)。2択ヒントで消した色は押せなくして薄くする。
    private func choiceSwatches(_ q: ColorQuizQuestion) -> some View {
        let letters = ["A", "B", "C", "D"]
        let out = Set(choiceHint.eliminated.map(Int.init))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            ForEach(Array(q.choices.enumerated()), id: \.offset) { i, hex in
                let isOut = out.contains(i)
                Button { pickChoice(hex, q) } label: {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hexString: hex))
                            .frame(height: 76)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(QS.line, lineWidth: 1))
                        HStack {
                            Text(letters[i % letters.count]).foregroundStyle(QS.faint)
                            Spacer(minLength: 2)
                            Text(hex.uppercased())
                        }
                        .font(QS.mono(11))
                        .foregroundStyle(QS.ink)
                        .padding(.horizontal, 4)
                    }
                    .padding(8)
                    .background(QS.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(QS.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(QuizPressStyle())
                .disabled(isOut)
                .opacity(isOut ? 0.18 : 1)
                .accessibilityLabel("色 \(letters[i % letters.count]) \(hex)")
            }
        }
    }

    private func openChoiceHint(_ kind: ColorQuizHintKind, _ q: ColorQuizQuestion) {
        AppAnalytics.tap(kind == .family ? "color_match_game.hint_family" : "color_match_game.hint_fifty")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            choiceOpened.append(kind)
            choiceHint = colorQuizHintState(question: q, opened: choiceOpened, answered: false)
        }
    }

    private func pickChoice(_ hex: String, _ q: ColorQuizQuestion) {
        guard choiceVerdict == nil else { return }
        AppAnalytics.tap("color_match_game.choose")
        choiceScoreBefore = Int(choiceTally.points)
        let outcome = colorQuizAnswer(question: q, opened: choiceOpened, pickedHex: hex,
                                      before: choiceTally, questionCount: UInt32(clamping: questionCount))
        let name = idolById[q.answer.id]?.name ?? ""
        let number = plays.count + 1
        let family = colorQuizHintState(question: q, opened: choiceOpened, answered: true).familyLabel
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            choiceTally = outcome.tally
            plays.append(QuizStagePlay(number: number, isCorrect: outcome.isCorrect,
                                       answerName: name, answerHex: q.answer.color,
                                       pickedName: outcome.isCorrect ? nil : hex.uppercased()))
            choiceVerdict = QuizVerdict(isCorrect: outcome.isCorrect, number: number,
                                        answerName: name, answerHex: q.answer.color,
                                        earned: Int(outcome.earnedPoints), base: Int(choiceHint.baseValue),
                                        hints: Int(outcome.revealedHints),
                                        pickedName: outcome.isCorrect ? nil : hex.uppercased(),
                                        detail: [q.answer.color?.uppercased(), family].compactMap { $0 }.joined(separator: " · "))
        }
        UINotificationFeedbackGenerator().notificationOccurred(outcome.isCorrect ? .success : .error)
        QuizResumeStore.shared.save(QuizSuspended(
            kind: .colorMatch, seed: seed, brandIds: Array(selectedBrandIds),
            nextIndex: roundIndex + 1, asked: Int(choiceTally.asked), correct: Int(choiceTally.correct),
            points: Int(choiceTally.points), plays: plays, total: questionCount,
            difficulty: difficulty, colorMode: "choice", savedAt: .now))
    }

    /// 答え合わせの一枚。全員当てたら生成りのカード、外したら暗いカード。
    private func roundVerdict(_ j: ColorMatchJudgement) -> some View {
        let cleared = j.score == j.outOf
        return HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Q.%02d — ", roundIndex + 1) + (cleared ? "PERFECT" : "RESULT"))
                    .font(QS.mono(12)).tracking(1.4)
                Text(cleared ? "全員正解！" : "\(j.score) / \(j.outOf) 正解")
                    .font(QS.text(cleared ? 40 : 34, weight: .black))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            Text("+\(j.score)").font(QS.num(64, weight: .black))
        }
        .foregroundStyle(cleared ? QS.paperInk : QS.ink)
        .padding(.horizontal, 22).padding(.vertical, 18)
        .background(cleared ? QS.paper : QS.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(cleared ? Color.clear : QS.line, lineWidth: 1))
        .transition(.scale(scale: 0.94).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    private var ticket: some View {
        QuizTicket {
            QuizTicketHeading(label: "IMAGE COLOR",
                              question: judged ? "答え合わせ" : "だれのイメージカラー？")
            Text(judged ? "丸の中が選んだ色、名前の下が本人の色" : "色をドラッグ、またはタップで割り当て")
                .font(QS.text(12, weight: .bold)).foregroundStyle(QS.paperSub)
                .padding(.horizontal, 18).padding(.bottom, 8)
            QuizTicketNotch()
            ForEach(Array(round.members.enumerated()), id: \.element.id) { idx, member in
                memberRow(member, at: idx)
            }
            Color.clear.frame(height: 6)
        }
    }

    /// 色チップ。色見本 + 記号 + HEX。ドラッグでもタップ選択でも割り当てられる。
    private var palette: some View {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Array(round.palette.enumerated()), id: \.element) { i, hex in
                let used = assignments.values.contains(hex)
                let selected = selectedHex == hex
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hexString: hex))
                        .frame(height: 56)
                        .overlay {
                            if used {
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(ColorMath.onColor(Color(hexString: hex)))
                            }
                        }
                    HStack {
                        Text(letters[i % letters.count]).foregroundStyle(QS.faint)
                        Spacer(minLength: 2)
                        Text(hex.uppercased())
                    }
                    .font(QS.mono(10))
                    .foregroundStyle(QS.ink)
                    .padding(.horizontal, 2)
                }
                .padding(6)
                .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? QS.ink : QS.line, lineWidth: selected ? 2.5 : 1))
                .opacity(used && !selected ? 0.45 : 1)
                .scaleEffect(selected ? 1.03 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
                .draggable(hex) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hexString: hex)).frame(width: 64, height: 44)
                }
                .onTapGesture { selectedHex = selected ? nil : hex }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("色 \(letters[i % letters.count]) \(hex)")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    @ViewBuilder
    private func memberRow(_ member: ColorMatchIdol, at position: Int) -> some View {
        let idol = idolById[member.id]
        let assigned = assignments[member.id]
        // 行の正誤はコアの答え合わせ結果をそのまま使う (画面側で色を比べ直さない)。
        let correct = judgement.map { $0.correct.indices.contains(position) && $0.correct[position] } ?? false
        let isTarget = dropTargetId == member.id
        HStack(spacing: 12) {
            // アイドル本人 (色はネタバレしないよう中立アバター: 画像があれば画像)
            ImasAvatar(label: idol?.shortName ?? "", seed: nil, size: 40,
                       imageURL: imageService.imageURL(for: member.id))
            VStack(alignment: .leading, spacing: 1) {
                if isCrossBrand, let b = idol.flatMap({ brandShort($0.brandId) }) {
                    Text(b).font(QS.text(11, weight: .bold)).foregroundStyle(QS.paperSub)
                }
                Text(idol?.name ?? "").font(QS.text(17, weight: .black)).lineLimit(1).minimumScaleFactor(0.7)
                if let judgement, judgement.correctHexLabels.indices.contains(position) {
                    // 答え合わせでは本人のメンバーカラーを色見本 + HEX コードで明示する。
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hexString: member.color)).frame(width: 28, height: 12)
                        Text(judgement.correctHexLabels[position]).font(QS.mono(11)).foregroundStyle(QS.paperSub)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 6)
            // 割り当てた色スロット (ドロップ/タップ対象)
            ZStack {
                if let assigned {
                    Circle().fill(Color(hexString: assigned))
                } else {
                    Circle().strokeBorder(isTarget ? QS.paperInk : QS.paperMuted,
                                          style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    Text("?").font(QS.num(18)).foregroundStyle(QS.paperSub)
                }
            }
            .frame(width: 44, height: 44)
            .overlay {
                if judged {
                    Image(systemName: correct ? "checkmark" : "xmark")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(assigned.map { ColorMath.onColor(Color(hexString: $0)) } ?? QS.paperInk)
                }
            }
            .scaleEffect(isTarget ? 1.12 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTarget)
        }
        .foregroundStyle(QS.paperInk)
        .padding(.horizontal, 18).padding(.vertical, 8)
        .frame(minHeight: 60)
        .background(isTarget ? QS.paperHighlight : Color.clear)
        .overlay(alignment: .top) {
            if position > 0 { Rectangle().fill(QS.paperLine).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard !judged, let hex = items.first else { return false }
            assign(hex, to: member.id); return true
        } isTargeted: { hovering in
            dropTargetId = hovering ? member.id : (dropTargetId == member.id ? nil : dropTargetId)
        }
        .onTapGesture {
            guard !judged else { return }
            if let sel = selectedHex { assign(sel, to: member.id); selectedHex = nil }
            else if assignments[member.id] != nil { assignments[member.id] = nil }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if judged {
            QuizStageNextButton(isLastQuestion: roundIndex + 1 >= questionCount,
                                onNext: advance, onFinish: advance)
        } else {
            let ready = assignments.count == round.members.count
            QuizStagePrimaryButton(title: ready ? "判定する" : "あと \(round.members.count - assignments.count) 人") {
                AppAnalytics.tap("color_match_game.judge"); judge()
            }
            .disabled(!ready)
            .opacity(ready ? 1 : 0.45)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.imasHeadline.weight(.semibold)).foregroundStyle(DS.onSys)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(DS.sys, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: - Logic

    /// セグメントの index → コアの難易度 (並びは `ColorMatchDifficulty` と同順)。
    private var coreDifficulty: ColorMatchDifficulty {
        switch difficulty {
        case 0:  return .easy
        case 2:  return .hard
        default: return .normal
        }
    }

    /// 開始に要る最低人数 (4択は 4 色並べるので 4 人、並べるは 2 人)。
    private var requiredPool: Int { isChoiceMode ? 4 : minimumPool }

    /// ブランドが複数混ざるときだけ行にブランド名を添える (誰の色か絞りにくくなるため)。
    private var isCrossBrand: Bool { selectedBrandIds.count != 1 }

    private func brandShort(_ id: String) -> String? {
        // 出題母集団に載っているブランド (メンバー 4 人以上) だけ名前を添える。
        // 一覧に出るだけのブランドまで名乗らせない原本の挙動を保つ。
        guard pools.brandPools.contains(where: { $0.brandId == id }) else { return nil }
        return brands.first { $0.id == id }?.shortName
    }

    /// 選択ブランド → 出題母集団 (未選択は全ブランド)。色の一意化はコア側。
    private func refreshPool() {
        pool = colorMatchEffectivePool(pools: pools, selectedBrandIds: Array(selectedBrandIds))
    }

    /// 「はじめる」1 回で全問まとめて生成する (問題ごとに FFI を呼ばない)。
    private func startSession() {
        // つづきからは保存した設定とシードで同じ出題を作り直し、答えた問題の次から始める。
        let saved = didUseResume ? nil : resume
        didUseResume = true
        if let saved {
            playMode = saved.colorMode == "choice" ? 0 : 1
            difficulty = saved.difficulty ?? difficulty
            questionCount = saved.total
            selectedBrandIds = Set(saved.brandIds)
            refreshPool()
            seed = saved.seed
        } else {
            var generator = SystemRandomNumberGenerator()
            seed = generator.next()
            QuizResumeStore.shared.clear(.colorMatch)
        }
        guard pool.count >= requiredPool else { return }
        if isChoiceMode {
            choiceQuestions = colorQuizStartGame(pool: pool, difficulty: coreDifficulty,
                                                 questionCount: UInt32(clamping: questionCount), seed: seed)
            rounds = []
            choiceTally = saved?.tally ?? QuizTally(asked: 0, correct: 0, points: 0)
        } else {
            rounds = colorMatchStartGame(pool: pool, difficulty: coreDifficulty,
                                         questionCount: UInt32(clamping: questionCount),
                                         seed: seed)
            choiceQuestions = []
        }
        roundIndex = saved?.nextIndex ?? 0
        totalCorrect = saved?.correct ?? 0
        totalAnswered = saved?.asked ?? 0
        plays = saved?.plays ?? []; sessionResult = nil; isNewBest = false; previousBest = nil
        sessionDone = false; inGame = true
        startRound()
        // 最後の問題まで答えてから閉じていたら、そのまま結果へ。
        if saved != nil && roundIndex >= questionCount { finishSession() }
    }

    private func resetToSetup() {
        inGame = false; sessionDone = false; sessionResult = nil
    }

    /// 1 問の答え合わせ。行の正誤・正解数・正解色の表示文字列はコアが一括で返す。
    private func judge() {
        let result = colorMatchJudgeRound(
            members: round.members,
            assignments: assignments.map { ColorMatchAssignment(idolId: $0.key, hex: $0.value) })
        // 外したメンバーを「見直す」に並べる (全員当てた問題は並べない)。
        let missed = round.members.indices
            .filter { !(result.correct.indices.contains($0) && result.correct[$0]) }
            .map { round.members[$0] }
        let cleared = result.score == result.outOf
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            judgement = result
            totalCorrect += Int(result.score)
            totalAnswered += Int(result.outOf)
            plays.append(QuizStagePlay(
                number: roundIndex + 1, isCorrect: cleared,
                answerName: (cleared ? round.members : missed).compactMap { idolById[$0.id]?.name }.joined(separator: "、"),
                answerHex: (cleared ? round.members.first : missed.first)?.color,
                pickedName: nil))
        }
        UINotificationFeedbackGenerator().notificationOccurred(cleared ? .success : .warning)
        // 1 問答えるたびに途中経過を残す (× で閉じても「つづきから」で戻れる)。
        QuizResumeStore.shared.save(QuizSuspended(
            kind: .colorMatch, seed: seed, brandIds: Array(selectedBrandIds),
            nextIndex: roundIndex + 1, asked: totalAnswered, correct: totalCorrect,
            points: totalCorrect, plays: plays, total: questionCount,
            difficulty: difficulty, colorMode: "match", savedAt: .now))
    }

    private func advance() {
        if roundIndex + 1 < questionCount {
            roundIndex += 1
            startRound()
        } else {
            finishSession()
        }
    }

    private func finishSession() {
        QuizResumeStore.shared.clear(.colorMatch)
        previousBest = GameProgressStore.shared.previousBestScore(for: .colorMatch)
        // 4択はヒント込みの点 / 満点、並べるは当てた人数 / 出題人数を記録する。
        let update = isChoiceMode
            ? GameProgressStore.shared.recordResult(
                .colorMatch, score: Int(choiceTally.points),
                outOf: Int(colorQuizSessionResult(tally: choiceTally, questionCount: UInt32(clamping: questionCount)).outOf))
            : GameProgressStore.shared.recordResult(.colorMatch, score: totalCorrect, outOf: totalAnswered)
        isNewBest = update.isNewBest
        if isChoiceMode {
            sessionResult = colorQuizSessionResult(tally: choiceTally, questionCount: UInt32(clamping: questionCount))
            choiceVerdict = nil
            sessionDone = true
            return
        }
        // 点 = 色を当てた人数、「n / N 正解」= 全員当てた問題数。グレードの閾値はコア。
        sessionResult = quizAccuracyResult(
            points: UInt32(clamping: totalCorrect), outOf: UInt32(clamping: totalAnswered),
            correct: UInt32(clamping: plays.filter(\.isCorrect).count),
            questions: UInt32(clamping: questionCount))
        judgement = nil
        sessionDone = true
    }

    /// 1 問ぶんの解答状態を戻す (出題自体は `startSession` で生成済み)。
    private func startRound() {
        judgement = nil; assignments = [:]; selectedHex = nil; dropTargetId = nil
        choiceVerdict = nil; choiceOpened = []
        if let q = choiceQuestion {
            choiceHint = colorQuizHintState(question: q, opened: [], answered: false)
        }
    }

    private func assign(_ hex: String, to idolId: String) {
        for (k, v) in assignments where v == hex && k != idolId { assignments[k] = nil }
        assignments[idolId] = hex
        dropTargetId = nil
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
        let allBrands = (try? await AppContainer.shared.brandReading.brands()) ?? []
        idolById = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // 除外 ('other' やコラボ枠・外部演者・色未設定)、色の一意化、ブランドごとの
        // 出題可否 (4 人以上) はコアがまとめて判断する。
        pools = colorMatchBuildPools(
            idols: all.map {
                ColorMatchIdolSource(id: $0.id, brandId: $0.brandId, color: $0.color,
                                     isExternal: $0.isExternal, sortOrder: Int32(clamping: $0.sortOrder))
            },
            brands: allBrands.map { ColorMatchBrandRef(id: $0.id, sortOrder: Int32(clamping: $0.sortOrder)) })
        // 出題ブランド選択に並べるのはコアが選抜したブランド ('other' 等は出さない)。
        let selectable = Set(pools.selectableBrandIds)
        brands = allBrands.filter { selectable.contains($0.id) }
        refreshPool()
        if resume != nil && !didUseResume { startSession() }
    }
}
