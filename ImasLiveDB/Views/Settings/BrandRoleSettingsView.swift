import SwiftUI

/// 担当ブランドの並び (ブランドごとに なし / 担当 / メイン の段のついたスライダー)。
/// 設定の画面とはじめの案内で同じ中身。段・既定・保存の形はコア (`brandRoleSettings` / `brandRoleSet`)。
struct BrandRoleSection: View {
    @Binding var rows: [BrandRoleRow]
    var footer: String? = nil

    private let steps = brandRoleSteps()

    var body: some View {
        ImasListSection("担当ブランド", footer: footer) {
            ForEach(rows, id: \.brandId) { row in
                ImasStepSliderRow(
                    title: row.label,
                    steps: steps.map(\.label),
                    index: Binding(
                        get: { Int(brandRoleStep(role: row.role).index) },
                        set: { rows = brandRoleSet(rows: rows, brandId: row.brandId,
                                                   role: brandRoleFromIndex(index: Int64($0))) }
                    ),
                    brand: row.color
                )
                .listRowInsets(EdgeInsets())
            }
        }
    }

    static let note = "担当は丸、メインは二重丸でプロフィール帳の担当ブランドに付きます。メインはいくつでも選べます。"
}

/// 設定の「担当ブランド」。動かしたらその場で保存する (設定の画面の決まり)。
struct BrandRoleSettingsView: View {
    @State private var rows: [BrandRoleRow] = []
    @State private var configured = true
    @State private var loaded = false

    var body: some View {
        List {
            if loaded {
                BrandRoleSection(
                    rows: Binding(get: { rows }, set: { next in
                        rows = next
                        configured = true
                        BrandRoleStore.save(next)
                    }),
                    footer: configured
                        ? BrandRoleSection.note
                        : "担当アイドルと参加した公演から組んだ見立てです。動かすと決まります。" + BrandRoleSection.note
                )
            } else {
                ImasInlineLoading()
            }
        }
        .imasForm()
        .navigationTitle("担当ブランド")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .trackScreen("brand_roles")
    }

    private func load() async {
        let settings = await BrandRoleStore.load()
        rows = settings.rows
        configured = settings.configured
        loaded = true
    }
}

/// はじめの案内: 担当ブランドを選ぶ (初回起動の案内の後と、まだ決めていない人がプロフィール帳を
/// はじめて開いたときに 1 度だけ)。記録から組んだ見立てを並べて確かめてもらう。× で飛ばせる。
struct BrandRoleSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void = {}

    @State private var rows: [BrandRoleRow] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ImasNote("担当しているブランドを選んでください。プロフィール帳の担当ブランドの丸になります。あとから設定 (マイページ) で直せます。")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if loaded {
                    BrandRoleSection(rows: $rows, footer: BrandRoleSection.note)
                } else {
                    ImasInlineLoading()
                }
            }
            .imasForm()
            .navigationTitle("担当ブランド")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(canSave: loaded, onCancel: skip, onSave: save))
        }
        .task {
            rows = await BrandRoleStore.load().rows
            loaded = true
        }
        .trackScreen("brand_roles_setup")
    }

    private func skip() {
        BrandRoleStore.markPrompted()
        dismiss()
    }

    private func save() {
        BrandRoleStore.save(rows)
        AppAnalytics.tap("brand_roles.setup_save")
        onSaved()
        dismiss()
    }
}
