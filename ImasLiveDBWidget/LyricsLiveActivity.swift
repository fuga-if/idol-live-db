import ActivityKit
import SwiftUI
import WidgetKit

/// ロック画面・Dynamic Island の「いま歌っている行」。中身はアプリ (`LyricsLiveActivityController`) が送る。
///
/// ⚠️ 載せるのはいまの行と次の行だけ。歌詞の本文はここで保存しない (ファイル・App Group に書かない)。
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LyricsLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(ImasWidgetColor.paper)
                .activitySystemActionForegroundColor(ImasWidgetColor.ink)
        } dynamicIsland: { context in
            let accent = ImasWidgetColor.accent(context.attributes.seedHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.songTitle).imasWidgetText(.islandMeta(size: 13)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .top, spacing: ImasWidgetSpace.gap) {
                        LyricsPartStripe(colors: context.state.singerColors)
                        VStack(alignment: .leading, spacing: ImasWidgetSpace.gapTight) {
                            Text(context.state.line ?? "♪").imasWidgetText(.islandTitle(size: 18)).lineLimit(2)
                            if let call = context.state.call {
                                (Text(Image(systemName: "megaphone.fill")) + Text(" " + call))
                                    .imasWidgetText(.call(size: 16, hex: context.attributes.seedHex))
                                    .lineLimit(1)
                            }
                            if let next = context.state.nextLine {
                                Text(next).imasWidgetText(.islandMeta(size: 14)).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: "music.note").foregroundStyle(accent)
            } compactTrailing: {
                LyricsPartStripe(colors: context.state.singerColors.isEmpty ? [context.attributes.seedHex ?? ""]
                                 : context.state.singerColors)
                    .frame(height: 14)
            } minimal: {
                Image(systemName: "music.note").foregroundStyle(accent)
            }
        }
    }
}

/// ロック画面の 1 枚。上に曲名、真ん中にいまの行を大きく、下に次の行を薄く。
private struct LyricsLockScreenView: View {
    let attributes: LyricsActivityAttributes
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: ImasWidgetSpace.gap) {
            HStack(spacing: ImasWidgetSpace.gapTight) {
                Image(systemName: state.isPlaying ? "music.note" : "pause.fill")
                    .foregroundStyle(ImasWidgetColor.accent(attributes.seedHex))
                Text(attributes.songTitle).imasWidgetText(.meta(size: 13)).lineLimit(1)
            }
            HStack(alignment: .top, spacing: ImasWidgetSpace.gapLoose) {
                LyricsPartStripe(colors: state.singerColors)
                VStack(alignment: .leading, spacing: ImasWidgetSpace.gapTight) {
                    Text(state.line ?? "♪").imasWidgetText(.title(size: 20)).lineLimit(2)
                    if !state.singerNames.isEmpty {
                        Text(state.singerNames.joined(separator: "・")).imasWidgetText(.meta(size: 12)).lineLimit(1)
                    }
                    if let call = state.call {
                        (Text(Image(systemName: "megaphone.fill")) + Text(" " + call))
                            .imasWidgetText(.call(size: 17, hex: attributes.seedHex))
                            .lineLimit(1)
                    }
                    if let next = state.nextLine {
                        Text(next).imasWidgetText(.dim(size: 15)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(ImasWidgetSpace.activityInset)
    }
}

/// 歌う人の担当色の縦縞 (アプリ本体の `ImasPartStripe` と同じ描き方)。色が無ければ出さない。
private struct LyricsPartStripe: View {
    let colors: [String]

    var body: some View {
        if !colors.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                    Rectangle().fill(ImasWidgetColor.accent(hex))
                }
            }
            .frame(width: 4)
        }
    }
}
