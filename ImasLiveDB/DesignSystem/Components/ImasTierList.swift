import SwiftUI

// =============================================================================
// ティアー表 (docs/DESIGN_SYSTEM.md §12.3)
//
// ImasTierHeader   表の名前と振り分けの進み。押すと名前と段の編集を開く (鉛筆の記号つき)。
// ImasTierBoard    段を縦に積む枠。段の間は 2pt の細い隙間、外を角丸で切る。
// ImasTierRow      1 段。左に段の色の札、右に置いたものの面。何かを選んでいるときだけ、札と面が
//                  「ここへ移す」の押し先になる (選んでいないときは押せない)。
// ImasTierLabel    段の色の札。2 文字以下 (S・神) は大きく、長い名前は小さく 2 行まで。
//                  種類: 行の頭 (row)・移す先のボタン (button)・編集の色見本 (swatch)。
// ImasTierItems    段の中・未分類の並び。段の中は回り込み (flow)、未分類は数千件になりうるので
//                  見えている分だけ描く格子 (grid)。空のときは 1 行の文。
// ImasTierChip     表に置く 1 枚 (ジャケかアイコン + 名前 1 行)。選ぶと色の地と枠で浮く。
//                  ドラッグで上に来ている間は左の隙間に墨の縦線 (「この左に入る」の印) を出す。
// ImasTierMoveBar  選んでいる間だけ下に出す「〇〇をどこへ？」の帯。段のボタンを 6 列で折り返し、
//                  最後に未分類へ戻すボタン。
//
// 使わない場面: 順位 (→ ImasRankingRow)・段階の記録 (→ ImasLevelCell)。
// 段の色は段ごとのシード (`TierDef.colorSeed`) を色エンジンに通した accent / onAccent。
// =============================================================================

/// 表の名前と振り分けの進み。押すと名前と段の編集を開く。
struct ImasTierHeader: View {
    let title: String
    let subtitle: String
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: DS.sp1) {
                HStack(spacing: DS.sp2) {
                    Text(title)
                        .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "pencil")
                        .font(.imasScaled(13, weight: .semibold)).foregroundStyle(DS.ink3)
                }
                Text(subtitle).imasText(.meta)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 段を縦に積む枠。
struct ImasTierBoard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: DS.sp1) { content }
            .clipShape(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }
}

/// 1 段。札と面は `isTarget` のときだけ「ここへ移す」の押し先になる。
struct ImasTierRow<Content: View>: View {
    let label: String
    var seed: String?
    /// 何かを選んでいるとき true。
    let isTarget: Bool
    /// 札の読み上げ (「S 3件」など)。
    let accessibilityLabel: String
    let onMoveHere: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: onMoveHere) {
                ImasTierLabel(label: label, seed: seed, style: .row)
            }
            .buttonStyle(.plain)
            .disabled(!isTarget)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isTarget ? "選んだものをここへ移す" : "")

            content
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .background(DS.surface)
                .contentShape(Rectangle())
                .onTapGesture { if isTarget { onMoveHere() } }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 段の色の札。
struct ImasTierLabel: View {
    enum Style {
        /// 行の頭。幅 60・行の高さいっぱい・角なし (枠の角丸で切る)。
        case row
        /// 移す先のボタン。幅いっぱい・押せる高さ。
        case button
        /// 編集の色見本 (押すと色が変わる)。
        case swatch
    }

    let label: String
    var seed: String?
    var style: Style = .row

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ImasTheme.derive(seed: seed, scheme: scheme)
        let text = Text(label)
            .font(.imasScaled(label.count <= 2 ? sizes.large : sizes.small, weight: .black))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .foregroundStyle(theme.onAccent)
        switch style {
        case .row:
            text
                .padding(.horizontal, DS.sp2)
                .frame(width: 60)
                .frame(maxHeight: .infinity)
                .background(theme.accent)
        case .button:
            text
                .padding(.horizontal, DS.sp1)
                .frame(maxWidth: .infinity, minHeight: DS.Size.touch)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
        case .swatch:
            text
                .frame(width: 48, height: 34)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: DS.rXS, style: .continuous))
        }
    }

    /// 2 文字以下 / それより長い名前の文字の大きさ。
    private var sizes: (large: CGFloat, small: CGFloat) {
        switch style {
        case .row: (24, 14)
        case .button: (18, 11)
        case .swatch: (16, 10)
        }
    }
}

