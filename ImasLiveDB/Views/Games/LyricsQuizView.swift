import SwiftUI

/// 歌詞クイズ (曲名当て / 続きはどれ)。ヒント式段階採点はソロ曲クイズと同じ (3/2/1pt)。
///
/// 出題順・曲名当ての 4 択・歌詞のどこを出すか・続きはどれの 4 択・採点は imas-core の
/// `domain/lyrics_quiz.rs` にあり、Android と同じ実装を共有する。
/// この画面が担うのは描画・歌詞の取得・シード調達だけ。
///
/// ⚠️ JASRAC 許諾の条件 (一括ダウンロードできない形式) を守るため:
/// - 歌詞は**出題のたびに 1 曲ずつ**取る。先読みは「次の 1 問」まで。
/// - 歌詞の断片は表示中の問題 (と先読みした 1 問) にだけ持つ。振り返り・リザルト・シェアは
///   曲名だけで組み、歌詞を載せない。
struct LyricsQuizView: View {
    let mode: LyricsQuizMode
    /// 同梱 SQLite の曲 (出題の index 参照元)。コアが返す index はこの配列の位置を指す。
    let songs: [SongWithArtists]
    let publishedSongIds: [String]
    let selectedBrandIds: Set<String>
    /// 途中でやめたセッションの続き (ゲーム一覧の「つづきから」)。nil なら新しく始める。
    var resume: QuizSuspended? = nil

    /// 歌詞が届いて出題できる状態になった 1 問。
    private struct Prepared {
        /// `questions` 内の位置 (次の曲を探す起点)。
        let cursor: Int
        let question: LyricsQuizQuestion
        let excerpt: LyricsQuizExcerpt
    }

    private enum Phase: Equatable {
        case loading
        case playing
        case failed
        case exhausted
    }

    private var sessionLength: Int { Int(quizSessionLength()) }

    @State private var questions: [LyricsQuizQuestion] = []
    @State private var current: Prepared?
    /// 次の 1 問の先読み (解答中に取っておき、「次の問題」で待たせない)。
    @State private var prefetch: Task<Prepared?, Error>?
    @State private var phase: Phase = .loading
    @State private var selectedKey: String?
    @State private var revealed: UInt32 = 0
    @State private var hint = LyricsQuizHintState(currentValue: 0, shown: [], nextHint: nil)
    @State private var tally = QuizTally(asked: 0, correct: 0, points: 0)
    @State private var isLastQuestion = false
    @State private var history: [LyricsQuizHistoryItem] = []
    @State private var result: QuizSessionResult?
    @State private var isNewBest = false
    /// シェア画像に焼くジャケット。結果が出た時点で読み始め、シェアを押したときに待つ。
    @State private var shareArtwork: Task<[String: UIImage], Never>?
    @State private var isPreparingShare = false
    /// 正誤の手触り (sensoryFeedback のトリガ)。次の問題で nil に戻す。
    @State private var lastCorrect: Bool?
    /// 各問の記録 (ペンライト・連続正解・見直す)。歌詞は持たない。
    @State private var plays: [QuizStagePlay] = []
    /// 直前の問題の判定 (解答後に出す大きなカード)。
    @State private var verdict: QuizVerdict?
    @State private var scoreBefore = 0
    @State private var previousBest: Int?
    /// ヒントの段階ごとの獲得点。
    @State private var stageValues: [Int] = []
    /// このセッションの出題シード (つづきからで同じ出題順を作り直す)。
    @State private var seed: UInt64 = 0
    /// `resume` は最初の 1 回だけ使う (「もう一度」は新しいセッション)。
    @State private var didUseResume = false
    @Environment(\.dismiss) private var dismiss

    private var header: QuizStageHeader {
        if let result { return .result(total: Int(result.questions)) }
        guard current != nil else { return .none }
        return .question(current: min(plays.count + (verdict == nil ? 1 : 0), sessionLength),
                         total: sessionLength, points: Int(tally.points))
    }

