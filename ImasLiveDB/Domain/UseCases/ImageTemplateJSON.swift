import Foundation

/// 画像一括インポート用の「型紙」JSON を組み立てる。
///
/// アイドル名/ブランド名/ユニット名をキーに、URL を空文字で並べた JSON を配って
/// ユーザーに埋めてもらう仕組み。名前には `"` や `\` や絵文字が入りうるので、
/// 手書きのエスケープではなく `JSONSerialization` に文字列化させる。
///
/// 出力はキー順を保つ (`JSONSerialization` に辞書を渡すと順序が崩れるため、
/// 1 行ずつ組み立てている)。名前の並び = 一覧の並びのままにしておかないと、
/// 数百行の型紙から目的のアイドルを探すのが難しくなる。
func imageTemplateJSON(pairs: [(String, String)]) -> String {
    var lines: [String] = ["{"]
    for (i, (key, value)) in pairs.enumerated() {
        let comma = i < pairs.count - 1 ? "," : ""
        lines.append("  \(jsonStringLiteral(key)): \(jsonStringLiteral(value))\(comma)")
    }
    lines.append("}")
    return lines.joined(separator: "\n")
}

/// 文字列を JSON のリテラル (引用符込み) にする。
/// `JSONSerialization` に 1 要素の配列を書かせて `[` `]` を落とす方式。
func jsonStringLiteral(_ s: String) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data()
    let arrayString = String(data: data, encoding: .utf8) ?? "[\"\"]"
    return String(arrayString.dropFirst().dropLast())
}
