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
                    ProgressView("読み込み中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Text("ペンライトの色を選んで投票してください。複数選択できます。")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink2)
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)

                        if palette.isEmpty {
                            Section {
                                ContentUnavailableView(
                                    "カラーを取得できません",
                                    systemImage: "exclamationmark.triangle",
                                    description: Text("通信状況を確認して再度お試しください")
                                )
                            }
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }

                        Section("カラーを選択") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
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
                            .padding(.vertical, 8)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)

                        if !selectedColors.isEmpty {
                            Section("選択中のセット") {
                                PenlightColorBar(colors: Array(selectedColors).map(\.rawValue).sorted(), height: 32)
                                    .cornerRadius(6)
                            }
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(DS.bg)
                }
            }
            .navigationTitle("ペンライトカラーを投票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppAnalytics.tap("penlight_vote.submit")
                        Task { await vote() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("投票する")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(selectedColors.isEmpty || isSending)
                }
            }
            .task { await loadPalette() }
            .alert("投票エラー", isPresented: Binding(
                get: { alertError != nil },
                set: { if !$0 { alertError = nil } }
            )) {
                Button("OK") { alertError = nil }
            } message: {
                if let err = alertError {
                    Text(err.errorDescription ?? "不明なエラーが発生しました")
                }
            }
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
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hexColor: hexColor))
                        .frame(height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                                    lineWidth: isSelected ? 3 : 1
                                )
                        )
                    if entry.note != nil {
                        Image(systemName: "info.circle.fill")
                            .font(.imasScaled(11))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 1)
                            .padding(4)
                            .onTapGesture { showNote.toggle() }
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.imasTitle3)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Text(entry.name)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("色: \(entry.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .popover(isPresented: $showNote) {
            if let note = entry.note {
                Text(note)
                    .font(.imasCaption)
                    .padding()
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}
