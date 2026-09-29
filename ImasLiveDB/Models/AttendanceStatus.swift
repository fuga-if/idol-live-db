import Foundation

/// 参加マークから導く「参加予定 (あとN日) / 参加済み」の札。
///
/// 決め方 (公演単位のマークを優先・無ければイベント単位のマークで全公演の日付を見る・
/// 年や月だけの日付は日数なしの「参加予定」) と文言はコア (`AttendanceStatusRecord`)。
/// ここは画面の見た目 (SF Symbol) を足すだけ。
struct AttendanceStatus: Equatable {
    let state: AttendanceState
    let label: String

    static let none = AttendanceStatus(state: .none, label: "")

    init(state: AttendanceState, label: String) {
        self.state = state
        self.label = label
    }

    init(_ record: AttendanceStatusRecord) {
        self.init(state: record.state, label: record.label)
    }

    /// 参加マークが1つでも付いているか。
    var isMarked: Bool { state != .none }

    /// 予定中（未来公演あり）か。
    var isPlanned: Bool { state == .planned }

    /// SF Symbol。
    var systemImage: String {
        switch state {
        case .none: "circle"
        case .planned: "calendar.badge.clock"
        case .attended: "checkmark.seal.fill"
        }
    }
}
