import SwiftUI

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
/// - 左: 設定
/// - 中央: 絞り込みフィールド (`ImasSearchField`)
/// - 右: フィルタ(バッジ) → 副次アクション
///
/// 検索欄はバーの中に置き、大タイトルは出さない。以前は大タイトル + 検索ドロワーで
/// ヘッダーが 2 行あり、中身が見え始めるまでが遠かった。タブ名はタブバーに出ているので
/// 見出しが消えても現在地は分かる。
///
/// 虫眼鏡 (`UnifiedSearchView` への入口) はここには置かない。一覧の絞り込みが
/// 一覧側に来たことで役割が重なり、同じバーに検索欄と虫眼鏡が並ぶと
/// 「探す」と「絞る」の区別が付かないため。横断検索はカレンダータブに残してある。
///
/// 副次操作 (追加・表示切替・タグ・フィルタ解除など) は 1 つの `ToolbarItem` に HStack で
/// 詰めない。HStack 詰めだと幅不足時に iOS の「…」が機能せず (押しても何も出ない) 操作
/// 不能になるため。代わりに件数で出し分ける:
///   - 0 件 → 何も出さない
///   - 1 件 → そのまま直接ボタンで出す (1 つしかないのに「…」に隠さない)
///   - 2 件以上 → ellipsis メニューに畳む
/// これで 3 タブのツールバーが見た目・挙動とも揃う。
@MainActor @ToolbarContentBuilder
func standardListToolbar<SearchField: View>(
    filterBadge: Int,
    onFilter: @escaping @MainActor () -> Void,
    menuActions: [ListToolbarAction],
    @ViewBuilder searchField: () -> SearchField
) -> some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) { SettingsToolbarButton() }
    ToolbarItem(placement: .principal) { searchField() }
    ToolbarItem(placement: .topBarTrailing) {
        FilterBarButton(activeCount: filterBadge, action: onFilter)
    }
    // 試作の AI チャット (開発ビルド / TestFlight だけ)。
    if ChatGPTPlanSession.isPrototypeVisible {
        ToolbarItem(placement: .topBarTrailing) { AssistantToolbarButton() }
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
