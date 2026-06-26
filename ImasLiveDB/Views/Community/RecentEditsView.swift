import os
import SwiftUI

/// 「最近の編集」フィード。`GET /edits` を新しい順に読み、誰が何を変えたかを縦リストで見せる。
///
/// 設計 (vote-to-good): 即時オープン編集に移行したため、承認投票 (OK/NG) は撤去。
/// 各カードには編集者・op バッジ (追加/更新/削除/差戻し)・record_type アイコン・summary・
/// 相対時刻・Good (拍手) ボタンを置く。Good は楽観更新し、失敗時にロールバックする。
/// 自分の編集には Good ボタンを出さず「あなたの編集」ラベルを出す。未ログインは押下で
/// ログイン誘導 sheet を出す。
struct RecentEditsView: View {
    /// 特定ブランドに絞る場合に指定 (任意)。
    var brandId: String? = nil
    /// 自分の編集のみ (MyPage からの遷移用)。
    var mineOnly: Bool = false

    @State private var entries: [EditFeedEntry] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var showLoginPrompt = false

    @Environment(AppDatabase.self) private var database
    /// entry.id → 対象レコードの可読タイトル (ローカル DB から解決)。
    @State private var recordTitles: [Int: String] = [:]
    /// entry.id → 該当ページへの遷移先 (解決できた場合のみ)。
    @State private var destinations: [Int: DetailDestination] = [:]
    /// 該当ページ (曲/アイドル/ライブ/セトリ) を開くシート。
    @State private var sheetDestination: DetailDestination?
    /// 変更履歴 (差分) へのプッシュ遷移先。
    @State private var historyTarget: EditHistoryTarget?

    /// Good の楽観更新オーバーレイ。サーバ確定値が来るまで UI 即時反映する。
    /// editId -> 上書き済みの (gooded, count)。未操作の行はここに無く entry の値をそのまま使う。
    @State private var goodOverrides: [Int: (gooded: Bool, count: Int)] = [:]

    private let limit = 20

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(entries) { entry in
                    EditFeedCard(
                        entry: entry,
                        gooded: isGooded(entry),
                        goodCount: goodCount(entry),
                        isOwn: entry.isOwnEdit,
                        recordTitle: recordTitles[entry.id],
                        hasDestination: destinations[entry.id] != nil,
                        onOpen: { open(entry) },
                        onOpenHistory: { historyTarget = EditHistoryTarget(entry, title: recordTitles[entry.id]) },
                        onToggleGood: { Task { await toggleGood(entry) } }
                    )
                    .onAppear { maybeLoadMore(currentItem: entry) }
                    // 契約 §1: 編集者匿名性のため公開フィードは editorId を返さない。
                    // admin のユーザー単位モデレーションは UserModerationView を別の
                    // 管理導線 (GET /admin/users/:id/edits 等) から開く。
                }

