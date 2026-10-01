import SwiftUI

/// 結果: 表彰台 (1〜3 位) + 4 位以下の一覧 + 共有。
struct SortMakerResultView: View {
    let model: SortMakerPlayModel

    @Environment(\.dismiss) private var dismiss
    @State private var detail: DetailDestination?
    @State private var showShare = false
    @State private var confirmRestart = false
    @State private var tierBoard: TierListBoard?

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

    private var podium: some View {
        ImasPodium(entries: rows.prefix(3).map { row in
            ImasPodium.Entry(id: row.item.id, rank: row.rank, title: row.item.title, subtitle: row.item.subtitle,
                             seed: row.item.seed, brand: BrandColors.hex(for: row.item.brandId),
                             visual: AnyView(SortMakerVisual(item: row.item, size: row.rank == 1 ? 150 : 96))) {
                detail = row.item.detail
            }
        })
    }

    // MARK: - 操作

    private var actions: some View {
        VStack(spacing: DS.sp3) {
            ImasButton(title: "結果をシェア", systemImage: "square.and.arrow.up", role: .primary, size: .large, fillsWidth: true) {
                AppAnalytics.tap("sort_maker.share")
                showShare = true
            }

            ImasButton(title: "この順位でティアー表をつくる", systemImage: "square.stack.3d.up", role: .secondary, size: .large, fillsWidth: true) {
                AppAnalytics.tap("sort_maker.to_tier_list")
                // ティアー表は何枚でも保存できるので、新しい 1 枚として作る。
                makeTierList()
            }

            HStack(spacing: DS.sp3) {
                ImasButton(title: "最後の1戦をやり直す", systemImage: "arrow.uturn.backward", role: .secondary, size: .large, fillsWidth: true) {
                    withAnimation(.easeInOut(duration: 0.2)) { model.undo() }
                }
                .disabled(!model.canUndo)

                ImasButton(title: "もう一度", systemImage: "arrow.clockwise", role: .secondary, size: .large, fillsWidth: true) {
                    confirmRestart = true
                }
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

/// 曲 (ジャケ) / アイドル (判子) の絵。表彰台・順位表・対戦カードで共通の出し分け。
struct SortMakerVisual: View {
    let item: SortMakerItem
    let size: CGFloat

    var body: some View {
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
            // 全順位 (数百行) を一度に展開しうるので、ここだけは ImasCardList (eager) ではなく
            // LazyVStack にする。でないと数百件ぶんのジャケ読み込みが一斉に走る。
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.item.id) { i, row in
                    if i > 0 { ImasRowDivider(inset: 106) }
                    rowView(row)
                }
            }
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
    }

    @ViewBuilder
    private func rowView(_ row: (rank: Int, item: SortMakerItem)) -> some View {
        let content = ImasRow(title: row.item.title, subtitle: row.item.subtitle,
                              leading: .custom(AnyView(leadingVisual(row)), width: 78))
            .accessibilityElement(children: .combine)
        if let onSelect {
            Button { onSelect(row.item) } label: { content }.buttonStyle(.imasRow)
        } else {
            content
        }
    }

    private func leadingVisual(_ row: (rank: Int, item: SortMakerItem)) -> some View {
        HStack(spacing: DS.sp2) {
            ImasRankNumber(rank: row.rank)
            SortMakerVisual(item: row.item, size: 44)
        }
    }
}
