import SwiftUI

// =============================================================================
// クイズの「ステージ」見た目 (Claude Design 製のクイズ画面デザインを実装したもの)。
//
// ゲーム中の画面だけは、アプリ本体の灰色の画面ではなくライブ会場の暗いステージにする。
// 正解するたびに「セトリ」のペンライトがその問題の答えの色で 1 本ずつ灯り、
// 問題とヒントは生成り色の「チケット」に載る。数字は細長い太字、ラベルは等幅の英字。
//
// 見た目の部品だけを置き、出題・採点・グレードの規則は今まで通りコア (imas-core) が持つ。
// ダーク固定の配色なので DS トークンではなく `QS` の固定色を使う (ライト/ダークで反転させない)。
// =============================================================================

/// ステージ画面の配色・書体。
enum QS {
    static let bg = Color(red: 0x15 / 255, green: 0x13 / 255, blue: 0x1C / 255)
    static let panel = Color(red: 0x1F / 255, green: 0x1C / 255, blue: 0x28 / 255)
    static let raised = Color(red: 0x24 / 255, green: 0x21 / 255, blue: 0x2E / 255)
    static let line = Color(red: 0x3A / 255, green: 0x35 / 255, blue: 0x47 / 255)
    static let rowLine = Color(red: 0x2E / 255, green: 0x2A / 255, blue: 0x38 / 255)
    static let missFill = Color(red: 0x26 / 255, green: 0x23 / 255, blue: 0x2F / 255)
    /// 本文 (生成り)。
    static let ink = Color(red: 0xF6 / 255, green: 0xF1 / 255, blue: 0xE7 / 255)
    static let dim = Color(red: 0xA7 / 255, green: 0xA1 / 255, blue: 0xB5 / 255)
    static let faint = Color(red: 0x8C / 255, green: 0x86 / 255, blue: 0x99 / 255)

    /// チケット (生成りの紙) の上の色。
    static let paper = ink
    static let paperInk = Color(red: 0x1B / 255, green: 0x18 / 255, blue: 0x22 / 255)
    static let paperTile = Color(red: 0xEA / 255, green: 0xE3 / 255, blue: 0xD6 / 255)
    static let paperHighlight = Color(red: 0xEF / 255, green: 0xE8 / 255, blue: 0xDB / 255)
    static let paperSub = Color(red: 0x6B / 255, green: 0x64 / 255, blue: 0x78 / 255)
    static let paperMuted = Color(red: 0xA4 / 255, green: 0x9B / 255, blue: 0x8C / 255)
    static let paperLine = Color(red: 0xE4 / 255, green: 0xDC / 255, blue: 0xCD / 255)
    static let paperDash = Color(red: 0xC9 / 255, green: 0xC0 / 255, blue: 0xB0 / 255)
    static let stamp = Color(red: 0xB4 / 255, green: 0x23 / 255, blue: 0x35 / 255)

    /// 答えの色が無いとき (曲など) にペンライトへ回す色。アプリアイコンの帯の色。
    static let penlights: [Color] = [
        Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255),
        Color(red: 0xF0 / 255, green: 0x8C / 255, blue: 0x2E / 255),
        Color(red: 0xF2 / 255, green: 0xC1 / 255, blue: 0x2E / 255),
        Color(red: 0x3F / 255, green: 0xB2 / 255, blue: 0x7F / 255),
        Color(red: 0x3A / 255, green: 0x8E / 255, blue: 0xE6 / 255),
        Color(red: 0x7A / 255, green: 0x5A / 255, blue: 0xE0 / 255),
        Color(red: 0xD6 / 255, green: 0x5D / 255, blue: 0xB1 / 255),
    ]

    static func penlight(_ index: Int) -> Color { penlights[index % penlights.count] }

    /// 大きな数字 (細長い太字・等幅数字)。
    static func num(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        Font.imasScaled(size, weight: weight).width(.compressed).monospacedDigit()
    }

    /// 英字ラベル・番号 (等幅)。
    static func mono(_ size: CGFloat) -> Font {
        Font.imasScaled(size, weight: .semibold, design: .monospaced)
    }

    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.imasScaled(size, weight: weight)
    }
}

extension View {
    /// ゲーム中の画面をステージにする。ナビゲーションバーもステージ色に揃え (ステータスバーは白文字)、
    /// 戻るボタンの代わりに丸い × を置く。タブバーは隠す。
    func quizStage(onClose: @escaping () -> Void) -> some View {
        self
            .background(QS.bg.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .environment(\.colorScheme, .dark)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(QS.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    QuizStageRoundButton(systemImage: "xmark", label: "クイズを終了", action: onClose)
                }
            }
    }
}

