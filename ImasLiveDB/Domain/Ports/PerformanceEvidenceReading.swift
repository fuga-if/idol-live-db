import Foundation

/// 披露実績の集計 (共起曲 / 歌唱者) の読み取りポート (driven port)。
///
/// `SongReading` に相乗りさせず独立させている理由:
/// - これは全セトリ・全出演者を走査して初めて出せる集計で、**SQL 経路に等価な実装が無い**。
///   楽曲マスタの読み取り (`SongReading`) とは供給源も可用性も違う。
/// - そのため「未ロードなら空を返す」という他ポートに無い契約を持つ。契約の違うものを
///   同じポートに混ぜると、実装側が「どのメソッドはフォールバックできるのか」を
///   メソッドごとに覚える羽目になる。
///
/// 実装は `Adapters/Persistence/CorePerformanceEvidenceRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol PerformanceEvidenceReading: Sendable {
    /// 曲詳細に出す披露実績 (共起曲 + 歌唱者) を **1 回のクエリで**取る。
    ///
    /// 曲詳細は最も開かれる画面なので、共起と歌唱者を別々に問い合わせない
    /// (共有コア側も `song_performance_insights` で束ねて返している)。
    ///
    /// スナップショット未ロード時は `throw` せず `.empty` を返す。この機能に旧経路は
    /// 無いので、出せない時は節ごと出さないのが正しい振る舞い (他の情報は従来どおり出る)。
    func songPerformanceEvidence(
        songId: String,
        coLimit: Int,
        singerLimit: Int
    ) async throws -> SongPerformanceEvidence
}
