import Foundation

/// 披露実績の集計 (共起曲 / 歌唱者) の読み取りポート (driven port)。
///
/// `SongReading` に相乗りさせず独立させている理由は供給源ではなく**責務**:
/// 楽曲マスタの読み取り (`SongReading`) が「1 曲の属性」を返すのに対し、こちらは
/// 全セトリ・全出演者を横断した集計を返す。同じポートに混ぜると、楽曲 1 件を
/// 引きたいだけの呼び出し側にも集計の都合 (件数上限・分母の単位) が漏れる。
///
/// 実装は 2 つあり、どちらも同じ数え方をする:
/// - `Adapters/Persistence/CorePerformanceEvidenceRepository` (共有コアのスナップショット)
/// - `Adapters/Persistence/GRDBPerformanceEvidenceRepository` (SQL)
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol PerformanceEvidenceReading: Sendable {
    /// 曲詳細に出す披露実績 (共起曲 + 歌唱者) を **1 回のクエリで**取る。
    ///
    /// 曲詳細は最も開かれる画面なので、共起と歌唱者を別々に問い合わせない
    /// (共有コア側も `song_performance_insights` で束ねて返している)。
    ///
    /// 空が返るのは「披露実績がまだ 1 度も無い」ときだけ。スナップショットの
    /// 有無で節が出たり消えたりしてはいけない (メモリ警告のあと同じ曲を開き直したら
    /// 節が消えていた、では説明がつかない) ので、実装側は必ず SQL 経路へ落ちること。
    ///
    /// ⚠️ 数え方の単位が 2 つある。UI に出すときは取り違えないこと:
    /// - 共起 (`CoOccurringSong`) は**公演数**。1 公演で 2 回演奏されても 1。
    /// - 歌唱者 (`SongSingerTally`) は**セトリ行数** (= 曲詳細の「総披露 N 回」と同じ)。
    func songPerformanceEvidence(
        songId: String,
        coLimit: Int,
        singerLimit: Int
    ) async throws -> SongPerformanceEvidence
}
