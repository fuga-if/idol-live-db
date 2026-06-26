import SwiftUI

/// 画面遷移の二重発火ガード。
///
/// 重い画面でタップの反応が遅れた時に、同じ/連続したタップで遷移が二重に積まれる
/// (二重 push・二重 present) のを防ぐ、時間ベースのスロットル。
///
/// 使い方:
/// - `if NavThrottle.allow() { destination = ... }` … sheet/明示遷移トリガ(プログラム的 append 等)を直接ガード。
///
/// ⚠️ かつて `NavigationStack(path: $path.navThrottled())` で path のミューテーションを
/// 握り潰す拡張があったが、SwiftUI は path 書き込みの拒否を受け付けず内部スタックと desync し、
/// スタックを root まで pop させる不具合 (例: 投票一覧→詳細でタブ root に戻る) を起こすため撤去した。
/// 遷移ガードは必ず「トリガ側 (`allow()`)」で行い、path Binding には介入しないこと。
enum NavThrottle {
    // 遷移は常にメインスレッド上でのみ発火するため、スレッド安全性は実質保証される。
    nonisolated(unsafe) private static var lastFired = Date.distantPast

    /// 直近の遷移から `window` 秒未満なら `false` を返してタップを握り潰す。
    /// 「戻る → すぐ別の行をタップ」程度は許容したいので既定は短め。
    @discardableResult
    static func allow(window: TimeInterval = 0.5) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastFired) >= window else { return false }
        lastFired = now
        return true
    }
}

