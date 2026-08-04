import SwiftUI

/// 楽曲詳細の歌詞タブ。
///
/// 歌詞は曲詳細の束ね取得 (`GET /songs/{id}/detail`) に同梱されて届くので、
/// このタブは `DetailSheetViewModel` を読むだけ。タブを開いても**追加のリクエストは飛ばない**
/// (旧実装は ⋯ メニュー →「歌詞を見る」で push した先で個別に取りに行っていた)。
///
/// ⚠️ JASRAC 許諾の条件により、歌詞は**保存も一括取得もさせない**:
/// - 取得はメモリのみ保持の経路 (`SongDetailReading` / ephemeral セッション)。ディスクに書かない。
/// - 本文にテキスト選択 (`.imasSelectableText()` / `textSelection(.enabled)`) や
///   `imasCopyable` を**付けない**。コピー導線を作ると一括取り出しの入口になる。
/// - 共有 / 画像化 (`ShareCardScaffold`) にも繋がない。
struct SongLyricsTab: View {
    @Environment(\.colorScheme) private var scheme

    let song: Song
    /// 配色シード (ソロ曲は担当色、それ以外はブランド色)。
    let seed: String?
    let vm: DetailSheetViewModel
    /// 通信失敗時の再試行 (束ね取得のやり直し)。
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            InlineLoginPrompt(message: "歌詞の表示にはログインが必要です", seed: seed)
            content
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.serverDataState {
        case .loading:
            ImasInlineLoading()
        case .failed(let message):
            ImasEmptyState(systemImage: "exclamationmark.triangle",
                           title: "歌詞を表示できません",
                           message: message,
                           actionTitle: "再試行",
                           action: reload,
                           seed: seed)
        case .loaded:
            if let lyrics = vm.lyrics, lyrics.hasContent {
                // 未公開 (draft) はサーバが admin にしか返さない。公開済みと
                // 取り違えないよう画面に明示する。JASRAC の許諾が下りるまで
                // 一般ユーザーには配信されない。
                if lyrics.isDraft {
                    Label("下書き（未公開）。この表示は管理者のみ",
                          systemImage: "eye.slash")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .padding(.horizontal, DS.sp2)
                        .padding(.vertical, DS.sp1)
                        .background(DS.ink3.opacity(0.12), in: Capsule())
                        .padding(.horizontal, DS.sp1)
                }
                lyricsCard(lyrics)
                if let source = lyrics.source, !source.isEmpty {
                    Text("出典: \(source)")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink3)
                        .padding(.horizontal, DS.sp1)
                }
            } else {
                emptyState
            }
        }
    }

    /// 歌詞が無い時の空状態。未ログインは「無い」のではなく「見られない」ので文言を分ける
    /// (未ログインでは束ねの歌詞が常に null で返る)。
    @ViewBuilder
    private var emptyState: some View {
        if AuthService.shared.isSignedIn {
            ImasEmptyState(systemImage: "text.quote",
                           title: "歌詞はまだありません",
                           message: "この曲の歌詞はまだ登録されていません。",
                           seed: seed)
        } else {
            ImasEmptyState(systemImage: "text.quote",
                           title: "歌詞の表示にはログインが必要です",
                           message: "ログインすると、登録済みの曲の歌詞を表示できます。",
                           seed: seed)
        }
    }

    // MARK: - 本文

    private func lyricsCard(_ lyrics: Lyrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(song.title)
                .font(.imasTitle3.weight(.bold))
                .foregroundStyle(DS.ink)
                .padding(.bottom, DS.sp2)
            if let artistLine = vm.artistLine(for: song), !artistLine.isEmpty {
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
}
