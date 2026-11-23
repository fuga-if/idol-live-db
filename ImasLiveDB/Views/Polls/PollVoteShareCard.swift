import SwiftUI
import UIKit

/// 自分の投票 (「私の投票」) をシェアするシート。画像の中身 (見出し・いまの順位・誘いの帯) はコアの `pollVoteCard`。
/// 結果の画像 (`PollResultShareSheet`) と同じ骨格・同じ暗い紙面にそろえる。
struct PollVoteShareSheet: View {
    let poll: Poll
    let entries: [PollEntry]
    /// 添える本文 (「お題「…」で「A」に投票しました！ #アイドルライブDB」+ URL)。
    let shareText: String

    @State private var card: PollVoteCard?
    @State private var items: [String: PollResultShareItem] = [:]

    var body: some View {
        ShareCardSheet(title: "投票をシェア", screenName: "poll_vote_share") {
            ShareCardActionPane(card: { size in
                if let card {
                    PollVoteShareCard(card: card, items: items, size: size)
                } else {
                    ShareInk.nearBlack.frame(width: size.width, height: size.height)
                }
            }, isPreparingCard: card == nil, shareText: shareText)
        }
        .task { await load() }
    }

    private func load() async {
        let input = PollVoteCardInput(
            title: poll.title,
            target: poll.targetType.cardTarget,
            isActive: poll.isActive,
            endsAtEpochMs: Int64((poll.endsAt.timeIntervalSince1970 * 1000).rounded()),
            tzOffsetSeconds: Int32(TimeZone.current.secondsFromGMT(for: poll.endsAt)),
            myEntityIds: entries.filter(\.hasUserVoted).map(\.entityId),
            entries: entries.map { PollCardEntryInput(entityId: $0.entityId, voteCount: UInt32(clamping: $0.voteCount)) }
        )
        let built = pollVoteCard(input: input)
        let ids = built.picks.map(\.entityId)
        items = await PollShareItems.resolve(ids: ids, imageIds: Set(ids), target: poll.targetType)
        card = built
    }
}

/// 画像: 私の投票。骨格は `PosterShareScaffold` (結果の画像と同じ)。
/// 自分の票 (最大 3) を同じ大きさで横に並べ、絵の角に投票の印 (✓)、名前の下にいまの順位と票数。
/// 開催中は下に差し色の帯で「あなたも投票しよう」を刷る (平らな塗り、角は立てる)。
///
/// ImageRenderer で焼く固定キャンバスなので、色は固定色だけ、文字は固定 pt。
struct PollVoteShareCard: View {
    let card: PollVoteCard
    let items: [String: PollResultShareItem]
    var size: ShareCard.Size = ShareCard.portrait

    private var palette: ShareCardPalette {
        ShareCardPalette(seed: card.picks.first.flatMap { items[$0.entityId]?.seed })
    }

    /// 1 つなら大きく、3 つでも横幅 (468pt) に収まる大きさ。
    private var side: CGFloat {
        switch card.picks.count {
        case 0, 1: return 212
        case 2: return 188
        default: return 140
        }
    }

    /// 名前の欄は絵より 8pt 広い。3 つでも (140+8)×3 + 間 2 つ が横幅 468pt に収まる間隔。
    private var slotSpacing: CGFloat { card.picks.count >= 3 ? 10 : 16 }

    private var nameHeight: CGFloat? {
        switch card.picks.count {
        case 0, 1: return nil
        case 2: return 42
        default: return 38
        }
    }

    var body: some View {
        PosterShareScaffold(
            palette: palette,
            width: size.width, height: size.height,
            kicker: card.kicker,
            trailingKicker: card.imprint,
            title: card.title,
            titleSize: 38,
            subtitle: card.subtitle
        ) {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel.padding(.top, 22)
                // 絵の並びは見出しと帯 (締切後は足下) の間の真ん中に置き、帯は足下の上に据える。
                Spacer(minLength: 18)
                HStack(alignment: .top, spacing: slotSpacing) {
                    ForEach(card.picks, id: \.entityId) { pick in
                        pickSlot(pick)
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 22)
                if let cta = card.callToAction {
                    callToAction(cta)
                }
            }
            // 残りの高さを全部こちらで受ける (骨格の足下の前の余白は最小にする)。
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
        }
    }

    /// 「わたしの投票」+ 右へ伸びる罫 (チケットの欄の見出しの書き方)。
    private var sectionLabel: some View {
        HStack(spacing: 10) {
            Text(card.sectionLabel)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.7))
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
        }
    }

    private func pickSlot(_ pick: PollVotePick) -> some View {
        VStack(spacing: 10) {
            PollShareVisual(item: items[pick.entityId], side: side)
                .overlay(alignment: .topLeading) { voteMark(onStamp: isStamp(pick)) }
            Text(items[pick.entityId]?.name ?? "")
                .font(.system(size: card.picks.count >= 3 ? 14 : 16, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                // 並べたときは順位の行の高さをそろえるため 2 行分の高さを取る。1 つだけなら詰める。
                .frame(width: side + 8, height: nameHeight, alignment: .top)
            if !pick.rankLabel.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pick.rankLabel)
                        .font(.system(size: 20, weight: .black).width(.compressed).monospacedDigit())
                        .foregroundStyle(pick.rank == 1 ? palette.accent : .white.opacity(0.85))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(pick.voteCount)")
                            .font(.system(size: 18, weight: .heavy).width(.compressed).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                        Text("票")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    /// 絵の左上に重ねる投票の印。差し色の正方形に ✓ (投票用紙のチェック欄)。
    /// 画像の無いアイドルの判子 (丸) か。丸のときは印を角の外でなく丸の縁に重ねる。
    private func isStamp(_ pick: PollVotePick) -> Bool {
        let item = items[pick.entityId]
        return item?.image == nil && item?.monogram != nil
    }

    private func voteMark(onStamp: Bool) -> some View {
        Rectangle()
            .fill(palette.accent)
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(ShareInk.nearBlack)
            )
            .overlay(Rectangle().stroke(ShareInk.nearBlack, lineWidth: 2))
            .offset(x: onStamp ? side * 0.07 : -6, y: onStamp ? side * 0.07 : -6)
    }

    /// 開催中だけの誘いの帯。差し色の平らな塗りに黒の文字。
    private func callToAction(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 15, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .black))
        }
        .foregroundStyle(ShareInk.nearBlack)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(palette.accent)
    }
}
