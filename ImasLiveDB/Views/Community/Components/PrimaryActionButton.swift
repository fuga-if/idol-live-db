import SwiftUI

struct PrimaryActionButton: View {
    let label: String
    let icon: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 8) {
                    if !isLoading {
                        Image(systemName: icon)
                    }
                    Text(label)
                        .fontWeight(.semibold)
                }
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .font(.imasBody)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                (isDisabled || isLoading) ? Color(.systemGray4) : color,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(.white)
        }
        .disabled(isDisabled || isLoading)
        .animation(.smooth(duration: 0.2), value: isLoading)
        .accessibilityLabel(label)
        .accessibilityHint(isLoading ? "送信中" : "")
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryActionButton(label: "投稿する", icon: "paperplane.fill", action: {})
        PrimaryActionButton(label: "送信中...", icon: "paperplane.fill", isLoading: true, action: {})
        PrimaryActionButton(label: "投稿する", icon: "paperplane.fill", isDisabled: true, action: {})
        PrimaryActionButton(label: "更新する", icon: "arrow.up.circle.fill", color: .orange, action: {})
    }
    .padding()
}
