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

    /// 共有コア (imas-core) のインメモリスナップショット供給。
    /// 起動時ロード / sync 完了後の再ロードの配線は合成ルートの責務としてここ (init) で束ねる。
    let coreSnapshot: CoreSnapshotManager

    // マスタ読み取りの実装群。
    // どれも共有コア (imas-core) のスナップショットが答える。まだロードできていなければ
    // ロードを待つ (OS 側の SQL へ落とす経路は持たない)。
    // CoreSnapshotManager を注入する必要があるので、これらだけ init で組み立てる。

    /// 楽曲マスタ読み取りの実装。
    let songReading: any SongReading
    let nowPlayingReading: any NowPlayingReading

    /// アイドル(キャスト)マスタ読み取りの実装。
    let idolReading: any IdolReading

    /// ブランドマスタ読み取りの実装。
    let brandReading: any BrandReading

    /// ユニットマスタ読み取りの実装。
    let unitReading: any UnitReading

    /// イベント (ライブ/公演) マスタ読み取りの実装。
    let eventReading: any EventReading

    /// 公演 (Show) / セットリスト読み取りの実装。
    let showReading: any ShowReading

    /// カレンダーエントリ読み取りの実装。
    let calendarReading: any CalendarReading

    /// 統計 (ランキング/集計) 読み取りの実装。
    let statsReading: any StatsReading

    /// 年表 (ブランド史) 読み取りの実装。
    let timelineReading: any TimelineReading

    /// 横断検索の実装。
    let globalSearchReading: any GlobalSearchReading

    /// 披露実績の集計 (共起曲 / 歌唱者) 読み取りの実装。
    let performanceEvidenceReading: any PerformanceEvidenceReading

    /// セトリの機械予測の読み取りの実装。
    let setlistForecastReading: any SetlistForecastReading

    /// セトリ当てクイズの出題の実装。
    let setlistQuizReading: any SetlistQuizReading

    private init() {
        let snapshot = CoreSnapshotManager()
        coreSnapshot = snapshot
        songReading = CoreSongRepository(snapshot: snapshot, database: .shared)
        nowPlayingReading = CoreNowPlayingRepository(snapshot: snapshot)
        idolReading = CoreIdolRepository(snapshot: snapshot)
        brandReading = CoreBrandRepository(snapshot: snapshot)
        unitReading = CoreUnitRepository(snapshot: snapshot)
        eventReading = CoreEventRepository(snapshot: snapshot, database: .shared)
        showReading = CoreShowRepository(snapshot: snapshot, database: .shared)
        calendarReading = CoreCalendarRepository(snapshot: snapshot, database: .shared)
        statsReading = CoreStatsRepository(snapshot: snapshot)
        timelineReading = CoreTimelineRepository(snapshot: snapshot)
        globalSearchReading = CoreGlobalSearchRepository(snapshot: snapshot)
        performanceEvidenceReading = CorePerformanceEvidenceRepository(snapshot: snapshot)
        setlistForecastReading = CoreSetlistForecastRepository(snapshot: snapshot)
        setlistQuizReading = CoreSetlistQuizRepository(snapshot: snapshot)
        editFeedReading = GRDBEditFeedRepository(database: .shared, snapshot: snapshot)

        // ローカル編集 (モデレーターの .applied 経路やセトリ取込) は CloudKit sync を通らず
        // GRDB へ直接 upsert されるため、.masterDataDidSync だけではスナップショットが
        // 再ロードされない。書き込み成功後に再ロードを促すデコレータで包んで配線する
        // (これが無いと自分の編集が次の sync かアプリ再起動まで core 経路の曲一覧/曲詳細に映らない)。
        let invalidate: @Sendable () -> Void = { snapshot.requestLoad() }
        eventWriting = SnapshotInvalidatingEventWriting(base: GRDBEventWriting(database: .shared), invalidate: invalidate)
        showWriting = SnapshotInvalidatingShowWriting(base: GRDBShowWriting(database: .shared), invalidate: invalidate)
        idolWriting = SnapshotInvalidatingIdolWriting(base: GRDBIdolWriting(database: .shared), invalidate: invalidate)
        songWriting = SnapshotInvalidatingSongWriting(base: GRDBSongWriting(database: .shared), invalidate: invalidate)

        // 起動時ロード。上の `.shared` 参照が DB を開き終えている (Bundle DB → Documents コピー含む)
        // ので、この時点で master.sqlite は存在する。ロードが終わるまでの読み取りは、ロードを待つ。
        snapshot.requestLoad()

        // CloudKit sync がローカルのマスタを書き換えたら読み直す (新スナップショットへ原子的に差し替え)。
        NotificationCenter.default.addObserver(forName: .masterDataDidSync, object: nil, queue: nil) { _ in
            snapshot.requestLoad()
        }
    }

    /// セトリ予想への投票の実装 (Worker D1 集計 API)。
    let setlistPredictionVoting: any SetlistPredictionVoting = PredictionServiceVoting()

    /// 「みんなの投票」のユースケース実装 (Worker D1 集計 API)。
    let communityVoting: any CommunityVoting = CommunityAPI.shared

    /// コミュニティタグ (曲/アイドル/ユニット) の読み取り実装 (Worker D1 集計 API)。
    let communityTagReading: any CommunityTagReading = CommunityAPI.shared

    /// コミュニティタグ (曲/アイドル/ユニット) の書き込み実装 (Worker D1 集計 API)。
    let communityTagWriting: any CommunityTagWriting = CommunityAPI.shared

    /// 編集フィードのレコード解決の実装 (共有コア + 参考動画だけ GRDB)。
    let editFeedReading: any EditFeedReading

    /// DB メタ/診断読み取りの実装 (GRDB / 共有 AppDatabase)。
    let diagnosticsReading: any DiagnosticsReading = GRDBDiagnosticsRepository(database: .shared)

    /// マーク集合読み取りの実装 (GRDB / 共有 AppDatabase)。
    let markReading: any MarkReading = GRDBMarkRepository(database: .shared)

    /// 家計簿 (端末にだけある支出) の読み書きの実装 (GRDB / 共有 AppDatabase)。
    let ledgerReading: any LedgerReading = GRDBLedgerRepository(database: .shared)
    let ledgerWriting: any LedgerWriting = GRDBLedgerRepository(database: .shared)

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

    /// 歌詞クイズの出題母集団と 1 曲ぶんの歌詞の読み取り実装。
    /// ⚠️ 歌詞を含むので、ディスクキャッシュ無しの経路 (LyricsAPI) を通す。
    /// DEBUG かつ `FAKE_LYRICS=1` のときはダミー歌詞で遊べるフェイク。
    let lyricsQuizReading: any LyricsQuizReading = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FAKE_LYRICS"] == "1" {
            return FakeLyricsQuizReading()
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

    /// コールガイドの整備状況 (一覧 / 最近の編集 / 未整備) の読み取り実装。
    /// 認証不要・エッジキャッシュ前提の口で、**歌詞本文もコール本文も通らない**
    /// (通るのは曲 id と件数・日時・マスク済み表示名だけ)。
    /// DEBUG かつ `FAKE_LYRICS=1` のときは、Worker 未デプロイでも画面を確認できるフェイク。
    let callGuideDashboardReading: any CallGuideDashboardReading = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FAKE_LYRICS"] == "1" {
            return FakeCallGuideDashboardReading()
        }
        #endif
        return CallGuideAPI.shared
    }()

    // MARK: - 書き込み (編集/インポート系のローカル DB upsert)
    // スナップショットが読むマスタ表に触るため、init で SnapshotInvalidating* デコレータに
    // 包んで組み立てる (書き込み成功後に共有コアの再ロードを促す。配線は init 参照)。

    let eventWriting: any EventWriting
    let showWriting: any ShowWriting
    let idolWriting: any IdolWriting
    let songWriting: any SongWriting
}
