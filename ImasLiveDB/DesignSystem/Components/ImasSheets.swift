import SwiftUI

// =============================================================================
// シート・フォーム・一覧のまわり (docs/DESIGN_SYSTEM.md §2.1・§2.4〜§2.7・§16)
//
// .imasSheetToolbar(_:)       シートのボタンの置き場所を 1 か所で決める。文字は書かず × と ✓ の記号
//                             (iOS 26 は OS のガラスの丸、17/18 は記号のボタン)。読み上げは言葉で。
// .imasForm()                 編集シート・設定の Form / List(.insetGrouped) の体裁。
// .imasDiscardConfirmation    書きかけを閉じるときの確認。
// ImasListSection             List・Form の区画 (見出し・補足を DS の形で)。
// ImasFilterBar               一覧の頭に、効いている絞り込みを外せるチップで並べる。
// ImasListSummary             一覧の件数と並び順。
// ImasSelectionTray           複数選択で選んだものを下に並べる。
// =============================================================================

// MARK: - シートのボタン

/// シートの種類。種類ごとに左右のボタンの文言が決まっている (§16)。
enum ImasSheetToolbarKind {
    /// 編集・追加。左 = キャンセル、右 = 保存。
    case edit(canSave: Bool = true, onCancel: () -> Void, onSave: () -> Void)
    /// 投稿・投票・修正リクエスト (みんなに見える)。左 = キャンセル、右 = 送信。
    /// `isSubmitting` の間は送信の記号の代わりにくるくるを出し、連打できないようにする。
    case submit(canSubmit: Bool = true, isSubmitting: Bool = false, onCancel: () -> Void, onSubmit: () -> Void)
    /// 複数を選ぶ。左 = キャンセル、右 = 完了。
    case select(canFinish: Bool = true, onCancel: () -> Void, onFinish: () -> Void)
    /// 読むだけ。右 = 閉じる。
    case read(onClose: () -> Void)
    /// 後で答えてよい問いかけ (チケット代の記録など)。左 = あとで、右 = 記録する (§16)。
    case prompt(canRecord: Bool = true, onLater: () -> Void, onRecord: () -> Void)
}

extension View {
    /// シートのツールバー。文言と置き場所は種類が決める。画面で「閉じる」「完了」を書かない。
    func imasSheetToolbar(_ kind: ImasSheetToolbarKind) -> some View {
        toolbar { ImasSheetToolbarContent(kind: kind) }
    }
}

/// 種類から左右のボタンを決める。5 種類を 1 つの `toolbar { switch }` に書くと、古いコンパイラ
/// (CI の macos-15) が型を決めきれずに止まるので、ボタンの中身を値 (`Spec`) にしてから並べる。
private struct ImasSheetToolbarContent: ToolbarContent {
    let kind: ImasSheetToolbarKind

    struct Spec {
        let title: String
        let role: ImasSheetButton.Role
        var isLoading: Bool = false
        var isEnabled: Bool = true
        let action: () -> Void
    }

    /// 左 (取り消し側)。読むだけのシートには無い。
    private var cancel: Spec? {
        switch kind {
        case let .edit(_, onCancel, _): return Spec(title: "キャンセル", role: .cancel, action: onCancel)
        case let .submit(_, _, onCancel, _): return Spec(title: "キャンセル", role: .cancel, action: onCancel)
        case let .select(_, onCancel, _): return Spec(title: "キャンセル", role: .cancel, action: onCancel)
        case .read: return nil
        case let .prompt(_, onLater, _): return Spec(title: "あとで", role: .cancel, action: onLater)
        }
    }

    /// 右 (確定側)。
    private var confirm: Spec {
        switch kind {
        case let .edit(canSave, _, onSave):
            return Spec(title: "保存", role: .confirm, isEnabled: canSave, action: onSave)
        case let .submit(canSubmit, isSubmitting, _, onSubmit):
            return Spec(title: "送信", role: .confirm, isLoading: isSubmitting,
                        isEnabled: canSubmit && !isSubmitting, action: onSubmit)
        case let .select(canFinish, _, onFinish):
            return Spec(title: "完了", role: .confirm, isEnabled: canFinish, action: onFinish)
        case let .read(onClose):
            return Spec(title: "閉じる", role: .close, action: onClose)
        case let .prompt(canRecord, _, onRecord):
            return Spec(title: "記録する", role: .confirm, isEnabled: canRecord, action: onRecord)
        }
    }

    var body: some ToolbarContent {
        if let cancel {
            ToolbarItem(placement: .cancellationAction) { button(cancel) }
        }
        ToolbarItem(placement: .confirmationAction) { button(confirm) }
    }

    private func button(_ spec: Spec) -> some View {
        ImasSheetButton(title: spec.title, role: spec.role, isLoading: spec.isLoading, action: spec.action)
            .disabled(!spec.isEnabled)
    }
}

