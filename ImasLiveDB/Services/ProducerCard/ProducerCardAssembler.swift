import Foundation
import UIKit

/// 自分の記録 (担当・参加した公演)。名刺を組むのにも、受け取った名刺との共通点にも使う。
struct ProducerCardMyRecord: Sendable {
    /// 担当 (アプリの担当の印)。
    let oshiIds: [String]
    /// 担当の名前とブランド (端末のマスタで引けた人だけ、アプリの並び)。名刺に載せる担当はここから
    /// 本人の選択で選ぶ (選び方はコアの `producerCardOshiPickedIds`)。
    let oshiEntries: [CardOshiEntry]
    /// 参加を付けた公演 (今後の参加予定も含む)。
    let attended: [CardShowRef]
    /// 回収した曲の数。
    let songCount: Int

    /// 共通点に使う「行った公演」と「次の現場」。分け方はコア。
    var summary: CardRecordSummary {
        producerCardRecordSummary(today: JSTDay.today(), attended: attended)
    }

    /// `oshiEntries` を渡さなければ担当の id だけで組む (ブランドが分からないので、上限まで並び順で載る)。
    init(oshiIds: [String], oshiEntries: [CardOshiEntry]? = nil, attended: [CardShowRef], songCount: Int) {
        self.oshiIds = oshiIds
        self.oshiEntries = oshiEntries
            ?? oshiIds.map { CardOshiEntry(idolId: $0, name: "", brandId: "", brandLabel: "") }
        self.attended = attended
        self.songCount = songCount
    }

    /// 名刺に載せる担当 (載せる順)。`choice` は本人の選択 (nil はまだ選んでいない)。
    func cardOshiIds(choice: [String]?) -> [String] {
        producerCardOshiPickedIds(chosen: choice, oshi: oshiEntries)
    }
}

/// 自分の P名刺を組み立てる。名前などは端末の表、担当・記録の数はアプリの記録から毎回。
///
/// 何を載せるか (外した項目を落とす) だけをここで決め、名刺の形・QR の中身・公演の縮め方・
/// 収まらない分の落とし方はコア (`encodeProducerCard`)。
@MainActor
enum ProducerCardAssembler {
    static func loadMyRecord() async throws -> ProducerCardMyRecord {
        let c = AppContainer.shared
        let oshi = try await c.markReading.markedEntityIds(entity: .idol, kind: .myPick)
        let attended = try await c.producerCards.attendedShowRefs()
        let songs = try await c.markReading.autoCollectedSongIds()
        return ProducerCardMyRecord(oshiIds: oshi, oshiEntries: await oshiEntries(oshi), attended: attended,
                                    songCount: songs.count)
    }

    /// 担当の名前とブランド (名刺に載せる担当を選ぶ材料。端末のマスタで引けない担当は入れない)。
    static func oshiEntries(_ oshi: [String]) async -> [CardOshiEntry] {
        let directory = await ProducerCardDirectory.load(idolIds: oshi, showIds: [])
        return directory.oshiEntries(oshi)
    }

    /// 名刺の入力。外した項目は空にする。担当は本人の選択 (まだ選んでいなければ自動の選び方) で。
    static func input(card: MyProducerCard, record: ProducerCardMyRecord) -> ProducerCardInput {
        let summary = record.summary
        let limits = producerCardLimits()
        return ProducerCardInput(
            name: card.name,
            message: card.shows(.message) ? card.message : "",
            sinceYear: card.shows(.since) ? card.sinceYear.flatMap(UInt16.init(exactly:)) : nil,
            oshiIdolIds: card.shows(.oshi)
                ? Array(record.cardOshiIds(choice: card.cardOshiChoice).prefix(Int(limits.maxOshi))) : [],
            links: card.shows(.links) ? card.links : [],
            showCount: card.shows(.showCount) ? summary.showCount : nil,
            songCount: card.shows(.songCount) ? UInt32(record.songCount) : nil,
            nextShowId: card.shows(.next) ? summary.nextShowId : nil,
            attended: card.shows(.attended) ? summary.attendedPast : [],
            issuedOn: JSTDay.today(),
            design: card.cardDesign,
            qrUrl: card.qrUrl,
            showBrandLabels: card.shows(.brandLabels)
        )
    }

    /// 自分の名刺。まだ作っていない (名前が無い) なら nil。
    static func encode(card: MyProducerCard, record: ProducerCardMyRecord) -> EncodedProducerCard? {
        let input = input(card: card, record: record)
        guard validateProducerCard(input: input) == nil else { return nil }
        return encodeProducerCard(input: input)
    }

    /// `#` の後ろ。
    static func payload(of encoded: EncodedProducerCard) -> String {
        producerCardPayload(card: encoded.card)
    }

    /// 自分の担当の画像 (代表の 1 枚) を送る形にする。画像を設定していない担当は入れない (判子で出る)。
    static func myOshiImages(for card: ProducerCard) -> [CardFileImage] {
        let images = CustomImageService.shared
        return card.oshiIdolIds.compactMap { id in
            guard let url = images.imageURL(for: id),
                  let image = UIImage(contentsOfFile: url.path),
                  let jpeg = ProducerCardFiles.jpeg(image) else { return nil }
            return CardFileImage(idolId: id, jpeg: jpeg, kind: .oshi)
        }
    }

    /// 自分の名刺の写真 (切り抜いた JPEG をそのまま。元の画質で渡す)。出どころも渡す (X のアイコンなら
    /// 相手の端末でも丸く出る)。
    static func myPhotoImage() -> CardFileImage? {
        guard let url = ProducerCardFiles.myPhotoURL, let jpeg = try? Data(contentsOf: url) else { return nil }
        return CardFileImage(idolId: "", jpeg: jpeg, kind: .photo, photoSource: ProducerCardFiles.myPhotoSource)
    }

    /// 自作の名刺の画像 (表・裏。平らにした JPEG をそのまま渡す)。載せるかどうか
    /// (デザインが自作の画像の名刺だけ・裏は表があるときだけ) はコアの `encodeCardFile` が決める。
    static func myFaceImages() -> [CardFileImage] {
        [(ProducerCardFiles.Side.front, CardFileImageKind.faceFront), (.back, .faceBack)].compactMap { side, kind in
            guard let url = ProducerCardFiles.myFaceURL(side), let jpeg = try? Data(contentsOf: url) else { return nil }
            return CardFileImage(idolId: "", jpeg: jpeg, kind: kind)
        }
    }

    /// 自分の名刺ファイル (名刺 + 担当の画像 + 名刺の写真 + 自作の名刺の画像)。
    static func myCardFile(_ encoded: EncodedProducerCard) -> Data? {
        let images = myOshiImages(for: encoded.card) + [myPhotoImage()].compactMap { $0 } + myFaceImages()
        return encodeCardFile(payload: payload(of: encoded), images: images)
    }

    /// 共有シートに渡す名刺ファイル (一時フォルダに名刺の名前で書く)。
    static func writeShareFile(_ data: Data, card: ProducerCard) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("producer_card_share", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(cardFileName(card: card))
        try data.write(to: url, options: .atomic)
        return url
    }
}
