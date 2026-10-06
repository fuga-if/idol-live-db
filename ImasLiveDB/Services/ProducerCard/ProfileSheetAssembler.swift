import Foundation
import UIKit

/// プロフィール帳に載る担当 1 人 (押印欄の判子と担当の行)。画像は焼く前に読んでおく
/// (ImageRenderer は画像の読み込みを待たない)。
struct ProfileSheetOshi: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let color: String?
    let brandColor: String?
    let image: UIImage?
}

/// プロフィール帳の材料。中身の組み立て (欄・行・丸・詰め方) はコアの `profileSheetLayout`、
/// ここはアプリの記録とマスタを引いて渡す形にするだけ。
struct ProfileSheetMaterials {
    /// 名前・P歴・リンク・記録・ブランド・好きな曲 (好きな曲は `favoriteSongIds` を引いたもの)。
    var record: ProfileSheetRecord
    var oshi: [ProfileSheetOshi] = []
    /// P名刺の写真。
    var portrait: UIImage?
    /// 自分の QR (P名刺に載せていれば)。
    var qr: UIImage?
    /// 答え・名前の書体 (P名刺の書体の PostScript 名)。
    var nameFont: String
    /// 好きな曲を選ぶ候補 (お気に入りの曲)。
    var favoriteCandidates: [Song] = []
    /// 好きな曲の題 (id → 題)。
    var songTitles: [String: String] = [:]

    static let empty = ProfileSheetMaterials(
        record: ProfileSheetRecord(today: "", name: "", sinceYear: nil, oshiBrandIds: [], attended: [],
                                   songCount: 0, brands: [], favoriteSongs: [], links: []),
        nameFont: cardNameFonts()[0].postscriptName
    )

    /// 好きな曲を選び直したら、題を引き直さずに材料へ反映する。
    func with(favoriteSongIds ids: [String]) -> ProfileSheetMaterials {
        var out = self
        out.record.favoriteSongs = ids.compactMap { id in songTitles[id].map { ProfileSongInput(id: id, title: $0) } }
        return out
    }

    /// 担当の色 (帯・罫・押印の判子)。担当がいなければ nil (墨)。
    var seed: String? { oshi.first?.color }
}

@MainActor
enum ProfileSheetAssembler {
    static func load(card: MyProducerCard, sheet: ProfileSheet) async -> ProfileSheetMaterials {
        let c = AppContainer.shared
        let limits = producerCardLimits()
        let oshiIds = Array(((try? await c.markReading.markedEntityIds(entity: .idol, kind: .myPick)) ?? [])
            .prefix(Int(limits.maxOshi)))
        let attendedRefs = (try? await c.producerCards.attendedShowRefs()) ?? []
        let shows = (try? await c.producerCards.showInfos(ids: attendedRefs.map(\.showId))) ?? [:]
        let songCount = (try? await c.markReading.autoCollectedSongIds())?.count ?? 0
        let brands = (try? await c.brandReading.brands()) ?? []
        let brandById = Dictionary(brands.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let idols = oshiIds.isEmpty ? [] : ((try? await c.idolReading.idols(ids: oshiIds)) ?? [])
        let idolById = Dictionary(idols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oshiIdols = oshiIds.compactMap { idolById[$0] }

        // 好きな曲の候補はお気に入りの曲 (選んだ曲がお気に入りから外れていても題は引く)。
        let favoriteIds = (try? await c.markReading.markedEntityIds(entity: .song, kind: .favorite)) ?? []
        let songIds = Array(Set(favoriteIds + sheet.favoriteSongIds))
        let songs = songIds.isEmpty ? [] : ((try? await c.songReading.songs(ids: songIds)) ?? [])
        let songById = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let images = CustomImageService.shared
        let oshi = oshiIdols.map { idol in
            ProfileSheetOshi(
                id: idol.id, name: idol.name, shortName: idol.shortName, color: idol.color,
                brandColor: brandById[idol.brandId]?.color,
                image: images.imageURL(for: idol.id).flatMap { UIImage(contentsOfFile: $0.path) }
            )
        }

        let record = ProfileSheetRecord(
            today: JSTDay.today(),
            name: card.name,
            sinceYear: card.sinceYear.flatMap(UInt16.init(exactly:)),
            oshiBrandIds: oshiIdols.map(\.brandId),
            attended: attendedRefs.compactMap { ref in
                guard let info = shows[ref.showId] else { return nil }
                return ProfileShowInput(showId: ref.showId, date: ref.date, title: info.label,
                                        venue: info.venue, brandId: info.brandId)
            },
            songCount: UInt32(songCount),
            brands: brands.map {
                ProfileBrandInput(id: $0.id, label: $0.shortName, color: $0.color, sortOrder: Int64($0.sortOrder))
            },
            favoriteSongs: [],
            links: card.links.map { cardLinkView(link: $0).display }
        )
        var out = ProfileSheetMaterials(
            record: record,
            oshi: oshi,
            portrait: ProducerCardFiles.myPhotoURL.flatMap { UIImage(contentsOfFile: $0.path) },
            qr: card.qrUrl.flatMap { ImasQRCode.render($0) },
            nameFont: cardNameFontInfo(font: card.font).postscriptName,
            favoriteCandidates: favoriteIds.compactMap { songById[$0] },
            songTitles: songById.mapValues(\.title)
        )
        out = out.with(favoriteSongIds: sheet.favoriteSongIds)
        return out
    }

    /// 書き出す画像 (1080 幅の PNG にする UIImage)。
    static func render(layout: ProfileSheetLayout, materials: ProfileSheetMaterials) -> UIImage? {
        ShareCardRenderer.render(ProfileSheetCard(layout: layout, materials: materials))
    }
}
