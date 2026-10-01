import SwiftUI

// =============================================================================
// 状態とお知らせ (docs/DESIGN_SYSTEM.md §11)
//
// ImasStateContainer  読み込み・空・失敗・中身を出し分ける。画面で `if isLoading` を書かない。
// ImasLoadingState    画面全体の読み込み。
// ImasInlineLoading   区画だけの読み込み。
// ImasEmptyState      何もない・見つからない・読めなかった・ログインが要る。
// ImasNotice          読まないと困ること (始められない・失敗した・オフライン)。囲む。
// ImasSignInPrompt    区画の中の「ログインが必要です」。
// .imasSavingOverlay  保存・送信中。
// .imasErrorAlert     操作の失敗。
// .imasConfirmDestructive 消す前の確認。
// =============================================================================

// MARK: - 読み込み

/// 画面・シート全体の読み込み中。空いている領域いっぱいに出して中央に置く。
struct ImasLoadingState: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 区画や一覧の途中の読み込み中。行 1 つ分の高さで横中央に置く。
struct ImasInlineLoading: View {
    /// 暗い地 (ステージ) に置くときの色。
    var tint: Color? = nil

    var body: some View {
        ProgressView()
            .tint(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.section / 2)
    }
}

// MARK: - 空状態

struct ImasEmptyState: View {
    /// 空の理由。理由ごとに記号と言い方を揃える。
    enum Kind {
        /// まだ何もない。
        case empty
        /// 絞り込み・検索で 0 件。
        case noResults
        /// 読み込めなかった。
        case failed
        /// ログインが要る。
        case signInRequired
    }

    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var seed: String? = nil
    var brand: String? = nil

    /// 理由から既定の記号を決める形。題と説明は画面の言葉で渡す。
    init(_ kind: Kind, title: String, message: String? = nil,
         actionTitle: String? = nil, action: (() -> Void)? = nil) {
        switch kind {
        case .empty: self.systemImage = "tray"
        case .noResults: self.systemImage = "magnifyingglass"
        case .failed: self.systemImage = "exclamationmark.triangle"
        case .signInRequired: self.systemImage = "person.crop.circle.badge.exclamationmark"
        }
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    init(systemImage: String, title: String, message: String? = nil, actionTitle: String? = nil,
         action: (() -> Void)? = nil, seed: String? = nil, brand: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.seed = seed
        self.brand = brand
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.imasScaled(32, weight: .light))
                .foregroundStyle(DS.ink3)
                .accessibilityHidden(true)
                .padding(.bottom, DS.Space.gapLoose)
            Text(title)
                .imasText(.cardTitle)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .imasText(.note)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.imas(.primary, size: .medium))
                    .padding(.top, DS.Space.card)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}

// MARK: - 状態の出し分け

/// 画面・区画の中身の状態。
enum ImasContentState: Equatable {
    case loading
    case loaded
    case empty
    case failed(message: String?)
}

/// 読み込み・空・失敗・中身を出し分ける。空と失敗の見せ方は呼び出し側が渡す。
struct ImasStateContainer<Content: View, Empty: View>: View {
    let state: ImasContentState
    /// 初回の読み込みにスケルトンを出す (一覧)。false なら くるくる (詳細)。
    var skeleton: ImasSkeletonKind? = nil
    var onRetry: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var empty: Empty

    var body: some View {
        switch state {
        case .loading:
            if let skeleton {
                switch skeleton {
                case .list(let rows): ImasListSkeleton(rows: rows)
                case .grid: ImasGridSkeleton()
                }
            } else {
                ImasLoadingState()
            }
        case .loaded:
            content
        case .empty:
            empty
        case .failed(let message):
            ImasEmptyState(.failed, title: "読み込めませんでした",
                           message: message ?? "通信状況を確かめて、もう一度試してください。",
                           actionTitle: onRetry == nil ? nil : "もう一度", action: onRetry)
        }
    }
}

enum ImasSkeletonKind {
    case list(rows: Int)
    case grid
}

// MARK: - お知らせの帯

/// 読まないと困ることを囲んで知らせる帯。補足 (読まなくても困らない) は `ImasNote`。
struct ImasNotice: View {
    enum Kind {
        case info, warning, error, success

        var systemImage: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: return DS.ink2
            case .warning: return DS.warning
            case .error: return DS.danger
            case .success: return DS.successInk
            }
        }

    }

    @Environment(\.imasBackdrop) private var backdrop

    let kind: Kind
    var title: String? = nil
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.gapLoose) {
            Image(systemName: kind.systemImage)
                .font(.imasScaled(16, weight: .semibold))
                .foregroundStyle(kind.tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                if let title {
                    Text(title).font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                }
                Text(message)
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.imas(.secondary, size: .small))
                        .padding(.top, DS.Space.gapTight)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.gapLoose + 2)
        // 地は面の色。意味の色は記号だけに出す (色の地も、カードの縁の色の帯も敷かない)。
        .background(DS.surface(on: backdrop), in: RoundedRectangle(cornerRadius: DS.rControl(50), style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ログインの誘い

/// 区画の中の「〇〇にはログインが必要です」。押すとログインのシートを開く。
struct ImasSignInPrompt: View {
    var message: String = "投稿・投票にはログインが必要です"
    @State private var showLogin = false
    @Environment(\.imasBackdrop) private var backdrop

    var body: some View {
        if !AuthService.shared.isSignedIn {
            HStack(spacing: DS.Space.gapLoose) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.imasScaled(18, weight: .regular))
                    .foregroundStyle(DS.ink2)
                Text(message)
                    .font(.imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Space.gap)
                Button("ログイン") {
                    AppAnalytics.tap("inline_login.open")
                    showLogin = true
                }
                .buttonStyle(.imas(.primary, size: .small))
            }
            .padding(.horizontal, DS.Space.rowH)
            .padding(.vertical, DS.Space.gapLoose)
            .background(DS.surface(on: backdrop), in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
            .sheet(isPresented: $showLogin) { LoginToEditSheet() }
        }
    }
}

// MARK: - 保存中・失敗・確認

extension View {
    /// 保存・送信中に画面を覆う。下の操作を止め、何をしているかを 1 語で出す。
    func imasSavingOverlay(_ isSaving: Bool, label: String = "保存中") -> some View {
        overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: DS.Space.gapLoose) {
                        ProgressView().controlSize(.large)
                        Text(label).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
                }
                .transition(.opacity)
            }
        }
        .animation(.imasStandard, value: isSaving)
    }

    /// 操作の失敗を知らせる。題は「〇〇できませんでした」、本文に理由。
    func imasErrorAlert(_ title: String = "保存できませんでした", message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// 消す前の確認。題は「〇〇を削除しますか？」、破壊のボタンは「削除」。
    func imasConfirmDestructive(_ title: String, isPresented: Binding<Bool>, actionTitle: String = "削除",
                                message: String? = nil, action: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(actionTitle, role: .destructive, action: action)
            Button("キャンセル", role: .cancel) {}
        } message: {
            if let message { Text(message) }
        }
    }
}
