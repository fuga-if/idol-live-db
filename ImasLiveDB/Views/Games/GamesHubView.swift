import SwiftUI

/// クイズ・ゲームのハブ。プロデュース → 「クイズ・ゲーム」から push。
/// イントロドン／アイドル当て／ソロ曲／メンバーカラー合わせ／歌詞クイズを束ねる。
///
/// 一覧そのものはアプリ本体と同じ明るい画面のまま、上にだけ「QUIZ STAGE」の
/// チケット (ゲーム画面と同じ暗いステージ色) を置いて、ここから先が会場だと分かるようにする。
struct GamesHubView: View {
    @State private var progress = GameProgressStore.shared
    @State private var resumeStore = QuizResumeStore.shared
    @State private var sortStore = SortMakerStore.shared
    @State private var tierStore = TierListStore.shared
    /// 「再開」を押してから遷移先へ進む (ボタンと NavigationLink を入れ子にしないため)。
    @State private var resumeTarget: QuizSuspended?

    /// ハブに並べるゲーム定義 (表示順)。
    private struct GameEntry {
        let kind: GameKind
        let systemImage: String
        let title: String
        let blurb: String
    }

    /// 歌詞クイズは歌詞タブと同じ根拠 (`LyricsFeature`) で出し分ける。
    private let entries: [GameEntry] = Self.allEntries.filter { $0.kind != .lyricsQuiz || LyricsFeature.isAvailable }