/// ステージ上の丸いボタン (× / シェア)。
struct QuizStageRoundButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(QS.ink)
                .frame(width: 40, height: 40)
                .background(QS.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 上部 (ゲーム名・問題番号・スコア)

/// ナビゲーションバー中央の「ゲーム名 / Q.04 / 10」。
struct QuizStageTitle: View {
    let title: String
    let current: Int
    let total: Int

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(QS.text(11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(QS.dim)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "Q.%02d", current)).font(QS.num(24))
                Text("/ \(total)").font(QS.num(14, weight: .bold)).foregroundStyle(QS.faint)
            }
            .foregroundStyle(QS.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) 第\(current)問 全\(total)問")
    }
}

/// ナビゲーションバー右の「SCORE 300」。
struct QuizStageScore: View {
    let points: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("SCORE").font(QS.mono(9)).tracking(1).foregroundStyle(QS.dim)
            Text("\(points)")
                .font(QS.num(22))
                .foregroundStyle(QS.ink)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("スコア \(points)")
    }
}

// MARK: - セトリのペンライト (進み具合)

/// 1 問分のペンライト。正解 = 答えの色で点灯 / 不正解 = 消灯 (×) / 出題中 / これから。
enum QuizPenlight: Hashable {
    case lit(Color)
    case miss
    case now
    case next

    /// これまでの結果 (正解はその色、不正解は nil) から全問ぶんを並べる。
    /// `answering` のときは次の 1 本を「出題中」にする。
    static func slots(results: [Color?], total: Int, answering: Bool) -> [QuizPenlight] {
        (0..<max(total, results.count)).map { i in
            if i < results.count { return results[i].map { .lit($0) } ?? .miss }
            return (answering && i == results.count) ? .now : .next
        }
    }
}

/// ペンライトの列。
struct QuizPenlightRow: View {
    let slots: [QuizPenlight]
    var height: CGFloat = 26
    /// 結果画面で下に問題番号を振る。
    var numbered = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { i, slot in
                VStack(spacing: 2) {
                    stick(slot)
                        .frame(height: height)
                    UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                        .fill(QS.line)
                        .frame(width: 10, height: numbered ? 8 : 6)
                    if numbered {
                        Text(String(format: "%02d", i + 1))
                            .font(QS.mono(10)).foregroundStyle(QS.faint)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: slots)
        .accessibilityHidden(true)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 3,
                               bottomTrailingRadius: 3, topTrailingRadius: 6)
    }

    @ViewBuilder
    private func stick(_ slot: QuizPenlight) -> some View {
        switch slot {
        case .lit(let color):
            shape.fill(color).shadow(color: color.opacity(0.55), radius: 6)
        case .miss:
            shape.fill(QS.missFill)
                .overlay(Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(QS.faint))
        case .now:
            shape.fill(QS.raised).overlay(shape.inset(by: 1).stroke(QS.ink, lineWidth: 2))
        case .next:
            shape.inset(by: 0.5).stroke(QS.line, lineWidth: 1)
        }
    }
}

/// ヘッダ下のペンライト + 一言 (「セトリ 3 / 10 曲目まで点灯」「3 連続正解中」)。
struct QuizStageProgress: View {
    let slots: [QuizPenlight]
    let caption: String
    /// 連続正解数 (2 以上で右に出す)。
    let streak: Int
    /// 直前の問題で連続が途切れたとき。
    var streakBrokeAt: Int? = nil

    var body: some View {
        VStack(spacing: 10) {
            QuizPenlightRow(slots: slots)
            HStack {
                Text(caption)
                Spacer(minLength: 8)
                if streak >= 2 {
                    Label("\(streak) 連続正解中", systemImage: "arrowtriangle.up.fill")
                        .labelStyle(QuizTightLabelStyle())
                        .fontWeight(.bold)
                        .foregroundStyle(QS.ink)
                } else if let broke = streakBrokeAt, broke >= 2 {
                    Text("連続正解 \(broke) でストップ").fontWeight(.bold)
                }
            }
            .font(QS.text(12))
            .foregroundStyle(QS.dim)
        }
        .accessibilityElement(children: .combine)
    }
}

struct QuizTightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}

/// 連続正解の数え方 (見た目のための集計。採点には使わない)。
enum QuizStreak {
    /// 末尾から数えた連続正解数。
    static func current(_ results: [Bool]) -> Int {
        results.reversed().prefix { $0 }.count
    }

