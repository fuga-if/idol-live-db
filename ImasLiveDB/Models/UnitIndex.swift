import Foundation

/// セトリ表示でパフォーマー集合から「ユニット成立しているか?」を逆引きするためのインデックス。
/// AppDatabase.fetchUnitIndex() で一度構築し、setlist 画面内で使い回す。
struct UnitIndex: Sendable {
    let units: [Unit]
    /// unit_id → メンバー idol_id の集合
    let memberIds: [String: Set<String>]
    /// idol_id → その idol が所属する unit_id の集合
    let byIdol: [String: Set<String>]
    /// 楽曲が紐付いている unit_id (songs.unit_id 参照)。
    /// セトリ表示での unit 逆引きはこれに含まれるものだけに絞り、
    /// 名前だけ一致する合同メンバー集合での誤検出を避ける。
    let unitsWithSongs: Set<String>

    private let unitById: [String: Unit]

    init(
        units: [Unit],
        memberIds: [String: Set<String>],
        byIdol: [String: Set<String>],
        unitsWithSongs: Set<String> = []
    ) {
        self.units = units
        self.memberIds = memberIds
        self.byIdol = byIdol
        self.unitsWithSongs = unitsWithSongs
        self.unitById = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0) })
    }

    /// パフォーマー idol 集合から、最も良く match するユニットを返す。
    ///
    /// 判定ロジック:
    ///   - 候補ユニットは「performerIds に含まれる idol を 1 人以上メンバーに持つ」unit
    ///   - そのうち「全 members が performerIds に含まれる」= subset を満たすものを採用
    ///   - subset を満たす unit が複数あれば、メンバー数が多い方を優先 (大きい単位で表示)
    ///   - 2 ユニット合同等で performerIds がちょうど「unitA + unitB」の和集合の場合は
    ///     単一 unit で完全被覆しないため nil を返す (呼び出し側で「複数ユニット合同」扱い)
    /// - Parameters:
    ///   - requireSongs: true のとき「楽曲あり unit」のみ候補にする。セトリ表示では true 推奨。
    ///   - restrictTo: 候補に含めて良い unit_id の集合。nil なら全 unit を候補にする。
    ///     「その公演で歌唱されたユニットのみ」に絞り込むのに使う。
    func bestMatchingUnit(
        for performerIds: Set<String>,
        requireSongs: Bool = false,
        restrictTo: Set<String>? = nil
    ) -> Unit? {
        guard !performerIds.isEmpty else { return nil }

        var candidates: Set<String> = []
        for idolId in performerIds {
            if let units = byIdol[idolId] {
                candidates.formUnion(units)
            }
        }

        var best: Unit? = nil
        var bestSize = 0
        for uid in candidates {
            if let restrictTo, !restrictTo.contains(uid) { continue }
            if requireSongs && !unitsWithSongs.contains(uid) { continue }
            guard let members = memberIds[uid], members.count >= 2 else { continue }
            if members.isSubset(of: performerIds) && members.count > bestSize {
                best = unitById[uid]
                bestSize = members.count
            }
        }
        return best
    }

    /// performerIds を互いに素な unit 群で被覆する (最大集合優先の greedy)。
    /// 例: 放クラ 5 人 + ストレイライト 3 人 → [放クラ, ストレイライト]
    /// 単独枠は unit に属さない → 残りとして返す。
    func coveringUnits(
        for performerIds: Set<String>,
        requireSongs: Bool = false,
        restrictTo: Set<String>? = nil
    ) -> (units: [Unit], remaining: Set<String>) {
        guard !performerIds.isEmpty else { return ([], []) }

        var remaining = performerIds
        var chosen: [Unit] = []

        while !remaining.isEmpty {
            guard let best = bestMatchingUnit(
                for: remaining,
                requireSongs: requireSongs,
                restrictTo: restrictTo
            ) else { break }
            chosen.append(best)
            remaining.subtract(memberIds[best.id] ?? [])
        }

        return (chosen, remaining)
    }

    /// セトリ表示用: performerIds に 1 / 2 / 3 unit の「和集合が完全一致」する場合のみ返す。
    /// subset マッチ (偶然 unit メンバーが全員含まれてるだけの合唱曲で TintMe が誤検出) を防ぐ。
    /// 合同曲は 2-3 unit の union として検出される (例: アンティーカ×シーズ, 放クラ×ストレイ)。
    func exactMatchingUnits(for performerIds: Set<String>, requireSongs: Bool = false) -> [Unit] {
        guard performerIds.count >= 2 else { return [] }

        let cand = units.filter { u in
            (!requireSongs || unitsWithSongs.contains(u.id)) &&
            (memberIds[u.id]?.count ?? 0) >= 2 &&
            (memberIds[u.id]?.isSubset(of: performerIds) ?? false)
        }
        // 1 unit
        if let exact = cand.first(where: { memberIds[$0.id] == performerIds }) {
            return [exact]
        }
        // 2 unit union
        for i in 0..<cand.count {
            let u = memberIds[cand[i].id] ?? []
            for j in (i + 1)..<cand.count {
                let v = memberIds[cand[j].id] ?? []
                if u.union(v) == performerIds {
                    return [cand[i], cand[j]]
                }
            }
        }
        // 3 unit union (合同で 3 ユニット集結するケース)
        for i in 0..<cand.count {
            let u = memberIds[cand[i].id] ?? []
            for j in (i + 1)..<cand.count {
                let v = memberIds[cand[j].id] ?? []
                let uv = u.union(v)
                if uv.count > performerIds.count { continue }
                for k in (j + 1)..<cand.count {
                    let w = memberIds[cand[k].id] ?? []
                    if uv.union(w) == performerIds {
                        return [cand[i], cand[j], cand[k]]
                    }
                }
            }
        }
        return []
    }
}
