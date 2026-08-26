import SwiftUI
import UIKit

// =============================================================================
// ImasLiveDB — 無限色テーマエンジン (SwiftUI 配線)
// -----------------------------------------------------------------------------
// 入力は「シード色 1 色」だけ。そこから UI に必要なトークン一式を機械的に導出する。
//
// **導出の計算そのものは Rust 共有コア (imas-core: domain/color_engine.rs) が正本。**
// 以前はここに 338 行の同じ計算があり、Android にも別実装があったため、同じシードから
// 同じ色が出る保証が無かった。計算を 1 本に畳んだので、このファイルに残すのは
// OS ブリッジだけ:
//   1. コアが返す ThemeRgb (sRGB 0.0–1.0) → SwiftUI `Color`
//   2. SwiftUI `Color` → 成分の取り出し (UIColor で現在のトレイトを解決してから渡す)
//   3. メモ化 — SwiftUI が描画のたびに導出を呼ぶという「描画側の事情」。
//      コアは純粋計算だけを持ち、キャッシュは呼ばれる回数を知っている側 (ここ) が持つ。
//
// 集約 (一覧) では穏やか・フォーカス (詳細/担当ヒーロー) では鮮やか、の原則と
// 「アイドル色 → 所属ブランド色 → ニュートラル」のフォールバック連鎖はコア側の規則。
// =============================================================================

/// シード 1 色から導出されたテーマトークン一式。ライト/ダークで導出規則が変わる。
struct ImasTheme: Equatable {
    var accent: Color
    var onAccent: Color
    var tint: Color
    var tintStrong: Color
    var chipBg: Color
    var chipText: Color
    var ring: Color
    var bar: Color
    var dot: Color
    var gradFrom: Color
    var gradTo: Color
    var separator: Color
    var heroSurface: Color
    /// 低彩度シード (S < 0.10) は「グレー」扱いで発色を抑える。
    var isNeutral: Bool

    /// コアのトークン → SwiftUI。色が Swift 側に現れる唯一の地点。
    fileprivate init(_ colors: ImasThemeColors) {
        accent = Color(colors.accent)
        onAccent = Color(colors.onAccent)
        tint = Color(colors.tint)
        tintStrong = Color(colors.tintStrong)
        chipBg = Color(colors.chipBg)
        chipText = Color(colors.chipText)
        ring = Color(colors.ring)
        bar = Color(colors.bar)
        dot = Color(colors.dot)
        gradFrom = Color(colors.gradFrom)
        gradTo = Color(colors.gradTo)
        separator = Color(colors.separator)
        heroSurface = Color(colors.heroSurface)
        isNeutral = colors.isNeutral
    }
}

// MARK: - 導出エントリポイント + メモ化
//
// メモの実装 (CacheKey / cache / memoized) は private のまま同じ extension に閉じ込める。
// 呼ぶのはこのファイルの導出入口だけで、外から鍵を作られると同じ色に別の鍵が生えるため。

extension ImasTheme {
    /// シード hex (アイドル色) → トークン。色が無ければブランド色 → ニュートラルへフォールバック。
    /// - Parameters:
    ///   - seed: アイドル等のイメージカラー hex (`#RRGGBB`)。nil/不正なら次へ。
    ///   - brand: ブランドカラー hex。seed が無いときのフォールバック。
    ///   - scheme: ライト/ダーク。
    static func derive(seed: String?, brand: String? = nil, scheme: ColorScheme) -> ImasTheme {
        let dark = scheme == .dark
        return memoized(CacheKey(source: .seed(seed, brand), dark: dark)) {
            ImasTheme(themeDerive(seed: seed, brand: brand, dark: dark))
        }
    }

    /// 実体色を持たない「分類キー」(タグのカテゴリ名、編集フィードのレコード種別名等) から
    /// 安定した色を導出する。同じキーは常に同じ色になる (文字列の安定ハッシュ → 色相)。
    /// アイドル/ブランドの「本当の色」を表すものではなく、3種類以上の区分を見分けやすく
    /// 塗り分けたいだけの場面向け。個別に固定パレット (`.purple`/`.indigo`/... 等) を
    /// 手書きする代わりにこちらを使うと、区分がいくつ増えても保守なしで書き分けられる。
    static func derive(categoryKey: String, scheme: ColorScheme) -> ImasTheme {
        let dark = scheme == .dark
        return memoized(CacheKey(source: .categoryKey(categoryKey), dark: dark)) {
            ImasTheme(themeDeriveForCategoryKey(key: categoryKey, dark: dark))
        }
    }

