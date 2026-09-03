import SwiftUI

/// コール 1 件の入力/編集。歌詞タブで範囲を選んだ直後、行末の ＋ を押したとき、
/// または既存コールをタップしたときに出る。
///
/// パレットは**近道**でしかないので、自由入力を常に受ける (実際のコールは曲ごと・現場ごとに
/// 違い、固定リストで賄えない)。パレットのタップは置き換えではなく**末尾に足す** —
/// `(Hi!) (Hi!) (Fuu--!)` のような連なりが実物では普通だから。
struct CallEditorSheet: View {
    /// 何に対する編集かを 1 個の値で運ぶ (`.sheet(item:)` にそのまま渡せる形)。
    struct Request: Identifiable {
        let id = UUID()
        let lineId: String
        /// アンカー開始 (スカラー単位)。幅ゼロ (`start == end`) は行末の追っかけ、
        /// または marker 行に直接ぶら下がるコール。
        let start: Int
        let end: Int
        let anchorText: String
        /// アンカーが乗っている行の本文。**どこに掛かるのかを行ごと見せる**ために持つ。
        /// 語だけを出しても、同じ語が行に 2 回出てくるとどちらか分からない。
        let lineText: String
        /// 既存コールの編集なら中身。新規なら nil。
        let existing: LyricCall?

        /// 歌詞の一部に掛かる (= 被せるか追っかけるかを選べる) アンカーか。
        var hasAnchor: Bool { end > start }
    }

    let request: Request
    var seed: String?
    /// 保存 (新規なら追加、既存なら更新)。
    let onSubmit: (String, CallEmphasis, CallTiming) -> Void
    /// 既存コールの削除。新規のときは呼ばれない。
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var text: String = ""
    @State private var emphasis: CallEmphasis = .normal
    @State private var timing: CallTiming = .after
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp5) {
                    anchorSection
                    inputSection
                    timingSection
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
                        onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines),
                                 emphasis, request.hasAnchor ? timing : .after)
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
            // 既定は追っかけ (アイマスではこちらが主)。
            timing = request.existing?.timing ?? .after
            focused = true
        }
    }

    // MARK: - アンカー

    @ViewBuilder
    private var anchorSection: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text("アンカー").font(.imasCaption).foregroundStyle(DS.ink2)
            if request.anchorText.isEmpty {
                Label("行末（追っかけ）— 歌詞に被せず、この行の後で返すコール",
                      systemImage: "arrow.turn.down.right")
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // 行ごと出して、その中でアンカーを光らせる。
                // シートは歌詞を覆うので、後ろの行に色を敷いても見えない
                // (`.medium` でも隠れる位置にあることを実機で確認した)。
                // 語だけを出す形だと、同じ語が行に 2 回出てくるとどちらか分からない。
                Text(CallGuideText.attributed(
                    request.lineText,
                    highlights: [.init(start: request.start, end: request.end,
                                       color: ImasTheme.derive(seed: seed, scheme: scheme).accent,
                                       isPending: true)]
                ))
                .font(.imasBody)
                .foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - タイミング

    /// 被せる / 追っかける の選択。
    ///
    /// アンカー範囲は「どのフレーズに対するコールか」しか表さないので、タイミングは別に選ばせる。
    /// **幅ゼロのアンカー (行末追加) では出さない** — 被せる相手が無く、選択肢を出しても
    /// 常に追っかけにしかならないから (サーバも `start == end` を `after` に倒す)。
    @ViewBuilder
    private var timingSection: some View {
        if request.hasAnchor {
            VStack(alignment: .leading, spacing: DS.sp2) {
                Text("タイミング").font(.imasCaption).foregroundStyle(DS.ink2)
                ImasSegmented(options: CallTiming.allCases, selection: $timing, seed: seed) { $0.label }
                Text(timing.hint).font(.imasCaption2).foregroundStyle(DS.ink3)
            }
        }
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
                Circle()
                    .fill(emphasis.color(accent: ImasTheme.derive(seed: seed, scheme: scheme).accent))
                    .frame(width: 8, height: 8)
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
