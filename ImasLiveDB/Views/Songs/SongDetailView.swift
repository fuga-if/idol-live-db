import SwiftUI

/// 楽曲詳細の push エントリ。
/// 実体は `SongSheetContent` (大ジャケ・ヒーロー固定 + ImasSegmented の内部セグメント
/// [情報・歌唱][披露履歴][コミュニティ] + ⋯ メニュー) に集約している。
/// 編集 / 編集履歴 / 歌詞 / Apple Music / コミュニティ投稿 (タグ・コーレス・動画・ペンライト投票)
/// の導線はすべて `SongSheetContent` 側に配線済み。
/// このラッパは子画面への遷移を共通シート (`DetailSheetView`) に流すだけの薄い入口。
struct SongDetailView: View {
    @Environment(AppDatabase.self) private var database
    let song: Song

    @State private var sheetDestination: DetailDestination?

    var body: some View {
        SongSheetContent(song: song, navigate: { sheetDestination = $0 })
            .sheet(item: $sheetDestination) { dest in
                DetailSheetView(destination: dest)
                    .environment(database)
            }
            .trackScreen("song_detail")
    }
}
