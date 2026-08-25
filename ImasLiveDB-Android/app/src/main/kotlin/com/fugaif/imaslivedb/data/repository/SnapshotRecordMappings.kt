package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.model.Brand
import uniffi.imas_core.BrandRecord

/**
 * 共有コア (imas-core) の射影 → Room エンティティの変換のうち、**複数のリポジトリで
 * 共有するもの**だけを置く。1 リポジトリでしか使わない変換は、対応の根拠 (どの SQL の
 * 置き換えか) が読める場所に近い方が良いので各リポジトリのファイル内に private で置く。
 */

/** BrandRecord → [Brand]。列は 1:1 (icon_url は Room 側に無いので落とす)。 */
internal fun BrandRecord.toBrand(): Brand = Brand(
    id = id,
    name = name,
    shortName = shortName,
    color = color,
    sortOrder = sortOrder.toInt()
)
