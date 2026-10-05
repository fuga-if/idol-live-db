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

    /// 名前の書体の PostScript 名 (書体の一覧と既定はコア)。
    static func nameFont(_ card: ProducerCard) -> String {
        producerCardNameFont(card: card).postscriptName
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

    static func sinceImprint(_ card: ProducerCard) -> String? {
        card.sinceYear.map { "SINCE \($0)" }
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
        if parts.isEmpty, let link = links(card).first {
            parts.append(link.display)
        }
        return parts.joined(separator: " · ")
    }

    /// 名刺 1 枚の View (自分の名刺・受け取った名刺で同じ部品)。
    /// `portraitURL` は名刺の写真 (自分の名刺は端末の写真、受け取った名刺は届いた写真。QR だけで
    /// 受け取った名刺には無い)。
    static func view(_ card: ProducerCard, directory: ProducerCardDirectory, sharedWith myOshi: Set<String> = [],
                     imageURL: (String) -> URL?, portraitURL: URL? = nil,
                     onOpenLink: ((ImasProducerCard.Link) -> Void)?,
                     onOpenOshi: ((ImasProducerCard.Oshi) -> Void)?) -> ImasProducerCard {
        let oshi = oshi(card, directory: directory, sharedWith: myOshi, imageURL: imageURL)
        return ImasProducerCard(
            sinceImprint: sinceImprint(card),
            name: card.name,
            message: card.message,
            oshi: oshi,
            links: links(card),
            cells: cells(card, directory: directory),
            boardTrailing: boardTrailing(card),
            photoURL: oshi.compactMap(\.imageURL).first,
            portraitURL: portraitURL,
            nameFont: nameFont(card),
            onOpenLink: onOpenLink,
            onOpenOshi: onOpenOshi
        )
    }
}
