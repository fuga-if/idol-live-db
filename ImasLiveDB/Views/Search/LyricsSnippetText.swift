import SwiftUI

/// 歌詞の一致箇所まわりを 1 本ぶん表示する。
///
/// 横断検索の結果行 (`LyricsSearchRow`) と楽曲一覧の行 (`SongRowView`) の双方から使う。
/// 一覧側で歌詞検索しても「どこで引っかかったか」が出ず、曲名だけが並んで
/// 理由の分からない絞り込みに見えていたのが、共通化した理由。
///
/// ⚠️ ここにテキスト選択 (`.textSelection(.enabled)` / `.imasCopyable`) を足さないこと。
/// 歌詞タブ本体 (`SongLyricsTab`) と同じ理由で、コピー導線は一括取り出しの入口になる。
struct LyricsSnippetText: View {
    @Environment(\.colorScheme) private var scheme

    let snippet: LyricsSnippet
    var lineLimit: Int = 2

    /// 一致箇所の敷き色。行ごとに担当色を変えると一覧が騒がしくなって
    /// 「どこが一致したか」が逆に読み取りにくいので、全行で同じ色にする。
    private var accent: Color { ImasTheme.derive(seed: nil, scheme: scheme).accent }

    var body: some View {
        Text(attributed)
            .font(.imasFootnote)
            .foregroundStyle(DS.ink2)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 一致部分に色を敷いた本文。
    ///
    /// 文字色は本文のまま (`DS.ink`) にして、敷き色だけで示す。文字色まで
    /// アクセント色にすると、薄い敷き色の上に同系色が乗って逆に読みにくくなる。
    ///
    /// オフセットは Unicode スカラー単位 (サーバと合意済みの規約)。`AttributedString` の
    /// インデックスは文字単位なので、スカラー位置から `String.Index` を作って変換する。
    /// UTF-16 で数え直すと絵文字を含む行でズレる。
    private var attributed: AttributedString {
        var text = AttributedString(snippet.snippet)
        let range = snippet.matchRange
        guard range.lowerBound < range.upperBound else { return text }

        let scalars = snippet.snippet.unicodeScalars
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
