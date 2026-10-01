import SwiftUI

// =============================================================================
// 全幅・単発のアクション提案バー
//
// 用途      一覧の絞り込み結果から「この範囲でイントロドンを始める」のような、
//           その場限りの単発の提案を 1 本の全幅バーで出す。
// 使わない  恒常的な入口 → `ImasEntryCard` / 読まないと困る注意 → `ImasNotice`
// 構成      [記号] [文言] [補足 (件数など、任意)] ……… [閉じる × (任意)]
// 種類      `.prominent` (強い提案。墨の塗り、無効時は薄灰) / `.subtle` (弱い提案。墨の薄い地)
// 状態      通常 / 無効 (`isEnabled: false` で `.prominent` は薄灰になり押せなくなる)
// =============================================================================

/// 全幅・単発のアクション提案バー。
struct ImasSuggestionBar: View {
    enum Style {
        /// 強い提案 (選択を確定させる導線など)。墨の塗り。
        case prominent
        /// 弱い提案 (一覧の下にそっと置く誘い)。墨の薄い地。
        case subtle
    }

    let systemImage: String
    let title: String
    /// 文言の後ろに添える補足 (「12曲」「4曲以上必要」)。
    var detail: String? = nil
    var style: Style = .subtle
    var isEnabled: Bool = true
    let action: () -> Void
    /// 右端の閉じる記号。渡すと表示し、押すとこれを呼ぶ (提案そのものを隠す)。
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: DS.Space.gap) {
                    Image(systemName: systemImage).font(.imasScaled(14, weight: .bold))
                    Text(title).font(.imasHeading(15, weight: .bold)).lineLimit(1)
                    if let detail {
                        Text(detail).font(.imasFootnote).foregroundStyle(detailColor).lineLimit(1)
                    }
                    Spacer(minLength: DS.Space.gap)
                }
                .foregroundStyle(titleColor)
                .padding(.horizontal, DS.Space.screen)
                .padding(.vertical, DS.Space.gap + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.imasScaled(12, weight: .bold))
                        .foregroundStyle(DS.ink2)
                        .padding(.trailing, DS.Space.screen)
                        .padding(.vertical, DS.Space.gap + 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("提案を閉じる")
            }
        }
        .background(background)
    }

    private var background: Color {
        switch style {
        case .prominent: return isEnabled ? DS.sys : DS.fill
        case .subtle: return DS.sys.opacity(0.10)
        }
    }

    private var titleColor: Color {
        switch style {
        case .prominent: return isEnabled ? DS.onSys : DS.ink3
        case .subtle: return DS.sys
        }
    }

    private var detailColor: Color {
        switch style {
        case .prominent: return (isEnabled ? DS.onSys : DS.ink3).opacity(0.85)
        case .subtle: return DS.ink2
        }
    }
}
