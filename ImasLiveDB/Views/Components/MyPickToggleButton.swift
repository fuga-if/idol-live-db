import SwiftUI

/// 一覧の各行から 担当 (UserMarkKind.myPick) をタップで toggle できるハートボタン。
/// 主に Idol 一覧用 (idol entity のみ意味のある mark)。
struct MyPickToggleButton: View {
    let id: String
    var size: CGFloat = 18

    @State private var refresh = false

    private var isMyPick: Bool {
        UserMarkService.shared.bool(.myPick, entity: .idol, id: id)
    }

    var body: some View {
        Button {
            AppAnalytics.tap("my_pick.toggle")
            do {
                try UserMarkService.shared.toggle(.myPick, entity: .idol, id: id)
            } catch {
                LocalWriteFailure.report(error, action: "担当の切り替え")
            }
            refresh.toggle()
        } label: {
            Image(systemName: isMyPick ? "heart.fill" : "heart")
                .font(.imasScaled( size))
                .foregroundStyle(isMyPick ? DS.pick : DS.ink3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .id(refresh)
        .accessibilityLabel(isMyPick ? "担当解除" : "担当に追加")
    }
}
