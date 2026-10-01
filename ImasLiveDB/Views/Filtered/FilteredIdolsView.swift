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
                ImasLoadingState()
            } else if idols.isEmpty {
                ImasEmptyState(
                    systemImage: "person.2",
                    title: "アイドルが見つかりません"
                )
            } else {
                List {
                    ImasListSummary<Int>(count: idols.count, unit: "人")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(DS.bg)
                        .listRowSeparator(.hidden)
                    ForEach(idols) { idol in
                        Button { navigate(.idol(idol)) } label: {
                            ImasIdolRow(idol: idol, trailing: .chevron, density: .compact)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .imasList()
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
