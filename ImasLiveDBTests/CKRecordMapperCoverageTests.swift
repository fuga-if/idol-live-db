import CloudKit
import XCTest
@testable import ImasLiveDB

/// `CKRecordMapper` がレコードのフィールドを読み落としていないことを検査する。
///
/// なぜ個別フィールドのテストではなく網羅チェックなのか:
/// GRDB の `upsert` は「モデルがエンコードした列」を全部書く
/// (`AppDatabase+Sync.swift` の `record.upsert(db)`)。したがって
/// **モデルにプロパティを足して mapper に足し忘れると、同期のたびにその列が
/// NULL で上書きされる** — 列を足さないより悪い。
///
/// これは実際に `series_group` で起きていた。`Song` 側にはプロパティも
/// CodingKeys もあり「宣言漏れを直した」というコメントまで付いていたのに、
/// `CKRecordMapper.song(from:)` だけが `record["seriesGroup"]` を読んでおらず、
/// 1,956 曲の series_group が同期のたび消えてシリーズ絞り込みが壊れていた。
/// (Android の `SyncMappers.kt` は正しく読んでいたので iOS だけの不整合。)
///
/// 個別テストでは「次に足したプロパティ」を守れないので、Mirror で全プロパティを
/// 走査して「値を入れたレコードから作ったモデルに nil が残っていないか」を見る。
final class CKRecordMapperCoverageTests: XCTestCase {

    /// 全プロパティに値が入った CKRecord を組み立てる。
    private func record(type: String, fields: [String: CKRecordValue]) -> CKRecord {
        let rec = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: "test"))
        for (key, value) in fields { rec[key] = value }
        return rec
    }

    /// Mirror で nil のプロパティ名を集める。
    private func nilProperties(of subject: Any) -> [String] {
        Mirror(reflecting: subject).children.compactMap { child in
            guard let label = child.label else { return nil }
            // Optional の中身が nil かどうかを Mirror 経由で判定する
            let valueMirror = Mirror(reflecting: child.value)
            guard valueMirror.displayStyle == .optional else { return nil }
            return valueMirror.children.isEmpty ? label : nil
        }
    }

    /// Song: CloudKit の Song レコードにある全フィールドを埋めて、
    /// 変換後の Song に nil が1つも残らないことを確認する。
    func testSongMapperReadsEveryField() throws {
        let rec = record(type: "Song", fields: [
            "id": "s1" as NSString,
            "title": "蒼い鳥" as NSString,
            "titleKana": "アオイトリ" as NSString,
            "brandId": "765as" as NSString,
            "songType": "solo" as NSString,
            "releaseDate": "2005-01-01" as NSString,
            "durationSec": 240 as NSNumber,
            "composer": "作曲者" as NSString,
            "lyricist": "作詞者" as NSString,
            "arranger": "編曲者" as NSString,
            "cdSeries": "MASTER ARTIST" as NSString,
            "cdTitle": "アルバム名" as NSString,
            "artworkUrl": "https://example.com/a.jpg" as NSString,
            "previewUrl": "https://example.com/p.m4a" as NSString,
            "appleMusicId": "123456" as NSString,
            "appleMusicAlbumId": "654321" as NSString,
            "isrc": "JPXX01234567" as NSString,
            "lyricsUrl": "https://example.com/l" as NSString,
            "parentSongId": "s0" as NSString,
            "singerLabel": "如月千早" as NSString,
            "unitName": "ユニット名" as NSString,
            "unitId": "u1" as NSString,
            "seriesGroup": "LIVE THE@TER FORWARD" as NSString,
        ])

        let song = try XCTUnwrap(CKRecordMapper.song(from: rec))
        let missing = nilProperties(of: song)
        XCTAssertTrue(
            missing.isEmpty,
            """
            CKRecordMapper.song(from:) が読み落としているプロパティ: \(missing)

            Song にプロパティを足したら CKRecordMapper.song(from:) にも足すこと。
            片方だけだと CloudKit 同期のたびに該当列が NULL 上書きされる。
            (このテストにも該当フィールドを追加すること。)
            """
        )
    }

    /// Idol も同じ性質を持つので同様に守る (現状は全フィールド読めている)。
    func testIdolMapperReadsEveryField() throws {
        let rec = record(type: "Idol", fields: [
            "id": "i1" as NSString,
            "brandId": "765as" as NSString,
            "name": "如月千早" as NSString,
            "nameKana": "キサラギチハヤ" as NSString,
            "nameRomaji": "Kisaragi Chihaya" as NSString,
            "familyName": "如月" as NSString,
            "givenName": "千早" as NSString,
            "nickname": "ちひゃー" as NSString,
            "color": "#0000FF" as NSString,
            "sortOrder": 5 as NSNumber,
            "birthday": "02-25" as NSString,
            "bloodType": "A" as NSString,
            "height": 162.0 as NSNumber,
            "weight": 41.0 as NSNumber,
            "birthPlace": "東京都" as NSString,
            "age": 16 as NSNumber,
            "bust": 72.0 as NSNumber,
            "waist": 55.0 as NSNumber,
            "hip": 78.0 as NSNumber,
            "constellation": "うお座" as NSString,
            "hobbies": "音楽鑑賞" as NSString,
            "talents": "歌" as NSString,
            "description": "歌に人生を捧げる少女" as NSString,
            "gender": "女性" as NSString,
            "handedness": "右" as NSString,
            "debutDate": "2005-01-01" as NSString,
            "attribute": "クール" as NSString,
            "isExternal": 0 as NSNumber,
            "aliases": "千早" as NSString,
            "voiceActors": "今井麻美" as NSString,
        ])

        let idol = try XCTUnwrap(CKRecordMapper.idol(from: rec))
        let missing = nilProperties(of: idol)
        XCTAssertTrue(
            missing.isEmpty,
            "CKRecordMapper.idol(from:) が読み落としているプロパティ: \(missing)"
        )
    }
}
