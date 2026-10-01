import SwiftUI

/// 関連 / おすすめ楽曲の 1 行。見た目は DS の `ImasSongRow`。
///
/// 楽曲詳細の「関連楽曲」(ローカル算出) と「この曲が好きな人にはこれも」(タグ類似・サーバ算出)
/// が同じ見た目を使う。タップ時の遷移は呼び出し側が決める (ここは行の描画だけ)。
struct RelatedSongRow: View {
    let song: Song
    /// 配色シード。呼び出し元の画面テーマに合わせる。
    let seed: String?
    /// 右端の補足 (例: "タグ3個一致")。不要なら nil。
    var badge: String? = nil

    var body: some View {
        ImasSongRow(
            title: song.title,
            subtitle: song.singerLabel ?? song.unitName,
            artworkURL: URL.safeHTTP(string: song.artworkUrl),
            brandHex: seed,
            trailing: badge.map { .custom(AnyView(trailingBadge($0))) } ?? .chevron,
            density: .compact
        ) {
            EmptyView()
        }
    }

    private func trailingBadge(_ text: String) -> some View {
        HStack(spacing: DS.Space.gapTight) {
            Text(text).imasText(.meta)
            ImasRowChevron()
        }
    }
}
