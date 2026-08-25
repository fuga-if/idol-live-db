import SwiftUI

/// ソロ曲クイズ (ヒント式段階採点)。最初は「曲名だけ」で出題し、ヒントを開くほど手がかりが増える
/// 代わりに獲得点が下がる: 曲名だけで正解=3pt / ジャケットを見る=2pt / プレビュー再生=1pt。
/// ジャケットを初手で出すと答え (歌手) がバレるため、開示はヒントで段階制御する。
/// データは songs(song_type=solo) と song_artists(role=original) の事実情報のみ。
///
/// 出題の生成・選択肢の作り方・採点・母集団の条件 (原唱が単独の曲だけ / 歌手が 4 人以上) は
/// imas-core の `domain/quiz_generation.rs` にあり、Android と同じ実装を共有する。
/// この画面が担うのは描画・プレビュー再生・シード調達だけ。
struct SongSingerQuizView: View {
    @Environment(AppDatabase.self) private var database

    /// 出題ブランド絞り込み（空集合 = 全ブランド対象）。SongSingerQuizSetupView から渡す。
    let selectedBrandIds: Set<String>

    init(selectedBrandIds: Set<String> = []) {
        self.selectedBrandIds = selectedBrandIds
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
    @State private var revealed: UInt32 = 0    // 0=曲名のみ / 1=ジャケ / 2=プレビュー
    /// ジャケ/プレビューの開示段階と次のヒント (コアが算出)。
    @State private var hint = SongSingerQuizHintState(currentValue: 0, showArtwork: false,
                                                     canPreview: false, nextHint: nil)
    /// 解答済み問題数・正解数・累計ポイント (コアが積み上げる)。
    @State private var tally = QuizTally(asked: 0, correct: 0, points: 0)
    @State private var isLastQuestion = false
    @State private var history: [QuizHistoryItem] = [] // 各問の振り返り (リザルトに渡す)
    @State private var result: QuizSessionResult?
    @State private var isNewBest = false
    @State private var isLoading = true

    private var question: SongSingerQuizQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                if isLoading {
                    ImasInlineLoading(tint: DS.sys)
                } else if let result {
                    QuizResultView(result: result,
                                   kind: .songSingerQuiz, isNewBest: isNewBest,
                                   history: history,
                                   onReplay: { restart() })
                } else if let q = question, let song = songById[q.songId] {
                    QuizProgressHeader(current: min(Int(tally.asked) + (selectedId != nil ? 0 : 1), sessionLength),
                                       total: sessionLength, points: Int(tally.points))
                    songCard(q, song: song)
                    if selectedId == nil { hintArea(song) }
                    IdolChoiceGrid(choices: choices(q), answer: singers[Int(q.answer)],
                                   selectedId: selectedId, onPick: { pick($0, song: song) })
                    if selectedId != nil {
                        QuizNextButton(isLastQuestion: isLastQuestion, onNext: nextQuestion, onFinish: finish)
                    }
                } else {
                    ImasEmptyState(systemImage: "music.note", title: "出題できるソロ曲が不足しています")
                }
            }
            .padding(DS.sp5)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("ソロ曲クイズ")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { MusicKitService.shared.stop() }
        .task { await load() }
        .trackScreen("song_singer_quiz")
    }

    // MARK: - 出題カード

    private func songCard(_ q: SongSingerQuizQuestion, song: Song) -> some View {
        let answered = selectedId != nil
        let answer = singers[Int(q.answer)]
        // ジャケットは「ヒント1以降」または解答後にだけ出す。プレビューは「ヒント2以降」。
        return VStack(spacing: DS.sp4) {
            HStack {
                Text("このソロ曲を歌うのは？").font(.imasHeadline.weight(.bold)).foregroundStyle(DS.ink)
                Spacer(minLength: 0)
                if !answered { QuizValueBadge(value: Int(hint.currentValue)) }
            }
            if hint.showArtwork {
                ArtworkImageView(url: URL(string: song.artworkUrl ?? ""), size: 132,
                                 previewURL: hint.canPreview ? song.previewUrl.flatMap { URL(string: $0) } : nil,
                                 songTitle: song.title,
                                 seed: answered ? answer.color : nil)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            } else {
                // 曲名だけのプレースホルダ (ジャケはまだ伏せる)。
                ZStack {
                    RoundedRectangle(cornerRadius: DS.rMD, style: .continuous).fill(DS.fill)
                    Image(systemName: "questionmark")
                        .font(.imasScaled( 44, weight: .bold)).foregroundStyle(DS.ink3)
                }
                .frame(width: 132, height: 132)
            }
            Text(song.title).font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                .multilineTextAlignment(.center)
            if let cd = song.cdTitle, !cd.isEmpty {
                Text(cd).font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(1)
            }
            if answered {
                HStack(spacing: DS.sp3) {
                    IdolAvatarView(idol: answer, size: 28)
                    Text("正解: \(answer.name)").font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    // MARK: - ヒント

    /// 次に開けるヒント (ヒント1: ジャケット / ヒント2: プレビュー) はコアが決める。
    /// プレビューが無い曲では 2 段目が返らないので、押しても何も起きないボタンは出ない。
    @ViewBuilder
    private func hintArea(_ song: Song) -> some View {
        if let next = hint.nextHint {
            switch next.kind {
            case .artwork:
                QuizHintButton(systemImage: "photo.fill", title: "ヒント: ジャケットを見る",
                               nextValue: Int(next.nextValue)) {
                    AppAnalytics.tap("song_singer_quiz.hint_artwork")
                    withAnimation(.easeInOut(duration: 0.2)) {
                        revealed = 1
                        refreshHint(song)
                    }
                }
            case .preview:
                QuizHintButton(systemImage: "play.circle.fill", title: "ヒント: プレビューを再生する",
                               nextValue: Int(next.nextValue)) {
                    AppAnalytics.tap("song_singer_quiz.hint_preview")
                    withAnimation(.easeInOut(duration: 0.2)) {
                        revealed = 2
                        refreshHint(song)
                    }
                    if let url = song.previewUrl.flatMap({ URL(string: $0) }) {
                        MusicKitService.shared.togglePreview(url: url, title: song.title)
                    }
                }
            }
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
        // 正誤判定・獲得点 (開示段階で決まる)・積み上げはコアがまとめて返す。
        let outcome = songSingerQuizAnswer(revealed: revealed, pickedIdolId: idol.id,
                                           answerIdolId: answer.id, before: tally)
        tally = outcome.tally
        isLastQuestion = outcome.isLastQuestion
        refreshHint(song)
        history.append(QuizHistoryItem(
            id: "\(tally.asked)-\(song.id)",
            index: Int(tally.asked),
            subjectTitle: song.title,
            subjectSubtitle: song.cdTitle,
            answer: answer,
            picked: idol,
            earnedPoints: Int(outcome.earnedPoints),
            revealedHints: Int(outcome.revealedHints)
        ))
    }

    private func nextQuestion() {
        MusicKitService.shared.stop()
        selectedId = nil
        revealed = 0
        index += 1
        if let song = question.flatMap({ songById[$0.songId] }) { refreshHint(song) }
    }

    private func restart() {
        startSession()
    }

    private func finish() {
        let sessionResult = songSingerQuizSessionResult(tally: tally)
        // 保存と「自己ベスト更新！」の判定は進捗ストア (コアの game_progress) が 1 回で返す。
        let update = GameProgressStore.shared.recordResult(
            .songSingerQuiz, score: Int(sessionResult.points), outOf: Int(sessionResult.outOf))
        isNewBest = update.isNewBest
        result = sessionResult
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
        rows = songQuizOriginalArtistRows(solos: solos, originalArtistIds: origMap)
        startSession()
    }

    /// 1 ゲーム分の出題をコアに一括生成させる (問題ごとに FFI を呼ばない)。
    private func startSession() {
        var generator = SystemRandomNumberGenerator()
        questions = songSingerQuizSession(rows: rows,
                                          singers: songQuizSingerRefs(singers),
                                          selectedBrandIds: Array(selectedBrandIds),
                                          seed: generator.next())
        index = 0
        selectedId = nil
        revealed = 0
        tally = QuizTally(asked: 0, correct: 0, points: 0)
        isLastQuestion = false
        history = []
        result = nil
        isNewBest = false
        if let song = question.flatMap({ songById[$0.songId] }) { refreshHint(song) }
    }

    /// 開示段階と次のヒントを引き直す (出題が変わった / ヒントを開いた / 解答した とき)。
    private func refreshHint(_ song: Song) {
        hint = songSingerQuizHintState(revealed: revealed,
                                       hasPreview: !(song.previewUrl ?? "").isEmpty,
                                       answered: selectedId != nil)
    }
}
