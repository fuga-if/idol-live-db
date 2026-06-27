import Nuke
import NukeUI
import SwiftUI

// =============================================================================
// ImasLiveDB — 共通コンポーネント (唯一の正)  ※ design/components.css・ui.css の移植
// すべて ImasTheme のトークンを消費する。フラット基調・謎グラデ排除。
// 既存の同名型と衝突しないよう、新部品は `Imas` プレフィックスで定義する。
// =============================================================================

// MARK: - アイドルアバター (画像なし時 = モノグラム / 担当 = トーナル二重輪 D3)

/// モノグラム・アバター。淡ティント面 + 細リング + アクセント頭文字。
/// 担当 (`isPick`) のときは外側に「トーナル二重輪 (D3)」をまとう。
struct ImasAvatar: View {
    let label: String
    var seed: String?
    var brand: String? = nil
    var size: CGFloat = 40
    var isPick: Bool = false
    var imageURL: URL? = nil

    @Environment(\.colorScheme) private var scheme

    private var ringInset: CGFloat { isPick ? 5.5 : 0 }

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        ZStack {
            if isPick {
                // D3: 外側 grad-to (2px) → accent (1.5px) → surface ギャップ (2px)
                Circle().fill(t.gradTo).frame(width: size + 11, height: size + 11)
                Circle().fill(t.accent).frame(width: size + 7, height: size + 7)
                Circle().fill(DS.surface).frame(width: size + 4, height: size + 4)
            }
            core(t)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(t.ring, lineWidth: 1.5))
        }
        .frame(width: size + ringInset * 2, height: size + ringInset * 2)
        .accessibilityLabel(label)
    }

    @ViewBuilder private func core(_ t: ImasTheme) -> some View {
        if let imageURL {
            let px = Int(size * UIScreen.main.scale)
            LazyImage(url: imageURL) { state in
                if let img = state.image {
                    img.resizable().scaledToFill()
                } else {
                    monogram(t)
                }
            }
            .processors([ImageProcessors.Resize(size: CGSize(width: px, height: px), unit: .pixels)])
        } else {
            monogram(t)
        }
    }

    private func monogram(_ t: ImasTheme) -> some View {
        ZStack {
            t.tint
            Text(label)
                .font(.imasDisplay(size * 0.40, weight: .semibold))
                .foregroundStyle(t.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)
        }
    }
}

// MARK: - ジャケ写 (画像なし時 = ソリッド面 + 曲名)

/// 楽曲ジャケット。実画像があれば表示、無ければアクセント面 + 中央に曲名 (variant C)。
struct ImasArtwork: View {
    let title: String
    var seed: String?
    var brand: String? = nil
    var size: CGFloat = 56
    var imageURL: URL? = nil

    @Environment(\.colorScheme) private var scheme

    private var radius: CGFloat { max(8, size * 0.16) }

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        Group {
            if let imageURL {
                let px = Int(size * UIScreen.main.scale)
                LazyImage(url: imageURL) { state in
                    if let img = state.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        fallback(t)
                    }
                }
                .processors([ImageProcessors.Resize(size: CGSize(width: px, height: px), unit: .pixels)])
            } else {
                fallback(t)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityLabel(title)
    }

    private func fallback(_ t: ImasTheme) -> some View {
        ZStack {
            t.accent
            Text(title)
                .font(.imasScaled( max(9, size * 0.13), weight: .bold))
                .foregroundStyle(t.onAccent)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .padding(size * 0.12)
        }
    }
}

// MARK: - リーディングバー (一覧の控えめなエンティティ色マーカー)

struct ImasLeadBar: View {
    var seed: String?
    var brand: String? = nil
    /// 合同ライブ等で虹色にする。
    var rainbow: Bool = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(rainbow
                  ? AnyShapeStyle(LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple], startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(t.bar))
            .frame(width: 3)
    }
}

// MARK: - Chip / FilterChip

enum ImasChipStyle { case themed, selected, neutral }

