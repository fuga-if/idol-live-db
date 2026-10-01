import SwiftUI

/// ユニットのアバターを円形表示するコンポーネント。中身は DesignSystem の `ImasUnitAvatar`。
/// (元の型は他の画面からも呼ばれているため、呼び出し口としてこのファイルを残している。)
struct UnitAvatarView: View {
    let unit: Unit
    var size: CGFloat = 36

    var body: some View {
        ImasUnitAvatar(unit: unit, size: size)
    }
}
