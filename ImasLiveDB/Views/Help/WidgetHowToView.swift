import SwiftUI

/// 担当画像ウィジェットの使い方を、各ステップのイラスト付きで案内する画面。
/// ヘルプ → 「担当ウィジェットの使い方」から開く。
struct WidgetHowToView: View {
    private let pink = Color(red: 1.0, green: 0.30, blue: 0.55)
    private let purple = Color(red: 0.55, green: 0.35, blue: 0.95)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                StepCard(number: 1, tint: pink,
                         title: "アプリで担当に画像を追加",
                         detail: "アイドル詳細 → プロフィール下の「ギャラリー」→「追加」から、好きな画像を何枚でも入れられます。先頭の1枚がアイコンになります。") {
                    addImageArt
                }

                StepCard(number: 2, tint: purple,
                         title: "ホーム画面にウィジェットを追加",
                         detail: "ホーム画面の何もない所を長押し → 左上の「＋」をタップ。") {
                    homeAddArt
                }

                StepCard(number: 3, tint: pink,
                         title: "「担当」で検索して選ぶ",
                         detail: "ウィジェット一覧で「担当」と検索。「担当の画像（タップで切替）」と「（タップでアプリ）」の2種類があります。好きな方を追加。") {
                    searchArt
                }

                StepCard(number: 4, tint: purple,
                         title: "どのアイドルを出すか選ぶ",
                         detail: "置いたウィジェットを長押し →「ウィジェットを編集」→ アイドルを選択。画像を入れた担当が候補に出ます。") {
                    editArt
                }

                StepCard(number: 5, tint: pink,
                         title: "タップで次の画像へ",
                         detail: "「タップで切替」版はタップするたびに次の画像にローテーション。放っておいても30分ごとに自動で切り替わります。「タップでアプリ」版はタップでアプリが開きます。") {
                    tapArt
                }

                tips
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .navigationTitle("担当ウィジェットの使い方")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("widget_how_to")
    }

    // MARK: - Header / Tips

    private var header: some View {
        VStack(spacing: 10) {
            phoneFrame {
                imageFill
            }
            .frame(width: 120, height: 120)
            Text("推しの画像をホーム画面に")
                .font(.imasTitle3)
            Text("自分でアプリに入れた画像だけを表示します。版権画像は使いません。")
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("画像を足した・消した時は、アプリを一度開くとウィジェットも更新されます。", systemImage: "arrow.triangle.2.circlepath")
            Label("ロック画面ウィジェットは仕様上フルカラー写真を出せません（ホーム画面向けの機能です）。", systemImage: "lock.iphone")
        }
        .font(.imasCaption)
        .foregroundStyle(DS.ink2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD))
    }

    // MARK: - Illustrations

    /// 端末/ウィジェットらしい角丸フレーム。
    private func phoneFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 2))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }

    private var imageFill: some View {
        ZStack {
            LinearGradient(colors: [pink.opacity(0.85), purple.opacity(0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "person.fill")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
                .offset(y: 6)
        }
    }

    private var addImageArt: some View {
        ZStack(alignment: .bottomTrailing) {
            phoneFrame { imageFill }
                .frame(width: 92, height: 92)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .offset(x: 6, y: 6)
        }
    }

    private var homeAddArt: some View {
        ZStack(alignment: .topLeading) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 3), spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DS.fill)
                        .frame(width: 34, height: 34)
                }
            }
            .frame(width: 122)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 26))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, purple)
                .offset(x: -10, y: -10)
        }
        .padding(.top, 6)
    }

    private var searchArt: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(DS.ink2)
                Text("担当").font(.imasSubhead).foregroundStyle(DS.ink)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(DS.fill, in: Capsule())
            .frame(width: 150)
            phoneFrame { imageFill }.frame(width: 64, height: 64)
        }
    }

    private var editArt: some View {
        HStack(spacing: 12) {
            phoneFrame { imageFill }.frame(width: 70, height: 70)
            Image(systemName: "arrow.right").foregroundStyle(DS.ink3)
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text("編集").font(.imasCaption.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(DS.fill, in: Capsule())
        }
    }

    private var tapArt: some View {
        ZStack(alignment: .bottomTrailing) {
            phoneFrame { imageFill }.frame(width: 92, height: 92)
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .padding(7)
                .background(.black.opacity(0.4), in: Circle())
                .offset(x: 8, y: 8)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(pink)
                .offset(x: 10, y: -4)
        }
    }
}

/// 番号バッジ + イラスト + 説明 の 1 ステップカード。
private struct StepCard<Art: View>: View {
    let number: Int
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder let art: () -> Art

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.imasDisplay(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint.gradient, in: Circle())
                Text(title)
                    .font(.imasHeadline)
                    .foregroundStyle(DS.ink)
                Spacer(minLength: 0)
            }

            art()
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .background(DS.bg, in: RoundedRectangle(cornerRadius: DS.rMD))

            Text(detail)
                .font(.imasSubhead)
                .foregroundStyle(DS.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG))
    }
}

#Preview {
    NavigationStack { WidgetHowToView() }
}
