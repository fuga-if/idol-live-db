import SwiftUI

// =============================================================================
// フィルタシート共通の体裁。
//
// 以前は 4 つのフィルタシート (ライブ / アイドル / タグ / 楽曲) で
//  - リストスタイルが .plain と既定 (inset grouped) で混在
//  - 背景が DS.bg のものと未指定のものが混在
//  - 「リセット」がツールバーとリスト内セクションに二重掲載
// と揃っておらず、同じ「フィルタ」なのに画面ごとに別物に見えていた。
// 体裁とツールバーをここに集約し、各シートは中身 (Section) だけを書く。
// =============================================================================

extension View {
    /// フィルタシートのリスト体裁 (背景・スクロール背景の抑止)。
    /// 行の面は `.listRowBackground(DS.surface)` を各 Section に付ける。
    func imasFilterSheetChrome() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .navigationTitle("フィルタ")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// フィルタシート共通のツールバー: 左「リセット」/ 右「適用」。
///
/// リセットは **ツールバーにだけ** 置く。以前はリスト末尾にも destructive な
/// 「リセット」セクションがあり、同じ操作が 1 画面に 2 つ存在していた。
/// 条件が何も付いていないときは disabled にして、押せる/押せないで状態を示す。
@MainActor @ToolbarContentBuilder
func filterSheetToolbar(
    analyticsPrefix: String,
    canReset: Bool,
    onReset: @escaping @MainActor () -> Void,
    onApply: @escaping @MainActor () -> Void
) -> some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
        Button("リセット") {
            AppAnalytics.tap("\(analyticsPrefix).reset")
            onReset()
        }
        .disabled(!canReset)
    }
    ToolbarItem(placement: .topBarTrailing) {
        Button("適用") {
            AppAnalytics.tap("\(analyticsPrefix).apply")
            onApply()
        }
        .fontWeight(.bold)
    }
}
