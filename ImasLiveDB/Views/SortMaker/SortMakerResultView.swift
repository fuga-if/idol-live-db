import SwiftUI

/// 結果: 表彰台 (1〜3 位) + 4 位以下の一覧 + 共有。
struct SortMakerResultView: View {
    let model: SortMakerPlayModel

    @Environment(\.dismiss) private var dismiss
    @State private var detail: DetailDestination?
    @State private var showShare = false
    @State private var confirmRestart = false
    @State private var tierBoard: TierListBoard?
    @State private var confirmOverwriteTier = false

    private var subject: SortMakerSubject { model.session.subject }
    private var rows: [(rank: Int, item: SortMakerItem)] { model.rankedItems }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                header
                podium
                if rows.count > 3 {
                    SortMakerRankingList(rows: Array(rows.dropFirst(3))) { detail = $0.detail }
                }
                actions
            }
            .padding(DS.sp5)
        }
        .scrollContentBackground(.hidden)
        .sheet(item: $detail) { dest in
            DetailSheetView(destination: dest)
        }
        .sheet(isPresented: $showShare) {
            SortMakerShareSheet(subject: subject, scopeLabel: model.session.scopeLabel, rows: rows)
        }
        .confirmationDialog("この結果を消して、同じ対象でやり直しますか？", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("設定に戻ってやり直す", role: .destructive) {
                SortMakerStore.shared.clear(subject)
                dismiss()
            }
        }
        .confirmationDialog("作りかけのティアー表を、この結果のたたき台で置き換えますか？",
                            isPresented: $confirmOverwriteTier, titleVisibility: .visible) {
            Button("置き換える", role: .destructive) { makeTierList() }
        }
        .navigationDestination(item: $tierBoard) { TierListView(board: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.sp1) {
            Text("あなたの\(subject == .song ? "好きな曲" : "好きなアイドル")ランキング")
                .font(.imasTitle2.weight(.bold)).foregroundStyle(DS.ink)
            Text("\(model.session.scopeLabel) · \(model.state.answered)戦で決定")
                .font(.imasCaption).foregroundStyle(DS.ink3)
        }
    }

    // MARK: - 表彰台

    @ViewBuilder
    private var podium: some View {
        if let first = rows.first {
            VStack(spacing: DS.sp3) {
                SortMakerPodiumCard(rank: first.rank, item: first.item, large: true) { detail = first.item.detail }
                if rows.count > 1 {
                    HStack(alignment: .top, spacing: DS.sp3) {
                        ForEach(Array(rows.dropFirst().prefix(2).enumerated()), id: \.offset) { _, row in
                            SortMakerPodiumCard(rank: row.rank, item: row.item, large: false) { detail = row.item.detail }
                        }
                        if rows.count == 2 { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }

    // MARK: - 操作

    private var actions: some View {
        VStack(spacing: DS.sp3) {
            Button {
                AppAnalytics.tap("sort_maker.share")
                showShare = true
            } label: {
                Label("結果をシェア", systemImage: "square.and.arrow.up")
                    .font(.imasHeadline).foregroundStyle(DS.onSys)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(DS.sys, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                AppAnalytics.tap("sort_maker.to_tier_list")
                if TierListStore.shared.board(subject) != nil {
                    confirmOverwriteTier = true
                } else {
                    makeTierList()
                }
            } label: {
                Label("この順位でティアー表をつくる", systemImage: "square.stack.3d.up")
                    .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: DS.sp3) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { model.undo() }
                } label: {
                    Label("最後の1戦をやり直す", systemImage: "arrow.uturn.backward")
                        .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!model.canUndo)

                Button {
                    confirmRestart = true
                } label: {
                    Label("もう一度", systemImage: "arrow.clockwise")
                        .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, DS.sp3)
    }
}

extension SortMakerResultView {
    /// 順位からたたき台 (S〜D の振り分け) を作って開く。振り分け規則はコア。
    fileprivate func makeTierList() {
        let board = TierListBoard.fromRanking(subject: subject, scopeLabel: model.session.scopeLabel, rows: rows)
        TierListStore.shared.save(board)
        tierBoard = board
    }
}

/// 表彰台のカード。1 位は大きく、2・3 位は横並び。
struct SortMakerPodiumCard: View {
    let rank: Int
    let item: SortMakerItem
    let large: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ImasTheme.derive(seed: item.seed, brand: BrandColors.hex(for: item.brandId), scheme: scheme)
        Button(action: action) {
            VStack(spacing: DS.sp3) {
                ZStack(alignment: .topLeading) {
                    visual(size: large ? 150 : 96)
                    Text("\(rank)")
                        .font(.imasScaled(large ? 22 : 16, weight: .black)).monospacedDigit()
                        .foregroundStyle(theme.onAccent)
                        .frame(minWidth: large ? 40 : 30, minHeight: large ? 40 : 30)
                        .background(theme.accent, in: Circle())
                        .overlay(Circle().stroke(DS.surface, lineWidth: 3))
                        .offset(x: -10, y: -10)
                }
                VStack(spacing: DS.sp1) {
                    Text(item.title)
                        .font(large ? .imasTitle3.weight(.bold) : .imasSubhead.weight(.bold))
                        .foregroundStyle(DS.ink).multilineTextAlignment(.center).lineLimit(2)
                    if let sub = item.subtitle {
                        Text(sub).font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(1)
                    }
                }
            }
            .padding(large ? DS.sp6 : DS.sp4)
            .frame(maxWidth: .infinity)
            .background(large ? theme.tint : DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank)位 \(item.title)")
    }

    @ViewBuilder
    private func visual(size: CGFloat) -> some View {
        switch item {
        case .song(let song):
            ArtworkImageView(url: song.artworkUrl.flatMap(URL.safeHTTP(string:)), size: size,
                             songTitle: song.title, songId: song.id)
                .allowsHitTesting(false)
        case .idol(let idol):
            IdolAvatarView(idol: idol, size: size, reservesPickRing: false)
        }
    }
}

/// 順位表の一覧 (結果の 4 位以下・対戦中の「いまの順位」)。
struct SortMakerRankingList: View {
    let rows: [(rank: Int, item: SortMakerItem)]
    let onSelect: ((SortMakerItem) -> Void)?

    var body: some View {
        if rows.isEmpty {
            ImasEmptyState(systemImage: "list.number", title: "まだ順位はありません")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.item.id) { i, row in
                    if i > 0 { ImasRowDivider(inset: 96) }
                    rowView(row)
                }
            }
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
    }

    @ViewBuilder
    private func rowView(_ row: (rank: Int, item: SortMakerItem)) -> some View {
        let content = HStack(spacing: DS.sp4) {
            Text("\(row.rank)")
                .font(.imasHeadline).monospacedDigit().foregroundStyle(DS.ink2)
                .frame(width: 32, alignment: .trailing)
            thumb(row.item)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.title).font(.imasBody.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                if let sub = row.item.subtitle {
                    Text(sub).font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.sp4)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        if let onSelect {
            Button { onSelect(row.item) } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private func thumb(_ item: SortMakerItem) -> some View {
        switch item {
        case .song(let song):
            ArtworkImageView(url: song.artworkUrl.flatMap(URL.safeHTTP(string:)), size: 44,
                             songTitle: song.title, songId: song.id)
                .allowsHitTesting(false)
        case .idol(let idol):
            IdolAvatarView(idol: idol, size: 44, reservesPickRing: false)
        }
    }
}
