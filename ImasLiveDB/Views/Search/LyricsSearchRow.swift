import SwiftUI

/// 歌詞検索の結果 1 行。ジャケ写 + 曲名 + 一致箇所まわりのスニペット。
///
/// ⚠️ ここにテキスト選択 (`.textSelection(.enabled)` / `.imasCopyable`) を足さないこと。
/// 歌詞タブ本体 (`SongLyricsTab`) と同じ理由で、コピー導線は一括取り出しの入口になる。
/// `SongTitleRow` を再利用しないのもこれが理由 (あちらは `imasCopyable` を持っている)。
struct LyricsSearchRow: View {
    let song: Song
    let hit: LyricsSearchHit

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
                // 語ごとに1本ずつ。AND だと複数出て「なぜ引っかかったか」が分かる。
                ForEach(hit.snippets) { s in
                    LyricsSnippetText(snippet: s)
                        .padding(.top, 1)
                }
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

}
