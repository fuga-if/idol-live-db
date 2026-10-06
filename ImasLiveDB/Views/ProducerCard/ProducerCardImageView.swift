import SwiftUI

/// SNS に貼る P名刺の画像: 自分の P名刺と記録を、履歴書の様式の 1 枚絵にする (P名刺の 3 つ目の出し方)。
///
/// 開くとすぐできあがりの見本が上に固定で見え、選ぶのは大きさ (4:5 / 9:16) と載せる項目の付け外しだけ。
/// 中身はすべて P名刺とアプリの記録から入る: 名前・P歴・写真・リンク・自分の QR・好きな曲は P名刺
/// (直すのは P名刺の編集)、担当ブランドの丸はアプリ全体の設定 (`BrandRoleStore`)、参加した公演・回収は記録。
/// 名刺 (交換するもの) に載せない記録の数も、ここ (見せるもの) には載る。
/// 選んだものはその場で自分の名刺の行に保存する。欄の一覧と値・付け外しはコア
/// (`profileAutoFieldRows` / `profileToggleField`、組みは `profileSheetLayout`)。
struct ProducerCardImageView: View {
    @State private var card: MyProducerCard?
    @State private var materials = ProfileSheetMaterials.empty
    @State private var loaded = false
    @State private var showingBrandSetup = false
    @State private var saveError: String?
    @State private var exportError: String?
    @State private var pendingSave: Task<Void, Never>?
    @State private var saveGeneration = 0

    private let sizes = profileSheetSizes()

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
                            title: "まだ P名刺がありません",
                            message: "P名刺を作ると、名前・写真・好きな曲と参加の記録から画像ができます。"
                        )
                    }
                }
            }
        }
        .navigationTitle("SNS に貼る画像")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let card {
                ToolbarItem(placement: .topBarTrailing) {
                    ImasToolbarButton(systemImage: "square.and.arrow.up", label: "画像を書き出す") {
                        export(card.profile)
                    }
                }
            }
        }
        .sheet(isPresented: $showingBrandSetup) {
            BrandRoleSetupSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .brandRolesChanged)) { _ in
            materials.record.brandRolesJson = BrandRoleStore.json
        }
        .imasErrorAlert("保存できませんでした", message: $saveError)
        .imasErrorAlert("画像を書き出せませんでした", message: $exportError)
        .task {
            guard !loaded else { return }
            await load()
            // 担当ブランドをまだ決めていなければ、はじめて開いたときに 1 度だけ確かめてもらう (画像に丸が付く)。
            if card != nil, BrandRoleStore.shouldPrompt {
                BrandRoleStore.markPrompted()
                showingBrandSetup = true
            }
        }
        .trackScreen("producer_card_image")
    }

    // MARK: - 見本と選ぶもの

    private func chooser(_ card: MyProducerCard) -> some View {
        let sheet = card.profile
        let layout = profileSheetLayout(sheet: sheet, record: materials.record)
        let rows = profileAutoFieldRows(sheet: sheet, record: materials.record)
        return List {
            ImasListSection("大きさ") {
                ImasSegmented(options: sizes.map(\.size), selection: sizeBinding) { size in
                    sizes.first { $0.size == size }.map { "\($0.label) \($0.caption)" } ?? ""
                }
            }
            ImasListSection("載せる項目",
                            footer: "記録の無いものは並びません。名前・P歴・写真・リンク・自分の QR・好きな曲は P名刺の編集で、担当ブランドは設定で直せます。") {
                ForEach(rows, id: \.key) { row in
                    ImasToggleRow(title: row.label, subtitle: subtitle(row),
                                  isOn: Binding(get: { row.shown }, set: { _ in toggleField(row.field) }))
                }
            }
            Section {
                ImasButton(title: "画像を書き出す", systemImage: "square.and.arrow.up", role: .primary, size: .large) {
                    export(sheet)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .imasForm()
        .imasPinnedPreview {
            ShareCardPreview(size: ProfileSheetInk.size(sheet.size)) {
                ProfileSheetCard(layout: layout, materials: materials)
            }
            .accessibilityElement()
            .accessibilityLabel("\(layout.title)の見本")
        }
    }

    /// 行の副題: 中身の出どころ (P名刺・設定) と今の値。
    private func subtitle(_ row: ProfileAutoFieldRow) -> String? {
        let from: String? = switch row.field {
        case .brands: "設定の担当ブランドから"
        case .songs: "P名刺の好きな曲から"
        default: row.fromCard ? "P名刺から" : nil
        }
        let parts = [from, row.value.isEmpty ? nil : row.value].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var sizeBinding: Binding<ProfileSheetSize> {
        Binding(
            get: { (card?.profile ?? profileSheetDefault()).size },
            set: { size in
                guard var sheet = card?.profile else { return }
                sheet.size = size
                update(sheet)
            }
        )
    }

    private func export(_ sheet: ProfileSheet) {
        let layout = profileSheetLayout(sheet: sheet, record: materials.record)
        guard let image = ProfileSheetAssembler.render(layout: layout, materials: materials) else {
            exportError = "もう一度試すか、アプリを再起動してください。"
            return
        }
        AppAnalytics.tap("producer_card_image.export")
        SystemShare.present(items: [ShareCardImageSource(image)])
    }

    // MARK: - 保存

    private func toggleField(_ field: ProfileAutoField) {
        guard let current = card?.profile else { return }
        update(profileToggleField(sheet: current, field: field))
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

    /// 自分の名刺の行に画像の選択 (大きさ・載せる項目) を書く。名刺のほかの欄と好きな曲は DB の最新を使う
    /// (好きな曲は P名刺の編集で直すので、ここで開いた時の古い選択で戻さない)。
    private func persist(_ sheet: ProfileSheet) async throws {
        guard let card else { return }
        var saved = (try await AppContainer.shared.producerCards.myCard()) ?? card
        var next = sheet
        next.songs = saved.profile.songs
        saved.profile = next
        try await AppContainer.shared.producerCards.saveMyCard(saved)
    }

    private func load() async {
        let mine = try? await AppContainer.shared.producerCards.myCard()
        // 材料を読み終えてから名刺を入れる (読み込み中に空の材料で並べない)。
        if let mine {
            materials = await ProfileSheetAssembler.load(card: mine)
        }
        card = mine
        loaded = true
    }
}
