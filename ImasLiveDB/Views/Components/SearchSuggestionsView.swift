import SwiftUI

struct SearchSuggestionItem: Identifiable, Hashable {
    let id: String
    let text: String
    let subtitle: String?
    let icon: String

    init(text: String, subtitle: String? = nil, icon: String = "magnifyingglass") {
        self.id = text
        self.text = text
        self.subtitle = subtitle
        self.icon = icon
    }
}

struct SearchSuggestionsView: View {
    let scope: SearchScope
    let currentQuery: String
    let suggestions: [SearchSuggestionItem]
    let onClear: (() -> Void)?

    init(
        scope: SearchScope,
        currentQuery: String,
        suggestions: [SearchSuggestionItem],
        onClear: (() -> Void)? = nil
    ) {
        self.scope = scope
        self.currentQuery = currentQuery
        self.suggestions = suggestions
        self.onClear = onClear
    }

    var body: some View {
        let history = SearchHistoryManager.shared.history(for: scope)
        if currentQuery.isEmpty && !history.isEmpty {
            Section {
                ForEach(history, id: \.self) { item in
                    Label(item, systemImage: "clock")
                        .searchCompletion(item)
                }
            } header: {
                HStack {
                    Text("最近の検索")
                    Spacer()
                    Button("クリア") {
                        SearchHistoryManager.shared.clear(scope: scope)
                        onClear?()
                    }
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                }
            }
        }

        if !currentQuery.isEmpty && !suggestions.isEmpty {
            Section("候補") {
                ForEach(suggestions) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.text)
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.imasCaption)
                                    .foregroundStyle(DS.ink2)
                            }
                        }
                    } icon: {
                        Image(systemName: item.icon)
                    }
                    .searchCompletion(item.text)
                }
            }
        }
    }
}