    /// セッション中の最長。
    static func longest(_ results: [Bool]) -> Int {
        var best = 0, run = 0
        for ok in results {
            run = ok ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// 直前の不正解で途切れた連続数 (途切れていなければ nil)。
    static func brokeAt(_ results: [Bool]) -> Int? {
        guard results.last == false else { return nil }
        return current(Array(results.dropLast()))
    }
}

// MARK: - 正解でもらえる点

/// 「正解でもらえる点 +70 (100)」とヒントで減っていく 10 目盛り。
struct QuizValueMeter: View {
    let value: Int
    /// ヒントを開いていないときの点。
    let base: Int
    /// 右下の一言 (「ヒントを開くと減ります」「ヒント 2 枚で −30」)。
    let note: String

    private var litSegments: Int {
        guard base > 0 else { return 0 }
        return Int((Double(value) / Double(base) * 10).rounded())
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("正解でもらえる点").font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("+\(value)").font(QS.num(42)).contentTransition(.numericText())
                    if value < base {
                        Text("\(base)").font(QS.num(20, weight: .bold)).foregroundStyle(QS.faint).strikethrough()
                    }
                }
                .foregroundStyle(QS.ink)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { i in
                        if i < litSegments {
                            RoundedRectangle(cornerRadius: 2).fill(QS.ink).frame(width: 7, height: 24)
                        } else {
                            RoundedRectangle(cornerRadius: 2).strokeBorder(QS.line, lineWidth: 1).frame(width: 7, height: 24)
                        }
                    }
                }
                .animation(.easeOut(duration: 0.25), value: litSegments)
                .accessibilityHidden(true)
                Text(note).font(QS.text(11)).foregroundStyle(QS.dim)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正解でもらえる点 \(value)点。\(note)")
    }
}

// MARK: - チケット (問題とヒントを載せる生成りの紙)

struct QuizTicket<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .foregroundStyle(QS.paperInk)
            .environment(\.colorScheme, .light)
            .background(QS.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// チケットの切り取り線 (両端がステージ色の半円で欠ける)。
struct QuizTicketNotch: View {
    var body: some View {
        HStack(spacing: 0) {
            UnevenRoundedRectangle(bottomTrailingRadius: 9, topTrailingRadius: 9)
                .fill(QS.bg).frame(width: 9, height: 18)
            Line()
                .stroke(QS.paperDash, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 1.5)
                .padding(.horizontal, 8)
            UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9)
                .fill(QS.bg).frame(width: 9, height: 18)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

/// チケット上部の「? / PROFILE / このアイドルはだれ？」。
struct QuizTicketHeading: View {
    let label: String
    let question: String
    /// 右端に出す獲得点 (ヘッダにメーターを出さない画面用)。
    var value: Int? = nil
    var base: Int? = nil

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .strokeBorder(QS.paperMuted, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: 48, height: 48)
                .overlay(Text("?").font(QS.num(26)).foregroundStyle(QS.paperSub))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(QS.mono(11)).tracking(1.4).foregroundStyle(QS.paperSub)
                Text(question).font(QS.text(20, weight: .black)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let value {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("+\(value)").font(QS.num(30))
                    if let base, value < base {
                        Text("\(base)").font(QS.num(16, weight: .bold)).foregroundStyle(QS.paperMuted).strikethrough()
                    }
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 12)
    }
}

/// チケットに最初から見えている事実 (血液型 A型 など) のタイル。
struct QuizTicketFactTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(QS.text(11, weight: .bold)).foregroundStyle(QS.paperSub)
            Text(value).font(QS.text(18, weight: .black)).lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(QS.paperTile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// ヒント欄の見出し「ヒント — 開くほど点が下がる   1 / 3」。
struct QuizTicketHintHeader: View {
    let opened: Int
    let total: Int

    var body: some View {
        HStack {
            Text("ヒント — 開くほど点が下がる")
            Spacer()
            Text("\(opened) / \(total)").font(QS.mono(11))
        }
        .font(QS.text(11, weight: .bold))
        .foregroundStyle(QS.paperSub)
        .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 2)
    }
}

/// ヒント 1 行。未開封は「••• / 開く −10」、開封後は中身と差し引いた点。
struct QuizTicketHintRow<Revealed: View>: View {
    let number: Int
    let label: String
    /// 開くと下がる点 (開封済みなら下がった点)。
    let cost: Int
    let isOpen: Bool
    var isNew = false
    var isFirst = false
    let onOpen: () -> Void
    @ViewBuilder let revealed: () -> Revealed

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", number)).font(QS.mono(11)).foregroundStyle(QS.paperSub)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(label).font(QS.text(11, weight: .bold)).foregroundStyle(QS.paperSub)
                    if isNew {
                        Text("NEW").font(QS.mono(9))
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(QS.paperInk, lineWidth: 1))
                    }
                }
                if isOpen {
                    revealed()
                } else {
                    Text("••••••").font(QS.text(16, weight: .black)).tracking(2).foregroundStyle(QS.paperMuted)
                        .accessibilityLabel("未開封")
                }
            }
            Spacer(minLength: 6)
            if isOpen {
                Text("−\(cost)").font(QS.num(18)).foregroundStyle(QS.paperSub)
            } else {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        Text("開く").font(QS.text(14, weight: .bold))
                        Text("−\(cost)").font(QS.num(18)).foregroundStyle(QS.paperTile.opacity(0.85))
                    }
                    .foregroundStyle(QS.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(QS.paperInk, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label)のヒントを開く。\(cost)点下がります")
            }
        }
        .padding(.leading, 18).padding(.trailing, isOpen ? 18 : 10)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .background(isNew ? QS.paperHighlight : .clear)
        .overlay(alignment: .top) {
            if !isFirst { Rectangle().fill(QS.paperLine).frame(height: 1) }
        }
    }
}

