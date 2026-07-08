import SwiftUI

/// アイドル当てクイズ。最初はシルエット＋曖昧なプロフィール1項目だけで出題し、
/// 並んだヒントの属性をユーザがどれから開けるか選ぶ (戦略性)。
/// 素点は 10pt で、ヒントを 1 つ開くごとに獲得点が下がる (CV/メンバーカラーは -2pt)。
/// CV枠は常設し、声優未発表キャラは開封して初めて「声優未発表」と分かる
/// (CV枠の有無で不在が無料でバレないようにする)。全 sessionLength 問のセッション制。
struct IdolQuizView: View {
    @Environment(AppDatabase.self) private var database

    /// 出題ブランド絞り込み（空集合 = 全ブランド対象）。IdolQuizSetupView から渡す。
    let selectedBrandIds: Set<String>

    init(selectedBrandIds: Set<String> = []) {
        self.selectedBrandIds = selectedBrandIds
    }

    private let sessionLength = 10
    /// ノーヒント正解の素点。
    private let basePoints = 10

    @State private var pool: [Idol] = []
    @State private var question: Question?
    @State private var selectedId: String?
    @State private var opened: Set<Int> = []   // 開いたヒントの facts インデックス (1...)
    @State private var points = 0              // 累計獲得ポイント (加点式・上昇のみ)
    @State private var correct = 0             // 正解数
    @State private var asked = 0               // 解答済み問題数
    @State private var seenIds: Set<String> = []   // セッション中に出題済みアイドル (重複出題防止)
    @State private var history: [QuizHistoryItem] = []  // 各問の振り返り (リザルトに渡す)
    @State private var sessionDone = false
    @State private var isNewBest = false
    @State private var isLoading = true

    private struct Question {
        let answer: Idol
        let choices: [Idol]
        /// 出題に使う事実。先頭 (facts[0]) が無料公開、以降がヒントとして任意順で開ける。
        /// (IdolQuizSetupView の見積りとも共有する `idolQuizFacts(for:)` が返す型)
        let facts: [IdolQuizFact]
    }