    /// SwiftUI `Color` を直接シードにしたい場面 (ユーザーが選んだ任意色等、hex文字列を
    /// 経由せず既に `Color` を持っている) 用のエントリポイント。
    static func derive(colorSeed: Color, scheme: ColorScheme) -> ImasTheme {
        derive(hex: ColorMath.hexString(from: colorSeed), dark: scheme == .dark)
    }

    /// 単一の有効な hex からトークンを導出する低レベル API (メモ化付き)。
    /// 不正な hex はコアがニュートラルグレーへ倒すので、seed だけ渡す形と結果は一致する。
    static func derive(hex: String, dark: Bool) -> ImasTheme {
        memoized(CacheKey(source: .seed(hex, nil), dark: dark)) {
            ImasTheme(themeDerive(seed: hex, brand: nil, dark: dark))
        }
    }

    // MARK: メモ化 (描画側の事情。コアは持たない)

    /// 導出結果のメモ。一覧では全行の avatar/chip が同じ少数の色を何度も導出するうえ、
    /// SwiftUI は描画のたびに body を評価する。毎回 FFI 境界を跨ぐとスクロール/タブ切替の
    /// フレーム落ちになるので、境界の手前で止める。distinct な色数は高々アイドル数×2 で有界。
    private struct CacheKey: Hashable {
        /// 入口ごとに鍵を分ける。文字列連結の鍵だと、シードや分類キーに区切り文字が
        /// 混ざったときに別物同士が同じ鍵になり得る。
        enum Source: Hashable {
            case seed(String?, String?)
            case categoryKey(String)
        }

        var source: Source
        var dark: Bool
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [CacheKey: ImasTheme] = [:]

    private static func memoized(_ key: CacheKey, _ compute: () -> ImasTheme) -> ImasTheme {
        if let cached = cacheLock.withLock({ cache[key] }) { return cached }
        // FFI はロックの外で跨ぐ。同じ鍵が同時に二度計算されても、コアは純粋関数なので
        // 結果は同一 (ロックを跨いで待たせるより、まれな二重計算の方が安い)。
        let theme = compute()
        cacheLock.withLock { cache[key] = theme }
        return theme
    }

    /// 一覧 1 画面ぶんのシードを **1 回の FFI** でまとめて温める。
    ///
    /// 行ごとに `derive` を呼ぶと初回描画で行数ぶん境界を跨ぐ。行が組まれる前にここで
    /// メモを埋めておけば、以後は行がキャッシュだけを引く。既出の鍵と重複は落とすので、
    /// 同じ色が並ぶ一覧で実際にコアへ渡る件数はごく少ない。
    static func prewarm(_ requests: [ThemeSeedRequest], scheme: ColorScheme) {
        let dark = scheme == .dark
        var keys: [CacheKey] = []
        var pending: [ThemeSeedRequest] = []
        var seen: Set<CacheKey> = []
        cacheLock.withLock {
            for request in requests {
                let key = CacheKey(source: .seed(request.seed, request.brand), dark: dark)
                guard cache[key] == nil, seen.insert(key).inserted else { continue }
                keys.append(key)
                pending.append(request)
            }
        }
        guard !pending.isEmpty else { return }

        let derived = themeDeriveBatch(requests: pending, dark: dark)
        cacheLock.withLock {
            for (key, colors) in zip(keys, derived) { cache[key] = ImasTheme(colors) }
        }
    }
}

// MARK: - 色ユーティリティ (コアへの入口 + UIColor ブリッジ)

/// 色の計算は **すべて Rust コア (domain/color_engine.rs) が正本**。ここに計算式を
/// 書き足してはいけない (書いた瞬間、iOS だけ Android と違う色を出す経路が復活する)。
/// 残しているのは (1) コア関数へのそのままの入口と (2) SwiftUI `Color` ⇄ 成分の
/// OS ブリッジだけ。
enum ColorMath {
    /// 色が無いときに使う低彩度グレーのシード (ニュートラル経路に落ちる)。
    /// `static let` なのでコアへの問い合わせはプロセスで 1 回だけ。
    static let neutralSeed = themeNeutralSeed()

