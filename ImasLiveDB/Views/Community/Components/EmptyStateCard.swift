import SwiftUI

struct EmptyStateCard: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.imasScaled( 44))
                .foregroundStyle(DS.ink3)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.imasHeadline)
                    .foregroundStyle(DS.ink)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink2)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.imasSubhead)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    EmptyStateCard(
        icon: "tray",
        title: "投稿がありません",
        message: "このカテゴリの投稿はまだありません",
        actionLabel: "最初に投稿する",
        action: {}
    )
}
