import SwiftUI

// MARK: - 図解の部品 (よその画面の見立て)

/// 手順の図に置く、よその Web 画面の見立て (Spotify の開発者サイトなど)。上に URL、下に中身。
/// 本物の見た目は写さず、紙の窓に「どこを押すか」だけを描く。読み上げからは隠す (手順の文が同じことを言う)。
struct ImasMockBrowser<Content: View>: View {
    let url: String
    @ViewBuilder var content: Content

    var body: some View {
        ImasCard(style: .inset) {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                Label(url, systemImage: "lock.fill")
                    .font(ImasTextRole.meta.font.monospaced())
                    .foregroundStyle(DS.ink3)
                    .lineLimit(1)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

/// 見立ての中のボタン。押す所 (`isTarget`) は墨で塗る (主ボタンと同じ見え方で「ここを押す」と読ませる)。
struct ImasMockButton: View {
    let title: String
    var isTarget = false

    var body: some View {
        Text(title)
            .imasText(.chip, color: isTarget ? DS.onSys : DS.ink)
            .padding(.horizontal, DS.Space.rowGap)
            .padding(.vertical, DS.Space.gap)
            .background(isTarget ? DS.sys : DS.fill, in: .rect(cornerRadius: DS.rControl(32)))
    }
}

/// 見立ての中の入力欄・値の欄。触る所には「ここ」の札、使わない欄は薄く「使わない」の札。
struct ImasMockField: View {
    let label: String
    let value: String
    var isTarget = false
    var isUnused = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            HStack(spacing: DS.Space.gap) {
                Text(label).imasText(.meta)
                if isTarget { ImasBadge(text: "ここ", kind: .lead) }
                if isUnused { ImasBadge(text: "使わない", kind: .neutral) }
            }
            Text(value)
                .font(ImasTextRole.value.font.monospaced())
                .foregroundStyle(isUnused ? DS.ink3 : DS.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(DS.Space.gap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.fill, in: .rect(cornerRadius: DS.rXS))
        }
    }
}

/// 見立ての中のチェック欄。入れる所には「ここ」の札。
struct ImasMockCheck: View {
    let label: String
    var isChecked = false

    var body: some View {
        HStack(spacing: DS.Space.gap) {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .foregroundStyle(isChecked ? DS.ink : DS.ink3)
            Text(label).imasText(.value, color: isChecked ? DS.ink : DS.ink3)
            if isChecked { ImasBadge(text: "ここ", kind: .lead) }
        }
    }
}
