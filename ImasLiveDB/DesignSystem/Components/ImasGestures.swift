import SwiftUI

// =============================================================================
// 指の操作 (docs/DESIGN_SYSTEM.md §1-6・§8.5)
//
// .imasSwipe(leading:trailing:)   行を引いて操作する。右に引く (先頭側) = 記録を付ける (参加・回収・予定)、
//                                 左に引く (末尾側) = 手元に置く (お気に入り・メモ・予想・削除)。
//                                 色と記号は操作の種類 (`ImasSwipeKind`) が決める。画面で tint を書かない。
// .imasTabSwipe(selection:options:) 中身を横に払ってタブを替える (`ImasTabs` と組む)。
//
// 長押しのメニューと中身の先見せは OS の `.contextMenu(menuItems:preview:)` をそのまま使う。
// =============================================================================

// MARK: - 行を引く

/// 行を引いたときに出る操作の種類。色と記号を決める。
enum ImasSwipeKind {
    /// 参加した (朱。判子を押す)。
    case attend
    /// 参加予定にする (墨。チケットを手に入れる)。
    case plan
    /// お気に入り (金)。
    case favorite
    /// メモ (灰)。
    case memo
    /// 予想に入れる (墨)。
    case predict
    /// 取り消す (薄い灰)。
    case undo
    /// 削除 (朱。OS の破壊的な操作として出す)。
    case delete

    var tint: Color {
        switch self {
        case .attend: return DS.stamp
        case .plan, .predict: return DS.sys
        case .favorite: return DS.favorite
        case .memo: return DS.ink2
        case .undo: return DS.ink3
        case .delete: return DS.danger
        }
    }

    var systemImage: String {
        switch self {
        case .attend: return "checkmark.seal.fill"
        case .plan: return "ticket.fill"
        case .favorite: return "star.fill"
        case .memo: return "note.text"
        case .predict: return "sparkles"
        case .undo: return "arrow.uturn.backward"
        case .delete: return "trash"
        }
    }
}

/// 行を引いたときの操作 1 つ。
struct ImasSwipeAction: Identifiable {
    let id: String
    let kind: ImasSwipeKind
    let title: String
    /// 記号を出すか。操作が 3 つ以上並ぶと幅が足りず記号だけが残って読めなくなるので、
    /// 選択肢を並べるとき (現地 / 配信 / LV) は文字だけにする。
    var showsIcon: Bool = true
    let action: () -> Void

    init(_ kind: ImasSwipeKind, title: String, id: String? = nil, showsIcon: Bool = true,
         action: @escaping () -> Void) {
        self.kind = kind
        self.title = title
        self.id = id ?? title
        self.showsIcon = showsIcon
        self.action = action
    }
}

extension View {
    /// 行を引いて操作する。List の行に付ける。
    /// - Parameters:
    ///   - leading: 右に引くと出る (記録を付ける)。1 つ目は引き切りで実行される。
    ///   - trailing: 左に引くと出る (手元に置く・削除)。
    func imasSwipe(leading: [ImasSwipeAction] = [], trailing: [ImasSwipeAction] = [],
                   allowsFullSwipe: Bool = true) -> some View {
        self
            .swipeActions(edge: .leading, allowsFullSwipe: allowsFullSwipe && leading.count == 1) {
                ForEach(leading) { item in swipeButton(item) }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe && trailing.count == 1) {
                ForEach(trailing) { item in swipeButton(item) }
            }
    }

    @ViewBuilder
    private func swipeButton(_ item: ImasSwipeAction) -> some View {
        Button(role: item.kind == .delete ? .destructive : nil, action: item.action) {
            if item.showsIcon {
                Label(item.title, systemImage: item.kind.systemImage)
            } else {
                Text(item.title)
            }
        }
        .tint(item.kind.tint)
    }
}

// MARK: - 横に払ってタブを替える

extension View {
    /// 中身を横に払って、`ImasTabs` の選択を隣へ移す。縦のスクロールは邪魔しない
    /// (横の動きが縦の倍以上あり、40pt 以上動いたときだけ替える)。
    func imasTabSwipe<Selection: Hashable>(selection: Binding<Selection>, options: [Selection]) -> some View {
        modifier(ImasTabSwipe(selection: selection, options: options))
    }
}

private struct ImasTabSwipe<Selection: Hashable>: ViewModifier {
    @Binding var selection: Selection
    let options: [Selection]

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 40, abs(dx) > abs(dy) * 2,
                          let index = options.firstIndex(of: selection) else { return }
                    let next = dx < 0 ? index + 1 : index - 1
                    guard options.indices.contains(next) else { return }
                    withAnimation(.imasStandard) { selection = options[next] }
                }
        )
    }
}
