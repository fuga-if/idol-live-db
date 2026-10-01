import SwiftUI

/// 曲のジャケ表示 + 試聴。見た目は DS の `ImasArtwork` (画像が無ければ灰の面 + 音符)。
/// 再生状態の読み出しと切り替えだけここで `MusicKitService` に橋渡しする
/// (DS はアプリのサービスを知らないので、ここが唯一の橋渡し場所)。
struct ArtworkImageView: View {
    let url: URL?
    var size: CGFloat = 50
    var previewURL: URL? = nil
    /// 画像が無いときのフォールバックに出す曲名。**表示専用** (ImasArtwork の読み上げに使う)。
    var songTitle: String? = nil
    /// 再生中の強調と試聴の切り替えに使う `songs.id`。
    /// 同名で別録音の曲が実在するので、ここを曲名で持つと取り違える。
    var songId: String? = nil
    /// フォールバック (画像なし) 時に使うシード色。曲/ブランドのイメージカラー hex。
    var seed: String? = nil

    private var isCurrentlyPlaying: Bool {
        guard let songId else { return false }
        return MusicKitService.shared.isPlaying(songId: songId)
    }

    var body: some View {
        ImasArtwork(
            title: songTitle ?? "",
            seed: seed,
            size: size,
            imageURL: url,
            previewURL: previewURL,
            isPreviewing: isCurrentlyPlaying,
            onPreview: {
                if let previewURL, let songId {
                    MusicKitService.shared.togglePreview(url: previewURL, songId: songId)
                }
            }
        )
    }
}
