import Foundation
import os

/// 端末にしか無いデータ (担当・参加・メモ・座席・習熟度・家計簿・マイタグ) の書き込み失敗を 1 か所で受ける。
///
/// これらはクラウドにもサーバにも無いので、書けなかったことを黙っていると、保存したつもりの
/// 記録が次に開いたときに消えている。画面は `try?` で握りつぶさず、失敗をここへ渡す。
///
/// ログに残し、利用者にはアラートで知らせる。出し方 (`presenter`) はアプリの起動時に差し込む
/// (`LocalWriteFailureAlert`)。ここは UIKit を知らない。
@MainActor
enum LocalWriteFailure {
    /// 利用者に見せる知らせ。
    struct Notice: Equatable {
        let title: String
        let message: String
    }

    /// 知らせを出す口。nil ならログだけ残す。
    static var presenter: (@MainActor (Notice) -> Void)?

    /// - Parameter action: 何をしようとして失敗したか (例: "メモの保存")。
    static func report(_ error: Error, action: String) {
        Logger.database.error(
            "local_write_failed action=\(action, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )
        presenter?(notice(action: action))
    }

    /// 失敗した操作の名前から、知らせの文面を作る。
    /// 書き込みは 1 トランザクションなので、失敗したら何も変わっていない。それをそのまま伝える。
    static func notice(action: String) -> Notice {
        Notice(
            title: "保存できませんでした",
            message: "\(action)に失敗しました。変更は保存されていません。もう一度お試しください。"
        )
    }
}
