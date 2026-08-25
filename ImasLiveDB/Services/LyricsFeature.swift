import Foundation

/// 歌詞タブ (= コールガイド) を画面に出してよいか。
///
/// 歌詞の掲載には JASRAC の許諾が要る。申請は出してあるが**認可はまだ下りていない**ので、
/// 審査に出すバイナリ (Release / TestFlight / App Store) にはこの機能を載せない。
///
/// サーバ側でも全曲 `status=draft` にしてあり admin にしか返らないが、それは
/// 「一般ユーザーに配信されない」保証であって「アプリに載っていない」保証ではない。
/// 導線ごと消すためにビルド構成でも切る。
///
/// 認可が下りたら `isAvailable` を `true` 固定にすればタブが復活する。呼び出し側は
/// `SongDetailTab.available` 経由でここしか見ていないので、直すのはこの 1 箇所でよい。
enum LyricsFeature {
    static var isAvailable: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
