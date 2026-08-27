import os
import SwiftUI

/// 起動時モーダル「今日の1曲」/「今日のアイドル」。
///
/// 各ブランドから 1 件を日替わり (決定論) でピックし、タグを付けてもらう。
/// タグは複数付与でき、同じタグは voteCount で集計される。
///
/// ## なぜ 1 日おきに入れ替えるのか
///
/// 曲もアイドルもタグはユーザーが育てるデータで、こちらから初期値を入れない
/// (熱心な人が手で付けること自体が盛り上がりになる)。だから「付けてもらう入口」の
/// 数がそのままデータの育ち方になる。曲とアイドルを同じシートに縦に並べると
/// 起動直後のモーダルがブランド数 × 2 枚になって読まれなくなるので、
/// **日で交互**にして 1 回あたりの分量は変えずに入口を 2 系統に増やしている。
/// どちらの日かはコア (`DailyPick.sheetKind`) が日付から決める。
struct DailyPickSheet: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    /// 出す種別。既定は今日の日付から決まる (テスト・プレビューで固定できるよう外から差せる)。
    var kind: DailyPickKind = DailyPickSheet.defaultKind()

    /// 既定の種別。通常は今日の日付から決まる。
    ///
    /// DEBUG では `DAILY_PICK_KIND=song|idol` で固定できる。日替わりなので、
    /// 見た目の確認や App Store 用のスクリーンショットを撮る日に出したい方が出るとは
    /// 限らない (`SCREENSHOT_MODE` / `CALL_GUIDE_PREVIEW` と同じ流儀)。
    static func defaultKind() -> DailyPickKind {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["DAILY_PICK_KIND"] {
        case "song": return .song
        case "idol": return .idol
        default: break
        }
        #endif
        return DailyPick.sheetKind()
    }

    @State private var songPicks: [(song: Song, brand: Brand?)] = []
    @State private var idolPicks: [(idol: Idol, brand: Brand?)] = []
    /// idol_id → CV 名。曲カードの歌唱者ラベルに当たる情報をアイドルカードにも出す。
    @State private var castNames: [String: String] = [:]
    @State private var tagTarget: TagTarget?
    @State private var taggedIds: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp4) {
                    Text(lead)
                        .font(.imasFootnote).foregroundStyle(DS.ink2)
                        .padding(.bottom, DS.sp1)

                    if isLoading {
                        ImasInlineLoading(tint: DS.sys)
                    } else {
                        switch kind {
                        case .song:
                            ForEach(songPicks, id: \.song.id) { pair in
                                songCard(pair.song, brand: pair.brand)
                            }
                        case .idol:
                            ForEach(idolPicks, id: \.idol.id) { pair in
                                idolCard(pair.idol, brand: pair.brand)
                            }
                        }
                    }
                }
                .padding(DS.sp5)
            }
            .background(DS.bg.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle(DailyPickSheet.title(for: kind))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .font(.imasSubhead.weight(.semibold))
                        .tint(DS.sys)
                }
            }
            // 曲とアイドルで sheet 修飾子を 2 つ重ねない。同じ View に .sheet を並べると
            // 後ろの 1 つしか効かないことがある (CalendarView でも踏んでいる落とし穴)。
            // その日出るのはどちらか一方なので、1 つの item にまとめて分岐する。
            .sheet(item: $tagTarget) { target in
                switch target {
                case .song(let song):
                    SongTagPicker(songId: song.id, song: SongWithArtists(song: song, artistNames: song.singerLabel ?? "")) { taggedIds.insert(song.id) }
                        .environment(database)
                case .idol(let idol):
                    IdolTagPicker(idol: idol) { taggedIds.insert(idol.id) }
                        .environment(database)
                }
            }
            .task { await load() }
            .trackScreen(kind == .song ? "daily_song_vote" : "daily_idol_vote")
        }
    }

    /// 画面名。カレンダーの導線 (ツールバー) もこれを読んでラベルを揃える。
    static func title(for kind: DailyPickKind) -> String {
        kind == .song ? "今日の1曲" : "今日のアイドル"
    }

    /// ツールバーの SF Symbol。タップ前にその日どちらが出るか分かるようにする。
    static func symbol(for kind: DailyPickKind) -> String {
        kind == .song ? "music.note.house.fill" : "person.crop.circle.badge.checkmark"
    }

    private var lead: String {
        switch kind {
        case .song:
            return "各ブランドから今日の1曲をピックしました。ジャケットをタップで試聴、気になる曲にタグを付けて投票しよう（複数OK・同じタグは人数が貯まります）。"
        case .idol:
            return "各ブランドから今日のアイドルをピックしました。性格でも髪型でも口ぐせでも、思いついたタグを付けて投票しよう（複数OK・同じタグは人数が貯まります）。"
        }
    }

    // MARK: - Cards

    private func songCard(_ song: Song, brand: Brand?) -> some View {
        let seed = brand?.color
        // ジャケはタップで試聴 (ArtworkImageView が previewURL を内部で再生制御)。
        // ジャケ以外をタップするとタグ投票ピッカーを開く。
        return pickCard(seed: seed, tagged: taggedIds.contains(song.id)) {
            ArtworkImageView(
                url: URL(string: song.artworkUrl ?? ""),
                size: 52,
                previewURL: song.previewUrl.flatMap { URL(string: $0) },
                songTitle: song.title,
                seed: seed
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
        } labels: {
            Text(brand?.shortName ?? "").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
            Text(song.title).font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink).lineLimit(2)
            if let label = song.singerLabel, !label.isEmpty {
                Text(label).font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
            }
        } onVote: {
            AppAnalytics.tap("daily_song_vote.vote")
            tagTarget = .song(song)
        }
    }

    private func idolCard(_ idol: Idol, brand: Brand?) -> some View {
        // 先頭の色帯はブランド色 (曲側と揃える)。アバターは本人の推しカラーで出る。
        let seed = brand?.color
        return pickCard(seed: seed, tagged: taggedIds.contains(idol.id)) {
            // 曲のジャケと違い試聴は無いので、アバター自体もタグ導線の一部として扱う
            // (カード全体がタップ領域になるよう Button の外に出さない)。
            IdolAvatarView(idol: idol, size: 52, reservesPickRing: false)
        } labels: {
            Text(brand?.shortName ?? "").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
            Text(idol.name).font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink).lineLimit(2)
            if let cv = castNames[idol.id], !cv.isEmpty {
                Text("CV: \(cv)").font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
            }
        } onVote: {
            AppAnalytics.tap("daily_idol_vote.vote")
            tagTarget = .idol(idol)
        }
    }

    /// 曲/アイドルで共通のカード外形。左の色帯・サムネ・見出し列・タグボタンの並びは同じで、
    /// 中身 (サムネと見出しの作り) だけが差し替わる。
    private func pickCard<Thumbnail: View, Labels: View>(
        seed: String?,
        tagged: Bool,
        @ViewBuilder thumbnail: () -> Thumbnail,
        @ViewBuilder labels: () -> Labels,
        onVote: @escaping () -> Void
    ) -> some View {
        HStack(spacing: DS.sp4) {
            ImasLeadBar(seed: seed).frame(height: 52)
            thumbnail()

            Button(action: onVote) {
                HStack(spacing: DS.sp2) {
                    VStack(alignment: .leading, spacing: DS.sp1) { labels() }
                    Spacer(minLength: DS.sp2)
                    HStack(spacing: DS.sp2) {
                        Image(systemName: tagged ? "checkmark.circle.fill" : "tag")
                        Text(tagged ? "投票済" : "タグ").font(.imasFootnote.weight(.semibold))
                    }
                    .foregroundStyle(tagged ? DS.success : ImasTheme.derive(seed: seed, scheme: .light).accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let key = DailyPick.dayKey()
        let brands = ((try? await AppContainer.shared.brandReading.brands()) ?? [])
            .filter { $0.id != "other" }
            .sorted { $0.sortOrder < $1.sortOrder }
        switch kind {
        case .song: await loadSongs(dayKey: key, brands: brands)
        case .idol: await loadIdols(dayKey: key, brands: brands)
        }
    }

    private func loadSongs(dayKey: String, brands: [Brand]) async {
        var candidates: [(brand: Brand, ids: [String])] = []
        for brand in brands {
            // リミックス変種を除外 (同名曲の紛らわしい連日重複を防ぐ)。
            let ids = (try? await AppContainer.shared.songReading.songIds(brandId: brand.id, includeCovers: false, excludeRemixes: true)) ?? []
            guard !ids.isEmpty else { continue }
            candidates.append((brand, ids))
        }
        // 全ブランド分を 1 回の FFI 呼び出しで解決する (ブランドごとに songIndex を呼ばない)。
        let indices = DailyPick.songIndices(
            dayKey: dayKey,
            brands: candidates.map { (brandId: $0.brand.id, count: $0.ids.count) })
        let chosen: [(brand: Brand, id: String)] = zip(candidates, indices).map { c, idx in
            (brand: c.brand, id: c.ids[idx])
        }
        let songs = (try? await AppContainer.shared.songReading.songs(ids: chosen.map(\.id))) ?? []
        let byId = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        songPicks = chosen.compactMap { c in byId[c.id].map { ($0, Optional(c.brand)) } }
    }

    /// タグピッカーの提示先。曲とアイドルを 1 つの `sheet(item:)` で扱うための包み。
    private enum TagTarget: Identifiable {
        case song(Song)
        case idol(Idol)

        // 曲とアイドルで id が衝突しないよう種別で名前空間を分ける。
        var id: String {
            switch self {
            case .song(let s): return "song-\(s.id)"
            case .idol(let i): return "idol-\(i.id)"
            }
        }
    }

    private func loadIdols(dayKey: String, brands: [Brand]) async {
        castNames = (try? await AppContainer.shared.idolReading.idolCastNames()) ?? [:]
        var candidates: [(brand: Brand, idols: [Idol])] = []
        for brand in brands {
            let idols = (try? await AppContainer.shared.idolReading.idols(brandId: brand.id)) ?? []
            guard !idols.isEmpty else { continue }
            candidates.append((brand, idols))
        }
        // 曲側と同じく全ブランド分を 1 回の FFI 呼び出しで解決する。
        let indices = DailyPick.idolIndices(
            dayKey: dayKey,
            brands: candidates.map { (brandId: $0.brand.id, count: $0.idols.count) })
        idolPicks = zip(candidates, indices).map { c, idx in (idol: c.idols[idx], brand: Optional(c.brand)) }
    }
}
