import Foundation

/// 入力欄の上限と数え方 (タグ名 30・タグの説明 300・表示名 40・お題 80・お題の説明 280)。
///
/// 上限の値も数え方 (表示名はコードポイント、ほかはサーバの `.length` と同じ UTF-16)、
/// 前後の空白を除くか、空を許すかも、コア (`input_limit_max` / `input_length` /
/// `input_clamp` / `input_is_acceptable`) が決める。ここは画面の言い回しに包むだけ。
enum InputLimits {
    /// 「N / 上限文字」の数え。`separator` と `unit` は画面ごとの今の見た目に合わせる。
    static func counter(_ field: InputField, _ text: String,
                        separator: String = " / ", unit: String = "文字") -> String {
        "\(inputLength(field: field, text: text))\(separator)\(inputLimitMax(field: field))\(unit)"
    }

    /// 入力が変わるたびに通す (上限で切る。文字の途中では切らない)。
    static func clamp(_ field: InputField, _ text: String) -> String {
        inputClamp(field: field, text: text)
    }

    /// 送信してよいか。
    static func isAcceptable(_ field: InputField, _ text: String) -> Bool {
        inputIsAcceptable(field: field, text: text)
    }

    static func max(_ field: InputField) -> Int { Int(inputLimitMax(field: field)) }
}
