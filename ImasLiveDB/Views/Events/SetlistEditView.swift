import os
import SwiftUI

/// セトリ編集 UI。ログイン済みユーザーが利用可能。
/// - 行のドラッグで順序入替
/// - swipe で削除
/// - 行内の「曲」セルで楽曲差替え、「出演」セルでアイドル多選択
/// - 「保存」で `POST /edits` 経由 CloudKit に反映 + ローカル DB を完全置換
///
/// 契約 v2:
/// - SetlistItem recordName は位置非依存 (`sli_<uuid>`)。position はフィールド。既存行は元 ID を維持。
/// - 削除は soft delete (op=delete を送るとサーバが deletedAt+modifiedAt を注入)。
/// - 出演者 (SetlistPerformer) も差分で soft delete する。recordName は決定論的
///   (`setlist_performers-<itemId>-<idolId>`) なので追加/削除を完全復元できる
///   → RedTeam Critical (外したはずの出演者が他端末で復活) を防ぐ。
struct SetlistEditView: View {
    let show: Show

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [EditableSetlistRow] = []
    /// 編集前の SetlistItem id 集合 (削除差分の算出に使う)。
    @State private var initialItemIds: [String] = []
    /// 編集前の SetlistItem 行 (id → row)。フォームに無いフィールド (notes / unitName) を
    /// ローカル楽観更新で nil 上書きしないための引き継ぎ元 + section クリアの判定に使う。
    @State private var originalItems: [String: SetlistRow] = [:]
    /// 編集前の SetlistPerformer recordName 集合 (出演者削除差分の算出に使う)。
    @State private var initialPerformerNames: Set<String> = []
    @State private var allIdols: [Idol] = []
    @State private var idolById: [String: Idol] = [:]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showClearConfirm = false

