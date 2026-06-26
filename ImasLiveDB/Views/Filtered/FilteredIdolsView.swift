import os
import SwiftUI

struct FilteredIdolsView: View {
    @Environment(AppDatabase.self) private var database
    let criterion: IdolFilterCriterion
    let navigate: (DetailDestination) -> Void

    @State private var idols: [Idol] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if idols.isEmpty {
                ContentUnavailableView(
                    "アイドルが見つかりません",
                    systemImage: "person.2"
                )
            } else {
                List {
                    Section {
                        ForEach(idols) { idol in
                            Button { navigate(.idol(idol)) } label: {
                                IdolNameRow(idol: idol)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("\(idols.count)人")
                            .font(.imasCaption)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(criterion.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIdols() }
        .trackScreen("filtered_idols")
    }

    private func loadIdols() async {
        isLoading = true
        do {
            idols = try await AppContainer.shared.idolReading.idols(criterion: criterion)
        } catch {
            Logger.database.error("load_failed filtered_idols: \(error.localizedDescription)")
            idols = []
        }
        isLoading = false
    }
}
