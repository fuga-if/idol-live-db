import Foundation

/// イベント名の作品名プレフィックスを省略表示するかどうかの設定キー。
/// 既定 ON (= 省略)。設定画面でフル表示に切り替えられる。
let eventNameAbbreviateKey = "event_name_abbreviate"

/// ライブ名の先頭を埋める作品名プレフィックス(ブランドはリードバー色で示すため冗長)を
/// 表示時だけ取り除き、公演を識別しやすくする。長いものから1つだけ除去。
/// 除去後が空/極端に短くなる場合は元の名前を返す。
///
/// 一覧・履歴・ピッカーなどアプリ全体の「行表示」で共通利用する。
/// 詳細画面のタイトルや共有文・デバイスカレンダー保存名など、正式名称が必要な箇所では使わない。
private let eventNamePrefixes: [String] = [
    "THE IDOLM@STER CINDERELLA GIRLS ",
    "THE IDOLM@STER MILLION LIVE! ",
    "THE IDOLM@STER MILLION LIVE!",
    "THE IDOLM@STER SideM ",
    "THE IDOLM@STER SHINY COLORS ",
    "THE IDOLM@STER ",
    "アイドルマスター シンデレラガールズ ",
    "アイドルマスター ミリオンライブ! ",
    "アイドルマスター シャイニーカラーズ ",
    "アイドルマスター SideM ",
    "学園アイドルマスター ",
    "アイドルマスター ",
]

func eventDisplayName(_ name: String) -> String {
    // 設定で OFF (フル表示) なら何もしない。キー未設定は ON (省略) 扱い。
    if UserDefaults.standard.object(forKey: eventNameAbbreviateKey) != nil,
       !UserDefaults.standard.bool(forKey: eventNameAbbreviateKey) {
        return name
    }
    for prefix in eventNamePrefixes where name.hasPrefix(prefix) {
        let stripped = String(name.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return stripped.count >= 2 ? stripped : name
    }
    return name
}
