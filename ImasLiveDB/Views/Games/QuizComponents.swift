import SwiftUI

// =============================================================================
// 4 択クイズ系 (アイドル当て / ソロ曲) の共通 UI 部品。
// ヒント式の段階採点を中核に据える: 最初は最小の情報だけで出題し、ヒントを開くほど
// 分かりやすくなる代わりに獲得点が下がる。進捗ヘッダ・選択肢・ヒント・結果を集約。
// =============================================================================

/// ヒント式採点の規則。1 問の満点は maxPoints、ヒントを 1 つ開くごとに 1 点ずつ上限が下がる。
enum QuizScoring {
    /// ノーヒント正解の満点。
    static let maxPoints = 3
    /// ヒントの最大数 (満点を 1 点まで下げられる本数)。
    static var maxHints: Int { maxPoints - 1 }

    /// revealed 個のヒントを開いた状態で正解したときの得点 (最低 1 点)。
    static func points(revealed: Int) -> Int { max(1, maxPoints - revealed) }
    /// 1 セッションの満点。
    static func sessionMax(questions: Int) -> Int { questions * maxPoints }
}

/// 4 択のディストラクタ (誤答候補) を 3 名選ぶ。同ブランドを優先し、足りなければ他ブランドで補う。
/// アイドル当て / ソロ曲クイズで共通。
func quizDistractors(from pool: [Idol], answer: Idol) -> [Idol] {
    var distractors = pool.filter { $0.id != answer.id && $0.brandId == answer.brandId }.shuffled()
    if distractors.count < 3 {
        distractors += pool.filter { $0.id != answer.id && $0.brandId != answer.brandId }.shuffled()
    }
    return Array(distractors.prefix(3))
}

/// 進捗バー + 累計ポイント。第 current/total 問と現在の獲得ポイントを表示。
struct QuizProgressHeader: View {
    let current: Int
    let total: Int
    let points: Int

    var body: some View {
        VStack(spacing: DS.sp3) {
            HStack {
                Text("第 \(current) / \(total) 問").font(.imasFootnote.weight(.semibold)).foregroundStyle(DS.ink2)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.imasScaled( 12)).foregroundStyle(DS.favorite)
                    Text("\(points) pt").font(.imasDisplay(15, weight: .bold)).foregroundStyle(DS.ink)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(DS.sys)
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.25), value: progress)
                }
            }
            .frame(height: 6)
        }
    }

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(current - 1) / Double(total)))
    }
}

/// 正解で獲得できるポイントを示すバッジ。加点表現に統一 (減点語は使わない)。
struct QuizValueBadge: View {
    let revealed: Int
    var body: some View {
        let pts = QuizScoring.points(revealed: revealed)
        HStack(spacing: 5) {
            Image(systemName: "plus.circle.fill").font(.imasScaled( 11, weight: .bold))
            Text("正解で +\(pts)pt").font(.imasCaption.weight(.bold))
        }
        .foregroundStyle(DS.success)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(DS.success.opacity(0.14), in: Capsule())
    }
}

