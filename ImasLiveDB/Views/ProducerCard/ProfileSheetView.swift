import PhotosUI
import SwiftUI

/// プロフィール帳: P としての自己紹介を、履歴書の様式の 1 枚絵にして SNS に貼る。
///
/// 開くとまず「載せる記録を選ぶ」画面 (この画面)。大きさ・証明写真・担当ブランド・載せる記録を選び、
/// 「作る」で画像の見本 (`ProfileSheetPreviewView`) へ進んで書き出す。見本から「編集」で戻れる。
/// 自分で書く欄は無く、中身はすべてアプリの記録から埋まる。名前・P歴・リンク・自分の QR は P名刺のもの
/// (ここからそのまま P名刺の編集を開ける)。担当ブランドはアプリ全体の設定 (`BrandRoleStore`)。
/// 選んだものはその場で自分の名刺の行に保存する。欄の一覧と見本の値・付け外しはコア
/// (`profileAutoFieldRows` / `profileToggleField`)。項目の多い設定寄りの画面なので Form の型で組む。
struct ProfileSheetView: View {
    @State private var card: MyProducerCard?
    @State private var materials = ProfileSheetMaterials.empty
    @State private var loaded = false
    @State private var showingPreview = false
    @State private var editingCard: CardEdit?
    @State private var showingBrandSetup = false
    @State private var saveError: String?
    @State private var pendingSave: Task<Void, Never>?
    @State private var saveGeneration = 0

    // 証明写真
    @State private var photoPick: PhotosPickerItem?
    @State private var cropping: PhotoDraft?
    @State private var isFetchingAvatar = false
    @State private var photoNotice: String?
    @State private var hasOwnPhoto = ProfileSheetFiles.photoURL != nil

    private let sizes = profileSheetSizes()

    /// P名刺の編集を開くときに渡すもの。
    struct CardEdit: Identifiable {
        let id = UUID()
        let card: MyProducerCard
        let record: ProducerCardMyRecord?
        /// 開いたら見せる欄 (`links`)。
        let focus: String?
    }

    /// 写真の位置を決めるシートに渡すもの。
    struct PhotoDraft: Identifiable {
        let id = UUID()
        let image: UIImage
        let crop: ImasPortraitCrop
    }

    var body: some View {
        Group {
            if !loaded {
                ImasLoadingState()
            } else if let card {
                chooser(card)
            } else {
                ImasPage {
                    ImasCard {
                        ImasEmptyState(
                            systemImage: "person.text.rectangle",
                            title: "先に P名刺を作ってください",
                            message: "プロフィール帳の名前・P歴・リンク・写真は P名刺から入ります。担当と参加の記録はアプリから自動で入ります。",
                            actionTitle: "P名刺を作る",
                            action: { Task { await openCardEditor(focus: nil) } }
                        )
                    }
                }
            }
        }
        .navigationTitle("載せる記録を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingPreview) {
            ProfileSheetPreviewView(sheet: card?.profile ?? profileSheetDefault(), materials: materials)
        }
        .sheet(item: $editingCard) { edit in
            ProducerCardEditorView(card: edit.card, record: edit.record) { saved in
                // 名刺の欄だけを今の行に重ねる (プロフィール帳の選択は古い中身で戻さない)。
                var row = saved
                if let latest = try await AppContainer.shared.producerCards.myCard() {
                    row.profileJson = latest.profileJson
                }
                try await AppContainer.shared.producerCards.saveMyCard(row)
                await load()
            }
            .environment(\.producerCardEditorFocus, edit.focus)
        }
        .sheet(isPresented: $showingBrandSetup) {
            BrandRoleSetupSheet()
        }
        .sheet(item: $cropping) { draft in
            ProfilePhotoCropSheet(image: draft.image, crop: draft.crop) { crop in
                Task { await savePhoto(draft.image, crop: crop) }
            }
        }
        .onChange(of: photoPick) { _, item in
            guard let item else { return }
            photoPick = nil
            Task { await loadPhoto(item) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .brandRolesChanged)) { _ in
            materials.record.brandRolesJson = BrandRoleStore.json
        }
        .imasErrorAlert("保存できませんでした", message: $saveError)
        .task {
            await load()
            // 担当ブランドをまだ決めていなければ、はじめて開いたときに 1 度だけ確かめてもらう。
            if card != nil, BrandRoleStore.shouldPrompt {
                BrandRoleStore.markPrompted()
                showingBrandSetup = true
            }
        }
        .trackScreen("profile_sheet")
    }

