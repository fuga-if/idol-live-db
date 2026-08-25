import SwiftUI

/// クイズ・ゲームのハブ。プロデュース → 「クイズ・ゲーム」から push。
/// イントロドン／アイドル当て／ソロ曲／メンバーカラー合わせを束ねる。
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

    var body: some View {
        ScrollView {
            VStack(spacing: DS.sp5) {
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
            VStack(alignment: .leading, spacing: DS.sp1) {
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
    /// 正答率は保存値から引く計算なのでコア (game_progress) に委譲する
    /// (記録が無ければ nil が返るので「—」を出す)。
    private func bestLabel(_ kind: GameKind, _ rec: GameRecord) -> String {
        if kind.scoreIsPercent {
            guard let pct = progress.bestRatePercent(for: kind) else { return "—" }
            return "最高 \(pct)%"
        }
        guard rec.bestOutOf > 0 else { return "—" }
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
