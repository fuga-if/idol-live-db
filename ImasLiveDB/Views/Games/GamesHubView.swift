import SwiftUI

/// クイズ・ゲームのハブ。プロデュース → 「クイズ・ゲーム」から push。
/// イントロドン／アイドル当て／ソロ曲／メンバーカラー合わせを束ね、
/// 連続記録 (ストリーク) と「今日のチャレンジ」で毎日開く動機を作る。
struct GamesHubView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
    @State private var progress = GameProgressStore.shared

    /// ハブに並べるゲーム定義 (表示順)。
    private struct GameEntry {
        let kind: GameKind
        let systemImage: String
        let title: String
        let blurb: String
    }

    private let entries: [GameEntry] = [
        .init(kind: .introDon, systemImage: "music.note.list", title: "イントロドン",
              blurb: "イントロを聴いて曲名を当てる"),
        .init(kind: .idolQuiz, systemImage: "person.fill.questionmark", title: "アイドル当てクイズ",
              blurb: "プロフィールから4択で誰かを当てる"),
        .init(kind: .songSingerQuiz, systemImage: "music.microphone", title: "ソロ曲クイズ",
              blurb: "ソロ曲を歌うアイドルを4択で当てる"),
        .init(kind: .colorMatch, systemImage: "paintpalette.fill", title: "メンバーカラー合わせ",
              blurb: "似た色のメンバーを正しいカラーに紐づける"),
    ]

    /// その日に推す 1 ゲーム (端末ローカルで日替わり・決定論)。
    private var featured: GameEntry {
        let idx = DailySongVoteSheet.stableIndex("featured|" + GameProgressStore.today(), mod: entries.count)
        return entries[idx]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.sp5) {
                streakCard
                dailyChallengeCard
                gameGrid
            }
            .padding(DS.sp5)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("クイズ・ゲーム")
        .navigationBarTitleDisplayMode(.large)
        .trackScreen("games_hub")
    }

    // MARK: - 連続記録

    private var streakCard: some View {
        let s = progress.displayStreak
        let cleared = progress.didClearToday
        return HStack(spacing: DS.sp4) {
            ZStack {
                Circle().fill(DS.favorite.opacity(0.16)).frame(width: 52, height: 52)
                Image(systemName: "flame.fill")
                    .font(.imasScaled( 24, weight: .semibold))
                    .foregroundStyle(s > 0 ? DS.favorite : DS.ink3)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(s)").font(.imasDisplay(28, weight: .bold)).foregroundStyle(DS.ink)
                    Text("日連続").font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink2)
                }
                Text(cleared ? "今日のプレイ達成！明日も続けよう"
                             : (s > 0 ? "今日プレイで記録を伸ばそう" : "今日からスタート"))
                    .font(.imasCaption).foregroundStyle(DS.ink3)
            }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text("\(progress.totalDays)").font(.imasDisplay(17, weight: .bold)).foregroundStyle(DS.ink)
                Text("通算日").font(.imasCaption).foregroundStyle(DS.ink3)
            }
        }
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    // MARK: - 今日のチャレンジ

    private var dailyChallengeCard: some View {
        let f = featured
        let cleared = progress.didClearToday
        return NavigationLink {
            destination(for: f.kind)
        } label: {
            VStack(alignment: .leading, spacing: DS.sp3) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.imasScaled( 12, weight: .bold))
                    Text("今日のチャレンジ").font(.imasCaption.weight(.bold))
                    Spacer(minLength: 0)
                    if cleared {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("達成").font(.imasCaption.weight(.bold))
                        }
                    }
                }
                .foregroundStyle(cleared ? DS.success : DS.onSys)

                HStack(spacing: DS.sp4) {
                    Image(systemName: f.systemImage)
                        .font(.imasScaled( 26, weight: .semibold))
                        .foregroundStyle(DS.onSys)
                        .frame(width: 50, height: 50)
                        .background(DS.onSys.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title).font(.imasHeadline.weight(.bold)).foregroundStyle(DS.onSys)
                        Text(f.blurb).font(.imasFootnote).foregroundStyle(DS.onSys.opacity(0.8)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.imasScaled( 15, weight: .semibold)).foregroundStyle(DS.onSys.opacity(0.7))
                }
            }
            .padding(DS.sp5)
            .background(DS.sys, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - ゲーム一覧 (2 列グリッド)

    private var gameGrid: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "ゲーム", count: "\(entries.count)")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.sp3), count: 2), spacing: DS.sp3) {
                ForEach(entries, id: \.kind) { entry in
                    NavigationLink {
                        destination(for: entry.kind)
                    } label: {
                        gameCard(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func gameCard(_ entry: GameEntry) -> some View {
        let rec = progress.record(for: entry.kind)
        return VStack(alignment: .leading, spacing: DS.sp3) {
            Image(systemName: entry.systemImage)
                .font(.imasScaled( 22, weight: .semibold))
                .foregroundStyle(DS.sys)
                .frame(width: 44, height: 44)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(entry.blurb).font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(2)
            }
            Spacer(minLength: 0)
            scoreLine(entry.kind, rec)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    @ViewBuilder
    private func scoreLine(_ kind: GameKind, _ rec: GameRecord) -> some View {
        if rec.hasPlayed {
            HStack(spacing: 5) {
                Image(systemName: "star.fill").font(.imasScaled( 10)).foregroundStyle(DS.favorite)
                Text(bestLabel(kind, rec)).font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink2)
                Spacer(minLength: 0)
                Text("\(rec.playCount)回").font(.imasCaption).foregroundStyle(DS.ink3)
            }
        } else {
            Text("未プレイ").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
        }
    }

    /// 最高記録の表示文字列。色合わせは正答率%、クイズ系は獲得ポイント。
    private func bestLabel(_ kind: GameKind, _ rec: GameRecord) -> String {
        guard rec.bestOutOf > 0 else { return "—" }
        if kind.scoreIsPercent {
            let pct = Int((Double(rec.bestScore) / Double(rec.bestOutOf) * 100).rounded())
            return "最高 \(pct)%"
        }
        return "最高 \(rec.bestScore)pt"
    }

    // MARK: - 遷移先

    @ViewBuilder
    private func destination(for kind: GameKind) -> some View {
        switch kind {
        case .introDon: IntroDonHomeView()
        // アイドル当て・ソロ曲はブランド絞り込み設定画面を先に挟む。
        case .idolQuiz: IdolQuizSetupView()
        case .songSingerQuiz: SongSingerQuizSetupView()
        case .colorMatch: ColorMatchGameView()
        }
    }
}
