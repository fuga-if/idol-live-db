import SwiftUI
import UIKit

// =============================================================================
// 機能 2: タグ付与シェアカード
// タグ付与完了時に「『曲名』にタグを付けました！」のカード + シェア文を生成する。
// =============================================================================

/// タグ付与シェアの内容。SongTagPicker の適用完了時に組み立てる。
struct TagShareContext {
    let songTitle: String
    let artistNames: String?
    /// 今回付けたタグ (カードに乗せるのは先頭 8 個まで)
    let tags: [CommunityTag]
    /// メンバーカラー seed (曲のブランドカラー → 先頭タグ色 の順でフォールバック)
    let seed: String?
    /// 曲の songs.artwork_url。完了ビュー表示時に async ロードしてカードに焼き込む。
    var artworkUrl: String? = nil
}

/// タグ付与カード本体 (4:5 縦長 540×675pt)。
/// 上にジャケ写フルブリード / 下を near-black のソリッドパネルにした編集レイアウト。
/// パネルに英字キャプスラベル + 曲名 (明朝・主役) + 線画タグチップを白基調で置く。
struct TagShareCard: View {
    let context: TagShareContext
    /// ジャケット写真。ImageRenderer で確実に焼けるようロード済み UIImage のみ受け取る。
    /// nil なら深く落としたメンバーカラー単色フォールバックに切り替わる。
    var artwork: UIImage? = nil
    var size: ShareCard.Size = ShareCard.portrait

    private var palette: ShareCardPalette { ShareCardPalette(seed: context.seed) }

    var body: some View {
        let palette = self.palette
        PhotoShareScaffold(artwork: artwork, palette: palette, size: size) {
            VStack(alignment: .leading, spacing: 0) {
                ShareEyebrow(text: "タグを追加しました！", accent: palette.accent, ink: .white.opacity(0.82))

                // 曲名を主役に (明朝で上品・編集的)。
                Text(context.songTitle)
                    .font(.imasScaled( 40, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.55)
                    .padding(.top, 12)

                if let artists = context.artistNames, !artists.isEmpty {
                    Text(artists)
                        .font(.imasScaled( 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                        .padding(.top, 8)
                }

                // 付けたタグを線画チップで最小限に (最大 6 個)。
                FlowLayout(spacing: 8) {
                    ForEach(context.tags.prefix(6)) { tag in
                        tagChip(tag)
                    }
                }
                .padding(.top, 22)
            }
        }
    }

    /// タグチップ: 塗らず細い罫線 + 小ドット (線画基調)。色はタグ固有色 → accent。
    private func tagChip(_ tag: CommunityTag) -> some View {
        // Color(hexString:default:) が HexColor バリデーションを内蔵し、不正/nil は
        // default に落ちるので、事前の hex 検証は不要。
        let dot = Color(hexString: tag.color?.rawValue, default: palette.accent)
        return HStack(spacing: 7) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
            Text(tag.name)
                .font(.imasScaled( 14, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
    }
}

/// タグ付与完了後にピッカー内へ差し込む完了 + シェアペイン。
struct TagShareCompletionView: View {
    let context: TagShareContext
    let onClose: () -> Void

    @State private var artwork = ShareArtworkLoader()

    var body: some View {
        ScrollView {
            VStack(spacing: DS.sp5) {
                VStack(spacing: DS.sp2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.imasScaled( 40))
                        .foregroundStyle(DS.success)
                    Text("タグを付けました！")
                        .font(.imasHeadline)
                        .foregroundStyle(DS.ink)
                    Text("せっかくなのでカードでシェアしませんか？")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                }
                .padding(.top, DS.sp4)

                ShareCardActionPane(
                    card: { size in
                        TagShareCard(context: context, artwork: artwork.image, size: size)
                    },
                    isPreparingCard: artwork.isPreparing(urlString: context.artworkUrl)
                )

                Button("閉じる", action: onClose)
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
                    .padding(.bottom, DS.sp4)
            }
            .padding(DS.sp5)
        }
        .background(DS.bg)
        .task { await artwork.load(from: context.artworkUrl) }
    }
}
