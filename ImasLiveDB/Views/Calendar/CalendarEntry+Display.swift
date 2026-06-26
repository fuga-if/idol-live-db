import SwiftUI

extension CalendarEntry {
    /// カレンダーのドットに使うエンティティ色。
    /// 公演=ブランド色 / リリース=橙 (DS.warning) / 誕生日=アイドル色 or ピンク。
    var accentColor: Color {
        switch self {
        case .show(let row):
            return Color(hexString: row.brandColor, default: DS.sys)
        case .release:
            return DS.warning
        case .birthday(let idol):
            return Color(hexString: idol.color, default: .pink)
        case .personal(let event):
            return event.color
        case .ticket(let row):
            // 申込締切=赤(緊急) / 当落発表=藍。公演(ブランド色)・リリース(橙)・誕生日(桃)と被らない色域。
            return row.kind == .deadline ? DS.danger : .indigo
        case .ticketPeriod:
            // 受付期間の帯。チケット系の藍でまとめる。
            return .indigo
        }
    }

    /// accentColor の帯/チップの上に乗せる前景色。
    /// ブランド色・アイドル色は黄色 (#F5C900 系) や白系など明るい色が普通に存在するため、
    /// 白文字固定にせず WCAG コントラストで黒/白を自動選択する。
    var accentInk: Color {
        ColorMath.onColor(accentColor)
    }
}

// MARK: - 受付期間の連続帯 (週共有ロジック)

/// 週内に描く受付期間の帯 1 本ぶん。列インデックス + レーン (縦段) を持つ純粋なレイアウト値。
/// 月グリッドと週ビューで座標系・描画は異なるが、ここまでの算出は共通なので共有する。
struct CalendarPeriodBand: Identifiable {
    let id: String
    let entry: CalendarEntry
    let name: String
    let startCol: Int
    let endCol: Int
    let roundLeading: Bool   // 受付開始がこの週内 (左端を丸める)
    let roundTrailing: Bool  // 申込締切がこの週内 (右端を丸める)
    var lane: Int = 0
}

extension CalendarPeriodBand {
    /// この週 (weekDays) に重なる受付期間スパンを列範囲へ落とし込み、重ならないようレーン詰めする。
    /// 描画は呼び出し側 (月セル / 週レーン) に任せ、ここは列インデックスとレーン段組みだけを返す。
    static func pack(
        weekDays: [Date],
        entriesByDate: [Date: [CalendarEntry]],
        calendar: Calendar
    ) -> [CalendarPeriodBand] {
        guard let firstDay = weekDays.first else { return [] }
        let weekStart = calendar.startOfDay(for: firstDay)
        let weekEnd = calendar.startOfDay(for: weekDays.last ?? firstDay)

        var seen = Set<String>()
        var bands: [CalendarPeriodBand] = []
        for date in weekDays {
            for entry in entriesByDate[calendar.startOfDay(for: date)] ?? [] {
                guard case .ticketPeriod(let row) = entry, seen.insert(row.eventId).inserted else { continue }
                guard let start = AppDatabase.parseDate(row.start),
                      let end = AppDatabase.parseDate(row.end) else { continue }
                let startDay = calendar.startOfDay(for: start)
                let endDay = calendar.startOfDay(for: end)
                let startRaw = calendar.dateComponents([.day], from: weekStart, to: startDay).day ?? 0
                let endRaw = calendar.dateComponents([.day], from: weekStart, to: endDay).day ?? 0
                let startCol = min(max(startRaw, 0), 6)
                let endCol = min(max(endRaw, 0), 6)
                guard endRaw >= 0, startRaw <= 6, endCol >= startCol else { continue }
                bands.append(CalendarPeriodBand(
                    id: row.eventId, entry: entry, name: row.eventName,
                    startCol: startCol, endCol: endCol,
                    roundLeading: startDay >= weekStart, roundTrailing: endDay <= weekEnd
                ))
            }
        }

        // レーン詰め (貪欲): 各レーンの最終 endCol より後に始まる帯を同レーンへ。空きが無ければ新レーン。
        bands.sort { $0.startCol < $1.startCol }
        var laneEnds: [Int] = []
        for i in bands.indices {
            if let lane = laneEnds.indices.first(where: { laneEnds[$0] < bands[i].startCol }) {
                bands[i].lane = lane
                laneEnds[lane] = bands[i].endCol
            } else {
                bands[i].lane = laneEnds.count
                laneEnds.append(bands[i].endCol)
            }
        }
        return bands
    }

    /// 帯リストが占めるレーン数 (0 = 帯なし)。
    static func laneCount(of bands: [CalendarPeriodBand]) -> Int {
        (bands.map(\.lane).max() ?? -1) + 1
    }
}
