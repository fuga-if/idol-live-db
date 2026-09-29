import Foundation
import os

/// イベント名の作品名プレフィックスを省略表示するかどうかの設定キー。
/// 既定 ON (= 省略)。設定画面でフル表示に切り替えられる。
let eventNameAbbreviateKey = "event_name_abbreviate"

/// ライブ名の先頭を埋める作品名 (ブランドはリードバー色で示すため冗長) を表示時だけ取り除き、
/// 公演を識別しやすくする。一覧・履歴・ピッカーなどアプリ全体の「行表示」で共通利用する。
/// 詳細画面のタイトルや共有文・デバイスカレンダー保存名など、正式名称が必要な箇所では使わない。
///
/// 落とし方 (どの作品名を・短くなりすぎたら元の名前) はコアの `event_short_name`。
/// ここは設定を見て、名前ごとに覚えるだけ (ライブ名は有界なので行ごとに FFI を呼ばない)。
func eventDisplayName(_ name: String) -> String {
    // 設定で OFF (フル表示) なら何もしない。キー未設定は ON (省略) 扱い。
    if UserDefaults.standard.object(forKey: eventNameAbbreviateKey) != nil,
       !UserDefaults.standard.bool(forKey: eventNameAbbreviateKey) {
        return name
    }
    return EventShortNames.of(name)
}

private enum EventShortNames {
    private static let cache = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    static func of(_ name: String) -> String {
        if let cached = cache.withLock({ $0[name] }) { return cached }
        let short = eventShortName(name: name)
        cache.withLock { $0[name] = short }
        return short
    }
}
