import AVFoundation
import Combine
import Foundation
import MediaPlayer
import os
import MusicKit
import Observation

struct MusicKitSongInfo: Sendable {
    let artworkURL: URL?
    let previewURL: URL?
    let appleMusicURL: URL?
    let musicKitId: MusicItemID?
}

// NSCache は参照型のみ格納できるためラッパーが必要
private final class Boxed<T>: @unchecked Sendable {
    let value: T
    init(_ v: T) { value = v }
}

@Observable @MainActor
final class MusicKitService {
    private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    private(set) var hasAppleMusicSubscription: Bool = false
    private(set) var isPlaying = false { didSet { syncPlayFlags() } }
    /// 鳴っている曲の `songs.id`。
    ///
    /// **曲名で持ってはいけない。** 「私はアイドル♡ (M@STER VERSION)」のように
    /// 同名で歌唱者の違う録音が実在するので、曲名で同一性を見ると別バージョンの
    /// ジャケと名義が出る。再生中バーの引き当てもここを使う。
    private(set) var nowPlayingSongId: String? { didSet { syncPlayFlags() } }
    private(set) var isFullPlayback = false
    /// フル尺をどこで鳴らしているか。Spotify は利用者の Spotify アプリを操作して鳴らす (`SpotifyRemotePlayer`)。
    enum FullSource { case appleMusic, spotify }
    private(set) var fullSource: FullSource = .appleMusic
    /// Spotify で鳴らせなかった理由。画面 (ContentView) が出して `clearSpotifyFailure` で消す。
    private(set) var spotifyFailure: SpotifyFailure?
    @ObservationIgnored private let spotifyRemote = SpotifyRemotePlayer()
    /// 積んだ Spotify の曲 id → `songs.id`。
    @ObservationIgnored private var songIdBySpotifyTrackId: [String: String] = [:]
    /// フル再生で ApplicationMusicPlayer に曲を積んだか (止めるときに queue を解放する必要があるか)。
    @ObservationIgnored private var usedApplicationPlayer = false

    /// フル再生で積んだ曲の `songs.id` (積んだ順)。1 曲だけ鳴らしたときは 1 つ。
    private(set) var queueSongIds: [String] = []
    /// いま鳴っている曲が `queueSongIds` の何番目か。
    private(set) var queueIndex: Int?
    /// 積んだ Apple Music の id → `songs.id`。曲が替わったときに引き当てる。
    @ObservationIgnored private var songIdByMusicKitId: [MusicItemID: String] = [:]
    @ObservationIgnored private var playerObservers: Set<AnyCancellable> = []

