import SwiftUI
import UIKit

// =============================================================================
// ミニゲーム共通の結果シェア画像 (1080×1350)。結果画面と同じ「暗いステージ + 生成りのチケット」。
//
// 上から: ゲーム名 → セトリのペンライト (正解は答えの色で点灯) → グレードと点のチケット →
// 1 問ずつの答え (最大 10 行) → アプリ名。曲のゲームは遊んだ曲のジャケットを上に敷く。
//
// ⚠️ 歌詞クイズでも歌詞は 1 文字も載せない (JASRAC の条件)。載せるのは曲名・名前・正誤・点だけ。
//
// NOTE: `ImageRenderer` で固定サイズのキャンバスへ焼くので、フォントは固定 pt を使う
// (`QS.num` などは Dynamic Type に追随するので使わない)。ジャケットは焼く前に UIImage にしておく。
// =============================================================================

/// シェア画像の 1 行 (1 問ぶん)。
struct QuizShareRow: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    /// 答えの色 (アイドルのイメージカラー)。曲など色が無ければ nil (ペンライトの色で代用)。
    let hex: String?
    let isCorrect: Bool
}

extension Array where Element == QuizStagePlay {
    /// 各問の記録 → シェア画像の行。
    var shareRows: [QuizShareRow] {
        map { QuizShareRow(number: $0.number, title: $0.answerName, hex: $0.answerHex, isCorrect: $0.isCorrect) }
    }
}

struct QuizShareCard: View {
    enum Footer {
        /// このアプリの宣伝。
        case app
        /// イントロドン: 本家アプリ「イントロクイズ」の宣伝。
        case introQuiz
    }

    let title: String
    /// モードや難易度 (「曲名当て」「ふつう · 4択」など)。
    var subtitle: String? = nil
    let result: QuizSessionResult
    let rows: [QuizShareRow]
    let longestStreak: Int
    let isNewBest: Bool
    /// 追加で見せる数字 (全曲チャレンジのタイムなど)。
    var extraStat: (label: String, value: String)? = nil
    /// 上に敷くジャケット (曲のゲーム)。空なら敷かない。
    var artworks: [UIImage] = []
    var footer: Footer = .app

