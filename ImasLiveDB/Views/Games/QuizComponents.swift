import SwiftUI

// =============================================================================
// 4 択クイズ系 (アイドル当て / ソロ曲) の共通 UI 部品。
// ヒント式の段階採点を中核に据える: 最初は最小の情報だけで出題し、ヒントを開くほど
// 分かりやすくなる代わりに獲得点が下がる。進捗ヘッダ・選択肢・ヒント・結果を集約。
//
// 出題の生成・選択肢の作り方・採点・グレード判定・母集団の条件は imas-core の
// `domain/quiz_generation.rs` が単独で持つ (iOS/Android で同じ規則を 2 度書かないため)。
// ここに残すのは描画と、コアが返した値の見せ方だけ。
// =============================================================================

/// `Idol` → アイドル当てクイズの射影。出題設定画面の見積り (`idolQuizPoolEstimate`) と
/// ゲーム本体 (`idolQuizSession`) が同じ母集団を見るよう、変換もこの 1 か所に置く。
/// CV は `VoiceActorDirectory` (MainActor) から引くのでこの関数も MainActor。
/// 誕生日は生の `--MM-DD` のまま渡す (「4月3日」への整形はコア側の規則)。
@MainActor
func idolQuizRefs(_ idols: [Idol]) -> [IdolQuizIdolRef] {
    idols.map { idol in
        IdolQuizIdolRef(
            id: idol.id,
            brandId: idol.brandId,
            isExternal: idol.isExternal,
            color: idol.color,
            bloodType: idol.bloodType,
            constellation: idol.constellation,
            birthPlace: idol.birthPlace,
            height: idol.height,
            age: idol.age.map { Int32(clamping: $0) },
            hobbies: idol.hobbies,
            talents: idol.talents,
            birthday: idol.birthday,
            voiceActor: VoiceActorDirectory.shared.current(for: idol.id)
        )
    }
}

/// ソロ曲クイズに渡す `song_artists(role='original')` の行。ゲーム本体
/// (`songSingerQuizSession`) と出題設定画面の見積り (`songSingerQuizPoolEstimate`) が
/// 同じ母集団を見るよう、行の並べ方もここに置く。
///
/// 曲名かな順の `solos` の順に並べる (コアはこの並びをそのまま母集団の並びにする)。
/// 1 曲に複数行あるまま渡すのが肝で、「原唱が単独の曲だけ出題する」判定はコアが行数で行う
/// (ここで間引くと合唱曲が 1 人の曲に化ける)。同じ曲の中の並びは辞書順に固定する
/// (`Set` の反復順は実行ごとに変わるが、どの行も落とされるので出題には影響しない)。
func songQuizOriginalArtistRows(
    solos: [SongWithArtists],
    originalArtistIds: [String: Set<String>]
) -> [SongQuizOriginalArtistRow] {
    solos.flatMap { sw in
        (originalArtistIds[sw.song.id] ?? []).sorted().map {
            SongQuizOriginalArtistRow(songId: sw.song.id, idolId: $0)
        }
    }
}

/// `Idol` → ソロ曲クイズの選択肢に使う射影 (歌手当てなのでプロフィールは要らない)。
func songQuizSingerRefs(_ idols: [Idol]) -> [SongQuizSingerRef] {
    idols.map { SongQuizSingerRef(id: $0.id, brandId: $0.brandId, isExternal: $0.isExternal) }
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
                HStack(spacing: DS.sp2) {
                    Image(systemName: "star.fill").font(.imasCaption).foregroundStyle(DS.favorite)
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
/// 点そのものはコアのヒント状態 (`currentValue`) が返した値を受け取る。
struct QuizValueBadge: View {
    let value: Int
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "plus.circle.fill").font(.imasScaled( 11, weight: .bold))
            Text("正解で +\(value)pt").font(.imasCaption.weight(.bold))
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
                    .background(DS.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
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
/// `isLastQuestion` はコアの解答結果 (`QuizAnswerOutcome`) が返した値をそのまま渡す。
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
    /// 選択肢が押されたとき。確定済みなら呼ばれない。
    let onPick: (_ idol: Idol) -> Void

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
                    onPick(idol)
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

/// クイズのグレード (正答率ベース)。リザルトの主役。
/// 何 % で何グレードかの判定はコア (`QuizGrade::from_rate`) が持ち、ここは見せ方だけ。
extension QuizGrade {
    /// リング内とシェア文言に出す 1 文字。
    var label: String {
        switch self {
        case .s: return "S"
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
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
    /// 今回のセッション結果 (点・満点・正解数・正答率・グレード)。コアが算出した値。
    let result: QuizSessionResult
    /// どのゲームの結果か (自己ベスト参照・シェア文言用)。
    var kind: GameKind = .idolQuiz
    /// 今回が自己ベスト更新だったか (進捗ストアの記録時にコアが返した判定)。
    var isNewBest: Bool = false
    /// 各問の振り返り (空なら履歴セクション非表示)。
    var history: [QuizHistoryItem] = []
    let onReplay: () -> Void

    @State private var appeared = false

    private var points: Int { Int(result.points) }
    private var maxPoints: Int { Int(result.maxPoints) }
    private var correct: Int { Int(result.correct) }
    private var questions: Int { Int(result.questions) }
    private var rate: Int { Int(result.ratePercent) }
    private var grade: QuizGrade { result.grade }

    /// 自己ベストは記録**後**の保存値から引く (記録が無い初回は今回の率で代用)。
    private var bestRate: Int { GameProgressStore.shared.bestRatePercent(for: kind) ?? rate }

    private var comment: String {
        switch rate {
        case 95...: return "お見事！担当への愛が伝わる"
        case 80...: return "高得点！プロデューサーの貫禄"
        case 50...: return "いい線いってる！次はもっと高みへ"
        default: return "これから一緒に覚えていこう"
        }
    }

    private var shareText: String {
        "\(kind.displayName)で \(points)/\(maxPoints)pt・グレード\(grade.label)（正解 \(correct)/\(questions)）でした！ #アイドルライブDB"
    }

    var body: some View {
        VStack(spacing: DS.sp4) {
            Spacer().frame(height: DS.sp5)

            // グレードリング (主役)。
            ZStack {
                Circle().fill(grade.color.opacity(0.14)).frame(width: 116, height: 116)
                Circle().strokeBorder(grade.color, lineWidth: 4).frame(width: 116, height: 116)
                Text(grade.label)
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
                .padding(.horizontal, DS.sp4).padding(.vertical, 6)
                .background(DS.favorite.opacity(0.16), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            HStack(alignment: .firstTextBaseline, spacing: DS.sp2) {
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
                    .frame(maxWidth: .infinity).padding(.vertical, DS.sp4)
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
        VStack(spacing: DS.sp1) {
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
            VStack(spacing: DS.sp1) {
                Text("Q\(item.index)").font(.imasCaption.weight(.bold).monospacedDigit()).foregroundStyle(DS.ink3)
                Image(systemName: item.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.imasCallout)
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
        .padding(.horizontal, DS.sp3).padding(.vertical, DS.sp2)
        .background(tone.opacity(0.12), in: Capsule())
    }
}
