import SwiftUI

/// ソロ曲クイズ (ヒント式採点)。最初は「曲名だけ」で出題し、ヒントを開くほど手がかりが増える
/// 代わりに獲得点が下がる: ノーヒント 10pt から 収録CD / ブランド / イメージカラー / ジャケット / 試聴
/// それぞれのコストを引く (点数と開けられる順はコアが決める。試聴はジャケットの後)。
/// データは songs(song_type=solo) と song_artists(role=original) の事実情報のみ。
///
/// 出題の生成・選択肢の作り方・採点・母集団の条件 (原唱が単独の曲だけ / 歌手が 4 人以上) は
/// imas-core の `domain/quiz_generation.rs` にあり、Android と同じ実装を共有する。
/// この画面が担うのは描画・プレビュー再生・シード調達だけ。
struct SongSingerQuizView: View {

    /// 出題ブランド絞り込み（空集合 = 全ブランド対象）。SongSingerQuizSetupView から渡す。
    let selectedBrandIds: Set<String>

    /// 途中でやめたセッションの続き (ゲーム一覧の「つづきから」)。nil なら新しく始める。
    let resume: QuizSuspended?

    init(selectedBrandIds: Set<String> = [], resume: QuizSuspended? = nil) {
        self.selectedBrandIds = selectedBrandIds
        self.resume = resume
    }

    /// 1 セッションの出題数 (規則本体はコア。UI は総問数の表示にだけ使う)。
    private var sessionLength: Int { Int(quizSessionLength()) }

    /// 出題の index 参照元。コアが返す `answer` / `choices` はこの配列の位置を指す。
    @State private var singers: [Idol] = []
    /// 出題曲の引き当て表 (コアは曲 id だけを返す)。
    @State private var songById: [String: Song] = [:]
    /// `song_artists(role='original')` の行 (曲名かな順)。母集団の条件 (原唱が単独か・
    /// 外部演者か・ブランド一致) はコアが持つので、ここは行を並べて渡すだけ。
    @State private var rows: [SongQuizOriginalArtistRow] = []
    /// 1 ゲーム分の出題 (コアが 1 回でまとめて生成)。
    @State private var questions: [SongSingerQuizQuestion] = []
    @State private var index = 0
    @State private var selectedId: String?
    /// この問題で開いたヒント。
    @State private var opened: [SongQuizHintKind] = []
    /// いまの獲得点・見せてよいもの・まだ開けるヒント (コアが算出)。
    @State private var hint = SongSingerQuizHintState(currentValue: 0, baseValue: 0, showArtwork: false,
                                                     canPreview: false, shown: [], hints: [])
    /// ブランドヒントに出す略称 (brand id → 略称)。
    @State private var brandNames: [String: String] = [:]
    /// 解答済み問題数・正解数・累計ポイント (コアが積み上げる)。
    @State private var tally = QuizTally(asked: 0, correct: 0, points: 0)
    @State private var isLastQuestion = false
    /// 各問の記録 (ペンライト・連続正解・見直す)。
    @State private var plays: [QuizStagePlay] = []
    /// 直前の問題の判定 (解答後に出す大きなカード)。
    @State private var verdict: QuizVerdict?
    @State private var scoreBefore = 0
    @State private var result: QuizSessionResult?
    @State private var isNewBest = false
    @State private var previousBest: Int?
    @State private var isLoading = true
    /// 遊んだ曲のジャケット (シェア画像の背景)。結果が出た時点で読み込み始める。
    @State private var shareArtwork: Task<[String: UIImage], Never>?
    @State private var isPreparingShare = false
    /// このセッションの出題シード (つづきからで同じ出題を作り直す)。
    @State private var seed: UInt64 = 0
    /// `resume` は最初の 1 回だけ使う (「もう一度」は新しいセッション)。
    @State private var didUseResume = false
    @Environment(\.dismiss) private var dismiss

    private var question: SongSingerQuizQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    private var header: QuizStageHeader {
        if let result { return .result(total: Int(result.questions)) }
        guard let q = question, songById[q.songId] != nil, !isLoading else { return .none }
        return .question(current: min(plays.count + (verdict == nil ? 1 : 0), sessionLength),
                         total: sessionLength, points: Int(tally.points))
    }

