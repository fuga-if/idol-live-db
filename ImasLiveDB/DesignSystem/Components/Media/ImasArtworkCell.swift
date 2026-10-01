import SwiftUI

// =============================================================================
// ジャケの格子セル (docs/DESIGN_SYSTEM.md §6.6)
//
// 用途      アルバム・シリーズなど「ジャケ + 題」を格子で並べる一覧 (3 列)。
// 使わない  アイドル・ユニットの格子 → `ImasIdolCell`
// 構成      ジャケ (正方形、列幅いっぱい) + 題 (2 行まで) + 副題 (任意、1 行)
// 状態      通常 / 押下 (押せるようにするのは呼び出し側。`.buttonStyle(.imasPress)` を付ける)
//
// ジャケは `ImasArtwork` をそのまま使う (画像が無ければ灰の面 + 音符。色地に題字を置かない)。
// =============================================================================

/// ジャケ + 題の格子セル (アルバム・シリーズの一覧)。
struct ImasArtworkCell: View {
    let title: String
    var subtitle: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    var imageURL: URL? = nil
    /// 画像が無いときの記号 (実体ごとに違う。例: シリーズは円盤の束)。
    var fallbackSystemImage: String = "music.note"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight + 2) {
            GeometryReader { geo in
                ImasArtwork(title: title, seed: seed, brand: brand, size: geo.size.width, imageURL: imageURL,
                           fallbackSystemImage: fallbackSystemImage)
            }
            .aspectRatio(1, contentMode: .fit)
            // 下の題で同じ曲名/アルバム名を読むので、ジャケ自体は読み上げから隠す (二重読み防止)。
            .accessibilityHidden(true)
            Text(title)
                .imasText(.rowLabel)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle).imasText(.meta)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
