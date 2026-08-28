import SwiftUI

/// 行がなぜ結果に入っているか。絞り込みの対象と入力語。
///
/// 検索対象ごとに示し方を変えると、同じ一覧なのに読み方を切り替えることになる。
/// どのスコープでも「当たった箇所に同じ色を敷く」に揃える。
struct SongRowMatch: Equatable {
    let text: String
    let scope: SongSearchMode
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

/// 楽曲一覧の 1 行 (新デザインシステム移植版)。
///
/// 構成: ImasLeadBar(ブランド) + ArtworkImageView(実ジャケ×ソリッドフォールバック, プレビュー対応)
///       + 曲名 + [歌唱者 StackedAvatars + ユニット/演者ラベル]
///       + マイマーク行 (リリース日 / 担当♥ / メモ / 現地回収✓) + ★お気に入りトグル。
///
/// 実ジャケと「画像なし=ソリッド面+曲名」が同列で違和感なく並ぶよう、ArtworkImageView に
/// ブランド色 seed を渡してフォールバックをテーマ色で表現する。
struct SongRowView: View {
    let item: SongWithArtists
    /// 現地回収 N 回 (参加ライブで披露された回数)。 0 / nil なら非表示。
    var collectedCount: Int? = nil
    /// お気に入りマーク
    var isFavorite: Bool = false
    /// 担当アイドルが歌唱者にいる (歌唱アイドル ∩ 担当 ≠ 空)
    var isMyPick: Bool = false
    /// メモがある
    var hasNote: Bool = false
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

    /// フォールバック (画像なし) と行頭リードバーに使うブランド色 hex。
    private var brandHex: String? { Self.brandColorHex(for: song.brandId) }

    /// タグ票数バッジの色。行のブランド色から導出する
    /// (DS 原則: システム accent を塗らず、色は常にエンティティ側から来る)。
    private var tagBadgeAccent: Color {
        ImasTheme.derive(seed: nil, brand: brandHex, scheme: scheme).accent
    }

    private var artworkURL: URL? {
        guard let dbUrl = song.artworkUrl else { return nil }
        return URL(string: dbUrl)
    }

    private var previewURL: URL? {
        guard let dbUrl = song.previewUrl else { return nil }
        return URL(string: dbUrl)
    }

