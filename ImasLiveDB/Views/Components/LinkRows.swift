import SwiftUI

/// アイドル名表示の統一行レイアウト。
/// アバター写真 + 名前 + (サブタイトル) + chevron。
/// Button や NavigationLink でラップしてもテキスト色が青に染まらない (foregroundStyle(DS.ink) を明示)。
struct IdolNameRow: View {
    let idol: Idol
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            IdolAvatarView(idol: idol, size: 36)
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(idol.name)
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.imasCaption2)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                ImasRowChevron()
            }
        }
        .contentShape(Rectangle())
        .imasCopyable([("アイドル名をコピー", idol.name), ("よみをコピー", idol.nameKana)])
    }
}

/// 楽曲タイトル表示の統一行レイアウト。
/// ジャケ写 (or プレースホルダー) + タイトル + (ユニット/シンガー) + chevron。
struct SongTitleRow: View {
    let song: Song
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: DS.sp4) {
            songArtwork
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(song.title)
                    .font(.imasBody)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                if let label = subtitle ?? song.unitName ?? song.singerLabel,
                   !label.isEmpty {
                    Text(label)
                        .font(.imasCaption2)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                ImasRowChevron()
            }
        }
        .contentShape(Rectangle())
        .imasCopyable([("曲名をコピー", song.title), ("よみをコピー", song.titleKana), ("歌唱者をコピー", song.singerLabel)])
    }

    private var songArtwork: some View {
        let size: CGFloat = 36
        let url = song.artworkUrl.flatMap { URL(string: $0) }
        return ArtworkImageView(url: url, size: size, previewURL: previewURL, songTitle: song.title)
    }

    /// タップでプレビュー再生できるよう song.previewUrl を渡す (SongRowView と同じ配線)。
    private var previewURL: URL? {
        guard let dbUrl = song.previewUrl else { return nil }
        return URL(string: dbUrl)
    }
}

/// ユニット名表示の統一行レイアウト。
/// アバター (person.3.fill モノグラム) + 名前 + (サブタイトル) + chevron。
struct UnitNameRow: View {
    let unit: Unit
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            UnitAvatarView(unit: unit, size: 36)
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(unit.displayName)
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.imasCaption2)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                ImasRowChevron()
            }
        }
        .contentShape(Rectangle())
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
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(eventDisplayName(event.name))
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.imasCaption2)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                ImasRowChevron()
            }
        }
        .contentShape(Rectangle())
        .imasCopyable([("ライブ名をコピー", event.name)])
    }
}
