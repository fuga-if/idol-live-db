import Foundation
import UIKit

/// P名刺の画像 (SNS に貼る履歴書の様式) に載る担当 1 人 (押印欄の判子と担当の行)。画像は焼く前に読んでおく
/// (ImageRenderer は画像の読み込みを待たない)。
struct ProfileSheetOshi: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let color: String?
    let brandColor: String?
    let image: UIImage?
}

/// P名刺の画像の材料。中身の組み立て (欄・行・丸・詰め方) はコアの `profileSheetLayout`、
/// ここは P名刺・アプリの記録とマスタを引いて渡す形にするだけ。自分で書く欄は無い。
struct ProfileSheetMaterials {
    /// 名前・P歴・リンク・記録・ブランド・担当ブランドの設定・お気に入りの曲。
    var record: ProfileSheetRecord
    var oshi: [ProfileSheetOshi] = []
    /// 証明写真の欄の画像 (P名刺の写真)。
    var portrait: UIImage?
    /// 証明写真の欄の中に丸く置く (X のアイコン。切り方はコアの `cardPhotoShape`)。
    var portraitRound = false
    /// 自分の QR (P名刺に載せていれば)。
    var qr: UIImage?

    static let empty = ProfileSheetMaterials(
        record: ProfileSheetRecord(today: "", name: "", sinceYear: nil, oshiNames: [], oshiBrandIds: [], attended: [],
                                   songCount: 0, brands: [], brandRolesJson: "", favoriteSongs: [], links: [],
                                   hasPhoto: false, hasQr: false)
    )
}

@MainActor
enum ProfileSheetAssembler {
    static func load(card: MyProducerCard) async -> ProfileSheetMaterials {
        let c = AppContainer.shared
        let limits = producerCardLimits()
        let today = JSTDay.today()
        // 載せる担当は名刺と同じ選び方 (ブランドごとに 1 人を先に確保して上限まで。規則はコア)。
        let oshiIds = Array(await ProducerCardAssembler.cardOshiIds(
            (try? await c.markReading.markedEntityIds(entity: .idol, kind: .myPick)) ?? []
        ).prefix(Int(limits.maxOshi)))
        let attendedRefs = (try? await c.producerCards.attendedShowRefs()) ?? []
        let shows = (try? await c.producerCards.showInfos(ids: attendedRefs.map(\.showId))) ?? [:]
        let songCount = (try? await c.markReading.autoCollectedSongIds())?.count ?? 0
        let brands = (try? await c.brandReading.brands()) ?? []
        let brandById = Dictionary(brands.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let idols = oshiIds.isEmpty ? [] : ((try? await c.idolReading.idols(ids: oshiIds)) ?? [])
        let idolById = Dictionary(idols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oshiIdols = oshiIds.compactMap { idolById[$0] }
        // 担当ブランドの既定は設定の画面と同じ材料で組む (担当の上限で切らない)。
        let brandRoleRecord = await BrandRoleStore.loadRecord()
        // お気に入りの曲すべて (載せる曲と並びは選択からコアが決める。引けない曲は入れない)。
        let favorites = await FavoriteSongSource.load()

        let images = CustomImageService.shared
        let oshi = oshiIdols.map { idol in
            ProfileSheetOshi(
                id: idol.id, name: idol.name, shortName: idol.shortName, color: idol.color,
                brandColor: brandById[idol.brandId]?.color,
                // 書き出しは画像の読み込みを待たないので、ここで小さく読んでおく。
                image: images.imageURL(for: idol.id).flatMap { ProducerCardFiles.printImage(at: $0, maxPixels: 240) }
            )
        }
        let portrait = ProducerCardFiles.myPhotoURL.flatMap { ProducerCardFiles.printImage(at: $0, maxPixels: 600) }
        let qr = card.qrUrl.flatMap { ImasQRCode.render($0) }

        let record = ProfileSheetRecord(
            today: today,
            name: card.name,
            sinceYear: card.sinceYear.flatMap(UInt16.init(exactly:)),
            oshiNames: oshiIdols.map(\.name),
            oshiBrandIds: brandRoleRecord.oshiBrandIds,
            attended: attendedRefs.compactMap { ref in
                guard let info = shows[ref.showId] else { return nil }
                return ProfileShowInput(showId: ref.showId, date: ref.date, title: info.label,
                                        venue: info.venue, brandId: info.brandId)
            },
            songCount: UInt32(songCount),
            brands: brands.map {
                ProfileBrandInput(id: $0.id, label: $0.shortName, color: $0.color, sortOrder: Int64($0.sortOrder))
            },
            brandRolesJson: BrandRoleStore.json,
            favoriteSongs: favorites.map(\.input),
            links: card.links.map { cardLinkView(link: $0).display },
            hasPhoto: portrait != nil,
            hasQr: qr != nil
        )
        return ProfileSheetMaterials(
            record: record,
            oshi: oshi,
            portrait: portrait,
            portraitRound: ProducerCardFiles.myPhotoRound,
            qr: qr
        )
    }

    /// 書き出す画像 (1080 幅の PNG にする UIImage)。
    static func render(layout: ProfileSheetLayout, materials: ProfileSheetMaterials) -> UIImage? {
        ShareCardRenderer.render(ProfileSheetCard(layout: layout, materials: materials))
    }
}
