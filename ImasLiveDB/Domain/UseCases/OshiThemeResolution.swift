import Foundation

/// 担当(推し)カラーをアプリ全体テーマに使うときの、保存すべき値の解決結果。
struct OshiThemeResolution: Equatable {
    /// 保存し直す担当アイドル ID。
    /// `nil` は「現在の選択を変更しない」の意味 (テーマ機能が OFF のとき)。
    var idolId: String?
    /// `ContentView` が参照する解決済みテーマ色 hex。無効・該当なしは空文字。
    var colorHex: String
}

/// 担当テーマ色を、現在の選択と担当一覧から解決する。
///
/// 非自明なのは次の 2 点なので純粋関数に切り出してある:
///
/// 1. **OFF のときは色だけ消し、選択した担当 ID は残す。**
///    消してしまうと、ユーザーが後で ON に戻したときに選び直しになる。
/// 2. **選択中の担当が担当から外れていたら、先頭の担当へ黙って寄せる。**
///    担当を解除したのにテーマ色だけ残り続ける状態を防ぐ。担当が 0 人なら空にする。
///
/// - Parameters:
///   - isEnabled: 担当カラーをテーマに使う設定 (`theme_use_oshi_color`)。
///   - currentIdolId: 現在保存されている担当 ID (`theme_oshi_idol_id`)。
///   - pickIdols: 「担当」としてマークされているアイドル。
func resolveOshiTheme(
    isEnabled: Bool,
    currentIdolId: String,
    pickIdols: [Idol]
) -> OshiThemeResolution {
    guard isEnabled else {
        return OshiThemeResolution(idolId: nil, colorHex: "")
    }

    // 選択が空、または担当から外れていたら先頭の担当に寄せる。
    let resolvedId: String
    if currentIdolId.isEmpty || !pickIdols.contains(where: { $0.id == currentIdolId }) {
        resolvedId = pickIdols.first?.id ?? ""
    } else {
        resolvedId = currentIdolId
    }

    let hex = pickIdols.first { $0.id == resolvedId }?.color ?? ""
    return OshiThemeResolution(idolId: resolvedId, colorHex: hex)
}
