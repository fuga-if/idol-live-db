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
    @Environment(AppDatabase.self) private var database

    /// 出題ブランド絞り込み（空集合 = 全ブランド対象）。IdolQuizSetupView から渡す。
    let selectedBrandIds: Set<String>

    init(selectedBrandIds: Set<String> = []) {
        self.selectedBrandIds = selectedBrandIds
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
    /// 解答済み問題数・正解数・累計ポイント (コアが積み上げる)。
    @State private var tally = QuizTally(asked: 0, correct: 0, points: 0)
    @State private var isLastQuestion = false
    @State private var history: [QuizHistoryItem] = []  // 各問の振り返り (リザルトに渡す)
    @State private var result: QuizSessionResult?
    @State private var isNewBest = false
    @State private var isLoading = true

    private var question: IdolQuizQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                if isLoading {
                    ImasInlineLoading(tint: DS.sys)
                } else if let result {
                    QuizResultView(result: result,
                                   kind: .idolQuiz, isNewBest: isNewBest,
                                   history: history,
                                   onReplay: { restart() })
                } else if let q = question {
                    QuizProgressHeader(current: min(Int(tally.asked) + (selectedId != nil ? 0 : 1), sessionLength),
                                       total: sessionLength, points: Int(tally.points))
                    promptCard(q)
                    if selectedId == nil { hintList() }
                    IdolChoiceGrid(choices: choices(q), answer: idols[Int(q.answer)],
                                   selectedId: selectedId, onPick: pick)
                    if selectedId != nil {
                        QuizNextButton(isLastQuestion: isLastQuestion, onNext: nextQuestion, onFinish: finish)
                    }
                } else {
                    ImasEmptyState(systemImage: "person.fill.questionmark", title: "出題できる候補が不足しています")
                }
            }
            .padding(DS.sp5)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("アイドル当てクイズ")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .trackScreen("idol_quiz")
    }

    // MARK: - 出題カード (シルエット + 公開済みプロフィール)

    private func promptCard(_ q: IdolQuizQuestion) -> some View {
        let answered = selectedId != nil
        let answer = idols[Int(q.answer)]
        return VStack(alignment: .leading, spacing: DS.sp4) {
            HStack(spacing: DS.sp4) {
                silhouette(answer, revealed: answered)
                VStack(alignment: .leading, spacing: DS.sp2) {
                    Text("このプロフィールは誰？").font(.imasHeadline.weight(.bold)).foregroundStyle(DS.ink)
                    if answered {
                        Text(answer.name).font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                    } else {
                        // 公開する事実 (無料 facts[0] + 開いたヒント) と獲得点はコアの開示状態から。
                        QuizValueBadge(value: Int(hint.currentValue))
                    }
                }
                Spacer(minLength: 0)
            }
            ImasListContainer {
                ForEach(Array(hint.shownFactIndices.enumerated()), id: \.element) { pos, idx in
                    if pos > 0 { ImasRowDivider(inset: DS.sp5) }
                    let f = q.facts[Int(idx)]
                    HStack {
                        Text(f.label).font(.imasSubhead).foregroundStyle(DS.ink2)
                        Spacer(minLength: 12)
                        // 色そのものが答えになる項目だけ色チップで見せる (文言ではなく種別で分岐)。
                        if f.kind == .memberColor {
                            colorSwatch(f.value)
                        } else {
                            Text(f.value).font(.imasSubhead.weight(.medium)).foregroundStyle(DS.ink)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(.horizontal, DS.sp5).padding(.vertical, 11)
                    .background(DS.surface)
                }
            }
        }
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    /// メンバーカラーのヒントは色そのものが答えなので、HEX 文字列ではなく色チップで見せる。
    private func colorSwatch(_ hex: String) -> some View {
        HStack(spacing: DS.sp3) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hexString: hex))
                .frame(width: 28, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DS.sep, lineWidth: 1))
            Text(hex.uppercased()).font(.imasSubhead.weight(.medium).monospaced()).foregroundStyle(DS.ink)
        }
    }

    /// 解答前はテーマ色のシルエット、解答後は本人アバター。版権上キャラ絵は使わずモノグラム/カスタム画像のみ。
    @ViewBuilder
    private func silhouette(_ idol: Idol, revealed: Bool) -> some View {
        if revealed {
            IdolAvatarView(idol: idol, size: 56)
        } else {
            // メンバーカラーは有料ヒントなので、シルエットのリングに色を漏らさず中立色で描く。
            ZStack {
                Circle().fill(DS.fill)
                Image(systemName: "person.fill")
                    .font(.imasScaled( 30, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .frame(width: 56, height: 56)
            .overlay(Circle().strokeBorder(DS.sep, lineWidth: 1.5))
        }
    }

    // MARK: - ヒント

    /// 未公開の事実を一覧で並べ、どのヒントを開くかユーザが選べるようにする (戦略性)。
    /// 並ぶ候補と開封後の獲得点はコアの開示状態がそのまま持っている。CV枠は常設
    /// (コアの facts が「声優未発表」も含めてスロット化済) なので、CV ラベルの
    /// 有無で声優未発表キャラの正体がバレることはない。
    private func hintList() -> some View {
        VStack(spacing: DS.sp3) {
            ForEach(hint.hints, id: \.factIndex) { option in
                IdolHintRow(label: option.label, nextValue: Int(option.nextValue)) {
                    AppAnalytics.tap("idol_quiz.hint")
                    withAnimation(.easeInOut(duration: 0.2)) {
                        opened.append(option.factIndex)
                        refreshHint()
                    }
                }
            }
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
        // 正誤判定・獲得点・積み上げはコアがまとめて返す (加点式なので不正解でも減点しない)。
        let outcome = idolQuizAnswer(facts: q.facts, openedFactIndices: opened,
                                     pickedIdolId: idol.id, answerIdolId: answer.id, before: tally)
        tally = outcome.tally
        isLastQuestion = outcome.isLastQuestion
        refreshHint()
        // 振り返り用に1問の記録を残す。題材はアバター無しの抽象 (シルエット出題なので)、
        // 補助情報として無料公開ぶんの事実を出すと一覧が読みやすい。
        history.append(QuizHistoryItem(
            id: "\(tally.asked)-\(answer.id)",
            index: Int(tally.asked),
            subjectTitle: "プロフィール問題",
            subjectSubtitle: q.facts.first.map { "\($0.label): \($0.value)" },
            answer: answer,
            picked: idol,
            earnedPoints: Int(outcome.earnedPoints),
            revealedHints: Int(outcome.revealedHints)
        ))
    }

    private func nextQuestion() {
        selectedId = nil
        opened = []
        index += 1
        refreshHint()
    }

    private func restart() {
        startSession()
    }

    private func finish() {
        let sessionResult = idolQuizSessionResult(tally: tally)
        // 保存と「自己ベスト更新！」の判定は進捗ストア (コアの game_progress) が 1 回で返す。
        let update = GameProgressStore.shared.recordResult(
            .idolQuiz, score: Int(sessionResult.points), outOf: Int(sessionResult.outOf))
        isNewBest = update.isNewBest
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
        var generator = SystemRandomNumberGenerator()
        questions = idolQuizSession(idols: idolQuizRefs(idols),
                                    selectedBrandIds: Array(selectedBrandIds),
                                    seed: generator.next())
        index = 0
        selectedId = nil
        opened = []
        tally = QuizTally(asked: 0, correct: 0, points: 0)
        isLastQuestion = false
        history = []
        result = nil
        isNewBest = false
        refreshHint()
    }

    /// 開示範囲と残りヒントを引き直す (出題が変わった / ヒントを開いた / 解答した とき)。
    private func refreshHint() {
        hint = idolQuizHintState(facts: question?.facts ?? [],
                                 openedFactIndices: opened,
                                 answered: selectedId != nil)
    }
}

/// アイドル当てクイズ専用のヒント行。属性ラベルを見せ、どれを開くかユーザが選べる戦略性を残す。
/// CV枠はコアの facts で常設しているため、CV ラベルが並んでも声優未発表キャラの正体は漏れない。
private struct IdolHintRow: View {
    let label: String
    let nextValue: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.sp3) {
                Image(systemName: "lightbulb.fill")
                    .font(.imasScaled( 16, weight: .semibold)).foregroundStyle(DS.warning)
                    .frame(width: 34, height: 34)
                    .background(DS.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("ヒント: \(label)を見る").font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                    Text("開いた後は正解で +\(nextValue)pt").font(.imasCaption).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.imasScaled( 13, weight: .semibold)).foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp4).padding(.vertical, DS.sp3)
            .frame(maxWidth: .infinity)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
                .strokeBorder(DS.warning.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
