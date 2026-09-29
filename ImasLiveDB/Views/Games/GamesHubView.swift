import SwiftUI

/// クイズ・ゲームのハブ。プロデュース → 「クイズ・ゲーム」から push。
/// イントロドン／アイドル当て／ソロ曲／メンバーカラー合わせ／歌詞クイズを束ねる。
///
/// 一覧そのものはアプリ本体と同じ明るい画面のまま、上にだけ「QUIZ STAGE」の
/// チケット (ゲーム画面と同じ暗いステージ色) を置いて、ここから先が会場だと分かるようにする。
struct GamesHubView: View {
    @State private var progress = GameProgressStore.shared
    @State private var resumeStore = QuizResumeStore.shared

    /// ハブに並べるゲーム定義 (表示順)。
    private struct GameEntry {
        let kind: GameKind
        let systemImage: String
        let title: String
        let blurb: String
    }

    private let entries: [GameEntry] = [
        .init(kind: .idolQuiz, systemImage: "person.fill.questionmark", title: "アイドル当て",
              blurb: "プロフィールから当てる"),
        .init(kind: .songSingerQuiz, systemImage: "music.microphone", title: "ソロ曲クイズ",
              blurb: "曲名から歌っているアイドルを"),
        .init(kind: .lyricsQuiz, systemImage: "text.quote", title: "歌詞クイズ",
              blurb: "曲名当て／続きの行当て"),
        .init(kind: .setlistQuiz, systemImage: "list.number", title: "セトリ当て",
              blurb: "セトリの空欄に入る曲を当てる"),
        .init(kind: .introDon, systemImage: "music.note.list", title: "イントロドン",
              blurb: "イントロを聴いて曲を当てる"),
        .init(kind: .colorMatch, systemImage: "paintpalette.fill", title: "メンバーカラー合わせ",
              blurb: "名前からイメージカラーを"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                stageTicket
                gameList
            }
            .padding(DS.sp5)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("クイズ・ゲーム")
        .navigationBarTitleDisplayMode(.large)
        .trackScreen("games_hub")
    }

    // MARK: - QUIZ STAGE チケット

    /// 自己ベストの正答率をグレードにしたもの (未プレイは nil)。
    private func bestGrade(_ kind: GameKind) -> QuizGrade? {
        progress.bestRatePercent(for: kind).map { quizGradeForRate(ratePercent: UInt32(clamping: $0)) }
    }

    /// 全ゲームを通した最高グレード (自己ベストの正答率がいちばん高いもの)。
    private var topGrade: QuizGrade? {
        entries.compactMap { progress.bestRatePercent(for: $0.kind) }.max()
            .map { quizGradeForRate(ratePercent: UInt32(clamping: $0)) }
    }

    private func title(_ kind: GameKind) -> String {
        entries.first { $0.kind == kind }?.title ?? ""
    }