/// 開いたヒントの中身 (文字)。
struct QuizTicketHintValue: View {
    let text: String
    var body: some View {
        Text(text).font(QS.text(18, weight: .black)).lineLimit(2).minimumScaleFactor(0.7)
    }
}

/// 開いたヒントの中身 (イメージカラー)。
struct QuizTicketColorValue: View {
    let hex: String
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hexString: hex))
                .frame(width: 44, height: 16)
            Text(hex.uppercased()).font(QS.mono(13))
        }
        .padding(.top, 2)
    }
}

// MARK: - 4 択

struct QuizStageChoice: Identifiable {
    let id: String
    let title: String
}

/// A〜D の 4 択 (2 列)。押したら確定。
struct QuizStageChoiceGrid: View {
    let choices: [QuizStageChoice]
    var columns = 2
    /// 50:50 などで消した選択肢 (押せなくし、取り消し線で薄く見せる)。
    var eliminated: Set<String> = []
    let onPick: (QuizStageChoice) -> Void

    private static let letters = ["A", "B", "C", "D", "E", "F"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { i, choice in
                let isOut = eliminated.contains(choice.id)
                Button { onPick(choice) } label: {
                    HStack(spacing: 10) {
                        Text(Self.letters[i % Self.letters.count]).font(QS.mono(12)).foregroundStyle(QS.faint)
                        Text(choice.title)
                            .font(QS.text(16, weight: .bold))
                            .foregroundStyle(QS.ink)
                            .strikethrough(isOut, color: QS.faint)
                            .lineLimit(columns == 1 ? 3 : 2).minimumScaleFactor(0.7)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(QS.line, lineWidth: 1))
                    .contentShape(Rectangle())
                    .opacity(isOut ? 0.35 : 1)
                }
                .buttonStyle(QuizPressStyle())
                .disabled(isOut)
                .animation(.easeInOut(duration: 0.2), value: isOut)
            }
        }
    }
}

/// 押している間だけ少し沈む。
struct QuizPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 正解 / 不正解

/// 解答直後に出す大きなカード。
struct QuizVerdict {
    let isCorrect: Bool
    let number: Int
    /// 正解の名前 (アイドル名・曲名)。
    let answerName: String
    /// 正解の色 (アイドルのイメージカラー)。曲など色が無いときは nil。
    let answerHex: String?
    /// 獲得点・ヒント無しの点・開いたヒント数。
    let earned: Int
    let base: Int
    let hints: Int
    /// 不正解のとき選んだもの。
    let pickedName: String?
    /// 正解の補足 (プロフィールの要約・収録CD など)。
    let detail: String?
    /// 正解の横に出すジャケット (イントロドン)。
    var artworkURL: URL? = nil
    /// 点の内訳 (+70 / BASE / HINT) を出すか。1 問 1 点の遊びでは出さない。
    var showsPoints = true
}

struct QuizVerdictCard: View {
    let verdict: QuizVerdict
    @State private var appeared = false

