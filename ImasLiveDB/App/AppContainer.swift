import Foundation
import UIKit

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
    /// 起動時ロード / sync 完了後の再ロード / メモリ警告での破棄の配線は合成ルートの責務
    /// としてここ (init) で束ねる。
    let coreSnapshot: CoreSnapshotManager

    /// 楽曲マスタ読み取りの実装。
    /// スナップショットがロード済みなら共有コア (imas-core)、未ロード/ロード失敗時は
    /// 従来の GRDB 経路へ呼び出し単位でフォールバックする (曲スライス並走の原則)。
    let songReading: any SongReading

    private init() {
        let snapshot = CoreSnapshotManager()
        coreSnapshot = snapshot
        songReading = CoreSongRepository(snapshot: snapshot, fallback: GRDBSongRepository(database: .shared))

        // ローカル編集 (モデレーターの .applied 経路やセトリ取込) は CloudKit sync を通らず
        // GRDB へ直接 upsert されるため、.masterDataDidSync だけではスナップショットが
        // 再ロードされない。書き込み成功後に再ロードを促すデコレータで包んで配線する
        // (これが無いと自分の編集が次の sync かアプリ再起動まで core 経路の曲一覧/曲詳細に映らない)。
        let invalidate: @Sendable () -> Void = { snapshot.requestLoad() }
        eventWriting = SnapshotInvalidatingEventWriting(base: GRDBEventWriting(database: .shared), invalidate: invalidate)
        showWriting = SnapshotInvalidatingShowWriting(base: GRDBShowWriting(database: .shared), invalidate: invalidate)
        idolWriting = SnapshotInvalidatingIdolWriting(base: GRDBIdolWriting(database: .shared), invalidate: invalidate)
        songWriting = SnapshotInvalidatingSongWriting(base: GRDBSongWriting(database: .shared), invalidate: invalidate)

        // 起動時ロード。上のインライン初期化子群が AppDatabase.shared を先に初期化しており
        // (Bundle DB → Documents コピー含む)、この時点で master.sqlite は存在する。
        // 失敗しても未ロードのまま GRDB が答え続けるので起動は塞がない。
        snapshot.requestLoad()

        // CloudKit sync がローカルのマスタを書き換えたら読み直す (新スナップショットへ原子的に差し替え)。
        NotificationCenter.default.addObserver(forName: .masterDataDidSync, object: nil, queue: nil) { _ in
            snapshot.requestLoad()
        }
        // メモリ警告でスナップショットを手放す (以後は GRDB へフォールバック。
        // 次の sync 完了 or アプリ再起動の requestLoad で復帰する)。
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in
            snapshot.unload()
        }
    }

    /// 「みんなの投票」のユースケース実装 (Worker D1 集計 API)。
    let communityVoting: any CommunityVoting = CommunityAPI.shared

    /// コミュニティタグ (曲/アイドル/ユニット) の読み取り実装 (Worker D1 集計 API)。
    let communityTagReading: any CommunityTagReading = CommunityAPI.shared

    /// コミュニティタグ (曲/アイドル/ユニット) の書き込み実装 (Worker D1 集計 API)。
    let communityTagWriting: any CommunityTagWriting = CommunityAPI.shared

    /// イベント (ライブ/公演) マスタ読み取りの実装 (GRDB / 共有 AppDatabase)。
    let eventReading: any EventReading = GRDBEventRepository(database: .shared)

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
    // スナップショットが読むマスタ表に触るため、init で SnapshotInvalidating* デコレータに
    // 包んで組み立てる (書き込み成功後に共有コアの再ロードを促す。配線は init 参照)。

    let eventWriting: any EventWriting
    let showWriting: any ShowWriting
    let idolWriting: any IdolWriting
    let songWriting: any SongWriting
}
