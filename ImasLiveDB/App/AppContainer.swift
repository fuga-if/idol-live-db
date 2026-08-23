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

    /// コミュニティタグ (曲/アイドル/ユニット) の読み取り実装 (Worker D1 集計 API)。
    let communityTagReading: any CommunityTagReading = CommunityAPI.shared

    /// コミュニティタグ (曲/アイドル/ユニット) の書き込み実装 (Worker D1 集計 API)。
    let communityTagWriting: any CommunityTagWriting = CommunityAPI.shared

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

    /// 年表 (ブランド史) 読み取りの実装 (GRDB / 共有 AppDatabase)。
    let timelineReading: any TimelineReading = GRDBTimelineRepository(database: .shared)

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

    /// 曲詳細のサーバ側データ (タグ / 類似曲 / ペンライト / 歌詞) 読み取りの実装。
    /// 束ねエンドポイント 1 本で取り、未配信 Worker では旧個別エンドポイントに落ちる。
    /// ⚠️ 歌詞を含むため JASRAC 許諾の条件によりディスクへは一切書けない。
    /// 永続化アダプタ (キャッシュ含む) を差し込まないこと。
    /// DEBUG かつ `FAKE_LYRICS=1` のときだけ、サーバ未完成でも見た目を確認できるフェイクに差し替える。
    let songDetailReading: any SongDetailReading = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FAKE_LYRICS"] == "1" {
            return FakeLyricsSongDetailReading()
        }
        #endif
        return SongDetailAPI.shared
    }()

    /// 歌詞本文の横断検索の実装。
    /// ⚠️ 曲を跨ぐ唯一の歌詞経路なので、こちらもディスクキャッシュ無しの経路 (LyricsAPI) を通す。
    /// DEBUG かつ `FAKE_LYRICS=1` のときは、ログイン無しで一覧の見た目を確認できるフェイク。
    let lyricsSearchReading: any LyricsSearchReading = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FAKE_LYRICS"] == "1" {
            return FakeLyricsSearchReading()
        }
        #endif
        return LyricsAPI.shared
    }()

    /// コールガイド (歌詞行に紐づくコール / 手拍子指示) の書き込み実装。
    /// ⚠️ 歌詞の断片が乗るので、こちらもディスクキャッシュ無しの経路を通す。
    /// DEBUG かつ `FAKE_LYRICS=1` のときは、サーバ未実装でも編集動線を確認できるフェイク。
    let callGuideWriting: any CallGuideWriting = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FAKE_LYRICS"] == "1" {
            return FakeCallGuideWriting()
        }
        #endif
        return CallGuideAPI.shared
    }()

    // MARK: - 書き込み (編集/インポート系のローカル DB upsert)

    let eventWriting: any EventWriting = GRDBEventWriting(database: .shared)
    let showWriting: any ShowWriting = GRDBShowWriting(database: .shared)
    let idolWriting: any IdolWriting = GRDBIdolWriting(database: .shared)
    let songWriting: any SongWriting = GRDBSongWriting(database: .shared)
}
