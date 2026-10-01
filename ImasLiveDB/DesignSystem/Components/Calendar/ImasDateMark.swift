import SwiftUI

// =============================================================================
// 日付の印 (GAPS.md §7 相当)
//
// ImasDateMark   月グリッドの日セル・週ビューの日付ヘッダに置く、当日/選択日の丸い印。
//                当日 = 墨で塗った丸、選択日 (当日以外) = 墨の線の丸、どちらでもなければ何も出さない。
//                月カレンダー・週ビューの 2 か所で重複していたロジックを 1 つにまとめたもの。
// =============================================================================

struct ImasDateMark: View {
    var isToday: Bool
    var isSelected: Bool
    var size: CGFloat = 26

    var body: some View {
        Group {
            if isToday {
                Circle().fill(DS.sys)
            } else if isSelected {
                Circle().strokeBorder(DS.sys, lineWidth: 1.5)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}
