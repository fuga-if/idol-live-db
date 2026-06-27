import SwiftUI

/// ソロ曲クイズ (ヒント式段階採点)。最初は「曲名だけ」で出題し、ヒントを開くほど手がかりが増える
/// 代わりに獲得点が下がる: 曲名だけで正解=3pt / ジャケットを見る=2pt / プレビュー再生=1pt。
/// ジャケットを初手で出すと答え (歌手) がバレるため、開示はヒントで段階制御する。
/// データは songs(song_type=solo) と song_artists(role=original) の事実情報のみ。
struct SongSingerQuizView: View {
    @Environment(AppDatabase.self) private var database

    /// 出題ブランド絞り込み（空集合 = 全ブランド対象）。SongSingerQuizSetupView から渡す。
    let selectedBrandIds: Set<String>

    init(selectedBrandIds: Set<String> = []) {
        self.selectedBrandIds = selectedBrandIds
    }

    private let sessionLength = 10

    @State private var pool: [(song: Song, singer: Idol)] = []
    @State private var idolPool: [Idol] = []
    @State private var question: Question?
    @State private var selectedId: String?
    @State private var revealed = 0          // 0=曲名のみ / 1=ジャケ / 2=プレビュー
    @State private var points = 0
    @State private var correct = 0
    @State private var asked = 0
    @State private var sessionDone = false
    @State private var isNewBest = false
    @State private var isLoading = true

    private struct Question {
        let song: Song
        let answer: Idol
        let choices: [Idol]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                if isLoading {
                    ProgressView().tint(DS.sys).frame(maxWidth: .infinity).padding(.top, DS.sp9)
                } else if sessionDone {
                    QuizResultView(points: points, maxPoints: QuizScoring.sessionMax(questions: sessionLength),
                                   correct: correct, questions: asked,
                                   kind: .songSingerQuiz, isNewBest: isNewBest,
                                   onReplay: { restart() })
                } else if let q = question {
                    QuizProgressHeader(current: min(asked + (selectedId != nil ? 0 : 1), sessionLength),
                                       total: sessionLength, points: points)
                    songCard(q)
                    if selectedId == nil { hintArea(q) }
                    IdolChoiceGrid(choices: q.choices, answer: q.answer, selectedId: selectedId, onPick: pick)
                    if selectedId != nil {
                        QuizNextButton(isLastQuestion: asked >= sessionLength, onNext: nextQuestion, onFinish: finish)
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

    private func songCard(_ q: Question) -> some View {
        let answered = selectedId != nil
        // ジャケットは「ヒント1以降」または解答後にだけ出す。プレビューは「ヒント2以降」。
        let showArtwork = answered || revealed >= 1
        let canPreview = answered || revealed >= 2
        return VStack(spacing: DS.sp4) {
            HStack {
                Text("このソロ曲を歌うのは？").font(.imasHeadline.weight(.bold)).foregroundStyle(DS.ink)
                Spacer(minLength: 0)
                if !answered { QuizValueBadge(revealed: revealed) }
            }
            if showArtwork {
                ArtworkImageView(url: URL(string: q.song.artworkUrl ?? ""), size: 132,
                                 previewURL: canPreview ? q.song.previewUrl.flatMap { URL(string: $0) } : nil,
                                 songTitle: q.song.title,
                                 seed: answered ? q.answer.color : nil)
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
            Text(q.song.title).font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                .multilineTextAlignment(.center)
            if let cd = q.song.cdTitle, !cd.isEmpty {
                Text(cd).font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(1)
            }
            if answered {
                HStack(spacing: DS.sp3) {
                    IdolAvatarView(idol: q.answer, size: 28)
                    Text("正解: \(q.answer.name)").font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    // MARK: - ヒント

    @ViewBuilder
    private func hintArea(_ q: Question) -> some View {
        let hasPreview = !(q.song.previewUrl ?? "").isEmpty
        // ヒント1: ジャケット / ヒント2: プレビュー (プレビューが無い曲は出さない)。
        if revealed == 0 {
            QuizHintButton(systemImage: "photo.fill", title: "ヒント: ジャケットを見る",
                           nextValue: QuizScoring.points(revealed: 1)) {
                AppAnalytics.tap("song_singer_quiz.hint_artwork")
                withAnimation(.easeInOut(duration: 0.2)) { revealed = 1 }
            }
        } else if revealed == 1, hasPreview {
            QuizHintButton(systemImage: "play.circle.fill", title: "ヒント: プレビューを再生する",
                           nextValue: QuizScoring.points(revealed: 2)) {
                AppAnalytics.tap("song_singer_quiz.hint_preview")
                withAnimation(.easeInOut(duration: 0.2)) { revealed = 2 }
                if let url = q.song.previewUrl.flatMap({ URL(string: $0) }) {
                    MusicKitService.shared.togglePreview(url: url, title: q.song.title)
                }
            }
        }
    }

    // MARK: - 進行

    private func pick(_ idol: Idol, isCorrect: Bool) {
        guard selectedId == nil else { return }
        AppAnalytics.tap("song_singer_quiz.answer")
        MusicKitService.shared.stop()
        selectedId = idol.id
        asked += 1
        if isCorrect {
            correct += 1
            points += QuizScoring.points(revealed: revealed)
        }
    }

    private func nextQuestion() {
        MusicKitService.shared.stop()
        selectedId = nil
        revealed = 0
        question = makeQuestion()
    }

    private func restart() {
        points = 0; correct = 0; asked = 0
        sessionDone = false; selectedId = nil; revealed = 0; isNewBest = false
        question = makeQuestion()
    }

    private func finish() {
        let outOf = QuizScoring.sessionMax(questions: asked)
        let before = GameProgressStore.shared.record(for: .songSingerQuiz)
        let beforeRate = before.bestOutOf > 0 ? Double(before.bestScore) / Double(before.bestOutOf) : -1
        let newRate = outOf > 0 ? Double(points) / Double(outOf) : 0
        isNewBest = before.hasPlayed && newRate > beforeRate
        sessionDone = true
        GameProgressStore.shared.recordResult(.songSingerQuiz, score: points, outOf: outOf)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let solos = (try? await AppContainer.shared.songReading.songs(filter: SongSearchFilter(songType: "solo"), sortOrder: .titleKana, ascending: nil)) ?? []
        let origMap = (try? await AppContainer.shared.showReading.originalArtistIds(songIds: solos.map(\.song.id))) ?? [:]
        let allIdolIds = Set(origMap.values.flatMap { $0 })
        let idols = (try? await AppContainer.shared.idolReading.idols(ids: Array(allIdolIds))) ?? []
        let idolById = Dictionary(uniqueKeysWithValues: idols.map { ($0.id, $0) })
        pool = solos.compactMap { sw in
            guard let ids = origMap[sw.song.id], ids.count == 1,
                  let singer = idolById[ids.first!], !singer.isExternal else { return nil }
            // ブランド絞り込み: 空集合のときは全ブランドを対象とする。
            guard selectedBrandIds.isEmpty || selectedBrandIds.contains(singer.brandId) else { return nil }
            return (sw.song, singer)
        }
        idolPool = Array(Set(pool.map { $0.singer.id })).compactMap { idolById[$0] }
        question = makeQuestion()
    }

    private func makeQuestion() -> Question? {
        guard pool.count >= 4, let entry = pool.randomElement() else { return nil }
        let answer = entry.singer
        let choices = (quizDistractors(from: idolPool, answer: answer) + [answer]).shuffled()
        return Question(song: entry.song, answer: answer, choices: choices)
    }
}
