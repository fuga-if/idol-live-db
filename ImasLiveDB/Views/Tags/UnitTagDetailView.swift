import SwiftUI

/// ユニットタグ (unit_tag_master) の詳細。IdolTagDetailView と同じ構成だが、
/// タグプールが別なので付いたユニットのランキングのみを表示する。
struct UnitTagDetailView: View {
    @Environment(AppDatabase.self) private var database
    let tagId: String
    let tagName: String

    @State private var detail: UnitTagDetailResponse?
    @State private var isLoading = true
    @State private var showEditSheet = false
    @State private var showHistoryView = false
    @State private var showReportAlert = false
    @State private var reportSuccessAlert = false
    @State private var alertError: CommunityAPIError?
    @State private var unitCache: [String: Unit] = [:]
    @State private var nextDestination: DetailDestination?

    var body: some View {
        List {
            if isLoading {
                ImasInlineLoading()
                    .listRowBackground(Color.clear)
            } else if let detail {
                Section {
                    ImasTagHeaderCard(
                        name: detail.tag.name,
                        colorHex: detail.tag.color?.rawValue,
                        categoryLabel: detail.tag.category.map { categoryLabel($0.rawValue) },
                        description: detail.tag.description
                    )
                    .listRowInsets(EdgeInsets(top: DS.Space.rowV, leading: DS.Space.screen,
                                              bottom: DS.Space.rowV, trailing: DS.Space.screen))
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                } footer: {
                    HStack {
                        Button("説明を編集") {
                            AppAnalytics.tap("unit_tag_detail.edit")
                            showEditSheet = true
                        }
                        .buttonStyle(.imas(.plain, size: .small))
                        Spacer()
                        Button("編集履歴") {
                            AppAnalytics.tap("unit_tag_detail.history")
                            showHistoryView = true
                        }
                        .buttonStyle(.imas(.plain, size: .small))
                    }
                }

                if !detail.units.isEmpty {
                    ImasListSection("「\(detail.tag.name)」なユニットランキング（\(detail.units.count)組）") {
                        ForEach(Array(detail.units.enumerated()), id: \.element.id) { idx, entry in
                            unitRankRow(entry: entry, rank: idx + 1)
                        }
                    }
                } else {
                    Section {
                        ImasEmptyState(systemImage: "tag", title: "まだこのタグが付いたユニットはいません")
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .navigationTitle(tagName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        AppAnalytics.tap("unit_tag_detail.report")
                        showReportAlert = true
                    } label: {
                        Label("不適切なタグを通報", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(DS.ink2)
                }
            }
        }
        .sheet(isPresented: $showEditSheet, onDismiss: { Task { await loadDetail() } }) {
            if let detail { TagEditSheet(tag: detail.tag, domain: .unit) }
        }
        .sheet(isPresented: $showHistoryView) {
            NavigationStack {
                TagHistoryView(tagId: tagId, domain: .unit)
            }
        }
        .sheet(item: $nextDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .alert("タグを通報", isPresented: $showReportAlert) {
            Button("通報する", role: .destructive) {
                Task { await reportTag() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("不適切なコンテンツとして通報します")
        }
        .alert("通報しました", isPresented: $reportSuccessAlert) {
            Button("OK") {}
        } message: {
            Text("ご報告ありがとうございます。内容を確認します。")
        }
        .alert("通報エラー", isPresented: Binding(
            get: { alertError != nil },
            set: { if !$0 { alertError = nil } }
        )) {
            Button("OK") { alertError = nil }
        } message: {
            if let err = alertError {
                if case .rateLimited = err {
                    Text("本日通報上限です。明日また試してください。")
                } else {
                    Text(err.errorDescription ?? "エラーが発生しました")
                }
            }
        }
        .task { await loadDetail() }
        .trackScreen("unit_tag_detail")
    }

    private func reportTag() async {
        do {
            try await AppContainer.shared.communityTagWriting.reportUnitTag(id: tagId, reason: nil)
            reportSuccessAlert = true
        } catch let error as CommunityAPIError {
            alertError = error
        } catch {
            alertError = .transport(error)
        }
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        detail = try? await AppContainer.shared.communityTagReading.unitTagDetail(id: tagId)
        if let units = detail?.units,
           let index = try? await AppContainer.shared.unitReading.unitIndex() {
            let missingIds = Set(units.map(\.unitId)).subtracting(unitCache.keys)
            for unit in index.units where missingIds.contains(unit.id) {
                unitCache[unit.id] = unit
            }
        }
    }

    private func categoryLabel(_ cat: String) -> String {
        TagCategoryOptions.unit.first { $0.value == cat }?.label ?? cat
    }

    /// ユニットランキング 1 行。未解決ならタイトルの代わりに ID を薄字で出す。
    @ViewBuilder
    private func unitRankRow(entry: TagUnitEntry, rank: Int) -> some View {
        if let unit = unitCache[entry.unitId] {
            Button { nextDestination = .unit(unit) } label: {
                HStack(spacing: DS.Space.gapTight) {
                    ImasRankBadge(rank: rank)
                    ImasRow(
                        title: unit.displayName,
                        leading: .custom(AnyView(UnitAvatarView(unit: unit, size: 32)), width: 32),
                        trailing: .custom(AnyView(
                            HStack(spacing: DS.Space.gap) {
                                ImasMetric(value: "\(entry.voteCount)", unit: "票", size: .medium)
                                ImasRowChevron()
                            }
                        ))
                    )
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: DS.Space.gapTight) {
                ImasRankBadge(rank: rank)
                ImasRow(title: entry.unitId, trailing: .metric("\(entry.voteCount)", unit: "票"), emphasis: .dimmed)
            }
        }
    }
}