    private static let allEntries: [GameEntry] = [
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
                sortMakerList
            }
            .padding(DS.sp5)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("クイズ・ゲーム")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: Binding(
            get: { resumeTarget != nil },
            set: { if !$0 { resumeTarget = nil } }
        )) {
            if let resumeTarget { QuizResumeDestination(suspended: resumeTarget) }
        }
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
        Self.allEntries.first { $0.kind == kind }?.title ?? ""
    }

    private var stageTicket: some View {
        ImasStagePreviewCard {
            VStack(spacing: 0) {
                // アプリアイコンの帯 (ペンライトの色)。
                HStack(spacing: 0) {
                    ForEach(0..<QS.penlights.count, id: \.self) { i in QS.penlights[i] }
                }
                .frame(height: 6)

                VStack(alignment: .leading, spacing: DS.sp4) {
                    HStack(spacing: DS.sp3) {
                        ImasStageWordmark(text: "@")
                        Text("QUIZ STAGE").font(QS.mono(11)).tracking(1.3).foregroundStyle(QS.dim)
                    }
                    // 累計ポイントは桁が伸びる (4桁以上) ので、3枚の等幅タイルに詰めると
                    // 393pt 幅でも折り返す。左に大きく・右はプレイ回数/最高グレードを縦に積む。
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: DS.sp1) {
                            Text("累計ポイント").font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
                            HStack(alignment: .lastTextBaseline, spacing: DS.sp2) {
                                Text(progress.totalPoints.formatted()).font(QS.num(48))
                                    .contentTransition(.numericText())
                                    .lineLimit(1).minimumScaleFactor(0.5)
                                Text("pt").font(QS.text(13, weight: .bold)).foregroundStyle(QS.dim)
                            }
                        }
                        Spacer(minLength: DS.sp3)
                        VStack(alignment: .trailing, spacing: DS.sp2) {
                            HStack(spacing: DS.sp2) {
                                Text("プレイ")
                                Text("\(progress.totalPlays)").fontWeight(.bold).foregroundStyle(QS.ink)
                                Text("回")
                            }
                            HStack(alignment: .lastTextBaseline, spacing: DS.sp2) {
                                Text("最高グレード")
                                Text(topGrade?.label ?? "—").font(QS.num(18)).foregroundStyle(QS.ink)
                            }
                        }
                        .font(QS.text(12))
                        .foregroundStyle(QS.dim)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, DS.sp6).padding(.top, DS.sp5).padding(.bottom, DS.sp5)

                // 切り取り線 (両端は一覧の背景色で欠ける)。
                QuizTicketNotch(background: DS.bg)

                resumeRow
            }
            .foregroundStyle(QS.ink)
        }
    }

    /// チケットの下半分。中断したクイズがあれば「つづきから」、無ければ連続プレイ日数。
    @ViewBuilder
    private var resumeRow: some View {
        HStack(spacing: DS.sp4) {
            if let s = resumeStore.latest, s.kind != .lyricsQuiz || LyricsFeature.isAvailable {
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text("つづきから").font(QS.text(11)).foregroundStyle(QS.dim)
                    Text("\(title(s.kind)) · " + String(format: "Q.%02d / %d", min(s.plays.count + 1, s.total), s.total))
                        .font(QS.text(15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: DS.sp3)
                QuizStagePrimaryButton(title: "再開", compact: true) {
                    AppAnalytics.tap("games_hub.resume")
                    resumeTarget = s
                }
            } else {
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text("連続プレイ").font(QS.text(11)).foregroundStyle(QS.dim)
                    Text(progress.displayStreak > 0 ? "\(progress.displayStreak) 日つづけて遊んでいます"
                                                    : "今日の 1 ゲームで連続記録が始まります")
                        .font(QS.text(15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(QS.ink)
        .padding(.leading, DS.sp6).padding(.trailing, DS.sp4)
        .frame(minHeight: 68)
    }

    // MARK: - ゲーム一覧

    private var gameList: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "ゲーム", count: "\(entries.count)")
            ImasCardList {
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

    // MARK: - ソートメーカー

    /// 点数を競うゲームではないので、QUIZ STAGE の記録とは別の節に置く。
    private var sortMakerList: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "ソートメーカー・ティアー表")
            ImasCardList {
                ForEach(Array(SortMakerSubject.allCases.enumerated()), id: \.element) { i, subject in
                    if i > 0 { ImasRowDivider(inset: 68) }
                    NavigationLink {
                        SortMakerSetupView(subject: subject)
                    } label: {
                        sortMakerRow(subject)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(SortMakerSubject.allCases) { subject in
                    ImasRowDivider(inset: 68)
                    NavigationLink {
                        SortMakerSetupView(subject: subject, purpose: .tier)
                    } label: {
                        tierListRow(subject)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 一覧の行 (3 種とも同じ `ImasRow` の形にまとめる)

    private func sortMakerRow(_ subject: SortMakerSubject) -> some View {
        let saved = sortStore.session(subject)
        let percent = (saved.map { !$0.isFinished }) == true ? saved?.replay().progressPercent : nil
        return hubRow(systemImage: subject.systemImage, title: subject.title,
                      subtitle: sortMakerBlurb(subject, saved),
                      state: percent.map { statusBlock(primary: "\($0)%") })
    }

    private func tierListRow(_ subject: SortMakerSubject) -> some View {
        let count = tierStore.boards(for: subject).count
        return hubRow(systemImage: "square.stack.3d.up", title: subject.tierTitle,
                      subtitle: count > 0 ? "保存 \(count) 件" : "段に振り分けて1枚の画像に",
                      state: nil)
    }

    private func sortMakerBlurb(_ subject: SortMakerSubject, _ saved: SortMakerSession?) -> String {
        if let saved {
            if saved.isFinished, let top = saved.topNames.first { return "前回の1位: \(top)" }
            if !saved.isFinished { return "つづきから" }
        }
        return subject == .song ? "2曲ずつ選んで好きな曲の順位を決める" : "2人ずつ選んで好きなアイドルの順位を決める"
    }

    private func gameRow(_ entry: GameEntry) -> some View {
        let rec = progress.record(for: entry.kind)
        let state: AnyView?
        if let s = resumeStore.suspended(entry.kind) {
            state = statusBlock(primary: "プレイ中", secondary: String(format: "Q.%02d", min(s.plays.count + 1, s.total)))
        } else if rec.hasPlayed, let grade = bestGrade(entry.kind) {
            state = statusBlock(primary: grade.label, secondary: bestLabel(entry.kind, rec), primaryFont: QS.num(22))
        } else {
            state = statusBlock(primary: "未プレイ")
        }
        return hubRow(systemImage: entry.systemImage,
                      customIcon: entry.kind == .colorMatch ? AnyView(ImasStageColorGridIcon()) : nil,
                      title: entry.title, subtitle: entry.blurb, state: state)
    }

    /// 行の右に出す状態 (プレイ中・自己ベスト・進み具合)。1〜2 行、色は灰。
    private func statusBlock(primary: String, secondary: String? = nil, primaryFont: Font = .imasCaption.weight(.semibold)) -> AnyView {
        AnyView(
            VStack(alignment: .trailing, spacing: DS.sp1) {
                Text(primary).font(primaryFont).foregroundStyle(DS.ink2)
                if let secondary {
                    Text(secondary).font(.imasCaption2).foregroundStyle(DS.ink3)
                }
            }
        )
    }

    /// ゲーム・ソートメーカー・ティアー表、3 つの入口が同じ行の形になるようにまとめたもの。
    /// 記号は地を敷かず (`ImasIconTile`)、右は自己ベスト・進み具合などの状態と矢印。
    private func hubRow(systemImage: String, customIcon: AnyView? = nil, title: String, subtitle: String,
                        state: AnyView?) -> some View {
        ImasRow(
            title: title,
            subtitle: subtitle,
            leading: customIcon.map { ImasRowLeading.custom($0, width: 40) } ?? .icon(systemImage, tone: .solid),
            trailing: .custom(AnyView(
                HStack(spacing: DS.Space.gap) {
                    state
                    ImasRowChevron()
                }
            )),
            density: .regular
        )
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

/// 中断したクイズの再開先。ゲーム一覧とプロデュースの「つづきから」で共有する。
struct QuizResumeDestination: View {
    let suspended: QuizSuspended

    var body: some View {
        let s = suspended
        switch s.kind {
        case .idolQuiz: IdolQuizView(selectedBrandIds: Set(s.brandIds), resume: s)
        case .songSingerQuiz: SongSingerQuizView(selectedBrandIds: Set(s.brandIds), resume: s)
        case .lyricsQuiz: LyricsQuizResumeView(suspended: s)
        case .setlistQuiz: SetlistQuizView(selectedBrandIds: Set(s.brandIds), resume: s)
        case .colorMatch: ColorMatchGameView(resume: s)
        case .introDon: IntroDonHomeView()
        }
    }
}
