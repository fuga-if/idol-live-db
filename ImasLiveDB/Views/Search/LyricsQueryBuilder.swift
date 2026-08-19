import Foundation
import Observation

/// 歌詞検索の検索式を組み立てる木。
///
/// 葉が検索語、節が「すべて含む (AND)」「いずれか含む (OR)」。
/// 入れ子にできるので `(翼 or つばさ) and 夢` と `翼 or (夢 and 星)` の両方が書ける。
/// 固定の優先順位だけだとどちらか一方しか表現できないため、木にしてある。
///
/// 参照型なのは、SwiftUI で木を編集するのに Binding を掘り下げるのが煩雑なため。
@Observable
final class LyricsQueryNode: Identifiable {
    enum Op: String { case and, or }

    let id = UUID()
    /// 葉のときの検索語。グループでは使わない。
    var text: String
    /// グループのときの結合方法。nil なら葉。
    var op: Op?
    var children: [LyricsQueryNode]

    var isGroup: Bool { op != nil }

    init(text: String = "") {
        self.text = text
        self.op = nil
        self.children = []
    }

    init(op: Op, children: [LyricsQueryNode]) {
        self.text = ""
        self.op = op
        self.children = children
    }

    /// 既定の形。検索欄が1つあるだけに見える。
    static func initialRoot() -> LyricsQueryNode {
        LyricsQueryNode(op: .and, children: [LyricsQueryNode()])
    }

    // MARK: - 編集

    func addTerm() { children.append(LyricsQueryNode()) }

    /// 入れ子グループを足す。親と逆の演算子で始めると、そのまま意味のある式になる
    /// (AND の中に OR を作る = 表記ゆれの束ね、が一番多い使い方)。
    func addGroup() {
        let inner: Op = (op == .and) ? .or : .and
        children.append(LyricsQueryNode(op: inner, children: [LyricsQueryNode()]))
    }

    func remove(_ child: LyricsQueryNode) {
        children.removeAll { $0.id == child.id }
    }

    // MARK: - 文字列化

    /// サーバに送る式にする。中身が空の枝は落とす。
    ///
    /// 語は必ず `"…"` で囲う。歌詞は全角スペースで区切られている
    /// (「空を描いて行くよ　ここで光るよ」) ので、囲わないと空白 = AND として割れる。
    func serialized() -> String {
        if !isGroup {
            let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            return term.isEmpty ? "" : "\"\(term)\""
        }
        let parts = children.map { $0.serialized() }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        guard parts.count > 1 else { return parts[0] }
        let joined = parts.joined(separator: op == .and ? " " : "|")
        return "(\(joined))"
    }

    /// 検索できる状態か (語が1つ以上ある)。
    var hasAnyTerm: Bool { !serialized().isEmpty }

    /// 画面に出す見出し。
    var opLabel: String { op == .and ? "すべて含む" : "いずれか含む" }
}
