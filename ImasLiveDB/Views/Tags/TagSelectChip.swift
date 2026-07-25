import SwiftUI

/// タグピッカー (楽曲 / アイドル / ユニット) 共通のタグ選択チップ。
///
/// 3 つのピッカーが同一実装の `tagChip` と WCAG 前景色計算 (`onColor`) をそれぞれ抱えており、
/// 三重複していたのを 1 つに寄せた。配色は `ImasChip(color:)` に委ねる ── タグ色を素で塗らず
/// テーマエンジンの WCAG コントラスト計算を通すので、どんな明るさのタグ色でも文字が読める側に倒れる。
///
/// 状態は 3 つ:
/// - 未適用   → ニュートラル + `plus`
/// - 選択中   → タグ色 + `checkmark.circle.fill`
/// - 適用済み → タグ色 + `checkmark` (押せない)
struct TagSelectChip: View {
    let tag: CommunityTag
    /// すでにこのタグを付けている (これ以上操作させない)。
    let isApplied: Bool
    /// この画面で選択中 (まだ未送信)。
    let isSelected: Bool
    let action: () -> Void

    private var isOn: Bool { isApplied || isSelected }

    private var icon: String {
        if isApplied { return "checkmark" }
        return isSelected ? "checkmark.circle.fill" : "plus"
    }

    /// 使用数はチップ本文に畳む (曲詳細のタグ表示と同じ見せ方に揃える)。
    private var label: String {
        if let uses = tag.totalUses, uses > 0 { return "\(tag.name) \(uses)" }
        return tag.name
    }

    var body: some View {
        ImasFilterChip(
            text: label,
            systemImage: icon,
            isSelected: isOn,
            color: tag.color.map { Color(hexColor: $0) },
            isDisabled: isApplied,
            action: action
        )
        .accessibilityLabel(tag.name)
        .accessibilityHint(isApplied ? "追加済み" : (isSelected ? "選択中" : "タップで追加"))
    }
}