    private var cardColor: Color {
        verdict.answerHex.map { Color(hexString: $0, default: QS.ink) } ?? QS.ink
    }

    var body: some View {
        Group {
            if verdict.isCorrect { correct } else { wrong }
        }
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) { appeared = true }
        }
    }

    private var correct: some View {
        let fg = ColorMath.onColor(cardColor)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(format: "Q.%02d — CORRECT", verdict.number)).font(QS.mono(12)).tracking(1.4)
                Spacer()
                Image(systemName: "checkmark.circle").font(.system(size: 28, weight: .semibold))
            }
            Text("正解！").font(QS.text(68, weight: .black)).minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: 12) {
                if let url = verdict.artworkURL { QuizVerdictArtwork(url: url, size: 64) }
                Text(verdict.answerName).font(QS.text(26, weight: .black)).lineLimit(2).minimumScaleFactor(0.6)
                if let hex = verdict.answerHex {
                    Text(hex.uppercased()).font(QS.mono(12))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(fg, lineWidth: 1.5))
                }
            }
            if verdict.showsPoints {
                DashedRule(color: fg.opacity(0.45))
                points
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 22)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(verdict.showsPoints ? "正解。\(verdict.answerName)。\(verdict.earned)点" : "正解。\(verdict.answerName)")
    }

    private var points: some View {
        HStack(alignment: .bottom) {
            Text("+\(verdict.earned)").font(QS.num(110, weight: .black)).lineLimit(1).minimumScaleFactor(0.5)
            Spacer(minLength: 8)
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow { Text("BASE").gridColumnAlignment(.leading); Text("+\(verdict.base)") }
                if verdict.hints > 0 {
                    GridRow { Text("HINT ×\(verdict.hints)").gridColumnAlignment(.leading); Text("−\(verdict.base - verdict.earned)") }
                }
            }
            .font(QS.mono(12))
            .padding(.bottom, 6)
        }
    }

    private var wrong: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(format: "Q.%02d — MISS", verdict.number)).font(QS.mono(12)).tracking(1.4)
                Spacer()
                Image(systemName: "xmark.circle").font(.system(size: 28, weight: .semibold))
            }
            .foregroundStyle(QS.dim)
            HStack(alignment: .bottom) {
                Text("不正解").font(QS.text(58, weight: .black)).foregroundStyle(QS.dim).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                if verdict.showsPoints {
                    Text("+0").font(QS.num(52, weight: .black)).foregroundStyle(QS.faint)
                }
            }
            if let picked = verdict.pickedName {
                HStack(spacing: 10) {
                    Text("あなたの回答").font(QS.text(13, weight: .bold))
                    Text(picked).font(QS.text(16, weight: .bold)).strikethrough().lineLimit(1)
                }
                .foregroundStyle(QS.dim)
            }
            DashedRule(color: QS.line)
            VStack(alignment: .leading, spacing: 10) {
                Text("正解は").font(QS.text(13, weight: .bold)).foregroundStyle(QS.dim)
                let fg = ColorMath.onColor(cardColor)
                HStack(spacing: 12) {
                    if let url = verdict.artworkURL { QuizVerdictArtwork(url: url, size: 52) }
                    Text(verdict.answerName).font(QS.text(26, weight: .black)).lineLimit(2).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    if let hex = verdict.answerHex {
                        Text(hex.uppercased()).font(QS.mono(12))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .overlay(Capsule().strokeBorder(fg, lineWidth: 1.5))
                    }
                }
                .foregroundStyle(fg)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let detail = verdict.detail, !detail.isEmpty {
                    Text(detail).font(QS.text(12)).foregroundStyle(QS.dim).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 22)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(QS.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("不正解。正解は\(verdict.answerName)")
    }
}

/// 判定カードに添えるジャケット。
private struct QuizVerdictArtwork: View {
    let url: URL
    let size: CGFloat
    var body: some View {
        ArtworkImageView(url: url, size: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct DashedRule: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .frame(height: 1.5)
    }
}

/// 解答後の「スコア 300 → 370」「連続正解 4」。
struct QuizVerdictStats: View {
    let before: Int
    let after: Int
    let streak: Int

    var body: some View {
        HStack(spacing: 10) {
            tile(label: "スコア") {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(before)").font(QS.num(20)).foregroundStyle(QS.faint)
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(QS.faint)
                    Text("\(after)").font(QS.num(30))
                }
            }
            tile(label: "連続正解") {
                Text("\(streak)").font(QS.num(30))
            }
        }
    }