/// 除去可能チップ。末尾 × 付きで、全体タップで onRemove を呼ぶ (アクティブフィルタ等)。
/// 配色は seed/brand 由来の accent を淡色 tint で表現 (seed 無しは DS.sys)。
/// 各画面でバラバラに手組みしていた removable chip を 1 部品に統一。
struct ImasRemovableChip: View {
    let text: String
    var seed: String? = nil
    var brand: String? = nil
    let onRemove: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent: Color = (seed != nil || brand != nil)
            ? ImasTheme.derive(seed: seed, brand: brand, scheme: scheme).accent
            : DS.sys
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Text(text).font(.imasScaled( 13.5, weight: .semibold)).lineLimit(1)
                Image(systemName: "xmark").font(.imasScaled( 9, weight: .bold)).opacity(0.8)
            }
            .padding(.leading, 13).padding(.trailing, 10).padding(.vertical, 7)
            .foregroundStyle(accent)
            .background(accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(text) を解除")
    }
}

struct ImasChip: View {
    let text: String
    var systemImage: String? = nil
    var style: ImasChipStyle = .neutral
    var seed: String? = nil
    var brand: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        let (bg, fg): (Color, Color) = {
            switch style {
            case .themed:   return (t.chipBg, t.chipText)
            case .selected: return (t.accent, t.onAccent)
            case .neutral:  return (DS.fill, DS.ink2)
            }
        }()
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.imasScaled( 13, weight: .semibold)) }
            Text(text).font(.imasScaled( 13.5, weight: .semibold))
        }
        .padding(.horizontal, 13).padding(.vertical, 7)
        .foregroundStyle(fg)
        .background(bg, in: Capsule())
        .lineLimit(1)
    }
}

// MARK: - AwardChip

/// 「みんなの投票」終了お題での順位を表すバッジ。優勝=金の塗り、入賞(2〜3位)=金の淡色 tint。
/// 配色はデザインシステムの warning(金) トークンに統一し、チップ家族 (Capsule・同タイポ/余白) と揃える。
/// 曲詳細・アイドル詳細などに差し込んで使う共通部品。
struct ImasAwardChip: View {
    let title: String
    let rank: Int

    private var isWinner: Bool { rank == 1 }
    private var rankLabel: String { isWinner ? "優勝" : "第\(rank)位" }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isWinner ? "crown.fill" : "rosette")
                .font(.imasScaled(12, weight: .semibold))
            Text("\(title) \(rankLabel)")
                .font(.imasScaled(13.5, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 13).padding(.vertical, 7)
        .foregroundStyle(isWinner ? Color.white : DS.warning)
        .background(
            isWinner ? AnyShapeStyle(DS.warning) : AnyShapeStyle(DS.warning.opacity(0.14)),
            in: Capsule()
        )
        .accessibilityLabel("\(title) で\(rankLabel)")
    }
}

// MARK: - SectionHeader

struct ImasSectionHeader: View {
    let title: String
    var count: String? = nil
    var seeAll: (() -> Void)? = nil
    /// tight = 小さめのサブ見出し (実画面の sheadTight)。
    var tight: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if tight {
                Text(title).font(.imasScaled( 13, weight: .semibold)).foregroundStyle(DS.ink2)
            } else {
                HStack(spacing: 8) {
                    Text(title).font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                    if let count { Text(count).font(.imasFootnote.weight(.semibold)).foregroundStyle(DS.ink3) }
                }
            }
            Spacer(minLength: 12)
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 2) {
                        Text("すべて見る").font(.imasScaled( 14, weight: .medium))
                        Image(systemName: "chevron.right").font(.imasScaled( 12, weight: .semibold))
                    }
                    .foregroundStyle(DS.ink2)
                }
            }
        }
    }
}

// MARK: - MetricBadge