    // MARK: - 選ぶ画面

    private func chooser(_ card: MyProducerCard) -> some View {
        let sheet = card.profile
        let rows = profileAutoFieldRows(sheet: sheet, record: materials.record)
        return List {
            ImasListSection("大きさ") {
                ImasSegmented(options: sizes.map(\.size), selection: choice(\.size)) { size in
                    sizes.first { $0.size == size }.map { "\($0.label) \($0.caption)" } ?? ""
                }
            }
            photoSection(card, row: rows.first { $0.field == .photo })
            brandsSection(row: rows.first { $0.field == .brands })
            ImasListSection("載せる記録", footer: "記録の無いものは並びません。外したものは画像に載りません。") {
                ForEach(rows.filter { $0.field != .photo && $0.field != .brands }, id: \.key) { row in
                    toggle(row, subtitle: row.fromCard ? "P名刺から · \(row.value)" : row.value)
                }
            }
            ImasListSection("P名刺から入るもの",
                            footer: "名前・P歴・連絡先のリンク・自分の QR は P名刺のものを使います。直すと次に作るときから変わります。") {
                Button { Task { await openCardEditor(focus: "links") } } label: {
                    ImasNavRow(title: "P名刺のリンクを直す", subtitle: linksSummary(card),
                               systemImage: "link", showsChevron: true)
                }
                .buttonStyle(.imasRow)
            }
            Section {
                ImasButton(title: "作る", systemImage: "doc.richtext", role: .primary, size: .large) {
                    AppAnalytics.tap("profile_sheet.make")
                    showingPreview = true
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .imasForm()
    }

    private func toggle(_ row: ProfileAutoFieldRow, subtitle: String?) -> some View {
        ImasToggleRow(title: row.label, subtitle: subtitle?.isEmpty == false ? subtitle : nil,
                      isOn: Binding(get: { row.shown }, set: { _ in toggleField(row.field) }))
    }

    private func linksSummary(_ card: MyProducerCard) -> String {
        let links = card.links.map { cardLinkView(link: $0).display }
        return links.isEmpty ? "まだリンクがありません" : links.joined(separator: "  ")
    }

    // MARK: - 証明写真

    private func photoSection(_ card: MyProducerCard, row: ProfileAutoFieldRow?) -> some View {
        let handle = cardXAvatarHandle(links: card.links)
        // PhotosPicker の label は古い SDK で Sendable な closure なので、状態は外で読んでおく。
        let pickTitle = hasOwnPhoto ? "写真を選び直す" : "写真から選ぶ"
        return ImasListSection("証明写真",
                               footer: "プロフィール帳だけの写真にできます (P名刺の写真は変わりません)。写真は端末の中だけに置き、バックアップには入りません。") {
            HStack(alignment: .top, spacing: DS.Space.gapLoose) {
                ImasCardPortrait(url: ProfileSheetFiles.effectiveURL, label: "証明写真")
                    .frame(width: thumbnailWidth)
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    Text(hasOwnPhoto ? "プロフィール帳の写真" : (ProducerCardFiles.myPhotoURL == nil ? "写真なし" : "P名刺の写真"))
                        .imasText(.rowTitle)
                    PhotosPicker(selection: $photoPick, matching: .images) {
                        ProfileActionLabel(title: pickTitle, systemImage: "photo")
                    }
                    .buttonStyle(.plain)
                    if let handle {
                        Button { Task { await useXAvatar(handle) } } label: {
                            ProfileActionLabel(
                                title: isFetchingAvatar ? "X のアイコンを取っています…" : "X のアイコンを使う (@\(handle))",
                                systemImage: "person.crop.square")
                        }
                        .buttonStyle(.plain)
                        .disabled(isFetchingAvatar)
                    }
                    if hasOwnPhoto {
                        Button { recrop() } label: {
                            ProfileActionLabel(title: "位置を直す", systemImage: "crop")
                        }
                        .buttonStyle(.plain)
                        Button { usePhotoOfCard() } label: {
                            ProfileActionLabel(title: "P名刺の写真に戻す", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.plain)
                    }
                    if let photoNotice {
                        Text(photoNotice).imasText(.note, color: DS.danger)
                    }
                }
            }
            .padding(.vertical, DS.Space.gapTight)
            if let row {
                toggle(row, subtitle: nil)
            }
        }
    }

    @ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 72

    private func loadPhoto(_ item: PhotosPickerItem) async {
        photoNotice = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            photoNotice = "写真を読み込めませんでした。"
            return
        }
        cropping = PhotoDraft(image: PaperCardRectifier.upright(image), crop: ImasPortraitCrop())
    }

    private func useXAvatar(_ handle: String) async {
        photoNotice = nil
        isFetchingAvatar = true
        let outcome = await XAvatarFetcher.fetch(handle: handle)
        isFetchingAvatar = false
        switch outcome {
        case .image(let image):
            AppAnalytics.tap("profile_sheet.x_avatar")
            cropping = PhotoDraft(image: PaperCardRectifier.upright(image), crop: ImasPortraitCrop())
        case .failed(let message):
            photoNotice = message
        }
    }

    private func recrop() {
        guard let source = ProfileSheetFiles.sourceURL.flatMap({ UIImage(contentsOfFile: $0.path) }) else { return }
        cropping = PhotoDraft(image: source, crop: ProfileSheetFiles.crop ?? ImasPortraitCrop())
    }

    private func savePhoto(_ image: UIImage, crop: ImasPortraitCrop) async {
        do {
            try ProfileSheetFiles.save(source: image, crop: crop)
            AppAnalytics.tap("profile_sheet.photo")
        } catch {
            photoNotice = "写真を保存できませんでした。"
        }
        await reloadMaterials()
    }

    private func usePhotoOfCard() {
        ProfileSheetFiles.delete()
        Task { await reloadMaterials() }
    }

    // MARK: - 担当ブランド

    private func brandsSection(row: ProfileAutoFieldRow?) -> some View {
        let marks = profileBrandMarks(record: materials.record)
        let main = marks.filter(\.main).map(\.label)
        let oshi = marks.filter { $0.checked && !$0.main }.map(\.label)
        var parts: [String] = []
        if !main.isEmpty { parts.append("メイン \(main.joined(separator: "・"))") }
        if !oshi.isEmpty { parts.append("担当 \(oshi.joined(separator: "・"))") }
        return ImasListSection("担当ブランド",
                               footer: "アプリ全体の設定です。担当は丸、メインは二重丸で付きます。") {
            NavigationLink {
                BrandRoleSettingsView()
            } label: {
                ImasNavRow(title: "担当ブランドを選ぶ", subtitle: parts.isEmpty ? "まだありません" : parts.joined(separator: " / "),
                           systemImage: "circle.circle", showsChevron: false, subtitleLineLimit: 2)
            }
            if let row {
                toggle(row, subtitle: nil)
            }
        }
    }

    // MARK: - 保存

    private func toggleField(_ field: ProfileAutoField) {
        guard let current = card?.profile else { return }
        update(profileToggleField(sheet: current, field: field))
    }

    /// 大きさの切り替え。
    private func choice<Value>(_ key: WritableKeyPath<ProfileSheet, Value>) -> Binding<Value> {
        Binding(
            get: { (card?.profile ?? profileSheetDefault())[keyPath: key] },
            set: { value in
                guard var sheet = card?.profile else { return }
                sheet[keyPath: key] = value
                update(sheet)
            }
        )
    }

    /// 選んだらその場で保存する。続けて変えても保存は順に 1 本ずつ流し (古い選択が後から書かれないように)、
    /// 失敗したときは最後に変えた分だけ前の選択に戻す。
    private func update(_ sheet: ProfileSheet) {
        guard let previous = card?.profile else { return }
        card?.profile = sheet
        saveGeneration += 1
        let generation = saveGeneration
        let prior = pendingSave
        pendingSave = Task {
            await prior?.value
            do {
                try await persist(sheet)
            } catch {
                guard generation == saveGeneration else { return }
                card?.profile = previous
                saveError = error.localizedDescription
            }
        }
    }

    /// 自分の名刺の行にプロフィール帳の選択を書く (名刺のほかの欄は DB の最新を使う)。
    private func persist(_ sheet: ProfileSheet) async throws {
        guard let card else { return }
        var saved = (try await AppContainer.shared.producerCards.myCard()) ?? card
        saved.profile = sheet
        try await AppContainer.shared.producerCards.saveMyCard(saved)
    }

    // MARK: - 読み込み

    private func openCardEditor(focus: String?) async {
        let record = try? await ProducerCardAssembler.loadMyRecord()
        editingCard = CardEdit(card: card ?? .empty(), record: record, focus: focus)
    }

    private func reloadMaterials() async {
        hasOwnPhoto = ProfileSheetFiles.photoURL != nil
        guard let card else { return }
        materials = await ProfileSheetAssembler.load(card: card)
    }

    private func load() async {
        await pendingSave?.value
        let mine = try? await AppContainer.shared.producerCards.myCard()
        // 材料を読み終えてから名刺を入れる (読み込み中に空の材料で並べない)。
        if let mine {
            materials = await ProfileSheetAssembler.load(card: mine)
        }
        hasOwnPhoto = ProfileSheetFiles.photoURL != nil
        card = mine
        loaded = true
    }
}

/// プロフィール帳の見本と書き出し。「編集」で選ぶ画面へ戻る。
struct ProfileSheetPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let sheet: ProfileSheet
    let materials: ProfileSheetMaterials

    @State private var exportError: String?

    var body: some View {
        let layout = profileSheetLayout(sheet: sheet, record: materials.record)
        ImasPage {
            ShareCardPreview(size: ProfileSheetInk.size(sheet.size)) {
                ProfileSheetCard(layout: layout, materials: materials)
            }
            .accessibilityLabel("\(layout.title)の見本")
            ImasButton(title: "画像を書き出す", systemImage: "square.and.arrow.up", role: .primary, size: .large) {
                export(layout)
            }
            ImasNote("中身はアプリの記録 (参加した公演・セトリ・回収・担当・お気に入り) から自動で入ります。載せるものは右上の鉛筆から選び直せます。")
        }
        .navigationTitle("プロフィール帳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ImasToolbarButton(systemImage: "pencil", label: "編集") { dismiss() }
            }
        }
        .imasErrorAlert("画像を書き出せませんでした", message: $exportError)
        .trackScreen("profile_sheet_preview")
    }

