import SwiftUI

/// 参加 / お気に入り / メモ / 座席 のマーキングバー。
/// 見た目は DesignSystem の `ImasMarkBar` (1 本の帯) + `ImasMarkTile` (ON は記号が実体の色で点く)。
struct UserMarkBar: View {
    let entity: UserMarkEntity
    let entityId: String
    let kinds: [UserMarkKind]
    /// テーマ色シード (公演/ライブのブランド色など)。ON 状態の発色に使う。
    var seed: String? = nil
    var brand: String? = nil
    /// `.attended` セルのタップを差し替える (イベントでは公演選択シートを開くため)。
    /// 指定時は通常のトグルではなく onAttendedTap を呼び、ON 状態は attendedIsOn で決める。
    var onAttendedTap: (() -> Void)? = nil
    var attendedIsOn: Bool = false

    @Environment(\.colorScheme) private var scheme
    @State private var showingNote = false
    @State private var noteDraft = ""
    @State private var showingSeat = false
    @State private var seatDraft = ""

    private let markService = UserMarkService.shared

    /// 座席は「参加」済みの公演でのみ意味があるので attended の時だけ出す。
    private var visibleKinds: [UserMarkKind] {
        kinds.filter { kind in
            kind != .seat || markService.bool(.attended, entity: entity, id: entityId)
        }
    }

    @Environment(\.imasTheme) private var envTheme

    var body: some View {
        // seed / brand を渡されたらその色、無ければ画面の実体色 (`.imasTheme`) を使う。
        let t = (seed != nil || brand != nil) ? ImasTheme.derive(seed: seed, brand: brand, scheme: scheme) : envTheme
        ImasMarkBar {
            ForEach(visibleKinds, id: \.self) { kind in
                cell(for: kind, theme: t)
            }
        }
        .environment(\.imasTheme, t)
        .sheet(isPresented: $showingNote) {
            NoteEditorSheet(entity: entity, entityId: entityId, draft: $noteDraft)
        }
        .sheet(isPresented: $showingSeat) {
            SeatEditorSheet(entity: entity, entityId: entityId, draft: $seatDraft)
        }
    }

    @ViewBuilder
    private func cell(for kind: UserMarkKind, theme t: ImasTheme) -> some View {
        switch kind {
        case .note:
            let hasNote = !(markService.note(entity: entity, id: entityId) ?? "").isEmpty
            markCell(
                icon: hasNote ? "note.text.badge.plus" : "note.text",
                label: "メモ", isOn: hasNote, theme: t,
                a11y: hasNote ? "メモあり" : "メモ"
            ) {
                noteDraft = markService.note(entity: entity, id: entityId) ?? ""
                showingNote = true
            }
        case .seat:
            let seat = markService.seat(entity: entity, id: entityId) ?? ""
            let hasSeat = !seat.isEmpty
            markCell(
                icon: hasSeat ? UserMarkKind.seat.activeIcon : UserMarkKind.seat.icon,
                label: "座席", isOn: hasSeat, theme: t,
                a11y: hasSeat ? "座席: \(seat)" : "座席を記録"
            ) {
                seatDraft = seat
                showingSeat = true
            }
        case .attended where onAttendedTap != nil:
            // イベント用: タップで公演選択シートを開く (公演単位で参加管理)。ON は派生状態。
            markCell(
                icon: attendedIsOn ? UserMarkKind.attended.activeIcon : UserMarkKind.attended.icon,
                label: UserMarkKind.attended.label, isOn: attendedIsOn, theme: t,
                a11y: attendedIsOn ? "参加した公演を編集" : "参加した公演を選ぶ"
            ) {
                onAttendedTap?()
            }
        default:
            let isOn = markService.bool(kind, entity: entity, id: entityId)
            markCell(
                icon: isOn ? kind.activeIcon : kind.icon,
                label: kind.label, isOn: isOn, theme: t, a11y: kind.label
            ) {
                do {
                    try markService.toggle(kind, entity: entity, id: entityId)
                } catch {
                    LocalWriteFailure.report(error, action: "\(kind.label)の切り替え")
                }
            }
        }
    }

    /// 印のタイル 1 つ (見た目は DesignSystem の `ImasMarkTile`)。
    private func markCell(icon: String, label: String, isOn: Bool, theme t: ImasTheme, a11y: String, action: @escaping () -> Void) -> some View {
        ImasMarkTile(systemImage: icon, label: label, isOn: isOn, accessibilityText: a11y, action: action)
    }
}
