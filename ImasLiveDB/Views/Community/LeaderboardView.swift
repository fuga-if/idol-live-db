import SwiftUI

// MARK: - Extended Model (tier対応)

/// ランキング行の表示モデル。貢献度は 2 指標を「個別」に持つ (合成しない。確定契約):
///   - `editCount`     = 編集件数 (ランキングの並び順 & tier 判定の主指標)
///   - `goodsReceived` = 受け取った Good 累計 (人気指標。並びには使わない)
private struct LeaderboardEntryExtended: Identifiable {
    let id: String
    let displayName: String
    let avatarUrl: String?
    let editCount: Int
    let goodsReceived: Int
    let tier: BadgeTier?
}

// MARK: - LeaderboardView

struct LeaderboardView: View {
    @State private var entries: [LeaderboardEntryExtended] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Top 3 podium
                if entries.count >= 3 {
                    podiumSection
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }

                // 4th onwards
                let remaining = entries.dropFirst(3)
                if !remaining.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(remaining.enumerated()), id: \.element.id) { offset, entry in
                            let rank = offset + 4
                            regularRow(rank: rank, entry: entry)
                            if rank < entries.count {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(DS.bg)
        .navigationTitle("貢献ランキング")
        .overlay {
            if isLoading && entries.isEmpty {
                ProgressView("読み込み中...")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if entries.isEmpty && !isLoading {
                EmptyStateCard(
                    icon: "trophy",
                    title: "データなし",
                    message: "まだランキングデータがありません"
                )
            }
        }
        .refreshable { await loadLeaderboard() }
        .task { await loadLeaderboard() }
        .alert("エラー", isPresented: Binding(
            get: { !(errorMessage ?? "").isEmpty },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .trackScreen("leaderboard")
    }

    // MARK: - Podium (top 3)

    @ViewBuilder
    private var podiumSection: some View {
        // Layout: 2nd (left) | 1st (center, taller) | 3rd (right)
        let top3 = Array(entries.prefix(3))
        if top3.count >= 3 {
            HStack(alignment: .bottom, spacing: 10) {
                // 2nd place
                podiumCard(entry: top3[1], rank: 2)
                // 1st place (tallest)
                podiumCard(entry: top3[0], rank: 1)
                // 3rd place
                podiumCard(entry: top3[2], rank: 3)
            }
        }
    }

    @ViewBuilder
    private func podiumCard(entry: LeaderboardEntryExtended, rank: Int) -> some View {
        let medalColor = self.medalColor(for: rank)
        let isFirst = rank == 1

        VStack(spacing: 8) {
            // Medal icon
            Image(systemName: rank == 1 ? "trophy.fill" : "medal.fill")
                .font(isFirst ? .title : .title2)
                .foregroundStyle(medalColor)
                .accessibilityHidden(true)

            leaderboardAvatar(
                entry: entry,
                size: isFirst ? 60 : 48,
                fill: medalColor.opacity(0.15),
                tint: medalColor,
                strokeColor: medalColor.opacity(0.4)
            )

            // Name
            Text(entry.displayName)
                .font(isFirst ? .subheadline : .caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Tier badge (if any)
            if let tier = entry.tier, tier != .none {
                TierBadgeView(tier: tier, size: .small)
            }

            // 編集件数 (主指標 = 並び順の根拠)
            Text("\(entry.editCount)")
                .font(isFirst ? .title2 : .headline)
                .fontWeight(.bold)
                .foregroundStyle(medalColor)
            Text("編集")
                .font(.imasScaled(11))
                .foregroundStyle(DS.ink2)

            // 受け取った Good (人気指標。0 のときも 0 を出す)
            Label("\(entry.goodsReceived)", systemImage: "hands.clap.fill")
                .font(.imasScaled(11).weight(.semibold))
                .foregroundStyle(.pink)
                .labelStyle(.titleAndIcon)

            // Rank platform base
            HStack {
                Spacer()
                Text("\(rank)位")
                    .font(.imasScaled(11))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(medalColor, in: RoundedRectangle(cornerRadius: 6))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, isFirst ? 20 : 12)
        .background(
            medalColor.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(medalColor.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(isFirst ? 1.0 : 0.92)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank)位: \(entry.displayName), 編集\(entry.editCount)件, 受け取ったGood\(entry.goodsReceived)")
    }

    // MARK: - Regular row (4th+)

    @ViewBuilder
    private func regularRow(rank: Int, entry: LeaderboardEntryExtended) -> some View {
        HStack(spacing: 12) {
            TagRankBadge(rank: rank)
                .frame(width: 28, alignment: .center)

            leaderboardAvatar(entry: entry, size: 38, fill: DS.fill, tint: DS.ink2, strokeColor: nil)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.imasBody)
                        .fontWeight(.medium)
                    if let tier = entry.tier, tier != .none {
                        TierBadgeView(tier: tier, size: .small)
                    }
                }
                Label("受け取った Good \(entry.goodsReceived)", systemImage: "hands.clap.fill")
                    .font(.imasCaption)
                    .foregroundStyle(.pink)
                    .labelStyle(.titleAndIcon)
            }

            Spacer()

            // 主指標は編集件数 (並び順の根拠)。
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(entry.editCount)")
                    .font(.imasHeadline)
                    .fontWeight(.bold)
                    .foregroundStyle(DS.ink)
                Text("編集")
                    .font(.imasScaled(11))
                    .foregroundStyle(DS.ink2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank)位: \(entry.displayName), 編集\(entry.editCount)件, 受け取ったGood\(entry.goodsReceived)")
    }

    /// Unified avatar: AsyncImage from URL or a fallback initial-letter circle.
    @ViewBuilder
    private func leaderboardAvatar(
        entry: LeaderboardEntryExtended,
        size: CGFloat,
        fill: Color,
        tint: Color,
        strokeColor: Color?
    ) -> some View {
        let initial = String(entry.displayName.prefix(1))
        let initialFont: Font = size >= 56 ? .title2 : (size >= 44 ? .headline : .subheadline)
        let fallback = Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(initialFont)
                    .fontWeight(.bold)
                    .foregroundStyle(tint)
            }

        Group {
            if let urlString = entry.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                fallback
            }
        }
        .overlay {
            if let strokeColor {
                Circle().stroke(strokeColor, lineWidth: 2)
            }
        }
    }

    // MARK: - Load

    private func loadLeaderboard() async {
        isLoading = true
        errorMessage = nil
        do {
            let plain = try await EditFeedService.shared.fetchLeaderboard()
            entries = plain.map { e in
                LeaderboardEntryExtended(
                    id: e.id,
                    displayName: e.displayName,
                    avatarUrl: e.avatarUrl,
                    editCount: e.editCount,
                    goodsReceived: e.goodsReceived,
                    tier: e.tier.flatMap { BadgeTier(rawValue: $0) }
                )
            }
        } catch {
            errorMessage = "読み込みに失敗しました: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.92, green: 0.72, blue: 0.10) // gold
        case 2: return Color(red: 0.60, green: 0.62, blue: 0.65) // silver
        case 3: return Color(red: 0.72, green: 0.48, blue: 0.30) // bronze
        default: return .gray
        }
    }
}

// MARK: - TierBadgeView

enum TierBadgeSize {
    case small, medium, large
}

struct TierBadgeView: View {
    let tier: BadgeTier
    var size: TierBadgeSize = .medium

    // All size-specific values in one place: (iconFont, labelFont, spacing, hPad, vPad)
    private var metrics: (icon: Font, label: Font, spacing: CGFloat, hPad: CGFloat, vPad: CGFloat) {
        switch size {
        case .small:  return (.caption2, .caption2,    2, 4,  2)
        case .medium: return (.caption,  .caption,     4, 6,  3)
        case .large:  return (.body,     .subheadline, 6, 10, 5)
        }
    }

    var body: some View {
        HStack(spacing: metrics.spacing) {
            Image(systemName: tier.icon)
                .font(metrics.icon)
                .foregroundStyle(tier.color)
            if size != .small {
                Text(tier.label)
                    .font(metrics.label)
                    .foregroundStyle(tier.color)
            }
        }
        .padding(.horizontal, metrics.hPad)
        .padding(.vertical, metrics.vPad)
        .background(tier.color.opacity(0.12), in: Capsule())
        .accessibilityLabel("ランク: \(tier.label)")
    }
}

