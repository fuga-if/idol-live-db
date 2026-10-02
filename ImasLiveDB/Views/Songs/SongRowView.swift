import SwiftUI

/// 行がなぜ結果に入っているか。絞り込みの対象と入力語。
///
/// 検索対象ごとに示し方を変えると、同じ一覧なのに読み方を切り替えることになる。
/// どのスコープでも「当たった箇所に同じ色を敷く」に揃える。
struct SongRowMatch: Equatable {
    let text: String
    let scope: SongSearchMode
    /// 行がなぜ当たったかの説明 (「田中琴葉 ほか51人」「作詞 ○○ / 作曲 ○○」)。
    /// 組み立てはコア (`search_match_texts`) で、一覧の ViewModel が絞り込みのたびに 1 回で作る。
    var described: String? = nil
}

/// 並び順の根拠として一覧行に出す指標。
///
/// 「披露回数順」で並べても回数が行に出ていないと、順番だけ見せられて理由が読めない。
/// 並びを変えたときに何が効いているかを行そのものに書く。
enum SongRowMetric: Equatable {
    /// 全公演での披露回数。
    case performances(Int)
    /// 回収率 (回収数 / 披露回数)。
    case collectRate(collected: Int, total: Int)
}

/// 楽曲一覧の 1 行。見た目は `ImasSongRow` (DS の曲の行)。
///
/// 構成: ImasSongRow (ブランドの色の帯 + ジャケ + 曲名) の detail に
///       [歌唱者 ImasAvatarStack + ユニット/演者ラベル] + マイマーク行 (リリース日 / 担当♥ /
///       メモ / 習熟度 / 現地回収✓) を積む。並び順の根拠 (披露回数・回収率) は行の末尾 (`.metric`)。
///
/// ★お気に入りトグルは行から撤去済み (2026-09)。一覧で毎行トグルできても
/// 実際にはほとんど使われず、行の情報密度だけが上がっていた。お気に入り自体は
/// 曲詳細のボタン・お気に入り一覧・絞り込みに残しているので機能は消えていない。
struct SongRowView: View {
    let item: SongWithArtists
    /// 現地回収 N 回 (参加ライブで披露された回数)。 0 / nil なら非表示。
    var collectedCount: Int? = nil
    /// 担当アイドルが歌唱者にいる (歌唱アイドル ∩ 担当 ≠ 空)
    var isMyPick: Bool = false
    /// メモがある
    var hasNote: Bool = false
    /// 習熟度の段階 (0 = 未設定)。付いているときだけ行に小さく出す。
    /// 更新したのが分からないと連続で付けていく作業が成立しないので、
    /// スワイプで変えたら**その場で**行に出る値も変わるようにしている。
    var masteryLevel: UInt8 = 0
    /// 現地回収バッジをタップしたとき (楽曲詳細の披露履歴へ飛ばす導線)。
    var onCollectedTap: (() -> Void)? = nil
    /// タグ絞り込み中、その曲に付いたタグ票数。nil で非表示。
    var tagVoteCount: Int? = nil
    /// 歌詞検索で当たった一節。空なら出さない。
    ///
    /// 曲名だけ並べると「なぜこの曲が出てきたのか」が分からず、理由のない絞り込みに見える。
    var lyricsSnippets: [LyricsSnippet] = []
    /// いま何で絞り込んでいるかと、その語。当たった行に色を敷いて理由を見せる。
    var searchMatch: SongRowMatch? = nil
    /// 並び順の根拠として出す指標。nil なら出さない。
    var metric: SongRowMetric? = nil

    @Environment(\.colorScheme) private var scheme

    private var song: Song { item.song }

    /// フォールバック (画像なし) と行頭の帯に使うブランド色 hex。
    private var brandHex: String? { Self.brandColorHex(for: song.brandId) }

    private var artworkURL: URL? {
        guard let dbUrl = song.artworkUrl else { return nil }
        return URL(string: dbUrl)
    }

    private var previewURL: URL? {
        guard let dbUrl = song.previewUrl else { return nil }
        return URL(string: dbUrl)
    }

