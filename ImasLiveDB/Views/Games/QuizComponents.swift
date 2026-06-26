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

/// 現在の獲得可能点を示す「配点バッジ」。ヒントを開くほど下がる様子を可視化する。
struct QuizValueBadge: View {
    let revealed: Int
    var body: some View {
        let pts = QuizScoring.points(revealed: revealed)
        HStack(spacing: 5) {
            Image(systemName: "target").font(.imasScaled( 11, weight: .bold))
            Text("正解で \(pts)pt").font(.imasCaption.weight(.bold))
            if revealed > 0 {
                Text("(ヒント\(revealed))").font(.imasCaption).opacity(0.7)
            }
        }
        .foregroundStyle(revealed == 0 ? DS.success : DS.warning)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background((revealed == 0 ? DS.success : DS.warning).opacity(0.14), in: Capsule())
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
                    Text("開くと正解 \(nextValue)pt に下がる").font(.imasCaption).foregroundStyle(DS.ink3)
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

/// セッション終了時の結果画面。獲得ポイント / 満点と「ヒント無し正解数」を出す。
struct QuizResultView: View {
    let points: Int
    let maxPoints: Int
    let correct: Int
    let questions: Int
    /// ヒントを 1 つも開かずに正解した数 (= 満点正解)。
    let perfectCount: Int
    let onReplay: () -> Void

    private var rate: Int { maxPoints > 0 ? Int((Double(points) / Double(maxPoints) * 100).rounded()) : 0 }

    private var comment: String {
        switch rate {
        case 100: return "全問ノーヒント正解！さすがプロデューサー"
        case 80...: return "お見事！担当への愛が伝わる"
        case 50...: return "いい線いってる！ヒントを減らして高得点を狙おう"
        default: return "これから一緒に覚えていこう"
        }
    }

    var body: some View {
        VStack(spacing: DS.sp4) {
            Spacer().frame(height: DS.sp6)
            Image(systemName: rate >= 80 ? "trophy.fill" : "checkmark.seal.fill")
                .font(.imasScaled( 52, weight: .semibold))
                .foregroundStyle(rate >= 80 ? DS.favorite : DS.sys)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(points)").font(.imasDisplay(40, weight: .bold)).foregroundStyle(DS.ink)
                Text("/ \(maxPoints) pt").font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink3)
            }
            HStack(spacing: DS.sp3) {
                resultStat(value: "\(correct)/\(questions)", label: "正解")
                resultStat(value: "\(perfectCount)", label: "ノーヒント正解")
            }
            Text(comment)
                .font(.imasFootnote).foregroundStyle(DS.ink3)
                .multilineTextAlignment(.center).padding(.top, DS.sp2)
            QuizPrimaryButton(title: "もう一度", action: onReplay)
                .padding(.top, DS.sp4)
        }
        .frame(maxWidth: .infinity)
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
