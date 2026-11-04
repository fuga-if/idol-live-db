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

    /// 入力の結果。`penlight` が非 nil ならペンライトの指示 (`text` は古いアプリ向けの代わりの文言)。
    struct Result {
        let text: String
        let emphasis: CallEmphasis
        let timing: CallTiming
        let penlight: LyricPenlight?
    }

    /// 叫ぶコールか、ペンライトの指示か。
    enum Kind: Hashable, CaseIterable {
        case call, penlight

        var label: String {
            switch self {
            case .call:     return "コール"
            case .penlight: return "ペンライト"
            }
        }
    }

    let request: Request
    var seed: String?
    /// ペンライトの「アイドルの色」の選択肢 (この曲の原唱者)。
    var cast: LyricPartCast = .empty
    /// 保存 (新規なら追加、既存なら更新)。
    let onSubmit: (Result) -> Void
    /// 既存コールの削除。新規のときは呼ばれない。
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var text: String = ""
    @State private var emphasis: CallEmphasis = .normal
    @State private var timing: CallTiming = .after
    @State private var kind: Kind = .call
    @State private var penlight = LyricPenlight()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp5) {
                    anchorSection
                    ImasSegmented(options: Kind.allCases, selection: $kind, seed: seed) { $0.label }
                    switch kind {
                    case .call:
                        inputSection
                        timingSection
                        emphasisSection
                        paletteSection
                    case .penlight:
                        CallEditorPenlightSection(penlight: $penlight, seed: seed, cast: cast)
                    }
                    if onDelete != nil { deleteButton }
                }
                .padding(DS.sp5)
            }
            .background(DS.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onSubmit(result)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            text = request.existing?.text ?? ""
            emphasis = request.existing?.emphasis ?? .normal
            // 既定は追っかけ (アイマスではこちらが主)。
            timing = request.existing?.timing ?? .after
            if let existing = request.existing?.penlight {
                kind = .penlight
                penlight = existing
            } else {
                focused = true
            }
        }
    }

    private var title: String {
        let isNew = request.existing == nil
        switch kind {
        case .call:     return isNew ? "コールを追加" : "コールを編集"
        case .penlight: return isNew ? "ペンライトを追加" : "ペンライトを編集"
        }
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 入力し終えた形。ペンライトはメモの空白を落とし、古いアプリ向けの文言をコアで作る。
    private var cleanedPenlight: LyricPenlight {
        var cue = penlight
        let note = (cue.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        cue.note = note.isEmpty ? nil : note
        return cue
    }

    private var canSubmit: Bool {
        switch kind {
        case .call:     return !trimmedText.isEmpty
        case .penlight: return !cleanedPenlight.isEmpty
        }
    }

    private var result: Result {
        switch kind {
        case .call:
            return Result(text: trimmedText, emphasis: emphasis,
                          timing: request.hasAnchor ? timing : .after, penlight: nil)
        case .penlight:
            let cue = cleanedPenlight
            // 語に掛けたペンライトはそのフレーズで振る (被せ)。行末は歌い終わってから。
            return Result(text: PenlightLook(penlight: cue, cast: cast).description, emphasis: .normal,
                          timing: request.hasAnchor ? .over : .after, penlight: cue)
        }
    }

    // MARK: - アンカー

    @ViewBuilder
    private var anchorSection: some View {
        ImasCard {
            VStack(alignment: .leading, spacing: DS.sp2) {
                Text("アンカー").imasText(.sectionLabel)
                if request.anchorText.isEmpty {
                    Label("行末（追っかけ）— 歌詞に被せず、この行の後で返すコール",
                          systemImage: "arrow.turn.down.right")
                        .imasText(.value, color: DS.ink2)
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
                    .imasText(.body)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            Text("コール文言").imasText(.sectionLabel)
            ImasCard {
                TextField("(Hi!) など", text: $text, axis: .vertical)
                    .imasText(.body)
                    .lineLimit(1...4)
                    .focused($focused)
            }
            ImasNote("繰り返しは「× 26」のように文言へ直接書く。")
        }
    }

    // MARK: - 強調

    private var emphasisSection: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text("コールの種類").font(.imasCaption).foregroundStyle(DS.ink2)
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
        case .normal:           return "みんなで入れる基本のコール。"
        case .optional:         return "おこのみで（緑）。入れても入れなくてもよいコール。"
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
            FlowLayout(spacing: DS.sp2, lineSpacing: DS.sp2) {
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
        ImasButton(title: kind == .penlight ? "このペンライトを削除" : "このコールを削除", systemImage: "trash", role: .destructive, size: .medium, fillsWidth: true) {
            onDelete?()
            dismiss()
        }
    }
}