struct ImasMetricBadge: View {
    let value: String
    var unit: String = ""
    /// メトリクスを accent 色にするか (一覧ランキング)。false で muted。
    var emphasized: Bool = true
    var seed: String? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.imasDisplay(15, weight: .bold))
            if !unit.isEmpty { Text(unit).font(.imasScaled( 11, weight: .semibold)).opacity(0.85) }
        }
        .foregroundStyle(emphasized ? t.accent : DS.ink2)
    }
}

// MARK: - StatTile (活動サマリ)

struct ImasStatTile: View {
    let systemImage: String
    let value: String
    var unit: String? = nil
    let label: String
    var seed: String? = nil
    var brand: String? = nil
    /// 奥の画面へ遷移できるタイルでは右上にシェブロンを出して「押せる」ことを示す。
    var tappable: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.imasScaled( 18, weight: .semibold))
                    .foregroundStyle(t.chipText)
                    .frame(width: 30, height: 30)
                    .background(t.chipBg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer(minLength: 0)
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.imasScaled( 12, weight: .semibold))
                        .foregroundStyle(DS.ink3)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.imasDisplay(26, weight: .bold)).foregroundStyle(DS.ink)
                if let unit { Text(unit).font(.imasFootnote).foregroundStyle(DS.ink3) }
            }
            Text(label).font(.imasScaled( 12.5, weight: .medium)).foregroundStyle(DS.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - EntryCard (奥の画面への入口)

struct ImasEntryCard: View {
    let systemImage: String
    let title: String
    var preview: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.imasScaled( 24, weight: .regular))
                .foregroundStyle(t.chipText)
                .frame(width: 44, height: 44)
                .background(t.chipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.imasHeadline.weight(.bold)).foregroundStyle(DS.ink)
                if let preview { Text(preview).font(.imasFootnote).foregroundStyle(DS.ink2).lineLimit(2) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.imasScaled( 16, weight: .semibold)).foregroundStyle(DS.ink3)
        }
        .padding(16)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }
}

// MARK: - StatBar (マスタ規模など)

struct ImasStatBar: View {
    let label: String
    let value: String
    /// 0–100。
    let percent: Double
    var seed: String? = nil
    var brand: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(t.dot).frame(width: 8, height: 8)
                Text(label).font(.imasFootnote).foregroundStyle(DS.ink)
            }
            .frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(t.accent).frame(width: geo.size.width * min(1, max(0, percent / 100)))
                }
            }
            .frame(height: 8)
            Text(value).font(.imasDisplay(13, weight: .semibold)).foregroundStyle(DS.ink2)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - RankingRow (曲・人 共通)

struct ImasRankingRow: View {
    enum Lead { case artwork(title: String, imageURL: URL?), avatar(label: String, imageURL: URL?) }
    let rank: Int
    let lead: Lead
    let title: String
    var sub: String? = nil
    let metric: String
    var unit: String = "回"
    var seed: String? = nil
    var brand: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.imasDisplay(17, weight: .bold))
                .foregroundStyle(rank <= 3 ? t.accent : DS.ink3)
                .frame(width: 26)
            switch lead {
            case let .artwork(title, url): ImasArtwork(title: title, seed: seed, brand: brand, size: 44, imageURL: url)
            case let .avatar(label, url): ImasAvatar(label: label, seed: seed, brand: brand, size: 44, imageURL: url)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                if let sub { Text(sub).font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1) }
            }
            Spacer(minLength: 8)
            ImasMetricBadge(value: metric, unit: unit, seed: seed)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(DS.surface)
    }
}

// MARK: - Segmented (詳細画面の内部セグメント)

