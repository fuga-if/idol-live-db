import SwiftUI

struct SetlistRowView: View {
    @Environment(AppDatabase.self) private var database
    /// 文字サイズ設定。曲名 (生 .system) のスケールに使い、変更時の行再評価の依存源も兼ねる。
    @AppStorage("text_scale") private var textScale: Double = 1.0
    let item: SetlistRow
    var displayNumber: Int? = nil
    var performers: [PerformerRow] = []
    var idolsById: [String: Idol] = [:]
    var unitIndex: UnitIndex? = nil
    /// この公演に出演する全 cast_id (= show_cast)。performer 集合がこれと一致したら「全員」表記。
    var showAllCastIds: Set<String> = []
    /// この公演でユニット単独曲を披露したユニット ID。
    /// 偶然メンバーが揃った合唱曲に過剰マッチするのを防ぐ。
    var activeUnitIds: Set<String> = []
    var isCharacterLive: Bool = false
    var coverType: CoverType = .unknown
    /// 担当アイドル ID。 performer に含まれていれば担当認知 (アバターの二重輪) に委ねる。
    var myPickIdolIds: Set<String> = []
    /// 公演 ID (post-vote like で使う)。
    var showId: String? = nil
    /// 公演名 / 公演日 (感想シェアカードに焼く)。nil ならカードでは省略。
    var showName: String? = nil
    var showDate: String? = nil
    /// 現在の like 集計 + 自分の like 状態。 nil なら 0 票 + 未 like 扱い。
    var likeEntry: SetlistLikeService.LikeEntry? = nil
    /// like トグル成功時に呼ばれ、 親に最新カウントを伝える。
    var onToggleLike: ((SetlistLikeService.LikeResult) -> Void)? = nil
    /// フォールバック (画像なし) のジャケ/チップ色シード。曲のブランド色 hex。
    var brandHex: String? = nil
    /// DetailSheetView の NavigationStack 内で表示された時に渡される push クロージャ。
    /// 非 nil なら曲/出演者遷移は自前 sheet ではなく共有 path に push する (sheet 多重化回避)。
    var navigate: ((DetailDestination) -> Void)? = nil
    @State private var sheetDestination: DetailDestination?
    @State private var showPerformersSheet = false
    @State private var likeBusy = false
    /// 感想シェアカードの compose sheet。
    @State private var showCommentShare = false
    /// Good 投票で未ログイン/失効を検知した時に親へログイン誘導を依頼する
    /// (同一 View に sheet を重ねると発火しないため、提示は親 SetlistView に集約)。
    var onRequireLogin: (() -> Void)? = nil

    /// 遷移の単一窓口。sheet 内は共有 path に push、standalone は自前 sheet。
    private func go(_ dest: DetailDestination) {
        if let navigate {
            navigate(dest)
        } else {
            sheetDestination = dest
        }
    }

    private var performerIdols: [Idol] {
        performers.compactMap { $0.idolId.flatMap { idolsById[$0] } }
    }

    /// 公演に出ている全キャストが歌唱している = 「全員」表記対象。
    /// show_cast が 1 件以上あって、performer の cast 集合がそれと完全一致した時のみ true。
    private var isAllPerformers: Bool {
        guard !showAllCastIds.isEmpty, showAllCastIds.count >= 2 else { return false }
        // PerformerRow.id は cast_id (fetchAllPerformers SQL での alias)
        let performerCastIds = Set(performers.map(\.id))
        return performerCastIds == showAllCastIds
    }

    /// performer 集合からユニット名を逆引き。セトリでは偶然メンバー揃った
    /// だけの subset マッチ (TintMe 等) を避けるため、exact match (単独 or
    /// 2-3 unit の和集合一致) のみ採用。合同曲は両方の unit が返る。
    private var matchingUnits: [Unit] {
        guard let unitIndex else { return [] }
        let perfIds = Set(performerIdols.map(\.id))
        let candidates = unitIndex.exactMatchingUnits(for: perfIds, requireSongs: true)
        // activeUnitIds が空の場合 (e.g., プレビュー / 1曲のみのライブ) はフィルタしない
        if activeUnitIds.isEmpty { return candidates }
        return candidates.filter { activeUnitIds.contains($0.id) }
    }

