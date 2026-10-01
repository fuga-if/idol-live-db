import SwiftUI

// =============================================================================
// ゲームの設定・読みもの・段階のメーター (docs/DESIGN_SYSTEM.md §2.8・§2.9・§10.4・§12)
//
// ImasSetupHeader     設定画面の頭 (記号 + 題 + 説明)。クイズ 4 種・ソートメーカー・ティアー表。
// ImasCandidateCount  出題できる候補の数 (数えている間はくるくる)。
// ImasMeter           段階のメーター (習熟度の段・クイズの点数)。
// ImasProse           読みものの本文 (見出し・段落・箇条書き)。
// ImasStepList        手順 1・2・3。
// =============================================================================

// MARK: - 設定画面の頭

struct ImasSetupHeader: View {
    let systemImage: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            Image(systemName: systemImage)
                .font(.imasScaled(28, weight: .light))
                .foregroundStyle(DS.ink)
                .accessibilityHidden(true)
            Text(title).imasText(.heroTitle)
            if let message {
                Text(message).imasText(.note).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 候補の数

/// 出題できる候補の数。数えている間はくるくる、足りないときは注意の色。
struct ImasCandidateCount: View {
    let count: Int?
    var unit: String = "曲"
    /// 足りるための数。下回ると注意の色にする。
    var minimum: Int? = nil
    var label: String = "出題できる候補"

    var body: some View {
        HStack(spacing: DS.Space.gap) {
            Text(label).imasText(.value).foregroundStyle(DS.ink2)
            Spacer(minLength: DS.Space.gap)
            if let count {
                ImasMetric(value: count.formatted(), unit: unit, size: .medium, emphasized: false)
                    .foregroundStyle(isShort ? DS.warning : DS.ink)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, DS.Space.rowH)
        .frame(minHeight: DS.Size.touch + 4)
        .background(DS.surface(on: backdrop), in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @Environment(\.imasBackdrop) private var backdrop

    private var isShort: Bool {
        guard let count, let minimum else { return false }
        return count < minimum
    }
}

// MARK: - 段階のメーター

/// 段階のメーター。`value` 段まで実体の色 (無ければ墨) で塗る (習熟度・クイズの点数)。
struct ImasMeter: View {
    let value: Int
    let total: Int

    @Environment(\.imasTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Rectangle()
                    .fill(i < value ? theme.penlight : DS.fill)
                    .frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(total) 段中 \(value) 段")
    }
}

// MARK: - 読みもの

/// 読みものの本文。見出し・段落・箇条書きを並べる。
struct ImasProse: View {
    enum Block: Hashable {
        case heading(String)
        case paragraph(String)
        case bullets([String])
        case note(String)
    }

    let blocks: [Block]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(text).imasText(.cardTitle).padding(.top, DS.Space.gap)
                case .paragraph(let text):
                    Text(text).imasText(.body).fixedSize(horizontal: false, vertical: true)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
                                Text("・").imasText(.body)
                                Text(item).imasText(.body).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .note(let text):
                    ImasNote(text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 手順 1・2・3。番号は等幅の札。
struct ImasStepList: View {
    struct Step: Hashable {
        let title: String
        var detail: String? = nil
    }

    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: DS.Space.gapLoose) {
                    Text("\(index + 1)")
                        .font(ImasNumeralSize.small.font)
                        .foregroundStyle(DS.onSys)
                        .frame(width: 26, height: 26)
                        .background(DS.sys, in: Circle())
                    VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                        Text(step.title).imasText(.rowTitle)
                        if let detail = step.detail {
                            Text(detail).imasText(.note).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
