import SwiftUI

/// プロフィール帳を直す。上に出来上がりの見本 (その場で変わる)、下に欄の一覧。
///
/// 自分で書く欄は「質問を足す」から足し、長く押して並べ替え、左に引いて外す。質問文も書き換えられる。
/// 質問の一覧・様式ごとの欄への割り当て・上限・対応範囲の丸の付け外しはコア
/// (`profileQuestions` / `profileSheetLayout` / `validateProfileSheet` / `profileToggleBrand`)。
/// 項目の多い設定寄りのシートで、並べ替えと引いて外すのに List が要るので Form の型で組む。
struct ProfileSheetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let card: MyProducerCard
    let materials: ProfileSheetMaterials
    let onSave: (ProfileSheet) async throws -> Void

    @State private var sheet: ProfileSheet
    @State private var answers: [EditableAnswer]
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var pickingSongs = false

    private let limits = profileSheetLimits()
    private let styles = profileSheetStyles()
    private let sizes = profileSheetSizes()
    private let autoFields = profileAutoFields()

    struct EditableAnswer: Identifiable, Hashable {
        let id = UUID()
        var question: ProfileQuestion
        var prompt: String
        var text: String
    }

    init(card: MyProducerCard, materials: ProfileSheetMaterials,
         onSave: @escaping (ProfileSheet) async throws -> Void) {
        self.card = card
        self.materials = materials
        self.onSave = onSave
        let sheet = card.profile
        _sheet = State(initialValue: sheet)
        _answers = State(initialValue: sheet.answers.map {
            EditableAnswer(question: $0.question, prompt: $0.prompt, text: $0.text)
        })
    }

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            List {
                Section { preview }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ImasListSection("様式") {
                    ImasSegmented(options: styles.map(\.style), selection: $sheet.style) { style in
                        styles.first { $0.style == style }?.label ?? ""
                    }
                    ImasSegmented(options: sizes.map(\.size), selection: $sheet.size) { size in
                        sizes.first { $0.size == size }.map { "\($0.label) \($0.caption)" } ?? ""
                    }
                }
                ImasListSection("氏名", footer: "名前・写真・書体・リンク・自分の QR は P名刺のものです。") {
                    ImasValueRow(key: "名前", value: card.name)
                    ImasTextFieldRow(title: "ふりがな", text: $sheet.furigana, prompt: "ふがぴー",
                                     error: profileTextLen(text: sheet.furigana) > limits.maxFuriganaChars
                                        ? profileSheetErrorMessage(error: .furiganaTooLong) : nil)
                }
                answersSection.id("answers")
                songsSection
                brandsSection.id("brands")
                ImasListSection("アプリの記録から", footer: "外した記録は画像に載りません。") {
                    ForEach(autoFields, id: \.key) { info in
                        ImasToggleRow(title: info.label, isOn: shownBinding(info.field))
                    }
                }
                if let message = error ?? validation.map({ profileSheetErrorMessage(error: $0) }) {
                    Section { Text(message).imasText(.note, color: DS.danger) }
                        .listRowBackground(Color.clear)
                }
            }
            .imasForm()
            #if DEBUG
            .onAppear {
                // シミュレータでの見た目確認 (PROFILE_SCROLL=answers|brands)。
                if let target = ProcessInfo.processInfo.environment["PROFILE_SCROLL"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(target, anchor: .top) }
                }
            }
            #endif
            .navigationTitle("プロフィール帳を編集")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(canSave: canSave, onCancel: cancel, onSave: { Task { await save() } }))
            .imasSavingOverlay(isSaving, label: "保存中")
            .imasDiscardConfirmation(isPresented: $confirmDiscard) { dismiss() }
            .interactiveDismissDisabled(isDirty)
            .navigationDestination(isPresented: $pickingSongs) {
                ProfileSongPicker(candidates: materials.favoriteCandidates,
                                  selection: $sheet.favoriteSongIds, limit: Int(limits.maxSongs))
            }
          }
        }
    }

    // MARK: - 見本

    private var preview: some View {
        let draft = draft
        let current = materials.with(favoriteSongIds: draft.favoriteSongIds)
        let layout = profileSheetLayout(sheet: draft, record: current.record)
        return ShareCardPreview(size: ProfileSheetInk.size(draft.size)) {
            ProfileSheetCard(layout: layout, materials: current)
        }
        .accessibilityLabel("\(layout.title)の見本")
    }

    // MARK: - 自分で書く欄

    private var answersSection: some View {
        ImasListSection("自分で書く欄", count: "\(answers.count) / \(limits.maxAnswers)",
                        footer: "長く押して並べ替え、左に引いて外します。質問も書き換えられます。答えの空の欄は画像に出ません。") {
            ForEach(Array($answers.enumerated()), id: \.element.id) { index, $answer in
                let info = profileQuestionInfo(question: answer.question)
                ImasQuestionField(number: index + 1, prompt: $answer.prompt, defaultPrompt: info.prompt,
                                  answer: $answer.text, placeholder: info.placeholder,
                                  promptLimit: Int(limits.maxPromptChars), answerLimit: Int(limits.maxAnswerChars),
                                  measure: { Int(profileTextLen(text: $0)) })
            }
            .onMove { answers.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { answers.remove(atOffsets: $0) }
            let hidden = profileSheetLayout(sheet: draft, record: materials.record).hiddenAnswers
            if hidden > 0, let size = sizes.first(where: { $0.size == sheet.size }) {
                ImasNote("\(size.label) の画像には答えのある欄の先頭 \(size.maxVisibleAnswers) つまで載ります (あと \(hidden) つは載りません)。並べ替えで選べます。")
                    .listRowBackground(DS.surface)
            }
            let addable = profileAddableQuestions(sheet: draft)
            if !addable.isEmpty {
                Menu {
                    ForEach(addable, id: \.key) { info in
                        Button(info.prompt) {
                            answers.append(EditableAnswer(question: info.question, prompt: "", text: ""))
                        }
                    }
                } label: {
                    ImasNavRow(title: "質問を足す", systemImage: "plus", showsChevron: false)
                }
                .buttonStyle(.imasRow)
            }
        }
    }

    // MARK: - 好きな曲

    private var songsSection: some View {
        ImasListSection("好きな曲", count: "\(sheet.favoriteSongIds.count) / \(limits.maxSongs)",
                        footer: "お気に入りの曲から選びます。長く押して並べ替え、左に引いて外します。") {
            ForEach(sheet.favoriteSongIds, id: \.self) { id in
                ImasRow(title: materials.songTitles[id] ?? "見つからない曲", density: .compact, titleRole: .rowLabel)
            }
            .onMove { sheet.favoriteSongIds.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { sheet.favoriteSongIds.remove(atOffsets: $0) }
            Button { pickingSongs = true } label: {
                ImasNavRow(title: "曲を選ぶ", subtitle: materials.favoriteCandidates.isEmpty
                           ? "曲の詳細で ★ を付けると、ここから選べます" : nil,
                           systemImage: "music.note.list")
            }
            .buttonStyle(.imasRow)
            .disabled(materials.favoriteCandidates.isEmpty)
        }
    }

    // MARK: - 対応範囲

    private var brandsSection: some View {
        let marks = profileBrandMarks(sheet: draft, record: materials.record)
        return ImasListSection("対応範囲", footer: "担当と参加した公演のブランドに丸が付いています。押すと付け外しできます。") {
            ImasChipFlow {
                ForEach(marks, id: \.id) { mark in
                    ImasFilterChip(text: mark.label, isSelected: mark.checked, brand: mark.color) {
                        sheet = profileToggleBrand(sheet: draft, record: materials.record, brandId: mark.id)
                    }
                    .accessibilityHint(mark.fromRecord ? "記録から丸が付くブランド" : "")
                }
            }
            .listRowBackground(DS.surface)
        }
    }

    // MARK: - 検査と保存

    private func shownBinding(_ field: ProfileAutoField) -> Binding<Bool> {
        Binding(
            get: { !sheet.hidden.contains(field) },
            set: { on in
                sheet.hidden.removeAll { $0 == field }
                if !on { sheet.hidden.append(field) }
            }
        )
    }

    /// 今の入力 (答えの並びを中身に戻したもの)。前後の空白は残し、検査と表示はコアが削る。
    private var draft: ProfileSheet {
        var out = sheet
        out.answers = answers.map { ProfileAnswer(question: $0.question, prompt: $0.prompt, text: $0.text) }
        return out
    }

    private var validation: ProfileSheetError? { validateProfileSheet(sheet: draft) }
    private var canSave: Bool { validation == nil && !isSaving }
    private var isDirty: Bool { draft != card.profile }

    private func cancel() {
        if isDirty { confirmDiscard = true } else { dismiss() }
    }

    private func save() async {
        if let validation {
            error = profileSheetErrorMessage(error: validation)
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draft)
            AppAnalytics.tap("profile_sheet.save")
            dismiss()
        } catch {
            self.error = "保存できませんでした。\(error.localizedDescription)"
        }
    }
}

/// 好きな曲を選ぶ (お気に入りの曲から、上限まで。選んだ順に並ぶ)。
private struct ProfileSongPicker: View {
    let candidates: [Song]
    @Binding var selection: [String]
    let limit: Int

    var body: some View {
        List {
            ImasListSection(count: "\(selection.count) / \(limit)", footer: "選んだ順に載ります。") {
                ForEach(candidates) { song in
                    let selected = selection.contains(song.id)
                    ImasSelectableRow(title: song.title, isSelected: selected,
                                      isDisabled: !selected && selection.count >= limit) {
                        if selected {
                            selection.removeAll { $0 == song.id }
                        } else if selection.count < limit {
                            selection.append(song.id)
                        }
                    }
                }
            }
        }
        .imasForm()
        .navigationTitle("好きな曲")
        .navigationBarTitleDisplayMode(.inline)
    }
}
