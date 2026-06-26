import os
import SwiftUI

/// 起動時モーダル「今日の1曲」。各ブランドから1曲を日替わり(決定論)でピックし、
/// 気になる1曲を選んでタグ投票してもらう。タグは複数付与でき、同じタグは voteCount で集計される。
struct DailySongVoteSheet: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var picks: [(song: Song, brand: Brand?)] = []
    @State private var tagTarget: Song?
    @State private var taggedIds: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp4) {
                    Text("各ブランドから今日の1曲をピックしました。ジャケットをタップで試聴、気になる曲にタグを付けて投票しよう（複数OK・同じタグは人数が貯まります）。")
                        .font(.imasFootnote).foregroundStyle(DS.ink2)
                        .padding(.bottom, DS.sp1)

                    if isLoading {
                        ProgressView().tint(DS.sys).frame(maxWidth: .infinity).padding(.top, DS.sp8)
                    } else {
                        ForEach(picks, id: \.song.id) { pair in
                            songCard(pair.song, brand: pair.brand)
                        }
                    }
                }
                .padding(DS.sp5)
            }
            .background(DS.bg.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("今日の1曲")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .font(.imasSubhead.weight(.semibold))
                        .tint(DS.sys)
                }
            }
            .sheet(item: $tagTarget) { song in
                SongTagPicker(songId: song.id, song: SongWithArtists(song: song, artistNames: song.singerLabel ?? "")) { taggedIds.insert(song.id) }
                    .environment(database)
            }
            .task { await load() }
            .trackScreen("daily_song_vote")
        }
    }

    private func songCard(_ song: Song, brand: Brand?) -> some View {
        let seed = brand?.color
        let tagged = taggedIds.contains(song.id)
        // ジャケはタップで試聴 (ArtworkImageView が previewURL を内部で再生制御)。
        // ジャケ以外をタップするとタグ投票ピッカーを開く。
        return HStack(spacing: DS.sp4) {
            ImasLeadBar(seed: seed).frame(height: 52)
            ArtworkImageView(
                url: URL(string: song.artworkUrl ?? ""),
                size: 52,
                previewURL: song.previewUrl.flatMap { URL(string: $0) },
                songTitle: song.title,
                seed: seed
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                AppAnalytics.tap("daily_song_vote.vote")
                tagTarget = song
            } label: {
                HStack(spacing: DS.sp2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(brand?.shortName ?? "").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
                        Text(song.title).font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink).lineLimit(2)
                        if let label = song.singerLabel, !label.isEmpty {
                            Text(label).font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
                        }
                    }
                    Spacer(minLength: DS.sp2)
                    HStack(spacing: 4) {
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
        let key = Self.dayKey()
        let brands = ((try? await AppContainer.shared.brandReading.brands()) ?? [])
            .filter { $0.id != "other" }
            .sorted { $0.sortOrder < $1.sortOrder }
        var chosen: [(brand: Brand, id: String)] = []
        for brand in brands {
            // リミックス変種を除外 (同名曲の紛らわしい連日重複を防ぐ)。
            let ids = (try? await AppContainer.shared.songReading.songIds(brandId: brand.id, includeCovers: false, excludeRemixes: true)) ?? []
            guard !ids.isEmpty else { continue }
            let idx = Self.stableIndex(key + "|" + brand.id, mod: ids.count)
            chosen.append((brand, ids[idx]))
        }
        let songs = (try? await AppContainer.shared.songReading.songs(ids: chosen.map(\.id))) ?? []
        let byId = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        picks = chosen.compactMap { c in byId[c.id].map { ($0, Optional(c.brand)) } }
    }

    /// 端末ローカルの YYYY-MM-DD。日替わりピックの種。
    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 文字列 → [0, mod) の安定インデックス (FNV-1a)。プロセス間で同一。
    static func stableIndex(_ s: String, mod: Int) -> Int {
        guard mod > 0 else { return 0 }
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(h % UInt64(mod))
    }
}