    private static let size = CGSize(width: 1080, height: 1350)
    private static let maxRows = 10
    private static let maxBand = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !rows.isEmpty && rows.count <= Self.maxBand {
                penlightBand.padding(.top, 34)
            }
            ticket.padding(.top, 30)
            if !rows.isEmpty {
                answerList.padding(.top, 26)
            }
            Spacer(minLength: 0)
            footerView
        }
        .padding(.horizontal, 64)
        .padding(.top, 60)
        .padding(.bottom, 52)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(backdrop)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - 背景

    private var backdrop: some View {
        ZStack(alignment: .top) {
            QS.bg
            if artworks.isEmpty {
                RadialGradient(colors: [QS.penlight(0).opacity(0.22), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 760)
                RadialGradient(colors: [QS.penlight(4).opacity(0.18), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 700)
            } else {
                LyricsQuizMosaicBackground(images: artworks)
                    .frame(height: 640)
                    .mask(LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.5), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(0.7)
            }
        }
    }

    // MARK: - 見出し

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUIZ STAGE")
                .font(Self.mono(22))
                .tracking(8)
                .foregroundStyle(QS.ink)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(.black.opacity(0.4), in: Capsule())
                .overlay(Capsule().strokeBorder(QS.ink.opacity(0.3), lineWidth: 1.5))
            Text(title)
                .font(.system(size: 66, weight: .black))
                .foregroundStyle(QS.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, 8)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(QS.dim)
            }
        }
    }

    // MARK: - セトリのペンライト

    private var penlightBand: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    Capsule()
                        .fill(row.isCorrect ? color(row, i) : QS.missFill)
                        .overlay(Capsule().strokeBorder(row.isCorrect ? .clear : QS.line, lineWidth: 2))
                        .shadow(color: row.isCorrect ? color(row, i).opacity(0.7) : .clear, radius: 14)
                        .frame(maxWidth: 40)
                        .frame(height: 96)
                }
            }
            Text("今回のセトリ \(rows.filter(\.isCorrect).count) 本点灯")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(QS.dim)
        }
    }

    // MARK: - チケット

    private var ticket: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Text("GRADE").font(Self.mono(20)).tracking(3).foregroundStyle(QS.paperSub)
                Text(result.grade.label)
                    .font(Self.num(210, weight: .black))
                    .foregroundStyle(QS.paperInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                Text("SCORE").font(Self.mono(20)).tracking(3).foregroundStyle(QS.paperSub)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(result.points)").font(Self.num(104, weight: .black))
                    Text("/ \(result.maxPoints) pt").font(.system(size: 26, weight: .bold)).foregroundStyle(QS.paperSub)
                }
                .foregroundStyle(QS.paperInk)
                Text(summaryLine)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(QS.paperInk)
                if let extraStat {
                    Text("\(extraStat.label) \(extraStat.value)")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(QS.paperInk)
                }
                if isNewBest {
                    Text("自己ベスト更新")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(QS.stamp)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(QS.stamp, lineWidth: 3.5))
                        .rotationEffect(.degrees(-5))
                        .padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 28)
        .background(QS.paper, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    private var summaryLine: String {
        var s = "\(result.correct) / \(result.questions) 正解"
        if longestStreak >= 2 { s += " · 最大 \(longestStreak) 連続" }
        return s
    }

    // MARK: - 答えの一覧

    private var answerList: some View {
        let shown = Array(rows.prefix(Self.maxRows))
        let extra = rows.count - shown.count
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                HStack(spacing: 18) {
                    Text(String(format: "Q.%02d", row.number))
                        .font(Self.mono(20)).foregroundStyle(QS.faint)
                        .frame(width: 78, alignment: .leading)
                    Circle().fill(color(row, i)).frame(width: 18, height: 18)
                        .opacity(row.isCorrect ? 1 : 0.35)
                    Text(row.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(row.isCorrect ? QS.ink : QS.dim)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: row.isCorrect ? "checkmark" : "xmark")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(row.isCorrect ? QS.ink : QS.faint)
                }
                .frame(height: 44)
                if i < shown.count - 1 {
                    Rectangle().fill(QS.rowLine).frame(height: 1)
                }
            }
            if extra > 0 {
                Text("ほか \(extra) 問")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(QS.dim)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(QS.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(QS.line, lineWidth: 1.5))
    }

    // MARK: - フッター

    @ViewBuilder
    private var footerView: some View {
        switch footer {
        case .app:
            HStack(alignment: .lastTextBaseline) {
                Text("アイドルライブDB")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(QS.ink)
                Spacer()
                Text("App Store で配信中")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(QS.dim)
            }
        case .introQuiz:
            HStack(alignment: .lastTextBaseline) {
                Text("もっと遊ぶなら本家アプリ")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(QS.dim)
                Spacer()
                Text("App Storeで「イントロクイズ」")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(QS.ink)
            }
        }
    }

    // MARK: - 部品

    private func color(_ row: QuizShareRow, _ index: Int) -> Color {
        row.hex.map { Color(hexString: $0, default: QS.penlight(index)) } ?? QS.penlight(index)
    }

    private static func num(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight).width(.compressed).monospacedDigit()
    }

    private static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

extension QuizShareCard {
    /// 画像に焼いて共有シートを出す。文面はコアの `shareQuizResultText` などで作って渡す。
    @MainActor
    func share(text: String) {
        let image = IntroShareImageRenderer.render(size: Self.size) { self }
        IntroShareImageRenderer.share(image: image, text: text)
    }

    /// 他のクイズ共通のシェア文 (コアが作る)。
    static func text(_ gameName: String, _ result: QuizSessionResult) -> String {
        shareQuizResultText(gameDisplayName: gameName, points: result.points, maxPoints: result.maxPoints,
                            grade: result.grade, correct: result.correct, questions: result.questions)
    }
}
