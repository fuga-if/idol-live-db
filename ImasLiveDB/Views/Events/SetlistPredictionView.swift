import MusicKit
import os
import SwiftUI

// MARK: - SetlistPredictionView

struct SetlistPredictionView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
    /// 予想は公演 (show) 単位。 同じイベントでも DAY1/DAY2 でセトリが違うため。
    let showId: String
    /// ヘッダ表示用 (show.name そのまま渡す想定)。
    let showName: String
    /// 投稿導線の文脈色 (公演のブランド色)。他の投稿UI (コーレス/動画/タグ) と揃える。
    var seed: String? = nil

    /// 「曲を追加」タップ時に親 (SetlistView) の安定した List 上で picker sheet を開いてもらう。
    /// sheet を Section に直接付けると、predictions 更新で行が再評価され初回 sheet が即閉じするため、
    /// presentation surface は親が持ち、ここは onSelect ハンドラ (addPredictions) だけ渡す。
    /// 複数選択に対応 (1回の起動でまとめて予想追加できる)。
    let presentSongPicker: (@escaping ([Song]) -> Void) -> Void

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

    var body: some View {
        Section {
            predictionHeader

            if !authService.isSignedIn {
                InlineLoginPrompt(message: "セトリ予想の投票にはログインが必要です", seed: seed)
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: DS.sp3, trailing: DS.sp5))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            predictionBody
                .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: DS.sp3, trailing: DS.sp5))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .overlay {
            if isCreatingPlaylist {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.large)
                        Text(playlistProgress.total > 0
                             ? "プレイリスト作成中… \(playlistProgress.current)/\(playlistProgress.total)"
                             : "プレイリスト作成中…")
                            .font(.imasSubhead)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isCreatingPlaylist)
        .alert("プレイリスト", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .task { await loadPredictions() }
    }

    /// 予想リスト本体。共通の ImasListContainer カードに詰めて、旧 List 行の強いマージンを解消。
    @ViewBuilder
    private var predictionBody: some View {
        if isLoading && predictions.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, DS.sp4)
        } else if predictions.isEmpty {
            ImasEmptyState(systemImage: "music.note.list",
                           title: "まだ予想がありません",
                           message: "「予想を追加」から、来そうな曲に投票しよう",
                           seed: seed)
        } else {
            VStack(alignment: .leading, spacing: DS.sp2) {
                ImasListContainer {
                    ForEach(Array(predictions.enumerated()), id: \.element.id) { index, prediction in
                        if index > 0 { Divider().overlay(DS.sep).padding(.leading, 58) }
                        // 投票ボタン自体が投票/取消のトグル (handleVote が hasUserVoted を見て分岐)。
                        // かつて取消導線を .contextMenu で付けていたが、List セル内ボタンに
                        // contextMenu を重ねると long-press ジェスチャがタップを飲み込み、
                        // .borderless ボタンのタップが不発になる (like 行は contextMenu 無しで正常)。
                        // トグルで取消できるので contextMenu は付けない。
                        PredictionRowView(
                            prediction: prediction,
                            rank: index + 1,
                            seed: seed,
                            isExpanded: expandedSongIds.contains(prediction.songId),
                            onToggleExpand: { toggleExpand(songId: prediction.songId) },
                            onVote: { await handleVote(prediction: prediction) },
                            requireLogin: requireLogin
                        )
                    }
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.imasCaption).foregroundStyle(DS.danger)
                        .padding(.leading, DS.sp1)
                }
            }
        }
    }

    // MARK: - Header

    /// セクション見出し + 文脈投稿導線。コミュニティ投稿 (タグ/コーレス/動画/投票) の
    /// communityHeader と同じ「タイトル + アクセント色の＋投稿ボタン」パターンに揃える。
    private var predictionHeader: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("セトリ予想").font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                if totalVotes > 0 {
                    Text("\(totalVotes)票").font(.imasFootnote.weight(.semibold)).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 12)

                Button {
                    // 未ログインでも押せる。押したらログイン誘導 → 完了後に picker を開く。
                    requireLogin {
                        presentSongPicker { songs in
                            Task { await addPredictions(songs: songs) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.imasScaled( 13, weight: .semibold))
                        Text("予想を追加").font(.imasScaled( 14, weight: .semibold))
                    }
                    .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)

                utilitiesMenu
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
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
                .font(.imasSubhead)
                .foregroundStyle(DS.ink2)
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
    private func addPredictions(songs: [Song]) async {
        guard authService.isSignedIn, !songs.isEmpty else { return }
        var failed = 0
        for song in songs {
            do {
                // 既に投票済み (alreadyVoted) でもサーバが現在の票数を返すだけなので、結果は再読込で吸収する。
                _ = try await predictionService.vote(showId: showId, songId: song.id)
            } catch {
                failed += 1
                Logger.community.error("add_prediction_failed song=\(song.id, privacy: .public): \(error.localizedDescription)")
            }
        }
        if failed > 0 {
            errorMessage = "\(failed)曲の追加に失敗しました"
        }
        await loadPredictions()
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

    // MARK: - Apple Music

    private func addToAppleMusicPlaylist() async {
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
                let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: id)
                if let song = try await request.response().items.first {
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
            MusicKitService.shared.togglePreview(url: previewURL, title: prediction.songTitle)
            try? await Task.sleep(for: .seconds(32))
            if !MusicKitService.shared.isPlaying { break }
        }
    }
}

