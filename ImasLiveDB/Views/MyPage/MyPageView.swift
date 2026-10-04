import os
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct MyPageView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultBrandId") private var defaultBrandId: String = ""
    /// 文字サイズ (極小 0.7 / 小 0.85 / 中 1.0 / 大 1.15 / 特大 1.3)。OS の Dynamic Type に
    /// 乗算で併用するアプリ内倍率。中(1.0) を境に縮小・拡大の両方向へ調整できる。
    @AppStorage("text_scale") private var textScale: Double = 1.0
    private static let textScaleOptions: [Double] = [0.7, 0.85, 1.0, 1.15, 1.3]
    /// 歌唱者の表示サンプル (実データの 1 人)。設定を切り替えた見え方をその場で見せる。
    private static let performerNameSample = PerformerRow(
        id: "sample",
        name: "下田麻美",
        idolColor: nil,
        idolName: "双海亜美"
    )
    private static let textScaleLabels = ["極小", "小", "中", "大", "特大"]
    private var textScaleIndex: Binding<Int> {
        Binding(
            // 既存ユーザーの保存値 (0.7/0.85/1.0) はそのまま該当インデックスに載る。
            // 未知値のフォールバックは「中」(1.0)。
            get: { Self.textScaleOptions.firstIndex(of: textScale) ?? Self.textScaleOptions.firstIndex(of: 1.0) ?? 2 },
            set: { textScale = Self.textScaleOptions[$0] }
        )
    }
    /// イベント名の作品名プレフィックスを省略表示するか (既定 ON)。OFF でフル表示。
    @AppStorage("event_name_abbreviate") private var abbreviateEventNames: Bool = true
    /// セトリの歌唱者をどの名前で出すか (既定=アイドル名)。
    /// 保存するのはコアが決めた `raw` の文字列 (序数で保存しない)。
    @AppStorage(PerformerNamePref.storageKey) private var performerNameRaw = PerformerNamePref.defaultRaw
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
    /// データ取得はすべて VM 側 (ポート注入)。View は UI 状態だけ持つ。
    @State private var vm = MyPageViewModel()
    @State private var notifAuthStatus: UNAuthorizationStatus = .notDetermined
    /// 担当(推し)に設定済みのアイドル一覧 (テーマ選択用)。
    @State private var imageURL: String = ""
    @State private var importer = BulkImageImporter()
    @State private var showImageImport = false
    @State private var brandImageURL: String = ""
    @State private var showBrandImageImport = false
    @State private var unitImageURL: String = ""
    @State private var showUnitImageImport = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var showHelp = false
    @State private var showEditName = false
    @State private var editingName = ""
    @State private var isSavingName = false
    @State private var nameErrorMessage: String?

    // MARK: - バックアップ/引き継ぎコード
    /// 復元時に端末IDも引き継ぐか (上級者向け・既定OFF)。同一端末からの復元でない限りOFFのままにすべき。
    @AppStorage("backup_restore_device_id") private var restoreDeviceIdOnImport: Bool = false
    @State private var isCreatingTransferCode = false
    @State private var transferCode: String?
    @State private var transferCodeExpiresAt: Date?
    @State private var transferCodeErrorMessage: String?
    @State private var importCodeInput = ""
    @State private var isImportingByCode = false
    @State private var backupFileURL: URL?
    @State private var exportErrorMessage: String?
    @State private var showBackupFileImporter = false
    @State private var importResultMessage: String?
    @State private var importErrorMessage: String?

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
        if AuthService.shared.adminCapabilities.canModerateUsers {
            adminSection
        }
    }

    @ViewBuilder
    private var lowerSections: some View {
        settingsSection
        dataSyncSection
        dataBackupSection
        if let stats = vm.dbStats {
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
        .listStyle(.insetGrouped)
        .imasForm()
        .navigationTitle("設定")
        .imasSheetToolbar(.read(onClose: { dismiss() }))
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
            .alert("ユニット画像インポート", isPresented: $showUnitImageImport) {
                TextField("JSON URL", text: $unitImageURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("インポート") {
                    Task {
                        await importer.importUnitImagesFromURL(unitImageURL, database: database)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("ユニット名(または id)と画像URLのJSONファイルのURLを入力してください。\n形式: {\"S.E.M\": \"画像URL\", ...}")
            }
            .sheet(isPresented: $showHelp) {
                HelpView()
            }
            .alert("表示名を変更", isPresented: $showEditName) {
                TextField("表示名", text: $editingName)
                    .textInputAutocapitalization(.never)
                    .onChange(of: editingName) { _, new in
                        // 上限と数え方 (コードポイント) はコア。無制限に打てるとサーバ側で弾かれる。
                        let clamped = InputLimits.clamp(.displayName, new)
                        if clamped != new { editingName = clamped }
                    }
                Button("保存") {
                    Task { await saveDisplayName() }
                }
                .disabled(!InputLimits.isAcceptable(.displayName, editingName) || isSavingName)
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("コミュニティ投稿で表示される名前です (\(InputLimits.max(.displayName))文字以内)")
            }
            .imasErrorAlert("表示名の保存に失敗", message: $nameErrorMessage)
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
            .imasConfirmDestructive(
                "アカウントを削除しますか?",
                isPresented: $showDeleteAccountConfirm,
                actionTitle: "削除する",
                message: "サーバー上のあなたの編集・Good・予想・ユーザー情報がすべて削除され、サインアウトされます。この操作は取り消せません。",
                style: .alert
            ) {
                Task { await performAccountDeletion() }
            }
            .imasErrorAlert("削除に失敗しました", message: $deleteAccountErrorMessage)
            .imasErrorAlert("引き継ぎコードの発行に失敗しました", message: $transferCodeErrorMessage)
            .imasErrorAlert("バックアップの保存に失敗しました", message: $exportErrorMessage)
            .fileImporter(isPresented: $showBackupFileImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    Task { await importBackupFromFile(url) }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                }
            }
            .alert(
                importErrorMessage != nil ? "復元に失敗しました" : "復元しました",
                isPresented: Binding(
                    get: { importResultMessage != nil || importErrorMessage != nil },
                    set: { if !$0 { importResultMessage = nil; importErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    importResultMessage = nil
                    importErrorMessage = nil
                }
            } message: {
                Text(importErrorMessage ?? importResultMessage ?? "")
            }
            .imasSavingOverlay(importer.isImporting, label: importer.statusMessage, progress: importer.progress,
                               blocksInteraction: false)
        }
        .trackScreen("my_page")
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        if AuthService.shared.isSignedIn {
            ImasListSection("アカウント") {
                ImasPass(
                    leftImprint: "ACCOUNT",
                    rightImprint: "ログイン中",
                    title: AuthService.shared.userName ?? "ユーザー",
                    subtitle: "コミュニティで表示される名前",
                    onOpen: nil
                ) {
                    Button {
                        AppAnalytics.tap("my_page.edit_name")
                        editingName = AuthService.shared.userName ?? ""
                        showEditName = true
                    } label: {
                        Image(systemName: "pencil.circle").font(.imasCallout)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("表示名を変更")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if let email = AuthService.shared.userEmail {
                    ImasValueRow(key: "メールアドレス", value: email)
                }
                #if DEBUG
                if let uid = AuthService.shared.userId {
                    ImasValueRow(key: "ID", value: uid, monospaced: true)
                }
                #endif
            }
            ImasListSection {
                ImasActionRow(title: "ログアウト", kind: .destructive) {
                    AppAnalytics.tap("my_page.logout")
                    AuthService.shared.signOut()
                }
                ImasActionRow(title: "アカウントを削除", kind: .destructive) {
                    AppAnalytics.tap("my_page.delete_account")
                    showDeleteAccountConfirm = true
                }
                .disabled(isDeletingAccount)
            }
        } else {
            ImasListSection("アカウント") {
                VStack(spacing: DS.Space.gap) {
                    Text("ログインするとライブ・セトリ・楽曲データの編集や Good ができます")
                        .imasText(.note)
                        .multilineTextAlignment(.center)
                    AppleSignInButton()
                }
                .padding(.vertical, DS.Space.gap)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Admin Section (モデレーション)

    /// admin 専用。確定契約 §1 で公開フィードは編集者匿名性のため editorId を返さないため、
    /// admin は対象ユーザー ID を直接指定してモデレーション画面 (履歴確認 / BAN / 一括取り消し) を開く。
    @ViewBuilder
    private var adminSection: some View {
        ImasListSection(
            "管理者",
            footer: "対象ユーザー ID を指定して編集履歴の確認・BAN・一括取り消し、 全曲のサブスク再生可否チェック等を行います。"
        ) {
            ImasActionRow(title: "ユーザーをモデレーション", systemImage: "person.badge.shield.checkmark") {
                AppAnalytics.tap("my_page.admin_moderation")
                moderationUserIdInput = ""
                showModerationPrompt = true
            }
            NavigationLink {
                PlayabilityCheckView()
            } label: {
                ImasNavRow(title: "再生可否チェック (Apple Music)", systemImage: "music.note.list", showsChevron: false)
            }
        }
    }

    // MARK: - Settings Section

    @ViewBuilder
    private var settingsSection: some View {
        helpSection
        // 試作。開発ビルドだけに出す (審査の端末も TestFlight と同じレシートなので、配布ビルドには出さない)。
        if ChatGPTPlanSession.isPrototypeVisible {
            chatGPTPlanSection
        }
        generalSettingsSection
        collectionSettingsSection
        masterySection
        notificationSection
        themeSection
        imageImportSection
    }

    @ViewBuilder
    private var helpSection: some View {
        ImasListSection {
            ImasActionRow(title: "使い方を見る", systemImage: "questionmark.circle.fill") {
                AppAnalytics.tap("my_page.open_help")
                showHelp = true
            }
        }
    }

    /// Sign in with ChatGPT の試作。ChatGPT Plus / Pro のプランで AI を呼ぶ。
    @ViewBuilder
    private var chatGPTPlanSection: some View {
        ImasListSection {
            NavigationLink {
                ChatGPTPlanLabView()
            } label: {
                ImasNavRow(
                    title: "ChatGPT 連携 (試作)",
                    systemImage: "sparkles",
                    value: ChatGPTPlanSession.shared.isSignedIn ? "連携中" : "Continue with ChatGPT",
                    showsChevron: false
                )
            }
        }
    }

    @ViewBuilder
    private var generalSettingsSection: some View {
        ImasListSection("設定") {
            NavigationLink {
                TabBarSettingsView()
            } label: {
                ImasNavRow(title: "タブバー", systemImage: "dock.rectangle", showsChevron: false)
            }

            ImasMenuRow(
                title: "デフォルトブランド",
                systemImage: "square.grid.2x2",
                options: [""] + vm.brands.map(\.id),
                selection: $defaultBrandId
            ) { id in
                id.isEmpty ? "すべて" : (vm.brands.first { $0.id == id }?.shortName ?? id)
            }

            VStack(alignment: .leading, spacing: DS.Space.gap) {
                Text("文字サイズ").imasText(.rowLabel)
                ImasSegmented(labels: Self.textScaleLabels, selection: textScaleIndex)
                // プレビュー: 選んだサイズで実際の見え方を即確認できる (設定画面のラベル自体は
                // システム既定フォントなので変化しないため、ここで反映後の文字を見せる)。
                VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                    Text("プレビュー").imasText(.rowSubtitle)
                    Text("Timeless Shooting Star").imasText(.rowTitle)
                    Text("ストレイライト ・ 全員").imasText(.rowSubtitle)
                }
                .padding(.top, DS.Space.gapTight)
            }
            .padding(.vertical, DS.Space.gapTight)

            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                // 選択肢はコアが出す (順も文言もアプリ 1 本)。
                ImasMenuRow(
                    title: "セトリの歌唱者",
                    systemImage: "person.2",
                    options: PerformerNamePref.options.map(\.raw),
                    selection: $performerNameRaw
                ) { raw in
                    PerformerNamePref.options.first { $0.raw == raw }?.label ?? raw
                }
                // 設定値で見え方が変わるサンプル。声優ライブの 1 人分をそのまま出す。
                Text(
                    Self.performerNameSample
                        .displayName(PerformerNamePref.mode(performerNameRaw), isCharacterLive: false)
                        .joined
                )
                .imasText(.meta)
                .padding(.horizontal, DS.Space.rowH)
            }

            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                ImasToggleRow(title: "ライブ名を省略表示", isOn: $abbreviateEventNames)
                // 設定値で見え方が変わるサンプル。ON なら作品名プレフィックスを省く。
                Text(eventDisplayName("THE IDOLM@STER SHINY COLORS 3rdLIVE TOUR"))
                    .imasText(.meta)
                    .padding(.horizontal, DS.Space.rowH)
            }

            // 曲一覧の「この絞り込みでイントロドン」導線の表示/非表示 (×で隠した後ここで戻せる)。
            ImasToggleRow(
                title: "曲一覧にイントロドン導線を表示",
                isOn: Binding(
                    get: { !introDonBarHidden },
                    set: { introDonBarHidden = !$0 }
                )
            )
        }
    }

    @ViewBuilder
    private var collectionSettingsSection: some View {
        ImasListSection(
            "披露回収",
            footer: "回収はリアルライブ(ライブ/フェス)の現地参加のみが対象です。配信でしか観られない方は、配信参加も回収に含められます。"
        ) {
            ImasToggleRow(title: "配信参加も回収に含める", isOn: $includeStreamInCollection)
                .onChange(of: includeStreamInCollection) {
                    UserMarkService.shared.refreshAutoCollected()
                }
        }
    }

    /// 習熟度の段階。ラベルの好みは人によるので、既定 (聞いた / 覚えた / 完璧) を
    /// 触れるようにしてある。保存は序数なのでラベルを直しても記録は壊れない。
    @ViewBuilder
    private var masterySection: some View {
        ImasListSection(
            "習熟度",
            footer: "段の数と名前を変えられます。段を減らすと、その段の曲は 1 つ下に移ります (記録は消えません)。"
        ) {
            NavigationLink {
                MasteryScaleSettingsView()
            } label: {
                ImasNavRow(title: "習熟度の段階", systemImage: "chart.bar",
                           value: UserMarkService.shared.scale.labels.joined(separator: " / "), showsChevron: false)
            }
        }
    }

    @ViewBuilder
    private var themeSection: some View {
        ImasListSection(
            "テーマ",
            footer: "ONにすると、選んだ担当のイメージカラーがアプリ全体のアクセントカラーになります。"
        ) {
            ImasToggleRow(title: "担当の色をテーマに使う", isOn: $useOshiColor)
            if useOshiColor {
                if vm.pickIdols.isEmpty {
                    ImasNote("アイドル詳細で担当(推し)に設定すると、ここで色を選べます。")
                        .padding(.horizontal, DS.Space.rowH)
                        .padding(.vertical, DS.Space.gapTight)
                } else {
                    ImasMenuRow(
                        title: "テーマにする担当",
                        options: vm.pickIdols.map(\.id),
                        selection: $themeOshiIdolId
                    ) { id in
                        vm.pickIdols.first { $0.id == id }?.name ?? id
                    }
                }
            }
        }
        .onChange(of: useOshiColor) { syncThemeColor() }
        .onChange(of: themeOshiIdolId) { syncThemeColor() }
    }

    @ViewBuilder
    private var imageImportSection: some View {
        ImasListSection(
            "画像インポート",
            footer: "型紙 JSON をダウンロード → URL を埋めて GitHub Gist 等にアップ → そのファイル URL をインポートに貼り付け。既存画像は上書きされます。"
        ) {
            ImasActionRow(title: "キャラクター画像をインポート", systemImage: "photo.on.rectangle.angled") {
                AppAnalytics.tap("my_page.image_import")
                showImageImport = true
            }
            if let url = vm.idolTemplateURL {
                ShareLink(item: url) {
                    ImasNavRow(title: "型紙 JSON をダウンロード (アイドル)", systemImage: "square.and.arrow.down",
                               showsChevron: false, titleLineLimit: 2)
                }
            }

            ImasActionRow(title: "ブランド画像をインポート", systemImage: "tag") {
                AppAnalytics.tap("my_page.brand_image_import")
                showBrandImageImport = true
            }
            if let url = vm.brandTemplateURL {
                ShareLink(item: url) {
                    ImasNavRow(title: "型紙 JSON をダウンロード (ブランド)", systemImage: "square.and.arrow.down",
                               showsChevron: false, titleLineLimit: 2)
                }
            }

            ImasActionRow(title: "ユニット画像をインポート", systemImage: "person.3") {
                AppAnalytics.tap("my_page.unit_image_import")
                showUnitImageImport = true
            }
            if let url = vm.unitTemplateURL {
                ShareLink(item: url) {
                    ImasNavRow(title: "型紙 JSON をダウンロード (ユニット)", systemImage: "square.and.arrow.down",
                               showsChevron: false, titleLineLimit: 2)
                }
            }

            if importer.importedCount > 0 || importer.failedCount > 0 {
                Text(importer.statusMessage).imasText(.note)
            }
            if !importer.failures.isEmpty {
                DisclosureGroup {
                    ForEach(importer.failures) { f in
                        VStack(alignment: .leading, spacing: DS.Space.gapTight / 2) {
                            Text(f.key).imasText(.note)
                            Text(f.reason).imasText(.meta)
                        }
                    }
                } label: {
                    Label("失敗内訳 (\(importer.failures.count) 件)", systemImage: "exclamationmark.triangle")
                        .imasText(.note, color: DS.warning)
                }
            }

            ImasActionRow(title: "カスタム画像を全削除", systemImage: "trash", kind: .destructive) {
                AppAnalytics.tap("my_page.clear_images")
                Task { await importer.clearAllImages() }
            }
        }
    }

    // MARK: - Notification Section

    private func rescheduleNotifications(turnedOn: Bool) {
        Task {
            await NotificationService.shared.rescheduleAll(
                database: database, reason: turnedOn ? .refresh : .settingTurnedOff)
        }
    }

    @ViewBuilder
    private var notificationSection: some View {
        ImasListSection(
            "通知",
            footer: (notifAuthStatus == .authorized || notifAuthStatus == .provisional)
                ? "お気に入りまたは参加マークしたイベントにライブ前・チケット通知を送ります。" : nil
        ) {
            switch notifAuthStatus {
            case .notDetermined, .denied:
                ImasActionRow(title: "通知を許可する", systemImage: "bell.badge") {
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
                }
                if notifAuthStatus == .denied {
                    Text("通知が拒否されています。設定アプリから許可してください。")
                        .imasText(.note, color: DS.warning)
                        .padding(.horizontal, DS.Space.rowH)
                        .padding(.vertical, DS.Space.gapTight)
                }
            default:
                ImasToggleRow(title: "担当アイドルの誕生日", isOn: $notifOshiBirthday)
                    .onChange(of: notifOshiBirthday) { _, isOn in rescheduleNotifications(turnedOn: isOn) }
                ImasToggleRow(title: "ライブ1週間前", isOn: $notifLiveWeek)
                    .onChange(of: notifLiveWeek) { _, isOn in rescheduleNotifications(turnedOn: isOn) }
                ImasToggleRow(title: "チケット締切・当落通知", isOn: $notifTicket)
                    .onChange(of: notifTicket) { _, isOn in rescheduleNotifications(turnedOn: isOn) }
                ImasToggleRow(title: "月曜が近いことを知らせる (日曜 20:00)", isOn: $notifMonday)
                    .onChange(of: notifMonday) { _, isOn in rescheduleNotifications(turnedOn: isOn) }
            }
        }
        .task {
            notifAuthStatus = await NotificationService.shared.authorizationStatus()
        }
    }

    // MARK: - Data Sync Section

    @ViewBuilder
    private var dataSyncSection: some View {
        ImasListSection("データ同期") {
            // 押せない状態表示なので矢印は出さない。末尾は同期中だけくるくる。
            ImasRow(
                title: syncEngine.state.description,
                leading: .icon(syncStateIcon, tone: syncStateTone),
                trailing: isSyncing ? .custom(AnyView(ImasInlineSpinner())) : .none,
                titleLineLimit: 3,
                titleRole: .rowLabel
            )

            ImasActionRow(title: "差分更新", systemImage: "arrow.triangle.2.circlepath") {
                AppAnalytics.tap("my_page.sync_incremental")
                Task { await syncEngine.performIncrementalSync(database: database) }
            }
            .disabled(isSyncing)

            ImasActionRow(title: "全データ同期", systemImage: "arrow.clockwise.icloud") {
                AppAnalytics.tap("my_page.sync_full")
                Task { await syncEngine.performFullSync(database: database) }
            }
            .disabled(isSyncing)

            #if DEBUG
            ImasValueRow(key: "スキーマバージョン", value: vm.schemaVersion)
            ImasValueRow(key: "データバージョン", value: vm.dataVersion)

            if let summary = syncEngine.lastSyncSummary {
                DisclosureGroup {
                    ImasValueRow(key: "modifiedSince", value: summary.modifiedSinceLabel)
                    ImasValueRow(key: "総取得件数", value: "\(summary.totalFetched)")
                    if summary.fetchedByType.isEmpty {
                        ImasNote("(各 RecordType 0 件)")
                    } else {
                        ForEach(summary.fetchedByType.sorted { $0.key < $1.key }, id: \.key) { (k, v) in
                            ImasValueRow(key: k, value: "\(v)")
                        }
                    }
                } label: {
                    Label("直近同期サマリ", systemImage: "list.bullet.rectangle").imasText(.note)
                }
            }
            #endif

            #if DEBUG
            DisclosureGroup {
                ImasValueRow(key: "reseed 結果", value: AppDatabase.lastReseedStatus, copyable: true)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = AppDatabase.lastReseedStatus
                        } label: {
                            Label("コピー", systemImage: "doc.on.doc")
                        }
                    }
            } label: {
                Label("診断", systemImage: "stethoscope").imasText(.note)
            }
            #endif
        }
    }

    // MARK: - Data Backup Section

    @ViewBuilder
    private var dataBackupSection: some View {
        ImasListSection(
            "バックアップ",
            footer: "担当/お気に入りはiCloudで自動バックアップされていますが、これは投票履歴・端末IDも含めた手動バックアップです。機種変更やAndroid版への移行、iCloudが使えない場合にご利用ください。同一端末からの復元でない場合は「端末IDも引き継ぐ」はオフのままにしてください。引き継ぎコードの発行・復元にはログインが必要です。ファイル保存はログイン不要です。"
        ) {
            if let code = transferCode {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    Text(code)
                        .font(ImasNumeralSize.date.font)
                        .foregroundStyle(DS.ink)
                        .textSelection(.enabled)
                    if let expiresAt = transferCodeExpiresAt {
                        Text("24時間有効・1回のみ使用可能です (期限: \(expiresAt.formatted(date: .abbreviated, time: .shortened)))")
                            .imasText(.meta)
                    }
                    Button {
                        UIPasteboard.general.string = code
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.imas(.secondary, size: .small))
                }
                .padding(.horizontal, DS.Space.rowH)
                .padding(.vertical, DS.Space.gap)
            }
            ImasActionRow(title: isCreatingTransferCode ? "発行中..." : "引き継ぎコードを発行する", systemImage: "arrow.up.doc",
                          isLoading: isCreatingTransferCode) {
                AppAnalytics.tap("my_page.backup_create_transfer_code")
                Task { await createTransferCode() }
            }
            .disabled(isCreatingTransferCode)

            HStack(spacing: DS.Space.gap) {
                TextField("引き継ぎコード", text: $importCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                ImasButton(title: "復元", role: .secondary, size: .small, isLoading: isImportingByCode) {
                    AppAnalytics.tap("my_page.backup_import_by_code")
                    Task { await importByCode() }
                }
                .disabled(isImportingByCode || importCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, DS.Space.rowH)
            .padding(.vertical, DS.Space.gapTight)
            .frame(minHeight: DS.Size.touch)

            ImasActionRow(title: "ファイルに保存する", systemImage: "square.and.arrow.up") {
                AppAnalytics.tap("my_page.backup_export_file")
                exportBackupFile()
            }
            if let url = backupFileURL {
                ShareLink(item: url) {
                    ImasNavRow(title: "バックアップファイルを共有", systemImage: "square.and.arrow.up.on.square",
                               showsChevron: false)
                }
            }

            ImasActionRow(title: "ファイルから復元する", systemImage: "square.and.arrow.down") {
                AppAnalytics.tap("my_page.backup_import_file")
                showBackupFileImporter = true
            }

            ImasToggleRow(title: "復元時に端末IDも引き継ぐ(上級者向け・通常はOFF)", isOn: $restoreDeviceIdOnImport)
        }
    }

    // MARK: - Data Stats Section

    @ViewBuilder
    private func dataStatsSection(_ stats: DatabaseStats) -> some View {
        ImasListSection("データ統計") {
            ImasValueRow(key: "楽曲数", value: "\(stats.songCount)曲")
            ImasValueRow(key: "アイドル数", value: "\(stats.idolCount)人")
            ImasValueRow(key: "イベント数", value: "\(stats.eventCount)件")
            ImasValueRow(key: "公演数", value: "\(stats.showCount)公演")
        }
    }

    // MARK: - App Info Section

    @ViewBuilder
    private var appInfoSection: some View {
        ImasListSection("アプリ情報") {
            NavigationLink {
                AboutView()
            } label: {
                ImasNavRow(title: "アプリについて", showsChevron: false)
            }
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                ImasNavRow(title: "プライバシーポリシー", showsChevron: false)
            }
            NavigationLink {
                TermsOfServiceView()
            } label: {
                ImasNavRow(title: "利用規約", showsChevron: false)
            }
            NavigationLink {
                SupportView()
            } label: {
                ImasNavRow(title: "サポート", showsChevron: false)
            }
        }
    }

    // MARK: - Credits Section

    @ViewBuilder
    private var creditsSection: some View {
        ImasListSection("クレジット") {
            Text("本アプリは非公式のファンメイドアプリです。")
                .imasText(.note)
                .padding(.horizontal, DS.Space.rowH)
                .padding(.vertical, DS.Space.gapTight)
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                ImasValueRow(key: "アプリバージョン", value: version)
            }
        }
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

    private var syncStateTone: ImasIconTile.Tone {
        switch syncEngine.state {
        case .idle: return .neutral
        case .syncing: return .solid
        case .completed: return .positive
        case .error:
            return syncEngine.state == .requiresFullResync ? .attention : .negative
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

    // MARK: - Backup / Transfer Code

    private func createTransferCode() async {
        isCreatingTransferCode = true
        defer { isCreatingTransferCode = false }
        do {
            let json = try BackupExportImportService.buildEnvelopeJSON(database: database)
            let (code, expiresAt) = try await BackupTransferClient.createTransferCode(payloadJSON: json)
            transferCode = code
            transferCodeExpiresAt = expiresAt
        } catch {
            transferCodeErrorMessage = error.localizedDescription
        }
    }

    private func importByCode() async {
        let code = importCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isImportingByCode = true
        defer { isImportingByCode = false }
        do {
            let json = try await BackupTransferClient.fetchTransferCode(code)
            applyBackupImport(json: json)
            importCodeInput = ""
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func exportBackupFile() {
        do {
            backupFileURL = try BackupExportImportService.exportToFile(database: database)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func importBackupFromFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let json = try String(contentsOf: url, encoding: .utf8)
            applyBackupImport(json: json)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    /// 引き継ぎコード復元・ファイル復元の共通処理。結果/エラーをアラート用の State に反映する。
    private func applyBackupImport(json: String) {
        do {
            let result = try BackupExportImportService.importEnvelopeJSON(
                json, database: database, restoreDeviceId: restoreDeviceIdOnImport
            )
            importResultMessage = backupImportSummary(
                addedMarks: result.addedMarks,
                addedVotes: result.addedVotes,
                addedPersonalTags: result.addedPersonalTags,
                addedExpenses: result.addedExpenses,
                addedPlaylists: result.addedPlaylists,
                skippedMarks: result.skippedMarks,
                deviceIdRestored: result.deviceIdRestored
            )
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Data Loading

    private func loadAll() async {
        await vm.load()
        syncThemeColor()
    }

    /// 担当テーマ色を現在の選択から再計算し、ContentView 参照用 hex を更新する。
    /// 解決規則は `resolveOshiTheme` (Domain/UseCases) 側でテスト済み。
    private func syncThemeColor() {
        let resolved = resolveOshiTheme(
            isEnabled: useOshiColor,
            currentIdolId: themeOshiIdolId,
            picks: vm.pickIdols
        )
        if let idolId = resolved.idolId {
            themeOshiIdolId = idolId
        }
        themeOshiColorHex = resolved.colorHex
    }
}

// MARK: - ModerationUserID

/// `.sheet(item:)` 駆動用の userId ラッパ (admin モデレーション画面を開く)。
private struct ModerationUserID: Identifiable {
    let id: String
}
