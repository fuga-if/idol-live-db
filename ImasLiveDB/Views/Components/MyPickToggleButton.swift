import SwiftUI

/// 一覧の各行から 担当 (UserMarkKind.myPick) をタップで toggle できるハートボタン。
/// 主に Idol 一覧用 (idol entity のみ意味のある mark)。見た目は DesignSystem の `ImasMarkButton`
/// (ON はアイドル本人 (無ければ所属ブランド) の色で点く)。
struct MyPickToggleButton: View {
    let id: String
    var seed: String? = nil
    var brand: String? = nil

    @State private var refresh = false

    private var isMyPick: Bool {
        UserMarkService.shared.bool(.myPick, entity: .idol, id: id)
    }

    var body: some View {
        ImasMarkButton(kind: .pick, isOn: isMyPick, seed: seed, brand: brand) {
            AppAnalytics.tap("my_pick.toggle")
            do {
                try UserMarkService.shared.toggle(.myPick, entity: .idol, id: id)
            } catch {
                LocalWriteFailure.report(error, action: "担当の切り替え")
            }
            refresh.toggle()
        }
        .id(refresh)
    }
}