struct ImasSegmented: View {
    let labels: [String]
    @Binding var selection: Int
    var seed: String? = nil
    var brand: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        HStack(spacing: 2) {
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                let on = idx == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = idx }
                } label: {
                    Text(label)
                        .font(.imasScaled( 13.5, weight: .semibold))
                        .foregroundStyle(on ? DS.ink : DS.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(on ? AnyShapeStyle(DS.surface) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
        .accentEnvironment(t)
    }
}

// MARK: - TagChip (セトリ行のユニット/カバー/全員)

struct ImasTagChip: View {
    enum Kind { case unit, all, cover, partial, lead, guest }
    let text: String
    let kind: Kind
    var seed: String? = nil
    var brand: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        // guest は主演 (塗りつぶし accent) と対比させる控えめな outline バッジ。
        let style: (bg: Color, fg: Color, stroke: Color?) = {
            switch kind {
            case .unit:    return (t.accent.opacity(0.12), t.accent, nil)
            case .all:     return (DS.fill, DS.ink2, nil)
            case .cover:   return (DS.pick.opacity(0.14), DS.pick, nil)
            case .partial: return (DS.warning.opacity(0.14), DS.warning, nil)
            case .lead:    return (t.accent, .white, nil)
            case .guest:   return (.clear, DS.ink2, DS.ink3)
            }
        }()
        Text(text)
            .font(.imasScaled( 11, weight: .semibold))
            .padding(.horizontal, 9).padding(.vertical, 2)
            .foregroundStyle(style.fg)
            .background(style.bg, in: Capsule())
            .overlay(
                style.stroke.map { Capsule().strokeBorder($0, lineWidth: 1) }
            )
    }
}

// MARK: - LabeledRow (よみ / CV / 会場 等の lcRow)

struct ImasLabeledRow: View {
    let key: String
    let value: String
    var showChevron: Bool = false
    var showSwatch: Bool = false
    var mono: Bool = false
    var tappable: Bool = false
    /// タップで省略を解除して全文を改行表示する (特技など長文向け)。
    /// 遷移/コピー等の action を持つ行とは併用しない想定。
    var expandable: Bool = false
    var seed: String? = nil
    var brand: String? = nil
    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        let row = HStack(spacing: 12) {
            Text(key).font(.imasSubhead).foregroundStyle(DS.ink2)
            Spacer(minLength: 12)
            if showSwatch {
                Circle().fill(t.accent).frame(width: 16, height: 16)
            }
            Text(value)
                .font(mono ? .imasDisplay(15) : .imasSubhead)
                .foregroundStyle(tappable ? t.accent : DS.ink)
                .lineLimit(expandable ? (expanded ? nil : 1) : 1)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
            if showChevron {
                Image(systemName: "chevron.right").font(.imasScaled( 13, weight: .semibold)).foregroundStyle(tappable ? t.accent : DS.ink3)
            } else if expandable {
                Image(systemName: "chevron.down")
                    .font(.imasScaled( 11, weight: .semibold)).foregroundStyle(DS.ink3)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(DS.surface)
        .contentShape(Rectangle())

        if expandable {
            row.onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
        } else {
            row
        }
    }
}

// MARK: - EmptyState (投稿導線つき)

struct ImasEmptyState: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var seed: String? = nil
    var brand: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.imasScaled( 28, weight: .regular))
                .foregroundStyle(t.chipText)
                .frame(width: 52, height: 52)
                .background(t.chipBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.bottom, 14)
            Text(title).font(.imasHeadline.weight(.bold)).foregroundStyle(DS.ink)
            if let message {
                Text(message).font(.imasScaled( 13.5)).foregroundStyle(DS.ink2)
                    .multilineTextAlignment(.center).padding(.top, 6).padding(.bottom, 16)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.imasSubhead.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .foregroundStyle(t.onAccent)
                        .background(t.accent, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30).padding(.horizontal, 24)
    }
}

// MARK: - 内部ユーティリティ

private extension View {
    /// セグメント等で tint を統一したいとき用の薄いラッパ (将来拡張点)。
    func accentEnvironment(_ t: ImasTheme) -> some View { self }
}

// MARK: - inset-grouped リスト風コンテナ

/// iOS inset grouped を模した角丸サーフェス。中の行は `Divider().overlay(DS.sep)` で区切る。
struct ImasListContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // 行は左揃え + 幅いっぱい。中央揃えだと幅の足りない行がインデントしてズレる。
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }
}
