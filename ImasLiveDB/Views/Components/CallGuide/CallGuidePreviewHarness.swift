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
    }

    /// 環境変数で指定されたモード。未指定なら nil (通常起動)。
    static var envMode: Mode? {
        ProcessInfo.processInfo.environment["CALL_GUIDE_PREVIEW"].flatMap(Mode.init(rawValue:))
    }

    let mode: Mode

    @State private var vm = DetailSheetViewModel(songDetailReading: HarnessSongDetailReading())

    var body: some View {
        Group {
            switch mode {
            case .view, .edit:
                ScrollView {
                    SongLyricsTab(song: Self.sampleSong, seed: nil, vm: vm, reload: {},
                                  debugStartsEditing: mode == .edit)
                        .padding(.bottom, DS.sp8)
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
    func songDetail(songId: String) async throws -> SongDetailBundle {
        SongDetailBundle(songId: songId, tags: nil, similar: nil, penlight: nil,
                         lyrics: try await FakeLyricsReading().lyrics(songId: songId))
    }
}
#endif
