import SwiftUI

/// プロフィール帳: P としての自己紹介を、履歴書・職務経歴書の様式の 1 枚絵にして SNS に貼る。
///
/// 名前・写真・書体・リンク・自分の QR は P名刺のもの、担当・記録はアプリから。自分で書く欄と
/// 様式・大きさは編集シート (`ProfileSheetEditorView`) で決め、端末の自分の名刺の行に持つ。
/// 欄の割り当て・行の組み立てはコア (`profileSheetLayout`)。
struct ProfileSheetView: View {
    @State private var card: MyProducerCard?
    @State private var materials = ProfileSheetMaterials.empty
    @State private var loaded = false
    @State private var editing: MyProducerCard?
    @State private var exportError: String?

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
                ImasButton(title: "画像を書き出す", systemImage: "square.and.arrow.up", role: .primary, size: .large) {
                    export(layout)
                }
                ImasNote("自分で書く欄・様式・載せる記録は右上の鉛筆から。名前・写真・書体・リンクは P名刺のものを使います。書き出した画像は共有シートから写真に保存できます。")
            }
        }
        .navigationTitle("プロフィール帳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if card != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ImasToolbarButton(systemImage: "pencil", label: "プロフィール帳を編集") { editing = card }
                }
            }
        }
        .sheet(item: $editing) { card in
            ProfileSheetEditorView(card: card, materials: materials) { sheet in
                var saved = (try await AppContainer.shared.producerCards.myCard()) ?? card
                saved.profile = sheet
                try await AppContainer.shared.producerCards.saveMyCard(saved)
                await load()
            }
        }
        .imasErrorAlert("画像を書き出せませんでした", message: $exportError)
        .task { await load() }
        .trackScreen("profile_sheet")
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
            materials = await ProfileSheetAssembler.load(card: mine, sheet: mine.profile)
        }
        card = mine
        loaded = true
    }
}
