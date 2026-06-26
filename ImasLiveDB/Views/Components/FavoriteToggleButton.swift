import SwiftUI

/// 一覧の各行から お気に入り (UserMarkKind.favorite) をタップで toggle できる
/// 小さい星ボタン。 行 navigation を吸わないよう `.buttonStyle(.borderless)`。
struct FavoriteToggleButton: View {
    let entity: UserMarkEntity
    let id: String
    var size: CGFloat = 18

    @State private var refresh = false

    private var isFavorite: Bool {
        UserMarkService.shared.bool(.favorite, entity: entity, id: id)
    }

    var body: some View {
        Button {
            AppAnalytics.tap("favorite.toggle")
            try? UserMarkService.shared.toggle(.favorite, entity: entity, id: id)
            refresh.toggle()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.imasScaled( size))
                .foregroundStyle(isFavorite ? .yellow : .secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .id(refresh)
        .accessibilityLabel(isFavorite ? "お気に入り解除" : "お気に入りに追加")
    }
}

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
            try? UserMarkService.shared.toggle(.myPick, entity: .idol, id: id)
            refresh.toggle()
        } label: {
            Image(systemName: isMyPick ? "p.circle.fill" : "p.circle")
                .font(.imasScaled( size))
                .foregroundStyle(isMyPick ? .pink : .secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .id(refresh)
        .accessibilityLabel(isMyPick ? "担当解除" : "担当に追加")
    }
}