                if isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(DS.bg)
        .navigationTitle(mineOnly ? "自分の編集" : "最近の編集")
        .overlay {
            if isLoading && entries.isEmpty {
                ProgressView("読み込み中...")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if entries.isEmpty && !isLoading {
                EmptyStateCard(
                    icon: "square.and.pencil",
                    title: "まだ編集がありません",
                    message: mineOnly
                        ? "ライブ・楽曲・セトリを編集すると、ここに履歴が残ります。"
                        : "誰かがデータを編集すると、ここに新着順で表示されます。"
                )
            }
        }
        .refreshable { await reload() }
        .task {
            if entries.isEmpty { await reload() }
        }
        .sheet(isPresented: $showLoginPrompt) {
            LoginToEditSheet()
        }
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest).environment(database)
        }
        .navigationDestination(item: $historyTarget) { target in
            EditHistoryView(recordType: target.recordType, recordName: target.recordName, title: target.title)
        }
        .alert("エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .trackScreen("recent_edits")
    }

    // MARK: - Good state resolution

    private func isGooded(_ entry: EditFeedEntry) -> Bool {
        goodOverrides[entry.id]?.gooded ?? entry.hasUserGood
    }

    private func goodCount(_ entry: EditFeedEntry) -> Int {
        goodOverrides[entry.id]?.count ?? entry.goodCount
    }

    // MARK: - Loading

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        page = 1
        do {
            let result = try await EditFeedService.shared.fetchEdits(
                page: 1, limit: limit, brandId: brandId, mine: mineOnly
            )
            entries = result.items
            goodOverrides.removeAll()
            recordTitles.removeAll()
            destinations.removeAll()
            await resolveTitles(for: result.items)
            hasMore = result.items.count >= limit
        } catch {
            errorMessage = errorText(error)
        }
    }

    /// 対象レコードの可読タイトル + 該当ページ遷移先をローカル DB から解決する。
    private func resolveTitles(for items: [EditFeedEntry]) async {
        let editFeed = AppContainer.shared.editFeedReading
        for e in items where recordTitles[e.id] == nil {
            if let t = try? await editFeed.editRecordTitle(recordType: e.recordType, recordName: e.recordName),
               !t.isEmpty {
                recordTitles[e.id] = t
            }
        }
        for e in items where destinations[e.id] == nil {
            if let dest = await resolveDestination(for: e) {
                destinations[e.id] = dest
            }
        }
    }

    /// 編集レコード → 該当ページ (曲/アイドル/ライブ/セトリ) の遷移先を解決する。
    /// セトリ系 (Show/ShowSetlist/SetlistItem/SetlistPerformer) は該当公演のセトリへ。
    private func resolveDestination(for entry: EditFeedEntry) async -> DetailDestination? {
        let songReading = AppContainer.shared.songReading
        let showReading = AppContainer.shared.showReading
        let editFeed = AppContainer.shared.editFeedReading
        switch entry.recordType {
        case "Song":
            if let song = try? await songReading.song(id: entry.recordName) { return .song(song) }
        case "Idol":
            if let idol = try? await AppContainer.shared.idolReading.idol(id: entry.recordName) { return .idol(idol) }
        case "Event":
            if let event = try? await AppContainer.shared.eventReading.event(id: entry.recordName) { return .event(event) }
        case "Show", "ShowSetlist", "SetlistItem", "SetlistPerformer":
            if let showId = (try? await editFeed.editRecordShowId(recordType: entry.recordType, recordName: entry.recordName)) ?? nil,
               let show = try? await showReading.show(id: showId) {
                return .show(show)
            }
        case "SongVideo", "SongCall":
            if let songId = (try? await editFeed.editRecordSongId(recordType: entry.recordType, recordName: entry.recordName)) ?? nil,
               let song = try? await songReading.song(id: songId) {
                return .song(song)
            }
        default:
            break
        }
        return nil
    }

    /// カードのタップ: 該当ページがあればそこへ、無ければ変更履歴 (差分) へ。
    private func open(_ entry: EditFeedEntry) {
        if let dest = destinations[entry.id] {
            sheetDestination = dest
        } else {
            historyTarget = EditHistoryTarget(entry, title: recordTitles[entry.id])
        }
    }

    private func maybeLoadMore(currentItem: EditFeedEntry) {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        // 末尾付近に到達したら次ページを取りに行く。
        guard let idx = entries.firstIndex(where: { $0.id == currentItem.id }),
              idx >= entries.count - 3 else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        do {
            let result = try await EditFeedService.shared.fetchEdits(
                page: next, limit: limit, brandId: brandId, mine: mineOnly
            )
            // 重複防止 (id 既出はスキップ)。
            let existing = Set(entries.map(\.id))
            let fresh = result.items.filter { !existing.contains($0.id) }
            entries.append(contentsOf: fresh)
            await resolveTitles(for: fresh)
            page = next
            hasMore = result.items.count >= limit
        } catch {
            // 追加読み込み失敗はサイレント (アラートで邪魔しない)。
            Logger.community.error("edits_load_more_failed: \(error.localizedDescription)")
            hasMore = false
        }
    }

    // MARK: - Good toggle (optimistic)

    private func toggleGood(_ entry: EditFeedEntry) async {
        // 未ログインはログイン誘導。
        guard AuthService.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        // 自分の編集には Good 不可 (自己賞賛防止)。UI 上もボタンは出ないが二重ガード。
        // 本人判定はサーバ算出の isOwnEdit を権威とする (契約 §1)。
        guard !entry.isOwnEdit else { return }

        let currentlyGooded = isGooded(entry)
        let currentCount = goodCount(entry)
        let newGooded = !currentlyGooded
        let newCount = max(0, currentCount + (newGooded ? 1 : -1))

        // 楽観更新。
        goodOverrides[entry.id] = (newGooded, newCount)

        do {
            let result = newGooded
                ? try await EditFeedService.shared.good(batchId: entry.id)
                : try await EditFeedService.shared.ungood(batchId: entry.id)
            // サーバ確定値で上書き。
            goodOverrides[entry.id] = (result.gooded, result.goodCount)
        } catch {
            // 失敗 → ロールバック。
            goodOverrides[entry.id] = (currentlyGooded, currentCount)
            if case APIClientError.notAuthorized = error {
                showLoginPrompt = true
            } else {
                errorMessage = errorText(error)
            }
        }
    }

    private func errorText(_ error: Error) -> String {
        if case APIClientError.rateLimited = error {
            return "操作が多すぎます。しばらく待ってからお試しください。"
        }
        return "読み込みに失敗しました: \(error.localizedDescription)"
    }
}

