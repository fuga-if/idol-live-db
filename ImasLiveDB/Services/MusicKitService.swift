import AVFoundation
import Foundation
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
    private(set) var nowPlayingTitle: String?
    private(set) var isFullPlayback = false

    /// LRU キャッシュ（最大500件）
    private let cache: NSCache<NSString, Boxed<MusicKitSongInfo?>> = {
        let c = NSCache<NSString, Boxed<MusicKitSongInfo?>>()
        c.countLimit = 500
        return c
    }()

    private var player: AVPlayer?
    private var endObserverToken: NSObjectProtocol?
    private let musicPlayer = ApplicationMusicPlayer.shared

    static let shared = MusicKitService()
    private init() {}

    func requestAuthorization() async {
        authorizationStatus = await MusicAuthorization.request()
        await checkSubscription()
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
    /// タイトル検索フォールバックは別曲ヒットの誤検出が多いため撤廃。
    /// 未登録曲は MusicKit 連携 (アートワーク・プレビュー・Apple Music リンク) を一切表示しない。
    func fetchSongInfo(title: String, appleMusicId: String? = nil) async -> MusicKitSongInfo? {
        guard let appleMusicId, !appleMusicId.isEmpty else { return nil }
        let cacheKey = appleMusicId
        if let boxed = cache.object(forKey: cacheKey as NSString) { return boxed.value }
        return await fetchById(appleMusicId: appleMusicId, cacheKey: cacheKey)
    }

    // MARK: - Playback

    /// プレビュー再生（30秒、誰でも可）
    func togglePreview(url: URL, title: String) {
        if isPlaying && nowPlayingTitle == title {
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
            nowPlayingTitle = title
        }
    }

    /// フル再生（Apple Musicサブスクユーザーのみ）
    nonisolated func playFull(songInfo: MusicKitSongInfo, title: String) async {
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
                self.nowPlayingTitle = title
            }
        } catch {
            Logger.musickit.error("playback_failed: \(error.localizedDescription)")
        }
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
        if isFullPlayback {
            musicPlayer.pause()
        }
        isPlaying = false
        isFullPlayback = false
        nowPlayingTitle = nil
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
