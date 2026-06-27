import SwiftUI

/// タブバーの直上に常時表示する同期ステータスバー。
/// 同期中は「○○を同期中…」+ 進捗バー、待機中は「最終同期: …」を控えめに出す。
/// ContentView の TabView に `.safeAreaInset(edge: .bottom)` で差し込む。
struct SyncStatusBar: View {
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    /// 待機/完了表示を一定時間で自動的に畳む。同期中は常に表示。
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>? = nil

    /// 待機/完了を見せておく時間。これを過ぎると勝手に消える。
    private static let autoHideAfter: UInt64 = 4_000_000_000

    var body: some View {
        Group {
            if visible {
                barContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { refresh(isSyncing: syncEngine.isSyncing) }
        .onChange(of: syncEngine.isSyncing) { _, syncing in refresh(isSyncing: syncing) }
    }

    private var barContent: some View {
        let state = syncEngine.state
        return VStack(spacing: 0) {
            // 同期中は実進捗の細いバー、それ以外は区切り線。
            if syncEngine.isSyncing {
                ProgressView(value: syncEngine.syncProgress ?? 0)
                    .progressViewStyle(.linear)
                    .tint(DS.sys)
                    .frame(height: 2)
                    .animation(.easeInOut(duration: 0.25), value: syncEngine.syncProgress)
            } else {
                Rectangle().fill(DS.sep).frame(height: 0.5)
            }

            HStack(spacing: 6) {
                leadingIcon(state)
                    .frame(width: 16, height: 16)
                Text(state.description)
                    .font(.imasCaption.weight(.medium))
                    .foregroundStyle(textColor(state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 5)
        }
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: syncEngine.isSyncing)
    }

    /// 同期中は出しっぱなし、それ以外は出してから autoHideAfter で畳む。
    private func refresh(isSyncing: Bool) {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) { visible = true }
        if isSyncing { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.autoHideAfter)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { visible = false }
        }
    }

    @ViewBuilder
    private func leadingIcon(_ state: CloudKitSyncEngine.SyncState) -> some View {
        switch state {
        case .syncing:
            ProgressView().controlSize(.mini).tint(DS.ink2)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.imasScaled( 13, weight: .semibold)).foregroundStyle(DS.success)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.imasScaled( 13, weight: .semibold)).foregroundStyle(DS.danger)
        case .idle:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.imasScaled( 13, weight: .semibold)).foregroundStyle(DS.ink3)
        }
    }

    private func textColor(_ state: CloudKitSyncEngine.SyncState) -> Color {
        switch state {
        case .error: return DS.danger
        case .syncing: return DS.ink
        default: return DS.ink3
        }
    }
}

extension View {
    /// タブコンテンツの下端 (= タブバーの真上) に同期バーを差し込む。
    /// TabView 自体に付けるとタブバー領域に被るので、各タブのコンテンツに付ける。
    func syncStatusBarInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { SyncStatusBar() }
    }

}