/// 段の中・未分類の並び。
struct ImasTierItems<ID: Hashable, Cell: View>: View {
    enum Layout {
        /// 回り込み。段の中 (数が少ない)。
        case flow
        /// 見えている分だけ描く格子。未分類 (全曲を入れると数千件)。
        case grid
    }

    let ids: [ID]
    var layout: Layout = .flow
    /// 空のときの 1 行。nil なら何も出さない。
    var emptyText: String?
    @ViewBuilder let cell: (ID) -> Cell

    var body: some View {
        if ids.isEmpty {
            Text(emptyText ?? "")
                .imasText(.meta)
                .padding(DS.sp4)
        } else {
            switch layout {
            case .flow:
                FlowLayout(spacing: 6) {
                    ForEach(ids, id: \.self) { cell($0) }
                }
                .padding(6)
            case .grid:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(ids, id: \.self) { cell($0) }
                }
                .padding(6)
            }
        }
    }
}

/// 表に置く 1 枚。`media` は渡された大きさのジャケかアイコン。
struct ImasTierChip<Media: View>: View {
    let title: String
    var seed: String?
    var brand: String?
    let isSelected: Bool
    /// ドラッグで上に来ている間 true。左の隙間に「この左に入る」の縦線を出す。
    var showsInsertMark = false
    /// 読み上げの名前。項目が読めなかったときの「不明」など、表示と変えたいときだけ渡す。
    var accessibilityTitle: String? = nil
    @ViewBuilder var media: (_ size: CGFloat) -> Media

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: DS.rSM, style: .continuous)
        VStack(spacing: 3) {
            media(52)
            Text(title)
                .font(.imasCaption2).foregroundStyle(DS.ink2)
                .lineLimit(1)
                .frame(width: 60)
        }
        .padding(3)
        .background(isSelected ? theme.tint : .clear, in: shape)
        .overlay(shape.stroke(theme.accent, lineWidth: isSelected ? 2.5 : 0))
        .scaleEffect(isSelected ? 1.06 : 1)
        .overlay(alignment: .leading) {
            // 並びの隙間 (6pt) の真ん中に 3pt の線。
            if showsInsertMark {
                Capsule().fill(DS.ink)
                    .frame(width: 3)
                    .padding(.vertical, DS.sp1)
                    .offset(x: -4.5)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showsInsertMark)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 選んでいる間だけ下に出す「〇〇をどこへ？」の帯。
struct ImasTierMoveBar: View {
    struct Tier: Identifiable {
        let id: String
        let label: String
        let seed: String?
    }

    let title: String
    let tiers: [Tier]
    let onCancel: () -> Void
    let onMove: (_ tierId: String) -> Void
    let onUnplace: () -> Void

    var body: some View {
        // 段は最大 10。6 個ずつ折り返す (1 行に詰めると押せない幅になる)。
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(6, tiers.count + 1))
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                Text(title)
                    .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                Spacer(minLength: DS.sp2)
                Button("やめる", action: onCancel)
                    .font(.imasSubhead).foregroundStyle(DS.ink2)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(tiers) { tier in
                    Button { onMove(tier.id) } label: {
                        ImasTierLabel(label: tier.label, seed: tier.seed, style: .button)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onUnplace) {
                    Image(systemName: "tray")
                        .font(.imasScaled(16, weight: .semibold))
                        .foregroundStyle(DS.ink2)
                        .frame(maxWidth: .infinity, minHeight: DS.Size.touch)
                        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("未分類へ")
            }
        }
        .padding(.horizontal, DS.sp5)
        .padding(.vertical, DS.sp3)
        .background(.bar)
    }
}
