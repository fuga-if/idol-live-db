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
/// ここはアプリの記録とマスタを引いて渡す形にするだけ。自分で書く欄は無い。
struct ProfileSheetMaterials {
    /// 名前・P歴・リンク・記録・ブランド・お気に入りの曲・セトリから数えた記録。
    var record: ProfileSheetRecord
    var oshi: [ProfileSheetOshi] = []
    /// P名刺の写真。
    var portrait: UIImage?
    /// 自分の QR (P名刺に載せていれば)。
    var qr: UIImage?
    /// 名前と記入欄の書体 (P名刺の書体の PostScript 名)。
    var nameFont: String

    static let empty = ProfileSheetMaterials(
        record: ProfileSheetRecord(today: "", name: "", sinceYear: nil, oshiNames: [], oshiBrandIds: [], attended: [],
                                   songCount: 0, brands: [], favoriteSongs: [], links: [], hasPhoto: false,
                                   hasQr: false,
                                   live: ProfileLiveRecord(topSongs: [], oshiHeard: [], topVenue: nil, prefectureCount: 0)),
        nameFont: cardNameFonts()[0].postscriptName
    )

    /// 担当の色 (帯・罫・押印の判子)。担当がいなければ nil (墨)。
    var seed: String? { oshi.first?.color }
}

@MainActor
enum ProfileSheetAssembler {
    static func load(card: MyProducerCard) async -> ProfileSheetMaterials {
        let c = AppContainer.shared
        let limits = producerCardLimits()
        let today = JSTDay.today()
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
        let live = (try? await c.statsReading.profileLiveRecord(
            attendedShowIds: attendedRefs.map(\.showId), oshiIdolIds: oshiIdols.map(\.id), today: today))
            ?? ProfileSheetMaterials.empty.record.live

        // お気に入りの曲 (載せる数と並びはコア。引けない曲は入れない)。
        let favoriteIds = (try? await c.markReading.markedEntityIds(entity: .song, kind: .favorite)) ?? []
        let songs = favoriteIds.isEmpty ? [] : ((try? await c.songReading.songs(ids: favoriteIds)) ?? [])
        let songById = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let images = CustomImageService.shared
        let oshi = oshiIdols.map { idol in
            ProfileSheetOshi(
                id: idol.id, name: idol.name, shortName: idol.shortName, color: idol.color,
                brandColor: brandById[idol.brandId]?.color,
                image: images.imageURL(for: idol.id).flatMap { UIImage(contentsOfFile: $0.path) }
            )
        }
        let portrait = ProducerCardFiles.myPhotoURL.flatMap { UIImage(contentsOfFile: $0.path) }
        let qr = card.qrUrl.flatMap { ImasQRCode.render($0) }

        let record = ProfileSheetRecord(
            today: today,
            name: card.name,
            sinceYear: card.sinceYear.flatMap(UInt16.init(exactly:)),
            oshiNames: oshiIdols.map(\.name),
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
            favoriteSongs: favoriteIds.compactMap { id in songById[id].map { ProfileSongInput(id: id, title: $0.title) } },
            links: card.links.map { cardLinkView(link: $0).display },
            hasPhoto: portrait != nil,
            hasQr: qr != nil,
            live: live
        )
        return ProfileSheetMaterials(
            record: record,
            oshi: oshi,
            portrait: portrait,
            qr: qr,
            nameFont: cardNameFontInfo(font: card.font).postscriptName
        )
    }

    /// 書き出す画像 (1080 幅の PNG にする UIImage)。
    static func render(layout: ProfileSheetLayout, materials: ProfileSheetMaterials) -> UIImage? {
        ShareCardRenderer.render(ProfileSheetCard(layout: layout, materials: materials))
    }
}
