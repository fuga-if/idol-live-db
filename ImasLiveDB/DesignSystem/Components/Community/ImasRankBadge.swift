import SwiftUI

// =============================================================================
// 順位の札 (docs/DESIGN_SYSTEM.md §10.1)
//
// ImasRankBadge  数字だけの小さい順位の札。タグ・お題のランキングで、色のドットや名前と
//                同じ行に差し込める (`ImasRankNumber` は行の先頭いっぱいに置く大きな数字で、
//                こちらは文中に添える小さい版)。色で順位を飾らない (メダル色の塗り分けはしない。
//                1〜3 位は墨の太字、それ以降は灰の細字)。
//                以前は画面ごとに同じ見た目の `TagRankBadge` を手書きしていた (7 ファイル)。
// =============================================================================

struct ImasRankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.imasMono(11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(rank <= 3 ? DS.ink : DS.ink2)
            .padding(.horizontal, 6)
            .frame(minWidth: 26, minHeight: DS.Size.badge)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
            .accessibilityLabel("\(rank)位")
    }
}
