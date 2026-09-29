import SwiftUI

/// アイマス関連の収支 (家計簿)。
///
/// 「この趣味にいくら使ったか」を、月/年でまとめて出す。1 件は日付・費目・金額を持ち、
/// 公演に紐づけると「この遠征でいくら使ったか」が出る。紐づけない支出 (課金・通販) も
/// 同じ帳簿に並ぶ。
///
/// 集計・絞り込み・並び・金額の表記は**共有コア** (`domain/ledger.rs`) 一本。
/// ここは返ってきた配列を描くのと、入力を受けて DB に書くところだけ。
///
/// ⚠️ 行のスワイプ (削除) を効かせるため **List** で組む。`ScrollView + LazyVStack` に
/// `swipeActions` を付けても無言で消える。
struct LedgerView: View {

    @State private var expenses: [Expense] = []
    @State private var showLabels: [String: String] = [:]
    @State private var loaded = false

    @State private var summary = LedgerSummary(
        total: 0, count: 0, travelTotal: 0, linkedTotal: 0,
        showCount: 0, averagePerShow: 0, buckets: [], byCategory: []
    )
    @State private var periodIndex = 0
    @State private var yearFilter = ""
    @State private var linkage: LedgerLinkage = .all

    @State private var editing: ExpenseEditorTarget?
    /// 過去の参加でチケット代がまだ無い公演 (取り込みの候補)。
    @State private var backfillRows: [TicketBackfillRow] = []
    @State private var showingBackfill = false
    /// 書き換えの版。**件数だけを鍵にすると、金額や紐づけを直しただけのときに
    /// 再集計が走らない** (件数が変わらないので `.task(id:)` が発火しない)。
    @State private var changeToken = 0

    private static let periodLabels = ["月別", "年別", "全期間"]
    private var period: LedgerPeriod {
        switch periodIndex {
        case 1: return .year
        case 2: return .all
        default: return .month
        }
    }

    private var filter: LedgerFilter {
        LedgerFilter(year: yearFilter, categories: [], linkage: linkage, eventId: "")
    }