    /// 現在この問題に正解した場合の獲得点 (素点 − 開いたヒントのコスト合計、最低 1pt)。
    private func currentValue(_ q: Question) -> Int {
        let cost = opened.reduce(0) { $0 + (q.facts.indices.contains($1) ? q.facts[$1].cost : 0) }
        return max(1, basePoints - cost)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                if isLoading {
                    ProgressView().tint(DS.sys).frame(maxWidth: .infinity).padding(.top, DS.sp9)
                } else if sessionDone {
                    QuizResultView(points: points, maxPoints: sessionLength * basePoints,
                                   correct: correct, questions: asked,
                                   kind: .idolQuiz, isNewBest: isNewBest,
                                   history: history,
                                   onReplay: { restart() })
                } else if let q = question {
                    QuizProgressHeader(current: min(asked + (selectedId != nil ? 0 : 1), sessionLength),
                                       total: sessionLength, points: points)
                    promptCard(q)
                    if selectedId == nil { hintList(q) }
                    IdolChoiceGrid(choices: q.choices, answer: q.answer, selectedId: selectedId, onPick: pick)
                    if selectedId != nil {
                        QuizNextButton(isLastQuestion: asked >= sessionLength, onNext: nextQuestion, onFinish: finish)
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

    private func promptCard(_ q: Question) -> some View {
        let answered = selectedId != nil
        // 公開する事実 = 無料 facts[0] + 開いたヒント。解答後は全部見せる。
        let shownIndices: [Int] = answered ? Array(q.facts.indices) : ([0] + opened.sorted())
        return VStack(alignment: .leading, spacing: DS.sp4) {
            HStack(spacing: DS.sp4) {
                silhouette(q.answer, revealed: answered)
                VStack(alignment: .leading, spacing: 4) {
                    Text("このプロフィールは誰？").font(.imasHeadline.weight(.bold)).foregroundStyle(DS.ink)
                    if answered {
                        Text(q.answer.name).font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                    } else {
                        valueBadge(q)
                    }
                }
                Spacer(minLength: 0)
            }
            ImasListContainer {
                ForEach(Array(shownIndices.enumerated()), id: \.element) { pos, idx in
                    if pos > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
                    let f = q.facts[idx]
                    HStack {
                        Text(f.label).font(.imasSubhead).foregroundStyle(DS.ink2)
                        Spacer(minLength: 12)
                        if f.label == "メンバーカラー" {
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

    /// 正解で獲得できるポイントを示すバッジ (加点表現で統一)。
    private func valueBadge(_ q: Question) -> some View {
        let pts = currentValue(q)
        return HStack(spacing: 5) {
            Image(systemName: "plus.circle.fill").font(.imasScaled( 11, weight: .bold))
            Text("正解で +\(pts)pt").font(.imasCaption.weight(.bold))
        }
        .foregroundStyle(DS.success)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(DS.success.opacity(0.14), in: Capsule())
    }

    /// メンバーカラーのヒントは色そのものが答えなので、HEX 文字列ではなく色チップで見せる。
    private func colorSwatch(_ hex: String) -> some View {
        HStack(spacing: 8) {
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
    /// CV枠は常設 (facts() 側で「声優未発表」も含めてスロット化済) なので、CV ラベルの
    /// 有無で声優未発表キャラの正体がバレることはない。
    private func hintList(_ q: Question) -> some View {
        let remaining = (1..<q.facts.count).filter { !opened.contains($0) }
        return VStack(spacing: DS.sp3) {
            ForEach(remaining, id: \.self) { idx in
                let f = q.facts[idx]
                let nextValue = max(1, currentValue(q) - f.cost)
                IdolHintRow(label: f.label, nextValue: nextValue) {
                    AppAnalytics.tap("idol_quiz.hint")
                    withAnimation(.easeInOut(duration: 0.2)) { _ = opened.insert(idx) }
                }
            }
        }
    }

    // MARK: - 進行

    private func pick(_ idol: Idol, isCorrect: Bool) {
        guard selectedId == nil, let q = question else { return }
        AppAnalytics.tap("idol_quiz.answer")
        selectedId = idol.id
        asked += 1
        let earned = isCorrect ? currentValue(q) : 0
        if isCorrect {
            correct += 1
            points += earned
        }
        // 振り返り用に1問の記録を残す。題材はアバター無しの抽象 (シルエット出題なので)、
        // 補助情報として「ブランド」を出すと一覧が読みやすい。
        history.append(QuizHistoryItem(
            id: "\(asked)-\(q.answer.id)",
            index: asked,
            subjectTitle: "プロフィール問題",
            subjectSubtitle: q.facts.first.map { "\($0.label): \($0.value)" },
            answer: q.answer,
            picked: idol,
            earnedPoints: earned,
            revealedHints: opened.count
        ))
    }

    private func nextQuestion() {
        selectedId = nil
        opened = []
        question = makeQuestion()
    }

    private func restart() {
        points = 0; correct = 0; asked = 0
        sessionDone = false; selectedId = nil; opened = []; isNewBest = false
        seenIds = []; history = []
        question = makeQuestion()
    }

    private func finish() {
        let outOf = asked * basePoints
        // recordResult が best を上書きする前に「更新したか」を判定する。
        let before = GameProgressStore.shared.record(for: .idolQuiz)
        let beforeRate = before.bestOutOf > 0 ? Double(before.bestScore) / Double(before.bestOutOf) : -1
        let newRate = outOf > 0 ? Double(points) / Double(outOf) : 0
        isNewBest = before.hasPlayed && newRate > beforeRate
        sessionDone = true
        GameProgressStore.shared.recordResult(.idolQuiz, score: points, outOf: outOf)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
        // IdolQuizSetupView.estimatePool() と同じ isIdolQuizEligible(_:selectedBrandIds:) を共有。
        // ここだけ別条件になると、見積りでは開始可能なのに実際は候補不足という
        // ズレが起きる (以前の facts>=3 チェック漏れがまさにそれだった)。
        pool = all.filter { isIdolQuizEligible($0, selectedBrandIds: selectedBrandIds) }
        question = makeQuestion()
    }

    /// プロフィール事実。IdolQuizSetupView とも共有する `idolQuizFacts(for:)` (QuizComponents.swift) に委譲。
    private func facts(for idol: Idol) -> [IdolQuizFact] {
        idolQuizFacts(for: idol)
    }

    private func makeQuestion() -> Question? {
        guard pool.count >= 4 else { return nil }
        // 既出を除外。母数が尽きたら一巡してリセット (短いセッション中の重複は防げる)。
        var candidates = pool.filter { !seenIds.contains($0.id) }
        if candidates.count < 1 {
            seenIds = []
            candidates = pool
        }
        guard let answer = candidates.randomElement() else { return nil }
        seenIds.insert(answer.id)
        let choices = (quizDistractors(from: pool, answer: answer) + [answer]).shuffled()
        return Question(answer: answer, choices: choices, facts: facts(for: answer))
    }
}

/// アイドル当てクイズ専用のヒント行。属性ラベルを見せ、どれを開くかユーザが選べる戦略性を残す。
/// CV枠は facts() で常設しているため、CV ラベルが並んでも声優未発表キャラの正体は漏れない。
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
                    .background(DS.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
