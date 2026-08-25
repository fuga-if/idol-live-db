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
        .padding(.vertical, DS.sp3)
        .background(DS.fill, in: Capsule())
    }
}

/// 同じバーに並ぶツールバーボタン (設定・フィルタ・その他) の背景の高さ。
///
/// iOS が描くボタン背景をスクリーンショットから実測した値 (44pt)。入力欄の高さを
/// 中身任せにすると 31pt にしかならず、隣のボタンより一回り低くなって収まりが悪い。
private let listSearchFieldHeight: CGFloat = 44

/// ナビゲーションバーの中に収める、1 行ぶんの絞り込みフィールド。
///
/// `.searchable` のドロワーは常時 52pt の行を占め、大タイトル (52pt) と合わせると
/// ステータスバー・フィルタチップ込みで画面の 3 割近くが中身の前に消えていた。
/// ここではバー (44pt) そのものに入れて、ヘッダーを 1 行に畳む。
///
/// `.searchable` を捨てた代償は自前で埋める:
/// - 消去は末尾の ⊗ (テキストがあるときだけ出す)
/// - `.searchScopes` の代わりが `leading` (楽曲一覧の 曲名/歌詞 切り替え)
/// - キーボードを閉じる導線は一覧側の `.scrollDismissesKeyboard` に任せる
///
/// 文字サイズは `.accessibility1` で頭打ちにする。ナビバーの高さは中身では伸びないので、
/// 際限なく拡大すると入力欄が切れて操作できなくなる。
///
/// 高さは隣のツールバーボタンに合わせる (`listSearchFieldHeight`)。
struct ListSearchField<Leading: View>: View {
    let prompt: String
    @Binding var text: String
    /// 確定 (キーボードの検索キー)。歌詞のようにサーバへ投げるものだけが使う。
    var onSubmit: () -> Void = {}
    /// 入力欄の頭に差す小物。検索対象の切り替えなど。
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: DS.sp2) {
            Image(systemName: "magnifyingglass")
                .font(.imasScaled(13, weight: .semibold))
                .foregroundStyle(DS.ink3)
            leading
            TextField(prompt, text: $text)
                .font(.imasSubhead)
                .foregroundStyle(DS.ink)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
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
        // ⚠️ `frame` は **`background` より先**に置くこと。
        // 後ろに置くと、カプセルは中身の幅のまま描かれて透明な枠だけが広がる
        // (見た目は「中央に寄った小さい入力欄」になり、余白の理由が分からなくなる)。
        //
        // `maxWidth: .infinity` だけでは広がらない。ナビバーの中央 (`.principal`) は
        // UIKit の titleView で、中身の**理想サイズ**を訊いて幅を決めるため。
        // 巨大な `idealWidth` を返して、左右のツールバー項目に挟まれた残り幅まで
        // 押し広げてもらう。
        .frame(idealWidth: 10_000, maxWidth: .infinity, minHeight: listSearchFieldHeight)
        .background(DS.fill, in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

extension ListSearchField where Leading == EmptyView {
    init(prompt: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) {
        self.init(prompt: prompt, text: text, onSubmit: onSubmit) { EmptyView() }
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
/// - 中央: 絞り込みフィールド (`ListSearchField`)
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
