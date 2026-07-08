import SwiftUI

/// イントロドン (ソロ) の Setup → Game → Result 間で共有する「複数階層まとめてpopしたい」シグナル。
///
/// この3画面はそれぞれ別の親が持つ実体のある `@State` Bool (Setup を presentするHome/SongList側の
/// Bool、Game を presentするSetup側の `navigateToGame`) に紐づく `dismiss()` で確実にpopできる。
/// 一方で Result → Home のように複数階層をまたいで一気に戻りたい場合、Result 自身の
/// `dismiss()` を連打しても「自分がpushされた1階層」しか閉じられず、祖先までは連鎖しない。
///
/// そこで Setup/Game/Result で同一インスタンスを共有し、Result 側でトークンをインクリメントする
/// ことで、Setup・Game それぞれが「自分の階層の実体あるdismiss()」を各々呼び出し、結果として
/// 3階層まとめて閉じる。Bool ではなく単調増加のトークンにしているのは、同じ値→値では
/// `onChange` が発火せず「もう一度あそぶ」を繰り返した際に2回目以降が届かなくなるのを防ぐため。
@Observable
final class IntroDonExitSignal {
    /// Result の「ホームに戻る」: Setup・Game・Result をすべて閉じて呼び出し元 (Home 等) まで戻る。
    private(set) var exitToHomeToken = 0
    /// Result の「もう一度あそぶ」: Game・Result だけを閉じて (積み上げ済みの) Setup まで戻る。
    private(set) var replayToken = 0

    func requestExitToHome() { exitToHomeToken &+= 1 }
    func requestReplay() { replayToken &+= 1 }
}