    @State private var songPickerForRowId: PickerSheetRowId?
    @State private var castPickerForRowId: PickerSheetRowId?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("セトリ編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            AppAnalytics.tap("setlist_edit.save")
                            // 既存セトリがあったのに 0 行で保存しようとした時は確認。
                            // 意図的な全削除 / 投稿前のリセットは許可するが誤操作を防ぐ。
                            if rows.isEmpty && !initialItemIds.isEmpty {
                                showClearConfirm = true
                            } else {
                                Task { await save() }
                            }
                        }
                        .disabled(isSaving)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton().disabled(isSaving)
                    }
                }
                .overlay {
                    if isSaving {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView("保存中…")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .alert("エラー", isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage ?? "")
                }
                .alert("セトリを全削除しますか?", isPresented: $showClearConfirm) {
                    Button("削除する", role: .destructive) {
                        Task { await save() }
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("この公演のセトリ \(initialItemIds.count) 件をすべて削除します。 この操作は取り消せません。")
                }
                .sheet(item: $songPickerForRowId) { wrapper in
                    SongPickerView { song in
                        if let idx = rows.firstIndex(where: { $0.id == wrapper.id }) {
                            rows[idx].songId = song.id
                            rows[idx].songTitle = song.title
                        }
                        songPickerForRowId = nil
                    }
                    .environment(database)
                }
                .sheet(item: $castPickerForRowId) { wrapper in
                    if let idx = rows.firstIndex(where: { $0.id == wrapper.id }) {
                        IdolMultiPickerView(
                            selected: rows[idx].castIds,
                            idols: allIdols
                        ) { newSelection in
                            rows[idx].castIds = newSelection
                            castPickerForRowId = nil
                        }
                    }
                }
                .task { await load() }
                .trackScreen("setlist_edit")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
        } else {
            List {
                ForEach($rows) { $row in
                    SetlistEditRow(
                        row: $row,
                        idolById: idolById,
                        onPickSong: { songPickerForRowId = PickerSheetRowId(id: row.id) },
                        onPickCasts: { castPickerForRowId = PickerSheetRowId(id: row.id) }
                    )
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
                .onMove { from, to in
                    rows.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    rows.remove(atOffsets: offsets)
                }

                Section {
                    Button {
                        AppAnalytics.tap("setlist_edit.add_song")
                        let newRow = EditableSetlistRow(
                            songId: "",
                            songTitle: "(曲を選択)",
                            section: nil,
                            castIds: []
                        )
                        rows.append(newRow)
                        songPickerForRowId = PickerSheetRowId(id: newRow.id)
                    } label: {
                        Label("曲を追加", systemImage: "plus.circle.fill")
                    }
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
        }
    }

    // MARK: - Load

    private func load() async {
        do {
            let setlist = try await AppContainer.shared.showReading.setlist(showId: show.id)
            let performers = try await AppContainer.shared.showReading.allPerformers(showId: show.id)
            initialItemIds = setlist.map(\.id)
            originalItems = Dictionary(uniqueKeysWithValues: setlist.map { ($0.id, $0) })
            var performerNames = Set<String>()
            rows = setlist.map { item in
                let castIds = Set((performers[item.id] ?? []).map { $0.id })
                for idolId in castIds {
                    performerNames.insert(Self.performerRecordName(itemId: item.id, idolId: idolId))
                }
                return EditableSetlistRow(
                    existingItemId: item.id,
                    songId: item.songId,
                    songTitle: item.songTitle,
                    section: item.section,
                    castIds: castIds
                )
            }
            initialPerformerNames = performerNames
            allIdols = try await AppContainer.shared.idolReading.allIdolsForPicker()
            idolById = Dictionary(uniqueKeysWithValues: allIdols.map { ($0.id, $0) })
            isLoading = false
        } catch {
            errorMessage = "セトリ読み込み失敗: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // 1. 検証
        for (i, row) in rows.enumerated() {
            if row.songId.isEmpty {
                errorMessage = "\(i + 1) 行目: 曲が未選択"
                return
            }
        }

        // 2. 新しい SetlistItem を構築。既存行は元 ID を維持 (位置非依存)、新規行は sli_<uuid>。
        //    フォームに無いフィールド (notes / unitName) は元レコードから引き継ぐ
        //    (nil で構築すると replaceSetlist のローカル全置換で消えてしまう)。
        let newItems: [SetlistItem] = rows.enumerated().map { idx, row in
            let position = idx + 1
            let itemId = row.existingItemId ?? "sli_\(UUID().uuidString.lowercased())"
            let original = row.existingItemId.flatMap { originalItems[$0] }
            return SetlistItem(
                id: itemId,
                showId: show.id,
                songId: row.songId,
                position: position,
                section: row.section,
                notes: original?.notes,
                unitName: original?.unitName
            )
        }
        var newPerformers: [SetlistPerformer] = []
        for (idx, row) in rows.enumerated() {
            let itemId = newItems[idx].id
            for idolId in row.castIds {
                newPerformers.append(SetlistPerformer(setlistItemId: itemId, idolId: idolId))
            }
        }

        // 3. 削除差分 (soft delete 対象)。
        let newItemIds = Set(newItems.map(\.id))
        let deletedItemNames = initialItemIds.filter { !newItemIds.contains($0) }

        let newPerformerNames = Set(newPerformers.map {
            Self.performerRecordName(itemId: $0.setlistItemId, idolId: $0.idolId)
        })
        let deletedPerformerNames = initialPerformerNames.subtracting(newPerformerNames)

        do {
            try await pushViaServer(
                items: newItems,
                performers: newPerformers,
                deletedItemNames: deletedItemNames,
                deletedPerformerNames: Array(deletedPerformerNames)
            )
            try await AppContainer.shared.showWriting.replaceSetlist(showId: show.id, items: newItems, performers: newPerformers)
            Logger.database.notice("setlist_edit_saved show=\(show.id, privacy: .public) items=\(newItems.count) performers=\(newPerformers.count) delItems=\(deletedItemNames.count) delPerf=\(deletedPerformerNames.count)")
            dismiss()
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
        }
    }

    private func pushViaServer(
        items: [SetlistItem],
        performers: [SetlistPerformer],
        deletedItemNames: [String],
        deletedPerformerNames: [String]
    ) async throws {
        var ops: [EditService.EditOperation] = []

        // 既存行は update、新規行 (existingItemId が無いので id が sli_<uuid>) は create。
        let existingIds = Set(initialItemIds)
        for item in items {
            var fields: [String: AnyEncodable] = [
                "showId": AnyEncodable(item.showId),
                "songId": AnyEncodable(item.songId),
                "position": AnyEncodable(item.position),
            ]
            if let section = item.section {
                fields["section"] = AnyEncodable(section)
            } else if originalItems[item.id]?.section != nil {
                // 「本編」に戻した = section のクリア。update はサーバ側マージ (未送信 = 現状維持)
                // なので null を明示送信して削除と解釈させる。
                fields["section"] = .null
            }
            ops.append(EditService.EditOperation(
                op: existingIds.contains(item.id) ? .update : .create,
                recordType: "SetlistItem",
                recordName: item.id,
                fields: fields
            ))
        }

        for performer in performers {
            let recordName = Self.performerRecordName(itemId: performer.setlistItemId, idolId: performer.idolId)
            // 既存出演者は update、新規は create (recordName 決定論的なので冪等)。
            let op: EditService.EditOp = initialPerformerNames.contains(recordName) ? .update : .create
            ops.append(EditService.EditOperation(
                op: op,
                recordType: "SetlistPerformer",
                recordName: recordName,
                fields: [
                    "setlistItemId": AnyEncodable(performer.setlistItemId),
                    "idolId": AnyEncodable(performer.idolId),
                ]
            ))
        }

        // 削除: SetlistItem / SetlistPerformer を soft delete (op=delete)。サーバが deletedAt を注入。
        for name in deletedItemNames {
            ops.append(EditService.EditOperation(op: .delete, recordType: "SetlistItem", recordName: name))
        }
        for name in deletedPerformerNames {
            ops.append(EditService.EditOperation(op: .delete, recordType: "SetlistPerformer", recordName: name))
        }

        _ = try await EditService.shared.submit(ops: ops, summary: "セトリ編集")
    }

    /// SetlistPerformer の決定論的 recordName。seed / CKRecordMapper と同じ規約。
    static func performerRecordName(itemId: String, idolId: String) -> String {
        "setlist_performers-\(itemId)-\(idolId)"
    }
}

// MARK: - Editable row model

struct EditableSetlistRow: Identifiable {
    let id = UUID()
    var existingItemId: String?
    var songId: String
    var songTitle: String
    var section: String?
    var castIds: Set<String>
}

/// Sheet の `item:` バインディング用に UUID をそのまま渡せる薄いラッパ。
struct PickerSheetRowId: Identifiable, Equatable {
    let id: UUID
}

// MARK: - Row view

private struct SetlistEditRow: View {
    @Binding var row: EditableSetlistRow
    let idolById: [String: Idol]
    let onPickSong: () -> Void
    let onPickCasts: () -> Void

    private let sections = ["本編", "アンコール", "MC", "ダブルアンコール"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPickSong) {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundStyle(DS.ink2)
                    Text(row.songTitle)
                        .foregroundStyle(row.songId.isEmpty ? DS.ink2 : DS.ink)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink3)
                }
            }
            .buttonStyle(.plain)

            Picker("セクション", selection: Binding(
                get: { row.section ?? "本編" },
                set: { row.section = ($0 == "本編") ? nil : $0 }
            )) {
                ForEach(sections, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

            Button(action: onPickCasts) {
                HStack(alignment: .top) {
                    Image(systemName: "person.2")
                        .foregroundStyle(DS.ink2)
                    if row.castIds.isEmpty {
                        Text("(出演者なし — タップで追加)")
                            .foregroundStyle(DS.ink2)
                    } else {
                        Text(performerNames())
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func performerNames() -> String {
        row.castIds
            .compactMap { idolById[$0]?.name }
            .sorted()
            .joined(separator: " / ")
    }
}
