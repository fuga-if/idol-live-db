import SwiftUI

// =============================================================================
// 申込書 (編集シートの欄) (docs/DESIGN_SYSTEM.md §2.4・§7)
//
// ImasFormPage       編集シートの本体。地・左右の余白・欄のまとまりの間隔。キーボードは引いて閉じる。
// ImasFormCard       欄をまとめる 1 枚の紙。欄の間は切り取り線。
// ImasFormField      欄 1 つ。上に印字の見出し (「DATE · 日程」)、下に値。誤りは朱で。
// ImasFormTextField  1 行の入力の欄。
// ImasFormTextArea   複数行の入力の欄 (メモ・感想)。
// ImasFormToggle     オン・オフの欄。
// ImasFormLink       押して別のシート・選択へ行く欄 (会場・日程)。値と矢印。
// ImasFormAmount     金額の欄。「¥」と細長い数字。
// ImasChoiceCards    大きな札から 1 つ選ぶ (参加のしかた: 現地・配信・LV)。選んだ札に穴が開く。
//
// OS の Form (灰の表) は設定画面だけ。ものを編集するシートはこの申込書で組む。
// =============================================================================

// MARK: - 本体

/// 編集シートの本体。地・左右の余白・欄のまとまりの間隔を持つ。中身は縦に並べる。
struct ImasFormPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                content
            }
            .padding(.horizontal, DS.Space.screen)
            .padding(.top, DS.Space.gap)
            .padding(.bottom, DS.Space.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.bg)
        .environment(\.imasBackdrop, .grouped)
        .readableContentMargins()
    }
}

// MARK: - 欄のまとまり

/// 欄をまとめる 1 枚の紙。欄 (`ImasFormField` の仲間) を縦に並べる。欄の間は切り取り線。
struct ImasFormCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            // 欄はそれぞれ上に切り取り線を引く。1 つ目の欄の線 (紙の上端) だけを隠す。
            .mask { Rectangle().padding(.top, 2) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
            .imasSurfaceEdge(cornerRadius: DS.rCard)
    }
}

// MARK: - 欄

/// 欄 1 つ。上に印字の見出し、下に値。値は自由に組める (入力・文字・選択)。
struct ImasFormField<Content: View>: View {
    let label: String
    /// 見出しの前の英字 (「DATE」)。日本語の見出しの前に「DATE · 日程」と並ぶ。
    var imprint: String? = nil
    var systemImage: String? = nil
    /// 欄の下の誤り (「URL の形になっていません」)。
    var error: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.imasScaled(11, weight: .semibold))
                }
                Text([imprint, label].compactMap { $0 }.joined(separator: " · "))
                    .imasText(.imprint)
            }
            .foregroundStyle(DS.ink2)
            .accessibilityHidden(true)
            content
                .font(.imasHeading(17, weight: .bold))
                .foregroundStyle(DS.ink)
                .accessibilityLabel(label)
            if let error {
                Text(error)
                    .font(.imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            ImasPerforation(color: DS.perforation).padding(.leading, 16)
        }
    }
}

/// 1 行の入力の欄。
struct ImasFormTextField: View {
    let label: String
    var imprint: String? = nil
    var systemImage: String? = nil
    @Binding var text: String
    var prompt: String? = nil
    var error: String? = nil
    var keyboard: UIKeyboardType = .default
    /// 題の欄 (ライブ名など) は大きく組む。
    var isTitle: Bool = false

    var body: some View {
        ImasFormField(label: label, imprint: imprint, systemImage: systemImage, error: error) {
            TextField(prompt ?? label, text: $text, axis: isTitle ? .vertical : .horizontal)
                .font(isTitle ? .imasHeading(22, weight: .heavy) : .imasHeading(17, weight: .bold))
                .keyboardType(keyboard)
        }
    }
}

/// 複数行の入力の欄 (メモ・感想・説明)。
struct ImasFormTextArea: View {
    let label: String
    var imprint: String? = "MEMO"
    var systemImage: String? = "note.text"
    @Binding var text: String
    var prompt: String
    var limit: Int? = nil

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 88