    /// 表示用ラベル: ユニット名/全体名 (あれば) を優先、無ければアイドル個別名連結。
    /// - song.unitName が DB にあればそれ
    /// - artistNames が "MILLIONSTARS（...）" 形式ならカッコ前を抜き出し (全体曲・ユニット名カッコ表記対応)
    /// - 落ちる場合は performerIdols の名前を「・」で繋ぐ
    private var displayLabel: String {
        if let unit = song.unitName, !unit.isEmpty { return unit }
        let label = item.artistNames
        if !label.isEmpty {
            for sep in ["（", "("] {
                if let idx = label.firstIndex(of: Character(sep)) {
                    let prefix = label[..<idx].trimmingCharacters(in: .whitespaces)
                    if !prefix.isEmpty { return prefix }
                }
            }
        }
        return item.performerIdols.map(\.name).joined(separator: "・")
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.sp4) {
            // 行頭の控えめなブランド色マーカー (集約 = 細いリードバー)。
            ImasLeadBar(brand: brandHex)
                .frame(height: 50)

            // 実ジャケ × ソリッドフォールバック (プレビュー再生対応)。
            ArtworkImageView(
                url: artworkURL,
                size: 50,
                previewURL: previewURL,
                songTitle: song.title,
                seed: brandHex
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(highlightedTitle)
                        .font(.imasHeadline.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    if let tagVoteCount {
                        HStack(spacing: 3) {
                            Image(systemName: "tag.fill").font(.imasScaled( 9, weight: .bold))
                            Text("\(tagVoteCount)").font(.imasCaption.weight(.bold)).monospacedDigit()
                        }
                        .foregroundStyle(tagBadgeAccent)
                        .padding(.horizontal, 6).padding(.vertical, DS.sp1)
                        .background(tagBadgeAccent.opacity(0.14), in: Capsule())
                    }
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
            .padding(.top, 1)

            Spacer(minLength: 0)

            FavoriteToggleButton(entity: .song, id: song.id)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .imasCopyable([
            CopyItem("曲名をコピー", song.title, key: "song_title"),
            CopyItem("よみをコピー", song.titleKana, key: "kana"),
            CopyItem("歌唱者をコピー", item.artistNames, key: "artists"),
        ])
    }

    // MARK: - 歌唱者 + ユニット/演者ラベル

    @ViewBuilder
    private var performerLine: some View {
        if !item.performerIdols.isEmpty {
            HStack(spacing: 7) {
                StackedAvatars(idols: item.performerIdols, maxVisible: 4, size: 22)
                Text(highlighted(performerText, in: .performer))
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(1)
            }
        } else if !item.artistNames.isEmpty {
            Text(highlighted(item.artistNames, in: .performer))
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
                .lineLimit(1)
        }
    }

    /// アイドルで絞っているときは、**当たった名前を先頭に**出す。
    ///
    /// 普段の表示はユニット名 (`displayLabel`) だが、「田中」で引いた曲が
    /// 「765 MILLION ALLSTARS」としか出ないと、当たった理由が行から消える。
    /// 連名をそのまま出しても 1 行に収まらず、当たった箇所が右端で切れて同じことになる。
    private var performerText: String {
        guard searchMatch?.scope == .performer, let needle = trimmedMatch else {
            return displayLabel
        }
        if let matched = item.performerIdols.first(where: { contains($0.name, needle) }) {
            return withOtherCount(matched.name)
        }
        // 出演アイドルに無く歌唱者表記で当たった場合 (song_artists 未整備の曲など)。
        for label in [song.unitName, song.singerLabel, item.artistNames].compactMap({ $0 }) {
            if let segment = matchedSegment(in: label, needle) { return withOtherCount(segment) }
        }
        // よみだけで当たった場合。表記側に範囲が無いので敷けないが、誰なのかは出す。
        return displayLabel
    }

    /// 「田中琴葉 ほか51人」。当たった 1 人だけだと規模が分からないので人数を添える。
    private func withOtherCount(_ name: String) -> String {
        let others = max(0, item.performerIdols.count - 1)
        return others > 0 ? "\(name) ほか\(others)人" : name
    }

    /// 連名表記 (「天海春香、春日未来、…」) から、当たった 1 人ぶんだけ抜き出す。
    private func matchedSegment(in label: String, _ needle: String) -> String? {
        label.split(whereSeparator: { "、,・/／".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { contains($0, needle) }
    }

    /// 作詞・作曲・編曲で絞っているときだけ出す行。普段の一覧には要らない情報なので、
    /// 当たった理由を見せる必要がある時にだけ増やす。
    @ViewBuilder
    private var creatorLine: some View {
        if searchMatch?.scope == .creator, let text = matchedCreatorText {
            Text(highlighted(text, in: .creator))
                .font(.imasCaption2)
                .foregroundStyle(DS.ink3)
                .lineLimit(1)
        }
    }

    /// 一致したクリエイターの役割と名前。複数の役割で当たったらまとめて出す。
    private var matchedCreatorText: String? {
        guard let needle = trimmedMatch else { return nil }
        let parts = [("作詞", song.lyricist), ("作曲", song.composer), ("編曲", song.arranger)]
            .compactMap { role, name -> String? in
                guard let name, contains(name, needle) else { return nil }
                return "\(role) \(name)"
            }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    /// 空白を落とした絞り込み語。空なら nil。
    private var trimmedMatch: String? {
        let text = searchMatch?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// 行がなぜ出ているかを説明するときの一致判定。
    ///
    /// 規則は `String.searchMatchRange(of:)` (= コアの照合そのもの) に任せる。
    /// ここに条件を書き足すと、一覧に載せる判定と食い違う。
    private func matchRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        haystack.searchMatchRange(of: needle)
    }

    private func contains(_ haystack: String, _ needle: String) -> Bool {
        matchRange(of: needle, in: haystack) != nil
    }

    // MARK: - マイマーク (リリース日 / 担当♥ / メモ / 現地回収✓)

    @ViewBuilder
    private var markRow: some View {
        if hasAnyMark {
            HStack(spacing: DS.sp3) {
                if let date = song.releaseDate {
                    Text(date)
                        .font(.imasDisplay(11, weight: .regular))
                        .foregroundStyle(DS.ink3)
                }
                if isMyPick {
                    Label("担当", systemImage: "heart.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.imasScaled( 11, weight: .semibold))
                        .foregroundStyle(DS.pick)
                }
                if hasNote {
                    Image(systemName: "pencil")
                        .font(.imasScaled( 11, weight: .semibold))
                        .foregroundStyle(DS.warning)
                }
                if let metric {
                    metricBadge(metric)
                }
                if let count = collectedCount, count > 0 {
                    let badge = HStack(spacing: DS.sp1) {
                        Image(systemName: "checkmark")
                        Text("\(count)").font(.imasDisplay(11, weight: .bold))
                    }
                    .font(.imasScaled( 11, weight: .semibold))
                    .foregroundStyle(DS.success)
                    if let onCollectedTap {
                        Button(action: onCollectedTap) { badge.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                    } else {
                        badge
                    }
                }
            }
        }
    }

    private var hasAnyMark: Bool {
        song.releaseDate != nil || isMyPick || hasNote || (collectedCount ?? 0) > 0
            || metric != nil
    }

    /// 並び順の根拠 (披露回数 / 回収率)。
    ///
    /// 回収率は分子 (回収数) が隣の ✓ バッジに出ているので、ここでは率と母数を出す。
    /// 率だけだと「1回のうち1回」も「12回のうち12回」も 100% で並んでしまい、
    /// どちらが重いのか読めない。
    private func metricBadge(_ metric: SongRowMetric) -> some View {
        let text: String
        switch metric {
        case .performances(let count):
            text = "\(count)回"
        case .collectRate(_, 0):
            // 一度も披露されていない曲の「0%」は率ではなく分母が無いだけ。
            // 率として出すと 0% で回収し損ねたように読める。
            text = "0回"
        case .collectRate(let collected, let total):
            let rate = Int((Double(collected) / Double(total) * 100).rounded())
            text = "\(rate)% / \(total)回"
        }
        return Label(text, systemImage: "music.mic")
            .labelStyle(.titleAndIcon)
            .font(.imasScaled(11, weight: .semibold))
            .foregroundStyle(DS.ink2)
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

    /// ブランド ID → イメージカラー hex。 リードバーとジャケフォールバックの seed に使う。
    static func brandColorHex(for brandId: String?) -> String? {
        BrandPalette.hex(for: brandId)
    }
}
