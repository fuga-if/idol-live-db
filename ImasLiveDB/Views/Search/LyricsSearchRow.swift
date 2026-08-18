import SwiftUI

/// 歌詞検索の結果 1 行。ジャケ写 + 曲名 + 一致箇所まわりのスニペット。
///
/// ⚠️ ここにテキスト選択 (`.textSelection(.enabled)` / `.imasCopyable`) を足さないこと。
/// 歌詞タブ本体 (`SongLyricsTab`) と同じ理由で、コピー導線は一括取り出しの入口になる。
/// `SongTitleRow` を再利用しないのもこれが理由 (あちらは `imasCopyable` を持っている)。
struct LyricsSearchRow: View {
    @Environment(\.colorScheme) private var scheme

    let song: Song
    let hit: LyricsSearchHit

    /// 一致箇所の敷き色。行ごとに担当色を変えると一覧が騒がしくなって
    /// 「どこが一致したか」が逆に読み取りにくいので、全行で同じ色にする。
    private var accent: Color { ImasTheme.derive(seed: nil, scheme: scheme).accent }

    var body: some View {
        HStack(alignment: .top, spacing: DS.sp4) {
            artwork
            VStack(alignment: .leading, spacing: DS.sp1) {
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
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, DS.sp1)
    }

    /// ジャケ写。曲一覧と同じ `ArtworkImageView` を使う (プレビュー再生の配線込み)。
    private var artwork: some View {
        ArtworkImageView(
            url: song.artworkUrl.flatMap { URL(string: $0) },
            size: 44,
            previewURL: song.previewUrl.flatMap { URL(string: $0) },
            songTitle: song.title
        )
    }

    /// 一致部分に色を敷いた本文。
    ///
    /// 文字色は本文のまま (`DS.ink`) にして、敷き色だけで示す。文字色まで
    /// アクセント色にすると、薄い敷き色の上に同系色が乗って逆に読みにくくなる。
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

        text[from ..< to].backgroundColor = accent.opacity(0.28)
        text[from ..< to].foregroundColor = DS.ink
        text[from ..< to].font = .imasFootnote.weight(.semibold)
        return text
    }
}
