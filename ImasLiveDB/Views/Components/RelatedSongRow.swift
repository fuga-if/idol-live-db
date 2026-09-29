import SwiftUI

/// 関連 / おすすめ楽曲の 1 行。ジャケ + 曲名 + 歌唱表記 (+ 補足バッジ)。
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
        HStack(spacing: DS.sp3) {
            ImasArtwork(title: song.title, seed: seed, size: 44,
                        imageURL: URL.safeHTTP(string: song.artworkUrl))
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(song.title).font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink).lineLimit(1)
                if let sub = song.singerLabel ?? song.unitName, !sub.isEmpty {
                    Text(sub).font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let badge {
                Text(badge).font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
            }
            ImasRowChevron()
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
