import SwiftUI

/// アイドル名表示の統一行レイアウト。
/// 色ドット + 名前 + (サブタイトル) + chevron。
/// Button や NavigationLink でラップしてもテキスト色が青に染まらない (foregroundStyle(.primary) を明示)。
struct IdolNameRow: View {
    let idol: Idol
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            ColorDotView(hex: idol.color, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(idol.name)
                    .font(.imasSubhead)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.imasScaled(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.imasCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// 楽曲タイトル表示の統一行レイアウト。
/// ジャケ写 (or プレースホルダー) + タイトル + (ユニット/シンガー) + chevron。
struct SongTitleRow: View {
    let song: Song
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            songArtwork
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.imasBody)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let label = subtitle ?? song.unitName ?? song.singerLabel,
                   !label.isEmpty {
                    Text(label)
                        .font(.imasScaled(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.imasCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var songArtwork: some View {
        let size: CGFloat = 36
        let url = song.artworkUrl.flatMap { URL(string: $0) }
        return ArtworkImageView(url: url, size: size, previewURL: nil, songTitle: song.title)
    }
}

/// イベント名表示の統一行レイアウト。
struct EventNameRow: View {
    let event: Event
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            BrandColorBar(brandId: event.brandId)
            VStack(alignment: .leading, spacing: 2) {
                Text(eventDisplayName(event.name))
                    .font(.imasSubhead)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.imasScaled(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.imasCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
