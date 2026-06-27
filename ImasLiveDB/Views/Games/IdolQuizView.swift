import SwiftUI

/// アイドル当てクイズ。最初はシルエット＋曖昧なプロフィール1項目だけで出題し、
/// 並んだ「？」スロットからヒントを好きな順で開ける。ヒントを開くほど正解時の獲得点は
/// 少なくなる (素点 10pt から最低 1pt)。CV はスロット内容を伏せて常設し、開封すると
/// 「声優未発表」も含めて見えるようにすることで、声優の有無が無料でバレないようにする。
/// 全 sessionLength 問のセッション制。データは Idol マスタの数値/テキストのプロフィール事実のみ。
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
    @State private var sessionDone = false
    @State private var isNewBest = false
    @State private var isLoading = true

    private struct Fact {
        let label: String
        let value: String
        /// 開いたときに下がる点数。CV のように一気にバレる項目は重く。
        let cost: Int
    }

    private struct Question {
        let answer: Idol
        let choices: [Idol]
        /// 出題に使う事実。先頭 (facts[0]) が無料公開、以降がヒントとして任意順で開ける。
        let facts: [Fact]
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

    /// 未公開の事実を「？」スロットで並べる。中身は開くまで分からない
    /// (どの属性枠が在る/無いかで CV未発表などが無料でバレるのを防ぐ)。
    /// 開封後の獲得点だけは見せて加点表現で誘導する。
    private func hintList(_ q: Question) -> some View {
        let remaining = (1..<q.facts.count).filter { !opened.contains($0) }
        return VStack(spacing: DS.sp3) {
            ForEach(Array(remaining.enumerated()), id: \.element) { pos, idx in
                let f = q.facts[idx]
                let nextValue = max(1, currentValue(q) - f.cost)
                IdolHintRow(number: pos + 1, nextValue: nextValue) {
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
        if isCorrect {
            correct += 1
            points += currentValue(q)
        }
    }

    private func nextQuestion() {
        selectedId = nil
        opened = []
        question = makeQuestion()
    }

    private func restart() {
        points = 0; correct = 0; asked = 0
        sessionDone = false; selectedId = nil; opened = []; isNewBest = false
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
        pool = all.filter { idol in
            // ブランド絞り込み: 空集合のときは全ブランドを対象とする。
            let brandMatch = selectedBrandIds.isEmpty || selectedBrandIds.contains(idol.brandId)
            return !idol.isExternal && (idol.color?.isEmpty == false)
                && facts(for: idol).count >= 3 && brandMatch
        }
        question = makeQuestion()
    }

    /// プロフィール事実を「曖昧 (絞り込みにくい) → 特定 (バレやすい)」の順で返す。
    /// 先頭が無料公開、後ろほど答えに近づく。CV は一気にバレるのでコストを重く (-2pt)。
    private func facts(for idol: Idol) -> [Fact] {
        var f: [Fact] = []
        // 曖昧グループ (該当者が多い)
        if let bt = idol.bloodType, !bt.isEmpty { f.append(Fact(label: "血液型", value: bt, cost: 1)) }
        if let c = idol.constellation, !c.isEmpty { f.append(Fact(label: "星座", value: c, cost: 1)) }
        if let p = idol.birthPlace, !p.isEmpty { f.append(Fact(label: "出身", value: p, cost: 1)) }
        if let h = idol.heightDisplay { f.append(Fact(label: "身長", value: h, cost: 1)) }
        if let age = idol.age { f.append(Fact(label: "年齢", value: "\(age)歳", cost: 1)) }
        // 特定グループ (一気に絞れる)
        if let h = idol.hobbies, !h.isEmpty { f.append(Fact(label: "趣味", value: h, cost: 1)) }
        if let t = idol.talents, !t.isEmpty { f.append(Fact(label: "特技", value: t, cost: 1)) }
        if let b = idol.birthdayDisplay, !b.isEmpty { f.append(Fact(label: "誕生日", value: b, cost: 1)) }
        // メンバーカラー・CV は一気にバレるのでコストを重く (-2pt)。
        if let color = idol.color, !color.isEmpty { f.append(Fact(label: "メンバーカラー", value: color, cost: 2)) }
        // CV は常にスロットを出す。声優未発表キャラは開封で「未発表」と分かる
        // (枠の有無で声優の有無が無料でバレるのを防ぐ)。
        let cvValue = (idol.currentVoiceActor?.isEmpty == false) ? idol.currentVoiceActor! : "声優未発表"
        f.append(Fact(label: "CV", value: cvValue, cost: 2))
        return f
    }

    private func makeQuestion() -> Question? {
        guard pool.count >= 4, let answer = pool.randomElement() else { return nil }
        let choices = (quizDistractors(from: pool, answer: answer) + [answer]).shuffled()
        return Question(answer: answer, choices: choices, facts: facts(for: answer))
    }
}

/// アイドル当てクイズ専用のヒント行。属性ラベルは伏せ「ヒント①②③」だけ見せる。
/// (どの属性が出題に積まれているかで CV未発表などが無料でバレるのを防ぐ)
/// 開いた後の獲得点を加点表現で見せる。
private struct IdolHintRow: View {
    let number: Int
    let nextValue: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.sp3) {
                Image(systemName: "questionmark")
                    .font(.imasScaled( 16, weight: .bold)).foregroundStyle(DS.warning)
                    .frame(width: 34, height: 34)
                    .background(DS.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("ヒント \(number) を見る").font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
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