    private func export(_ layout: ProfileSheetLayout) {
        guard let image = ProfileSheetAssembler.render(layout: layout, materials: materials) else {
            exportError = "もう一度試すか、アプリを再起動してください。"
            return
        }
        AppAnalytics.tap("profile_sheet.export")
        SystemShare.present(items: [ShareCardImageSource(image)])
    }
}

/// 証明写真の欄に合わせるシート。引いて動かし、つまんで広げ、✓ で決める。
struct ProfilePhotoCropSheet: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onDone: (ImasPortraitCrop) -> Void
    @State private var crop: ImasPortraitCrop

    init(image: UIImage, crop: ImasPortraitCrop, onDone: @escaping (ImasPortraitCrop) -> Void) {
        self.image = image
        self.onDone = onDone
        _crop = State(initialValue: crop)
    }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasPortraitCropper(image: image, crop: $crop)
                ImasNote("引いて動かし、2 本の指で広げると、履歴書の証明写真の枠 (3:4) に合わせられます。写真は端末の中だけに置きます。")
            }
            .navigationTitle("写真の位置")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(onCancel: { dismiss() }, onSave: {
                onDone(crop)
                dismiss()
            }))
        }
    }
}

/// 証明写真の小さな操作 (写真から選ぶ・位置を直す)。PhotosPicker の label は MainActor の外で組まれるので
/// View に包む。
private struct ProfileActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .imasText(.rowLabel, color: DS.ink)
    }
}

// MARK: - P名刺の編集を開いたときに見せる欄

private struct ProducerCardEditorFocusKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// P名刺の編集を開いたときに見せる欄 (`links` など、編集画面の欄の id)。プロフィール帳から
    /// 「P名刺のリンクを直す」で開くときに渡す。
    var producerCardEditorFocus: String? {
        get { self[ProducerCardEditorFocusKey.self] }
        set { self[ProducerCardEditorFocusKey.self] = newValue }
    }
}