    /// 最初に見つかった有効な hex を返す (正規化はしない)。
    static func firstValidHex(_ candidates: String?...) -> String? {
        // コアは未設定を空文字で受ける (空文字は常に無効なので nil を渡すのと同じ扱い)。
        themeFirstValidHex(candidates: candidates.map { $0 ?? "" })
    }

    /// `#RGB` / `#RRGGBB` を 6 桁小文字 hex に正規化。無効なら nil。
    static func normalizedHex(_ hex: String) -> String? {
        themeNormalizedHex(hex: hex)
    }

    /// 基準色 (ブランドカラー等) の色味を保ったまま、キーごとに少しだけ振ったバリエーション hex。
    /// 色相は ±16° までなので「同じブランドの別系列」に見える。
    ///
    /// メモ化するのは `ImasTheme` の導出と同じ理由。ブランドタイムラインは pan/zoom の
    /// たびに body を評価し、帯 1 本ごとにこれを引く。組み合わせは
    /// 「ブランド色 × 系列キー」で有界なので、境界を跨ぐのは各組み合わせにつき 1 回でよい。
    static func variantHex(of hex: String, key: String) -> String {
        let cacheKey = VariantKey(hex: hex, key: key)
        if let cached = variantLock.withLock({ variantCache[cacheKey] }) { return cached }
        let variant = themeVariantHex(hex: hex, key: key)
        variantLock.withLock { variantCache[cacheKey] = variant }
        return variant
    }

    private struct VariantKey: Hashable {
        var hex: String
        var key: String
    }

    private static let variantLock = NSLock()
    nonisolated(unsafe) private static var variantCache: [VariantKey: String] = [:]

    /// 任意の背景 `Color` (メンバーカラー/ブランドカラーの帯・チップ等) の上に乗せる
    /// 前景色を WCAG コントラストで黒/白から自動選択する。
    /// 黄色 (#F5C900 系)・白系・水色系など明るい背景での白文字固定の破綻を防ぐ共通入口。
    ///
    /// メモ化するのは `variantHex` と同じ理由。カレンダーの日セルや一覧の行は `ForEach` の
    /// 中からこれを引き、月送り・日付タップ・スクロールのたびに body ごと引き直す
    /// (月表示なら 6×7 マスの帯すべて)。行ごとに境界を跨がせない、という一覧の原則は
    /// 「行の中から呼ばれる関数」にもそのまま効く。
    ///
    /// 鍵は **現在のトレイトで解決した後の** 成分。動的色は同じ `Color` でもライト/ダークで
    /// 別の値に解決されるので、解決前の `Color` を鍵にすると片方の答えをもう片方に返す。
    /// 別々の値になる背景色は帯・チップの色数ぶんしか無いので、キャッシュは有界。
    static func onColor(_ bg: Color) -> Color {
        let background = bg.themeRgb
        if let cached = onColorLock.withLock({ onColorCache[background] }) { return cached }
        let ink = Color(themeOnColor(background: background))
        onColorLock.withLock { onColorCache[background] = ink }
        return ink
    }

    private static let onColorLock = NSLock()
    nonisolated(unsafe) private static var onColorCache: [ThemeRgb: Color] = [:]

    /// SwiftUI `Color` → `#rrggbb` (現在のトレイトで解決した sRGB 値)。
    /// コアの入口が hex なので、`Color` を 8bit hex に書き下すところまでがブリッジの仕事。
    static func hexString(from color: Color) -> String {
        let rgb = color.themeRgb
        return String(format: "#%02x%02x%02x", byte(rgb.r), byte(rgb.g), byte(rgb.b))
    }

    /// 0.0–1.0 の成分を 8bit へ。丸めは Swift `rounded()` (0 から遠い側) のまま。
    private static func byte(_ component: Double) -> Int {
        Int((min(1, max(0, component)) * 255).rounded())
    }
}

// MARK: - Color ⇄ コア成分 (この 2 つが唯一の変換点)

extension Color {
    /// コアが返す成分 (sRGB 0.0–1.0) をそのまま塗る。
    init(_ themeRgb: ThemeRgb) {
        self.init(.sRGB, red: themeRgb.r, green: themeRgb.g, blue: themeRgb.b)
    }

