import Foundation

/// 曲詳細のサーバ側データ (タグ / 類似曲 / ペンライト / 歌詞) の読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、束ねエンドポイント `/songs/{id}/detail` や
/// 旧個別エンドポイントへのフォールバックといった取得の具象を知らない。
/// 実装は `Services/SongDetailAPI`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
///
/// ⚠️ 戻り値には歌詞が含まれる。実装はディスクキャッシュを持たないセッションで取ること
/// (JASRAC 許諾の条件。`Models/Lyrics.swift` の注記を参照)。
protocol SongDetailReading: Sendable {
    /// 曲詳細 1 画面ぶんのサーバ側データを **1 リクエスト**で取る。
    ///
    /// 取れなかった要素・存在しない要素は `nil` で返る (エラーではなく「今は無い」)。
    /// 通信そのものが失敗した場合だけ throw する。
    func songDetail(songId: String) async throws -> SongDetailBundle
}
