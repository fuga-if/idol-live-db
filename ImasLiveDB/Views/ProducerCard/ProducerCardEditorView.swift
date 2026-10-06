import PhotosUI
import SwiftUI

/// 自分の P名刺を作る・直す。書くのは名前・ひとこと・P歴・リンク・名刺のデザイン・名刺の写真・自分の QR で、
/// 担当と記録の数はアプリの記録から入る (載せたくない項目はここで外す)。
/// 上に名刺の見本を置き、変えたものはその場で見本に出る。
///
/// デザインは 3 つ (入場証・かしこまった名刺・ポップ) と「自作の画像」から選ぶだけ (細かい見た目は選ばせない)。
/// 自作の画像は写真から選んだ名刺の画像 (表・任意で裏) を、紙の名刺の取り込みと同じく四隅を見つけて平らにし、
/// 画像の QR があれば自分の QR に入れる。名刺の写真は X のアイコンからも取れる。
///
/// 入力の検査・リンクと QR の URL の正規化・デザインの一覧・X のアイコンの規則はコア
/// (`validateProducerCard` / `normalizeCardLink` / `normalizeCardQrUrl` / `cardDesigns` / `cardXAvatarHandle`)。
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

    @State private var design: String
    @State private var qrUrl: String
    @State private var qrPick: PhotosPickerItem?
    @State private var qrNotice: String?

    /// 名刺の写真 (切り抜く前) と切り抜き。変えたら ✓ のときに書く。
    @State private var photoSource: UIImage?
    @State private var crop = ImasPortraitCrop()
    @State private var photoDirty = false
    @State private var photoPick: PhotosPickerItem?
    @State private var cropping: CropDraft?
    /// 見本に出す切り抜き済みの写真 (✓ の前は一時ファイル)。
    @State private var previewPortrait: URL?
    @State private var directory = ProducerCardDirectory()

    /// 自作の名刺の画像 (平らにした後)。変えた面だけ ✓ のときに書く (nil は外した)。
    @State private var faceImages: [ProducerCardFiles.Side: UIImage] = [:]
    /// 写真から選んだ元と見つけた四隅 (四隅を直すとき用。この編集で選んだ面だけ)。
    @State private var faceSources: [ProducerCardFiles.Side: PaperPhotoSource] = [:]
    /// 見本に出す画像 (保存済みのファイルか、✓ の前の一時ファイル)。
    @State private var facePreview: [ProducerCardFiles.Side: URL] = [:]
    @State private var faceDirty: Set<ProducerCardFiles.Side> = []
    @State private var faceFrontPick: PhotosPickerItem?
    @State private var faceBackPick: PhotosPickerItem?
    @State private var faceCorners: FaceCornerDraft?
    @State private var faceNotice: String?
    @State private var isReadingFace = false

    @State private var isFetchingAvatar = false
    @State private var avatarNotice: String?

    private let limits = producerCardLimits()
    private let kinds = cardLinkKinds()
    private let designs = cardDesigns()

    /// 切り抜きのシートに渡すもの。
    struct CropDraft: Identifiable {
        let id = UUID()
        let image: UIImage
        let crop: ImasPortraitCrop
    }

    /// 自作の名刺の画像の四隅を直すシートに渡すもの。
    struct FaceCornerDraft: Identifiable {
        let id = UUID()
        let side: ProducerCardFiles.Side
        let source: PaperPhotoSource
    }

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
        _design = State(initialValue: cardDesignKey(design: card.cardDesign))
        _qrUrl = State(initialValue: card.qrUrl ?? "")
    }

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            ImasFormPage {
                preview
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

                designCard.id("look")
                photoCard
                oshiCard
                linksCard
                qrCard.id("qr")
                recordCard

                if let error {
                    Text(error).imasText(.note, color: DS.danger)
                } else if validation == .tooLong {
                    Text(producerCardInputErrorMessage(error: .tooLong)).imasText(.note, color: DS.danger)
                }
                if design != designs[0].key || !qrUrl.trimmingCharacters(in: .whitespaces).isEmpty {
                    ImasNote("デザインや自分の QR を載せた名刺は、古い版のアプリでは読めません (相手にアプリを最新にしてもらうと読めます)。")
                }
                ImasNote("名刺の中身は QR に全部入ります。サーバには何も置かないので、圏外の会場でも交換できます。後から名刺を直しても、相手の手元の名刺は交換したときのままです。")
            }
            #if DEBUG
            .onAppear {
                // シミュレータでの見た目確認 (PRODUCER_CARD_SCROLL=look|qr)。
                if let target = ProcessInfo.processInfo.environment["PRODUCER_CARD_SCROLL"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(target, anchor: .top) }
                }
            }
            #endif
            .navigationTitle(card.name.isEmpty ? "P名刺を作る" : "P名刺を編集")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(canSave: canSave, onCancel: cancel, onSave: { Task { await save() } }))
            .imasSavingOverlay(isSaving || isReadingFace, label: isReadingFace ? "画像を整えています" : "保存中")
            .imasDiscardConfirmation(isPresented: $confirmDiscard) { dismiss() }
            .interactiveDismissDisabled(isDirty)
            .sheet(item: $cropping) { draft in
                CardPhotoCropSheet(image: draft.image, crop: draft.crop) { result in
                    Task { await applyCrop(image: draft.image, crop: result) }
                }
            }
            .onChange(of: photoPick) { _, item in
                guard let item else { return }
                photoPick = nil
                Task { await loadPhoto(item) }
            }
            .onChange(of: qrPick) { _, item in
                guard let item else { return }
                qrPick = nil
                Task { await readQR(item) }
            }
            .onChange(of: faceFrontPick) { _, item in
                guard let item else { return }
                faceFrontPick = nil
                Task { await loadFace(item, side: .front) }
            }
            .onChange(of: faceBackPick) { _, item in
                guard let item else { return }
                faceBackPick = nil
                Task { await loadFace(item, side: .back) }
            }
            .sheet(item: $faceCorners) { draft in
                PaperCardCornerSheet(image: draft.source.original,
                                     corners: draft.source.corners ?? PaperCardRectifier.defaultCorners) { corners in
                    Task { await applyFaceCorners(side: draft.side, source: draft.source, corners: corners) }
                }
            }
          }
        }
        .task {
            await loadOshi()
            loadPhoto()
            loadFaces()
        }
    }

    // MARK: - 見本

    /// 今の入力で組んだ名刺 (保存前でもその場で見た目に出す)。
    private var preview: some View {
        let rec = record ?? ProducerCardMyRecord(oshiIds: [], attended: [], songCount: 0)
        var sample = draft
        if sample.name.isEmpty { sample.name = "名前" }
        // 見本は書体・写真・リンクを見るためのもの。記録の掲示板は外して背を低くする。
        sample.hidden.formUnion([.showCount, .songCount, .next])
        let card = encodeProducerCard(input: ProducerCardAssembler.input(card: sample, record: rec)).card
        return ProducerCardDisplay.view(
            card, directory: directory,
            imageURL: { CustomImageService.shared.imageURL(for: $0) },
            portraitURL: previewPortrait,
            face: previewFace,
            onOpenLink: nil, onOpenOshi: nil
        )
        .accessibilityLabel("名刺の見本")
    }

    // MARK: - デザイン

    private var selectedDesign: CardDesignInfo {
        designs.first { $0.key == design } ?? designs[0]
    }

    private var previewFace: ProducerCardDisplay.Face? {
        facePreview[.front].map { ProducerCardDisplay.Face(front: $0, back: facePreview[.back]) }
    }

    private var designCard: some View {
        let lead = oshi.first
        return ImasFormCard {
            ImasFormField(label: "名刺のデザイン", imprint: "DESIGN") {
                ImasCardDesignPicker(
                    options: designs.map { info in
                        .init(id: info.key, label: info.label, look: look(info.design),
                              postScriptName: info.font.postscriptName)
                    },
                    selection: $design,
                    sample: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    seed: lead?.color, brand: lead.flatMap { brands[$0.brandId]?.color }
                )
            }
            if selectedDesign.usesFaceImage {
                faceField
            }
        }
    }

    private func look(_ design: CardDesign) -> ImasCardDesignPicker.Option.Look {
        switch design {
        case .pass: return .pass
        case .formal: return .formal
        case .pop: return .pop
        case .custom: return .face(facePreview[.front])
        }
    }

    /// 自作の名刺の画像 (表・裏)。
    private var faceField: some View {
        ImasFormField(label: "自作の画像", imprint: "FACE",
                      error: facePreview[.front] == nil ? "表の画像を選んでください" : nil) {
            VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                HStack(alignment: .top, spacing: DS.Space.gapLoose) {
                    faceSlot(.front, title: "表", pick: $faceFrontPick)
                    faceSlot(.back, title: "裏 (なくてもよい)", pick: $faceBackPick)
                }
                Text("自分で作った名刺の画像がそのまま名刺の顔になります (91:55 の比が基本、違う比率でも切りません)。紙の名刺を撮った写真なら、四隅を見つけて平らにします。画像の QR は自分の QR に入ります。")
                    .imasText(.note)
                if let faceNotice {
                    Text(faceNotice).imasText(.note, color: DS.ink)
                }
            }
        }
    }

    private func faceSlot(_ side: ProducerCardFiles.Side, title: String, pick: Binding<PhotosPickerItem?>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            Text(title).imasText(.rowLabel, color: DS.ink2)
            if let url = facePreview[side] {
                ImasCardFace(front: url, label: "自作の名刺の\(title)", thumbnail: true)
            }
            PhotosPicker(selection: pick, matching: .images) {
                CardEditorActionLabel(title: facePreview[side] == nil ? "画像を選ぶ" : "選び直す",
                                      systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            if let source = faceSources[side] {
                Button { faceCorners = FaceCornerDraft(side: side, source: source) } label: {
                    CardEditorActionLabel(title: "四隅を直す", systemImage: "crop")
                }
                .buttonStyle(.plain)
            }
            if facePreview[side] != nil {
                Button(role: .destructive) { removeFace(side) } label: {
                    CardEditorActionLabel(title: "外す", systemImage: "minus.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 名刺の写真

    private var photoCard: some View {
        let pickTitle = photoSource == nil ? "写真を選ぶ" : "写真を変える"
        let handle = cardXAvatarHandle(links: draft.links)
        return ImasFormCard {
            ImasFormField(label: "名刺の写真", imprint: "PHOTO") {
                HStack(alignment: .top, spacing: DS.Space.gapLoose) {
                    if let previewPortrait {
                        ImasCardPortrait(url: previewPortrait)
                            .frame(width: thumbnailWidth)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        PhotosPicker(selection: $photoPick, matching: .images) {
                            CardEditorActionLabel(title: pickTitle, systemImage: "photo")
                        }
                        .buttonStyle(.plain)
                        if let handle {
                            Button { Task { await useXAvatar(handle) } } label: {
                                CardEditorActionLabel(
                                    title: isFetchingAvatar ? "X のアイコンを取っています…" : "X のアイコンを使う (@\(handle))",
                                    systemImage: "person.crop.square")
                            }
                            .buttonStyle(.plain)
                            .disabled(isFetchingAvatar)
                        }
                        if let photoSource {
                            Button { cropping = CropDraft(image: photoSource, crop: crop) } label: {
                                CardEditorActionLabel(title: "位置を直す", systemImage: "crop")
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { removePhoto() } label: {
                                CardEditorActionLabel(title: "写真を外す", systemImage: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        if let avatarNotice {
                            Text(avatarNotice).imasText(.note, color: DS.danger)
                        } else if photoSource == nil {
                            Text("名前の横に証明写真のように載ります。担当の画像とは別です。").imasText(.note)
                        }
                    }
                }
            }
        }
    }

    @ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 60

    // MARK: - 自分の QR

    private var qrCard: some View {
        ImasFormCard {
            ImasFormField(label: "自分の QR", imprint: "QR", error: qrInvalid ? qrErrorMessage : nil) {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    HStack(spacing: DS.Space.gap) {
                        TextField("https://lit.link/…", text: $qrUrl)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .imasText(.value)
                        if !qrUrl.isEmpty {
                            Button { qrUrl = "" } label: {
                                Image(systemName: "minus.circle").foregroundStyle(DS.ink3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("自分の QR を外す")
                        }
                    }
                    let linkViews = draft.links.map { cardLinkView(link: $0) }
                    if !linkViews.isEmpty {
                        Menu {
                            ForEach(linkViews, id: \.url) { view in
                                Button("\(view.label) \(view.display)") { qrUrl = view.url }
                            }
                        } label: {
                            CardEditorActionLabel(title: "名刺のリンクから選ぶ", systemImage: "link")
                        }
                    }
                    PhotosPicker(selection: $qrPick, matching: .images) {
                        CardEditorActionLabel(title: "写真の QR を読む", systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(.plain)
                    if let qrNotice {
                        Text(qrNotice).imasText(.note, color: DS.danger)
                    }
                }
            }
        }
    }

    private var qrInvalid: Bool {
        !qrUrl.trimmingCharacters(in: .whitespaces).isEmpty && normalizeCardQrUrl(raw: qrUrl) == nil
    }

    private var qrErrorMessage: String { producerCardInputErrorMessage(error: .qrUrlInvalid) }

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
        out.design = design
        out.qrUrl = normalizeCardQrUrl(raw: qrUrl)
        return out
    }

    /// 検査は名刺に載る中身 (担当・記録の数・書体も) で組んだ入力に、書きかけのリンクと QR の URL を
    /// そのまま入れて渡す。載る中身を抜くと QR に収まるかの見積もりが実物より短くなり、
    /// 保存できても相手が読めない名刺になる。
    private var validation: ProducerCardInputError? {
        let filled = links.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        let rec = record ?? ProducerCardMyRecord(oshiIds: [], attended: [], songCount: 0)
        var input = ProducerCardAssembler.input(card: draft, record: rec)
        input.name = name
        input.message = message
        input.links = filled.map { CardLink(kind: $0.kind, value: $0.value) }
        input.qrUrl = qrUrl
        return validateProducerCard(input: input)
    }

    /// 自作の画像のデザインは表の画像が要る (無いと入場証になってしまう)。
    private var canSave: Bool {
        validation == nil && !isSaving && !(selectedDesign.usesFaceImage && facePreview[.front] == nil)
    }

    private var isDirty: Bool {
        name != card.name || message != card.message || sinceYear != card.sinceYear
            || hidden != card.hidden || draft.linksJson != card.linksJson
            || draft.cardDesign != card.cardDesign || draft.qrUrl != card.qrUrl || photoDirty || !faceDirty.isEmpty
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
            // 名刺を保存できてから写真を書く (保存に失敗して編集をやめたとき、写真だけ変わらないように)。
            if photoDirty {
                if let photoSource {
                    try ProducerCardFiles.saveMyPhoto(source: photoSource, crop: crop)
                } else {
                    ProducerCardFiles.deleteMyPhoto()
                }
            }
            for side in faceDirty {
                if let image = faceImages[side] {
                    try ProducerCardFiles.saveMyFace(image, side: side)
                } else {
                    ProducerCardFiles.deleteMyFace(side)
                }
            }
            AppAnalytics.tap("producer_card.save")
            dismiss()
        } catch {
            self.error = "保存できませんでした。\(error.localizedDescription)"
        }
    }

    // MARK: - 写真

    private func loadPhoto() {
        guard !photoDirty else { return }
        // 前に開いたときの見本の一時ファイルを片付ける。
        try? FileManager.default.removeItem(at: Self.previewFolder)
        photoSource = ProducerCardFiles.myPhotoSourceURL.flatMap { UIImage(contentsOfFile: $0.path) }
        crop = ProducerCardFiles.myPhotoCrop ?? ImasPortraitCrop()
        previewPortrait = photoSource == nil ? nil : ProducerCardFiles.myPhotoURL
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            error = "写真を読み込めませんでした。"
            return
        }
        let upright = PaperCardRectifier.upright(image)
        cropping = CropDraft(image: upright, crop: ImasPortraitCrop())
    }

    /// 切り抜きを決めた。見本には一時ファイルで出し、✓ で端末に書く。
    private func applyCrop(image: UIImage, crop: ImasPortraitCrop) async {
        avatarNotice = nil
        guard let rendered = crop.render(image), let jpeg = ProducerCardFiles.jpeg(rendered) else { return }
        let dir = Self.previewFolder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).jpg")
        guard (try? jpeg.write(to: url, options: .atomic)) != nil else { return }
        photoSource = image
        self.crop = crop
        previewPortrait = url
        photoDirty = true
    }

    /// 見本に出す切り抜き済みの写真の一時置き場。
    private static var previewFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("producer_card_edit", isDirectory: true)
    }

    private func removePhoto() {
        avatarNotice = nil
        photoSource = nil
        previewPortrait = nil
        photoDirty = true
    }

    // MARK: - X のアイコン

    /// 名刺のリンクの X の ID からアイコンを取り、名刺の写真の枠に合わせる。取れなければ案内を出す
    /// (写真から選ぶ形のまま)。
    private func useXAvatar(_ handle: String) async {
        avatarNotice = nil
        isFetchingAvatar = true
        let outcome = await XAvatarFetcher.fetch(handle: handle)
        isFetchingAvatar = false
        switch outcome {
        case .image(let image):
            AppAnalytics.tap("producer_card.x_avatar")
            cropping = CropDraft(image: PaperCardRectifier.upright(image), crop: ImasPortraitCrop())
        case .failed(let message):
            avatarNotice = message
        }
    }

    // MARK: - 自作の名刺の画像

    private func loadFaces() {
        guard faceDirty.isEmpty else { return }
        try? FileManager.default.removeItem(at: Self.faceFolder)
        for side in ProducerCardFiles.Side.allCases {
            facePreview[side] = ProducerCardFiles.myFaceURL(side)
        }
    }

    /// 写真から選んだ名刺の画像。紙の名刺を撮った写真なら四隅を見つけて平らにする (見つからなければ
    /// 画像のまま)。画像の QR は自分の QR に入れる。
    private func loadFace(_ item: PhotosPickerItem, side: ProducerCardFiles.Side) async {
        faceNotice = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            faceNotice = "画像を読み込めませんでした。"
            return
        }
        isReadingFace = true
        defer { isReadingFace = false }
        let result = await PaperCardRectifier.rectify(image)
        // 画面で作った画像は四隅が画像の縁なので見つからない。代わりに画像の中の小さな四角 (写真の枠など)
        // を拾うことがあるので、画像の半分に満たない四角では切り抜かない (四隅を直す で選び直せる)。
        let corners = result.corners.flatMap { Self.area(of: $0) >= 0.5 ? $0 : nil }
        faceSources[side] = PaperPhotoSource(original: result.original, corners: corners)
        await setFace(corners == nil ? result.original : result.image, side: side)
    }

    /// 四隅で囲んだ面積 (写真全体を 1 として)。
    private static func area(of quad: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for i in quad.indices {
            let a = quad[i], b = quad[(i + 1) % quad.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    private func applyFaceCorners(side: ProducerCardFiles.Side, source: PaperPhotoSource, corners: [CGPoint]) async {
        isReadingFace = true
        defer { isReadingFace = false }
        let flat = PaperCardRectifier.correct(source.original, corners: corners) ?? source.original
        faceSources[side] = PaperPhotoSource(original: source.original, corners: corners)
        await setFace(flat, side: side)
    }

    /// 見本には一時ファイルで出し、✓ で端末に書く。
    private func setFace(_ image: UIImage, side: ProducerCardFiles.Side) async {
        guard let jpeg = ProducerCardFiles.jpeg(image, maxPixels: 2000, quality: 0.9) else { return }
        let dir = Self.faceFolder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(side.rawValue)-\(UUID().uuidString).jpg")
        guard (try? jpeg.write(to: url, options: .atomic)) != nil else { return }
        faceImages[side] = image
        facePreview[side] = url
        faceDirty.insert(side)
        await readFaceQR(image)
    }

    private func removeFace(_ side: ProducerCardFiles.Side) {
        faceImages[side] = nil
        faceSources[side] = nil
        facePreview[side] = nil
        faceDirty.insert(side)
    }

    /// 画像に刷られた QR を読み、URL なら自分の QR に入れる (分け方はコア)。アプリの名刺の QR
    /// (自分の交換用の QR) は名刺に初めから入っているので入れない。
    private func readFaceQR(_ image: UIImage) async {
        for code in await PaperCardCodeReader.codes(in: [image]) {
            guard case .link(let url, _) = classifyScannedCode(text: code),
                  let normalized = normalizeCardQrUrl(raw: url) else { continue }
            if normalizeCardQrUrl(raw: qrUrl) != normalized {
                qrUrl = normalized
                faceNotice = "画像の QR (\(cardQrLinkView(url: normalized).display)) を自分の QR に入れました。"
            }
            return
        }
    }

    /// 自作の名刺の画像の一時置き場。
    private static var faceFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("producer_card_face_edit", isDirectory: true)
    }

    // MARK: - 写真の QR

    /// 写真に写った QR を読み、URL なら自分の QR に入れる (分け方はコア)。
    private func readQR(_ item: PhotosPickerItem) async {
        qrNotice = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            qrNotice = "写真を読み込めませんでした。"
            return
        }
        guard let code = await PhotoQRReader.firstCode(in: image) else {
            qrNotice = "写真に QR が見つかりませんでした。"
            return
        }
        switch classifyScannedCode(text: code) {
        case .link(let url, _):
            if normalizeCardQrUrl(raw: url) != nil {
                qrUrl = url
            } else {
                qrNotice = "この QR の URL は自分の QR にできません。"
            }
        case .card:
            qrNotice = "アプリの P名刺の QR です。交換用の QR は名刺に初めから入っています。"
        case .text:
            qrNotice = "URL の QR ではありません。"
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
        directory = await ProducerCardDirectory.load(idolIds: Array(ids), showIds: [])
    }
}

/// 編集画面の小さな操作 (写真を選ぶ・位置を直す・リンクから選ぶ)。
/// PhotosPicker の label は MainActor の外で組まれるので View に包む。
private struct CardEditorActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .imasText(.rowLabel, color: DS.ink)
    }
}

/// 名刺の写真を枠に合わせるシート。引いて動かし、つまんで広げ、✓ で決める。
struct CardPhotoCropSheet: View {
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
                ImasNote("引いて動かし、2 本の指で広げると、名刺の証明写真の枠に合わせられます。写真は端末の中と、名刺ファイル・近くの iPhone で渡した相手にだけ届きます (QR には入りません)。")
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
