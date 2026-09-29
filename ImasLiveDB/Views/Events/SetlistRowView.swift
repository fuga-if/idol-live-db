import SwiftUI

struct SetlistRowView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
    /// 文字サイズ設定。曲名 (生 .system) のスケールに使い、変更時の行再評価の依存源も兼ねる。
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
    /// ので、ここは受け取った順に並べるだけ。詳細表示以外では必ず空で来る。
    ///
    /// 丸い札にはしない。曲の属性 (カバー・ユニット名) と同じ形で並べると 1 行に丸が
    /// 5 つ並び、「・」で繋いだ 1 行にしても並列に並ぶだけで構造にならない。
    /// 軸の名前を左に固定幅で置き、値を右に流す。
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
    /// チップもシートもこれを見る (同じ人の名前を 2 度解決しない)。
    private var resolvedPerformers: [ResolvedPerformer] {
        performers.compactMap { row in
            guard let idol = row.idolId.flatMap({ idolsById[$0] }) else { return nil }
            return ResolvedPerformer(
                idol: idol,
                name: row.displayName(performerName, isCharacterLive: isCharacterLive)
            )
        }
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

    /// オリメンの札を ImasTagChip に写す。色の出し分けは種類だけで決める (文言はコア)。
    private var coverTag: (text: String, kind: ImasTagChip.Kind)? {
        guard let lineup else { return nil }
        let kind: ImasTagChip.Kind = switch lineup.kind {
        case .original, .originalPlus: .unit
        case .partial: .partial
        case .cover: .cover
        }
        return (lineup.label, kind)
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
                .padding(.top, DS.sp4)

            // ジャケ (画像/プレビュー対応。フォールバックは曲のブランド色ソリッド)。
            // 文字サイズ設定に合わせて縮小し、行全体のサイズ感を揃える。
            ArtworkImageView(
                url: artworkURL,
                size: 44 * CGFloat(textScale),
                previewURL: previewURL,
                songTitle: item.songTitle, songId: item.songId,
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

                // 「この曲が何か」(カバー・ユニット・歌唱者) の行。
                if hasMeta {
                    metaRow
                }

                // 「この披露はどうだったか」(披露の履歴・自分の回収) の段。
                noteGroupsBlock

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
                    .padding(.vertical, DS.sp3)
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
                performers: resolvedPerformers
            ) { dest in
                showPerformersSheet = false
                go(dest)
            }
            .environment(database)
        }
    }

    /// メタ行に出すものがあるか (カバー種別チップ or 履歴の札 or 歌唱者表現)。無ければ行ごと省く。
    private var hasMeta: Bool {
        coverTag != nil || !unitNames.isEmpty || isFullCast || !performers.isEmpty
    }

    /// **この曲が何か**の行 — カバー種別チップ + 歌唱者 (ユニット / 全員 / アバター)。
    ///
    /// 披露の履歴と自分の回収はここに入れない ([`notesLine`])。同じ形の札で混ぜると
    /// 「カバー」と「4 回目」が同じ重みに見えて、行が札の羅列になる。
    ///
    /// 横一列 (HStack) ではなく回り込み (FlowLayout) にしてある。幅が足りないとき、
    /// HStack は**札の中の文字を折り返す**ので「1 年 1 か月 / ぶり」と割れて読めなくなる。
    /// 回り込みなら札ごと次の行に落ちる (札は ideal size で置かれるので中では折れない)。
    @ViewBuilder
    private var metaRow: some View {
        FlowLayout(spacing: 6) {
            if let tag = coverTag {
                ImasTagChip(text: tag.text, kind: tag.kind, seed: seed)
            }
            performerMeta
        }
    }

    /// **この披露についての事実**の段 (詳細表示のときだけ来る)。
    ///
    /// ```text
    /// ────────────────────────
    /// 披露   3 回目   2 年 6 か月ぶり
    /// 回収   初回収
    /// ```
    ///
    /// 歌唱者との間にヘアラインを 1 本引いて、「この曲が何か」と「この披露がどうだったか」を
    /// 別のブロックとして読ませる。軸の名前は固定幅で左に置くので、39 曲のセトリでも
    /// 同じ位置に同じ軸が来る (縦に流し読みできる)。
    @ViewBuilder
    private var noteGroupsBlock: some View {
        if !noteGroups.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Rectangle()
                    .fill(DS.sep)
                    .frame(height: 0.5)
                    .padding(.top, 3)
                    .padding(.bottom, 2)
                ForEach(noteGroups, id: \.label) { group in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(group.label)
                            .font(.imasCaption2)
                            .kerning(0.4)
                            .foregroundStyle(DS.ink3)
                            .frame(width: 26, alignment: .leading)
                        Self.notesText(group.notes, accent: accent)
                            .font(.imasCaption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var accent: Color { ImasTheme.derive(seed: seed, scheme: scheme).accent }

    /// 1 つの軸の値を 1 本の `Text` に連結する。
    /// 連結した `Text` は普通の文として折り返すので、幅が足りなくても語の途中で割れない。
    private static func notesText(_ notes: [SetlistRowNoteRecord], accent: Color) -> Text {
        notes.enumerated().reduce(Text("")) { acc, pair in
            let (index, note) = pair
            return acc + (index == 0 ? Text("") : Text("  ")) + noteText(note, accent: accent)
        }
    }

    /// 事実 1 つの見え方。**判断はしない** — core が付けた `tone` に対応表を当てるだけ。
    ///
    /// 色だけで意味を分けると、色が見分けづらい人には全部同じ文字列に見える。
    /// 自分の記録 (回収 / 未回収) には印を付けて、色に頼らず分かるようにする。
    private static func noteText(_ note: SetlistRowNoteRecord, accent: Color) -> Text {
        switch note.tone {
        case .value:
            return Text(note.text).font(.imasCaption.weight(.medium)).foregroundColor(DS.ink)
        case .detail:
            return Text(note.text).foregroundColor(DS.ink3)
        case .debut:
            return Text(note.text).font(.imasCaption.weight(.semibold)).foregroundColor(accent)
        case .mine:
            // 印は細いチェックマークだけ。塗りつぶしのシールはこの大きさだとシール然として
            // 行から浮く (行に貼るのは「済み」の合図であって、賞ではない)。
            return Text(Image(systemName: "checkmark"))
                .font(.imasCaption2.weight(.semibold))
                .foregroundColor(DS.successInk)
                + Text(" ")
                + Text(note.text).font(.imasCaption.weight(.semibold)).foregroundColor(DS.successInk)
        case .missing:
            return Text(Image(systemName: "circle.dotted"))
                .font(.imasCaption2)
                .foregroundColor(DS.ink3)
                + Text(" ")
                + Text(note.text).foregroundColor(DS.ink2)
        }
    }

    @ViewBuilder
    private var performerMeta: some View {
        if !unitNames.isEmpty {
            // ユニット名義の行: ユニット名チップ
            ForEach(unitNames, id: \.self) { name in
                ImasTagChip(text: name, kind: .unit, seed: seed)
            }
        } else if isFullCast {
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
                FlowLayout(spacing: DS.sp2) {
                    ForEach(performers) { performer in
                        PerformerChip(
                            name: performer.displayName(performerName, isCharacterLive: isCharacterLive),
                            colorHex: performer.idolColor
                        )
                    }
                }
            }
        }
    }
}

private struct PerformerChip: View {
    /// 解決済みの表示名。**どちらを出すかの規則は imas-core が持つ**ので、
    /// ここは受け取った主/副を並べるだけ (chip の中で解決し直さない)。
    let name: PerformerDisplayName
    let colorHex: String?

    var body: some View {
        HStack(spacing: DS.sp2) {
            Circle()
                .fill(Color(hexString: colorHex, default: DS.ink3))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(name.primary)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                if let sub = name.secondary {
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