    /// 積んだ曲を流し終えそうになったら「次はこれ」を足して流し続けるか (端末の設定。既定は切。
    /// 入れ切りは「次に流れる曲」の ∞)。
    var autoplayNext: Bool = UserDefaults.standard.object(forKey: MusicKitService.autoplayKey) as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(autoplayNext, forKey: Self.autoplayKey)
            if autoplayNext { appendNextIfNeeded() }
        }
    }
    // 既定を切に変えたので鍵も替える (前の既定「入」で保存された値を引き継がない)。
    private static let autoplayKey = "music.autoplay_next.v2"
    /// 「次はこれ」で足した曲の理由 (songs.id → 「同じ公演で 12 回」など)。
    private(set) var recommendedLabels: [String: String] = [:]
    /// この再生で流した曲 (同じ曲に戻らないよう「次はこれ」から外す)。
    @ObservationIgnored private var playedSongIds: [String] = []
    @ObservationIgnored private var isAppendingNext = false

    /// この曲が今このアプリで鳴っているか。
    ///
    /// 「`isPlaying` かつ id 一致」という同じ式が 5 画面に写経されていて、
    /// 曲名 → id の付け替え時に 5 箇所を手で直す羽目になった。突き合わせ方は
    /// ここ 1 箇所に持つ。
    func isPlaying(songId: String) -> Bool {
        isPlaying && nowPlayingSongId == songId
    }

    /// 一覧の行が「自分の曲が鳴っているか」だけを見るための印 (曲ごとに 1 つ)。
    ///
    /// 行が `isPlaying(songId:)` を読むと、どの曲の再生を始めても止めても**見えている全行**が
    /// 描き直しになる (全行が同じ `isPlaying` / `nowPlayingSongId` に依存するため)。
    /// 曲ごとの印を読めば、変わった曲 (止めた曲と鳴らした曲) の行だけが描き直される。
    func playFlag(songId: String) -> SongPlayFlag {
        if let hit = playFlags[songId] { return hit }
        let flag = SongPlayFlag(isPlaying: isPlaying(songId: songId))
        playFlags[songId] = flag
        return flag
    }

    @ObservationIgnored private var playFlags: [String: SongPlayFlag] = [:]

    private func syncPlayFlags() {
        for (id, flag) in playFlags {
            let on = isPlaying && nowPlayingSongId == id
            if flag.isPlaying != on { flag.isPlaying = on }
        }
    }

    /// この曲がフル尺 (Apple Music のカタログ再生) で鳴っているか。
    func isPlayingFull(songId: String) -> Bool {
        isPlaying(songId: songId) && isFullPlayback
    }

    /// 鳴らし方。再生中バーに渡す。
    var nowPlayingKind: NowPlayingKind { isFullPlayback ? .full : .preview }

    /// 再生状態がひとまとまりで変わったことを表す値。
    ///
    /// 3 つのフラグは必ず同時に書き換わる (togglePreview / playFull / stop / pause / resume)
    /// ので、監視側は 1 つ見れば足りる。`.task(id:)` の鍵にして、バーの引き直しを
    /// 「状態が変わったとき 1 回」に閉じるために置いている。
    var playbackKey: String {
        "\(nowPlayingSongId ?? "-")|\(isPlaying)|\(isFullPlayback)"
    }

    /// フル尺をどのサービスで鳴らすか (選び方はコア)。どちらも使えなければ nil (試聴に落とす)。
    var fullPlaybackService: FullPlaybackService? {
        let spotify = SpotifyService.shared
        return chooseFullPlayback(preference: spotify.fullPlaybackPreference,
                                  appleMusicReady: hasAppleMusicSubscription,
                                  spotifyReady: spotify.isConnected && spotify.canControlPlayback)
    }

    func clearSpotifyFailure() { spotifyFailure = nil }

    /// Spotify アプリから戻ってきた (`imaslivedb://spotify-callback`)。SDK の繋ぎ直しに使う。
    func handleSpotifyCallback(_ url: URL) { spotifyRemote.handleCallback(url) }

    /// LRU キャッシュ（最大500件）
    private let cache: NSCache<NSString, Boxed<MusicKitSongInfo?>> = {
        let c = NSCache<NSString, Boxed<MusicKitSongInfo?>>()
        c.countLimit = 500
        return c
    }()

    private var player: AVPlayer?
    private var endObserverToken: NSObjectProtocol?
    private let musicPlayer = ApplicationMusicPlayer.shared
    /// 契約の変化の監視を張ったか (何度認可を取り直しても 1 本だけにする)。
    private var isObservingSubscription = false

    static let shared = MusicKitService()
    private init() {
        spotifyRemote.onChange = { [weak self] in self?.syncFromSpotify($0) }
        spotifyRemote.onFailure = { [weak self] failure in
            self?.spotifyFailure = failure
            if self?.fullSource == .spotify, SpotifyRemotePlayer.stopsPlayback(failure) {
                self?.stop(pausingSpotify: false)
            }
        }
    }

    /// Apple Music の認可を取り、契約の有無を読み直す。
    ///
    /// 起動時には呼ばない。使う画面 (曲詳細・セトリ・イントロクイズ・フル再生) が、使う直前に呼ぶ。
    /// 既に決まっていれば尋ねずにすぐ戻るので、何度呼んでもよい。
    ///
    /// - Parameter includingMediaLibrary: 端末のライブラリの認可も取る (イントロクイズだけ)。
    ///   カタログのストリーミング再生が失敗する曲 (Orange Sapphire game version 等) を
    ///   ライブラリ経由で鳴らす経路 (本家 IntroQuiz 方式) に要る。他の画面では尋ねない。
    func requestAuthorization(includingMediaLibrary: Bool = false) async {
        authorizationStatus = await MusicAuthorization.request()
        await checkSubscription()
        if includingMediaLibrary, MPMediaLibrary.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                MPMediaLibrary.requestAuthorization { _ in
                    continuation.resume()
                }
            }
        }
        guard !isObservingSubscription else { return }
        isObservingSubscription = true
        Task { await observeSubscriptionUpdates() }
    }

    /// 許可済みなら契約の有無だけ読み直す (尋ねない)。どちらで鳴らすかを見せる画面が、開いたときに呼ぶ。
    /// 起動時には契約を読まないので、読む前は「契約なし」に見えて Spotify が選ばれて見える。
    func checkSubscriptionIfAuthorized() async {
        guard MusicAuthorization.currentStatus == .authorized else { return }
        authorizationStatus = .authorized
        await checkSubscription()
    }

    @MainActor
    private func checkSubscription() async {
        do {
            let sub = try await MusicSubscription.current
            hasAppleMusicSubscription = sub.canPlayCatalogContent
        } catch {
            hasAppleMusicSubscription = false
            Logger.musickit.warning("subscription_check_failed: \(error.localizedDescription)")
        }
    }

    private func observeSubscriptionUpdates() async {
        for await update in MusicSubscription.subscriptionUpdates {
            await MainActor.run {
                self.hasAppleMusicSubscription = update.canPlayCatalogContent
            }
        }
    }

    /// 楽曲情報取得
    /// DB の `apple_music_id` がある曲のみ MusicKit から info を取得する。
    /// タイトル検索フォールバックは別曲ヒットの誤検出が多いため撤廃。その置き土産で
    /// `title:` 引数が本体で使われないまま残っていたので落とした (曲名では引き当てない)。
    /// 未登録曲は MusicKit 連携 (アートワーク・プレビュー・Apple Music リンク) を一切表示しない。
    func fetchSongInfo(appleMusicId: String?) async -> MusicKitSongInfo? {
        guard let appleMusicId, !appleMusicId.isEmpty else { return nil }
        let cacheKey = appleMusicId
        if let boxed = cache.object(forKey: cacheKey as NSString) { return boxed.value }
        // カタログを引くには認可が要る。起動時には取らないので、使う直前のここで取る。
        // 認可が無いまま引くと失敗が「この曲は無い」としてキャッシュに残るので、引かずに返す。
        // 求めるのはまだ決まっていないときだけ。拒否・制限の後に曲を開くたび求め直すと、
        // そのたびに加入状況の確認まで走る (尋ねる画面はもう出ないので結果も変わらない)。
        if authorizationStatus == .notDetermined { await requestAuthorization() }
        guard authorizationStatus == .authorized else { return nil }
        return await fetchById(appleMusicId: appleMusicId, cacheKey: cacheKey)
    }

    // MARK: - Playback

    /// プレビュー再生（30秒、誰でも可）
    func togglePreview(url: URL, songId: String) {
        if isPlaying(songId: songId) {
            stop()
        } else {
            stop()
            let playerItem = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: playerItem)

            endObserverToken = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }

            // 押した印は先に切り替える (音の準備を待たせない)。
            isPlaying = true
            isFullPlayback = false
            nowPlayingSongId = songId
            // 音声セッションの設定は重い (主スレッドで呼ぶと押してから印が変わるまで固まる) ので外で。
            let player = self.player
            Task.detached(priority: .userInitiated) {
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback)
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    Logger.musickit.error("avaudiosession_setup_failed: \(error.localizedDescription)")
                }
                // 準備の間に止められたり別の曲に替わっていたら鳴らさない。
                await MainActor.run { [weak self] in
                    guard let self, let player, self.player === player, self.isPlaying else { return }
                    player.play()
                }
            }
        }
    }

    /// 一覧の行の再生ボタン。Apple Music で鳴らせればフル尺、鳴らせなければ試聴 (30 秒)。
    ///
    /// 契約の有無は最初の 1 回だけ読む (以降は `observeSubscriptionUpdates` が追う)。
    /// 行を押すたびに読み直すと、未契約の人は押すごとに確認の往復を待たされる。
    func toggleSong(songId: String, appleMusicId: String?, previewURL: URL?) async {
        if isPlaying(songId: songId) {
            stop()
            return
        }
        if await playFullSongs([(songId: songId, appleMusicId: appleMusicId)], startAt: 0) { return }
        // Spotify で鳴らすつもりで鳴らせなかった (アプリが開いていない等) ときは、理由を出して試聴には落とさない。
        if spotifyFailure != nil { return }
        // 未契約・配信なし・カタログから消えた曲は試聴へ落とす。
        if let previewURL { togglePreview(url: previewURL, songId: songId) }
    }

    /// 曲をフル尺で鳴らす。Apple Music か Spotify か (`fullPlaybackService`) で振り分ける。
    ///
    /// - Parameters:
    ///   - entries: 積む順の `songs.id` と Apple Music の id (無い曲は nil。Spotify は曲名で探す)。
    ///   - startAt: `entries` の何番目から鳴らすか。その曲が鳴らせなければ、次に鳴らせる曲から。
    /// - Returns: フル尺で鳴り始めたか。
    @discardableResult
    func playFullSongs(_ entries: [(songId: String, appleMusicId: String?)], startAt: Int) async -> Bool {
        spotifyFailure = nil
        // Spotify を選んでいて使えるなら、Apple Music の許可は尋ねない (使わない人に出さない)。
        let spotify = SpotifyService.shared
        let prefersSpotify = spotify.fullPlaybackPreference == .spotify && spotify.isConnected && spotify.canControlPlayback
        if !prefersSpotify, !isObservingSubscription { await requestAuthorization() }
        switch fullPlaybackService {
        case .spotify?:
            return await playSpotify(entries.map(\.songId), startAt: startAt)
        case .appleMusic?:
            let playable = entries.compactMap { entry in
                entry.appleMusicId.flatMap { $0.isEmpty ? nil : (songId: entry.songId, appleMusicId: $0) }
            }
            guard !playable.isEmpty else { return false }
            let start = entries[min(startAt, entries.count - 1)...].lazy
                .compactMap { e in playable.firstIndex { $0.songId == e.songId } }.first ?? 0
            await playQueue(playable, startAt: start)
            return isFullPlayback
        case nil:
            return false
        }
    }

    /// Spotify で鳴らす。並べる曲を先に Spotify で探し (覚えている曲は探さない。探すのは並行で)、
    /// 見つかった曲だけを並べて、押した曲 (無ければその後ろで最初に見つかった曲) から鳴らす。
    ///
    /// 「次はこれ」は Spotify では足さない。足すには Spotify の「次に再生」に積むしかなく、
    /// それは鳴らし直しても消えずに次の再生へ割り込むため。
    private func playSpotify(_ songIds: [String], startAt: Int) async -> Bool {
        guard !songIds.isEmpty else { return false }
        let spotify = SpotifyService.shared
        let uris = await spotify.trackURIs(songIds: songIds)
        let playable = songIds.indices.compactMap { i in uris[i].map { (songId: songIds[i], uri: $0, index: i) } }
        guard let start = playable.firstIndex(where: { $0.index >= startAt }) ?? playable.indices.first else { return false }
        stop(pausingSpotify: false)
        do {
            try await spotifyRemote.play(uris: playable.map(\.uri), offset: start)
        } catch let failure as SpotifyWebAPI.Failure {
            spotifyFailure = failure.kind
            return false
        } catch {
            return false
        }
        fullSource = .spotify
        queueSongIds = playable.map(\.songId)
        queueIndex = start
        songIdBySpotifyTrackId = Dictionary(
            playable.compactMap { p in SpotifyRemotePlayer.trackId(fromURI: p.uri).map { ($0, p.songId) } },
            uniquingKeysWith: { first, _ in first })
        isPlaying = true
        isFullPlayback = true
        nowPlayingSongId = playable[start].songId
        recommendedLabels = [:]
        playedSongIds = [playable[start].songId]
        return true
    }

    /// Spotify の状態をこちらへ写す (曲が替わった・Spotify アプリ側で止めた)。
    /// このアプリが積んでいない曲に替わったら (Spotify アプリで別の曲を選んだ)、追うのをやめる。
    private func syncFromSpotify(_ snapshot: SpotifyRemotePlayer.Snapshot?) {
        guard fullSource == .spotify, isFullPlayback else { return }
        guard let snapshot, let trackId = snapshot.trackId else {
            if isPlaying { isPlaying = false }
            return
        }
        guard let songId = songIdBySpotifyTrackId[trackId] else {
            stop(pausingSpotify: false)
            return
        }
        if songId != nowPlayingSongId {
            nowPlayingSongId = songId
            queueIndex = queueSongIds.firstIndex(of: songId)
            playedSongIds.append(songId)
            appendNextIfNeeded()
        }
        if snapshot.isPlaying != isPlaying { isPlaying = snapshot.isPlaying }
    }

    /// フル再生（Apple Musicサブスクユーザーのみ）
    nonisolated func playFull(songInfo: MusicKitSongInfo, songId: String) async {
        guard let musicKitId = songInfo.musicKitId else { return }
        await playQueue([(songId: songId, appleMusicId: musicKitId.rawValue)], startAt: 0)
    }

    /// 曲を順に積んでフル再生する (プレイリスト)。Apple Music に無い曲は飛ばす。
    ///
    /// - Parameters:
    ///   - entries: 積む順の `songs.id` と Apple Music の id。
    ///   - startAt: `entries` の何番目から鳴らすか。その曲が Apple Music に無ければ、次に鳴らせる曲から。
    nonisolated func playQueue(_ entries: [(songId: String, appleMusicId: String)], startAt: Int) async {
        guard !entries.isEmpty else { return }
        await stop()

        do {
            let ids = entries.map { MusicItemID($0.appleMusicId) }
            let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, memberOf: ids)
            let response = try await request.response()
            let byId = Dictionary(response.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // 応答の並びは保証されないので、積む順は entries に合わせる。
            let playable = entries.enumerated().compactMap { offset, entry in
                byId[MusicItemID(entry.appleMusicId)].map { (offset: offset, songId: entry.songId, song: $0) }
            }
            guard let start = playable.firstIndex(where: { $0.offset >= startAt }) ?? playable.indices.first
            else { return }

            let player = ApplicationMusicPlayer.shared
            player.queue = ApplicationMusicPlayer.Queue(for: playable.map(\.song), startingAt: playable[start].song)
            try await player.play()
            let songIds = playable.map(\.songId)
            let map = Dictionary(playable.map { ($0.song.id, $0.songId) }, uniquingKeysWith: { first, _ in first })
            await MainActor.run {
                self.usedApplicationPlayer = true
                self.queueSongIds = songIds
                self.songIdByMusicKitId = map
                self.queueIndex = start
                self.isPlaying = true
                self.isFullPlayback = true
                self.nowPlayingSongId = songIds[start]
                self.recommendedLabels = [:]
                self.playedSongIds = [songIds[start]]
                self.observePlayer()
                self.appendNextIfNeeded()
            }
        } catch {
            Logger.musickit.error("playback_failed: \(error.localizedDescription)")
        }
    }

    /// 積んだ曲の次があるか / 前があるか (曲送りのボタンを出すか)。
    var canSkipToNext: Bool {
        guard isFullPlayback, let queueIndex else { return false }
        return playQueueNextIndex(index: UInt32(queueIndex), len: UInt32(queueSongIds.count)) != nil
    }
    var hasQueue: Bool { isFullPlayback && queueSongIds.count > 1 }

    /// 次に流れる曲と、「次はこれ」で足した曲ならその理由。
    var upNext: (songId: String, label: String?)? {
        guard isFullPlayback, let queueIndex, queueIndex + 1 < queueSongIds.count else { return nil }
        let id = queueSongIds[queueIndex + 1]
        return (id, recommendedLabels[id])
    }

    /// 今の曲が積んだ最後の曲なら、「次はこれ」を 1 曲足す (選び方はコア)。
    /// 足すのは最後の曲に来たときだけなので、積んでいくのは常に 1 曲先まで。
    private func appendNextIfNeeded() {
        // Spotify では足さない (理由は `playSpotify`)。
        guard autoplayNext, isFullPlayback, fullSource == .appleMusic, !isAppendingNext, let current = nowPlayingSongId,
              let queueIndex, queueIndex == queueSongIds.count - 1 else { return }
        isAppendingNext = true
        let exclude = Array((playedSongIds + queueSongIds).suffix(300))
        Task { @MainActor in
            defer { isAppendingNext = false }
            let picks = (try? await AppContainer.shared.nextSongRecommending
                .nextSongs(after: current, exclude: exclude, limit: 5)) ?? []
            for pick in picks {
                guard let appleMusicId = pick.song.appleMusicId, !appleMusicId.isEmpty else { continue }
                let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: MusicItemID(appleMusicId))
                guard let song = try? await request.response().items.first else { continue }
                // 待っている間に止めた・別の曲を鳴らし直したなら足さない。
                guard isFullPlayback, nowPlayingSongId == current, queueSongIds.last == current else { return }
                do {
                    try await ApplicationMusicPlayer.shared.queue.insert(song, position: .tail)
                } catch {
                    Logger.musickit.error("autoplay_insert_failed: \(error.localizedDescription)")
                    return
                }
                queueSongIds.append(pick.song.id)
                songIdByMusicKitId[song.id] = pick.song.id
                recommendedLabels[pick.song.id] = pick.label
                return
            }
        }
    }

    /// 次の曲へ。
    func skipToNext() {
        guard canSkipToNext else { return }
        if fullSource == .spotify { spotifyRemote.next(); return }
        Task { @MainActor in try? await ApplicationMusicPlayer.shared.skipToNextEntry() }
    }

    /// 前の曲へ。少し進んでいれば今の曲の頭へ戻す (どちらにするかはコア)。
    func skipToPrevious() {
        guard isFullPlayback, let queueIndex else { return }
        let target = playQueuePreviousIndex(index: UInt32(queueIndex), positionMs: Int64(fullPlaybackPositionMs ?? 0))
        if fullSource == .spotify {
            if Int(target) == queueIndex { spotifyRemote.seek(ms: 0) } else { spotifyRemote.previous() }
        } else if Int(target) == queueIndex {
            musicPlayer.playbackTime = 0
        } else {
            Task { @MainActor in try? await ApplicationMusicPlayer.shared.skipToPreviousEntry() }
        }
    }

    /// OS のプレイヤーの状態をこちらへ写す (曲が替わった・ロック画面やイヤホンで止めた)。
    /// 一度だけ繋ぐ。`objectWillChange` は変わる直前に来るので、次の周回で読む。
    private func observePlayer() {
        guard playerObservers.isEmpty else { return }
        let player = ApplicationMusicPlayer.shared
        player.queue.objectWillChange
            .merge(with: player.state.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.syncFromPlayer() }
            }
            .store(in: &playerObservers)
    }

    private func syncFromPlayer() {
        guard isFullPlayback, fullSource == .appleMusic else { return }
        let player = ApplicationMusicPlayer.shared
        if case .song(let song)? = player.queue.currentEntry?.item,
           let songId = songIdByMusicKitId[song.id], songId != nowPlayingSongId {
            nowPlayingSongId = songId
            queueIndex = queueSongIds.firstIndex(of: songId)
            playedSongIds.append(songId)
            appendNextIfNeeded()
        }
        let playing = player.state.playbackStatus == .playing
        if playing != isPlaying { isPlaying = playing }
    }

    /// フル再生の再生位置 (ミリ秒)。フル再生していなければ nil。
    ///
    /// 歌詞の追従・タイミング記録が周期で読む。観測対象ではない (OS のプレイヤーの値をその場で引く)。
    /// 30 秒試聴は曲のどこを切り出したか分からないので返さない。
    var fullPlaybackPositionMs: Int? {
        guard isFullPlayback, nowPlayingSongId != nil else { return nil }
        if fullSource == .spotify { return spotifyRemote.positionMs }
        return Int((musicPlayer.playbackTime * 1000).rounded())
    }

    /// フル再生している曲の長さ (ミリ秒)。分からなければ nil。
    var fullPlaybackDurationMs: Int? {
        if isFullPlayback, fullSource == .spotify { return spotifyRemote.durationMs }
        guard isFullPlayback, case .song(let song)? = musicPlayer.queue.currentEntry?.item,
              let duration = song.duration else { return nil }
        return Int((duration * 1000).rounded())
    }

    /// フル再生の位置を動かす (タイミング記録の巻き戻し)。フル再生中でなければ何もしない。
    func seekFull(toMs ms: Int) {
        guard isFullPlayback else { return }
        if fullSource == .spotify { spotifyRemote.seek(ms: ms); return }
        musicPlayer.playbackTime = TimeInterval(max(0, ms)) / 1000
    }

    /// 一時停止。曲は手放さず、音だけ止める。
    ///
    /// `stop()` と分けているのは、**再生中バーを残したまま止めたい**から。
    /// stop は queue ごと解放して `nowPlayingSongId` を nil にするので、
    /// バーの一時停止ボタンから呼ぶと曲そのものを見失う。
    func pause() {
        if isFullPlayback, fullSource == .spotify {
            spotifyRemote.pause()
        } else if isFullPlayback {
            musicPlayer.pause()
        } else {
            player?.pause()
        }
        isPlaying = false
    }

    /// 一時停止からの再開。
    ///
    /// 何も鳴らしていないときに呼んでも何も起きない (再生する曲を知らないため)。
    /// 曲を選び直す経路は `togglePreview` / `playFull` 側。
    func resume() {
        guard nowPlayingSongId != nil else { return }
        if isFullPlayback, fullSource == .spotify {
            spotifyRemote.resume()
        } else if isFullPlayback {
            // self の musicPlayer を Task に渡すと非 Sendable の送信になる。
            // playFull と同じく Task の中で shared を取り直す。
            Task { @MainActor in try? await ApplicationMusicPlayer.shared.play() }
        } else {
            guard player != nil else { return }
            player?.play()
        }
        isPlaying = true
    }

    /// 停止
    func stop() { stop(pausingSpotify: true) }

    /// - Parameter pausingSpotify: Spotify の音も止めるか。続けて別の曲を鳴らすとき・利用者が Spotify アプリで
    ///   別の曲を選んだときは止めない (止める頼みが後から届いて、鳴らし直した曲を止めてしまう)。
    private func stop(pausingSpotify: Bool) {
        // observer を先に解除してから player を解放
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
        player?.pause()
        player = nil
        // MusicKit の ApplicationMusicPlayer.shared は MPMusicPlayerController.application
        // MusicPlayer と OS 上で同一キューを共有する。 ここで pause だけで queue を残すと、
        // 次に IntroDon (MPMusicPlayer 経路) が setQueue を打っても残骸 queue が干渉して
        // .stopped 固着する事例があった。 必ず stop で queue を解放する。
        // ApplicationMusicPlayer の stop は OS とのやり取りで重いので、フル再生を使ったときだけ。
        if fullSource == .spotify {
            // 止めるのは Spotify アプリの音。聞きに行くのもやめる。
            if isFullPlayback, pausingSpotify { spotifyRemote.pause() }
            spotifyRemote.detach()
            fullSource = .appleMusic
            songIdBySpotifyTrackId = [:]
        } else if usedApplicationPlayer || isFullPlayback {
            musicPlayer.stop()
            usedApplicationPlayer = false
        }
        isPlaying = false
        isFullPlayback = false
        nowPlayingSongId = nil
        queueSongIds = []
        queueIndex = nil
        songIdByMusicKitId = [:]
        recommendedLabels = [:]
        playedSongIds = []
    }

    // MARK: - Search

    private func fetchById(appleMusicId: String, cacheKey: String) async -> MusicKitSongInfo? {
        do {
            let id = MusicItemID(rawValue: appleMusicId)
            let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: id)
            let response = try await request.response()
            guard let song = response.items.first else {
                cache.setObject(Boxed(nil), forKey: cacheKey as NSString)
                return nil
            }
            let info = MusicKitSongInfo(
                artworkURL: song.artwork?.url(width: 300, height: 300),
                previewURL: song.previewAssets?.first?.url,
                appleMusicURL: song.url,
                musicKitId: song.id
            )
            cache.setObject(Boxed(info), forKey: cacheKey as NSString)
            return info
        } catch {
            cache.setObject(Boxed(nil), forKey: cacheKey as NSString)
            return nil
        }
    }

}

/// 曲 1 つぶんの「鳴っているか」の印 (`MusicKitService.playFlag(songId:)`)。
@Observable @MainActor
final class SongPlayFlag {
    fileprivate(set) var isPlaying: Bool
    init(isPlaying: Bool) { self.isPlaying = isPlaying }
}