/// 段階ヒントを開くボタン。開くと「以降の上限点が下がる」ことを副題で明示する。
struct QuizHintButton: View {
    let systemImage: String
    let title: String
    let nextValue: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.sp3) {
                Image(systemName: systemImage)
                    .font(.imasScaled( 16, weight: .semibold)).foregroundStyle(DS.warning)
                    .frame(width: 34, height: 34)
                    .background(DS.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
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

/// 4 択ボタン。未解答 = ニュートラル / 解答後は正解=緑・誤答=赤で明示。
struct QuizChoiceButton: View {
    let name: String
    let answered: Bool
    let isAnswer: Bool
    let isPicked: Bool
    /// 解答後にだけ出すアバター/ジャケ等 (任意)。
    var avatar: () -> AnyView?
    let action: () -> Void

    var body: some View {
        let bg: Color = {
            guard answered else { return DS.surface }
            if isAnswer { return DS.success.opacity(0.18) }
            if isPicked { return DS.danger.opacity(0.18) }
            return DS.surface
        }()
        let border: Color = answered && (isAnswer || isPicked) ? (isAnswer ? DS.success : DS.danger) : .clear
        Button(action: action) {
            HStack(spacing: DS.sp3) {
                if answered, let av = avatar() { av }
                Text(name)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if answered && isAnswer {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.success)
                } else if answered && isPicked {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.danger)
                }
            }
            .padding(.horizontal, DS.sp4).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(bg, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous).strokeBorder(border, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }
}

/// クイズ共通の主ボタン (次の問題 / 結果を見る)。
struct QuizPrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.imasHeadline.weight(.semibold))
                .foregroundStyle(DS.onSys)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(DS.sys, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 解答後に出す「次の問題 / 結果を見る」ボタン。最終問なら結果へ、それ以外は次問へ進む。
/// アイドル当て / ソロ曲クイズで共通 (どちらも同じ進行ロジック)。
struct QuizNextButton: View {
    let isLastQuestion: Bool
    let onNext: () -> Void
    let onFinish: () -> Void

    var body: some View {
        QuizPrimaryButton(title: isLastQuestion ? "結果を見る" : "次の問題") {
            if isLastQuestion { onFinish() } else { onNext() }
        }
    }
}

/// アイドル 4 択グリッド。アイドル当て / ソロ曲クイズで共通。
/// 解答後は本人アバターを添えて正誤を色で示す。タップ確定は最初の 1 回だけ反映。
struct IdolChoiceGrid: View {
    let choices: [Idol]
    let answer: Idol
    let selectedId: String?
    /// 選択肢が押されたとき (正解なら isCorrect=true)。確定済みなら呼ばれない。
    let onPick: (_ idol: Idol, _ isCorrect: Bool) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.sp3), count: 2), spacing: DS.sp3) {
            ForEach(choices) { idol in
                let answered = selectedId != nil
                let isAnswer = idol.id == answer.id
                QuizChoiceButton(
                    name: idol.name, answered: answered, isAnswer: isAnswer, isPicked: idol.id == selectedId,
                    avatar: { answered ? AnyView(IdolAvatarView(idol: idol, size: 34)) : nil }
                ) {
                    guard selectedId == nil else { return }
                    onPick(idol, isAnswer)
                }
            }
        }
    }
}

/// セッション内の1問分の振り返り。リザルト画面の「何が出て何を間違えたか」一覧に使う。
/// アイドル当てとソロ曲クイズで共通 (どちらも 4択 + 正解アイドル)。
struct QuizHistoryItem: Identifiable, Hashable {
    let id: String                  // 一意キー (出題順 + 題材ID で衝突を防ぐ)
    let index: Int                  // 1始まりの問題番号
    let subjectTitle: String        // 題材の表示名 (アイドル当て=「プロフィール」/ソロ曲=曲名)
    let subjectSubtitle: String?    // 補助情報 (CD名等、無ければnil)
    let answer: Idol                // 正解
    let picked: Idol?               // ユーザが選んだ選択肢 (未解答なら nil)
    let earnedPoints: Int           // この問題で獲得した点 (0 = 不正解)
    let revealedHints: Int          // 開いたヒント数

    var isCorrect: Bool { picked?.id == answer.id }
}

/// アイドル当てクイズの「未公開プロフィール事実」1件。IdolQuizView (実際の出題・ヒント表示) と
/// IdolQuizSetupView (出題候補数の見積り) の両方から参照する共通の型。
struct IdolQuizFact {
    let label: String
    let value: String
    let cost: Int
}