    private var stageTicket: some View {
        VStack(spacing: 0) {
            // アプリアイコンの帯 (ペンライトの色)。
            HStack(spacing: 0) {
                ForEach(0..<QS.penlights.count, id: \.self) { i in QS.penlights[i] }
            }
            .frame(height: 6)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("@").font(QS.text(14, weight: .black)).foregroundStyle(QS.bg)
                        .frame(width: 22, height: 22)
                        .background(QS.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("QUIZ STAGE").font(QS.mono(11)).tracking(1.3).foregroundStyle(QS.dim)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("累計ポイント").font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(progress.totalPoints.formatted()).font(QS.num(56))
                                .contentTransition(.numericText())
                            Text("pt").font(QS.text(14, weight: .bold)).foregroundStyle(QS.dim)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("プレイ")
                            Text("\(progress.totalPlays)").fontWeight(.bold).foregroundStyle(QS.ink)
                            Text("回")
                        }
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("最高グレード")
                            Text(topGrade?.label ?? "—").font(QS.num(18)).foregroundStyle(QS.ink)
                        }
                    }
                    .font(QS.text(12))
                    .foregroundStyle(QS.dim)
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)

            // 切り取り線 (両端は一覧の背景色で欠ける)。
            HStack(spacing: 0) {
                UnevenRoundedRectangle(bottomTrailingRadius: 9, topTrailingRadius: 9)
                    .fill(DS.bg).frame(width: 9, height: 18)
                Rectangle().fill(.clear).frame(height: 1.5)
                    .overlay(Line().stroke(QS.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .padding(.horizontal, 6)
                UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9)
                    .fill(DS.bg).frame(width: 9, height: 18)
            }
            .accessibilityHidden(true)

            resumeRow
        }
        .foregroundStyle(QS.ink)
        .background(QS.bg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// チケットの下半分。中断したクイズがあれば「つづきから」、無ければ連続プレイ日数。
    @ViewBuilder
    private var resumeRow: some View {
        HStack(spacing: 12) {
            if let s = resumeStore.latest {
                VStack(alignment: .leading, spacing: 2) {
                    Text("つづきから").font(QS.text(11)).foregroundStyle(QS.dim)
                    Text("\(title(s.kind)) · " + String(format: "Q.%02d / %d", min(s.plays.count + 1, s.total), s.total))
                        .font(QS.text(15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                NavigationLink {
                    resumeDestination(s)
                } label: {
                    Text("再開").font(QS.text(15, weight: .bold)).foregroundStyle(QS.bg)
                        .padding(.horizontal, 20).frame(height: 44)
                        .background(QS.ink, in: Capsule())
                }
                .buttonStyle(QuizPressStyle())
                .simultaneousGesture(TapGesture().onEnded { AppAnalytics.tap("games_hub.resume") })
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("連続プレイ").font(QS.text(11)).foregroundStyle(QS.dim)
                    Text(progress.displayStreak > 0 ? "\(progress.displayStreak) 日つづけて遊んでいます"
                                                    : "今日の 1 ゲームで連続記録が始まります")
                        .font(QS.text(15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(QS.ink)
        .padding(.leading, 20).padding(.trailing, 12)
        .frame(minHeight: 68)
    }

    @ViewBuilder
    private func resumeDestination(_ s: QuizSuspended) -> some View {
        switch s.kind {
        case .idolQuiz: IdolQuizView(selectedBrandIds: Set(s.brandIds), resume: s)
        case .songSingerQuiz: SongSingerQuizView(selectedBrandIds: Set(s.brandIds), resume: s)
        case .lyricsQuiz: LyricsQuizResumeView(suspended: s)
        case .setlistQuiz: SetlistQuizView(selectedBrandIds: Set(s.brandIds), resume: s)
        case .colorMatch: ColorMatchGameView(resume: s)
        case .introDon: IntroDonHomeView()
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }

    // MARK: - ゲーム一覧

    private var gameList: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "ゲーム", count: "\(entries.count)")
            ImasListContainer {
                ForEach(Array(entries.enumerated()), id: \.element.kind) { i, entry in
                    if i > 0 { ImasRowDivider(inset: 68) }
                    NavigationLink {
                        destination(for: entry.kind)
                    } label: {
                        gameRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func gameRow(_ entry: GameEntry) -> some View {
        let rec = progress.record(for: entry.kind)
        return HStack(spacing: 12) {
            icon(entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.imasBody.weight(.semibold)).foregroundStyle(DS.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(entry.blurb).font(.imasFootnote).foregroundStyle(DS.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                if let s = resumeStore.suspended(entry.kind) {
                    Text("プレイ中").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink2)
                    Text(String(format: "Q.%02d", min(s.plays.count + 1, s.total))).font(.imasCaption2).foregroundStyle(DS.ink3)
                } else if rec.hasPlayed, let grade = bestGrade(entry.kind) {
                    Text(grade.label).font(QS.num(22)).foregroundStyle(DS.ink)
                    Text(bestLabel(entry.kind, rec)).font(.imasCaption2).foregroundStyle(DS.ink3)
                } else {
                    Text("未プレイ").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
                }
            }
            Image(systemName: "chevron.right")
                .font(.imasScaled(13, weight: .semibold))
                .foregroundStyle(DS.ink3)
        }
        .padding(.horizontal, DS.sp4)
        .frame(minHeight: 64)
        .background(DS.surface)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 暗いステージ色のアイコン。メンバーカラーだけ色の 2×2 にする。
    @ViewBuilder
    private func icon(_ entry: GameEntry) -> some View {
        if entry.kind == .colorMatch {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)], spacing: 3) {
                ForEach([0, 4, 2, 3], id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(QS.penlight(i)).frame(height: 9)
                }
            }
            .padding(9)
            .frame(width: 40, height: 40)
            .background(QS.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: entry.systemImage)
                .font(.imasScaled(18, weight: .semibold))
                .foregroundStyle(QS.ink)
                .frame(width: 40, height: 40)
                .background(QS.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// 最高記録の表示文字列。色合わせは正答率%、クイズ系は獲得ポイント。
    /// 正答率は保存値から引く計算なのでコア (game_progress) に委譲する
    /// (記録が無ければ nil が返るので「—」を出す)。
    private func bestLabel(_ kind: GameKind, _ rec: GameRecord) -> String {
        if kind.scoreIsPercent {
            guard let pct = progress.bestRatePercent(for: kind) else { return "—" }
            return "最高 \(pct)%"
        }
        guard rec.bestOutOf > 0 else { return "—" }
        return "最高 \(rec.bestScore) pt"
    }

    // MARK: - 遷移先

    @ViewBuilder
    private func destination(for kind: GameKind) -> some View {
        switch kind {
        case .introDon: IntroDonHomeView()
        // アイドル当て・ソロ曲はブランド絞り込み設定画面を先に挟む。
        case .idolQuiz: IdolQuizSetupView()
        case .songSingerQuiz: SongSingerQuizSetupView()
        case .colorMatch: ColorMatchGameView()
        case .lyricsQuiz: LyricsQuizSetupView()
        case .setlistQuiz: SetlistQuizSetupView()
        }
    }
}