    private func tile<V: View>(label: String, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
            value().foregroundStyle(QS.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 生成りの大きなボタン (次の問題へ / もう一度)。
struct QuizStagePrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var trailingArrow = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 16, weight: .bold)) }
                Text(title).font(QS.text(18, weight: .black))
                if trailingArrow { Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)) }
            }
            .foregroundStyle(QS.bg)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(QS.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(QuizPressStyle())
    }
}

/// 枠だけのボタン (一覧へ など)。
struct QuizStageSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(QS.text(15, weight: .bold)).foregroundStyle(QS.ink)
                .frame(maxWidth: .infinity, minHeight: 58)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(QS.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(QuizPressStyle())
    }
}

/// 解答後の「次の問題へ / 結果を見る」。
struct QuizStageNextButton: View {
    let isLastQuestion: Bool
    let onNext: () -> Void
    let onFinish: () -> Void

    var body: some View {
        QuizStagePrimaryButton(title: isLastQuestion ? "結果を見る" : "次の問題へ", trailingArrow: true) {
            if isLastQuestion { onFinish() } else { onNext() }
        }
    }
}

// MARK: - 結果

/// 結果画面で「見直す」に並べる 1 問。
struct QuizMissItem: Identifiable {
    let id: String
    let number: Int
    let title: String
    let hex: String?
    /// 選んでしまったもの。
    let picked: String?
}

struct QuizStageResultView: View {
    let result: QuizSessionResult
    let kind: GameKind
    let isNewBest: Bool
    /// 記録する前の自己ベスト (初回は nil)。
    let previousBest: Int?
    /// 全問ぶんのペンライト (点灯 / 消灯)。
    let slots: [QuizPenlight]
    let longestStreak: Int
    let misses: [QuizMissItem]
    let onReplay: () -> Void
    let onClose: () -> Void

    @State private var appeared = false

