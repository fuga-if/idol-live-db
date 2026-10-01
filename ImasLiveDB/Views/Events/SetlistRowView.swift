import SwiftUI

struct SetlistRowView: View {
    @Environment(AppDatabase.self) private var database
    /// 文字サイズ設定。歌唱者アイコンの束・ジャケのスケールに使い、変更時の行再評価の依存源も兼ねる。
    @AppStorage("text_scale") private var textScale: Double = 1.0
    let item: SetlistRow
    var displayNumber: Int? = nil
    var performers: [PerformerRow] = []
    var idolsById: [String: Idol] = [:]
    /// ユニット名のチップに出す名前。**どのユニット名を出すかは imas-core が決める**
    /// (その披露の名義 → 曲の名義 → 顔ぶれ推論)。空ならチップを出さない。
    var unitNames: [String] = []
    /// 公演の出演者全員で歌う行か (「全員」表記)。判定も imas-core。
    var isFullCast: Bool = false
    /// この披露についての事実を、軸 (`披露` / `回収`) ごとにまとめたもの。
    /// **軸の分け方も、ラベルも、順も、どれを強く見せるか (`tone`) も imas-core が決める**
    /// ので、ここは受け取ったまま `ImasSetlistRow` に渡す。詳細表示以外では必ず空で来る。
    var noteGroups: [SetlistRowNoteGroupRecord] = []
    /// 歌唱者をどの名前で出すか (親が AppStorage から解決して渡す)。
    var performerName: PerformerNameMode = .idolOnly
    /// `shows.performer_type == "character"`。
    ///
    /// 以前は既定値のまま誰も渡しておらず、キャラライブ分岐が死んでいた。
    var isCharacterLive: Bool = false
    /// オリメンの札 (`オリメン` / `オリメン+α` / `オリメン 4/5` / `オリメン不在`)。
    /// 付けるか・文言はコア (`SetlistRowMetaRecord.lineup`) が決める。nil = 付けない。
    var lineup: SetlistLineupNote? = nil
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

    /// アイドルと表示名を 1 組にした並び。**解決はここ 1 箇所**で、
    /// アバターの束もシートもこれを見る (同じ人の名前を 2 度解決しない)。
    private var resolvedPerformers: [ResolvedPerformer] {
        performers.compactMap { row in
            guard let idol = row.idolId.flatMap({ idolsById[$0] }) else { return nil }
            return ResolvedPerformer(
                idol: idol,
                name: row.displayName(performerName, isCharacterLive: isCharacterLive)
            )
        }
    }

    /// `ImasSetlistRow`/`ImasAvatarStack` に渡す形。アイドルが分かる人は判子の略称と写真を持たせ、
    /// アイコンを出せるようにする (アイコンを消さない)。
    private var rowPerformers: [ImasPerformer] {
        performers.map { row in
            let idol = row.idolId.flatMap { idolsById[$0] }
            return ImasPerformer(
                id: row.id,
                name: row.displayName(performerName, isCharacterLive: isCharacterLive).joined,
                color: row.idolColor,
                iconLabel: idol?.shortName,
                imageURL: row.idolId.flatMap { CustomImageService.shared.imageURL(for: $0) }
            )
        }
    }

    /// フォールバック色シード。曲のブランド色。
    private var seed: String? { brandHex }

    /// オリメンの札 (役割の札の 1 つ目)。
    private var lineupBadge: ImasBadgeSpec? {
        guard let lineup else { return nil }
        let kind: ImasBadge.Kind = switch lineup.kind {
        case .original, .originalPlus: .unit
        case .partial: .partial
        case .cover: .cover
        }
        return ImasBadgeSpec(text: lineup.label, kind: kind, seed: seed)
    }

    /// 役割の札。ユニット名義 / 全員 / オリメン を並べる (ユニット名・全員の札は今どおり)。
    private var badges: [ImasBadgeSpec] {
        var result: [ImasBadgeSpec] = []
        if let lineupBadge { result.append(lineupBadge) }
        if !unitNames.isEmpty {
            result.append(contentsOf: unitNames.map { ImasBadgeSpec(text: $0, kind: .unit, seed: seed) })
        } else if isFullCast {
            result.append(ImasBadgeSpec(text: "全員", kind: .all, seed: seed))
        }
        return result
    }

    /// 歌唱者の行。ユニット名義だけの行は顔ぶれを出さない (チップが名義を言い切っている)。
    /// 全員・個別歌唱は顔ぶれ (アイコンの束) を出す。
    private var performersForRow: [ImasPerformer] {
        unitNames.isEmpty ? rowPerformers : []
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

    /// ジャケ (画像/プレビュー対応。フォールバックは曲のブランド色ソリッド)。
    /// 文字サイズ設定に合わせて縮小し、行全体のサイズ感を揃える。
    private var customArtwork: AnyView {
        AnyView(
            ArtworkImageView(
                url: artworkURL,
                size: 44 * CGFloat(textScale),
                previewURL: previewURL,
                songTitle: item.songTitle, songId: item.songId,
                seed: seed
            )
        )
    }

    @ViewBuilder
    private var trailing: some View {
        if showId != nil {
            ImasLikeButton(isOn: likeEntry?.hasUserLiked ?? false, count: likeEntry?.likeCount ?? 0,
                          isBusy: likeBusy, action: toggleLike)
        }
    }

    private func toggleLike() {
        guard let showId, !likeBusy else { return }
        let liked = likeEntry?.hasUserLiked ?? false
        // 未ログインは投票不可 → 親にログイン誘導を依頼 (黙って失敗させない)。
        // bearerToken の事前チェックはしない (セッション更新中の窓で bearerToken == nil に
        // なる瞬間があり、401 の自動リフレッシュを潰して誤ってログイン誘導してしまうため)。
        guard AuthService.shared.isSignedIn else {
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
    }

    /// 曲名タップ → 楽曲詳細シート。曲は id だけ持っているので取得してから遷移する。
    private func selectTitle() {
        Task {
            if let song = try? await AppContainer.shared.songReading.song(id: item.songId) {
                go(.song(song))
            }
        }
    }

    var body: some View {
        ImasSetlistRow(
            number: "\(displayNumber ?? item.position)",
            title: item.songTitle,
            seed: seed,
            performers: performersForRow,
            badges: badges,
            customArtwork: customArtwork,
            onSelectTitle: selectTitle,
            onSelectPerformers: { showPerformersSheet = true },
            highlightsPick: hasMyPick,
            trailing: .custom(AnyView(trailing)),
            noteGroups: noteGroups,
            note: item.notes
        )
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
                performers: resolvedPerformers
            ) { dest in
                showPerformersSheet = false
                go(dest)
            }
            .environment(database)
        }
    }
}
