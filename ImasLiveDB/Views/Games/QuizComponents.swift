import SwiftUI

// =============================================================================
// 4 択クイズ系 (アイドル当て / ソロ曲) のコアへの受け渡しと、グレードの見せ方。
// 画面の部品 (ペンライト・チケット・正誤・結果) は QuizStage.swift にある。
//
// 出題の生成・選択肢の作り方・採点・グレード判定・母集団の条件は imas-core の
// `domain/quiz_generation.rs` が単独で持つ (iOS/Android で同じ規則を 2 度書かないため)。
// ここに残すのは描画と、コアが返した値の見せ方だけ。
// =============================================================================

/// `Idol` → アイドル当てクイズの射影。出題設定画面の見積り (`idolQuizPoolEstimate`) と
/// ゲーム本体 (`idolQuizSession`) が同じ母集団を見るよう、変換もこの 1 か所に置く。
/// CV は `VoiceActorDirectory` (MainActor) から引くのでこの関数も MainActor。
/// 誕生日は生の `--MM-DD` のまま渡す (「4月3日」への整形はコア側の規則)。
@MainActor
func idolQuizRefs(_ idols: [Idol]) -> [IdolQuizIdolRef] {
    idols.map { idol in
        IdolQuizIdolRef(
            id: idol.id,
            brandId: idol.brandId,
            isExternal: idol.isExternal,
            color: idol.color,
            bloodType: idol.bloodType,
            constellation: idol.constellation,
            birthPlace: idol.birthPlace,
            height: idol.height,
            age: idol.age.map { Int32(clamping: $0) },
            hobbies: idol.hobbies,
            talents: idol.talents,
            birthday: idol.birthday,
            voiceActor: VoiceActorDirectory.shared.current(for: idol.id)
        )
    }
}

/// ソロ曲クイズに渡す `song_artists(role='original')` の行。ゲーム本体
/// (`songSingerQuizSession`) と出題設定画面の見積り (`songSingerQuizPoolEstimate`) が
/// 同じ母集団を見るよう、行の並べ方もここに置く。
///
/// 曲名かな順の `solos` の順に並べる (コアはこの並びをそのまま母集団の並びにする)。
/// 1 曲に複数行あるまま渡すのが肝で、「原唱が単独の曲だけ出題する」判定はコアが行数で行う
/// (ここで間引くと合唱曲が 1 人の曲に化ける)。同じ曲の中の並びは辞書順に固定する
/// (`Set` の反復順は実行ごとに変わるが、どの行も落とされるので出題には影響しない)。
func songQuizOriginalArtistRows(
    solos: [SongWithArtists],
    originalArtistIds: [String: Set<String>]
) -> [SongQuizOriginalArtistRow] {
    solos.flatMap { sw in
        (originalArtistIds[sw.song.id] ?? []).sorted().map {
            SongQuizOriginalArtistRow(songId: sw.song.id, idolId: $0)
        }
    }
}

/// `Idol` → ソロ曲クイズの選択肢に使う射影 (歌手当てなのでプロフィールは要らない)。
func songQuizSingerRefs(_ idols: [Idol]) -> [SongQuizSingerRef] {
    idols.map { SongQuizSingerRef(id: $0.id, brandId: $0.brandId, isExternal: $0.isExternal) }
}

/// クイズのグレード (正答率ベース)。リザルトの主役。
/// 何 % で何グレードかの判定はコア (`QuizGrade::from_rate`) が持ち、ここは見せ方だけ。
extension QuizGrade {
    /// リング内とシェア文言に出す 1 文字。
    var label: String {
        switch self {
        case .s: return "S"
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        }
    }

    var color: Color {
        switch self {
        case .s: return DS.favorite
        case .a: return DS.success
        case .b: return DS.sys
        case .c: return DS.warning
        case .d: return DS.ink3
        }
    }
}
