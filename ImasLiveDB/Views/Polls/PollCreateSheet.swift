import SwiftUI

/// お題作成シート。デザインシステム準拠 (ImasSectionHeader / ImasListContainer /
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
        guard !trimmedTitle.isEmpty, !isSubmitting else { return false }
        switch scope {
        case .all: return true
        case .brand: return !selectedBrandIds.isEmpty
        case .manual: return manualCount >= 2
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp6) {
                    Text("お題を作って、みんなに推しを投票してもらおう。期間中は誰でも3票まで投票できます。")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                        .fixedSize(horizontal: false, vertical: true)

                    fieldSection(header: "タイトル", counter: "\(title.count)/80") {
                        TextField("例: 夏に聴きたい曲は？", text: $title, axis: .vertical)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink)
                            .lineLimit(1...3)
                            .onChange(of: title) { _, new in
                                if new.count > 80 { title = String(new.prefix(80)) }
                            }
                    }

                    fieldSection(header: "説明（任意）", counter: "\(description.count)/280") {
                        TextField("補足やルールがあれば（任意）", text: $description, axis: .vertical)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink)
                            .lineLimit(2...5)
                            .onChange(of: description) { _, new in
                                if new.count > 280 { description = String(new.prefix(280)) }
                            }
                    }

                    VStack(alignment: .leading, spacing: DS.sp3) {
                        ImasSectionHeader(title: "投票対象", tight: true)
                        HStack(spacing: DS.sp3) {
                            targetCard(.song, icon: "music.note", label: "曲")
                            targetCard(.idol, icon: "person.fill", label: "アイドル")
                            targetCard(.unit, icon: "person.3.fill", label: "ユニット")
                        }
                    }

                    scopeSection

                    VStack(alignment: .leading, spacing: DS.sp3) {
                        ImasSectionHeader(title: "募集期間", tight: true)
                        ImasSegmented(labels: dayOptions.map { "\($0)日間" }, selection: $dayIndex)
                    }

                    if let msg = errorMessage {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.imasFootnote)
                            .foregroundStyle(DS.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp4)
                .padding(.bottom, DS.sp7)
            }
            .background(DS.bg.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("お題を投稿")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("poll_create")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("作成") {
                        AppAnalytics.tap("poll_create.submit")
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                    .fontWeight(.semibold)
                }
            }
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

    // MARK: - Pieces

    @ViewBuilder
    private func fieldSection<Content: View>(
        header: String, counter: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: header, tight: true)
            ImasListContainer {
                content()
                    .padding(.horizontal, DS.sp4)
                    .padding(.vertical, DS.sp3)
            }
            Text(counter)
                .font(.imasCaption)
                .foregroundStyle(DS.ink3)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func targetCard(_ type: PollTargetType, icon: String, label: String) -> some View {
        let on = targetType == type
        return Button { targetType = type } label: {
            VStack(spacing: DS.sp2) {
                Image(systemName: icon).font(.imasScaled( 22, weight: .semibold))
                Text(label).font(.imasSubhead.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.sp4)
            .foregroundStyle(on ? Color.accentColor : DS.ink2)
            .background(
                on ? Color.accentColor.opacity(0.12) : DS.surface,
                in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
                    .strokeBorder(on ? Color.accentColor : DS.sep, lineWidth: on ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - スコープ選択

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "投票候補", tight: true)
            ImasSegmented(labels: ["全て", "ブランド限定", "候補指定"], selection: $scopeIndex)

            switch scope {
            case .all:
                Text("全\(targetLabel)から自由に投票できます。")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink3)
            case .brand:
                brandScopePicker
            case .manual:
                manualScopePicker
            }
        }
    }

    private var brandScopePicker: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            Text("チェックしたブランドの\(targetLabel)だけが候補になります。複数選択可。")
                .font(.imasFootnote)
                .foregroundStyle(DS.ink3)

            BrandGridPicker(brands: brands, selectedBrandIds: $selectedBrandIds)
                .padding(.vertical, DS.sp2)
                .padding(.horizontal, DS.sp3)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
                        .strokeBorder(DS.sep, lineWidth: 1)
                )

            if selectedBrandIds.isEmpty {
                Label("1つ以上選択してください", systemImage: "info.circle")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink3)
            }
        }
    }

    private var manualScopePicker: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                Text("候補は2件以上必要です。")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink3)
                Spacer()
                Text("\(manualCount)件選択中")
                    .font(.imasCaption.weight(.semibold))
                    .foregroundStyle(manualCount >= 2 ? DS.ink2 : DS.danger)
            }

            ImasListContainer {
                VStack(spacing: 0) {
                    switch targetType {
                    case .song:
                        ForEach(Array(selectedSongs.enumerated()), id: \.element.id) { idx, song in
                            manualRow(label: song.title, subtitle: song.titleKana) {
                                selectedSongs.remove(at: idx)
                            }
                            if idx < selectedSongs.count - 1 { Divider().background(DS.sep) }
                        }
                    case .idol:
                        ForEach(Array(selectedIdols.enumerated()), id: \.element.id) { idx, idol in
                            manualRow(label: idol.name, subtitle: idol.nameKana) {
                                selectedIdols.remove(at: idx)
                            }
                            if idx < selectedIdols.count - 1 { Divider().background(DS.sep) }
                        }
                    case .unit:
                        ForEach(Array(selectedUnits.enumerated()), id: \.element.id) { idx, unit in
                            manualRow(label: unit.displayName, subtitle: nil) {
                                selectedUnits.remove(at: idx)
                            }
                            if idx < selectedUnits.count - 1 { Divider().background(DS.sep) }
                        }
                    }

                    if manualCount == 0 {
                        Text("「候補を追加」から選んでください")
                            .font(.imasFootnote)
                            .foregroundStyle(DS.ink3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.sp4)
                    }
                }
            }

            Button {
                AppAnalytics.tap("poll_create.add_manual_candidate")
                switch targetType {
                case .song: showSongPicker = true
                case .idol: showIdolPicker = true
                case .unit: showUnitPicker = true
                }
            } label: {
                Label("候補を追加", systemImage: "plus.circle.fill")
                    .font(.imasSubhead.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.sp3)
                    .foregroundStyle(Color.accentColor)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func manualRow(label: String, subtitle: String?, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.imasSubhead).foregroundStyle(DS.ink)
                if let s = subtitle, !s.isEmpty {
                    Text(s).font(.imasCaption).foregroundStyle(DS.ink3)
                }
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.imasTitle3)
                    .foregroundStyle(DS.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
    }

    private var idolPickerSheet: some View {
        IdolPickerView(
            title: "候補アイドルを選択",
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