/// シートのボタン 1 つ。文字は書かず記号 (× / ✓) だけ。`title` は読み上げに使う。
/// iOS 26 はロールを付けた OS のガラスの丸 (確定は塗り)、17/18 は記号のボタン。
private struct ImasSheetButton: View {
    enum Role { case cancel, confirm, close }
    let title: String
    let role: Role
    /// 送信・保存の処理中。記号の代わりに砂時計がわりのくるくるを出す (17/18 のみ)。
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        // ButtonRole の .confirm / .close と label の無い Button(role:action:) は iOS 26 の SDK にしか無い。
        // CI (macos-15) の古い SDK でもビルドできるよう、コンパイラの版で分ける。
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            Button(role: buttonRole, action: action)
                .accessibilityLabel(title)
        } else {
            symbolButton
        }
        #else
        symbolButton
        #endif
    }

    /// 17/18 (と古い SDK) の記号のボタン。
    private var symbolButton: some View {
        Button(action: action) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: role == .confirm ? "checkmark" : "xmark")
                    .font(.imasScaled(17, weight: role == .confirm ? .bold : .semibold))
            }
        }
        .accessibilityLabel(title)
    }

    #if compiler(>=6.2)
    @available(iOS 26, *)
    private var buttonRole: ButtonRole {
        switch role {
        case .cancel: return .cancel
        case .confirm: return .confirm
        case .close: return .close
        }
    }
    #endif
}

// MARK: - フォーム

extension View {
    /// 編集シート・設定の Form / List の体裁 (地の色・行の面・区切り線の色)。
    func imasForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .listRowSeparatorTint(DS.sep)
            .environment(\.imasBackdrop, .grouped)
    }

    /// 曲・ライブ・アイドルなど「もの」の一覧 (List) の体裁。白い紙面に行を並べ、線は本文の頭から。
    func imasList() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.paper)
            .listRowSeparatorTint(DS.sep)
            .environment(\.imasBackdrop, .paper)
    }

    /// 書きかけのまま閉じようとしたときに確かめる。閉じる操作を `attempt` で包んで使う。
    func imasDiscardConfirmation(isPresented: Binding<Bool>, onDiscard: @escaping () -> Void) -> some View {
        confirmationDialog("変更を破棄しますか？", isPresented: isPresented, titleVisibility: .visible) {
            Button("変更を破棄", role: .destructive, action: onDiscard)
            Button("編集を続ける", role: .cancel) {}
        }
    }
}

/// フォームの 1 行入力。項目名 + 入力 + 誤りの文。
struct ImasTextFieldRow: View {
    let title: String
    @Binding var text: String
    var prompt: String? = nil
    /// 入力の下に出す誤り (「URL の形になっていません」)。nil なら出さない。
    var error: String? = nil
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            LabeledContent {
                TextField(prompt ?? title, text: $text)
                    .font(ImasTextRole.value.font)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboard)
            } label: {
                Text(title).imasText(.value, color: DS.ink2)
            }
            if let error {
                Text(error)
                    .font(.imasFootnote)
                    .foregroundStyle(DS.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listRowBackground(DS.surface)
    }
}

/// 複数行の入力 (メモ・説明・補足)。
struct ImasTextAreaRow: View {
    @Binding var text: String
    var prompt: String
    var minHeight: CGFloat = 120
    /// 行数の下限。既定は 4 行分の高さを確保する (メモ・感想などの長文)。
    var minLines: Int = 4
    /// 行数の上限。nil なら上限なし (打つだけ伸びる)。座席のような短い欄は上限を決める。
    var maxLines: Int? = nil
    /// 文字数の上限。nil なら数えない。
    var limit: Int? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.gapTight) {
            textField
                .frame(minHeight: minHeight, alignment: .topLeading)
            if let limit {
                // 送信を止める条件 (前後の空白・改行を除いた数) と同じ数え方にする。
                // 生の文字数で数えると、改行だけ打った分で上限に見えるのに送信は通る
                // (またはその逆) というズレが出る。
                let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
                Text("\(count) / \(limit)")
                    .font(.imasCaption.monospacedDigit())
                    .foregroundStyle(count > limit ? DS.danger : DS.ink3)
            }
        }
        .listRowBackground(DS.surface)
    }

    @ViewBuilder private var textField: some View {
        let field = TextField(prompt, text: $text, axis: .vertical).font(ImasTextRole.body.font)
        if let maxLines {
            field.lineLimit(minLines...maxLines)
        } else {
            field.lineLimit(minLines...)
        }
    }
}

// MARK: - List・Form の区画

/// List・Form の区画。見出しは DS の小さい見出し、補足は `ImasNote`、行の面は `DS.surface`。
struct ImasListSection<Content: View>: View {
    var title: String? = nil
    var count: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    init(_ title: String? = nil, count: String? = nil, footer: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.footer = footer
        self.content = content()
    }

