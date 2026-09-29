import SwiftUI

/// イントロドンの結果画面から「ホームに戻る」ときだけ使う、Setup へのシグナル。
///
/// ## なぜ Game ではなく Setup だけが見るのか
///
/// **SwiftUI は push で隠れた View の `onChange` を走らせない。** body は新しい値で
/// 再評価されるのに `onChange` のクロージャだけ呼ばれないため、結果画面を push して
/// いた頃は Game も Setup も「もう一度あそぶ」「ホームに戻る」を受け取れず、どちらの
/// ボタンも無反応だった (App Store のレビューで「アプリを落とすしかない」と複数報告)。
///
/// いまは結果画面を Game の `fullScreenCover` で出す。Game は presenter として生きた
/// ままなので、Game 自身の `dismiss()` がそのまま効く。残る 1 段 (Setup → Home) だけを
/// このシグナルで渡す。Setup は Game が pop された**後**に見えるようになるので、
/// そのときには `onChange` が正常に届く。
///
/// トークンにしてあるのは、同じ値→値では `onChange` が発火せず、2 回目以降の
/// 「ホームに戻る」が届かなくなるのを防ぐため。
@Observable
final class IntroDonExitSignal {
    private(set) var exitToHomeToken = 0

    func requestExitToHome() { exitToHomeToken &+= 1 }
}
