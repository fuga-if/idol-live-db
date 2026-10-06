import SwiftUI

/// プロフィール帳: P としての自己紹介を、履歴書・職務経歴書の様式の 1 枚絵にして SNS に貼る。
///
/// 自分で書く欄は無く、中身はすべてアプリの記録から埋まる (開いたらすぐ書き出せる)。名前・写真・
/// 書体・リンク・自分の QR は P名刺のもの。ここでは様式と大きさを選び、載せる記録と担当ブランドの丸は
/// 編集シート (`ProfileSheetEditorView`) で選ぶ。選択は端末の自分の名刺の行に持つ。
/// 欄の割り当て・行の組み立てはコア (`profileSheetLayout`)。
struct ProfileSheetView: View {
    @State private var card: MyProducerCard?
    @State private var materials = ProfileSheetMaterials.empty
    @State private var loaded = false
    @State private var editing: MyProducerCard?
    @State private var exportError: String?
    @State private var saveError: String?
    @State private var pendingSave: Task<Void, Never>?
    @State private var saveGeneration = 0

    private let styles = profileSheetStyles()
    private let sizes = profileSheetSizes()

    var body: some View {
        ImasPage {
            if !loaded {
                ImasInlineLoading()
            } else if let card {
                let sheet = card.profile
                let layout = profileSheetLayout(sheet: sheet, record: materials.record)
                ShareCardPreview(size: ProfileSheetInk.size(sheet.size)) {
                    ProfileSheetCard(layout: layout, materials: materials)
                }
                .accessibilityLabel("\(layout.title)の見本")
                ImasSegmented(options: styles.map(\.style), selection: choice(\.style)) { style in
                    styles.first { $0.style == style }?.label ?? ""
                }
                ImasSegmented(options: sizes.map(\.size), selection: choice(\.size)) { size in
                    sizes.first { $0.size == size }.map { "\($0.label) \($0.caption)" } ?? ""
                }
                ImasButton(title: "画像を書き出す", systemImage: "square.and.arrow.up", role: .primary, size: .large) {
                    export(layout)
                }
                ImasNote("中身はアプリの記録 (参加した公演・セトリ・回収・担当・お気に入り) から自動で埋まります。載せる記録と担当ブランドの丸は右上の鉛筆から。名前・写真・書体・リンクは P名刺のものを使います。")
            }
        }
        .navigationTitle("プロフィール帳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if card != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ImasToolbarButton(systemImage: "pencil", label: "載せる記録を選ぶ") { editing = card }
                }
            }
        }
        .sheet(item: $editing) { card in
            ProfileSheetEditorView(card: card, materials: materials) { sheet in
                await pendingSave?.value
                try await persist(sheet)
                self.card?.profile = sheet
            }
        }
        .imasErrorAlert("画像を書き出せませんでした", message: $exportError)
        .imasErrorAlert("保存できませんでした", message: $saveError)
        .task { await load() }
        .trackScreen("profile_sheet")
    }

    /// 様式・大きさの切り替え。選んだらその場で保存する (書き出しまで 1 画面で済ませる)。
    /// 続けて切り替えても保存は順に 1 本ずつ流し (古い選択が後から書かれないように)、
    /// 失敗したときは最後に押した分だけ前の選択に戻す。
    private func choice<Value>(_ key: WritableKeyPath<ProfileSheet, Value>) -> Binding<Value> {
        Binding(
            get: { (card?.profile ?? profileSheetDefault())[keyPath: key] },
            set: { value in
                guard let previous = card?.profile else { return }
                var sheet = previous
                sheet[keyPath: key] = value
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
        )
    }

    /// 自分の名刺の行にプロフィール帳の選択を書く (名刺のほかの欄は DB の最新を使う)。
    private func persist(_ sheet: ProfileSheet) async throws {
        guard let card else { return }
        var saved = (try await AppContainer.shared.producerCards.myCard()) ?? card
        saved.profile = sheet
        try await AppContainer.shared.producerCards.saveMyCard(saved)
    }

    private func export(_ layout: ProfileSheetLayout) {
        guard let image = ProfileSheetAssembler.render(layout: layout, materials: materials) else {
            exportError = "もう一度試すか、アプリを再起動してください。"
            return
        }
        AppAnalytics.tap("profile_sheet.export")
        SystemShare.present(items: [ShareCardImageSource(image)])
    }

    private func load() async {
        let mine = try? await AppContainer.shared.producerCards.myCard()
        // 材料を読み終えてから名刺を入れる (読み込み中に編集シートを空の材料で開かせない)。
        if let mine {
            materials = await ProfileSheetAssembler.load(card: mine)
        }
        card = mine
        loaded = true
    }
}
