import SwiftUI

/// 歌詞検索の検索式をアウトライン形式で組み立てる。
///
/// 括弧を打たせる代わりに**インデントで入れ子を見せる**。グループごとに
/// 「すべて含む / いずれか含む」を持つので、`(翼 or つばさ) and 夢` と
/// `翼 or (夢 and 星)` のどちらも書ける。固定の優先順位だと片方しか表現できない。
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
        VStack(alignment: .leading, spacing: DS.sp2) {
            // 子が2つ以上ないと「すべて/いずれか」に意味が無いので、1つのときは出さない。
            if node.children.count > 1 || depth > 0 {
                HStack(spacing: DS.sp3) {
                    Button {
                        node.op = (node.op == .and) ? .or : .and
                        AppAnalytics.tap("lyrics_query.toggle_op")
                    } label: {
                        Label(node.opLabel,
                              systemImage: node.op == .and ? "square.stack.3d.up" : "arrow.triangle.branch")
                            .font(.imasCaption.weight(.semibold))
                            .foregroundStyle(DS.ink2)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if let onRemove {
                        Button(role: .destructive, action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("このグループを削除")
                    }
                }
            }

            ForEach(node.children) { child in
                if child.isGroup {
                    LyricsQueryGroupView(node: child, depth: depth + 1,
                                         onRemove: { node.remove(child) }, onSubmit: onSubmit)
                        .padding(.leading, DS.sp4)
                        .overlay(alignment: .leading) { nestingRule }
                } else {
                    termRow(child, onRemove: node.children.count > 1
                            ? { node.remove(child) } : nil)
                }
            }

            HStack(spacing: DS.sp4) {
                Button {
                    node.addTerm()
                    AppAnalytics.tap("lyrics_query.add_term")
                } label: {
                    Label("条件", systemImage: "plus.circle")
                        .font(.imasCaption)
                }
                .buttonStyle(.plain)
                // 深くしすぎても読めないので2段まで。実用上ここで足りる。
                if depth < 2 {
                    Button {
                        node.addGroup()
                        AppAnalytics.tap("lyrics_query.add_group")
                    } label: {
                        Label("グループ", systemImage: "plus.rectangle.on.rectangle")
                            .font(.imasCaption)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(DS.ink2)
        }
    }

    /// 入れ子であることを示す縦罫。インデントだけだと段が読み取りにくい。
    private var nestingRule: some View {
        Rectangle()
            .fill(DS.sep)
            .frame(width: 1)
            .padding(.vertical, 2)
    }

    // MARK: - 検索語

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
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, 8)
        .background(DS.fill, in: Capsule())
    }
}
