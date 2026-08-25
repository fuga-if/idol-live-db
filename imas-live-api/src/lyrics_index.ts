// lyrics_index.ts — 歌詞検索の転置インデックス (lyrics_gram_index) の増分更新。
//
// 全再構築は tools/lyrics/build_gram_index.py が担う。こちらは
// PUT /admin/lyrics/:song_id で 1 曲だけ直したときに索引を追従させる。
//
// なぜ増分でよいか:
//   1 曲あたりの gram は中央値 520 種類。D1 無料枠の書き込みは 10万行/日 なので
//   1 曲の追加は 0.5% ほどしか使わない (1日あたり約 185 曲入れられる)。
//   全再構築 (67,348行) を毎回やる必要はない。
//
// なぜ一括投入で破綻しないか:
//   差分なので、同じ歌詞を入れ直したときは追加も削除も 0 件になり書き込みが発生しない。
//   2,290 曲の再 push でも索引の書き込みはゼロ。初回の一括投入だけは差分が全件に
//   なって 120 万行に達するので、そこは全再構築ツールの担当。
//
// ⚠️ 索引がズレても検索は壊れない。routes/lyrics.ts が候補に対して body LIKE で
//    必ず検証するので、誤ヒットは出ず「出るはずの曲が出ない」側にしか倒れない。
//    だから索引更新の失敗で PUT 自体を失敗させない (呼び出し側で握り潰す)。

import type { Env } from "./env";

/** tools/lyrics/build_gram_index.py の MAX_POSTING_BYTES と同値にすること。 */
const MAX_POSTING_BYTES = 20_000;
/** D1 の 1 文あたりバインド変数上限に対する余裕を見た値。 */
const MAX_BOUND_PARAMS = 90;
/** 1 バッチにまとめる文の数。 */
const STATEMENTS_PER_BATCH = 100;

const encoder = new TextEncoder();
const byteLength = (text: string) => encoder.encode(text).length;

/**
 * 本文から 1-gram / 2-gram を取り出す。
 *
 * ⚠️ tools/lyrics/build_gram_index.py の build_index と同じ規則にすること。
 *    片方だけ変えると、増分更新と全再構築で索引の中身が食い違う。
 *    - 行 (\n) をまたぐ gram は作らない。並びとして連続していないため。
 *    - 正規化しない (素の部分文字列)。検索側も素のまま引く。
 */
export function extractGrams(body: string): Set<string> {
    const grams = new Set<string>();
    for (const line of body.split("\n")) {
        const chars = Array.from(line);
        for (let i = 0; i < chars.length; i++) {
            grams.add(chars[i]);
            if (i < chars.length - 1) grams.add(chars[i] + chars[i + 1]);
        }
    }
    return grams;
}

interface GramRow {
    gram: string;
    part: number;
    song_ids: string;
}

/**
 * 1 曲ぶんの索引を旧本文との差分で更新する。
 *
 * 本文が変わっていなければ 1 クエリも投げない (差分が空)。
 */
export async function updateGramIndex(
    env: Env,
    songId: string,
    oldBody: string,
    newBody: string
): Promise<void> {
    if (oldBody === newBody) return;

    const oldGrams = extractGrams(oldBody);
    const newGrams = extractGrams(newBody);
    const added = [...newGrams].filter((g) => !oldGrams.has(g));
    const removed = [...oldGrams].filter((g) => !newGrams.has(g));
    if (added.length === 0 && removed.length === 0) return;

    // 触る gram の現状をまとめて読む。バインド変数上限があるので分割して引く。
    const affected = [...new Set([...added, ...removed])];
    const rowsByGram = new Map<string, GramRow[]>();
    for (let i = 0; i < affected.length; i += MAX_BOUND_PARAMS) {
        const chunk = affected.slice(i, i + MAX_BOUND_PARAMS);
        const result = await env.DB.prepare(
            `SELECT gram, part, song_ids FROM lyrics_gram_index
              WHERE gram IN (${chunk.map(() => "?").join(",")})
              ORDER BY gram, part`
        )
            .bind(...chunk)
            .all<GramRow>();
        for (const row of result.results ?? []) {
            const list = rowsByGram.get(row.gram) ?? [];
            list.push(row);
            rowsByGram.set(row.gram, list);
        }
    }

    const statements: D1PreparedStatement[] = [];

    for (const gram of added) {
        const parts = rowsByGram.get(gram) ?? [];
        // 既にどこかの part に居るなら何もしない (同じ曲を二重に持たない)。
        if (parts.some((p) => p.song_ids.split("\n").includes(songId))) continue;

        // 末尾の part に空きがあれば足す。無ければ新しい part を作る。
        // 先頭から詰め直さないのは、他の part を書き換えると書き込み行が増えるため。
        const last = parts[parts.length - 1];
        if (last && byteLength(last.song_ids) + byteLength(songId) + 1 <= MAX_POSTING_BYTES) {
            statements.push(
                env.DB.prepare(
                    `UPDATE lyrics_gram_index SET song_ids = song_ids || char(10) || ?
                      WHERE gram = ? AND part = ?`
                ).bind(songId, gram, last.part)
            );
        } else {
            statements.push(
                env.DB.prepare(
                    `INSERT INTO lyrics_gram_index (gram, part, song_ids) VALUES (?, ?, ?)
                     ON CONFLICT(gram, part) DO UPDATE SET
                       song_ids = lyrics_gram_index.song_ids || char(10) || excluded.song_ids`
                ).bind(gram, last ? last.part + 1 : 0, songId)
            );
        }
    }

    for (const gram of removed) {
        for (const row of rowsByGram.get(gram) ?? []) {
            const ids = row.song_ids.split("\n");
            if (!ids.includes(songId)) continue;
            const rest = ids.filter((id) => id !== songId);
            statements.push(
                rest.length === 0
                    // part が空になったら行ごと消す。空文字の行を残すと
                    // 検索側が「gram は存在する」と判断して候補が空になる。
                    ? env.DB.prepare(
                        `DELETE FROM lyrics_gram_index WHERE gram = ? AND part = ?`
                      ).bind(gram, row.part)
                    : env.DB.prepare(
                        `UPDATE lyrics_gram_index SET song_ids = ? WHERE gram = ? AND part = ?`
                      ).bind(rest.join("\n"), gram, row.part)
            );
        }
    }

    for (let i = 0; i < statements.length; i += STATEMENTS_PER_BATCH) {
        await env.DB.batch(statements.slice(i, i + STATEMENTS_PER_BATCH));
    }
}