    /// フォールバック色シード。曲のブランド色。
    private var seed: String? { brandHex }

    @ViewBuilder
    private var likeButton: some View {
        let liked = likeEntry?.hasUserLiked ?? false
        let count = likeEntry?.likeCount ?? 0
        VStack(spacing: 1) {
            Button {
                guard let showId, !likeBusy else { return }
                // 未ログインは投票不可 → 親にログイン誘導を依頼 (黙って失敗させない)。
                guard AuthService.shared.isSignedIn, AuthService.shared.bearerToken != nil else {
                    onRequireLogin?(); return
                }
                likeBusy = true
                Task {
                    defer { likeBusy = false }
                    do {
                        let result = liked
                            ? try await SetlistLikeService.shared.unlike(showId: showId, songId: item.songId)
                            : try await SetlistLikeService.shared.like(showId: showId, songId: item.songId)
                        onToggleLike?(result)
                    } catch LikeError.unauthorized {
                        onRequireLogin?()
                    } catch APIClientError.notAuthorized {
                        onRequireLogin?()
                    } catch {
                        // それ以外 (network 等) は黙る。次回 fetch で正しい状態に。
                    }
                }
            } label: {
                Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.imasScaled( 18, weight: liked ? .semibold : .regular))
                    .foregroundStyle(liked ? DS.pick : DS.ink3)
                    .frame(minWidth: 44, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(likeBusy)
            .accessibilityLabel(liked ? "Good を取り消す" : "この曲が良かった")

            if count > 0 {
                Text("\(count)")
                    .font(.imasDisplay(10))
                    .foregroundStyle(DS.ink3)
            }
        }
        .padding(.top, 6)
    }

    /// カバー/一部カバーを ImasTagChip にマップ (オリメン一致は表示しない)。
    private var coverTag: (text: String, kind: ImasTagChip.Kind)? {
        // 公演の出演者全員で歌う全体曲は、原曲メンバーと完全一致しなくても
        // (新メンバー追加・一部欠席で部分一致になるだけで) カバーではない。
        // この場合「一部カバー」表記を抑制する (全員アンセムの通常パターン)。
        if isAllPerformers, case .partial = coverType { return nil }
        switch coverType {
        case .original, .originalPlus, .unknown: return nil
        case .partial: return ("一部カバー", .partial)
        case .cover: return ("カバー", .cover)
        }
    }

    private var artworkURL: URL? {
        if let u = item.artworkUrl, let url = URL(string: u) { return url }
        return nil
    }
    private var previewURL: URL? {
        if let u = item.previewUrl, let url = URL(string: u) { return url }
        return nil
    }

    /// 担当(マイピック)アイドルがこの曲に出演しているか。左端のピンク帯で示す。
    private var hasMyPick: Bool {
        guard !myPickIdolIds.isEmpty else { return false }
        return performers.contains { $0.idolId.map { myPickIdolIds.contains($0) } ?? false }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 連番 (等幅数字)
            Text("\(displayNumber ?? item.position)")
                .font(.imasDisplay(13))
                .foregroundStyle(DS.ink3)
                .frame(width: 22, alignment: .trailing)
                .padding(.top, 12)

            // ジャケ (画像/プレビュー対応。フォールバックは曲のブランド色ソリッド)。
            // 文字サイズ設定に合わせて縮小し、行全体のサイズ感を揃える。
            ArtworkImageView(
                url: artworkURL,
                size: 44 * CGFloat(textScale),
                previewURL: previewURL,
                songTitle: item.songTitle,
                seed: seed
            )

            VStack(alignment: .leading, spacing: 5) {
                // 曲名タップ → 楽曲詳細シート。タップ領域・折り返しを行幅いっぱいに取り、
                // チップに幅を奪われて単語途中で改行する詰まりを防ぐ。
                Button {
                    Task {
                        if let song = try? await AppContainer.shared.songReading.song(id: item.songId) {
                            go(.song(song))
                        }
                    }
                } label: {
                    Text(item.songTitle)
                        .font(.imasScaled( 16 * textScale, weight: .semibold))
                        .foregroundStyle(DS.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                // List セル内に複数ボタンが同居するため .borderless でタップをスコープ。
                .buttonStyle(.borderless)

                // カバー種別 + 歌唱者 (ユニット / 全員 / アバター) を 1 行にまとめる。
                if hasMeta {
                    metaRow
                }

                if let notes = item.notes {
                    Text(notes)
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .italic()
                }
            }

            Spacer(minLength: 8)

            // 良かった like (公演がセトリ確定 = showId 注入時のみ)。
            if showId != nil {
                likeButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        // 担当アイドルが歌唱 → 左端にピンク帯 (デザイン 03 の pinkbar)。
        .overlay(alignment: .leading) {
            if hasMyPick {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(DS.pick.opacity(0.7))
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        // 長押し → 感想カード (曲名 + コメントのシェア画像) を作る。
        .contextMenu {
            Button {
                showCommentShare = true
            } label: {
                Label("感想カードを作る", systemImage: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $showCommentShare) {
            SetlistCommentComposeSheet(
                songTitle: item.songTitle,
                showName: showName,
                showDate: showDate,
                showId: showId,
                seed: seed,
                artworkUrl: item.artworkUrl
            )
        }
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .sheet(isPresented: $showPerformersSheet) {
            PerformerDetailSheet(
                songTitle: item.songTitle,
                idols: performerIdols
            ) { dest in
                showPerformersSheet = false
                go(dest)
            }
            .environment(database)
        }
    }

    /// メタ行に出すものがあるか (カバー種別チップ or 歌唱者表現)。無ければ行ごと省く。
    private var hasMeta: Bool {
        coverTag != nil || !matchingUnits.isEmpty || isAllPerformers || !performers.isEmpty
    }

    /// カバー種別チップ + 歌唱者 (ユニット / 全員 / アバター) を横一列に。
    @ViewBuilder
    private var metaRow: some View {
        HStack(alignment: .center, spacing: 6) {
            if let tag = coverTag {
                ImasTagChip(text: tag.text, kind: tag.kind, seed: seed)
            }
            performerMeta
        }
    }

    @ViewBuilder
    private var performerMeta: some View {
        if !matchingUnits.isEmpty {
            // ユニット単独曲: ユニット名チップ
            ForEach(matchingUnits) { unit in
                ImasTagChip(text: unit.name, kind: .unit, seed: seed)
            }
        } else if isAllPerformers {
            ImasTagChip(text: "全員", kind: .all, seed: seed)
                .contentShape(Rectangle())
                .onTapGesture { showPerformersSheet = true }
        } else if !performers.isEmpty {
            if !performerIdols.isEmpty {
                StackedAvatars(idols: performerIdols, maxVisible: 5, size: 26 * CGFloat(textScale)) {
                    showPerformersSheet = true
                }
            } else {
                // アイドル情報なし → テキスト chip フォールバック
                FlowLayout(spacing: 4) {
                    ForEach(performers) { performer in
                        PerformerChip(performer: performer, isCharacterLive: isCharacterLive)
                    }
                }
            }
        }
    }
}

private struct PerformerChip: View {
    let performer: PerformerRow
    var isCharacterLive: Bool = false

    /// キャラライブならアイドル名、声優ライブならCV名を表示
    private var displayName: String {
        if isCharacterLive {
            return performer.idolName ?? performer.name
        }
        return performer.name
    }

    /// サブテキスト（キャラライブならCV名、声優ライブならアイドル名）
    private var subName: String? {
        if isCharacterLive {
            return performer.idolName != nil ? "CV:\(performer.name)" : nil
        }
        return performer.idolName
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hexString: performer.idolColor, default: DS.ink3))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(displayName)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                if let sub = subName {
                    Text(sub)
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DS.fill, in: Capsule())
    }
}

/// シンプルなフローレイアウト
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
