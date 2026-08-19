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

    /// 検索欄を1つ足す。既に空の欄があるならそれを使う (空行を積まない)。
    func addTerm() {
        guard !children.contains(where: {
            !$0.isGroup && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return }
        children.append(LyricsQueryNode())
    }

    /// 入れ子グループを足す。親と逆の演算子で始めると、そのまま意味のある式になる
    /// (AND の中に OR を作る = 表記ゆれの束ね、が一番多い使い方)。
    ///
    /// 空の入力欄があればそれを置き換える。追加のたびに使わない空行が
    /// 積み上がると、消す手間が増えるだけで意味が無い。
    func addGroup() {
        let inner: Op = (op == .and) ? .or : .and
        let group = LyricsQueryNode(op: inner,
                                    children: [LyricsQueryNode(), LyricsQueryNode()])
        if let slot = children.firstIndex(where: {
            !$0.isGroup && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            children[slot] = group
        } else {
            children.append(group)
        }
    }

    func remove(_ child: LyricsQueryNode) {
        children.removeAll { $0.id == child.id }
        // まとまりが1つだけになったら、その中身を親へ引き上げて段を減らす。
        // 中身1つのまとまりは式として意味が無く、インデントが無駄に深くなるだけ。
        if isGroup, children.count == 1, let only = children.first, only.isGroup {
            op = only.op
            children = only.children
        }
    }

    /// この子を1つ上の兄弟とまとめる。既に上がまとまりならそこへ入れる。
    ///
    /// 「空のまとまりを作って埋める」より手順が短い。打ってから
    /// 「こことここをまとめる」と言える方が、作りたい形から素直に辿れる。
    func groupWithPrevious(_ child: LyricsQueryNode) {
        guard let index = children.firstIndex(where: { $0.id == child.id }), index > 0 else { return }
        let previous = children[index - 1]
        if previous.isGroup {
            previous.children.append(child)
            children.remove(at: index)
            return
        }
        // 親と逆の演算子で始める (AND の中に OR = 表記ゆれの束ね、が一番多い使い方)。
        let inner: Op = (op == .and) ? .or : .and
        children[index - 1] = LyricsQueryNode(op: inner, children: [previous, child])
        children.remove(at: index)
    }

    /// まとまりを解いて中身を親の位置へ戻す。
    func ungroup(_ child: LyricsQueryNode) {
        guard child.isGroup,
              let index = children.firstIndex(where: { $0.id == child.id }) else { return }
        children.replaceSubrange(index...index, with: child.children)
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

    // MARK: - 簡易検索との行き来

    /// 簡易検索の入力 (空白区切り) を式にする。**空白は AND**。
    ///
    /// OR ではなく AND にしたのは、OR だと 2語打つと 1語より結果が増えるため。
    /// 絞ろうとして増えるのは直感に反する (夢=1,273曲 / 夢+翼 は AND 98曲・OR 1,308曲)。
    /// 表記ゆれは かなの正規化が ツバサ/つばさ を吸収するので、残る漢字絡み
    /// (翼 と つばさ) だけが詳細検索の担当になる。
    static func simpleQuery(_ raw: String) -> String {
        let terms = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return "" }
        return terms.map { "\"\($0)\"" }.joined(separator: " ")
    }

    /// 簡易の入力を詳細の木に移す。切り替えで打ち直しにならないように。
    static func fromSimple(_ raw: String) -> LyricsQueryNode {
        let terms = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return .initialRoot() }
        // 簡易は空白 = AND なので、移した先も「かつ」で始める。
        return LyricsQueryNode(op: .and, children: terms.map { LyricsQueryNode(text: $0) })
    }

    /// 詳細の木を簡易の入力に戻す (語だけ拾って空白区切り)。
    /// 構造は落ちるので、戻すときは値が変わりうることを画面側で伝えること。
    func flattenedTerms() -> String {
        if !isGroup {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return children.map { $0.flattenedTerms() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 画面に出す見出し。
    var opLabel: String { op == .and ? "すべて含む" : "いずれか含む" }

    /// 人が読める式。詳細検索を畳んだときに「今どんな条件か」を1行で見せる。
    /// 記号 (| や括弧) ではなく日本語で出す。式の記法を覚えている前提にしない。
    func readable() -> String {
        if !isGroup {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let parts = children.map { $0.readable() }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        guard parts.count > 1 else { return parts[0] }
        let joined = parts.joined(separator: op == .and ? " かつ " : " または ")
        return "(\(joined))"
    }
}
