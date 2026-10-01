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

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ImasLoadingState()
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
                                PenlightColorBar(colors: Array(selectedColors).map(\.rawValue).sorted(), height: 32)
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
            .imasSheetToolbar(.submit(canSubmit: !selectedColors.isEmpty && !isSending, onCancel: { dismiss() }, onSubmit: {
                AppAnalytics.tap("penlight_vote.submit")
                Task { await vote() }
            }))
            .task { await loadPalette() }
            .imasErrorAlert("投票できませんでした", message: Binding(
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
            alertError = error
        } catch {
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
            alertError = error
        } catch {
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
                    if entry.note != nil {
                        // 任意の色の上に乗る記号なので、WCAG 計算で読める側の色を選ぶ。
                        Image(systemName: "info.circle.fill")
                            .imasText(.meta, color: ColorMath.onColor(Color(hexColor: hexColor)))
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
