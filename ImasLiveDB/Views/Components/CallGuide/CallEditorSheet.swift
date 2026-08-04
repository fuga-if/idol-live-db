import SwiftUI

/// コール 1 件の入力/編集。歌詞タブで範囲を選んだ直後、または既存コールをタップしたときに出る。
///
/// パレットは**近道**でしかないので、自由入力を常に受ける (実際のコールは曲ごと・現場ごとに
/// 違い、固定リストで賄えない)。パレットのタップは置き換えではなく**末尾に足す** —
/// `(Hi!) (Hi!) (Fuu--!)` のような連なりが実物では普通だから。
struct CallEditorSheet: View {
    /// 何に対する編集かを 1 個の値で運ぶ (`.sheet(item:)` にそのまま渡せる形)。
    struct Request: Identifiable {
        let id = UUID()
        let lineId: String
        /// アンカー開始 (スカラー単位)。アンカー無し (marker 行) は start == end == 0。
        let start: Int
        let end: Int
        let anchorText: String
        /// 既存コールの編集なら中身。新規なら nil。
        let existing: LyricCall?
    }

    let request: Request
    var seed: String?
    /// 保存 (新規なら追加、既存なら更新)。
    let onSubmit: (String, CallEmphasis) -> Void
    /// 既存コールの削除。新規のときは呼ばれない。
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var text: String = ""
    @State private var emphasis: CallEmphasis = .normal
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp5) {
                    anchorSection
                    inputSection
                    emphasisSection
                    paletteSection
                    if onDelete != nil { deleteButton }
                }
                .padding(DS.sp5)
            }
            .background(DS.bg)
            .navigationTitle(request.existing == nil ? "コールを追加" : "コールを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines), emphasis)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            text = request.existing?.text ?? ""
            emphasis = request.existing?.emphasis ?? .normal
            focused = true
        }
    }

    // MARK: - アンカー

    @ViewBuilder
    private var anchorSection: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text("アンカー").font(.imasCaption).foregroundStyle(DS.ink2)
            if request.anchorText.isEmpty {
                Text("歌詞なし（この行に直接ぶら下がるコール）")
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
            } else {
                Text(request.anchorText)
                    .font(.imasBody.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - 入力

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text("コール文言").font(.imasCaption).foregroundStyle(DS.ink2)
            TextField("(Hi!) など", text: $text, axis: .vertical)
                .font(.imasBody)
                .lineLimit(1...4)
                .focused($focused)
                .padding(DS.sp4)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            Text("繰り返しは「× 26」のように文言へ直接書く。")
                .font(.imasCaption2)
                .foregroundStyle(DS.ink3)
        }
    }

    // MARK: - 強調

    private var emphasisSection: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text("強調").font(.imasCaption).foregroundStyle(DS.ink2)
            ImasSegmented(options: CallEmphasis.allCases, selection: $emphasis, seed: seed) { $0.label }
            HStack(spacing: DS.sp2) {
                Circle().fill(emphasis.color).frame(width: 8, height: 8)
                Text(emphasisHint).font(.imasCaption2).foregroundStyle(DS.ink3)
            }
        }
    }

    private var emphasisHint: String {
        switch emphasis {
        case .normal:           return "通常のコール。凡例には出ない。"
        case .optional:         return "おこのみで（緑）。やってもやらなくてもよい。"
        case .performerRequest: return "演者要望（赤）。演者から明示的に求められたもの。"
        }
    }

    // MARK: - パレット

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            Text("パレット（タップで末尾に追加）")
                .font(.imasCaption).foregroundStyle(DS.ink2)
            if let lyricCall = CallPalette.lyricCall(anchorText: request.anchorText) {
                paletteGroup(title: "歌詞コール", items: [lyricCall])
            }
            ForEach(CallPalette.groups) { group in
                paletteGroup(title: group.title, items: group.items)
            }
        }
    }

    private func paletteGroup(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            Text(title).font(.imasCaption2.weight(.semibold)).foregroundStyle(DS.ink3)
            CallGuideFlowLayout(itemSpacing: DS.sp2, lineSpacing: DS.sp2) {
                ForEach(items, id: \.self) { item in
                    Button { append(item) } label: {
                        ImasChip(text: item, style: .themed, seed: seed)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func append(_ item: String) {
        text = text.isEmpty ? item : text + " " + item
    }

    // MARK: - 削除

    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete?()
            dismiss()
        } label: {
            Label("このコールを削除", systemImage: "trash")
                .font(.imasSubhead.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(DS.danger)
                .background(DS.danger.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
