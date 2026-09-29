import Foundation

/// 歌詞クイズの読み取りポート (driven port)。
///
/// 出題母集団 (歌詞を公開している曲の id) と、出題する 1 曲ぶんの歌詞を取る。
/// 実装は `Services/LyricsAPI` (適合は `extension LyricsAPI: LyricsQuizReading`)。
///
/// ⚠️ JASRAC 許諾の条件 (一括ダウンロードできない形式) を守るため、歌詞は**出題のたびに
/// 1 曲ずつ**取る。まとめて先読みしない (次の 1 問ぶんの先読みまで)。公開曲の一覧は
/// 本文を含まない (`GET /lyrics/published`)。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol LyricsQuizReading: Sendable {
    /// 歌詞を公開している曲の id。
    func publishedSongIds() async throws -> [String]

    /// 指定曲の歌詞。未登録は `nil`。
    func lyrics(songId: String) async throws -> Lyrics?
}