/// プロフィール事実を「曖昧 (絞り込みにくい) → 特定 (バレやすい)」の順で返す。
/// 先頭が無料公開、後ろほど答えに近づく。CV は一気にバレるのでコストを重く (-2pt)。
///
/// IdolQuizView.load() の実絞り込みと IdolQuizSetupView.estimatePool() の見積りが
/// 別々にこの判定を持つと、見積りでは開始可能でも実際は候補不足で
/// 「出題できる候補が不足しています」に落ちるズレが起きるため、必ずこれを共有する。
func idolQuizFacts(for idol: Idol) -> [IdolQuizFact] {
    var f: [IdolQuizFact] = []
    // 曖昧グループ (該当者が多い)
    if let bt = idol.bloodType, !bt.isEmpty { f.append(IdolQuizFact(label: "血液型", value: bt, cost: 1)) }
    if let c = idol.constellation, !c.isEmpty { f.append(IdolQuizFact(label: "星座", value: c, cost: 1)) }
    if let p = idol.birthPlace, !p.isEmpty { f.append(IdolQuizFact(label: "出身", value: p, cost: 1)) }
    if let h = idol.heightDisplay { f.append(IdolQuizFact(label: "身長", value: h, cost: 1)) }
    if let age = idol.age { f.append(IdolQuizFact(label: "年齢", value: "\(age)歳", cost: 1)) }
    // 特定グループ (一気に絞れる)
    if let h = idol.hobbies, !h.isEmpty { f.append(IdolQuizFact(label: "趣味", value: h, cost: 1)) }
    if let t = idol.talents, !t.isEmpty { f.append(IdolQuizFact(label: "特技", value: t, cost: 1)) }
    if let b = idol.birthdayDisplay, !b.isEmpty { f.append(IdolQuizFact(label: "誕生日", value: b, cost: 1)) }
    // メンバーカラー・CV は一気にバレるのでコストを重く (-2pt)。
    if let color = idol.color, !color.isEmpty { f.append(IdolQuizFact(label: "メンバーカラー", value: color, cost: 2)) }
    // CV は常にスロットを出す。声優未発表キャラは開封で「未発表」と分かる
    // (枠の有無で声優の有無が無料でバレるのを防ぐ)。
    let cvValue = (idol.currentVoiceActor?.isEmpty == false) ? idol.currentVoiceActor! : "声優未発表"
    f.append(IdolQuizFact(label: "CV", value: cvValue, cost: 2))
    return f
}

/// アイドル当てクイズの出題対象として使えるか。外部人物除外・メンバーカラー必須に加えて
/// facts が最低3件 (ヒントとして機能する数) 無いと出題に使えない。
func isIdolQuizEligible(_ idol: Idol, selectedBrandIds: Set<String>) -> Bool {
    let brandMatch = selectedBrandIds.isEmpty || selectedBrandIds.contains(idol.brandId)
    return !idol.isExternal && (idol.color?.isEmpty == false)
        && idolQuizFacts(for: idol).count >= 3 && brandMatch
}

/// クイズのグレード (正答率ベース)。リザルトの主役。
enum QuizGrade: String {
    case s = "S", a = "A", b = "B", c = "C", d = "D"

    static func from(rate: Int) -> QuizGrade {
        switch rate {
        case 95...: return .s
        case 80...: return .a
        case 60...: return .b
        case 40...: return .c
        default:    return .d
        }
    }

    var color: Color {
        switch self {
        case .s: return DS.favorite
        case .a: return DS.success
        case .b: return DS.sys
        case .c: return DS.warning
        case .d: return DS.ink3
        }
    }
}

/// セッション終了時の結果画面。グレード・自己ベスト・新記録・出題履歴・シェアまで載せる。
struct QuizResultView: View {
    let points: Int
    let maxPoints: Int
    let correct: Int
    let questions: Int
    /// どのゲームの結果か (自己ベスト参照・シェア文言用)。
    var kind: GameKind = .idolQuiz
    /// 今回が自己ベスト更新だったか。
    var isNewBest: Bool = false
    /// 各問の振り返り (空なら履歴セクション非表示)。
    var history: [QuizHistoryItem] = []
    let onReplay: () -> Void

    @State private var appeared = false

    private var rate: Int { maxPoints > 0 ? Int((Double(points) / Double(maxPoints) * 100).rounded()) : 0 }
    private var grade: QuizGrade { .from(rate: rate) }

    private var bestRate: Int {
        let rec = GameProgressStore.shared.record(for: kind)
        guard rec.bestOutOf > 0 else { return rate }
        return Int((Double(rec.bestScore) / Double(rec.bestOutOf) * 100).rounded())
    }

    private var comment: String {
        switch rate {
        case 95...: return "お見事！担当への愛が伝わる"
        case 80...: return "高得点！プロデューサーの貫禄"
        case 50...: return "いい線いってる！次はもっと高みへ"
        default: return "これから一緒に覚えていこう"
        }
    }

    private var shareText: String {
        "\(kind.displayName)で \(points)/\(maxPoints)pt・グレード\(grade.rawValue)（正解 \(correct)/\(questions)）でした！ #アイドルライブDB"
    }

