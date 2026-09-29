import SwiftUI

/// 公演 (Show) 1 件の行をスワイプすると出る参加登録アクション。
///
/// 選択肢と「取り消す」の出し分けは、SetlistView の参加確認ダイアログ
/// (`AttendanceAvailability.options` + `UserMarkService.shared.attendance` != nil) と
/// **全く同じ規則**をスワイプ版として呼ぶだけにしている。ここで新しい判定を書き足すと、
/// ダイアログ版とスワイプ版で規則が二重管理になり、どちらかだけ直る事故のもとになる。
struct AttendanceSwipeActions: ViewModifier {
    let show: Show
    /// 開催形態フォールバック元 (show に未設定の配信/LV 有無を event から継承)。
    var event: Event? = nil
    /// 変更後に呼ぶ (呼び出し側で派生状態を再計算するため。例: EventDetailView の参加チップ)。
    var onChange: () -> Void = {}

    private var marks: UserMarkService { UserMarkService.shared }

    func body(content: Content) -> some View {
        // 一覧行数は公演単位 (多くて数十件) なので、行ごとに現在値を読んでも
        // 習熟度一覧 (数千曲) のような再評価コストにはならない。
        let current = marks.attendance(entity: .show, id: show.id)
        return content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                ForEach(AttendanceAvailability.options(show: show, event: event), id: \.self) { type in
                    Button {
                        AppAnalytics.tap("attendance_swipe.set_\(type.rawValue)")
                        set(type)
                    } label: {
                        // ⚠️ ラベルは**文字だけ**。`Label(_, systemImage:)` にすると
                        // 幅が足りないときにアイコンだけが残り、どれを押すのか読めなくなる
                        // (現地/配信/LV + 取消の 4 つで実機の幅を超える)。
                        Text(type.label)
                    }
                    .tint(current == type ? DS.ink3 : UserMarkKind.attended.tint)
                }
                if current != nil {
                    Button(role: .destructive) {
                        AppAnalytics.tap("attendance_swipe.cancel")
                        set(nil)
                    } label: {
                        Text("取消")
                    }
                }
            }
    }

    private func set(_ type: AttendanceType?) {
        do {
            try marks.setAttendance(entity: .show, id: show.id, type: type)
        } catch {
            LocalWriteFailure.report(error, action: "参加の記録")
        }
        onChange()
    }
}

extension View {
    /// 公演の行に参加登録のスワイプアクションを付ける。
    func attendanceSwipe(show: Show, event: Event? = nil, onChange: @escaping () -> Void = {}) -> some View {
        modifier(AttendanceSwipeActions(show: show, event: event, onChange: onChange))
    }
}

/// イベント (Event) の行をスワイプすると出る参加登録アクション。
///
/// イベントは公演 (show) を複数束ねることがあり、参加は show 単位でしか保存できない。
/// 「1 公演だけなら直接登録」のような出し分けをここで新設すると、EventAttendanceSheet が
/// 既に持つ「公演ごとに選ぶ / 全公演に現地参加」の規則と二重管理になる。
/// そのため公演数によらず、常に同じ EventAttendanceSheet (EventDetailView と共有) を開く。
struct EventAttendanceSwipeActions: ViewModifier {
    let event: Event
    var seed: String? = nil
    var brand: String? = nil

    @State private var shows: [Show] = []
    @State private var showSheet = false

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    AppAnalytics.tap("attendance_swipe.open_event_sheet")
                    Task {
                        shows = (try? await AppContainer.shared.showReading.shows(eventId: event.id)) ?? []
                        showSheet = true
                    }
                } label: {
                    Label("参加を登録", systemImage: UserMarkKind.attended.icon)
                }
                .tint(UserMarkKind.attended.tint)
            }
            .sheet(isPresented: $showSheet) {
                EventAttendanceSheet(shows: shows, event: event, seed: seed, brand: brand) {}
            }
    }
}

extension View {
    /// イベントの行に参加登録のスワイプアクションを付ける (公演選択シートを開く)。
    func eventAttendanceSwipe(event: Event, seed: String? = nil, brand: String? = nil) -> some View {
        modifier(EventAttendanceSwipeActions(event: event, seed: seed, brand: brand))
    }
}