    @Environment(\.imasBackdrop) private var backdrop

    var body: some View {
        Section {
            content
                .listRowBackground(backdrop == .paper ? DS.paper : DS.surface)
                .listRowSeparatorTint(DS.sep)
        } header: {
            if let title {
                ImasSectionHeader(title, count: count, style: .small)
                    .textCase(nil)
            }
        } footer: {
            if let footer {
                ImasNote(footer)
            }
        }
    }
}

// MARK: - 一覧の頭

/// 効いている絞り込みを外せるチップで 1 段に並べる。何も効いていなければ何も出さない。
struct ImasFilterBar: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        var seed: String? = nil
        var brand: String? = nil
        let onRemove: () -> Void
    }

    let items: [Item]
    /// 2 つ以上効いているときに「すべて解除」を出す。
    var onClearAll: (() -> Void)? = nil

    var body: some View {
        if !items.isEmpty {
            ImasChipRow {
                ForEach(items) { item in
                    ImasRemovableChip(text: item.title, seed: item.seed, brand: item.brand, onRemove: item.onRemove)
                }
                if items.count >= 2, let onClearAll {
                    Button("すべて解除", action: onClearAll)
                        .buttonStyle(.imas(.plain, size: .small))
                }
            }
            .padding(.vertical, DS.Space.gapTight)
        }
    }
}

/// 一覧の件数と並び順。並び順はメニューで選ぶ。
struct ImasListSummary<Sort: Hashable>: View {
    let count: Int
    var unit: String = "件"
    var sortOptions: [Sort] = []
    var sortSelection: Binding<Sort>? = nil
    var sortLabel: (Sort) -> String = { "\($0)" }
    /// 昇順・降順の方向トグル (任意)。渡すとメニューに「方向」の項目が増え、
    /// ボタンの記号もその向きになる。渡さなければ軸の切り替えだけ (双方向の矢印)。
    var sortAscending: Binding<Bool>? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            ImasMetric(value: "\(count)", unit: unit, size: .small)
            Spacer(minLength: DS.Space.gap)
            if let sortSelection, !sortOptions.isEmpty {
                Menu {
                    Picker("並び順", selection: sortSelection) {
                        ForEach(sortOptions, id: \.self) { Text(sortLabel($0)).tag($0) }
                    }
                    if let sortAscending {
                        Picker("方向", selection: sortAscending) {
                            Label("昇順", systemImage: "arrow.up").tag(true)
                            Label("降順", systemImage: "arrow.down").tag(false)
                        }
                    }
                } label: {
                    HStack(spacing: DS.Space.gapTight) {
                        Image(systemName: sortAscending.map { $0.wrappedValue ? "arrow.up" : "arrow.down" }
                              ?? "arrow.up.arrow.down")
                        Text(sortLabel(sortSelection.wrappedValue))
                    }
                    .font(.imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: DS.Size.chip)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.rControl(DS.Size.chip), style: .continuous)
                            .strokeBorder(DS.line, lineWidth: 1)
                    }
                }
                .accessibilityLabel(sortAccessibilityLabel(sortSelection, sortAscending))
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.vertical, DS.Space.gapTight)
    }

    /// 「並び替え: 〇〇順、昇順/降順」。方向トグルを渡していない画面では軸名だけ読む。
    private func sortAccessibilityLabel(_ selection: Binding<Sort>, _ ascending: Binding<Bool>?) -> String {
        let base = "並び替え: \(sortLabel(selection.wrappedValue))"
        guard let ascending else { return base }
        return "\(base)、\(ascending.wrappedValue ? "昇順" : "降順")"
    }
}

extension ImasListSummary where Sort == Never {
    /// 並べ替えの無い一覧 (件数だけ)。型引数を書かずに `ImasListSummary(count:unit:)` と呼べるようにする。
    init(count: Int, unit: String = "件") {
        // 並べ替えの引数を 1 つ明示して、この init 自身ではなく既定の init を呼ぶ。
        self.init(count: count, unit: unit, sortOptions: [])
    }
}

// MARK: - 選んだもの

/// 複数選択のシートの下に、選んだものを外せるチップで並べる。
struct ImasSelectionTray<Item: Identifiable>: View {
    let items: [Item]
    let title: (Item) -> String
    var seed: (Item) -> String? = { _ in nil }
    let onRemove: (Item) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text("選んだもの \(items.count)")
                    .imasText(.sectionLabel)
                    .padding(.horizontal, DS.Space.screen)
                ImasChipRow {
                    ForEach(items) { item in
                        ImasRemovableChip(text: title(item), seed: seed(item)) { onRemove(item) }
                    }
                }
            }
            .padding(.vertical, DS.Space.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}