    private var litCount: Int {
        slots.filter { if case .lit = $0 { return true } else { return false } }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            ticket
            // 全曲チャレンジのように問題数が多いと 1 列に並びきらないので出さない。
            if !slots.isEmpty && slots.count <= 20 { setlist }
            if !misses.isEmpty { missList }
            HStack(spacing: 10) {
                QuizStageSecondaryButton(title: "一覧へ", action: onClose)
                QuizStagePrimaryButton(title: "もう一度", systemImage: "arrow.counterclockwise", action: onReplay)
                    .layoutPriority(1)
            }
            .padding(.top, 8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.1)) { appeared = true }
        }
    }

    private var ticket: some View {
        QuizTicket {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GRADE").font(QS.mono(11)).tracking(1.6).foregroundStyle(QS.paperSub)
                    Text(result.grade.label)
                        .font(QS.num(140, weight: .black))
                        .lineLimit(1)
                        .scaleEffect(appeared ? 1 : 1.6)
                        .opacity(appeared ? 1 : 0)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("SCORE").font(QS.mono(11)).tracking(1.6).foregroundStyle(QS.paperSub)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(result.points)").font(QS.num(58, weight: .black))
                        Text("/ \(result.maxPoints) pt").font(QS.text(13, weight: .bold)).foregroundStyle(QS.paperSub)
                    }
                    Text("\(result.correct) / \(result.questions) 正解 · 最大 \(longestStreak) 連続")
                        .font(QS.text(13, weight: .bold))
                    if isNewBest { bestStamp.padding(.top, 4) }
                    Text(result.comment).font(QS.text(12)).foregroundStyle(QS.paperSub)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            QuizTicketNotch()
            gradeLadder.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 14)
        }
    }

    private var bestStamp: some View {
        VStack(spacing: 1) {
            Text("自己ベスト更新").font(QS.text(13, weight: .black))
            if let previousBest {
                Text("\(previousBest) → \(result.points)").font(QS.mono(11))
            }
        }
        .foregroundStyle(QS.stamp)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(QS.stamp, lineWidth: 2))
        .rotationEffect(.degrees(-5))
        .scaleEffect(appeared ? 1 : 1.8)
        .opacity(appeared ? 1 : 0)
    }

    /// グレードの目安 (正答率の閾値はコアの `QuizGrade::from_rate` と同じ)。
    private var gradeLadder: some View {
        let rungs: [GradeRung] = [.init(grade: .s, range: "95%〜"), .init(grade: .a, range: "80%〜"),
                                  .init(grade: .b, range: "60%〜"), .init(grade: .c, range: "40%〜"),
                                  .init(grade: .d, range: "〜39%")]
        return HStack(spacing: 6) {
            ForEach(rungs, id: \.range) { rung in
                let current = rung.grade == result.grade
                VStack(spacing: 1) {
                    Text(rung.grade.label).font(QS.num(22))
                    Text(rung.range).font(QS.mono(10))
                }
                .foregroundStyle(current ? QS.ink : QS.paperSub)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(current ? QS.paperInk : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private struct GradeRung {
        let grade: QuizGrade
        let range: String
    }

    private var setlist: some View {
        VStack(spacing: 10) {
            HStack {
                Text("今回のセトリ")
                Spacer()
                Text("\(litCount) 本点灯")
            }
            .font(QS.text(12, weight: .bold))
            .foregroundStyle(QS.dim)
            QuizPenlightRow(slots: slots, numbered: true)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slots.count)問中\(litCount)問正解")
    }

    private var missList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("見直す").font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            ForEach(Array(misses.enumerated()), id: \.element.id) { i, miss in
                HStack(spacing: 12) {
                    Circle().fill(miss.hex.map { Color(hexString: $0, default: QS.line) } ?? QS.line)
                        .frame(width: 22, height: 22)
                    Text(String(format: "Q.%02d", miss.number)).font(QS.mono(11)).foregroundStyle(QS.dim)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(miss.title).font(QS.text(15, weight: .bold)).foregroundStyle(QS.ink).lineLimit(1)
                        if let picked = miss.picked {
                            Text("あなた: \(picked)").font(QS.text(11)).foregroundStyle(QS.faint).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .overlay(alignment: .top) {
                    if i > 0 { Rectangle().fill(QS.rowLine).frame(height: 1) }
                }
            }
        }
        .padding(.bottom, 4)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 画面の骨組み

/// ステージ画面の骨組み。ナビゲーションバーに「ゲーム名 / Q.04 / 10」と SCORE を置き、
/// 結果画面では「RESULT / ゲーム名 · 全10問」に替える。本文はスクロールする縦並び。
enum QuizStageHeader {
    case question(current: Int, total: Int, points: Int)
    case result(total: Int)
    /// 読み込み中・出題できないとき。
    case none
}

struct QuizStageScaffold<Content: View, Trailing: View>: View {
    let title: String
    let header: QuizStageHeader
    let onClose: () -> Void
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 34)
        }
        .quizStage(onClose: onClose)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { principal }
            ToolbarItem(placement: .topBarTrailing) {
                switch header {
                case .question(_, _, let points): QuizStageScore(points: points)
                default: trailing()
                }
            }
        }
    }

    @ViewBuilder
    private var principal: some View {
        switch header {
        case .question(let current, let total, _):
            QuizStageTitle(title: title, current: current, total: total)
        case .result(let total):
            VStack(spacing: 1) {
                Text("RESULT").font(QS.num(24)).tracking(1)
                Text("\(title) · 全\(total)問").font(QS.text(11, weight: .bold)).foregroundStyle(QS.dim)
            }
            .foregroundStyle(QS.ink)
        case .none:
            Text(title).font(QS.text(15, weight: .bold)).foregroundStyle(QS.ink)
        }
    }
}

extension QuizStageScaffold where Trailing == EmptyView {
    init(title: String, header: QuizStageHeader, onClose: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, header: header, onClose: onClose, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - 1 問ごとの記録

/// 解答済みの 1 問。ペンライト・連続正解・結果画面の「見直す」の元になる。
struct QuizStagePlay: Codable {
    let number: Int
    let isCorrect: Bool
    let answerName: String
    /// 答えの色 (アイドルのイメージカラー)。無ければペンライトは帯の色を順に使う。
    let answerHex: String?
    let pickedName: String?
}

extension Array where Element == QuizStagePlay {
    private func penlightColor(_ i: Int) -> Color {
        let fallback = QS.penlight(i)
        return self[i].answerHex.map { Color(hexString: $0, default: fallback) } ?? fallback
    }

    func penlights(total: Int, answering: Bool) -> [QuizPenlight] {
        QuizPenlight.slots(results: indices.map { self[$0].isCorrect ? penlightColor($0) : nil },
                           total: total, answering: answering)
    }

    var streak: Int { QuizStreak.current(map(\.isCorrect)) }
    var longestStreak: Int { QuizStreak.longest(map(\.isCorrect)) }
    var streakBrokeAt: Int? { QuizStreak.brokeAt(map(\.isCorrect)) }

    var misses: [QuizMissItem] {
        filter { !$0.isCorrect }.map {
            QuizMissItem(id: "\($0.number)", number: $0.number, title: $0.answerName,
                         hex: $0.answerHex, picked: $0.pickedName)
        }
    }

    /// 「セトリ 3 / 10 曲目まで点灯」。
    func setlistCaption(total: Int) -> String {
        "セトリ \(count) / \(total) 曲目まで点灯"
    }
}

extension GameProgressStore {
    /// 記録する前の自己ベスト点 (未プレイなら nil)。結果画面の「700 → 755」に使う。
    func previousBestScore(for kind: GameKind) -> Int? {
        let r = record(for: kind)
        return r.playCount > 0 ? Int(r.bestScore) : nil
    }
}

/// 不正解のあとに添える一言。
struct QuizVerdictFootnote: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(QS.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text("この問題は結果画面から見直せます").font(QS.text(13, weight: .bold)).foregroundStyle(QS.ink)
                Text("次に正解すると連続記録がまた始まります").font(QS.text(11)).foregroundStyle(QS.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 曲ものチケット (ソロ曲・歌詞)

/// 「SOLO SONG ・ +100 / この曲を歌っているのは？」のチケット上部。本文 (曲名・歌詞) は content に置く。
struct QuizTicketTitleBlock<Content: View>: View {
    let label: String
    let question: String
    let value: Int
    let base: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                Text(label).font(QS.mono(11)).tracking(1.4).foregroundStyle(QS.paperSub)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("+\(value)").font(QS.num(22)).contentTransition(.numericText())
                    if value < base {
                        Text("\(base)").font(QS.num(15, weight: .bold)).foregroundStyle(QS.paperSub).strikethrough()
                    }
                }
                .accessibilityLabel("正解で\(value)点")
            }
            Text(question).font(QS.text(15, weight: .bold)).foregroundStyle(QS.paperSub)
            content()
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 18)
    }
}

/// 横に並ぶヒントのタイル。未開封は点線枠の「収録CD −10」、開封済みは中身、まだ開けないものは薄く。
struct QuizTicketHintTile: View {
    enum Phase {
        case available(cost: Int, action: () -> Void)
        case open(value: String)
        /// 開いた色ヒント (イメージカラーなど)。色の帯と名前を出す。
        case openSwatch(hex: String, label: String)
        case locked(cost: Int)
    }

    let title: String
    let phase: Phase

    var body: some View {
        switch phase {
        case .available(let cost, let action):
            Button(action: action) {
                VStack(spacing: 0) {
                    Text(title).font(QS.text(13, weight: .bold))
                    Text("−\(cost)").font(QS.num(16)).foregroundStyle(QS.paperSub)
                }
                .foregroundStyle(QS.paperInk)
                .frame(maxWidth: .infinity, minHeight: 56)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(QS.paperMuted, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .contentShape(Rectangle())
            }
            .buttonStyle(QuizPressStyle())
            .accessibilityLabel("\(title)のヒントを開く。\(cost)点下がります")
        case .open(let value):
            VStack(spacing: 0) {
                Text(title).font(QS.text(11, weight: .bold)).foregroundStyle(QS.paperSub)
                Text(value).font(QS.text(15, weight: .black)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(QS.paperTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .openSwatch(let hex, let label):
            VStack(spacing: 4) {
                Text(title).font(QS.text(11, weight: .bold)).foregroundStyle(QS.paperSub)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hexString: hex))
                    .frame(width: 44, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(QS.paperLine, lineWidth: 1))
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(QS.paperTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(label)")
        case .locked(let cost):
            VStack(spacing: 0) {
                Text(title).font(QS.text(13, weight: .bold))
                Text("−\(cost)").font(QS.num(16))
            }
            .foregroundStyle(QS.paperMuted)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(QS.paperLine, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .accessibilityLabel("\(title)のヒント (前のヒントを開くと開けます)")
        }
    }
}

/// ヒントタイルの並び (見出し付き)。`columns` を渡すとその列数で折り返す (ヒントが多いクイズ用)。
struct QuizTicketHintTiles<Tiles: View>: View {
    var showsHeading = true
    var columns: Int? = nil
    @ViewBuilder let tiles: () -> Tiles

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeading {
                Text("ヒント — 開くほど点が下がる").font(QS.text(11, weight: .bold)).foregroundStyle(QS.paperSub)
                    .padding(.leading, 8)
            }
            if let columns {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                    tiles()
                }
            } else {
                HStack(spacing: 6) { tiles() }
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 14)
    }
}
