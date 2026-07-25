import SwiftUI
import UIKit

/// 名前・曲名などを長押しでコピーできるようにする共通修飾子。
///
/// 「正式な曲名で外部検索したい」「アイドル名をそのまま貼りたい」といった用途で、
/// 一覧・詳細のどこからでも原文を取り出せるようにする。
///
/// なぜ `.textSelection(.enabled)` ではなく contextMenu か:
/// 一覧の行はタップで詳細へ遷移する。テキスト選択を有効にすると行タップが
/// テキスト側に吸われて遷移できなくなるため、タップと共存する長押しメニューにしている。
struct ImasCopyableModifier: ViewModifier {
    /// コピーされる文字列。表示が加工されていても **原文** を渡すこと
    /// (例: 表示は省略されていても曲名は全文をコピーできるように)。
    let text: String
    /// メニューに出すラベル。「曲名をコピー」のように対象を言う。
    let label: String

    func body(content: Content) -> some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content
        } else {
            content.contextMenu {
                Button {
                    UIPasteboard.general.string = text
                    // コピーは画面に変化が出ないので、触覚で「入った」ことを返す。
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    AppAnalytics.tap("copy.\(label)")
                } label: {
                    Label(label, systemImage: "doc.on.doc")
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
    func imasCopyable(_ text: String?, label: String = "コピー") -> some View {
        modifier(ImasCopyableModifier(text: text ?? "", label: label))
    }

    /// 複数項目をまとめてコピーできるようにする (曲名とアーティスト名など)。
    /// 主となる項目を先頭に置くこと。
    func imasCopyable(_ items: [(label: String, text: String?)]) -> some View {
        let valid = items.compactMap { item -> (String, String)? in
            guard let t = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return (item.label, t)
        }
        return contextMenu {
            if !valid.isEmpty {
                ForEach(Array(valid.enumerated()), id: \.offset) { _, item in
                    Button {
                        UIPasteboard.general.string = item.1
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        AppAnalytics.tap("copy.\(item.0)")
                    } label: {
                        Label(item.0, systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
