import SwiftUI

/// フィルタシート先頭に置く「名前で絞り込み」フィールド。
///
/// これは検索ではなく **フィルタ** である (ブランド絞り込み・並び順と合成され、一覧の並びを保つ)。
/// 以前はツールバーの虫眼鏡から出るインライン検索だったが、それだと同じナビバーに虫眼鏡が
/// 2 つ並び「探す (詳細へ飛ぶ)」と「絞る (一覧を絞る)」の区別が付かなかったため、
/// 役割どおりフィルタ側へ移した。横断的に探すのは `UnifiedSearchView` の担当。
struct NameFilterField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: DS.sp3) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.imasScaled(13, weight: .semibold))
                .foregroundStyle(DS.ink3)
            TextField(prompt, text: $text)
                .font(.imasSubhead)
                .foregroundStyle(DS.ink)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.imasScaled(14))
                        .foregroundStyle(DS.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("絞り込みを解除")
            }
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, 8)
        .background(DS.fill, in: Capsule())
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
/// - 左: 設定
/// - 右: 検索(虫眼鏡・1 つだけ) → フィルタ(バッジ) → 副次アクション
///
/// 虫眼鏡は **アプリ全体で 1 つ**。以前は左に「全体検索」右に「タブ内検索」の 2 つが並んでいて
/// 区別が付かなかった。今は虫眼鏡 = `UnifiedSearchView` (呼び出し元タブのスコープで開く) に一本化し、
/// 一覧の絞り込みはフィルタ側 (`NameFilterField`) に寄せている。
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
    searchScope: UnifiedSearchScope,
    filterBadge: Int,
    onFilter: @escaping @MainActor () -> Void,
    menuActions: [ListToolbarAction]
) -> some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) { SettingsToolbarButton() }
    ToolbarItem(placement: .topBarTrailing) { SearchToolbarButton(scope: searchScope) }
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