    var body: some View {
        VStack(spacing: DS.sp4) {
            Spacer().frame(height: DS.sp5)

            // グレードリング (主役)。
            ZStack {
                Circle().fill(grade.color.opacity(0.14)).frame(width: 116, height: 116)
                Circle().strokeBorder(grade.color, lineWidth: 4).frame(width: 116, height: 116)
                Text(grade.rawValue)
                    .font(.imasDisplay(56, weight: .bold))
                    .foregroundStyle(grade.color)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: appeared)

            if isNewBest {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill").font(.imasScaled(12, weight: .bold))
                    Text("自己ベスト更新！").font(.imasFootnote.weight(.bold))
                }
                .foregroundStyle(DS.favorite)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(DS.favorite.opacity(0.16), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(points)").font(.imasDisplay(40, weight: .bold)).foregroundStyle(DS.ink)
                Text("/ \(maxPoints) pt").font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink3)
            }

            HStack(spacing: DS.sp3) {
                resultStat(value: "\(correct)/\(questions)", label: "正解")
                resultStat(value: "\(rate)%", label: "正答率")
                resultStat(value: "\(bestRate)%", label: "自己ベスト")
            }
            Text(comment)
                .font(.imasFootnote).foregroundStyle(DS.ink3)
                .multilineTextAlignment(.center).padding(.top, DS.sp1)

            if !history.isEmpty {
                QuizHistoryList(items: history).padding(.top, DS.sp4)
            }

            VStack(spacing: DS.sp3) {
                QuizPrimaryButton(title: "もう一度", action: onReplay)
                ShareLink(item: shareText) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.imasScaled(14, weight: .semibold))
                        Text("結果をシェア").font(.imasSubhead.weight(.semibold))
                    }
                    .foregroundStyle(DS.sys)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(DS.sys.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, DS.sp3)
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }

    private func resultStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.imasDisplay(20, weight: .bold)).foregroundStyle(DS.ink)
            Text(label).font(.imasCaption).foregroundStyle(DS.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }
}

// MARK: - 出題履歴 (リザルトの「何が出て何を間違えたか」一覧)

/// セッション中の各問の振り返り一覧。題材 / 正解 / 自分の選択 / 正誤 を出す。
struct QuizHistoryList: View {
    let items: [QuizHistoryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.imasScaled(13, weight: .semibold)).foregroundStyle(DS.ink2)
                Text("出題の振り返り").font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                Spacer(minLength: 0)
            }
            VStack(spacing: DS.sp2) {
                ForEach(items) { item in QuizHistoryRow(item: item) }
            }
        }
    }
}

private struct QuizHistoryRow: View {
    let item: QuizHistoryItem

    var body: some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            // 問題番号 + 正誤アイコン
            VStack(spacing: 2) {
                Text("Q\(item.index)").font(.imasCaption.weight(.bold).monospacedDigit()).foregroundStyle(DS.ink3)
                Image(systemName: item.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.imasScaled(16))
                    .foregroundStyle(item.isCorrect ? DS.success : DS.danger)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                // 題材 (アイドル当て=「プロフィール」、ソロ曲=曲名)
                Text(item.subjectTitle)
                    .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                    .lineLimit(2)
                if let sub = item.subjectSubtitle, !sub.isEmpty {
                    Text(sub).font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(1)
                }
                // 正解と (誤答時のみ) 自分の選択
                HStack(spacing: DS.sp2) {
                    answerChip(label: "正解", idol: item.answer, tone: DS.success)
                    if !item.isCorrect, let picked = item.picked {
                        answerChip(label: "選択", idol: picked, tone: DS.danger)
                    }
                }
                // ヒント数と獲得点
                HStack(spacing: 10) {
                    Label("\(item.earnedPoints)pt", systemImage: "plus.circle.fill")
                        .font(.imasCaption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(item.earnedPoints > 0 ? DS.success : DS.ink3)
                    if item.revealedHints > 0 {
                        Label("ヒント\(item.revealedHints)", systemImage: "lightbulb.fill")
                            .font(.imasCaption.weight(.semibold))
                            .foregroundStyle(DS.warning)
                    }
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.horizontal, DS.sp3).padding(.vertical, DS.sp3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    private func answerChip(label: String, idol: Idol, tone: Color) -> some View {
        HStack(spacing: 6) {
            IdolAvatarView(idol: idol, size: 20)
            Text(label).font(.imasCaption.weight(.bold)).foregroundStyle(tone)
            Text(idol.name).font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tone.opacity(0.12), in: Capsule())
    }
}
