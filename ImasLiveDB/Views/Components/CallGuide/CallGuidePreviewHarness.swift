#if DEBUG
import SwiftUI

/// コールガイドの見た目を実機/シミュレータで確認するための DEBUG 専用ハーネス。
///
/// 既存の `SCREENSHOT_MODE` / `FAKE_LYRICS` と同じ「起動時の環境変数で挙動を変える」流儀。
/// 実画面 (`SongLyricsTab` / `CallEditorSheet`) をそのまま出すので、ここで見えるものが
/// そのまま本番の見た目になる (ハーネス専用の描画は一切していない)。
///
///     SIMCTL_CHILD_FAKE_LYRICS=1 SIMCTL_CHILD_SCREENSHOT_MODE=1 \
///     SIMCTL_CHILD_CALL_GUIDE_PREVIEW=view \
///     xcrun simctl launch <udid> com.fugaif.ImasLiveDB
///
/// 歌詞はすべて `FakeLyricsReading` のダミー文言 (著作物は使っていない)。
struct CallGuidePreviewHarness: View {
    enum Mode: String {
        /// 閲覧モードのコールガイド。
        case view
        /// 編集モード (範囲選択・手拍子指定・ズレ一覧)。
        case edit
        /// コール入力シート単体。
        case sheet
        /// 再生への追従 (ダミーの時刻を振り、起動からの経過時間を再生位置とみなす)。
        case sync
        /// タイミング編集。
        case record
        /// 歌詞プレイヤー (sync と同じダミーの時刻)。
        case player
        /// 行の区切りの編集 (くっつける / 切り離す)。
        case structure
    }

    /// 環境変数で指定されたモード。未指定なら nil (通常起動)。
    static var envMode: Mode? {
        ProcessInfo.processInfo.environment["CALL_GUIDE_PREVIEW"].flatMap(Mode.init(rawValue:))
    }

    let mode: Mode

    @State private var vm: DetailSheetViewModel
    /// 追従・記録の確認用の擬似プレイヤー。起動からの経過時間を再生位置とみなす。
    @State private var startedAt = Date()
    @State private var scrollTarget: String?

    init(mode: Mode) {
        self.mode = mode
        _vm = State(initialValue: DetailSheetViewModel(
            songDetailReading: HarnessSongDetailReading(timed: mode != .view && mode != .edit && mode != .sheet)))
    }

    private var fakePlayback: SongLyricsTab.Playback {
        guard mode == .sync || mode == .record || mode == .player else { return .init() }
        let startedAt = startedAt
        return .init(isFullLoaded: true, isPlaying: true,
                     positionMs: { Int(Date().timeIntervalSince(startedAt) * 1000) },
                     startFull: { true },
                     durationMs: { 60_000 },
                     seek: { _ in },
                     scrollTo: { scrollTarget = $0 })
    }

    var body: some View {
        Group {
            switch mode {
            case .view, .edit, .sync, .record, .player, .structure:
                ScrollViewReader { proxy in
                    ScrollView {
                        SongLyricsTab(song: Self.sampleSong, seed: nil, vm: vm, playback: fakePlayback,
                                      reload: {}, debugStartsEditing: mode == .edit,
                                      debugStartsRecording: mode == .record,
                                      debugStartsPlayer: mode == .player,
                                      debugStartsStructure: mode == .structure)
                            .padding(.bottom, DS.sp8)
                    }
                    .onChange(of: scrollTarget) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .background(DS.bg)
            case .sheet:
                CallEditorSheet(
                    request: .init(lineId: "ll_5", start: 0, end: 3,
                                   anchorText: "ダミー",
                                   lineText: "ダミー歌詞のサンプル行です 2", existing: nil),
                    seed: nil,
                    onSubmit: { _, _, _ in },
                    onDelete: nil
                )
            }
        }
        .task { await vm.loadServerData(song: Self.sampleSong) }
    }

    /// 表示確認用のダミー楽曲 (DB を引かずに済ませる)。
    static let sampleSong = Song(
        id: "preview_call_guide", title: "サンプル楽曲（表示確認用）", titleKana: nil,
        brandId: nil, songType: "unit", releaseDate: nil, durationSec: nil,
        composer: nil, lyricist: nil, arranger: nil, cdSeries: nil, cdTitle: nil,
        artworkUrl: nil, previewUrl: nil, appleMusicId: nil, appleMusicAlbumId: nil,
        isrc: nil, lyricsUrl: nil, parentSongId: nil, singerLabel: "ダミーユニット",
        unitName: nil, unitId: nil, seriesGroup: nil
    )
}

/// ネットワークを一切叩かず、ダミー歌詞だけを返す読み取り (ハーネス専用)。
private struct HarnessSongDetailReading: SongDetailReading {
    /// 行に 2.5 秒おきのダミー時刻を振る (追従の確認用)。
    var timed = false

    func songDetail(songId: String) async throws -> SongDetailBundle {
        var lyrics = try await FakeLyricsReading().lyrics(songId: songId)
        if timed, let base = lyrics {
            let lines = base.lines.enumerated().map { i, l in
                // 被せの見え方の確認用: 行の中の括弧 (追いかけ) と、行まるごと括弧の被せ行。
                let text = l.kind != .lyric ? l.text
                    : i % 6 == 3 ? "（ダミーの被せ行）"
                    : i % 4 == 1 ? l.text + "（追いかけ）" : l.text
                return LyricLine(id: l.id, ord: l.ord, kind: l.kind, text: text, section: l.section,
                          startMs: l.kind == .blank ? nil : i * 2500, clap: l.clap,
                          calls: l.calls.enumerated().map { k, c in
                              var call = c
                              call.startMs = i * 2500 + 1200 + k * 400
                              return call
                          },
                          likeCount: [0, 1, 2, 5, 9, 4, 1, 0, 3, 6][i % 10])
            }
            lyrics = Lyrics(songId: base.songId, source: base.source, updatedAt: base.updatedAt,
                            lines: lines, status: base.status)
        }
        return SongDetailBundle(songId: songId, tags: nil, similar: nil, penlight: nil, lyrics: lyrics)
    }
}
#endif
