import Foundation

/// 公演/イベントで提示する参加形態の選択肢。
///
/// 方針: 3形態 (現地 / 配信 / LV) を全ライブで常時提示する。
/// - フラグでフィルタしない理由: LV や配信の開催情報は欠落しやすく、出し漏れより
///   「過去にLV参加したのに記録できない」方が体験上のダメージが大きい。
///   3つ並んでいても誤選択は稀で、ユーザが自分の参加形態を選べる方が自由度が高い。
/// - shows/events の has_streaming / has_live_viewing 列はデータとしては残すが、
///   選択肢の出し分けには使わない (将来のフィルタや統計表示の余地として保持)。
enum AttendanceAvailability {
    static func options(show: Show?, event: Event?) -> [AttendanceType] {
        // 3形態を常に提示する。
        [.live, .stream, .liveViewing]
    }
}