    var body: some View {
        List {
            if loaded {
                summarySection.plainRow(background: DS.bg)
                if !backfillRows.isEmpty {
                    backfillBanner.plainRow(background: DS.bg)
                }
                controlSection.plainRow(background: DS.bg)
                if expenses.isEmpty {
                    ImasEmptyState(
                        systemImage: "yensign.circle",
                        title: "まだ記録がありません",
                        message: "右上の + から、チケット代や遠征費を足してください。"
                    )
                    .plainRow(background: DS.bg)
                } else {
                    bucketSections
                }
            } else {
                ImasInlineLoading().padding(.vertical, DS.sp8).plainRow(background: DS.bg)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("収支")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = ExpenseEditorTarget(expense: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("支出を足す")
            }
        }
        .sheet(item: $editing) { target in
            ExpenseEditorView(expense: target.expense) { saved in
                await save(saved)
            }
        }
        .sheet(isPresented: $showingBackfill) {
            TicketBackfillView(rows: backfillRows) { saved in
                await saveBackfill(saved)
            }
        }
        .task { if !loaded { await load() } }
        .task(id: recomputeKey) { recompute() }
        .trackScreen("ledger")
    }

    /// 組み直しが要る条件。ここに出てこない変化では再集計しない。
    private var recomputeKey: String {
        "\(loaded)-\(expenses.count)-\(changeToken)-\(periodIndex)-\(yearFilter)-\(linkage)"
    }

    // MARK: - 要約

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            ImasSectionHeader(title: "使った額", tight: true)
            VStack(alignment: .leading, spacing: DS.sp3) {
                HStack(alignment: .firstTextBaseline, spacing: DS.sp2) {
                    Text(formatYen(amount: summary.total))
                        .font(.imasDisplay(30, weight: .bold)).foregroundStyle(DS.ink)
                    Text("\(summary.count)件")
                        .font(.imasDisplay(15)).foregroundStyle(DS.ink2)
                }
                HStack(spacing: DS.sp5) {
                    metric("遠征費", formatYen(amount: summary.travelTotal))
                    if summary.showCount > 0 {
                        metric("1公演あたり", formatYen(amount: summary.averagePerShow))
                        metric("公演数", "\(summary.showCount)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.sp5)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))

            if !summary.byCategory.isEmpty {
                VStack(spacing: 0) {
                    ForEach(summary.byCategory, id: \.label) { row in
                        ImasStatBar(label: row.label,
                                    value: formatYen(amount: row.total),
                                    percent: Double(row.percent),
                                    valueWidth: 76)
                    }
                }
                .padding(.horizontal, DS.sp4)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.imasCaption).foregroundStyle(DS.ink3)
            Text(value).font(.imasFootnote.weight(.bold)).foregroundStyle(DS.ink)
        }
    }

    // MARK: - 過去の参加の取り込み

    private var backfillBanner: some View {
        Button {
            showingBackfill = true
        } label: {
            HStack(spacing: DS.sp4) {
                Image(systemName: "ticket").foregroundStyle(DS.ink2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("過去の参加からチケット代を取り込む")
                        .font(.imasFootnote.weight(.semibold)).foregroundStyle(DS.ink)
                    Text("チケット代が未記録の公演が\(backfillRows.count)件あります")
                        .font(.imasCaption).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.imasCaption).foregroundStyle(DS.ink3)
            }
            .padding(DS.sp5)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 絞り込み

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            ImasSegmented(labels: Self.periodLabels, selection: $periodIndex)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp3) {
                    ImasFilterChip(text: "全期間", isSelected: yearFilter.isEmpty) { yearFilter = "" }
                    ForEach(years, id: \.self) { year in
                        ImasFilterChip(text: "\(year)年", isSelected: yearFilter == year) {
                            yearFilter = yearFilter == year ? "" : year
                        }
                    }
                }
                .padding(.vertical, DS.sp1)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp3) {
                    ImasFilterChip(text: "すべて", isSelected: linkage == .all) { linkage = .all }
                    ImasFilterChip(text: "公演あり", isSelected: linkage == .linkedOnly) {
                        linkage = linkage == .linkedOnly ? .all : .linkedOnly
                    }
                    ImasFilterChip(text: "公演なし", isSelected: linkage == .unlinkedOnly) {
                        linkage = linkage == .unlinkedOnly ? .all : .unlinkedOnly
                    }
                }
                .padding(.vertical, DS.sp1)
            }
        }
    }

    /// 記録のある年だけ、新しい順。**無い年のチップは出さない**。
    private var years: [String] {
        Array(Set(expenses.map { String($0.date.prefix(4)) }))
            .filter { $0.count == 4 }
            .sorted(by: >)
    }

    // MARK: - 明細

