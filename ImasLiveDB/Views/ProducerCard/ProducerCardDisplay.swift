import SwiftUI

/// 名刺を描くのに要る、端末のマスタの引き当て (担当のアイドル・ブランド・公演)。
/// 名刺は id しか持たないので、表示のたびにまとめて引く。端末に無い id は出さない
/// (相手の方が新しいデータを持っていた等。名刺そのものは壊さずに残す)。
struct ProducerCardDirectory {
    var idols: [String: Idol] = [:]
    var brands: [String: Brand] = [:]
    var shows: [String: ProducerCardShowInfo] = [:]

    static func load(idolIds: [String], showIds: [String]) async -> ProducerCardDirectory {
        let c = AppContainer.shared
        var dir = ProducerCardDirectory()
        let ids = Array(Set(idolIds))
        if !ids.isEmpty, let idols = try? await c.idolReading.idols(ids: ids) {
            dir.idols = Dictionary(idols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        if let brands = try? await c.brandReading.brands() {
            dir.brands = Dictionary(brands.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        let shows = showIds.filter { !$0.isEmpty }
        if !shows.isEmpty {
            dir.shows = (try? await c.producerCards.showInfos(ids: shows)) ?? [:]
        }
        return dir
    }

    /// 担当の名前とブランド (端末に無い担当は入れない)。名刺の表の組み・名刺に載せる担当の選び方はコア
    /// (`producerCardFace` / `producerCardPickOshi`)。
    func oshiEntries(_ ids: [String]) -> [CardOshiEntry] {
        ids.compactMap { id in
            guard let idol = idols[id] else { return nil }
            return CardOshiEntry(idolId: id, name: idol.name, brandId: idol.brandId,
                                 brandLabel: brands[idol.brandId]?.shortName ?? "")
        }
    }
}

/// 名刺 (コアの `ProducerCard`) を DS の `ImasProducerCard` に載せる形にする。
@MainActor
enum ProducerCardDisplay {
    /// 担当の行。`imageURL` は担当の画像の在り処 (自分の名刺はアイドルの画像、受け取った名刺は受け取った画像)。
    static func oshi(_ card: ProducerCard, directory: ProducerCardDirectory, sharedWith myOshi: Set<String> = [],
                     imageURL: (String) -> URL?) -> [ImasProducerCard.Oshi] {
        card.oshiIdolIds.compactMap { id in
            guard let idol = directory.idols[id] else { return nil }
            let brand = directory.brands[idol.brandId]
            return ImasProducerCard.Oshi(
                id: idol.id, name: idol.name, shortName: idol.shortName,
                seed: idol.color, brand: brand?.color, imageURL: imageURL(idol.id),
                subtitle: brand?.shortName, isShared: myOshi.contains(idol.id)
            )
        }
    }

    /// リンクの行。自分の QR があれば先頭に「QR」として出す (押せば開く)。
    static func links(_ card: ProducerCard) -> [ImasProducerCard.Link] {
        let qr = card.qrUrl.map { cardQrLinkView(url: $0) }
        return ([qr].compactMap { $0 } + card.links.map { cardLinkView(link: $0) }).map { view in
            ImasProducerCard.Link(label: view.label, display: view.display, url: view.url)
        }
    }

    /// 名刺の顔 (自作の名刺の画像の表・裏)。自分の名刺は端末の画像、受け取った名刺は届いた画像。
    struct Face: Equatable {
        let front: URL
        var back: URL?
    }

    /// 描くデザイン (自作の画像の名刺でも画像が無ければ入場証。決めるのはコア)。
    static func design(_ card: ProducerCard, face: Face?) -> CardDesignInfo {
        producerCardDisplayDesign(card: card, hasFaceImage: face != nil)
    }

    /// 名前の書体の PostScript 名 (デザインの書体。一覧と既定はコア)。
    static func nameFont(_ card: ProducerCard, face: Face? = nil) -> String {
        design(card, face: face).font.postscriptName
    }

    /// DS の名刺のデザイン。
    static func cardDesign(_ card: ProducerCard, face: Face?) -> ImasProducerCard.Design {
        switch design(card, face: face).design {
        case .pass: return .pass
        case .formal: return .formal
        case .pop: return .pop
        case .oshi: return .oshi
        case .custom: return face.map { .face(front: $0.front, back: $0.back) } ?? .pass
        }
    }

    /// 自分の名刺の顔 (自作の画像の表があれば)。
    static func myFace() -> Face? {
        ProducerCardFiles.myFaceURL(.front).map { Face(front: $0, back: ProducerCardFiles.myFaceURL(.back)) }
    }

    /// 受け取った名刺の顔 (届いた自作の画像の表があれば)。
    static func receivedFace(cardId: String) -> Face? {
        ProducerCardFiles.faceURL(cardId: cardId, side: .front).map {
            Face(front: $0, back: ProducerCardFiles.faceURL(cardId: cardId, side: .back))
        }
    }

    /// 記録の数 (参加公演・回収曲・次の現場)。載っていない数は出さない。
    static func cells(_ card: ProducerCard, directory: ProducerCardDirectory) -> [ImasBoard.Cell] {
        var cells: [ImasBoard.Cell] = []
        if let shows = card.showCount {
            cells.append(.init(value: shows.formatted(), unit: "公演", label: "参加公演"))
        }
        if let songs = card.songCount {
            cells.append(.init(value: songs.formatted(), unit: "曲", label: "回収曲"))
        }
        if let id = card.nextShowId, let show = directory.shows[id] {
            cells.append(.init(value: monthDay(show.date), label: "次の現場"))
        }
        return cells
    }

    /// 掲示板の右上 (「2014 — 2026」)。P 歴が無ければ名刺を作った年だけ。
    static func boardTrailing(_ card: ProducerCard) -> String? {
        let issued = String(card.issuedOn.prefix(4))
        guard issued.count == 4 else { return nil }
        if let since = card.sinceYear { return "\(since) — \(issued)" }
        return issued
    }

    /// 次の現場の掲示板の値 (`10/18`)。
    static func monthDay(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count >= 3, let m = Int(parts[1]), let d = Int(parts[2].prefix(2)) else { return "—" }
        return "\(m)/\(d)"
    }

    /// 1 行の要約 (「如月千早 · 63 公演」)。名刺入れの行の副題。
    static func summaryLine(_ card: ProducerCard, directory: ProducerCardDirectory) -> String {
        var parts: [String] = []
        let names = card.oshiIdolIds.compactMap { directory.idols[$0]?.name }
        if let first = names.first {
            parts.append(names.count > 1 ? "\(first) ほか\(names.count - 1)人" : first)
        }
        if let shows = card.showCount { parts.append("\(shows.formatted()) 公演") }
        if parts.isEmpty, let link = card.links.first {
            parts.append(cardLinkView(link: link).display)
        }
        return parts.joined(separator: " · ")
    }

    /// 名刺の裏 (紙に刷る裏と同じ)。QR は渡さなければ交換用。`payload` は受け取ったままの中身
    /// (組み直すと、新しい版のアプリが足した項目を落とした QR になる)。無ければ名刺から組む。
    static func back(_ card: ProducerCard, face: CardFace, payload: String?, qr: ImasProducerCard.Back? = nil)
        -> ImasProducerCard.Back {
        if let qr { return qr }
        return ImasProducerCard.Back(
            qr: producerCardUrlFromPayload(payload: payload ?? producerCardPayload(card: card)),
            showCount: card.showCount, songCount: card.songCount, issuedLabel: face.issuedLabel)
    }

    /// 自分の QR の裏 (「自分の QR」を選んだとき)。
    static func ownQRBack(_ card: ProducerCard, url: String) -> ImasProducerCard.Back {
        ImasProducerCard.Back(
            qr: url, qrLabel: "自分の QR コード", note: "読み取ると \(cardQrLinkView(url: url).display) が開きます。",
            showCount: card.showCount, songCount: card.songCount, issuedLabel: cardIssuedLabel(issuedOn: card.issuedOn))
    }

    /// 名刺 1 枚 (自分の名刺・受け取った名刺で同じ部品)。名刺の下の詳細は `.details`。
    /// `portraitURL` は名刺の写真 (`portraitSource` はその出どころ。X のアイコンは丸く出す)、`face` は自作の名刺の画像 (自分の名刺は端末の画像、受け取った名刺は
    /// 届いた画像。QR だけで受け取った名刺には無いので、自作の画像の名刺も入場証で描く)。
    /// `back` は裏の QR (渡さなければ交換用)。`payload` は受け取ったままの名刺の中身 (交換用の QR に使う)。
    /// `showsRecord` は名刺の下の記録の掲示板 (自分の名刺は出さない。自分の記録は P名刺の画像で見せる)。
    static func view(_ card: ProducerCard, directory: ProducerCardDirectory, sharedWith myOshi: Set<String> = [],
                     imageURL: (String) -> URL?, portraitURL: URL? = nil,
                     portraitSource: CardPhotoSource = .picked, face: Face? = nil,
                     back: ImasProducerCard.Back? = nil, payload: String? = nil, showsRecord: Bool = true,
                     onOpenLink: ((ImasProducerCard.Link) -> Void)?,
                     onOpenOshi: ((ImasProducerCard.Oshi) -> Void)?) -> ImasProducerCard {
        let oshi = oshi(card, directory: directory, sharedWith: myOshi, imageURL: imageURL)
        let cardFace = producerCardFace(card: card, drawable: directory.oshiEntries(oshi.map(\.id)))
        let byId = Dictionary(oshi.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ImasProducerCard(
            design: cardDesign(card, face: face),
            sinceImprint: cardFace.sinceImprint,
            name: card.name,
            message: card.message,
            oshi: oshi,
            faceGroups: cardFace.oshiGroups.map { group in
                ImasProducerCard.FaceGroup(label: group.brandLabel, oshi: group.idolIds.compactMap { byId[$0] })
            },
            faceCaption: cardFace.oshiCaption,
            heroOshi: cardFace.heroIdolIds.compactMap { byId[$0] },
            moreOshi: Int(cardFace.moreOshi),
            handle: cardFace.handle?.display,
            links: links(card),
            cells: showsRecord ? cells(card, directory: directory) : [],
            boardTrailing: boardTrailing(card),
            photoURL: oshi.compactMap(\.imageURL).first,
            portraitURL: portraitURL,
            portraitRound: cardPhotoShape(source: portraitSource) == .round,
            nameFont: nameFont(card, face: face),
            back: Self.back(card, face: cardFace, payload: payload, qr: back),
            onOpenLink: onOpenLink,
            onOpenOshi: onOpenOshi
        )
    }
}
