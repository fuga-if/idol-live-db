import SwiftUI

struct PenlightVoteSheet: View {
    let songId: String
    let onVoted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var palette: [PenlightPaletteEntry] = []
    @State private var selectedColors: Set<HexColor> = []
    @State private var isLoading = false
    @State private var isSending = false
    @State private var alertError: CommunityAPIError?
    /// 今の alertError がカラーの取得の失敗か (投票の失敗と題を分けるため)。
    @State private var isLoadError = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ImasLoadingState(title: "読み込み中…")
                } else {
                    List {
                        Section {
                            ImasNote("ペンライトの色を選んで投票してください。複数選択できます。")
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)

                        if palette.isEmpty {
                            Section {
                                ImasEmptyState(
                                    systemImage: "exclamationmark.triangle",
                                    title: "カラーを取得できません",
                                    message: "通信状況を確認して再度お試しください"
                                )
                            }
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }

                        ImasListSection("カラーを選択") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: DS.Space.card) {
                                ForEach(palette.filter { $0.colorHex != nil }) { entry in
                                    if let hex = entry.colorHex {
                                        PenlightColorChip(
                                            entry: entry,
                                            hexColor: hex,
                                            isSelected: selectedColors.contains(hex)
                                        ) {
                                            if selectedColors.contains(hex) {
                                                selectedColors.remove(hex)
                                            } else {
                                                selectedColors.insert(hex)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, DS.Space.rowV)
                        }

                        if !selectedColors.isEmpty {
                            ImasListSection("選択中のセット") {
                                ImasPenlightColorBar(colors: Array(selectedColors).map(\.rawValue).sorted(), height: 32)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(DS.bg)
                }
            }
            .navigationTitle("ペンライトカラーを投票")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.submit(
                canSubmit: !selectedColors.isEmpty && !isSending,
                isSubmitting: isSending,
                onCancel: { dismiss() },
                onSubmit: {
                    AppAnalytics.tap("penlight_vote.submit")
                    Task { await vote() }
                }
            ))
            .task { await loadPalette() }
            .imasErrorAlert(isLoadError ? "カラーを取得できませんでした" : "投票できませんでした", message: Binding(
                get: { alertError?.errorDescription ?? (alertError != nil ? "不明なエラーが発生しました" : nil) },
                set: { if $0 == nil { alertError = nil } }
            ))
            .trackScreen("penlight_vote")
        }
    }

    private func loadPalette() async {
        isLoading = true
        do {
            palette = try await CommunityAPI.shared.penlightPalette()
        } catch let error as CommunityAPIError {
            isLoadError = true
            alertError = error
        } catch {
            isLoadError = true
            alertError = .transport(error)
        }
        isLoading = false
    }

    private func vote() async {
        guard !selectedColors.isEmpty else { return }
        isSending = true
        do {
            try await CommunityAPI.shared.votePenlight(
                songId: songId,
                colors: Array(selectedColors).map(\.rawValue)
            )
            onVoted()
            dismiss()
        } catch let error as CommunityAPIError {
            isLoadError = false
            alertError = error
        } catch {
            isLoadError = false
            alertError = .transport(error)
        }
        isSending = false
    }
}

private struct PenlightColorChip: View {
    let entry: PenlightPaletteEntry
    let hexColor: HexColor
    let isSelected: Bool
    let onTap: () -> Void

    @State private var showNote = false

    var body: some View {
        Button {
            AppAnalytics.tap("penlight_vote.color_toggle")
            onTap()
        } label: {
            VStack(spacing: DS.Space.gapTight) {
                ZStack(alignment: .topTrailing) {
                    ImasSwatch(hex: hexColor.rawValue, size: .large, isSelected: isSelected)
                    if isSelected {
                        // 選択は輪に加えて中央にも✓ (色の違いだけに頼らない)。
                        Image(systemName: "checkmark.circle.fill")
                            .imasText(.body, color: ColorMath.onColor(Color(hexColor: hexColor)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }
                    if entry.note != nil {
                        // 任意の色の上に乗る記号なので、WCAG 計算で読める側の色を選ぶ。
                        // 押せる範囲は見た目の記号より広く取り、44pt 以上を確保する。
                        Image(systemName: "info.circle.fill")
                            .imasText(.meta, color: ColorMath.onColor(Color(hexColor: hexColor)))
                            .frame(minWidth: DS.Size.touch, minHeight: DS.Size.touch)
                            .contentShape(Rectangle())
                            .onTapGesture { showNote.toggle() }
                    }
                }
                Text(entry.name).imasText(.meta)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("色: \(entry.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .popover(isPresented: $showNote) {
            if let note = entry.note {
                Text(note).imasText(.body).padding().presentationCompactAdaptation(.popover)
            }
        }
    }
}
