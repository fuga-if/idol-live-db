import os
import SwiftUI
import UserNotifications

struct MyPageView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultBrandId") private var defaultBrandId: String = ""
    /// 文字サイズ (極小 0.7 / 小 0.85 / 中 1.0)。密度の高いセトリ等を読みやすくする。
    @AppStorage("text_scale") private var textScale: Double = 1.0
    /// イベント名の作品名プレフィックスを省略表示するか (既定 ON)。OFF でフル表示。
    @AppStorage("event_name_abbreviate") private var abbreviateEventNames: Bool = true
    /// 曲一覧の「この絞り込みでイントロドン」導線を隠すか (曲一覧側の×と同じキー)。
    @AppStorage("songlist_introdon_bar_hidden") private var introDonBarHidden: Bool = false
    /// 回収に配信参加も含めるか (既定=現地のみ)。地方勢など配信中心の人向け。
    @AppStorage("collection_include_stream") private var includeStreamInCollection: Bool = false
    /// 担当(推し)カラーをアプリ全体テーマに使うか。
    @AppStorage("theme_use_oshi_color") private var useOshiColor: Bool = false
    /// テーマに使う担当アイドル ID (複数担当から1人選択)。
    @AppStorage("theme_oshi_idol_id") private var themeOshiIdolId: String = ""
    /// ContentView が参照する解決済みテーマ色 hex。無効時は空。
    @AppStorage("theme_oshi_color") private var themeOshiColorHex: String = ""

    // MARK: - 通知設定
    @AppStorage("notif_oshi_birthday") private var notifOshiBirthday: Bool = true
    @AppStorage("notif_live_week") private var notifLiveWeek: Bool = true
    @AppStorage("notif_ticket") private var notifTicket: Bool = true
    @AppStorage("notif_monday") private var notifMonday: Bool = true
    /// 現在の通知認可状態。View の onAppear で更新する。
    @State private var notifAuthStatus: UNAuthorizationStatus = .notDetermined
    /// 担当(推し)に設定済みのアイドル一覧 (テーマ選択用)。
    @State private var pickIdols: [Idol] = []
    @State private var schemaVersion: String = "..."
    @State private var dataVersion: String = "..."
    @State private var dbStats: DatabaseStats?
    @State private var brands: [Brand] = []
    @State private var imageURL: String = ""
    @State private var importer = BulkImageImporter()
    @State private var showImageImport = false
    @State private var brandImageURL: String = ""
    @State private var showBrandImageImport = false
    @State private var idolTemplateURL: URL?
    @State private var brandTemplateURL: URL?
    @State private var syncDiagnostics: SyncDiagnostics?
    @State private var ckQueryProbeResult: String?
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var showHelp = false
    @State private var showEditName = false
    @State private var editingName = ""
    @State private var isSavingName = false
    @State private var nameErrorMessage: String?

    // admin モデレーション導線。確定契約 §1 で公開フィードは editorId を返さない
    // (編集者匿名性) ため、admin は対象ユーザー ID を直接指定してモデレーション画面を開く。
    @State private var showModerationPrompt = false
    @State private var moderationUserIdInput = ""
    /// 入力された userId でモデレーション画面を開く (sheet 駆動)。
    @State private var moderationTarget: String?

    private var isSyncing: Bool {
        if case .syncing = syncEngine.state { return true }
        return false
    }

    // 型チェック負荷を下げるため List の中身を上下2つに分割。
    @ViewBuilder
    private var upperSections: some View {
        // この画面は「設定」。参加ライブ/貢献バッジ/編集履歴 等の個人アクティビティは
        // プロデュースタブ「あなたの活動」と重複するため、ここには置かない。
        accountSection
        if AuthService.shared.isAdmin {
            adminSection
        }
    }

    @ViewBuilder
    private var lowerSections: some View {
        settingsSection
        dataSyncSection
        if let stats = dbStats {
            dataStatsSection(stats)
        }
        creditsSection
        appInfoSection
    }

    // 型チェック負荷分散: List + chrome を decoratedList に切り出し、alert/sheet 群は body 側に。
    private var decoratedList: some View {
        List {
            upperSections
            lowerSections
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .navigationTitle("設定")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") { dismiss() }
            }
        }
        .task { await loadAll() }
        .onChange(of: syncEngine.state) {
            if case .completed = syncEngine.state {
                Task { await loadAll() }
            }
        }
    }

    var body: some View {
        NavigationStack {
            decoratedList
            .alert("画像一括インポート", isPresented: $showImageImport) {
                TextField("JSON URL", text: $imageURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("インポート") {
                    Task {
                        await importer.importFromURL(imageURL, database: database)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("アイドル名と画像URLのJSONファイルのURLを入力してください。\n形式: {\"アイドル名\": \"画像URL\", ...}")
            }
            .alert("ブランド画像インポート", isPresented: $showBrandImageImport) {
                TextField("JSON URL", text: $brandImageURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("インポート") {
                    Task {
                        await importer.importBrandImagesFromURL(brandImageURL, database: database)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("ブランド名(または short_name / id)と画像URLのJSONファイルのURLを入力してください。\n形式: {\"765AS\": \"画像URL\", ...}")
            }
            .sheet(isPresented: $showHelp) {
                HelpView()
            }
            .alert("表示名を変更", isPresented: $showEditName) {
                TextField("表示名", text: $editingName)
                    .textInputAutocapitalization(.never)
                Button("保存") {
                    Task { await saveDisplayName() }
                }
                .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingName)
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("コミュニティ投稿で表示される名前です (40文字以内)")
            }
            .alert("表示名の保存に失敗", isPresented: Binding(
                get: { nameErrorMessage != nil },
                set: { if !$0 { nameErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { nameErrorMessage = nil }
            } message: {
                Text(nameErrorMessage ?? "")
            }
            .alert("ユーザーをモデレーション", isPresented: $showModerationPrompt) {
                TextField("ユーザー ID", text: $moderationUserIdInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("開く") {
                    let trimmed = moderationUserIdInput.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { moderationTarget = trimmed }
                }
                .disabled(moderationUserIdInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("対象ユーザーの ID を入力すると編集履歴の確認・BAN・一括取り消しができます。")
            }
            .sheet(item: Binding(
                get: { moderationTarget.map { ModerationUserID(id: $0) } },
                set: { moderationTarget = $0?.id }
            )) { target in
                NavigationStack {
                    UserModerationView(userId: target.id)
                }
            }
            .alert("アカウントを削除しますか?", isPresented: $showDeleteAccountConfirm) {
                Button("削除する", role: .destructive) {
                    Task { await performAccountDeletion() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("サーバー上のあなたの編集・Good・予想・ユーザー情報がすべて削除され、サインアウトされます。この操作は取り消せません。")
            }
            .alert("削除に失敗しました", isPresented: Binding(
                get: { deleteAccountErrorMessage != nil },
                set: { if !$0 { deleteAccountErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { deleteAccountErrorMessage = nil }
            } message: {
                Text(deleteAccountErrorMessage ?? "")
            }
            .overlay {
                if importer.isImporting {
                    VStack(spacing: 16) {
                        ProgressView(value: importer.progress)
                            .frame(width: 200)
                        Text(importer.statusMessage)
                            .font(.imasCaption)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .trackScreen("my_page")
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        Section("アカウント") {
            if AuthService.shared.isSignedIn {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.imasTitle2)
                        .foregroundStyle(DS.ink2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(AuthService.shared.userName ?? "ユーザー")
                                .font(.imasHeadline)
                            Button {
                                AppAnalytics.tap("my_page.edit_name")
                                editingName = AuthService.shared.userName ?? ""
                                showEditName = true
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .font(.imasCallout)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("表示名を変更")
                        }
                        if let email = AuthService.shared.userEmail {
                            Text(email)
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink2)
                        }
                        #if DEBUG
                        if let uid = AuthService.shared.userId {
                            Text("ID: \(uid)")
                                .font(.imasScaled(11).monospaced())
                                .foregroundStyle(DS.ink3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        #endif
                    }
                }
                Button("ログアウト", role: .destructive) {
                    AppAnalytics.tap("my_page.logout")
                    AuthService.shared.signOut()
                }
                Button("アカウントを削除", role: .destructive) {
                    AppAnalytics.tap("my_page.delete_account")
                    showDeleteAccountConfirm = true
                }
                .disabled(isDeletingAccount)
            } else {
                VStack(spacing: 8) {
                    Text("ログインするとライブ・セトリ・楽曲データの編集や Good ができます")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                    AppleSignInButton()
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    // MARK: - Admin Section (モデレーション)

    /// admin 専用。確定契約 §1 で公開フィードは編集者匿名性のため editorId を返さないため、
    /// admin は対象ユーザー ID を直接指定してモデレーション画面 (履歴確認 / BAN / 一括取り消し) を開く。
    @ViewBuilder
    private var adminSection: some View {
        Section {
            Button {
                AppAnalytics.tap("my_page.admin_moderation")
                moderationUserIdInput = ""
                showModerationPrompt = true
            } label: {
                Label("ユーザーをモデレーション", systemImage: "person.badge.shield.checkmark")
            }
        } header: {
            Text("管理者")
        } footer: {
            Text("対象ユーザー ID を指定して編集履歴の確認・BAN・一括取り消しを行います。")
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    // MARK: - Settings Section

    @ViewBuilder
    private var settingsSection: some View {
        helpSection
        generalSettingsSection
        collectionSettingsSection
        notificationSection
        themeSection
        imageImportSection
    }

    @ViewBuilder
    private var helpSection: some View {
        Section {
            Button {
                AppAnalytics.tap("my_page.open_help")
                showHelp = true
            } label: {
                Label("使い方を見る", systemImage: "questionmark.circle.fill")
            }
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    @ViewBuilder
    private var generalSettingsSection: some View {
        Section("設定") {
            Picker("デフォルトブランド", selection: $defaultBrandId) {
                Text("すべて").tag("")
                ForEach(brands) { brand in
                    Text(brand.shortName).tag(brand.id)
                }
            }
            Picker("文字サイズ", selection: $textScale) {
                Text("極小").tag(0.7)
                Text("小").tag(0.85)
                Text("中").tag(1.0)
            }
            .pickerStyle(.segmented)
            // プレビュー: 選んだサイズで実際の見え方を即確認できる (設定画面のラベル自体は
            // システム既定フォントなので変化しないため、ここで反映後の文字を見せる)。
            VStack(alignment: .leading, spacing: 3) {
                Text("プレビュー")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                Text("Timeless Shooting Star")
                    .font(.imasScaled(16, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Text("ストレイライト ・ 全員")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
            }
            .padding(.vertical, 2)

            Toggle("ライブ名を省略表示", isOn: $abbreviateEventNames)
            // 設定値で見え方が変わるサンプル。ON なら作品名プレフィックスを省く。
            Text(eventDisplayName("THE IDOLM@STER SHINY COLORS 3rdLIVE TOUR"))
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)

            // 曲一覧の「この絞り込みでイントロドン」導線の表示/非表示 (×で隠した後ここで戻せる)。
            Toggle("曲一覧にイントロドン導線を表示", isOn: Binding(
                get: { !introDonBarHidden },
                set: { introDonBarHidden = !$0 }
            ))
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    @ViewBuilder
    private var collectionSettingsSection: some View {
        Section {
            Toggle("配信参加も回収に含める", isOn: $includeStreamInCollection)
                .onChange(of: includeStreamInCollection) {
                    UserMarkService.shared.refreshAutoCollected()
                }
        } header: {
            Text("披露回収")
        } footer: {
            Text("回収はリアルライブ(ライブ/フェス)の現地参加のみが対象です。配信でしか観られない方は、配信参加も回収に含められます。")
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    @ViewBuilder
    private var themeSection: some View {
        Section {
            Toggle("担当の色をテーマに使う", isOn: $useOshiColor)
            if useOshiColor {
                if pickIdols.isEmpty {
                    Text("アイドル詳細で担当(推し)に設定すると、ここで色を選べます。")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                } else {
                    Picker("テーマにする担当", selection: $themeOshiIdolId) {
                        ForEach(pickIdols) { idol in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hexString: idol.color))
                                    .frame(width: 14, height: 14)
                                Text(idol.name)
                            }
                            .tag(idol.id)
                        }
                    }
                }
            }
        } header: {
            Text("テーマ")
        } footer: {
            Text("ONにすると、選んだ担当のイメージカラーがアプリ全体のアクセントカラーになります。")
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
        .onChange(of: useOshiColor) { syncThemeColor() }
        .onChange(of: themeOshiIdolId) { syncThemeColor() }
    }

    @ViewBuilder
    private var imageImportSection: some View {
        Section {
            Button {
                AppAnalytics.tap("my_page.image_import")
                showImageImport = true
            } label: {
                Label("キャラクター画像をインポート", systemImage: "photo.on.rectangle.angled")
            }
            if let url = idolTemplateURL {
                ShareLink(item: url) {
                    Label("型紙 JSON をダウンロード (アイドル)", systemImage: "square.and.arrow.down")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                }
            }

            Button {
                AppAnalytics.tap("my_page.brand_image_import")
                showBrandImageImport = true
            } label: {
                Label("ブランド画像をインポート", systemImage: "tag")
            }
            if let url = brandTemplateURL {
                ShareLink(item: url) {
                    Label("型紙 JSON をダウンロード (ブランド)", systemImage: "square.and.arrow.down")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                }
            }

            if importer.importedCount > 0 || importer.failedCount > 0 {
                Text(importer.statusMessage)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
            }
            if !importer.failures.isEmpty {
                DisclosureGroup {
                    ForEach(importer.failures) { f in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.key).font(.imasCaption).bold()
                            Text(f.reason).font(.imasScaled(11)).foregroundStyle(DS.ink2)
                        }
                    }
                } label: {
                    Label("失敗内訳 (\(importer.failures.count) 件)", systemImage: "exclamationmark.triangle")
                        .font(.imasCaption)
                        .foregroundStyle(DS.warning)
                }
            }

            Button(role: .destructive) {
                AppAnalytics.tap("my_page.clear_images")
                Task { await importer.clearAllImages() }
            } label: {
                Label("カスタム画像を全削除", systemImage: "trash")
            }
        } header: {
            Text("画像インポート")
        } footer: {
            Text("型紙 JSON をダウンロード → URL を埋めて GitHub Gist 等にアップ → そのファイル URL をインポートに貼り付け。既存画像は上書きされます。")
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    // MARK: - Notification Section

    @ViewBuilder
    private var notificationSection: some View {
        Section {
            switch notifAuthStatus {
            case .notDetermined, .denied:
                Button {
                    AppAnalytics.tap("my_page.request_notification")
                    Task {
                        let granted = await NotificationService.shared.requestAuthorization()
                        if granted {
                            notifAuthStatus = .authorized
                            Task { await NotificationService.shared.rescheduleAll(database: database) }
                        } else {
                            notifAuthStatus = .denied
                        }
                    }
                } label: {
                    Label("通知を許可する", systemImage: "bell.badge")
                }
                if notifAuthStatus == .denied {
                    Text("通知が拒否されています。設定アプリから許可してください。")
                        .font(.imasCaption)
                        .foregroundStyle(DS.warning)
                }
            default:
                Toggle("担当アイドルの誕生日", isOn: $notifOshiBirthday)
                    .onChange(of: notifOshiBirthday) {
                        Task { await NotificationService.shared.rescheduleAll(database: database) }
                    }
                Toggle("ライブ1週間前", isOn: $notifLiveWeek)
                    .onChange(of: notifLiveWeek) {
                        Task { await NotificationService.shared.rescheduleAll(database: database) }
                    }
                Toggle("チケット締切・当落通知", isOn: $notifTicket)
                    .onChange(of: notifTicket) {
                        Task { await NotificationService.shared.rescheduleAll(database: database) }
                    }
                Toggle("月曜が近いことを知らせる (日曜 20:00)", isOn: $notifMonday)
                    .onChange(of: notifMonday) {
                        Task { await NotificationService.shared.rescheduleAll(database: database) }
                    }
            }
        } header: {
            Text("通知")
        } footer: {
            if notifAuthStatus == .authorized || notifAuthStatus == .provisional {
                Text("お気に入りまたは参加マークしたイベントにライブ前・チケット通知を送ります。")
            }
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
        .task {
            notifAuthStatus = await NotificationService.shared.authorizationStatus()
        }
    }

    // MARK: - Data Sync Section

    @ViewBuilder
    private var dataSyncSection: some View {
        Section("データ同期") {
            HStack {
                Image(systemName: syncStateIcon)
                    .foregroundStyle(syncStateColor)
                Text(syncEngine.state.description)
                    .font(.imasSubhead)
                if isSyncing {
                    Spacer()
                    ProgressView()
                }
            }

            Button {
                AppAnalytics.tap("my_page.sync_incremental")
                Task { await syncEngine.performIncrementalSync(database: database) }
            } label: {
                Label("差分更新", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isSyncing)

            Button {
                AppAnalytics.tap("my_page.sync_full")
                Task { await syncEngine.performFullSync(database: database) }
            } label: {
                Label("全データ同期", systemImage: "arrow.clockwise.icloud")
            }
            .disabled(isSyncing)

            #if DEBUG
            LabeledContent("スキーマバージョン", value: schemaVersion)
            LabeledContent("データバージョン", value: dataVersion)

            if let summary = syncEngine.lastSyncSummary {
                DisclosureGroup {
                    LabeledContent("modifiedSince", value: summary.modifiedSinceLabel)
                        .font(.imasScaled(11))
                    LabeledContent("総取得件数", value: "\(summary.totalFetched)")
                        .font(.imasScaled(11))
                    if summary.fetchedByType.isEmpty {
                        Text("(各 RecordType 0 件)")
                            .font(.imasScaled(11))
                            .foregroundStyle(DS.ink2)
                    } else {
                        ForEach(summary.fetchedByType.sorted { $0.key < $1.key }, id: \.key) { (k, v) in
                            LabeledContent(k, value: "\(v)")
                                .font(.imasScaled(11))
                        }
                    }
                } label: {
                    Label("直近同期サマリ", systemImage: "list.bullet.rectangle")
                        .font(.imasCaption)
                }
            }
            #endif

            #if DEBUG
            if let diag = syncDiagnostics {
                DisclosureGroup {
                    LabeledContent("@ events", value: "\(diag.eventsAt)").font(.imasScaled(11))
                    LabeledContent("@ shows", value: "\(diag.showsAt)").font(.imasScaled(11))
                    LabeledContent("@ setlist_items", value: "\(diag.setlistItemsAt)").font(.imasScaled(11))
                    LabeledContent("ML 13thLIVE event", value: diag.ml13thLiveExists ? "✅" : "❌").font(.imasScaled(11))
                    LabeledContent("ML 13thLIVE shows", value: "\(diag.ml13thShowsCount)").font(.imasScaled(11))
                    LabeledContent("ML 13thLIVE items", value: "\(diag.ml13thSetlistItemsCount)").font(.imasScaled(11))
                    LabeledContent("SC 8th name", value: diag.sc8thName ?? "(nil)").font(.imasScaled(11))
                    LabeledContent("SC 8th kind", value: diag.sc8thKind ?? "(nil)").font(.imasScaled(11))
                    LabeledContent("SC 8th shows", value: "\(diag.sc8thShowsCount)").font(.imasScaled(11))

                    if let probe = ckQueryProbeResult {
                        LabeledContent("CK Query probe (showId)", value: probe).font(.imasScaled(11))
                    }
                    Button {
                        Task { await probeCKQuery() }
                    } label: {
                        Label("CK Query probe", systemImage: "play.circle")
                            .font(.imasScaled(11))
                    }
                    LabeledContent("reseed 結果", value: AppDatabase.lastReseedStatus)
                        .font(.imasScaled(11))
                        .textSelection(.enabled)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = AppDatabase.lastReseedStatus
                            } label: {
                                Label("コピー", systemImage: "doc.on.doc")
                            }
                        }
                } label: {
                    Label("@ 診断", systemImage: "stethoscope")
                        .font(.imasCaption)
                }
            }
            #endif
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    // MARK: - Data Stats Section

    @ViewBuilder
    private func dataStatsSection(_ stats: DatabaseStats) -> some View {
        Section("データ統計") {
            LabeledContent("楽曲数", value: "\(stats.songCount)曲")
            LabeledContent("アイドル数", value: "\(stats.idolCount)人")
            LabeledContent("イベント数", value: "\(stats.eventCount)件")
            LabeledContent("公演数", value: "\(stats.showCount)公演")
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    // MARK: - App Info Section

    @ViewBuilder
    private var appInfoSection: some View {
        Section("アプリ情報") {
            NavigationLink("アプリについて") {
                AboutView()
            }
            NavigationLink("プライバシーポリシー") {
                PrivacyPolicyView()
            }
            NavigationLink("利用規約") {
                TermsOfServiceView()
            }
            NavigationLink("サポート") {
                SupportView()
            }
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    // MARK: - Credits Section

    @ViewBuilder
    private var creditsSection: some View {
        Section("クレジット") {
            Text("本アプリは非公式のファンメイドアプリです。")
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                LabeledContent("アプリバージョン", value: version)
            }
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    // MARK: - Sync State UI Helpers

    private var syncStateIcon: String {
        switch syncEngine.state {
        case .idle: return "icloud"
        case .syncing: return "icloud.and.arrow.down"
        case .completed: return "checkmark.icloud"
        case .error:
            return syncEngine.state == .requiresFullResync
                ? "arrow.triangle.2.circlepath.icloud"
                : "exclamationmark.icloud"
        }
    }

    private var syncStateColor: Color {
        switch syncEngine.state {
        case .idle: return .secondary
        case .syncing: return .accentColor
        case .completed: return .green
        case .error:
            return syncEngine.state == .requiresFullResync ? .orange : .red
        }
    }

    @MainActor
    private func saveDisplayName() async {
        // サーバ側は JS String.trim() (改行や各種 Unicode 空白も除去) で正規化するため、
        // クライアントも .whitespacesAndNewlines に揃える。.whitespaces だと末尾改行が残り、
        // ローカルキャッシュ userName とサーバ保存値が乖離する。
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await AuthService.shared.updateDisplayName(trimmed)
        } catch {
            // レート制限 (429) は「失敗」というより日次上限なので、表示名専用の文言に差し替える。
            // グローバルな APIClientError.rateLimited 文言は他エンドポイントと共有なので触らない。
            if case APIClientError.rateLimited = error {
                nameErrorMessage = "今日はこれ以上、表示名を変更できません。明日また試してください"
            } else {
                nameErrorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func performAccountDeletion() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await AuthService.shared.deleteAccount()
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Data Loading

    private func loadAll() async {
        do {
            let diagnostics = AppContainer.shared.diagnosticsReading
            schemaVersion = try await diagnostics.metaValue(forKey: "schema_version") ?? "不明"
            dataVersion = try await diagnostics.metaValue(forKey: "data_version") ?? "不明"
            dbStats = try await diagnostics.databaseStats()
            syncDiagnostics = try await diagnostics.syncDiagnostics()
            brands = try await AppContainer.shared.brandReading.brands()
            let pickIds = try await AppContainer.shared.markReading.markedEntityIds(entity: .idol, kind: .myPick)
            pickIdols = try await AppContainer.shared.idolReading.idols(ids: pickIds)
            syncThemeColor()
        } catch {
            Logger.database.error("load_failed settings: \(error.localizedDescription)")
        }

        await regenerateImportTemplates()
    }

    /// 担当テーマ色を現在の選択から再計算し、ContentView 参照用 hex を更新する。
    /// 無効時は空にする。選択未設定なら先頭の担当を既定にする。
    private func syncThemeColor() {
        guard useOshiColor else {
            themeOshiColorHex = ""
            return
        }
        if themeOshiIdolId.isEmpty || !pickIdols.contains(where: { $0.id == themeOshiIdolId }) {
            themeOshiIdolId = pickIdols.first?.id ?? ""
        }
        themeOshiColorHex = pickIdols.first { $0.id == themeOshiIdolId }?.color ?? ""
    }

    private func regenerateImportTemplates() async {
        do {
            let idols = try await AppContainer.shared.idolReading.idols(brandId: nil)
            let idolMapping = idols.map { ($0.name, "") }
            idolTemplateURL = try Self.writeJSONTemplate(
                pairs: idolMapping,
                fileName: "idol_images_template.json"
            )

            let brandMapping = brands.map { ($0.shortName, "") }
            brandTemplateURL = try Self.writeJSONTemplate(
                pairs: brandMapping,
                fileName: "brand_images_template.json"
            )
        } catch {
            Logger.database.error("template_generation_failed: \(error.localizedDescription)")
        }
    }

    private static func writeJSONTemplate(pairs: [(String, String)], fileName: String) throws -> URL {
        var lines: [String] = ["{"]
        for (i, (key, value)) in pairs.enumerated() {
            let comma = i < pairs.count - 1 ? "," : ""
            lines.append("  \(jsonEscape(key)): \(jsonEscape(value))\(comma)")
        }
        lines.append("}")
        let json = lines.joined(separator: "\n")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try json.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private static func jsonEscape(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data()
        let arrayString = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(arrayString.dropFirst().dropLast())
    }

    private func probeCKQuery() async {
        ckQueryProbeResult = "実行中..."
        do {
            let recs = try await CloudKitService.shared.debugFetchSetlistItemsByShowId("sh_the_idolm@ster_million_live_13thlive_1")
            ckQueryProbeResult = "showId query: \(recs.count) 件"
            // ついでにそれを upsert してみる
            let mapped = recs.compactMap { CKRecordMapper.setlistItem(from: $0) }
            if !mapped.isEmpty {
                try await AppContainer.shared.showWriting.upsertSetlistItems(mapped)
                syncDiagnostics = try await AppContainer.shared.diagnosticsReading.syncDiagnostics()
                ckQueryProbeResult = (ckQueryProbeResult ?? "") + " / upsert \(mapped.count) 件"
            }
        } catch {
            ckQueryProbeResult = "エラー: \(error.localizedDescription)"
        }
    }

}

// MARK: - ModerationUserID

/// `.sheet(item:)` 駆動用の userId ラッパ (admin モデレーション画面を開く)。
private struct ModerationUserID: Identifiable {
    let id: String
}
