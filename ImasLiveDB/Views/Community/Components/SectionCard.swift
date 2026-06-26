import SwiftUI

struct SectionCard<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    var headerColor: Color = DS.ink2
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(.imasCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(headerColor)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 12))

            if let footer {
                Text(footer)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
    }
}

// MARK: - SectionCardRow

struct SectionCardRow<Content: View>: View {
    var showDivider: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if showDivider {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            SectionCard(header: "イベント情報", footer: "公演の基本情報を入力してください") {
                SectionCardRow {
                    Text("ラジオ3000% LIVE")
                }
                SectionCardRow {
                    HStack {
                        Text("会場")
                            .foregroundStyle(DS.ink2)
                        Spacer()
                        Text("幕張メッセ")
                    }
                }
                SectionCardRow(showDivider: false) {
                    HStack {
                        Text("日付")
                            .foregroundStyle(DS.ink2)
                        Spacer()
                        Text("2024年3月16日")
                    }
                }
            }
        }
        .padding()
    }
    .background(DS.bg)
}
