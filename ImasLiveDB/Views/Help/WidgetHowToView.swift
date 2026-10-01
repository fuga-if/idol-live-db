import SwiftUI

/// 担当画像ウィジェットの使い方を、各ステップのイラスト付きで案内する画面。
/// ヘルプ → 「担当ウィジェットの使い方」から開く。
struct WidgetHowToView: View {
    @Environment(\.colorScheme) private var scheme

    private var pink: ImasTheme { ImasTheme.derive(seed: "#FF4D8C", scheme: scheme) }
    private var purple: ImasTheme { ImasTheme.derive(seed: "#8C59F2", scheme: scheme) }

    var body: some View {
        ImasPage {
            header

            ImasCard {
                ImasStepList(steps: [
                    .init(title: "アプリで担当に画像を追加",
                          detail: "アイドル詳細 → プロフィール下の「ギャラリー」→「追加」から、好きな画像を何枚でも入れられます。先頭の1枚がアイコンになります。") {
                        addImageArt
                    },
                ], startIndex: 1)
            }

            ImasCard {
                ImasStepList(steps: [
                    .init(title: "ホーム画面にウィジェットを追加",
                          detail: "ホーム画面の何もない所を長押し → 左上の「＋」をタップ。") {
                        homeAddArt
                    },
                ], startIndex: 2)
            }

            ImasCard {
                ImasStepList(steps: [
                    .init(title: "「担当」で検索して選ぶ",
                          detail: "ウィジェット一覧で「担当」と検索。「担当の画像（タップで切替）」と「（タップでアプリ）」の2種類があります。好きな方を追加。") {
                        searchArt
                    },
                ], startIndex: 3)
            }

            ImasCard {
                ImasStepList(steps: [
                    .init(title: "どのアイドルを出すか選ぶ",
                          detail: "置いたウィジェットを長押し →「ウィジェットを編集」→ アイドルを選択。画像を入れた担当が候補に出ます。") {
                        editArt
                    },
                ], startIndex: 4)
            }

            ImasCard {
                ImasStepList(steps: [
                    .init(title: "タップで次の画像へ",
                          detail: "「タップで切替」版はタップするたびに次の画像にローテーション。放っておいても30分ごとに自動で切り替わります。「タップでアプリ」版はタップでアプリが開きます。") {
                        tapArt
                    },
                ], startIndex: 5)
            }

            tips
        }
        .navigationTitle("担当ウィジェットの使い方")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("widget_how_to")
    }

    // MARK: - Header / Tips

    private var header: some View {
        VStack(spacing: DS.Space.gap) {
            phoneFrame { imageFill }
                .frame(width: 120, height: 120)
            Text("推しの画像をホーム画面に").imasText(.cardTitle)
            Text("自分でアプリに入れた画像だけを表示します。版権画像は使いません。")
                .imasText(.note)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.gap)
    }

    private var tips: some View {
        ImasCard {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                Label("画像を足した・消した時は、アプリを一度開くとウィジェットも更新されます。", systemImage: "arrow.triangle.2.circlepath")
                Label("ロック画面ウィジェットは仕様上フルカラー写真を出せません（ホーム画面向けの機能です）。", systemImage: "lock.iphone")
            }
            .imasText(.note)
        }
    }

    // MARK: - Illustrations

    /// 端末/ウィジェットらしい角丸フレーム (実機の角丸を模した図解なので RoundedRectangle を使う)。
    private func phoneFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var imageFill: some View {
        ZStack {
            pink.accent.opacity(0.85)
            Image(systemName: "person.fill")
                .font(ImasTextRole.heroTitle.font)
                .foregroundStyle(pink.onAccent.opacity(0.9))
                .offset(y: 6)
        }
    }

    private var addImageArt: some View {
        ZStack(alignment: .bottomTrailing) {
            phoneFrame { imageFill }
                .frame(width: 92, height: 92)
            Image(systemName: "plus.circle.fill")
                .font(ImasNumeralSize.large.font)
                .symbolRenderingMode(.palette)
                .foregroundStyle(DS.ticket, .green)
                .offset(x: 6, y: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    private var homeAddArt: some View {
        ZStack(alignment: .topLeading) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: DS.Space.gap), count: 3),
                      spacing: DS.Space.gap) {
                ForEach(0..<6, id: \.self) { _ in
                    // ホーム画面のアプリアイコンの実形状を模した図解。
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DS.fill)
                        .frame(width: 34, height: 34)
                }
            }
            .frame(width: 122)
            Image(systemName: "plus.circle.fill")
                .font(ImasNumeralSize.large.font)
                .symbolRenderingMode(.palette)
                .foregroundStyle(DS.ticket, purple.accent)
                .offset(x: -10, y: -10)
        }
        .padding(.top, DS.Space.gapTight)
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    private var searchArt: some View {
        VStack(spacing: DS.Space.rowGap) {
            HStack(spacing: DS.Space.gap) {
                Image(systemName: "magnifyingglass").foregroundStyle(DS.ink2)
                Text("担当").imasText(.value)
                Spacer()
            }
            // 検索欄の実形状を模した図解。
            .padding(.horizontal, DS.Space.rowGap).padding(.vertical, DS.Space.gap)
            .background(DS.fill, in: Capsule())
            .frame(width: 150)
            phoneFrame { imageFill }.frame(width: 64, height: 64)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    private var editArt: some View {
        HStack(spacing: DS.Space.rowGap) {
            phoneFrame { imageFill }.frame(width: 70, height: 70)
            Image(systemName: "arrow.right").foregroundStyle(DS.ink3)
            HStack(spacing: DS.Space.gap) {
                Image(systemName: "slider.horizontal.3")
                Text("編集").imasText(.chip)
            }
            // 編集ボタンの実形状を模した図解。
            .padding(.horizontal, DS.Space.rowGap).padding(.vertical, DS.Space.gap)
            .background(DS.fill, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    private var tapArt: some View {
        ZStack(alignment: .bottomTrailing) {
            phoneFrame { imageFill }.frame(width: 92, height: 92)
            Image(systemName: "hand.tap.fill")
                .font(ImasNumeralSize.large.font)
                .foregroundStyle(DS.ticket)
                .offset(x: 8, y: 8)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(ImasTextRole.sectionTitle.font)
                .foregroundStyle(pink.accent)
                .offset(x: 10, y: -4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }
}

#Preview {
    NavigationStack { WidgetHowToView() }
}