    private var isCurrentlyPlaying: Bool {
        MusicKitService.shared.isPlaying(songId: song.id)
    }

    /// 行に出す名義。全体曲は個人名を連ねると行を埋めるので、ユニット名・名義を先に出す。
    private var displayLabel: String {
        // ユニット名 → 名義 (singer_label) → 個人名の並び。規則はコア。曲ごとに 1 回だけ引く
        // (行は描き直しのたびに評価されるので、毎回コアを呼ばない)。
        if let hit = Self.labelCache[song.id] { return hit }
        let names = item.artistNames.isEmpty ? item.performerIdols.map(\.name).joined(separator: "・") : item.artistNames
        let label = songCreditLabel(unitName: song.unitName, singerLabel: song.singerLabel, artistNames: names)
        Self.labelCache[song.id] = label
        return label
    }

    /// 曲 id → 名義。曲のマスタが変わるのは同期のときだけで、そのときは起動し直すまで古くても害は小さい。
    @MainActor private static var labelCache: [String: String] = [:]

    var body: some View {
        ImasSongRow(
            title: song.title,
            artworkURL: artworkURL,
            brandHex: brandHex,
            showsBrandBar: true,
            previewURL: previewURL,
            isPreviewing: isCurrentlyPlaying,
            onPreviewTap: {
                if let previewURL { MusicKitService.shared.togglePreview(url: previewURL, songId: song.id) }
            },
            trailing: trailingMetric,
            attributedTitle: highlightedTitle
        ) {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                if let tagVoteCount {
                    ImasBadge(text: "\(tagVoteCount)", kind: .themed, systemImage: "tag.fill", brand: brandHex)
                }
                performerLine
                creatorLine
                markRow
                // 歌詞検索で当たった一節。語ごとに 1 本ずつ返るが、一覧の行に
                // 3 本も積むと 1 曲で画面が埋まるので 2 本まで。
                ForEach(lyricsSnippets.prefix(2)) { s in
                    LyricsSnippetText(snippet: s, lineLimit: 1)
                }
            }
        }
        .imasCopyable([
            CopyItem("曲名をコピー", song.title, key: "song_title"),
            CopyItem("よみをコピー", song.titleKana, key: "kana"),
            CopyItem("歌唱者をコピー", item.artistNames, key: "artists"),
        ])
    }

    // MARK: - 並び順の根拠 (行の末尾)

    private var trailingMetric: ImasRowTrailing {
        guard let metric else { return .none }
        switch metric {
        case .performances(let count):
            return .metric("\(count)", unit: "回")
        case .collectRate(_, 0):
            // 一度も披露されていない曲の「0%」は率ではなく分母が無いだけ。
            // 率として出すと 0% で回収し損ねたように読める。
            return .metric("0", unit: "回")
        case .collectRate(let collected, let total):
            // 率だけだと「1回のうち1回」も「12回のうち12回」も 100% で並んでしまい、
            // どちらが重いのか読めない。分母の実数 (/ N回) を添える。
            let rate = Int((Double(collected) / Double(total) * 100).rounded())
            return .custom(AnyView(collectRateLabel(rate: rate, total: total)))
        }
    }

    private func collectRateLabel(rate: Int, total: Int) -> some View {
        Label("\(rate)% / \(total)回", systemImage: "music.mic")
            .labelStyle(.titleAndIcon)
            .imasText(.meta)
            .lineLimit(1)
    }

    // MARK: - 歌唱者 + ユニット/演者ラベル

    @ViewBuilder
    private var performerLine: some View {
        if !item.performerIdols.isEmpty {
            HStack(spacing: DS.Space.gap) {
                ImasAvatarStack(people: item.performerIdols.map(Self.performer), maxVisible: 4, size: 22,
                                accessibilityMode: .count(label: "出演者"))
                Text(highlighted(performerText, in: .performer)).imasText(.rowSubtitle)
            }
        } else if !item.artistNames.isEmpty {
            Text(highlighted(item.artistNames, in: .performer)).imasText(.rowSubtitle)
        }
    }

    private static func performer(_ idol: Idol) -> ImasPerformer {
        ImasPerformer(id: idol.id, name: idol.name, color: idol.color, iconLabel: idol.shortName,
                      imageURL: CustomImageService.shared.imageURL(for: idol.id))
    }

    /// アイドルで絞っているときは、**当たった名前を先頭に**出す。
    ///
    /// 普段の表示はユニット名 (`displayLabel`) だが、「田中」で引いた曲が
    /// 「765 MILLION ALLSTARS」としか出ないと、当たった理由が行から消える。
    /// 連名をそのまま出しても 1 行に収まらず、当たった箇所が右端で切れて同じことになる。
    /// よみだけで当たったとき (説明が無いとき) は普段の表示のまま。
    private var performerText: String {
        guard searchMatch?.scope == .performer, let described = searchMatch?.described else {
            return displayLabel
        }
        return described
    }

    /// 作詞・作曲・編曲で絞っているときだけ出す行。普段の一覧には要らない情報なので、
    /// 当たった理由を見せる必要がある時にだけ増やす。
    @ViewBuilder
    private var creatorLine: some View {
        if searchMatch?.scope == .creator, let text = matchedCreatorText {
            Text(highlighted(text, in: .creator)).imasText(.meta, color: DS.ink3)
        }
    }

    /// 一致したクリエイターの役割と名前 (組み立てはコア)。
    private var matchedCreatorText: String? { searchMatch?.described }

    /// 空白を落とした絞り込み語。空なら nil。
    private var trimmedMatch: String? {
        let text = searchMatch?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    // MARK: - マイマーク (リリース日 / 担当♥ / メモ / 現地回収✓)

    @ViewBuilder
    private var markRow: some View {
        if hasAnyMark {
            HStack(spacing: DS.Space.gap) {
                if let date = song.releaseDate {
                    Text(date).imasText(.meta)
                }
                if isMyPick {
                    Label("担当", systemImage: "heart.fill")
                        .labelStyle(.titleAndIcon)
                        .imasText(.meta, color: DS.pick)
                }
                if hasNote {
                    Image(systemName: "pencil").imasText(.meta, color: DS.warning)
                }
                if masteryLevel > 0 {
                    MasteryChip(level: masteryLevel, scale: UserMarkService.shared.scale)
                }
                if let count = collectedCount, count > 0 {
                    let badge = ImasBadge(text: "\(count)", kind: .positive, systemImage: "checkmark")
                    if let onCollectedTap {
                        Button(action: onCollectedTap) { badge }.buttonStyle(.plain)
                    } else {
                        badge
                    }
                }
            }
        }
    }

    private var hasAnyMark: Bool {
        song.releaseDate != nil || isMyPick || hasNote || (collectedCount ?? 0) > 0
            || masteryLevel > 0
    }

    // MARK: - 一致部分のハイライト

    private var highlightedTitle: AttributedString { highlighted(song.title, in: .title) }

    /// 絞り込み語に当たった部分に色を敷く。
    ///
    /// 敷き方そのものは `SearchHighlight` (検索画面と共通) が持つ。ここが決めるのは
    /// 「このスコープで絞っているか」だけ。別のスコープで絞っているときは敷かない
    /// (曲名で絞ったのにアイドル名が光ると、どちらで当たったのか読めなくなる)。
    /// 漢字の曲名を読み仮名で引いた場合は表記側に範囲が無いので、そのときも敷かない。
    private func highlighted(_ source: String, in scope: SongSearchMode) -> AttributedString {
        guard searchMatch?.scope == scope else { return AttributedString(source) }
        return SearchHighlight.attributed(source, matching: trimmedMatch, scheme: scheme)
    }

    // MARK: - Brand color

    /// ブランド ID → マスタのブランド色 hex。 リードバーとジャケフォールバックの seed に使う。
    static func brandColorHex(for brandId: String?) -> String? {
        BrandColors.hex(for: brandId)
    }
}
