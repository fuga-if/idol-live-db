import SwiftUI

/// 習熟度の段階を編集する。段数とラベルを決める面。
///
/// **保存されているのは序数だけ**なので、ラベルを書き換えても記録には触らない。
/// 段を減らしたときだけ、その段にいた曲が 1 つ下へ寄る (規則は core の
/// `remapMasteryLevel`)。消さずに寄せるので、増やし直せば戻る訳ではないが記録は残る。
///
/// 削除は**最上段だけ**にしている。真ん中を抜くと序数の意味がずれて、寄せ先の規則
/// (上限で丸める) と噛み合わなくなる。規則を増やすより操作を狭める方を選んだ。
struct MasteryScaleSettingsView: View {
    private var marks: UserMarkService { UserMarkService.shared }

    @State private var labels: [String] = []
    @State private var loaded = false
    @FocusState private var focused: Int?

    private static let maxSteps = 8

    var body: some View {
        List {
            presetSection
            stageSection
            if let warning = shrinkWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.warning)
                }
                .listRowBackground(DS.surface)
            }
            applySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("習熟度の段階")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            labels = marks.scale.labels
            loaded = true
        }
        .trackScreen("mastery_scale_settings")
    }

    // MARK: - プリセット

    private var presetSection: some View {
        Section {
            HStack(spacing: DS.sp3) {
                ForEach(MasteryScale.presets, id: \.name) { preset in
                    ImasFilterChip(text: preset.name,
                                   isSelected: labels == preset.scale.labels) {
                        labels = preset.scale.labels
                    }
                }
                Spacer()
            }
        } header: {
            Text("プリセット").font(.imasCaption).foregroundStyle(DS.ink2)
        } footer: {
            Text("どのラベルも 4 文字以内にしておくと、一覧のスワイプで切れずに出ます。")
                .font(.imasCaption2).foregroundStyle(DS.ink3)
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    // MARK: - 段

    private var stageSection: some View {
        Section {
            ForEach(labels.indices, id: \.self) { i in
                HStack(spacing: DS.sp4) {
                    MasteryCell(level: UInt8(i + 1),
                                scale: MasteryScale(labels: labels), size: 16)
                    TextField("段の名前", text: Binding(
                        get: { i < labels.count ? labels[i] : "" },
                        set: { if i < labels.count { labels[i] = $0 } }
                    ))
                    .font(.imasBody)
                    .focused($focused, equals: i)
                    .submitLabel(.done)
                    Text("\(count(at: i))")
                        .font(.imasDisplay(11)).foregroundStyle(DS.ink2)
                    if i == labels.count - 1 && labels.count > 1 {
                        Button {
                            labels.removeLast()
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(DS.danger)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("最上段を削除")
                    }
                }
            }
            if labels.count < Self.maxSteps {
                Button {
                    labels.append("")
                    focused = labels.count - 1
                } label: {
                    Label("段を追加", systemImage: "plus.circle").font(.imasSubhead)
                }
            }
        } header: {
            Text("下から順に積み上がる").font(.imasCaption).foregroundStyle(DS.ink2)
        } footer: {
            Text("右の数字はいまその段にある曲数。削除できるのは最上段だけです。")
                .font(.imasCaption2).foregroundStyle(DS.ink3)
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    /// いまその段にある曲数 (保存済みの段数で数えた値)。
    private func count(at index: Int) -> Int {
        let counts = marks.masteryCounts()
        return index < counts.count ? counts[index] : 0
    }

    // MARK: - 反映

    private var trimmed: [String] {
        labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var isValid: Bool {
        let t = trimmed
        return !t.isEmpty && t.allSatisfy { !$0.isEmpty } && Set(t).count == t.count
    }

    private var isDirty: Bool { trimmed != marks.scale.labels }

    /// 段を減らすときに何曲動くか。動かないなら nil。
    private var shrinkWarning: String? {
        let newSteps = UInt8(clamping: max(1, min(trimmed.count, Self.maxSteps)))
        let oldSteps = marks.scale.steps
        guard newSteps < oldSteps else { return nil }
        let counts = marks.masteryCounts()
        let moving = counts.enumerated()
            .filter { $0.offset + 1 > Int(newSteps) }
            .reduce(0) { $0 + $1.element }
        guard moving > 0 else { return nil }
        let dest = trimmed.indices.contains(Int(newSteps) - 1) ? trimmed[Int(newSteps) - 1] : "最上段"
        return "\(moving) 曲が「\(dest)」に移ります。記録は消えません。"
    }

    private var applySection: some View {
        Section {
            Button {
                apply()
            } label: {
                Text("この段階にする").font(.imasSubhead.weight(.semibold))
            }
            .disabled(!isValid || !isDirty)
            if isDirty {
                Button("元に戻す", role: .cancel) { labels = marks.scale.labels }
            }
        } footer: {
            if !isValid {
                Text("空の段と同じ名前の段は置けません。")
                    .font(.imasCaption2).foregroundStyle(DS.danger)
            }
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    private func apply() {
        guard isValid else { return }
        do {
            try marks.setScale(MasteryScale(labels: trimmed))
        } catch {
            LocalWriteFailure.report(error, action: "習熟度の段階の保存")
        }
        labels = marks.scale.labels
    }
}
