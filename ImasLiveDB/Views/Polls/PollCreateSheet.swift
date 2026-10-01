import SwiftUI

/// お題作成シート。デザインシステム準拠 (ImasSectionHeader / ImasCardList /
/// ImasSegmented + 対象カード)。
struct PollCreateSheet: View {
    let onCreate: (Poll) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var targetType: PollTargetType = .song
    @State private var dayIndex = 1   // 0:7 / 1:14 / 2:30
    @State private var scopeIndex = 0 // 0:all 1:brand 2:manual
    @State private var selectedBrandIds: Set<String> = []
    @State private var selectedSongs: [Song] = []
    @State private var selectedIdols: [Idol] = []
    @State private var selectedUnits: [Unit] = []
    @State private var brands: [Brand] = []
    @State private var allIdolsForPicker: [Idol] = []
    @State private var allUnitsForPicker: [Unit] = []
    @State private var showSongPicker = false
    @State private var showIdolPicker = false
    @State private var showUnitPicker = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let dayOptions = [7, 14, 30]
    private var days: Int { dayOptions[dayIndex] }

    private var scope: PollCandidateScope {
        switch scopeIndex {
        case 1: return .brand
        case 2: return .manual
        default: return .all
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    private var manualCount: Int {
        switch targetType {
        case .song: return selectedSongs.count
        case .idol: return selectedIdols.count
        case .unit: return selectedUnits.count
        }
    }

    private var targetLabel: String { targetType.label }

    private var canSubmit: Bool {
        guard InputLimits.isAcceptable(.pollTitle, title), !isSubmitting else { return false }
        switch scope {
        case .all: return true
        case .brand: return !selectedBrandIds.isEmpty
        case .manual: return manualCount >= 2
        }
    }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasNote("お題を作って、みんなに推しを投票してもらおう。期間中は誰でも\(CommunityVoteLimit.perTarget)票まで投票できます。")

                ImasFormCard {
                    ImasFormField(label: "タイトル", imprint: "TITLE") {
                        VStack(alignment: .trailing, spacing: DS.Space.gapTight) {
                            TextField("例: 夏に聴きたい曲は？", text: $title, axis: .vertical)
                                .lineLimit(1...3)
                                .onChange(of: title) { _, new in
                                    let clamped = InputLimits.clamp(.pollTitle, new)
                                    if clamped != new { title = clamped }
                                }
                            Text(InputLimits.counter(.pollTitle, title, separator: "/", unit: ""))
                                .font(.imasCaption.monospacedDigit())
                                .foregroundStyle(DS.ink3)
                        }
                    }
                    ImasFormField(label: "説明（任意）", imprint: "DESCRIPTION", systemImage: "text.alignleft") {
                        VStack(alignment: .trailing, spacing: DS.Space.gapTight) {
                            TextField("補足やルールがあれば（任意）", text: $description, axis: .vertical)
                                .font(.imasBody)
                                .lineLimit(2...5)
                                .onChange(of: description) { _, new in
                                    let clamped = InputLimits.clamp(.pollDescription, new)
                                    if clamped != new { description = clamped }
                                }
                            Text(InputLimits.counter(.pollDescription, description, separator: "/", unit: ""))
                                .font(.imasCaption.monospacedDigit())
                                .foregroundStyle(DS.ink3)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DS.Space.header) {
                    ImasSectionHeader("投票対象", style: .small)
                    ImasChoiceCards(choices: [
                        .init(value: PollTargetType.song, title: "曲", systemImage: "music.note"),
                        .init(value: PollTargetType.idol, title: "アイドル", systemImage: "person.fill"),
                        .init(value: PollTargetType.unit, title: "ユニット", systemImage: "person.3.fill"),
                    ], selection: $targetType)
                }

                scopeSection

                VStack(alignment: .leading, spacing: DS.Space.header) {
                    ImasSectionHeader("募集期間", style: .small)
                    ImasSegmented(labels: dayOptions.map { "\($0)日間" }, selection: $dayIndex)
                }

                if let msg = errorMessage {
                    ImasNotice(kind: .error, message: msg)
                }
            }
            .navigationTitle("お題を投稿")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("poll_create")
            .imasSheetToolbar(.submit(canSubmit: canSubmit, onCancel: { dismiss() }, onSubmit: {
                AppAnalytics.tap("poll_create.submit")
                Task { await submit() }
            }))
            .task {
                async let brandsTask = AppContainer.shared.brandReading.brands()
                async let idolsTask = AppContainer.shared.idolReading.idols(brandId: nil)
                async let unitsTask = AppContainer.shared.unitReading.unitsWithSongs()
                brands = (try? await brandsTask) ?? []
                allIdolsForPicker = (try? await idolsTask) ?? []
                allUnitsForPicker = (try? await unitsTask) ?? []
            }
            .onChange(of: targetType) { _, _ in
                // 種類を切り替えたら manual 選択をリセット (混在不可)
                selectedSongs.removeAll()
                selectedIdols.removeAll()
                selectedUnits.removeAll()
            }
            .sheet(isPresented: $showSongPicker) {
                SongSearchPickerView { songs in
                    let existing = Set(selectedSongs.map(\.id))
                    for s in songs where !existing.contains(s.id) {
                        selectedSongs.append(s)
                    }
                }
            }
            .sheet(isPresented: $showIdolPicker) {
                idolPickerSheet
            }
            .sheet(isPresented: $showUnitPicker) {
                unitPickerSheet
            }
        }
    }

    // MARK: - スコープ選択

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.header) {
            ImasSectionHeader("投票候補", style: .small)
            ImasSegmented(labels: ["全て", "ブランド限定", "候補指定"], selection: $scopeIndex)

            switch scope {
            case .all:
                ImasNote("全\(targetLabel)から自由に投票できます。")
            case .brand:
                brandScopePicker
            case .manual:
                manualScopePicker
            }
        }
    }

    private var brandScopePicker: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            ImasNote("チェックしたブランドの\(targetLabel)だけが候補になります。複数選択可。")

            ImasCard {
                ImasBrandPicker(brands: brands, selection: $selectedBrandIds, includesAll: false)
            }

            if selectedBrandIds.isEmpty {
                ImasNote("1つ以上選択してください", systemImage: "info.circle")
            }
        }
    }

    private var manualScopePicker: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            HStack {
                ImasNote("候補は2件以上必要です。")
                Spacer()
                Text("\(manualCount)件選択中")
                    .imasText(.meta, color: manualCount >= 2 ? DS.ink2 : DS.danger)
            }

            ImasCardList {
                switch targetType {
                case .song:
                    ForEach(Array(selectedSongs.enumerated()), id: \.element.id) { idx, song in
                        if idx > 0 { ImasRowDivider() }
                        manualRow(label: song.title, subtitle: song.titleKana) {
                            selectedSongs.remove(at: idx)
                        }
                    }
                case .idol:
                    ForEach(Array(selectedIdols.enumerated()), id: \.element.id) { idx, idol in
                        if idx > 0 { ImasRowDivider() }
                        manualRow(label: idol.name, subtitle: idol.nameKana) {
                            selectedIdols.remove(at: idx)
                        }
                    }
                case .unit:
                    ForEach(Array(selectedUnits.enumerated()), id: \.element.id) { idx, unit in
                        if idx > 0 { ImasRowDivider() }
                        manualRow(label: unit.displayName, subtitle: nil) {
                            selectedUnits.remove(at: idx)
                        }
                    }
                }

                if manualCount == 0 {
                    ImasEmptyState(.empty, title: "「候補を追加」から選んでください")
                }
            }

            ImasActionRow(title: "候補を追加", systemImage: "plus.circle.fill") {
                AppAnalytics.tap("poll_create.add_manual_candidate")
                switch targetType {
                case .song: showSongPicker = true
                case .idol: showIdolPicker = true
                case .unit: showUnitPicker = true
                }
            }
        }
    }

    private func manualRow(label: String, subtitle: String?, onRemove: @escaping () -> Void) -> some View {
        ImasRow(
            title: label,
            subtitle: subtitle,
            trailing: .custom(AnyView(
                ImasIconButton(systemImage: "minus.circle.fill", label: "候補から外す", size: .small, style: .plain,
                               action: onRemove)
            )),
            density: .compact,
            titleRole: .rowLabel
        )
    }

    private var idolPickerSheet: some View {
        IdolPickerView(
            title: "候補アイドル",
            idols: allIdolsForPicker,
            selected: Set(selectedIdols.map(\.id))
        ) { newIds in
            // 順序保持: 既存はそのまま、新規分だけ末尾に追加
            let existing = Set(selectedIdols.map(\.id))
            let added = newIds.subtracting(existing)
            let removed = existing.subtracting(newIds)
            selectedIdols.removeAll { removed.contains($0.id) }
            for id in added {
                if let idol = allIdolsForPicker.first(where: { $0.id == id }) {
                    selectedIdols.append(idol)
                }
            }
        }
    }

    private var unitPickerSheet: some View {
        UnitMultiPickerView(
            selected: Set(selectedUnits.map(\.id)),
            units: allUnitsForPicker
        ) { newIds in
            // 順序保持: 既存はそのまま、新規分だけ末尾に追加
            let existing = Set(selectedUnits.map(\.id))
            let added = newIds.subtracting(existing)
            let removed = existing.subtracting(newIds)
            selectedUnits.removeAll { removed.contains($0.id) }
            for id in added {
                if let unit = allUnitsForPicker.first(where: { $0.id == id }) {
                    selectedUnits.append(unit)
                }
            }
        }
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        let scopeBrandIds: [String]? = scope == .brand ? Array(selectedBrandIds).sorted() : nil
        let manualEntityIds: [String] = {
            switch targetType {
            case .song: return selectedSongs.map(\.id)
            case .idol: return selectedIdols.map(\.id)
            case .unit: return selectedUnits.map(\.id)
            }
        }()
        let scopeEntityIds: [String]? = scope == .manual ? manualEntityIds : nil

        do {
            let poll = try await AppContainer.shared.communityVoting.createPoll(
                title: trimmedTitle,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                targetType: targetType,
                days: days,
                candidateScope: scope,
                scopeBrandIds: scopeBrandIds,
                scopeEntityIds: scopeEntityIds
            )
            onCreate(poll)
            dismiss()
        } catch {
            // APIClientError の説明 (認証エラー/上限到達等) をそのまま見せる
            errorMessage = (error as? APIClientError)?.errorDescription
                ?? "作成に失敗しました。時間をおいて再試行してください。"
        }
    }
}
