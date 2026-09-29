//  公演のチケット価格の読み書き。マスタ表なので基本は読むだけで、
//  書き込みは同期 (CloudKit) 経由。
//
//  どの券を選ぶか・価格帯をどう出すかの判断は共有コア (domain/ticket_prices.rs)。

import Foundation
import GRDB

extension AppDatabase {

    func showTicketsAsync(showId: String) async throws -> [ShowTicketRecord] {
        try await dbQueue.read { db in
            try ShowTicketRecord
                .filter(ShowTicketRecord.Columns.showId == showId)
                .fetchAll(db)
        }
    }

}