    var body: some View {
        QuizStageScaffold(title: mode == .title ? "歌詞クイズ" : "歌詞 · 続きはどれ", header: header,
                          onClose: { dismiss() }, trailing: {
            if let result {
                QuizStageRoundButton(systemImage: isPreparingShare ? "hourglass" : "square.and.arrow.up",
                                     label: "結果を画像でシェア") { shareResultImage(result) }
            }
        }) {
            if let result {
                QuizStageResultView(result: result, kind: .lyricsQuiz, isNewBest: isNewBest,
                                    previousBest: previousBest,
                                    slots: plays.penlights(total: Int(result.questions), answering: false),
                                    longestStreak: plays.longestStreak, misses: plays.misses,
                                    onReplay: { startSession() }, onClose: { dismiss() })
            } else {
                switch phase {
                case .loading where current == nil:
                    ImasInlineLoading(tint: QS.ink)
                case .failed:
                    ImasEmptyState(systemImage: "wifi.exclamationmark",
                                   title: "歌詞を読み込めませんでした",
                                   message: "通信状態を確認して、もう一度お試しください。",
                                   actionTitle: "再試行", action: { retry() })
                case .exhausted where current == nil:
                    ImasEmptyState(systemImage: "text.quote", title: "出題できる歌詞が不足しています")
                default:
                    if let p = current { questionBody(p) }
                }
            }
            JASRACLicenseNotice(placement: .lyrics)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .sensoryFeedback(trigger: lastCorrect) { _, new in
            guard let new else { return nil }
            return new ? .success : .error
        }
        .task { startSession() }
        .onDisappear { prefetch?.cancel() }
        .trackScreen("lyrics_quiz")
    }

    // MARK: - 出題

    @ViewBuilder
    private func questionBody(_ p: Prepared) -> some View {
        QuizStageProgress(slots: plays.penlights(total: sessionLength, answering: verdict == nil),
                          caption: plays.setlistCaption(total: sessionLength),
                          streak: plays.streak, streakBrokeAt: plays.streakBrokeAt)
            .padding(.bottom, 2)
        if let verdict {
            QuizVerdictCard(verdict: verdict).id(verdict.number)
            QuizVerdictStats(before: scoreBefore, after: Int(tally.points), streak: plays.streak)
            if !verdict.isCorrect { QuizVerdictFootnote() }
            if phase == .loading {
                // 次の曲の歌詞がまだ届いていない (先読みが間に合わなかった)。
                HStack(spacing: 10) {
                    ProgressView().tint(QS.ink)
                    Text("次の歌詞を読み込み中…").font(QS.text(14)).foregroundStyle(QS.dim)
                }
                .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                QuizStageNextButton(isLastQuestion: isLastQuestion || phase == .exhausted,
                                    onNext: nextQuestion, onFinish: finish)
                    .padding(.top, 4)
            }
        } else {
            Group {
                ticket(p)
                let hidden: Set<String> = Set(hint.shown).contains(.fiftyFifty)
                    ? Set(p.excerpt.fiftyFiftyHidden.map { String($0) }) : []
                QuizStageChoiceGrid(choices: choices(p).map { QuizStageChoice(id: $0.id, title: $0.text) },
                                    columns: mode == .nextLine ? 1 : 2, eliminated: hidden) { picked in
                    if let choice = choices(p).first(where: { $0.id == picked.id }) { pick(choice, prepared: p) }
                }
                .padding(.top, 4)
            }
            .id(p.cursor)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))
        }
    }

    private func song(_ index: UInt32) -> SongWithArtists? {
        songs.indices.contains(Int(index)) ? songs[Int(index)] : nil
    }

    private func singerText(_ s: SongWithArtists) -> String {
        let label = s.song.singerLabel ?? ""
        return label.isEmpty ? s.artistNames : label
    }

    // MARK: - チケット

    private func ticket(_ p: Prepared) -> some View {
        let shown = Set(hint.shown)
        let answerSong = song(p.question.song)
        return QuizTicket {
            QuizTicketTitleBlock(label: "LYRIC",
                                 question: mode == .title ? "この一節はどの曲？" : "この歌詞の続きは？",
                                 value: Int(hint.currentValue), base: stageValues.first ?? 0) {
                // 続きはどれは曲を明かして出題する (知っている曲の続きを当てる遊び)。
                if mode == .nextLine, let s = answerSong {
                    HStack(spacing: 10) {
                        ArtworkImageView(url: URL(string: s.song.artworkUrl ?? ""), size: 36,
                                         songTitle: s.song.title, songId: s.song.id)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(s.song.title).font(QS.text(15, weight: .black)).lineLimit(2)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Text("“").font(QS.num(56, weight: .black)).foregroundStyle(QS.paperDash)
                        .frame(height: 40, alignment: .top)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        if mode == .nextLine, shown.contains(.previousLine), let prev = p.excerpt.contextLine {
                            lyricLine(prev, emphasized: false)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        lyricLine(p.excerpt.prompt, emphasized: true)
                        if mode == .title, shown.contains(.nextLine), let next = p.excerpt.contextLine {
                            lyricLine(next, emphasized: false)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if mode == .nextLine {
                            Text("？？？").font(QS.text(20, weight: .black)).foregroundStyle(QS.paperMuted)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
            if !p.excerpt.hints.isEmpty {
                QuizTicketNotch()
                QuizTicketHintTiles {
                    ForEach(Array(p.excerpt.hints.enumerated()), id: \.offset) { i, kind in
                        QuizTicketHintTile(title: hintTitle(kind), phase: tilePhase(i, kind: kind, song: answerSong))
                    }
                }
            }
        }
    }

    /// 歌詞 1 行。出題行は大きく、ヒントで開いた行は控えめに出す。
    private func lyricLine(_ text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(QS.text(emphasized ? 22 : 16, weight: emphasized ? .black : .bold))
            .foregroundStyle(emphasized ? QS.paperInk : QS.paperSub)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ヒント

    /// ヒントは順番に開く (コアが段階を持つ)。開いたもの / 次に開けるもの / まだ開けないもの。
    private func tilePhase(_ i: Int, kind: LyricsQuizHintKind, song: SongWithArtists?) -> QuizTicketHintTile.Phase {
        let cost = stageValues.indices.contains(i + 1) ? stageValues[i] - stageValues[i + 1] : 0
        if i < Int(revealed) {
            switch kind {
            case .singer:       return .open(value: song.map(singerText) ?? "—")
            case .fiftyFifty:   return .open(value: "2 択に")
            case .nextLine, .previousLine: return .open(value: "表示中")
            }
        }
        if i == Int(revealed) {
            return .available(cost: cost, action: {
                AppAnalytics.tap("lyrics_quiz.hint_\(hintKey(kind))")
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    revealed += 1
                    refreshHint()
                }
            })
        }
        return .locked(cost: cost)
    }

    private func hintTitle(_ kind: LyricsQuizHintKind) -> String {
        switch kind {
        case .nextLine:     return "次の行"
        case .singer:       return "歌唱"
        case .previousLine: return "前の行"
        case .fiftyFifty:   return "2 択に絞る"
        }
    }

    private func hintKey(_ kind: LyricsQuizHintKind) -> String {
        switch kind {
        case .nextLine:     return "next_line"
        case .singer:       return "singer"
        case .previousLine: return "previous_line"
        case .fiftyFifty:   return "fifty_fifty"
        }
    }

    // MARK: - 選択肢

    private struct Choice: Identifiable {
        let id: String      // 採点に渡すキー (曲名当て=曲 id / 続きはどれ=位置)
        let text: String
        let song: SongWithArtists?
    }

    private func choices(_ p: Prepared) -> [Choice] {
        switch mode {
        case .title:
            return p.question.choices.compactMap { i in
                song(i).map { Choice(id: $0.song.id, text: $0.song.title, song: $0) }
            }
        case .nextLine:
            return p.excerpt.choices.enumerated().map { Choice(id: String($0.offset), text: $0.element, song: nil) }
        }
    }

    private func answerKey(_ p: Prepared) -> String {
        switch mode {
        case .title:    return song(p.question.song)?.song.id ?? ""
        case .nextLine: return String(p.excerpt.answer)
        }
    }

    // MARK: - 進行

    private func pick(_ choice: Choice, prepared p: Prepared) {
        guard selectedKey == nil else { return }
        AppAnalytics.tap("lyrics_quiz.answer")
        let answer = answerKey(p)
        let outcome = lyricsQuizAnswer(revealed: revealed, picked: choice.id, answer: answer, before: tally)
        let answerSong = song(p.question.song)
        let number = plays.count + 1
        scoreBefore = Int(tally.points)
        // 振り返り・結果は曲名だけで組む (歌詞は載せない)。続きはどれの正しい行は、
        // いま表示中の問題の判定カードにだけ出す。
        let correctLine = mode == .nextLine && p.excerpt.choices.indices.contains(Int(p.excerpt.answer))
            ? p.excerpt.choices[Int(p.excerpt.answer)] : nil
        let singer = answerSong.map(singerText) ?? ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            selectedKey = choice.id
            tally = outcome.tally
            isLastQuestion = outcome.isLastQuestion
            refreshHint()
            plays.append(QuizStagePlay(number: number, isCorrect: outcome.isCorrect,
                                       answerName: answerSong?.song.title ?? "", answerHex: nil,
                                       pickedName: mode == .title && !outcome.isCorrect ? choice.text : nil))
            verdict = QuizVerdict(isCorrect: outcome.isCorrect, number: number,
                                  answerName: answerSong?.song.title ?? "", answerHex: nil,
                                  earned: Int(outcome.earnedPoints), base: stageValues.first ?? 0,
                                  hints: Int(outcome.revealedHints),
                                  pickedName: mode == .title && !outcome.isCorrect ? choice.text : nil,
                                  detail: correctLine.map { "続き: \($0)" } ?? singer)
        }
        lastCorrect = outcome.isCorrect
        history.append(LyricsQuizHistoryItem(
            id: "\(tally.asked)-\(answerSong?.song.id ?? "")",
            index: Int(tally.asked),
            songTitle: answerSong?.song.title ?? "",
            singer: singer,
            pickedTitle: mode == .title && !outcome.isCorrect ? choice.text : nil,
            isCorrect: outcome.isCorrect,
            earnedPoints: Int(outcome.earnedPoints),
            revealedHints: Int(outcome.revealedHints),
            artworkUrl: answerSong?.song.artworkUrl
        ))
        if !outcome.isLastQuestion { startPrefetch(after: p.cursor) }
        // 1 問答えるたびに途中経過を残す。保存するのは出題順の位置と曲名だけ (歌詞は残さない)。
        QuizResumeStore.shared.save(QuizSuspended(
            kind: .lyricsQuiz, seed: seed, brandIds: Array(selectedBrandIds),
            nextIndex: p.cursor + 1, asked: Int(tally.asked), correct: Int(tally.correct),
            points: Int(tally.points), plays: plays, total: sessionLength,
            lyricsMode: (mode == .title ? LyricsQuizModeSetting.title : .nextLine).rawValue,
            savedAt: .now))
    }

    private func nextQuestion() {
        guard let task = prefetch else { return }
        phase = .loading
        Task {
            do {
                let next = try await task.value
                prefetch = nil
                if let next {
                    withAnimation(.easeInOut(duration: 0.25)) { show(next) }
                } else {
                    // 予備の曲も尽きた。ここまでの成績で結果へ。
                    phase = .exhausted
                    finish()
                }
            } catch {
                prefetch = nil
                phase = .failed
            }
        }
    }

    private func finish() {
        prefetch?.cancel()
        prefetch = nil
        let sessionResult = lyricsQuizSessionResult(tally: tally)
        QuizResumeStore.shared.clear(.lyricsQuiz)
        previousBest = GameProgressStore.shared.previousBestScore(for: .lyricsQuiz)
        if tally.asked > 0 {
            let update = GameProgressStore.shared.recordResult(
                .lyricsQuiz, score: Int(sessionResult.points), outOf: Int(sessionResult.outOf))
            isNewBest = update.isNewBest
        }
        let urls = Array(Set(history.compactMap(\.artworkUrl)))
        shareArtwork = Task { await LyricsQuizShareArtwork.load(urls) }
        withAnimation(.easeInOut(duration: 0.25)) {
            verdict = nil
            result = sessionResult
        }
    }

    private var modeLabel: String { mode == .title ? "曲名当て" : "続きはどれ" }

    /// 結果カードを画像にしてシェアする (イントロドンと同じ手順)。画像にも文面にも歌詞は載せない。
    private func shareResultImage(_ result: QuizSessionResult) {
        guard !isPreparingShare else { return }
        AppAnalytics.tap("lyrics_quiz.share_image")
        isPreparingShare = true
        Task {
            let artworks = await shareArtwork?.value ?? [:]
            // 背景のジャケットは遊んだ順・重複なし。
            var seen = Set<String>()
            let images = history.compactMap { item -> UIImage? in
                guard let url = item.artworkUrl, seen.insert(url).inserted else { return nil }
                return artworks[url]
            }
            isPreparingShare = false
            QuizShareCard(title: "歌詞クイズ", subtitle: modeLabel, result: result, rows: plays.shareRows,
                          longestStreak: plays.longestStreak, isNewBest: isNewBest, artworks: images)
                .share(text: QuizShareCard.text("歌詞クイズ（\(modeLabel)）", result))
        }
    }

    private func show(_ p: Prepared) {
        current = p
        selectedKey = nil
        verdict = nil
        revealed = 0
        lastCorrect = nil
        phase = .playing
        refreshHint()
    }

    private func startSession() {
        prefetch?.cancel()
        prefetch = nil
        // つづきからは保存したシードで同じ出題順を作り直し、続きの位置から歌詞を取りに行く。
        let saved = didUseResume ? nil : resume
        didUseResume = true
        if let saved {
            seed = saved.seed
        } else {
            var generator = SystemRandomNumberGenerator()
            seed = generator.next()
            QuizResumeStore.shared.clear(.lyricsQuiz)
        }
        questions = lyricsQuizSession(songs: lyricsQuizSongRefs(songs),
                                      publishedSongIds: publishedSongIds,
                                      selectedBrandIds: Array(selectedBrandIds),
                                      seed: seed)
        current = nil
        selectedKey = nil
        revealed = 0
        tally = saved?.tally ?? QuizTally(asked: 0, correct: 0, points: 0)
        isLastQuestion = false
        history = []
        plays = saved?.plays ?? []
        verdict = nil
        result = nil
        isNewBest = false
        previousBest = nil
        shareArtwork?.cancel()
        shareArtwork = nil
        lastCorrect = nil
        loadFirst(from: saved?.nextIndex ?? 0, resuming: saved != nil)
    }

    private func loadFirst(from start: Int = 0, resuming: Bool = false) {
        phase = .loading
        let task = makePrepareTask(from: start)
        Task {
            do {
                if let p = try await task.value {
                    show(p)
                } else if resuming && tally.asked > 0 {
                    // 続きの曲が残っていない (最後まで答えてから閉じていた)。ここまでの成績で結果へ。
                    finish()
                } else {
                    phase = .exhausted
                }
            } catch {
                phase = .failed
            }
        }
    }

    private func retry() {
        if let p = current {
            // 次の問題の取得で失敗した。解答済みの画面に戻して先読みをやり直す。
            phase = .playing
            startPrefetch(after: p.cursor)
        } else {
            loadFirst()
        }
    }

    private func startPrefetch(after cursor: Int) {
        prefetch?.cancel()
        prefetch = makePrepareTask(from: cursor + 1)
    }

    /// `from` 以降の曲を順に試し、出題できる最初の 1 問を返す (尽きたら nil)。
    /// 歌詞が無い・出題に向かない曲は飛ばす。取得は 1 リクエスト 1 曲。
    private func makePrepareTask(from start: Int) -> Task<Prepared?, Error> {
        let questions = questions
        let songs = songs
        let mode = mode
        let reader = AppContainer.shared.lyricsQuizReading
        return Task {
            var cursor = start
            while cursor < questions.count {
                try Task.checkCancellation()
                let q = questions[cursor]
                guard songs.indices.contains(Int(q.song)) else { cursor += 1; continue }
                let s = songs[Int(q.song)]
                if let lyrics = try await reader.lyrics(songId: s.song.id) {
                    let lines = lyrics.lines.map {
                        LyricsQuizLine(text: $0.text, isLyric: $0.kind == .lyric)
                    }
                    let singer = (s.song.singerLabel ?? "").isEmpty ? s.artistNames : (s.song.singerLabel ?? "")
                    var generator = SystemRandomNumberGenerator()
                    if let excerpt = lyricsQuizExcerpt(lines: lines, songTitle: s.song.title,
                                                       hasSinger: !singer.isEmpty, mode: mode,
                                                       seed: generator.next()) {
                        return Prepared(cursor: cursor, question: q, excerpt: excerpt)
                    }
                }
                cursor += 1
            }
            return nil
        }
    }

    private func refreshHint() {
        let hints = current?.excerpt.hints ?? []
        hint = lyricsQuizHintState(hints: hints, revealed: revealed, answered: selectedKey != nil)
        // 段階ごとの獲得点 (ヒント 0 枚 / 1 枚 / …)。メーターの元値とタイルの「−n」に使う。
        stageValues = (0...hints.count).map {
            Int(lyricsQuizHintState(hints: hints, revealed: UInt32($0), answered: false).currentValue)
        }
    }
}

// MARK: - 振り返り

/// 1 問分の振り返り。⚠️ 歌詞は載せない (曲名と正誤だけ)。
struct LyricsQuizHistoryItem: Identifiable, Hashable {
    let id: String
    let index: Int
    let songTitle: String
    let singer: String
    /// 曲名当てで誤答したときに選んだ曲名 (それ以外は nil)。
    let pickedTitle: String?
    let isCorrect: Bool
    let earnedPoints: Int
    let revealedHints: Int
    /// シェア画像の背景と一覧に使うジャケット。
    let artworkUrl: String?
}

// MARK: - つづきから

/// ゲーム一覧の「つづきから」で歌詞クイズを再開する入口。出題に要る曲一覧と
/// 歌詞の公開曲 id を設定画面と同じ手順で読んでから、続きの問題を出す。
struct LyricsQuizResumeView: View {
    let suspended: QuizSuspended

    @State private var songs: [SongWithArtists] = []
    @State private var publishedIds: [String]?
    @State private var failed = false

    var body: some View {
        Group {
            if let publishedIds {
                LyricsQuizView(
                    mode: (LyricsQuizModeSetting(rawValue: suspended.lyricsMode ?? "") ?? .title).core,
                    songs: songs, publishedSongIds: publishedIds,
                    selectedBrandIds: Set(suspended.brandIds), resume: suspended)
            } else if failed {
                ImasEmptyState(systemImage: "wifi.exclamationmark",
                               title: "歌詞を読み込めませんでした",
                               message: "通信状態を確認して、もう一度お試しください。",
                               actionTitle: "再試行", action: { Task { await load() } })
            } else {
                ImasInlineLoading(tint: DS.sys)
            }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        if songs.isEmpty {
            songs = (try? await AppContainer.shared.songReading.songs(
                filter: SongSearchFilter(), sortOrder: .titleKana, ascending: nil)) ?? []
        }
        do {
            publishedIds = try await AppContainer.shared.lyricsQuizReading.publishedSongIds()
        } catch {
            failed = true
        }
    }
}