    var body: some View {
        ImasFormField(label: label, imprint: imprint, systemImage: systemImage) {
            VStack(alignment: .trailing, spacing: DS.Space.gapTight) {
                TextField(prompt, text: $text, axis: .vertical)
                    .font(.imasBody)
                    .lineLimit(3...)
                    .frame(minHeight: minHeight, alignment: .topLeading)
                if let limit {
                    Text("\(text.count) / \(limit)")
                        .font(.imasMono(11))
                        .foregroundStyle(text.count > limit ? DS.danger : DS.ink3)
                }
            }
        }
    }
}

/// オン・オフの欄。
struct ImasFormToggle: View {
    let label: String
    var imprint: String? = nil
    var systemImage: String? = nil
    /// 値の文言 (「開演 1 時間前に知らせる」)。
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        ImasFormField(label: label, imprint: imprint, systemImage: systemImage) {
            Toggle(isOn: $isOn) {
                Text(title).font(.imasHeading(15, weight: .semibold))
            }
            .tint(DS.switchOn)
        }
    }
}

/// 押して選択・別のシートへ行く欄。値と矢印。値が無いときは灰色の誘い。
struct ImasFormLink: View {
    let label: String
    var imprint: String? = nil
    var systemImage: String? = nil
    let value: String?
    var placeholder: String = "選ぶ"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ImasFormField(label: label, imprint: imprint, systemImage: systemImage) {
                HStack(spacing: DS.Space.gap) {
                    Text(value ?? placeholder)
                        .foregroundStyle(value == nil ? DS.ink3 : DS.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: DS.Space.gap)
                    Image(systemName: "chevron.right")
                        .font(.imasScaled(13, weight: .semibold))
                        .foregroundStyle(DS.ink3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ImasRowButtonStyle())
    }
}

/// 金額の欄。「¥」と細長い数字。入力は数字のキーボード。
struct ImasFormAmount: View {
    let label: String
    var imprint: String? = "PRICE"
    var systemImage: String? = "ticket"
    @Binding var amount: Int?
    /// 右に添える補足 (「一般 指定席」)。
    var note: String? = nil

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ImasFormField(label: label, imprint: imprint, systemImage: systemImage) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.imasHeading(18, weight: .bold))
                    .foregroundStyle(DS.ink2)
                TextField("0", text: $text)
                    .font(ImasNumeralSize.large.font)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .fixedSize()
                    .onChange(of: text) { _, new in
                        let digits = new.filter(\.isNumber)
                        amount = Int(digits)
                        let formatted = amount.map { $0.formatted(.number.grouping(.automatic)) } ?? ""
                        if formatted != new { text = formatted }
                    }
                Spacer(minLength: DS.Space.gap)
                if let note {
                    Text(note).font(.imasFootnote).foregroundStyle(DS.ink2).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .onAppear { text = amount.map { $0.formatted(.number.grouping(.automatic)) } ?? "" }
    }
}

// MARK: - 大きな札から選ぶ

/// 大きな札から 1 つ選ぶ (参加のしかた・遊び方の種類)。選んだ札は墨の縁で囲み、角に穴が開く。
struct ImasChoiceCards<Option: Hashable>: View {
    struct Choice {
        let value: Option
        let title: String
        var systemImage: String? = nil
        var subtitle: String? = nil
    }

    let choices: [Choice]
    @Binding var selection: Option

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 76

    var body: some View {
        HStack(spacing: DS.Space.gap) {
            ForEach(choices, id: \.value) { choice in
                let on = choice.value == selection
                Button {
                    withAnimation(.imasStandard) { selection = choice.value }
                } label: {
                    VStack(spacing: 6) {
                        if let systemImage = choice.systemImage {
                            Image(systemName: systemImage).font(.imasScaled(20, weight: .regular))
                        }
                        Text(choice.title).font(.imasHeading(14, weight: .heavy)).foregroundStyle(DS.ink)
                        if let subtitle = choice.subtitle {
                            Text(subtitle).font(.imasCaption2).foregroundStyle(DS.ink2).lineLimit(1)
                        }
                    }
                    .foregroundStyle(on ? DS.ink : DS.ink2)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(on ? DS.surface : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.rControl(height) - 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.rControl(height) - 6, style: .continuous)
                            .strokeBorder(on ? DS.ink : DS.line, lineWidth: on ? 2 : 1.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if on { ImasPunchHole(size: .small).padding(8) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.imasPress)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
