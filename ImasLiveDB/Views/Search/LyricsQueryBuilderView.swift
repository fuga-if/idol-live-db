import SwiftUI

/// 歌詞検索の検索式をアウトライン形式で組み立てる。
///
/// 演算子は**各行の頭**に「かつ / または」として出す。グループの見出しに
/// 「すべて含む」と書く形も試したが、式の言い方であって操作対象に見えなかった。
/// 行間に置けば「この行を前の行とどうつなぐか」がそのまま読める。
///
/// 入れ子はインデントと縦罫で見せる。括弧を打たせずに
/// `(翼 or つばさ) and 夢` と `翼 or (夢 and 星)` の両方を書けるようにするため。
struct LyricsQueryBuilderView: View {
    @Bindable var root: LyricsQueryNode
    /// 確定 (検索実行)。キーボードの検索キーからも呼ぶ。
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            LyricsQueryGroupView(node: root, depth: 0, onRemove: nil, onSubmit: onSubmit)
        }
        .padding(.horizontal, DS.sp5)
        .padding(.bottom, DS.sp3)
    }
}

/// グループ1つぶん。**独立した View 型**にしてあるのは、再帰する `some View` を
/// 関数で書くと「不透明型が自分自身で定義される」ためコンパイルできないから。
private struct LyricsQueryGroupView: View {
    @Bindable var node: LyricsQueryNode
    let depth: Int
    let onRemove: (() -> Void)?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp1) {
            ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                HStack(alignment: .top, spacing: DS.sp2) {
                    // 演算子は**1グループに1つ**。行ごとに別々に持てると
                    // 「A または B かつ C」の優先順位が決まらないため。分けたいときは
                    // まとまりを作る。
                    //
                    // なので押せるのは2行目だけにして、3行目以降は同じ値を静かに出す。
                    // 全部を押せるボタンにすると行ごとに変えられると誤解される
                    // (実際そう見えるという指摘を受けた)。
                    Group {
                        if index > 0 { junctionChip(for: child) } else { Color.clear }
                    }
                    .frame(width: 46, height: 28)

                    if child.isGroup {
                        LyricsQueryGroupView(node: child, depth: depth + 1,
                                             onRemove: { node.remove(child) },
                                             onSubmit: onSubmit)
                            .padding(.leading, DS.sp2)
                            .overlay(alignment: .leading) { nestingRule }
                    } else {
                        termRow(child,
                                onRemove: node.children.count > 1 ? { node.remove(child) } : nil)
                    }
                }
            }

            HStack(spacing: DS.sp4) {
                Color.clear.frame(width: 46, height: 1)
                Button {
                    node.addTerm()
                    AppAnalytics.tap("lyrics_query.add_term")
                } label: {
                    Label("条件を追加", systemImage: "plus.circle")
                        .font(.imasCaption)
                }
                .buttonStyle(.plain)
                // 深くしすぎても読めないので2段まで。実用上ここで足りる。
                if depth < 2 {
                    Button {
                        node.addGroup()
                        AppAnalytics.tap("lyrics_query.add_group")
                    } label: {
                        Label("まとまり", systemImage: "plus.rectangle.on.rectangle")
                            .font(.imasCaption)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.imasCaption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("このまとまりを削除")
                }
            }
            .foregroundStyle(DS.ink2)
        }
    }

    /// 行と行のつなぎ目。ここを押すと「つなぎ方の変更」と「まとめる」が出る。
    ///
    /// つなぎ方はまとまり全体に効く (行ごとに別々だと「A または B かつ C」の
    /// 優先順位が決まらない)。メニューの文言で「すべて」と明示して、
    /// 1つ変えたら全部変わることが押す前に分かるようにしている。
    private func junctionChip(for child: LyricsQueryNode) -> some View {
        Menu {
            Section("つなぎ方") {
                Button { setOp(.and) } label: {
                    Label("すべて「かつ」", systemImage: node.op == .and ? "checkmark" : "")
                }
                Button { setOp(.or) } label: {
                    Label("すべて「または」", systemImage: node.op == .or ? "checkmark" : "")
                }
            }
            Button {
                node.groupWithPrevious(child)
                AppAnalytics.tap("lyrics_query.group_with_previous")
            } label: {
                Label("上の行とまとめる", systemImage: "rectangle.3.group")
            }
            if child.isGroup {
                Button {
                    node.ungroup(child)
                    AppAnalytics.tap("lyrics_query.ungroup")
                } label: {
                    Label("まとまりを解除", systemImage: "rectangle.split.3x1")
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(node.op == .and ? "かつ" : "または")
                    .font(.imasCaption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.imasScaled(8))
            }
            .foregroundStyle(DS.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
        }
    }

    private func setOp(_ op: LyricsQueryNode.Op) {
        node.op = op
        AppAnalytics.tap("lyrics_query.toggle_op")
    }

    /// 入れ子であることを示す縦罫。インデントだけだと段が読み取りにくい。
    private var nestingRule: some View {
        Rectangle()
            .fill(DS.sep)
            .frame(width: 1)
            .padding(.vertical, 2)
    }

    private func termRow(_ node: LyricsQueryNode, onRemove: (() -> Void)?) -> some View {
        HStack(spacing: DS.sp3) {
            Image(systemName: "magnifyingglass")
                .font(.imasCaption)
                .foregroundStyle(DS.ink3)
            TextField("歌詞の一節", text: Bindable(node).text)
                .font(.imasBody)
                .foregroundStyle(DS.ink)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("この条件を削除")
            }
        }
        .padding(.horizontal, DS.sp3)
        .padding(.vertical, 6)
        .background(DS.fill, in: Capsule())
    }
}

/// 詳細検索を組むシート。
///
/// 検索画面に置くと、条件を増やすほど縦に伸びて結果が見えなくなる
/// (実際ナビバーに潜り込んだ)。「組む」と「見る」を画面ごと分ける。
struct LyricsQueryBuilderSheet: View {
    @Bindable var root: LyricsQueryNode
    /// 「検索」で閉じるときに呼ぶ。
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp4) {
                    LyricsQueryBuilderView(root: root, onSubmit: onApply)

                    if !root.readable().isEmpty {
                        // 組み上がった式を日本語で見せる。入れ子は行の見た目でも
                        // 分かるが、確定前に一息で読めるものがある方が安心できる。
                        VStack(alignment: .leading, spacing: DS.sp1) {
                            Text("この条件で探します")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink3)
                            Text(root.readable())
                                .font(.imasSubhead)
                                .foregroundStyle(DS.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.sp4)
                        .background(DS.surface,
                                    in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                        .padding(.horizontal, DS.sp5)
                    }
                }
                .padding(.vertical, DS.sp4)
            }
            .background(DS.bg)
            .navigationTitle("詳細検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("検索", action: onApply)
                        .font(.imasSubhead.weight(.semibold))
                        .disabled(!root.hasAnyTerm)
                }
            }
        }
    }
}