// MARK: - Edit Feed Card

private struct EditFeedCard: View {
    let entry: EditFeedEntry
    let gooded: Bool
    let goodCount: Int
    let isOwn: Bool
    /// 対象レコードの人間可読タイトル (曲名/公演名/アイドル名 等)。解決できない時は nil。
    var recordTitle: String? = nil
    /// 該当ページ (曲/アイドル/ライブ/セトリ) へ遷移できるか。
    var hasDestination: Bool = false
    /// カードタップ: 該当ページ (なければ変更履歴) を開く。
    let onOpen: () -> Void
    /// 変更履歴 (差分) を開く。
    let onOpenHistory: () -> Void
    let onToggleGood: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 上半分タップで該当ページ (該当ページが無いレコードは変更履歴) へ。
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    EditRecordIcon(recordType: entry.recordType)

                    VStack(alignment: .leading, spacing: 6) {
                        // editor + op バッジ + 相対時刻
                        HStack(spacing: 6) {
                            Text(entry.editorDisplayLabel)
                                .font(.imasSubhead.weight(.semibold))
                                .lineLimit(1)
                            EditOpBadge(op: entry.op)
                            Spacer(minLength: 4)
                            Text(EditFeedFormat.relativeTime(entry.createdDate))
                                .font(.imasScaled(11))
                                .foregroundStyle(DS.ink2)
                        }

                        // 対象タイトル(何を) — どの曲/公演かを明示。
                        HStack(spacing: 6) {
                            Text(recordTitle ?? EditFeedFormat.recordTypeLabel(entry.recordType))
                                .font(.imasSubhead.weight(.semibold))
                                .foregroundStyle(DS.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.right")
                                .font(.imasScaled(11).weight(.semibold))
                                .foregroundStyle(DS.ink3)
                        }

                        // summary (どうした — 機械生成の変更概要)
                        if let summary = entry.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            goodRow
        }
        .padding(14)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var goodRow: some View {
        HStack(spacing: 10) {
            if isOwn {
                Label("あなたの編集", systemImage: "person.fill")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
            } else {
                Button {
                    AppAnalytics.tap("recent_edits.toggle_good")
                    onToggleGood()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: gooded ? "hands.clap.fill" : "hands.clap")
                        Text(goodCount > 0 ? "\(goodCount)" : "Good")
                            .font(.imasCaption.weight(.semibold))
                    }
                    .foregroundStyle(gooded ? AnyShapeStyle(.pink) : AnyShapeStyle(DS.ink2))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        (gooded ? Color.pink : Color.secondary).opacity(0.12),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(gooded ? "Good を取り消す" : "Good を付ける")
            }

            if isOwn, goodCount > 0 {
                Label("\(goodCount)", systemImage: "hands.clap.fill")
                    .font(.imasCaption)
                    .foregroundStyle(.pink)
            }

            Spacer(minLength: 4)

            // 該当ページに飛べる時は、差分を見る導線を別途用意 (カード本体=ページ遷移のため)。
            if hasDestination {
                Button {
                    AppAnalytics.tap("recent_edits.open_history")
                    onOpenHistory()
                } label: {
                    Label("変更履歴", systemImage: "clock.arrow.circlepath")
                        .font(.imasCaption.weight(.semibold))
                        .foregroundStyle(DS.ink2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }
}

/// 変更履歴 (差分) へのプッシュ遷移先。`navigationDestination(item:)` 用。
struct EditHistoryTarget: Identifiable, Hashable {
    let id: Int
    let recordType: String
    let recordName: String
    let title: String?

    init(_ entry: EditFeedEntry, title: String? = nil) {
        self.id = entry.id
        self.recordType = entry.recordType
        self.recordName = entry.recordName
        self.title = title
    }
}

// MARK: - Record type icon

private struct EditRecordIcon: View {
    let recordType: String

    var body: some View {
        let design = EditFeedFormat.recordTypeDesign(recordType)
        Circle()
            .fill(design.color.opacity(0.15))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: design.icon)
                    .font(.imasScaled( 16, weight: .medium))
                    .foregroundStyle(design.color)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Op badge

private struct EditOpBadge: View {
    let op: String

    var body: some View {
        let (label, color) = EditFeedFormat.opDesign(op)
        Text(label)
            .font(.imasScaled(11).weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Formatting helpers

/// record_type / op の表示メタ + 相対時刻整形を 1 箇所に集約。
/// (旧 SubmissionTypeInfo を撤去したため、フィード専用に最小マッピングを持つ。)
enum EditFeedFormat {
    static func recordTypeDesign(_ type: String) -> (icon: String, color: Color) {
        switch type {
        case "Event":            return ("calendar", .purple)
        case "Show":             return ("music.mic", .indigo)
        case "Song":             return ("music.note", .pink)
        case "Idol":             return ("person.fill", .blue)
        case "SetlistItem", "ShowSetlist":
            return ("music.note.list", .teal)
        case "SetlistPerformer": return ("person.2.fill", .teal)
        case "SongArtist":       return ("music.quarternote.3", .green)
        case "ShowCast":         return ("person.3.fill", .orange)
        default:                 return ("doc.text", .gray)
        }
    }

    static func recordTypeLabel(_ type: String) -> String {
        switch type {
        case "Event":            return "ライブ・イベント"
        case "Show":             return "公演"
        case "Song":             return "楽曲"
        case "Idol":             return "アイドル"
        case "SetlistItem", "ShowSetlist":
            return "セットリスト"
        case "SetlistPerformer": return "セトリ出演者"
        case "SongArtist":       return "楽曲アーティスト"
        case "ShowCast":         return "出演キャスト"
        default:                 return type
        }
    }

    static func opDesign(_ op: String) -> (label: String, color: Color) {
        switch op {
        case "create":            return ("追加", .green)
        case "update", "replace": return ("更新", .blue)
        case "delete":            return ("削除", .red)
        case "revert":            return ("差戻し", .orange)
        case "snapshot":          return ("セトリ更新", .teal)
        default:                  return (op, .gray)
        }
    }

    static func relativeTime(_ date: Date) -> String {
        // RelativeDateTimeFormatter は non-Sendable のため static 共有を避け都度生成する
        // (生成コストは軽微。呼び出しは UI 描画時のみ)。
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}