// MARK: - PredictionRowView

/// 予想セトリ1行 (DS共通トークン)。ランク + ジャケ(プレビュー再生) + 曲名/票数 + 投票トグル。
/// 下部に「誰が歌う？」展開ブロックを持つ。
private struct PredictionRowView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
    let prediction: SetlistPrediction
    let rank: Int
    var seed: String? = nil
    /// 「歌唱メンバー予想」の展開状態は親 (SetlistPredictionView) が songId キーで保持する。
    /// 行ローカル @State にすると List 再描画/id 衝突で他行へ漏れるため、親から注入する。
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onVote: () async -> Void
    /// 「誰が歌う？」の未ログイン投票導線用。親 SetlistPredictionView の requireLogin をそのまま流す。
    let requireLogin: (@escaping () -> Void) -> Void

    private var artworkURL: URL? { prediction.artworkUrl.flatMap { URL(string: $0) } }
    private var previewURL: URL? { prediction.previewUrl.flatMap { URL(string: $0) } }

    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.sp3) {
                Text("\(rank)")
                    .font(.imasCaption.monospacedDigit())
                    .foregroundStyle(DS.ink3)
                    .frame(width: 22, alignment: .trailing)

                ArtworkImageView(
                    url: artworkURL,
                    size: 44,
                    previewURL: previewURL,
                    songTitle: prediction.songTitle,
                    seed: seed
                )

                VStack(alignment: .leading, spacing: DS.sp2) {
                    Text(prediction.songTitle)
                        .font(.imasSubhead.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.imasScaled( 10))
                            .foregroundStyle(DS.ink3)
                        Text("\(prediction.voteCount)票")
                            .font(.imasCaption.monospacedDigit())
                            .foregroundStyle(DS.ink2)
                    }
                }

                Spacer(minLength: 4)

                // 投票 = Good ボタン (★お気に入り/★like と区別するため thumbsup)。右寄せ。
                Button {
                    Task { await onVote() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: prediction.hasUserVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.imasSubhead.weight(.semibold))
                        Text(prediction.hasUserVoted ? "投票済" : "予想")
                            .font(.imasCaption.weight(.semibold))
                    }
                    .foregroundStyle(prediction.hasUserVoted ? t.onAccent : t.accent)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(prediction.hasUserVoted ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.chipBg),
                                in: Capsule())
                    .contentShape(Capsule())
                    .accessibilityLabel(prediction.hasUserVoted ? "投票を取り消す" : "この曲に投票")
                }
                // List セル内に複数ボタンがある時 .plain だとタップがセル全体に散って効かない。
                // .borderless で各ボタンにタップをスコープする。
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.top, DS.sp3)
            .padding(.bottom, DS.sp2)
            .contentShape(Rectangle())

            // MARK: 「誰が歌う？」展開ブロック
            performerToggle(theme: t)

            if isExpanded {
                PerformerPredictionView(
                    showId: prediction.showId,
                    songId: prediction.songId,
                    seed: seed,
                    requireLogin: requireLogin
                )
                .padding(.horizontal, DS.sp4)
                .padding(.bottom, DS.sp3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    /// 「歌唱メンバー予想」トグルボタン。小さめの補助行として曲行下端に配置。
    private func performerToggle(theme t: ImasTheme) -> some View {
        Button {
            AppAnalytics.tap("setlist_prediction.toggle_performers")
            onToggleExpand()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.2")
                    .font(.imasScaled(10, weight: .semibold))
                Text("歌唱メンバー予想")
                    .font(.imasScaled(12, weight: .medium))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.imasScaled(9, weight: .semibold))
            }
            .foregroundStyle(DS.ink3)
            .padding(.horizontal, DS.sp4)
            .padding(.top, DS.sp2)
            .padding(.bottom, isExpanded ? DS.sp2 : DS.sp3)
        }
        .buttonStyle(.borderless)
    }
}

