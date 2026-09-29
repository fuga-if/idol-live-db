import SwiftUI

struct IntroGameResultView: View {
    let session: IntroGameSession
    /// 「もう一度あそぶ」/「ホームに戻る」で呼ぶ処理。**この View は画面遷移を持たない。**
    ///
    /// 以前は共有シグナルを立てて Game / Setup の `onChange` に拾わせていたが、
    /// **SwiftUI は push で隠れた View の `onChange` を走らせない** (body は再評価される
    /// のに onChange だけ来ない) ため、どちらのボタンも無反応だった。押した側から
    /// 画面を持っている側へ直接渡す。
    let onReplay: () -> Void
    let onHome: () -> Void

    /// 実際に回答した問題数 (スキップ含む)。正答率の母数。
    /// Rush は候補曲(最大300)を全部出せるわけがないので totalCount ではなく回答数で割る。
    private var answered: Int { session.records.count }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var modeLabel: String {
        if session.isAllSongsChallenge { return "全曲チャレンジ" }
        switch session.settings.mode {
        case .rush: return "ラッシュ \(Int(session.settings.rushTimeLimit))秒"
        case .party: return "パーティ対戦"
        case .allSongs, .normal: return "ノーマル"
        }
    }

    /// 結果カードを画像化してシェア (本家宣伝フッター付き)。
    private func shareResultImage() {
        // 全曲チャレンジは曲数が多すぎて内訳が無意味なのでサマリ+タイムのみ。
        let rows = session.isAllSongsChallenge
            ? []
            : session.records.enumerated().map { i, r in
                QuizShareRow(number: i + 1, title: r.title, hex: nil, isCorrect: r.correct)
            }
        QuizShareCard(title: "イントロドン", subtitle: modeLabel, result: result, rows: rows,
                      longestStreak: session.bestCombo, isNewBest: session.isNewBest,
                      extraStat: session.isAllSongsChallenge ? ("タイム", timeString(session.elapsedTime)) : nil,
                      footer: .introQuiz)
            .share(text: shareText)
    }

    /// シェア用テキスト (本家アプリの宣伝も兼ねる)。文面はコアが作る。
    private var shareText: String {
        shareIntroDonText(input: IntroDonShareInput(
            mode: shareMode,
            score: Int32(clamping: session.score),
            answered: Int32(clamping: answered),
            bestCombo: Int32(clamping: session.bestCombo),
            elapsedSeconds: session.elapsedTime,
            rushTimeLimitSeconds: session.settings.rushTimeLimit))
    }

    /// シェア文の種類。全曲チャレンジかどうかは、設定の mode ではなくセッションの状態で決まる。
    private var shareMode: IntroDonShareMode {
        if session.isAllSongsChallenge { return .allSongs }
        switch session.settings.mode {
        case .rush: return .rush
        case .party: return .party
        case .allSongs, .normal: return .normal
        }
    }

    /// 他のクイズと同じ形の結果 (グレード・一言)。点は正解数、分母は回答した数。
    private var result: QuizSessionResult {
        quizAccuracyResult(points: UInt32(clamping: session.score), outOf: UInt32(clamping: answered),
                           correct: UInt32(clamping: session.score), questions: UInt32(clamping: answered))
    }

    private var slots: [QuizPenlight] {
        let results: [Color?] = session.records.enumerated().map { i, r in r.correct ? QS.penlight(i) : nil }
        return QuizPenlight.slots(results: results, total: results.count, answering: false)
    }

    private var misses: [QuizMissItem] {
        session.records.enumerated()
            .filter { !$0.element.correct }
            .prefix(30)
            .map { i, r in
                QuizMissItem(id: r.id + "-\(i)", number: i + 1, title: r.title, hex: nil,
                             picked: r.selectedTitle ?? "スキップ")
            }
    }

    var body: some View {
        NavigationStack {
            QuizStageScaffold(title: "イントロドン · \(modeLabel)", header: .result(total: answered),
                              onClose: {
                                  AppAnalytics.tap("intro_game_result.go_home")
                                  // ⚠️ ここで session.reset() を呼ばない (下の画面が空表示に化ける)。
                                  onHome()
                              },
                              trailing: {
                                  QuizStageRoundButton(systemImage: "square.and.arrow.up", label: "結果を画像でシェア") {
                                      AppAnalytics.tap("intro_game_result.share")
                                      shareResultImage()
                                  }
                              }) {
                // 全曲チャレンジはタイムを競う。
                if session.isAllSongsChallenge { timeTile }
                QuizStageResultView(
                    result: result, kind: .introDon,
                    isNewBest: session.isNewBest, previousBest: session.previousBestScore,
                    slots: slots, longestStreak: session.bestCombo, misses: misses,
                    onReplay: {
                        AppAnalytics.tap("intro_game_result.replay")
                        // ⚠️ ここで session.reset() を呼んではいけない。
                        // この結果画面はまだ画面上にあるので、記録が消えた瞬間に 0/0・履歴なしへ
                        // 描き変わってしまう (「空の結果画面が後から出てくる」の原因)。
                        // 次の対局の初期化は IntroGameSession.generateQuestions が全部やる。
                        // Setup画面(積み上げ済み)まで戻すだけ。
                        onReplay()
                    },
                    onClose: {
                        AppAnalytics.tap("intro_game_result.go_home")
                        onHome()
                    })
            }
        }
        .trackScreen("intro_game_result")
    }

    private var timeTile: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("タイム").font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
                Text(timeString(session.elapsedTime)).font(QS.num(40)).foregroundStyle(QS.ink)
            }
            Spacer()
            if session.newBestTimeAchieved {
                Text("ベストタイム更新")
                    .font(QS.text(13, weight: .black))
                    .foregroundStyle(QS.stamp)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(QS.paper, in: RoundedRectangle(cornerRadius: 8))
                    .rotationEffect(.degrees(-4))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
