import Foundation

/// ある公演/イベントで「実在した参加形態だけ」を出し分けるための解決ロジック。
/// 開催形態フラグは show 単位 + event フォールバック。
///
/// 方針:
/// - 現地 (.live): 常に選択可 (無観客配信のみの例外は別途 has_local を足す余地あり、現状は常時)。
/// - 配信 (.stream): デフォルト選択可。明示的に false のときだけ隠す (配信は一般的なため)。
/// - LV (.liveViewing): 明示的に true のときだけ出す (例外的形態なので opt-in)。
enum AttendanceAvailability {
    /// show 優先・event フォールバックで解決した Bool? を返す。
    private static func resolve(_ showValue: Bool?, _ eventValue: Bool?) -> Bool? {
        showValue ?? eventValue
    }

    static func options(show: Show?, event: Event?) -> [AttendanceType] {
        var opts: [AttendanceType] = [.live]

        let stream = resolve(show?.hasStreaming, event?.hasStreaming)
        if stream != false { opts.append(.stream) }   // 既定で許可、明示 false のみ非表示

        let lv = resolve(show?.hasLiveViewing, event?.hasLiveViewing)
        if lv == true { opts.append(.liveViewing) }    // 明示 true のみ

        return opts
    }
}
