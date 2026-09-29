import AVFoundation
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
    private(set) var isPlaying = false
    /// 鳴っている曲の `songs.id`。
    ///
    /// **曲名で持ってはいけない。** 「私はアイドル♡ (M@STER VERSION)」のように
    /// 同名で歌唱者の違う録音が実在するので、曲名で同一性を見ると別バージョンの
    /// ジャケと名義が出る。再生中バーの引き当てもここを使う。
    private(set) var nowPlayingSongId: String?
    private(set) var isFullPlayback = false

    /// この曲が今このアプリで鳴っているか。
    ///
    /// 「`isPlaying` かつ id 一致」という同じ式が 5 画面に写経されていて、
    /// 曲名 → id の付け替え時に 5 箇所を手で直す羽目になった。突き合わせ方は
    /// ここ 1 箇所に持つ。
    func isPlaying(songId: String) -> Bool {
        isPlaying && nowPlayingSongId == songId
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
    private init() {}

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

            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                Logger.musickit.error("avaudiosession_setup_failed: \(error.localizedDescription)")
            }

            player?.play()
            isPlaying = true
            isFullPlayback = false
            nowPlayingSongId = songId
        }
    }

    /// フル再生（Apple Musicサブスクユーザーのみ）
    nonisolated func playFull(songInfo: MusicKitSongInfo, songId: String) async {
        guard let musicKitId = songInfo.musicKitId else { return }
        await stop()

        do {
            let request = MusicCatalogResourceRequest<MusicKit.Song>(
                matching: \.id, equalTo: musicKitId
            )
            let response = try await request.response()
            guard let song = response.items.first else { return }

            let player = ApplicationMusicPlayer.shared
            player.queue = [song]
            try await player.play()
            await MainActor.run {
                self.isPlaying = true
                self.isFullPlayback = true
                self.nowPlayingSongId = songId
            }
        } catch {
            Logger.musickit.error("playback_failed: \(error.localizedDescription)")
        }
    }

    /// 一時停止。曲は手放さず、音だけ止める。
    ///
    /// `stop()` と分けているのは、**再生中バーを残したまま止めたい**から。
    /// stop は queue ごと解放して `nowPlayingSongId` を nil にするので、
    /// バーの一時停止ボタンから呼ぶと曲そのものを見失う。
    func pause() {
        if isFullPlayback {
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
        if isFullPlayback {
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
    func stop() {
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
        musicPlayer.stop()
        isPlaying = false
        isFullPlayback = false
        nowPlayingSongId = nil
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
