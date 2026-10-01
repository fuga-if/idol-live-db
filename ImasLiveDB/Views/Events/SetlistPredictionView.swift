import MusicKit
import os
import SwiftUI

// MARK: - SetlistPredictionView

struct SetlistPredictionView: View {

    /// カタログから 1 曲を引く。
    ///
    /// `MusicCatalogResourceRequest` は非 Sendable なので、@MainActor の View 側で作って
    /// await すると隔離境界を越えて Swift 6 の厳格チェックに引っかかる。
    /// nonisolated なここでリクエストを作り、Sendable な結果だけを返す。
    nonisolated static func fetchCatalogSong(id: MusicItemID) async throws -> MusicKit.Song? {
        let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: id)
        return try await request.response().items.first
    }

    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
    /// 予想は公演 (show) 単位。 同じイベントでも DAY1/DAY2 でセトリが違うため。
    let showId: String
    /// ヘッダ表示用 (show.name そのまま渡す想定)。
    let showName: String
    /// 投稿導線の文脈色 (公演のブランド色)。他の投稿UI (動画/タグ) と揃える。
    var seed: String? = nil

    /// 「曲を追加」タップ時に親 (SetlistView) の安定した List 上で picker sheet を開いてもらう。
    /// sheet を Section に直接付けると、predictions 更新で行が再評価され初回 sheet が即閉じするため、
    /// presentation surface は親が持ち、ここは onSelect ハンドラ (addPredictions) だけ渡す。
    /// 複数選択に対応 (1回の起動でまとめて予想追加できる)。
    let presentSongPicker: (@escaping ([Song]) -> Void) -> Void

    /// 機械予測の節 (コアの `setlistForecast`)。
    @State private var forecast: SetlistForecastViewModel

    init(
        showId: String,
        showName: String,
        seed: String? = nil,
        presentSongPicker: @escaping (@escaping ([Song]) -> Void) -> Void
    ) {
        self.showId = showId
        self.showName = showName
        self.seed = seed
        self.presentSongPicker = presentSongPicker
        _forecast = State(initialValue: SetlistForecastViewModel(showId: showId))
    }

    @State private var predictions: [SetlistPrediction] = []
    /// 「歌唱メンバー予想」を展開中の曲 (songId)。行ローカル @State だと List 再描画/
    /// id 重複時に展開状態が他行へ漏れる (開いたら別の曲も開く) ため、親で songId をキーに保持する。
    @State private var expandedSongIds: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isCreatingPlaylist = false
    @State private var playlistProgress: (current: Int, total: Int) = (0, 0)
    /// ログイン誘導 sheet と、ログイン完了後に実行する保留アクション。
    @State private var showLogin = false
    @State private var afterLogin: (() -> Void)?

    private var authService: AuthService { AuthService.shared }
    private var predictionService: PredictionService { PredictionService.shared }

    private var totalVotes: Int { predictions.reduce(0) { $0 + $1.voteCount } }

    /// 自分が投票済みの曲 (票数順のまま)。残り票数の算出とシェア文面の両方で使う。
    private var myVotedPredictions: [SetlistPrediction] { predictions.filter(\.hasUserVoted) }

    /// 残り投票可能数 (1公演3票まで)。上限導入前に3票超で投票済みなら 0 に丸める。
    private var remaining: Int { CommunityVoteLimit.remaining(myVoteCount: myVotedPredictions.count) }

    /// 「予想を追加」を押せるか。未ログインはログイン誘導のため常に押せる (残票は投票後に効く)。
    private var canAddVote: Bool { !authService.isSignedIn || remaining > 0 }

    /// 「〇〇に投票しました！」のシェア内容。1票も入れていなければ nil (導線ごと隠す)。
    private var votePayload: SharePayload? {
        let titles = myVotedPredictions.map(\.songTitle)
        guard !titles.isEmpty else { return nil }
        return sharePredictionVotesPayload(showId: showId, showName: showName, songTitles: titles)
    }

    var body: some View {
        Section {
            predictionHeader

            if !authService.isSignedIn {
                ImasSignInPrompt(message: "セトリ予想の投票にはログインが必要です")
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: DS.sp3, trailing: DS.sp5))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            predictionBody
                .listRowInsets(EdgeInsets(top: DS.sp4, leading: DS.sp5, bottom: DS.sp3, trailing: DS.sp5))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            forecastBody
                .listRowInsets(EdgeInsets(top: DS.sp4, leading: DS.sp5, bottom: DS.sp3, trailing: DS.sp5))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .imasSavingOverlay(isCreatingPlaylist, label: playlistProgress.total > 0
                           ? "プレイリスト作成中 \(playlistProgress.current)/\(playlistProgress.total)"
                           : "プレイリスト作成中")
        .animation(.easeInOut(duration: 0.15), value: isCreatingPlaylist)
        .alert("プレイリスト", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .task { await loadPredictions() }
        .task { await forecast.load() }
    }

    /// 予想リスト本体。共通の ImasCardList カードに詰めて、旧 List 行の強いマージンを解消。
    @ViewBuilder
    private var predictionBody: some View {
        if isLoading && predictions.isEmpty {
            ImasInlineLoading()
        } else if predictions.isEmpty {
            ImasEmptyState(systemImage: "music.note.list",
                           title: "まだ予想がありません",
                           message: "「予想を追加」から、来そうな曲に投票しよう",
                           seed: seed)
        } else {
            // 残票 0 なら未投票曲の「予想」ボタンを落とす (押してから 409 で弾かれるより、
            // 押せない理由が見えている方が早い)。行ごとに remaining を引くと
            // filter が行数分走るので、ここで1回だけ畳んで各行に配る。
            let canAdd = remaining > 0
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                ImasCardList {
                    ForEach(Array(predictions.enumerated()), id: \.element.id) { index, prediction in
                        // 行と行の区切りは、ぴったり密着すると詰まって見えるので、
                        // フル幅 Divider + 上下に少し余白を確保する。
                        if index > 0 {
                            ImasRowDivider()
                        }
                        // 投票ボタン自体が投票/取消のトグル (handleVote が hasUserVoted を見て分岐)。
                        // かつて取消導線を .contextMenu で付けていたが、List セル内ボタンに
                        // contextMenu を重ねると long-press ジェスチャがタップを飲み込み、
                        // .borderless ボタンのタップが不発になる (like 行は contextMenu 無しで正常)。
                        // トグルで取消できるので contextMenu は付けない。
                        predictionRow(prediction, rank: index + 1, canAddVote: canAdd)
                    }
                }
                myVoteShareBar
                if let errorMessage {
                    ImasNotice(kind: .error, message: errorMessage)
                }
            }
        }
    }

    /// 機械予測の節。読み込みに失敗したとき・出す曲が無いときは節ごと出さない。
    @ViewBuilder
    private var forecastBody: some View {
        switch forecast.phase {
        case .loading:
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                forecastHeading(note: nil)
                ImasInlineLoading()
            }
        case .unavailable:
            EmptyView()
        case .loaded:
            let songs = forecast.visibleSongs(predictedSongIds: Set(predictions.map(\.songId)))
            if !songs.isEmpty {
                let canAdd = !authService.isSignedIn || remaining > 0
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    forecastHeading(note: forecast.castUnannouncedNote)
                    ImasCardList {
                        ForEach(Array(songs.enumerated()), id: \.element.songId) { index, song in
                            if index > 0 {
                                ImasRowDivider()
                            }
                            forecastRow(song, canPromote: canAdd)
                        }
                    }
                }
            }
        }
    }

    /// 「機械予測」の見出しと注記。出演者未発表の注記はコアの label をそのまま出す。
    private func forecastHeading(note: String?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            ImasSectionHeader("機械予測")
            ImasNote("過去のセトリから推定")
            if let note {
                ImasNote(note, systemImage: "exclamationmark.circle")
            }
        }
    }

    // MARK: - Rows

    /// みんなの予想の 1 曲。押すと投票・取り消し、「歌唱メンバー予想」を開ける。
    private func predictionRow(_ prediction: SetlistPrediction, rank: Int, canAddVote: Bool) -> some View {
        let isExpanded = expandedSongIds.contains(prediction.songId)
        let maxVotes = max(1, predictions.map(\.voteCount).max() ?? 1)
        return ImasForecastRow(
            rank: rank,
            title: prediction.songTitle,
            artworkURL: prediction.artworkUrl.flatMap { URL(string: $0) },
            measure: .votes(prediction.voteCount, share: Double(prediction.voteCount) / Double(maxVotes)),
            preview: prediction.previewUrl.flatMap { URL(string: $0) }.map { ($0, prediction.songId) },
            isMine: prediction.hasUserVoted,
            isVoteDisabled: !canAddVote,
            onVote: { Task { await handleVote(prediction: prediction) } },
            accessory: AnyView(
                Button {
                    AppAnalytics.tap("setlist_prediction.toggle_performers")
                    withAnimation(.easeInOut(duration: 0.18)) { toggleExpand(songId: prediction.songId) }
                } label: {
                    Label("歌唱メンバー予想", systemImage: isExpanded ? "chevron.up" : "person.2")
                }
                .buttonStyle(.imas(.plain, size: .small))
            ),
            expansion: isExpanded
                ? AnyView(PerformerPredictionView(showId: prediction.showId, songId: prediction.songId,
                                                  seed: seed, requireLogin: requireLogin))
                : nil
        )
    }

    /// 機械予測の 1 曲。根拠はオリメン (誰が出るか) と理由 (コアの文言)。
    private func forecastRow(_ song: ForecastSongRecord, canPromote: Bool) -> some View {
        let originals = song.originals
        let reasons = song.reasons.map(\.label).joined(separator: "・")
        let performers = (originals?.namesListed == true ? originals?.members ?? [] : []).map {
            ImasPerformer(id: $0.idolId, name: $0.name, color: $0.color, isAbsent: $0.attending == false)
        }
        let originalsSummary = originals.flatMap { $0.namesListed ? nil : ($0.summary.isEmpty ? nil : $0.summary) }
        let hasOriginalsLine = !performers.isEmpty || originalsSummary != nil
        return ImasForecastRow(
            rank: Int(song.rank),
            title: song.title,
            artworkURL: song.artworkUrl.flatMap { URL(string: $0) },
            brand: BrandColors.hex(for: song.brandId),
            measure: .probability(song.score),
            reasonLabel: hasOriginalsLine ? "オリメン" : (reasons.isEmpty ? nil : "理由"),
            reason: hasOriginalsLine ? originalsSummary : (reasons.isEmpty ? nil : reasons),
            performers: performers,
            secondReason: hasOriginalsLine && !reasons.isEmpty ? ("理由", reasons) : nil,
            preview: song.previewUrl.flatMap { URL(string: $0) }.map { ($0, song.songId) },
            isVoteDisabled: !canPromote || forecast.promotingSongId != nil,
            isVoting: forecast.promotingSongId == song.songId,
            onVote: { Task { await promoteForecast(songId: song.songId) } }
        )
    }

    /// 自分の予想をまとめてシェアする導線。1票も入れていない間は出さない。
    @ViewBuilder
    private var myVoteShareBar: some View {
        if let votePayload {
            let t = ImasTheme.derive(seed: seed, scheme: scheme)
            HStack(spacing: DS.sp2) {
                Text("あなたの予想 \(myVotedPredictions.count)/\(CommunityVoteLimit.perTarget)")
                    .imasText(.meta, color: DS.ink3)
                Spacer(minLength: 8)
                SocialShareMenu(payload: votePayload, analyticsKey: "setlist_prediction.share") {
                    SocialShareChipLabel(title: "予想をシェア", accent: t.accent)
                }
                .accessibilityLabel("自分のセトリ予想をシェア")
            }
            .padding(.top, DS.sp1)
        }
    }

    // MARK: - Header

    /// セクション見出し + 文脈投稿導線。コミュニティ投稿 (タグ/動画/投票) の
    /// communityHeader と同じ「タイトル + アクセント色の＋投稿ボタン」パターンに揃える。
    private var predictionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
            ImasSectionHeader("セトリ予想", count: totalVotes > 0 ? "\(totalVotes)票" : nil)
                .fixedSize()
            // 残り票数はログイン済みのときだけ意味を持つ (未ログインは常に3票のままなので出さない)。
            if authService.isSignedIn {
                Text("残り\(remaining)/\(CommunityVoteLimit.perTarget)")
                    .imasText(.meta, color: remaining > 0 ? DS.ink3 : DS.danger)
            }
            Spacer(minLength: DS.Space.gap)
            Button {
                // 未ログインでも押せる。押したらログイン誘導 → 完了後に picker を開く。
                requireLogin {
                    presentSongPicker { songs in
                        Task { await addPredictions(songs: songs) }
                    }
                }
            } label: {
                Label("予想を追加", systemImage: "plus")
            }
            .buttonStyle(.imas(.secondary, size: .small))
            .disabled(!canAddVote)

            utilitiesMenu
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: DS.sp4, trailing: 16))
        // ヘッダは常時表示で安定しているのでログイン sheet のホストに使う
        // (InlineLoginPrompt はログイン後に消えるためホストにできない)。
        .sheet(isPresented: $showLogin) {
            LoginToEditSheet(onSignedIn: {
                let action = afterLogin
                afterLogin = nil
                // login sheet の dismiss を待ってから次の picker sheet を開く (二重 sheet 回避)。
                if let action {
                    Task { try? await Task.sleep(for: .milliseconds(350)); action() }
                }
            })
        }
    }

    /// プレイリスト作成・プレビュー再生などの補助操作 (投稿ではないので ⋯ に集約)。
    private var utilitiesMenu: some View {
        Menu {
            Button {
                Task { await addToAppleMusicPlaylist() }
            } label: {
                Label("Appleプレイリスト作成", systemImage: "music.note.list")
            }
            .disabled(predictions.isEmpty)

            Button {
                Task { await playAllPreviews() }
            } label: {
                Label("上位曲をプレビュー再生", systemImage: "play.fill")
            }
            .disabled(predictions.isEmpty)

            if MusicKitService.shared.isPlaying {
                Button(role: .destructive) {
                    MusicKitService.shared.stop()
                } label: {
                    Label("再生停止", systemImage: "stop.fill")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imasText(.value, color: DS.ink2)
                .accessibilityLabel("操作")
        }
    }

    // MARK: - Data

    private func loadPredictions() async {
        isLoading = true
        errorMessage = nil
        do {
            // songId をキー (SetlistPrediction.id) にしているので、重複があると
            // ForEach の id 衝突で展開状態が混線する。念のため songId で一意化する。
            var seen = Set<String>()
            predictions = try await predictionService.fetch(showId: showId)
                .filter { seen.insert($0.songId).inserted }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleExpand(songId: String) {
        if expandedSongIds.contains(songId) {
            expandedSongIds.remove(songId)
        } else {
            expandedSongIds.insert(songId)
        }
    }

    /// 複数曲をまとめて予想追加 (picker の複数選択に対応)。順番に投票し、最後に1回だけ再読込。
    /// 残票を超える選択は先頭から残票分だけ投票し、溢れた分はメッセージで伝える
    /// (サーバも 409 で弾くが、何票入ったのかを画面側で確定させる)。
    private func addPredictions(songs: [Song]) async {
        guard authService.isSignedIn, !songs.isEmpty else { return }
        // 投票済みの曲は残票を消費しない。どれを入れてどれが溢れるかはコア (`planVoteSelection`)。
        let plan = planVoteSelection(
            alreadyVoted: myVotedPredictions.map(\.songId), selectedInOrder: songs.map(\.id),
            myVoteCount: UInt32(clamping: myVotedPredictions.count), unvoteDeselected: false)
        let overflow = Int(plan.overflow)
        var failed = 0
        for songId in plan.toVote {
            do {
                _ = try await predictionService.vote(showId: showId, songId: songId)
            } catch {
                failed += 1
                Logger.community.error("add_prediction_failed song=\(songId, privacy: .public): \(error.localizedDescription)")
            }
        }
        // loadPredictions() が errorMessage をクリアするので、メッセージは再読込の後に立てる。
        let notice: String? = if failed > 0 {
            "\(failed)曲の追加に失敗しました"
        } else if overflow > 0 {
            "1公演\(CommunityVoteLimit.perTarget)票までなので、\(overflow)曲は投票できませんでした"
        } else {
            nil
        }
        await loadPredictions()
        if let notice { errorMessage = notice }
    }

    /// ログイン必須アクションのゲート。未ログインならログイン誘導 → 完了後に action を実行。
    private func requireLogin(_ action: @escaping () -> Void) {
        if authService.isSignedIn {
            action()
        } else {
            afterLogin = action
            showLogin = true
        }
    }

    private func handleVote(prediction: SetlistPrediction) async {
        guard authService.isSignedIn else {
            // 未ログインで投票トグルを押したら、エラー表示ではなくログイン誘導から始める。
            requireLogin { Task { await handleVote(prediction: prediction) } }
            return
        }
        do {
            if prediction.hasUserVoted {
                try await predictionService.unvote(showId: showId, songId: prediction.songId)
            } else {
                _ = try await predictionService.vote(showId: showId, songId: prediction.songId)
            }
            await loadPredictions()
        } catch {
            errorMessage = error.localizedDescription
            AppAnalytics.event("prediction_vote_failed")
        }
    }

    /// 機械予測の曲を予想に入れる (格上げ)。認証・エラーの扱いは `handleVote` と同じ。
    private func promoteForecast(songId: String) async {
        guard authService.isSignedIn else {
            requireLogin { Task { await promoteForecast(songId: songId) } }
            return
        }
        do {
            try await forecast.promote(songId: songId)
            await loadPredictions()
        } catch {
            errorMessage = error.localizedDescription
            AppAnalytics.event("prediction_vote_failed")
        }
    }

    // MARK: - Apple Music

    private func addToAppleMusicPlaylist() async {
        // 認可は起動時に取らないので、使う直前に取る (契約の有無もここで読み直す)。
        await MusicKitService.shared.requestAuthorization()
        guard MusicKitService.shared.hasAppleMusicSubscription else {
            alertMessage = "Apple Musicのサブスクリプションが必要です"
            showAlert = true
            return
        }

        let targetPredictions = predictions.prefix(20)
        let songIds: [MusicItemID] = targetPredictions.compactMap { pred in
            guard let amId = pred.appleMusicId, !amId.isEmpty else { return nil }
            return MusicItemID(rawValue: amId)
        }

        guard !songIds.isEmpty else {
            alertMessage = "Apple Music IDが登録されている曲がありません"
            showAlert = true
            return
        }

        isCreatingPlaylist = true
        playlistProgress = (0, songIds.count)
        defer { isCreatingPlaylist = false }

        do {
            var songs: [MusicKit.Song] = []
            for (index, id) in songIds.enumerated() {
                // MusicCatalogResourceRequest は非 Sendable。@MainActor の文脈で作って
                // await すると隔離境界を越えるので、nonisolated な口の中で作って返す。
                if let song = try await Self.fetchCatalogSong(id: id) {
                    songs.append(song)
                }
                playlistProgress = (index + 1, songIds.count)
            }

            playlistProgress = (0, songs.count)
            let playlist = try await MusicLibrary.shared.createPlaylist(
                name: "\(showName) 予想セトリ",
                description: "アイドルライブDB 予想セトリから作成"
            )
            for (index, song) in songs.enumerated() {
                try await MusicLibrary.shared.add(song, to: playlist)
                playlistProgress = (index + 1, songs.count)
            }

            alertMessage = "「\(showName) 予想セトリ」プレイリストを作成しました（\(songs.count)曲）"
            showAlert = true
        } catch {
            alertMessage = "プレイリスト作成に失敗しました: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func playAllPreviews() async {
        let targets = predictions.prefix(20)
        for prediction in targets {
            guard let previewUrlStr = prediction.previewUrl,
                  let previewURL = URL(string: previewUrlStr) else { continue }
            MusicKitService.shared.togglePreview(url: previewURL, songId: prediction.songId)
            try? await Task.sleep(for: .seconds(32))
            if !MusicKitService.shared.isPlaying { break }
        }
    }
}
