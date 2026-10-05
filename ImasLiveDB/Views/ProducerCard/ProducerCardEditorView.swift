import SwiftUI

/// 自分の P名刺を作る・直す。書くのは名前・ひとこと・P歴・リンクだけで、
/// 担当と記録の数はアプリの記録から入る (載せたくない項目はここで外す)。
///
/// 入力の検査・リンクの正規化はコア (`validateProducerCard` / `normalizeCardLink`)。
struct ProducerCardEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let card: MyProducerCard
    let record: ProducerCardMyRecord?
    let onSave: (MyProducerCard) async throws -> Void

    @State private var name: String
    @State private var message: String
    @State private var sinceYear: Int?
    @State private var links: [EditableLink]
    @State private var hidden: Set<ProducerCardField>
    @State private var oshi: [Idol] = []
    @State private var brands: [String: Brand] = [:]
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDiscard = false

    private let limits = producerCardLimits()
    private let kinds = cardLinkKinds()

    struct EditableLink: Identifiable, Hashable {
        let id = UUID()
        var kind: CardLinkKind
        var value: String
    }

    init(card: MyProducerCard, record: ProducerCardMyRecord?,
         onSave: @escaping (MyProducerCard) async throws -> Void) {
        self.card = card
        self.record = record
        self.onSave = onSave
        _name = State(initialValue: card.name)
        _message = State(initialValue: card.message)
        _sinceYear = State(initialValue: card.sinceYear)
        _links = State(initialValue: card.links.map { EditableLink(kind: $0.kind, value: $0.value) })
        _hidden = State(initialValue: card.hidden)
    }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasFormCard {
                    ImasFormTextField(label: "名前", imprint: "NAME", text: $name, prompt: "ふがP",
                                      error: name.count > Int(limits.maxNameChars) ? "\(limits.maxNameChars)文字までです" : nil,
                                      isTitle: true)
                    ImasFormTextArea(label: "ひとこと", imprint: "MESSAGE", systemImage: nil, text: $message,
                                     prompt: "現地派・ライブ皆勤目指してます", limit: Int(limits.maxMessageChars))
                    ImasFormField(label: "P歴の始まり", imprint: "SINCE") {
                        Picker("P歴の始まり", selection: $sinceYear) {
                            Text("載せない").tag(Int?.none)
                            ForEach(Self.years, id: \.self) { year in
                                Text(verbatim: "\(year)年").tag(Int?.some(year))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(DS.ink)
                    }
                }

                oshiCard
                linksCard
                recordCard

                if let error {
                    Text(error).imasText(.note, color: DS.danger)
                }
                ImasNote("名刺の中身は QR に全部入ります。サーバには何も置かないので、圏外の会場でも交換できます。後から名刺を直しても、相手の手元の名刺は交換したときのままです。")
            }
            .navigationTitle(card.name.isEmpty ? "P名刺を作る" : "P名刺を編集")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(canSave: canSave, onCancel: cancel, onSave: { Task { await save() } }))
            .imasSavingOverlay(isSaving, label: "保存中")
            .imasDiscardConfirmation(isPresented: $confirmDiscard) { dismiss() }
            .interactiveDismissDisabled(isDirty)
        }
        .task { await loadOshi() }
    }

    // MARK: - 担当

    private var oshiCard: some View {
        ImasFormCard {
            ImasFormField(label: "担当 · アプリから", imprint: "OSHI") {
                if oshi.isEmpty {
                    Text("アイドル詳細で「担当」を付けると、ここに入ります").imasText(.note)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        ForEach(oshi) { idol in
                            HStack(spacing: DS.Space.gap) {
                                ImasAvatar(label: idol.shortName, seed: idol.color, brand: brands[idol.brandId]?.color,
                                           size: 26, isPick: true,
                                           imageURL: CustomImageService.shared.imageURL(for: idol.id))
                                Text(idol.name).imasText(.rowTitle)
                            }
                        }
                    }
                }
            }
            toggle(.oshi, title: "担当を載せる")
        }
    }

    // MARK: - リンク

    private var linksCard: some View {
        ImasFormCard {
            ImasFormField(label: "リンク", imprint: "LINKS") {
                VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                    ForEach($links) { $link in
                        linkEditor($link)
                    }
                    if links.count < Int(limits.maxLinks) {
                        Menu {
                            ForEach(kinds, id: \.label) { info in
                                Button(info.label) { links.append(EditableLink(kind: info.kind, value: "")) }
                            }
                        } label: {
                            Label("リンクを足す", systemImage: "plus")
                                .imasText(.rowLabel, color: DS.ink)
                        }
                    }
                }
            }
            toggle(.links, title: "リンクを載せる")
        }
    }

    private func linkEditor(_ link: Binding<EditableLink>) -> some View {
        let info = kinds.first { $0.kind == link.wrappedValue.kind }
        let invalid = !link.wrappedValue.value.trimmingCharacters(in: .whitespaces).isEmpty
            && normalizeCardLink(link: CardLink(kind: link.wrappedValue.kind, value: link.wrappedValue.value)) == nil
        return VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            HStack(spacing: DS.Space.gap) {
                Text(info?.label ?? "").imasText(.value, color: DS.ink2)
                TextField(info?.placeholder ?? "", text: link.value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .imasText(.value)
                Button {
                    links.removeAll { $0.id == link.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(DS.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(info?.label ?? "リンク")を外す")
            }
            if invalid {
                Text("リンクの書き方を確かめてください").imasText(.note, color: DS.danger)
            }
        }
    }

    // MARK: - 記録

    private var recordCard: some View {
        let summary = record?.summary
        return ImasFormCard {
            toggle(.showCount, title: "参加公演数", value: summary.map { "\($0.showCount.formatted()) 公演" })
            toggle(.songCount, title: "回収曲数", value: record.map { "\($0.songCount.formatted()) 曲" })
            toggle(.next, title: "次の現場", value: summary?.nextShowId == nil ? "参加予定なし" : nil)
            toggle(.attended, title: "参加した公演の一覧", value: "共通点を出すのに使う")
        }
    }

    private func toggle(_ field: ProducerCardField, title: String, value: String? = nil) -> some View {
        ImasFormToggle(
            label: value.map { "\(field.label) · \($0)" } ?? field.label,
            title: title,
            isOn: Binding(
                get: { !hidden.contains(field) },
                set: { on in if on { hidden.remove(field) } else { hidden.insert(field) } }
            )
        )
    }

    // MARK: - 保存

    private static var years: [Int] {
        let now = Calendar(identifier: .gregorian).component(.year, from: Date())
        return Array((2005...max(2005, now)).reversed())
    }

    private var draft: MyProducerCard {
        var out = card
        out.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        out.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        out.sinceYear = sinceYear
        out.links = links
            .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { normalizeCardLink(link: CardLink(kind: $0.kind, value: $0.value)) }
        out.hidden = hidden
        return out
    }

    private var validation: ProducerCardInputError? {
        let filled = links.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        let input = ProducerCardInput(
            name: name, message: message, sinceYear: nil, oshiIdolIds: [],
            links: filled.map { CardLink(kind: $0.kind, value: $0.value) },
            showCount: nil, songCount: nil, nextShowId: nil, attended: [], issuedOn: JSTDay.today())
        return validateProducerCard(input: input)
    }

    private var canSave: Bool { validation == nil && !isSaving }

    private var isDirty: Bool {
        name != card.name || message != card.message || sinceYear != card.sinceYear
            || hidden != card.hidden || draft.linksJson != card.linksJson
    }

    private func cancel() {
        if isDirty { confirmDiscard = true } else { dismiss() }
    }

    private func save() async {
        if let validation {
            error = producerCardInputErrorMessage(error: validation)
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draft)
            AppAnalytics.tap("producer_card.save")
            dismiss()
        } catch {
            self.error = "保存できませんでした。\(error.localizedDescription)"
        }
    }

    private func loadOshi() async {
        guard let ids = record?.oshiIds.prefix(Int(limits.maxOshi)), !ids.isEmpty else { return }
        let idols = (try? await AppContainer.shared.idolReading.idols(ids: Array(ids))) ?? []
        let byId = Dictionary(idols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        oshi = ids.compactMap { byId[$0] }
        if let all = try? await AppContainer.shared.brandReading.brands() {
            brands = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }
}
