package com.fugaif.imaslivedb.data.model

import kotlin.math.pow
import kotlin.random.Random

/**
 * 重み付きのランダム抽出 (非復元)。iOS の `WeightedSampling` と 1:1。
 *
 * 「タグが似ている曲」のおすすめで使う。サーバは候補を近い順に返すだけで、
 * そこから実際に見せるものは毎回ここで引き直す。上位固定にしないのは、
 * - 同じ曲を開くたびに同じ並びだと発見がない
 * - 少しだけ被っている曲もたまには顔を出してほしい
 * という理由。重みが大きいほど選ばれやすいので、近い曲が中心に出つつ
 * 遠い曲もときどき混ざる。
 */
object WeightedSampling {

    /**
     * 重みに比例した確率で [count] 件を非復元抽出する。
     *
     * Efraimidis–Spirakis 法: 各要素に `U^(1/w)` の鍵を振り、大きい順に取る。
     * 1 パスで「重み付き非復元抽出」になり、結果の並びもそのまま重み付きの
     * ランダム順になる (先頭ほど重い要素が来やすい)。
     *
     * - 重みが 0 以下の要素は、候補が足りないときの穴埋めとしてのみ使う。
     * - [count] が候補数以上なら全件を (ランダム順で) 返す。
     *
     * @param random テストから固定乱数を差せるようにするための乱数源。
     */
    fun <T> pick(
        items: List<T>,
        count: Int,
        random: Random = Random.Default,
        weight: (T) -> Double
    ): List<T> {
        if (count <= 0) return emptyList()
        return items
            .map { item ->
                val w = weight(item)
                // u は (0, 1]。0 を避けるのは pow(0, x) で鍵が潰れるのを防ぐため。
                val key = if (w > 0) (1.0 - random.nextDouble()).pow(1.0 / w) else 0.0
                item to key
            }
            .sortedByDescending { it.second }
            .take(count)
            .map { it.first }
    }
}
