import SwiftUI
import UIKit

/// 長押しメニューに出すコピー項目。
struct CopyItem {
    /// メニュー文言。「曲名をコピー」のように **何を** コピーするか言う。
    let label: String
    /// コピーされる原文。表示が加工・省略されていても全文を渡すこと
    /// (例: 一覧で「…」と省略されていても曲名は全文をコピーできるように)。
    let text: String?
    /// 分析用の安定キー。表示文言は変わりうるので集計キーには使わない。
    let key: String

    init(_ label: String, _ text: String?, key: String) {
        self.label = label
        self.text = text
        self.key = key
    }

    /// 空白のみ / nil を除いた、実際にコピーできる本文。
    var usableText: String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

/// 表示要素を長押しでコピーできるようにする共通修飾子。
///
/// 「正式な曲名で外部検索したい」「アイドル名をそのまま貼りたい」といった用途で、
/// 一覧・詳細のどこからでも原文を取り出せるようにする。
///
/// なぜ `.textSelection(.enabled)` ではなく contextMenu か:
/// 一覧の行はタップで詳細へ遷移する。テキスト選択を有効にすると行タップが
/// テキスト側に吸われて遷移できなくなるため、タップと共存する長押しメニューにしている。
///
/// コピーできる項目が 1 つも無いときは修飾自体を付けない。空の contextMenu を
/// 付けると、長押しで浮き上がるのに何も出ない行になってしまうため。
struct ImasCopyableModifier: ViewModifier {
    let items: [CopyItem]

    private var usable: [(item: CopyItem, text: String)] {
        items.compactMap { item in item.usableText.map { (item, $0) } }
    }

    func body(content: Content) -> some View {
        let entries = usable
        if entries.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Button {
                        UIPasteboard.general.string = entry.text
                        // コピーは画面に変化が出ないので、触覚で「入った」ことを返す。
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        AppAnalytics.tap("copy.\(entry.item.key)")
                    } label: {
                        Label(entry.item.label, systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}

extension View {
    /// 長押しでコピーできるようにする。
    /// - Parameters:
    ///   - text: コピーする原文 (表示が省略されていても全文を渡す)。空なら何もしない。
    ///   - label: メニュー文言。既定は「コピー」。対象が分かる文言を推奨。
    ///   - key: 分析用の安定キー。
    func imasCopyable(_ text: String?, label: String = "コピー", key: String = "text") -> some View {
        modifier(ImasCopyableModifier(items: [CopyItem(label, text, key: key)]))
    }

    /// 複数項目をまとめてコピーできるようにする (曲名とアーティスト名など)。
    /// 主となる項目を先頭に置くこと。
    func imasCopyable(_ items: [CopyItem]) -> some View {
        modifier(ImasCopyableModifier(items: items))
    }
}