    var body: some View {
        QuizStageScaffold(title: "ソロ曲クイズ", header: header, onClose: { dismiss() }, trailing: {
            if let result {
                QuizStageRoundButton(systemImage: isPreparingShare ? "hourglass" : "square.and.arrow.up",
                                     label: "結果を画像でシェア") { shareResultImage(result) }
            }
        }) {
            content
        }
        .onDisappear { MusicKitService.shared.stop() }
        .task { await load() }
        .trackScreen("song_singer_quiz")
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ImasInlineLoading(tint: QS.ink)
        } else if let result {
            QuizStageResultView(result: result, kind: .songSingerQuiz, isNewBest: isNewBest,
                                previousBest: previousBest,
                                slots: plays.penlights(total: Int(result.questions), answering: false),
                                longestStreak: plays.longestStreak, misses: plays.misses,
                                onReplay: { restart() }, onClose: { dismiss() })
        } else if let q = question, let song = songById[q.songId] {
            QuizStageProgress(slots: plays.penlights(total: sessionLength, answering: verdict == nil),
                              caption: plays.setlistCaption(total: sessionLength),
                              streak: plays.streak, streakBrokeAt: plays.streakBrokeAt)
                .padding(.bottom, 2)
            if let verdict {
                QuizVerdictCard(verdict: verdict).id(verdict.number)
                QuizVerdictStats(before: scoreBefore, after: Int(tally.points), streak: plays.streak)
                if !verdict.isCorrect { QuizVerdictFootnote() }
                QuizStageNextButton(isLastQuestion: isLastQuestion, onNext: nextQuestion, onFinish: finish)
                    .padding(.top, 4)
            } else {
                ticket(song, question: q)
                QuizStageChoiceGrid(choices: choices(q).map { QuizStageChoice(id: $0.id, title: $0.name) }) { choice in
                    if let idol = singers.first(where: { $0.id == choice.id }) { pick(idol, song: song) }
                }
                .padding(.top, 4)
            }
        } else {
            ImasEmptyState(systemImage: "music.note", title: "出題できるソロ曲が不足しています")
        }
    }

    // MARK: - チケット

    /// 曲名を大きく載せ、ジャケットを開いたら横に出す。ヒントは 3 列のタイル。
    private func ticket(_ song: Song, question q: SongSingerQuizQuestion) -> some View {
        let answer = singers.indices.contains(Int(q.answer)) ? singers[Int(q.answer)] : nil
        return QuizTicket {
            QuizTicketTitleBlock(label: "SOLO SONG", question: "この曲を歌っているのは？",
                                 value: Int(hint.currentValue), base: Int(hint.baseValue)) {
                HStack(alignment: .center, spacing: 14) {
                    if hint.showArtwork {
                        ArtworkImageView(url: URL(string: song.artworkUrl ?? ""), size: 84,
                                         previewURL: hint.canPreview ? song.previewUrl.flatMap { URL(string: $0) } : nil,
                                         songTitle: song.title, songId: song.id, seed: nil)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    Text(song.title)
                        .font(QS.text(hint.showArtwork ? 30 : 40, weight: .black))
                        .lineLimit(3).minimumScaleFactor(0.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }
            QuizTicketNotch()
            QuizTicketHintTiles(columns: 3) {
                ForEach(availableHints(song, question: q), id: \.self) { kind in
                    hintTile(kind, song: song, answer: answer)
                }
            }
        }
    }

    @ViewBuilder
    private func hintTile(_ kind: SongQuizHintKind, song: Song, answer: Idol?) -> some View {
        let title = hintTitle(kind)
        if hint.shown.contains(kind) {
            switch kind {
            case .cd: QuizTicketHintTile(title: title, phase: .open(value: song.cdTitle ?? "—"))
            case .brand: QuizTicketHintTile(title: title, phase: .open(value: answer.flatMap { brandNames[$0.brandId] } ?? "—"))
            case .color: QuizTicketHintTile(title: title, phase: .openSwatch(hex: answer?.color ?? "", label: answer?.color ?? ""))
            case .artwork: QuizTicketHintTile(title: title, phase: .open(value: "表示中"))
            case .preview: QuizTicketHintTile(title: title, phase: .open(value: "再生中"))
            }
        } else if let option = hint.hints.first(where: { $0.kind == kind }) {
            QuizTicketHintTile(title: title, phase: option.locked ? .locked(cost: Int(option.cost))
                               : .available(cost: Int(option.cost), action: { openHint(kind, song: song) }))
        }
    }

    private func hintTitle(_ kind: SongQuizHintKind) -> String {
        switch kind {
        case .cd: "収録CD"
        case .brand: "ブランド"
        case .color: "イメージカラー"
        case .artwork: "ジャケット"
        case .preview: "試聴"
        }
    }

    /// この曲で出せるヒント。データが無いもの・選択肢が全員同じブランドのときのブランドは外す。
    private func availableHints(_ song: Song, question q: SongSingerQuizQuestion) -> [SongQuizHintKind] {
        let answer = singers.indices.contains(Int(q.answer)) ? singers[Int(q.answer)] : nil
        var kinds: [SongQuizHintKind] = []
        if !(song.cdTitle ?? "").isEmpty { kinds.append(.cd) }
        if let answer, brandNames[answer.brandId] != nil,
           Set(choices(q).map(\.brandId)).count > 1 { kinds.append(.brand) }
        if !(answer?.color ?? "").isEmpty { kinds.append(.color) }
        if !(song.artworkUrl ?? "").isEmpty { kinds.append(.artwork) }
        if !(song.previewUrl ?? "").isEmpty { kinds.append(.preview) }
        return kinds
    }

    private func openHint(_ kind: SongQuizHintKind, song: Song) {
        AppAnalytics.tap("song_singer_quiz.hint_\(String(describing: kind))")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            opened.append(kind)
            refreshHint(song)
        }
        if kind == .preview, let url = song.previewUrl.flatMap({ URL(string: $0) }) {
            MusicKitService.shared.togglePreview(url: url, songId: song.id)
        }
    }

    // MARK: - 進行

    /// 選択肢に並べるアイドル (コアが返す index を引き当てる)。
    private func choices(_ q: SongSingerQuizQuestion) -> [Idol] {
        q.choices.compactMap { singers.indices.contains(Int($0)) ? singers[Int($0)] : nil }
    }

    private func pick(_ idol: Idol, song: Song) {
        guard selectedId == nil, let q = question else { return }
        AppAnalytics.tap("song_singer_quiz.answer")
        MusicKitService.shared.stop()
        selectedId = idol.id
        let answer = singers[Int(q.answer)]
        scoreBefore = Int(tally.points)
        // 正誤判定・獲得点 (開いたヒントで決まる)・積み上げはコアがまとめて返す。
        let outcome = songSingerQuizAnswer(opened: opened, pickedIdolId: idol.id,
                                           answerIdolId: answer.id, before: tally)
        isLastQuestion = outcome.isLastQuestion
        refreshHint(song)
        let number = plays.count + 1
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            tally = outcome.tally
            plays.append(QuizStagePlay(number: number, isCorrect: outcome.isCorrect,
                                       answerName: answer.name, answerHex: answer.color,
                                       pickedName: outcome.isCorrect ? nil : idol.name))
            verdict = QuizVerdict(isCorrect: outcome.isCorrect, number: number,
                                  answerName: answer.name, answerHex: answer.color,
                                  earned: Int(outcome.earnedPoints), base: Int(hint.baseValue),
                                  hints: Int(outcome.revealedHints),
                                  pickedName: outcome.isCorrect ? nil : idol.name,
                                  detail: "「\(song.title)」" + (song.cdTitle.map { " · \($0)" } ?? ""))
        }
        UINotificationFeedbackGenerator().notificationOccurred(outcome.isCorrect ? .success : .error)
        // 1 問答えるたびに途中経過を残す (× で閉じても「つづきから」で戻れる)。
        QuizResumeStore.shared.save(QuizSuspended(
            kind: .songSingerQuiz, seed: seed, brandIds: Array(selectedBrandIds),
            nextIndex: index + 1, asked: Int(tally.asked), correct: Int(tally.correct),
            points: Int(tally.points), plays: plays, total: sessionLength, savedAt: .now))
    }

    private func nextQuestion() {
        MusicKitService.shared.stop()
        selectedId = nil
        opened = []
        verdict = nil
        index += 1
        if let song = question.flatMap({ songById[$0.songId] }) { refreshHint(song) }
    }

    private func restart() {
        startSession()
    }

    private func finish() {
        let sessionResult = songSingerQuizSessionResult(tally: tally)
        previousBest = GameProgressStore.shared.previousBestScore(for: .songSingerQuiz)
        // 保存と「自己ベスト更新！」の判定は進捗ストア (コアの game_progress) が 1 回で返す。
        let update = GameProgressStore.shared.recordResult(
            .songSingerQuiz, score: Int(sessionResult.points), outOf: Int(sessionResult.outOf))
        isNewBest = update.isNewBest
        QuizResumeStore.shared.clear(.songSingerQuiz)
        let urls = questions.prefix(plays.count).compactMap { songById[$0.songId]?.artworkUrl }.filter { !$0.isEmpty }
        shareArtwork = Task { await LyricsQuizShareArtwork.load(Array(Set(urls))) }
        verdict = nil
        result = sessionResult
    }

    /// 結果を画像にしてシェアする。背景には遊んだ曲のジャケットを敷く。
    private func shareResultImage(_ result: QuizSessionResult) {
        guard !isPreparingShare else { return }
        AppAnalytics.tap("song_singer_quiz.share_image")
        isPreparingShare = true
        Task {
            let artworks = await shareArtwork?.value ?? [:]
            isPreparingShare = false
            QuizShareCard(title: "ソロ曲クイズ", result: result, rows: plays.shareRows,
                          longestStreak: plays.longestStreak, isNewBest: isNewBest,
                          artworks: Array(artworks.values))
                .share(text: QuizShareCard.text("ソロ曲クイズ", result))
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let solos = (try? await AppContainer.shared.songReading.songs(filter: SongSearchFilter(songType: "solo"), sortOrder: .titleKana, ascending: nil)) ?? []
        let origMap = (try? await AppContainer.shared.showReading.originalArtistIds(songIds: solos.map(\.song.id))) ?? [:]
        let allIdolIds = Set(origMap.values.flatMap { $0 })
        let idols = (try? await AppContainer.shared.idolReading.idols(ids: Array(allIdolIds))) ?? []
        songById = Dictionary(solos.map { ($0.song.id, $0.song) }, uniquingKeysWith: { first, _ in first })
        singers = idols
        let brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
        brandNames = Dictionary(brands.map { ($0.id, $0.shortName) }, uniquingKeysWith: { a, _ in a })
        rows = songQuizOriginalArtistRows(solos: solos, originalArtistIds: origMap)
        startSession()
    }

    /// 1 ゲーム分の出題をコアに一括生成させる (問題ごとに FFI を呼ばない)。
    private func startSession() {
        // つづきからは保存したシードで同じ出題を作り直し、答えた所まで進める。
        let saved = didUseResume ? nil : resume
        didUseResume = true
        if let saved {
            seed = saved.seed
        } else {
            var generator = SystemRandomNumberGenerator()
            seed = generator.next()
            QuizResumeStore.shared.clear(.songSingerQuiz)
        }
        questions = songSingerQuizSession(rows: rows,
                                          singers: songQuizSingerRefs(singers),
                                          selectedBrandIds: Array(selectedBrandIds),
                                          seed: seed)
        index = saved?.nextIndex ?? 0
        selectedId = nil
        opened = []
        tally = saved?.tally ?? QuizTally(asked: 0, correct: 0, points: 0)
        isLastQuestion = false
        plays = saved?.plays ?? []
        verdict = nil
        result = nil
        isNewBest = false
        previousBest = nil
        if let song = question.flatMap({ songById[$0.songId] }) { refreshHint(song) }
        // 最後の問題まで答えてから閉じていたら、そのまま結果へ。
        if saved != nil && index >= questions.count && !questions.isEmpty { finish() }
    }

    /// 獲得点と見せてよいヒントを引き直す (出題が変わった / ヒントを開いた / 解答した とき)。
    private func refreshHint(_ song: Song) {
        guard let q = question else { return }
        hint = songSingerQuizHintState(opened: opened, available: availableHints(song, question: q),
                                       answered: selectedId != nil)
    }
}
