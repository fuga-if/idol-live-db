import SwiftUI

/// 自分の投稿累計の内訳ビュー。プロデュースタブ「投稿」タイル → ここに飛ぶ。
/// ローカル LocalContributionLog のカウントを内訳として並べる。
/// 個別履歴 (どのライブのコーレスか等) は将来の拡張 — 今は累計表示で割り切る。
struct MyContributionsView: View {
    @State private var log = LocalContributionLog.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp4) {
                summary
                breakdown
                editsLink
                helpText
            }
            .padding(DS.sp5)
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("マイ投稿")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("my_contributions")
    }

    /// セトリ編集・楽曲アーティスト等、サーバに記録される「編集」の履歴確認・取り消し導線。
    /// 投稿履歴(このビュー)と近い機能のため、内訳の直下にリンクとして置く。
    private var editsLink: some View {
        NavigationLink {
            MyEditsView()
        } label: {
            HStack(spacing: DS.sp3) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.imasScaled(18, weight: .semibold))
                    .foregroundStyle(DS.sys)
                    .frame(width: 36, height: 36)
                    .background(DS.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("自分の編集を確認・取り消す").font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                    Text("ライブ・楽曲・セトリの編集履歴").font(.imasCaption).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 0)
                ImasRowChevron()
            }
            .padding(.horizontal, DS.sp4).padding(.vertical, DS.sp3)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        VStack(spacing: DS.sp3) {
            Image(systemName: "square.and.pencil")
                .font(.imasScaled(36, weight: .semibold))
                .foregroundStyle(DS.sys)
                .padding(.top, DS.sp3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(log.total)").font(.imasDisplay(36, weight: .bold)).foregroundStyle(DS.ink)
                Text("件").font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink3)
            }
            Text("コミュニティへの投稿累計").font(.imasFootnote).foregroundStyle(DS.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "内訳", tight: true)
            LazyVStack(spacing: DS.sp2) {
                ForEach(LocalContributionLog.Kind.allCases, id: \.rawValue) { kind in
                    HStack(spacing: DS.sp3) {
                        Image(systemName: kind.systemImage)
                            .font(.imasScaled(18, weight: .semibold))
                            .foregroundStyle(DS.sys)
                            .frame(width: 36, height: 36)
                            .background(DS.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(kind.label).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                        Spacer(minLength: 0)
                        Text("\(log.count(of: kind))")
                            .font(.imasTitle3.weight(.bold).monospacedDigit())
                            .foregroundStyle(DS.ink)
                        Text("件").font(.imasCaption).foregroundStyle(DS.ink3)
                    }
                    .padding(.horizontal, DS.sp4).padding(.vertical, DS.sp3)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                }
            }
        }
    }

    private var helpText: some View {
        Text("セトリ編集・コーレス・動画追加・タグ追加が累計に含まれます。再インストールするとカウントはリセットされます (端末ローカル記録)。")
            .font(.imasCaption).foregroundStyle(DS.ink3)
            .padding(.top, DS.sp2)
    }
}
