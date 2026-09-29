package com.fugaif.imaslivedb.data.model

import kotlin.random.Random
import uniffi.imas_core.weightedSampleIndices

/**
 * 重み付きのランダム抽出 (非復元)。
 *
 * 抽選本体は imas-core (Rust) の `domain/weighted_sampling.rs` にあり、iOS の
 * `WeightedSampling` と同じ実装 (Efraimidis–Spirakis 法) を共有する。
 * なぜ上位固定にしないか・重み 0 の扱いなどの設計意図もそちらに記載。
 *
 * ここが担うのは「シードの調達」と「index 列 → Kotlin リストの解決」だけ。
 * - 実行時は [Random.Default] からシードを引く (毎回顔ぶれが変わる)。
 * - テストは固定シードの [Random] を差して決定論にする。
 * 重みの射影と index 列だけを FFI に通すので、候補件数によらず 1 呼び出しで済む。
 */
object WeightedSampling {

    /**
     * 重みに比例した確率で [count] 件を非復元抽出する。
     *
     * @param random シード調達源。テストから固定乱数を差せるようにするための注入点。
     */
    fun <T> pick(
        items: List<T>,
        count: Int,
        random: Random = Random.Default,
        weight: (T) -> Double
    ): List<T> {
        val indices = weightedSampleIndices(
            items.map(weight),
            // 負の count は 0 (空) に丸める。境界の型合わせのみで判定はしない。
            count.coerceAtLeast(0).toUInt(),
            random.nextLong().toULong(),
        )
        return indices.map { items[it.toInt()] }
    }
}
