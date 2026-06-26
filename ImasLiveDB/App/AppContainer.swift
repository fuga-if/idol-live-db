import Foundation

/// 合成ルート (Composition Root)。
///
/// 具象実装を1箇所で組み立てて供給する。Presentation (ViewModel) は `.shared` を直接掴まず、
/// ここが渡す抽象 (プロトコル) にだけ依存する。`XxxService.shared` 直参照は段階的にここへ寄せ、
/// 最終的にシングルトンは Container 内部の実装詳細に押し込む。
///
/// 不変の Sendable 依存のみ保持するため、どのスレッド/アクターからでも参照できる。
final class AppContainer: Sendable {
    static let shared = AppContainer()
    private init() {}

    /// 「みんなの投票」のユースケース実装 (Worker D1 集計 API)。
    let communityVoting: any CommunityVoting = CommunityAPI.shared

    /// イベント (ライブ/公演) マスタ読み取りの実装 (GRDB / 共有 AppDatabase)。
    let eventReading: any EventReading = GRDBEventRepository(database: .shared)

    /// 楽曲マスタ読み取りの実装 (GRDB / 共有 AppDatabase)。
    let songReading: any SongReading = GRDBSongRepository(database: .shared)

    /// アイドル(キャスト)マスタ読み取りの実装 (GRDB / 共有 AppDatabase)。
    let idolReading: any IdolReading = GRDBIdolRepository(database: .shared)

    /// ブランドマスタ読み取りの実装 (GRDB / 共有 AppDatabase)。
    let brandReading: any BrandReading = GRDBBrandRepository(database: .shared)

    /// 公演 (Show) / セットリスト読み取りの実装 (GRDB / 共有 AppDatabase)。
    let showReading: any ShowReading = GRDBShowRepository(database: .shared)

    /// ユニットマスタ読み取りの実装 (GRDB / 共有 AppDatabase)。
    let unitReading: any UnitReading = GRDBUnitRepository(database: .shared)

    /// 統計 (ランキング/集計) 読み取りの実装 (GRDB / 共有 AppDatabase)。
    let statsReading: any StatsReading = GRDBStatsRepository(database: .shared)

    /// 編集フィードのレコード解決の実装 (GRDB / 共有 AppDatabase)。
    let editFeedReading: any EditFeedReading = GRDBEditFeedRepository(database: .shared)

    /// DB メタ/診断読み取りの実装 (GRDB / 共有 AppDatabase)。
    let diagnosticsReading: any DiagnosticsReading = GRDBDiagnosticsRepository(database: .shared)

    /// マーク集合読み取りの実装 (GRDB / 共有 AppDatabase)。
    let markReading: any MarkReading = GRDBMarkRepository(database: .shared)

    /// カレンダーエントリ読み取りの実装 (GRDB / 共有 AppDatabase)。
    let calendarReading: any CalendarReading = GRDBCalendarRepository(database: .shared)

    /// 横断検索の実装 (GRDB / 共有 AppDatabase)。
    let globalSearchReading: any GlobalSearchReading = GRDBGlobalSearchRepository(database: .shared)

    // MARK: - 書き込み (編集/インポート系のローカル DB upsert)

    let eventWriting: any EventWriting = GRDBEventWriting(database: .shared)
    let showWriting: any ShowWriting = GRDBShowWriting(database: .shared)
    let idolWriting: any IdolWriting = GRDBIdolWriting(database: .shared)
    let songWriting: any SongWriting = GRDBSongWriting(database: .shared)
}
