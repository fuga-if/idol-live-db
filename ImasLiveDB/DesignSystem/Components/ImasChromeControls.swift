import SwiftUI

// =============================================================================
// ナビバーの部品 (docs/DESIGN_SYSTEM.md §2.1)
//
// ImasToolbarButton    ナビバーの記号のボタン。読み上げは言葉で。数の札 (絞り込みの件数) を付けられる。
// ImasSearchField      ナビバーの中に収める 1 行の絞り込み欄 (一覧の頭)。
// ImasNameFilterField  絞り込みシートの頭の「名前で絞り込み」欄。
// =============================================================================

// MARK: - 記号のボタン

/// ナビバーの記号のボタン。文字は書かず記号 1 つ。`label` は読み上げに使う。
/// `badge` が 1 以上なら右上に朱の数の札 (効いている絞り込みの数など)。
struct ImasToolbarButton: View {
    let systemImage: String
    let label: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.imasMono(10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(DS.stamp, in: Capsule())
                            .offset(x: 8, y: -7)
                            .accessibilityHidden(true)
                    }
                }
        }
        .accessibilityLabel(label)
        .accessibilityValue(badge > 0 ? "\(badge) 件" : "")
    }
}

// MARK: - 絞り込みの欄

/// フィルタシート先頭に置く「名前で絞り込み」フィールド。
///
/// これは検索ではなく **フィルタ** である (ブランド絞り込み・並び順と合成され、一覧の並びを保つ)。
/// 以前はツールバーの虫眼鏡から出るインライン検索だったが、それだと同じナビバーに虫眼鏡が
/// 2 つ並び「探す (詳細へ飛ぶ)」と「絞る (一覧を絞る)」の区別が付かなかったため、
/// 役割どおりフィルタ側へ移した。横断的に探すのは `UnifiedSearchView` の担当。
struct ImasNameFilterField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: DS.sp3) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.imasScaled(13, weight: .semibold))
                .foregroundStyle(DS.ink3)
            TextField(prompt, text: $text)
                .font(.imasSubhead)
                .foregroundStyle(DS.ink)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .autocorrectionDisabled()
            // ⚠️ `if !text.isEmpty { ... }` で出し入れしてはいけない。
            // 1 文字目を打った瞬間だけ「空 → 非空」で入力欄の兄弟構成が変わり、
            // その組み直しで日本語 IME の未確定文字が確定されてしまう
            // (「1 文字目だけ変換できない」の原因。2 文字目以降は非空のままなので起きない)。
            // 常に置いたまま見た目だけ消す。空のときに幅を確保しておくと、
            // 入力開始時に文字が横にずれる跳ねも同時に無くなる。
            Button { text = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.imasScaled(14))
                    .foregroundStyle(DS.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("絞り込みを解除")
            .opacity(text.isEmpty ? 0 : 1)
            .disabled(text.isEmpty)
            .accessibilityHidden(text.isEmpty)
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
        .background(DS.fill, in: Capsule())
    }
}

/// 同じバーに並ぶツールバーボタン (設定・フィルタ・その他) の背景の高さ。
///
/// iOS が描くボタン背景をスクリーンショットから実測した値 (44pt)。入力欄の高さを
/// 中身任せにすると 31pt にしかならず、隣のボタンより一回り低くなって収まりが悪い。
private let imasSearchFieldHeight: CGFloat = 44

/// ナビゲーションバーの中に収める、1 行ぶんの絞り込みフィールド。
///
/// `.searchable` のドロワーは常時 52pt の行を占め、大タイトル (52pt) と合わせると
/// ステータスバー・フィルタチップ込みで画面の 3 割近くが中身の前に消えていた。
/// ここではバー (44pt) そのものに入れて、ヘッダーを 1 行に畳む。
///
/// `.searchable` を捨てた代償は自前で埋める:
/// - 消去は末尾の ⊗ (テキストがあるときだけ出す)
/// - `.searchScopes` の代わりが `leading` (楽曲一覧の 曲名/歌詞 切り替え)
/// - キーボードを閉じる導線は一覧側の `.scrollDismissesKeyboard` に任せる
///
/// 文字サイズは `.accessibility1` で頭打ちにする。ナビバーの高さは中身では伸びないので、
/// 際限なく拡大すると入力欄が切れて操作できなくなる。
///
/// 高さは隣のツールバーボタンに合わせる (`imasSearchFieldHeight`)。
struct ImasSearchField<Leading: View>: View {
    let prompt: String
    @Binding var text: String
    /// 確定 (キーボードの検索キー)。歌詞のようにサーバへ投げるものだけが使う。
    var onSubmit: () -> Void = {}
    /// 入力欄の頭に差す小物。検索対象の切り替えなど。
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: DS.sp2) {
            Image(systemName: "magnifyingglass")
                .font(.imasScaled(13, weight: .semibold))
                .foregroundStyle(DS.ink3)
            leading
            TextField(prompt, text: $text)
                .font(.imasSubhead)
                .foregroundStyle(DS.ink)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
            // ⚠️ `if !text.isEmpty { ... }` で出し入れしてはいけない。
            // 1 文字目を打った瞬間だけ「空 → 非空」で入力欄の兄弟構成が変わり、
            // その組み直しで日本語 IME の未確定文字が確定されてしまう
            // (「1 文字目だけ変換できない」の原因。2 文字目以降は非空のままなので起きない)。
            // 常に置いたまま見た目だけ消す。空のときに幅を確保しておくと、
            // 入力開始時に文字が横にずれる跳ねも同時に無くなる。
            Button { text = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.imasScaled(14))
                    .foregroundStyle(DS.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("絞り込みを解除")
            .opacity(text.isEmpty ? 0 : 1)
            .disabled(text.isEmpty)
            .accessibilityHidden(text.isEmpty)
        }
        .padding(.horizontal, DS.sp4)
        // ⚠️ `frame` は **`background` より先**に置くこと。
        // 後ろに置くと、カプセルは中身の幅のまま描かれて透明な枠だけが広がる
        // (見た目は「中央に寄った小さい入力欄」になり、余白の理由が分からなくなる)。
        //
        // `maxWidth: .infinity` だけでは広がらない。ナビバーの中央 (`.principal`) は
        // UIKit の titleView で、中身の**理想サイズ**を訊いて幅を決めるため。
        // 巨大な `idealWidth` を返して、左右のツールバー項目に挟まれた残り幅まで
        // 押し広げてもらう。
        .frame(idealWidth: 10_000, maxWidth: .infinity, minHeight: imasSearchFieldHeight)
        .background(DS.fill, in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

extension ImasSearchField where Leading == EmptyView {
    init(prompt: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) {
        self.init(prompt: prompt, text: text, onSubmit: onSubmit) { EmptyView() }
    }
}