    @ViewBuilder
    private var bucketSections: some View {
        let byId = expensesById
        ForEach(summary.buckets, id: \.key) { bucket in
            Section {
                ForEach(entries(in: bucket, byId: byId), id: \.id) { expense in
                    row(expense)
                        .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: 0, trailing: DS.sp5))
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await delete(expense) } } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(bucket.label).font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                    Spacer(minLength: 12)
                    Text(formatYen(amount: bucket.total))
                        .font(.imasCaption.weight(.bold)).foregroundStyle(DS.ink2)
                }
                .padding(.vertical, DS.sp2)
                .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: 0, trailing: DS.sp5))
                .listRowBackground(DS.bg)
            }
        }
    }

    /// その箱に入る明細。絞り込みも「どの箱に入るか」もコアが `bucket.entryIds` として
    /// 既に決めている (`buildLedgerSummary`)。ここは id を引くだけで、条件を書き直さない
    /// (書き直すと iOS と Android で必ず食い違う)。
    private func entries(in bucket: LedgerBucket, byId: [String: Expense]) -> [Expense] {
        bucket.entryIds.compactMap { byId[$0] }
    }

    /// id → 支出。バケットごとに `entries(in:)` で引き直すための索引。
    private var expensesById: [String: Expense] {
        Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0) })
    }

    private func row(_ expense: Expense) -> some View {
        Button {
            editing = ExpenseEditorTarget(expense: expense)
        } label: {
            HStack(spacing: DS.sp4) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.sp2) {
                        Text(expenseCategoryLabel(category: expense.categoryValue))
                            .font(.imasCaption.weight(.bold))
                            .padding(.horizontal, DS.sp3).padding(.vertical, 2)
                            .background(DS.fill, in: Capsule())
                            .foregroundStyle(DS.ink2)
                        Text(shortDate(expense.date))
                            .font(.imasCaption).foregroundStyle(DS.ink3)
                    }
                    // 公演名かメモ。両方あれば公演名 (どの遠征の支出かが先に要る)。
                    if let label = expense.showId.flatMap({ showLabels[$0] }) ?? expense.note,
                       !label.isEmpty {
                        Text(label)
                            .font(.imasFootnote).foregroundStyle(DS.ink2).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(formatYen(amount: expense.amount))
                    .font(.imasBody.weight(.semibold)).foregroundStyle(DS.ink)
                    .monospacedDigit()
            }
            .padding(.vertical, DS.sp3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortDate(_ date: String) -> String {
        guard date.count == 10 else { return date }
        let month = date.dropFirst(5).prefix(2)
        let day = date.suffix(2)
        return "\(Int(month) ?? 0)/\(Int(day) ?? 0)"
    }

    // MARK: - 読み書き

    private func load() async {
        let ledger = AppContainer.shared.ledgerReading
        expenses = (try? await ledger.expenses()) ?? []
        showLabels = (try? await ledger.attendedShowLabels()) ?? [:]
        backfillRows = (try? await TicketBackfill.candidates()) ?? []
        loaded = true
    }

    /// 取り込んだ分を 1 件ずつ書く。書けたものだけ一覧に足し、候補を読み直す
    /// (途中で失敗しても、書けた公演が候補に残って二重に入らないように)。
    private func saveBackfill(_ saved: [Expense]) async {
        for expense in saved {
            guard await save(expense) else { break }
        }
        backfillRows = (try? await TicketBackfill.candidates()) ?? []
    }

    private func recompute() {
        summary = buildLedgerSummary(entries: projected(), period: period, filter: filter)
    }

    /// コアに渡す射影。公演名は表示用なので OS 側で解決して渡す。
    private func projected() -> [ExpenseEntry] {
        expenses.map { expense in
            ExpenseEntry(
                id: expense.id,
                date: expense.date,
                category: expense.categoryValue,
                amount: expense.amount,
                showId: expense.showId,
                eventId: expense.eventId,
                showLabel: expense.showId.flatMap { showLabels[$0] },
                note: expense.note
            )
        }
    }

    /// 保存に成功してから一覧を直す (失敗しても一覧だけ直すと、保存済みに見えて
    /// 次に開くと消えている)。書けたら true。
    private func save(_ expense: Expense) async -> Bool {
        do {
            try await AppContainer.shared.ledgerWriting.save(expense)
        } catch {
            LocalWriteFailure.report(error, action: "家計簿の保存")
            return false
        }
        if let index = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[index] = expense
        } else {
            expenses.append(expense)
        }
        expenses.sort { ($0.date, $0.id) > ($1.date, $1.id) }
        changeToken += 1
        return true
    }

    private func delete(_ expense: Expense) async {
        do {
            try await AppContainer.shared.ledgerWriting.delete(id: expense.id)
        } catch {
            LocalWriteFailure.report(error, action: "家計簿の削除")
            return
        }
        expenses.removeAll { $0.id == expense.id }
        changeToken += 1
    }
}

/// シートの対象。nil の `expense` は新規作成。
struct ExpenseEditorTarget: Identifiable {
    let expense: Expense?
    var id: String { expense?.id ?? "new" }
}