    /// 現在のトレイトで解決した sRGB 成分 (0.0–1.0)。ダーク対応の動的色はここで確定する。
    fileprivate var themeRgb: ThemeRgb {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return ThemeRgb(r: Double(r), g: Double(g), b: Double(b))
    }
}

// MARK: - SwiftUI 連携

private struct ImasThemeKey: EnvironmentKey {
    static let defaultValue = ImasTheme.derive(hex: ColorMath.neutralSeed, dark: false)
}

extension EnvironmentValues {
    /// 祖先が `.imasTheme(seed:)` を与えた場合に読めるテーマ。
    var imasTheme: ImasTheme {
        get { self[ImasThemeKey.self] }
        set { self[ImasThemeKey.self] = newValue }
    }
}

extension View {
    /// このサブツリーに seed 由来のテーマを供給する。配下は `@Environment(\.imasTheme)` で参照。
    func imasTheme(seed: String?, brand: String? = nil) -> some View {
        modifier(ImasThemeModifier(seed: seed, brand: brand))
    }

    /// 一覧が行ごとに引くテーマを、行が組まれる前に 1 回の FFI でまとめて温める。
    /// スクロールで次々に現れる行が個別に境界を跨がないようにするための下ごしらえ。
    ///
    /// - Parameters:
    ///   - population: **母集団が入れ替わったら変わる**安い値 (データの版、件数など)。
    ///     body は検索語の 1 打鍵や関係の無い状態変化のたびに再評価されるので、これが
    ///     同じなら温め直す物は 1 件も無い、と即断して `seeds` の評価ごと省く。
    ///     余分に変わるぶんには温め直すだけで無害だが、変わったのに同じ値を渡すと
    ///     新しい行が個別に導出してしまうので、母集団の識別子として正しい値を渡すこと。
    ///   - seeds: 温めるシード一式。上記のとおり毎回は評価されない (行数ぶんの配列を
    ///     打鍵のたびに組み直さないための遅延)。
    func imasThemePrewarm(population: some Hashable,
                          seeds: @escaping @MainActor () -> [ThemeSeedRequest]) -> some View {
        modifier(ImasThemePrewarmModifier(population: AnyHashable(population), seeds: seeds))
    }

    /// ブランドへのフォールバックを使わない一覧 (アイドル色だけで塗るグリッド等) 向けの短い形。
    func imasThemePrewarm(population: some Hashable,
                          colorSeeds: @escaping @MainActor () -> [String?]) -> some View {
        imasThemePrewarm(population: population) {
            colorSeeds().map { ThemeSeedRequest(seed: $0, brand: nil) }
        }
    }
}

private struct ImasThemeModifier: ViewModifier {
    let seed: String?
    let brand: String?
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.environment(\.imasTheme, ImasTheme.derive(seed: seed, brand: brand, scheme: scheme))
    }
}

/// 温め済みの母集団の目印。ライト/ダークで導出規則が変わるので配色も鍵に含める。
private struct PrewarmToken: Hashable {
    var population: AnyHashable
    var dark: Bool
}

/// 直前に温めた目印を body の評価を跨いで持ち回すだけの箱。
///
/// 参照型なのは、`@State` が指す**値**を差し替えずに中身だけ書き換えるため。
/// 値を差し替えると「描画中の状態変更」になり SwiftUI の再評価を誘発してしまうが、
/// ただのクラスのプロパティ更新は SwiftUI から観測されないので誘発しない。
private final class PrewarmMemo {
    var warmed: PrewarmToken?
}

private struct ImasThemePrewarmModifier: ViewModifier {
    let population: AnyHashable
    let seeds: @MainActor () -> [ThemeSeedRequest]
    @Environment(\.colorScheme) private var scheme
    @State private var memo = PrewarmMemo()

    func body(content: Content) -> some View {
        // 温めは body の評価中に済ませる。行 (LazyVStack の中身) が組まれるのはこの後なので、
        // 初回描画から行はメモだけを引く。onAppear では初回描画に間に合わない。
        // 埋めるのは純粋計算のメモだけで、観測される状態は動かないため再評価も誘発しない。
        //
        // 母集団が前回と同じなら `seeds()` すら呼ばない。body は打鍵やスクロールのたびに
        // 再評価されるが、そのとき温める物はもう 1 件も無いので、行数ぶんの配列を組み直して
        // 全件キャッシュ済みだと確かめ直すのは丸ごと無駄になる。
        let token = PrewarmToken(population: population, dark: scheme == .dark)
        if memo.warmed != token {
            ImasTheme.prewarm(seeds(), scheme: scheme)
            memo.warmed = token
        }
        return content
    }
}
