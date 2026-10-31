import SwiftUI

/// 参加した公演から、P履歴書の「思い出の公演」に載せる公演を選ぶ画面 (push で開く)。
/// 保存先は呼び出し側に任せる (`onChange` に選び直した P名刺の画像の選択を渡す)。
///
/// 上は載せる公演 (選んだ順。引いて並べ替え、左に引くと外す)、下は参加した公演すべて (新しい順。
/// 押すと載せる / 外す)。公演は何百にもなるので公演名・会場で絞る (照合はコアの `TextSearchCatalog`)。
/// 上限・まだ選んでいないときの既定 (お気に入りのライブの公演)・並べ替えはコア
/// (`profileMemoryPicks` / `profileToggleMemory` / `profileMoveMemory`)。
struct MemoryShowPickerView: View {
    let record: ProfileSheetRecord
    let onChange: (ProfileSheet) -> Void

    @State private var sheet: ProfileSheet
    @State private var catalog: TextSearchCatalog?
    @State private var query = ""

    init(sheet: ProfileSheet, record: ProfileSheetRecord, onChange: @escaping (ProfileSheet) -> Void) {
        self.record = record
        self.onChange = onChange
        _sheet = State(initialValue: sheet)
    }

    var body: some View {
        let picks = profileMemoryPicks(sheet: sheet, record: record)
        let pickedIds = Set(picks.picked.map(\.showId))
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let candidates = trimmed.isEmpty
            ? picks.candidates
            : (catalog?.filter(picks.candidates, needle: trimmed) ?? picks.candidates)
        List {
            if trimmed.isEmpty {
                ImasListSection("載せる公演", count: "\(picks.picked.count) / \(picks.max)",
                                footer: picks.chosenByHand
                                    ? "載せる順に並びます。引いて並べ替え、左に引くと外します。"
                                    : "まだ選んでいないので、お気に入りに付けたライブの公演を新しい順に載せています。選び直すとその順になります。") {
                    if picks.picked.isEmpty {
                        Text("下の参加した公演から選んでください。")
                            .imasText(.note)
                    }
                    ForEach(picks.picked, id: \.showId) { show in
                        row(show)
                            .imasSwipe(trailing: [ImasSwipeAction(.delete, title: "外す") { toggle(show.showId) }])
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        // List の行き先は「この位置の前に入れる」なので、後ろへ動かすときは 1 つ詰める。
                        let target = to > f ? to - 1 : to
                        set(profileMoveMemory(sheet: sheet, record: record, from: UInt32(f), to: UInt32(target)))
                    }
                }
            }
            ImasListSection("参加した公演", count: "\(candidates.count)公演",
                            footer: picks.full ? "載せられるのは \(picks.max) 公演までです。足すときは先にどれかを外してください。" : nil) {
                ForEach(candidates, id: \.showId) { show in
                    let isPicked = pickedIds.contains(show.showId)
                    let locked = picks.full && !isPicked
                    ImasSelectableRow(title: show.title, subtitle: subtitle(show), isSelected: isPicked,
                                      isDisabled: locked) {
                        toggle(show.showId)
                    }
                }
            }
        }
        .imasForm()
        .searchable(text: $query, prompt: "公演名・会場で検索")
        .navigationTitle("思い出の公演")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard catalog == nil else { return }
            catalog = TextSearchCatalog(fieldsPerItem: picks.candidates.map { [$0.title, $0.venue ?? ""] })
        }
        .trackScreen("memory_show_picker")
    }

    private func row(_ show: ProfileShowInput) -> some View {
        ImasRow(title: show.title, subtitle: subtitle(show), density: .compact)
    }

    private func subtitle(_ show: ProfileShowInput) -> String {
        [show.date.replacingOccurrences(of: "-", with: "."), show.venue].compactMap { $0 }.joined(separator: " · ")
    }

    private func toggle(_ showId: String) {
        AppAnalytics.tap("memory_show_picker.toggle")
        set(profileToggleMemory(sheet: sheet, record: record, showId: showId))
    }

    private func set(_ next: ProfileSheet) {
        guard next != sheet else { return }
        sheet = next
        onChange(next)
    }
}
