import Foundation

/// 歌詞の読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、取得の具象 (`LyricsAPI` / Worker API) を知らない。
/// 実装は `Services/LyricsAPI` (適合は Data レイヤ側の `extension LyricsAPI: LyricsReading`)。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
///
/// ⚠️ JASRAC 許諾の条件により、歌詞は**プロセス内メモリ以外に一切保持できない**。
/// そのため一般的な「読み取りポート」には現れない `purge()` がここに居る:
/// 破棄はビューの都合ではなく、この機能の成立条件そのものなのでドメイン契約に含める。
protocol LyricsReading: Sendable {
    /// 指定曲の歌詞。歌詞が登録されていない曲 (サーバ 404) は `nil`。
    ///
    /// 未認証 (401) は `APIClientError.notAuthorized` を投げる。
    func lyrics(songId: String) async throws -> Lyrics?

    /// メモリ上に保持している歌詞をすべて破棄する。
    /// バックグラウンド遷移・メモリ警告で呼ぶ。
    func purge() async
}
