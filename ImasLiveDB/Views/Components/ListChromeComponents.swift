import SwiftUI

/// ライブ / アイドル / 楽曲 の各タブで共通して使う「タブ内検索フィールド」。
///
/// iOS 標準の `.searchable` は検索バーを常時(またはスクロールで)表示してしまうため使わず、
/// ツールバーの虫眼鏡を押したときだけ出る on-demand 方式で 3 タブを統一する。
/// `isSearching` が true の間だけツリーに入る前提で、表示時に自動フォーカスする。
struct InTabSearchField: View {
    let prompt: String
    @Binding var text: String
    @Binding var isSearching: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            Button("キャンセル") {
                text = ""
                isSearching = false
            }
            .font(.imasSubhead)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { focused = true }
    }
}

/// 「その他メニュー」に入れる副次アクション 1 つ分。
struct ListToolbarAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var isDestructive: Bool = false
    let action: @MainActor () -> Void

    init(id: String, title: String, systemImage: String,
         isDestructive: Bool = false, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// ライブ / アイドル / 楽曲 共通のツールバー構成。
///
/// - 左: 設定 + グローバル検索 (各タブ共通)
/// - 右: 虫眼鏡(タブ内検索) → フィルタ(バッジ) → 副次アクション
///
/// 副次操作 (追加・表示切替・タグ・フィルタ解除など) は 1 つの `ToolbarItem` に HStack で
/// 詰めない。HStack 詰めだと幅不足時に iOS の「…」が機能せず (押しても何も出ない) 操作
/// 不能になるため。代わりに件数で出し分ける:
///   - 0 件 → 何も出さない
///   - 1 件 → そのまま直接ボタンで出す (1 つしかないのに「…」に隠さない)
///   - 2 件以上 → ellipsis メニューに畳む
/// これで 3 タブのツールバーが見た目・挙動とも揃う。
@MainActor @ToolbarContentBuilder
func standardListToolbar(
    onSearch: @escaping @MainActor () -> Void,
    filterBadge: Int,
    onFilter: @escaping @MainActor () -> Void,
    menuActions: [ListToolbarAction]
) -> some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) { SettingsToolbarButton() }
    ToolbarItem(placement: .topBarLeading) { GlobalSearchToolbarButton() }
    ToolbarItem(placement: .topBarTrailing) {
        Button(action: onSearch) {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("検索")
    }
    ToolbarItem(placement: .topBarTrailing) {
        FilterBarButton(activeCount: filterBadge, action: onFilter)
    }
    if menuActions.count == 1, let only = menuActions.first {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: only.action) {
                Image(systemName: only.systemImage)
                    .foregroundStyle(only.isDestructive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
            .accessibilityLabel(only.title)
        }
    } else if menuActions.count >= 2 {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(menuActions) { item in
                    Button(role: item.isDestructive ? .destructive : nil, action: item.action) {
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
            } label: {
                Image(systemName: filterBadge > 0 ? "ellipsis.circle.fill" : "ellipsis.circle")
            }
            .accessibilityLabel("その他の操作")
        }
    }
}
