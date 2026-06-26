import SwiftUI
import UIKit

// =============================================================================
// 機能 3: セトリコメントカード
// セトリの曲に感想を書いて「曲名 + コメント + 装飾」のカード画像を生成する。
// コメントはシェア用途のみのローカル入力で、サーバーには保存しない。
// =============================================================================

/// セトリコメントカード本体 (4:5 縦長 540×675pt)。
/// ジャケ写を全面背景に敷き、下部に曲名 (主役) + 感想の短い引用 + 小さな公演/日付を白基調で重ねる。
/// 余白を贅沢に取り、引用符 1 文字のみのミニマルな装飾でおしゃれに。
struct SetlistCommentShareCard: View {
    let songTitle: String
    var showName: String?
    var showDate: String?
    let comment: String
    var seed: String?
    /// ジャケット写真。ImageRenderer で確実に焼けるようロード済み UIImage のみ受け取る。
    /// nil なら深く落としたメンバーカラー単色フォールバックに切り替わる。
    var artwork: UIImage? = nil
    var size: ShareCard.Size = ShareCard.portrait

    private var palette: ShareCardPalette { ShareCardPalette(seed: seed) }

    var body: some View {
        let palette = self.palette
        PhotoShareScaffold(artwork: artwork, palette: palette, size: size) {
            VStack(alignment: .leading, spacing: 0) {
                ShareEyebrow(text: "セトリの感想", accent: palette.accent, ink: .white.opacity(0.82))

                // 感想を短い引用として (明朝・大きめ、編集的)。
                Text(comment)
                    .font(.imasScaled( 23, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .lineSpacing(7)
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 14)

                // 曲名 (主役) + 小さな公演/日付メタ。継ぎ目に細い罫線。
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 28, height: 2)
                    .padding(.top, 18)

                Text(songTitle)
                    .font(.imasScaled( 26, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 12)

                if let meta = showMetaLine {
                    Text(meta)
                        .font(.imasScaled( 12, weight: .medium).monospacedDigit())
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 5)
                }
            }
        }
    }

    /// 「公演名  ·  日付」の 1 行メタ。両方空なら nil。
    private var showMetaLine: String? {
        let parts = [showName, showDate].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

/// 感想入力 + ライブプレビュー + シェアの compose sheet。
/// セトリ曲行のコンテキストメニューから開く。
struct SetlistCommentComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let songTitle: String
    var showName: String?
    var showDate: String?
    /// 公演 ID。あればシェア文のリンクを公演セトリの deeplink にする。
    var showId: String?
    var seed: String?
    /// 曲の songs.artwork_url。シート表示時に async ロードしてカードに焼き込む。
    var artworkUrl: String?

    @State private var comment = ""
    @FocusState private var commentFocused: Bool
    @State private var artwork = ShareArtworkLoader()

    private var trimmedComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// プレビュー/カードに流す文言。未入力時はプレースホルダで完成形を見せる。
    private var displayComment: String {
        trimmedComment.isEmpty ? "ここに感想が入ります" : trimmedComment
    }

    private func card(size: ShareCard.Size) -> SetlistCommentShareCard {
        SetlistCommentShareCard(
            songTitle: songTitle,
            showName: showName,
            showDate: showDate,
            comment: displayComment,
            seed: seed,
            artwork: artwork.image,
            size: size
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp5) {
                    VStack(alignment: .leading, spacing: DS.sp3) {
                        Text("この曲の感想")
                            .font(.imasFootnote.weight(.semibold))
                            .foregroundStyle(DS.ink3)
                        TextField("最高だった！ 泣いた…など", text: $comment, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.imasBody)
                            .focused($commentFocused)
                            .padding(DS.sp4)
                            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                    }

                    ShareCardActionPane(
                        card: { size in card(size: size) },
                        isPreparingCard: artwork.isPreparing(urlString: artworkUrl)
                    )
                }
                .padding(DS.sp5)
            }
            .background(DS.bg)
            .task { await artwork.load(from: artworkUrl) }
            .navigationTitle("感想カードを作る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear { commentFocused = true }
            .trackScreen("setlist_comment_share")
        }
    }
}
