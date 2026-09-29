import Nuke
import NukeUI
import SwiftUI

struct ArtworkImageView: View {
    let url: URL?
    var size: CGFloat = 50
    var previewURL: URL? = nil
    /// 画像が無いときのフォールバックに出す曲名。**表示専用**。
    var songTitle: String? = nil
    /// 再生中の強調と試聴の切り替えに使う `songs.id`。
    /// 同名で別録音の曲が実在するので、ここを曲名で持つと取り違える。
    var songId: String? = nil
    /// フォールバック (画像なし) 時に使うシード色。曲/ブランドのイメージカラー hex。
    var seed: String? = nil

    @Environment(\.colorScheme) private var scheme

    private var isCurrentlyPlaying: Bool {
        guard let songId else { return false }
        return MusicKitService.shared.isPlaying(songId: songId)
    }

    var body: some View {
        let scale = UIScreen.main.scale
        let px = Int(size * scale)
        ZStack {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholderIcon
                }
            }
            .processors([ImageProcessors.Resize(size: CGSize(width: px, height: px), unit: .pixels)])
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.15))

            // プレビュー再生オーバーレイ
            if previewURL != nil {
                ZStack {
                    if isCurrentlyPlaying {
                        Color.black.opacity(0.4)
                            .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
                    }
                    Image(systemName: isCurrentlyPlaying ? "stop.fill" : "play.fill")
                        .font(.imasScaled( size * 0.25))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
                .frame(width: size, height: size)
            }
        }
        .onTapGesture {
            if let previewURL, let songId {
                MusicKitService.shared.togglePreview(url: previewURL, songId: songId)
            }
        }
    }

    /// 画像が無いときのフォールバック = アクセント面 + 中央に曲名 (デザイン variant C)。
    /// 灰色 + 音符の安っぽいプレースホルダを廃し、テーマ色で「第一級の表現」にする。
    private var placeholderIcon: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        return ZStack {
            t.accent
            if let songTitle, !songTitle.isEmpty {
                Text(songTitle)
                    .font(.imasScaled( max(9, size * 0.13), weight: .bold))
                    .foregroundStyle(t.onAccent)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(size * 0.12)
            } else {
                Image(systemName: "music.note")
                    .font(.imasScaled( size * 0.4))
                    .foregroundStyle(t.onAccent.opacity(0.85))
            }
        }
    }
}
