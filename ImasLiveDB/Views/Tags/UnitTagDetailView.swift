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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            if isLoading {
                ImasInlineLoading()
                    .listRowBackground(Color.clear)
            } else if let detail {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: DS.sp3) {
                            if let hexColor = detail.tag.color {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hexColor: hexColor))
                                    .frame(width: 16, height: 16)
                                    .accessibilityLabel("タグカラー: \(hexColor.rawValue)")
                            }
                            Text(detail.tag.name)
                                .font(.imasTitle2.bold())
                            Spacer()
                            if let cat = detail.tag.category {
                                Text(categoryLabel(cat.rawValue))
                                    .font(.imasCaption)
                                    .padding(.horizontal, DS.sp3)
                                    .padding(.vertical, 3)
                                    .background(categoryColor(cat.rawValue).opacity(0.2))
                                    .foregroundStyle(categoryColor(cat.rawValue))
                                    .clipShape(Capsule())
                                    .accessibilityLabel("カテゴリ: \(categoryLabel(cat.rawValue))")
                            }
                        }
                        if let desc = detail.tag.description, !desc.isEmpty {
                            Text(desc)
                                .font(.imasBody)
                                .foregroundStyle(DS.ink)
                        } else {
                            Text("説明なし")
                                .font(.imasBody)
                                .foregroundStyle(DS.ink3)
                                .italic()
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                } footer: {
                    HStack {
                        Button("説明を編集") {
                            AppAnalytics.tap("unit_tag_detail.edit")
                            showEditSheet = true
                        }
                            .font(.imasCaption)
                        Spacer()
                        Button("編集履歴") {
                            AppAnalytics.tap("unit_tag_detail.history")
                            showHistoryView = true
                        }
                            .font(.imasCaption)
                    }
                }

                if !detail.units.isEmpty {
                    Section("「\(detail.tag.name)」なユニットランキング（\(detail.units.count)組）") {
                        ForEach(Array(detail.units.enumerated()), id: \.element.id) { idx, entry in
                            if let unit = unitCache[entry.unitId] {
                                Button { nextDestination = .unit(unit) } label: {
                                    HStack(spacing: DS.sp2) {
                                        TagRankBadge(rank: idx + 1)
                                        UnitAvatarView(unit: unit, size: 32)
                                        Text(unit.displayName).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                                        Spacer(minLength: 4)
                                        Text("\(entry.voteCount)票")
                                            .font(.imasCaption.monospacedDigit())
                                            .foregroundStyle(DS.ink2)
                                        ImasRowChevron()
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                HStack(spacing: DS.sp2) {
                                    TagRankBadge(rank: idx + 1)
                                    Text(entry.unitId)
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                    Spacer()
                                    Text("\(entry.voteCount)票")
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                }
                            }
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
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

    private func categoryColor(_ cat: String) -> Color {
        ImasTheme.derive(categoryKey: cat, scheme: scheme).accent
    }
}
