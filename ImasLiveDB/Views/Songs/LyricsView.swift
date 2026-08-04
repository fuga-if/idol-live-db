import SwiftUI

/// 楽曲詳細から開く歌詞表示。
///
/// ⚠️ JASRAC 許諾の条件により、歌詞は**保存も一括取得もさせない**:
/// - 取得は `LyricsReading` (メモリのみ保持) 経由。ディスクには一切書かない。
/// - 本文にテキスト選択 (`.imasSelectableText()` / `textSelection(.enabled)`) や
///   `imasCopyable` を**付けない**。コピー導線を作ると一括取り出しの入口になる。
/// - 共有 / 画像化 (`ShareCardScaffold`) にも繋がない。
struct LyricsView: View {
    @Environment(\.colorScheme) private var scheme

    let song: Song
    /// 配色シード (呼び出し元の楽曲詳細と揃える)。
    var seed: String?

    /// 読み取りポート。プレビュー/デバッグはフェイクを差し込める。
    var reading: any LyricsReading = AppContainer.shared.lyricsReading

    @State private var lyrics: Lyrics?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp4) {
                InlineLoginPrompt(message: "歌詞の表示にはログインが必要です", seed: seed)
                if isLoading {
                    ImasInlineLoading()
                } else if let loadError {
                    ImasEmptyState(systemImage: "exclamationmark.triangle",
                                   title: "歌詞を表示できません",
                                   message: loadError,
                                   actionTitle: "再試行",
                                   action: { Task { await load() } },
                                   seed: seed)
                } else if let lyrics, lyrics.hasContent {
                    lyricsCard(lyrics)
                    if let source = lyrics.source, !source.isEmpty {
                        Text("出典: \(source)")
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink3)
                            .padding(.horizontal, DS.sp1)
                    }
                } else {
                    ImasEmptyState(systemImage: "text.quote",
                                   title: "歌詞はまだありません",
                                   message: "この曲の歌詞はまだ登録されていません。",
                                   seed: seed)
                }
                Color.clear.frame(height: DS.sp9)
            }
            .padding(.horizontal, DS.sp5)
            .padding(.top, DS.sp4)
        }
        .background(DS.bg)
        .navigationTitle("歌詞")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .trackScreen("song_lyrics")
    }

    // MARK: - 本文

    private func lyricsCard(_ lyrics: Lyrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(song.title)
                .font(.imasTitle3.weight(.bold))
                .foregroundStyle(DS.ink)
                .padding(.bottom, DS.sp2)
            if let artistLine = song.singerLabel, !artistLine.isEmpty {
                Text(artistLine)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .padding(.bottom, DS.sp4)
            }
            ForEach(lyrics.lines) { line in
                row(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.sp5)
        .padding(.vertical, DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    @ViewBuilder
    private func row(_ line: LyricLine) -> some View {
        switch line.kind {
        case .lyric:
            Text(line.text)
                .font(.imasBody)
                .foregroundStyle(DS.ink)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
        case .marker:
            marker(line.text)
        case .blank:
            Color.clear.frame(height: DS.sp5)
        }
    }

    /// 「イントロ」「サビ」等の構成マーカー。歌詞本文と混ざらないよう罫線で挟んだ細いラベルにする。
    private func marker(_ text: String) -> some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        return HStack(spacing: DS.sp3) {
            rule
            Text(text)
                .font(.imasCaption2.weight(.semibold))
                .foregroundStyle(t.chipText)
                .lineLimit(1)
            rule
        }
        .padding(.vertical, DS.sp3)
        .accessibilityLabel("セクション: \(text)")
    }

    private var rule: some View {
        Rectangle().fill(DS.sep).frame(height: 1)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            lyrics = try await reading.lyrics(songId: song.id)
        } catch {
            lyrics = nil
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

#if DEBUG
#Preview("歌詞あり") {
    NavigationStack {
        LyricsView(
            song: Song(id: "preview_song", title: "サンプル楽曲", songType: "solo",
                       singerLabel: "サンプルアイドル"),
            seed: "ff6699",
            reading: FakeLyricsReading()
        )
    }
}

#Preview("歌詞なし") {
    NavigationStack {
        LyricsView(
            song: Song(id: "preview_nolyrics", title: "サンプル楽曲", songType: "solo"),
            seed: "3399ff",
            reading: FakeLyricsReading()
        )
    }
}
#endif
