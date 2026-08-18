import SwiftUI

/// 歌詞検索の結果 1 行。曲名 + 一致箇所まわりのスニペット。
///
/// ⚠️ ここにテキスト選択 (`.textSelection(.enabled)` / `.imasCopyable`) を足さないこと。
/// 歌詞タブ本体 (`SongLyricsTab`) と同じ理由で、コピー導線は一括取り出しの入口になる。
struct LyricsSearchRow: View {
    @Environment(\.colorScheme) private var scheme

    let song: Song
    let hit: LyricsSearchHit
    /// 配色シード (曲のブランド色など)。強調色に使う。
    let seed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text(song.title)
                .font(.imasBody)
                .foregroundStyle(DS.ink)
                .lineLimit(1)
            if let label = song.unitName ?? song.singerLabel, !label.isEmpty {
                Text(label)
                    .font(.imasCaption2)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(1)
            }
            // ⚠️ .textSelection / .imasCopyable を付けないこと。
            Text(snippet)
                .font(.imasFootnote)
                .foregroundStyle(DS.ink2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DS.sp1)
    }

    /// 一致部分だけ色と太さを変えた本文。
    ///
    /// オフセットは Unicode スカラー単位 (サーバと合意済みの規約)。`AttributedString` の
    /// インデックスは文字単位なので、スカラー位置から `String.Index` を作って変換する。
    /// UTF-16 で数え直すと絵文字を含む行でズレる。
    private var snippet: AttributedString {
        var text = AttributedString(hit.snippet)
        let range = hit.matchRange
        guard range.lowerBound < range.upperBound else { return text }

        let scalars = hit.snippet.unicodeScalars
        guard let lower = scalars.index(scalars.startIndex, offsetBy: range.lowerBound,
                                        limitedBy: scalars.endIndex),
              let upper = scalars.index(scalars.startIndex, offsetBy: range.upperBound,
                                        limitedBy: scalars.endIndex),
              let from = AttributedString.Index(lower, within: text),
              let to = AttributedString.Index(upper, within: text)
        else { return text }

        text[from ..< to].foregroundColor = ImasTheme.derive(seed: seed, scheme: scheme).accent
        text[from ..< to].font = .imasFootnote.weight(.bold)
        return text
    }
}
