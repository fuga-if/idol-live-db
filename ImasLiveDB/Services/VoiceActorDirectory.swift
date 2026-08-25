import Foundation
import Observation

/// アイドル → 現任の声優名 を引くための共有キャッシュ。
///
/// 声優は `idol_voice_actors` に**期間つきの履歴**として持つようになり、
/// `Idol` 単体からは引けなくなった (旧 `idols.voice_actors` 列は廃止)。
/// とはいえ一覧やピッカーは `Idol` の配列しか持っておらず、行ごとに DB を引くのは
/// N+1 になる。300件程度の小さな辞書なので、まとめて読んで持っておく。
///
/// ⚠️ 「現任」は `valid_to IS NULL` の人。交代が発表されて後任が未定の間は**誰も居ない**
///    (姫野かのんが実際にその状態)。呼び出し側は nil を「未設定」ではなく
///    「今は居ない」として扱えるようにしておくこと。
@MainActor
@Observable
final class VoiceActorDirectory {
    static let shared = VoiceActorDirectory()

    private var currentByIdolId: [String: String] = [:]
    private var loaded = false

    private init() {}

    /// 現任の声優名。居なければ nil。
    func current(for idolId: String) -> String? { currentByIdolId[idolId] }

    /// 起動時と同期後に呼ぶ。二重に読み込まないよう `force` を明示しない限り一度きり。
    func load(force: Bool = false) async {
        guard force || !loaded else { return }
        do {
            currentByIdolId = try await AppContainer.shared.idolReading.idolCastNames()
            loaded = true
        } catch {
            // 読めなくても致命ではない (CV 名が出ないだけ)。次の機会に読み直す。
            loaded = false
        }
    }
}
