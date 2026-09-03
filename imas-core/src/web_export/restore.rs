//! `db/master.sql` (dump) から作業用の SQLite を作る。
//!
//! `tools/build_db.sh` に相当する処理を Rust で行う。build_db.sh を呼ばないのは、
//! あちらの出力先が `ImasLiveDB/Resources/master.sqlite` 固定でアプリ同梱物を上書き
//! してしまうため。Web の出力は Web の作業ディレクトリで完結させる。
//!
//! FK 整合のゲートは掛けない。`sqlite_loader` が FK 孤児を読み飛ばす契約になっており、
//! 「アプリに同梱してよいか」はアプリ側の関心事だから (build_db.sh 側で守られている)。
//! `data_version` のゲートも掛けない。reseed 判定はアプリ固有で、Web には無関係。

use super::{Result, WebExportError};
use std::path::Path;

/// dump を流し込んで `work_db` を作り直す。
pub fn restore(sql_path: &Path, work_db: &Path) -> Result<()> {
    let sql = std::fs::read_to_string(sql_path)?;
    if let Some(parent) = work_db.parent() {
        std::fs::create_dir_all(parent)?;
    }
    // 作り直す。前回の残骸に新しい dump を重ねると、消えた行が残る。
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{suffix}", work_db.display()));
    }
    let conn = rusqlite::Connection::open(work_db).map_err(|e| WebExportError::Db(e.to_string()))?;
    // dump は BEGIN TRANSACTION / COMMIT を含むので execute_batch がそのまま使える。
    conn.execute_batch(&sql).map_err(|e| WebExportError::Db(e.to_string()))?;
    conn.close().map_err(|(_, e)| WebExportError::Db(e.to_string()))?;
    Ok(())
}

/// dump の内容指紋。`shasum -a 256 db/master.sql` と同じ値。
///
/// `build_db.sh` が `meta.content_hash` に入れているのと**同じ規則**にしてある。
/// 版番号 (`data_version`) は人が管理する数字で内容とズレることがある (実際にズレて
/// 配信が止まった) ので、Web でも「内容が変われば必ず変わる」指紋の方を持っておく。
pub fn content_hash(sql_path: &Path) -> Result<String> {
    Ok(sha256_hex(&std::fs::read(sql_path)?))
}

// ---------------------------------------------------------------------------
// SHA-256
// ---------------------------------------------------------------------------
//
// crate を足さずに自前で持つ。用途は「内容が変われば必ず変わる指紋」だけで
// 暗号強度は要らないが、`shasum -a 256` と同じ値でないと build_db.sh が入れた
// 指紋と突き合わせられないので、規格どおりに実装してテストベクタで固定する。

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

/// SHA-256 (FIPS 180-4)。
pub fn sha256_hex(data: &[u8]) -> String {
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    /// SHA-256 のブロック長 (バイト)。
    const BLOCK: usize = 64;

    // パディング: 0x80 → 0 埋め → 元の長さ (bit) を 8 バイト big endian で。
    let mut padded = data.to_vec();
    let bit_len = (data.len() as u64).wrapping_mul(8);
    padded.push(0x80);
    while padded.len() % BLOCK != BLOCK - 8 {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());

    let mut w = [0u32; 64];
    // パディング済みなので端数は出ない。
    let (blocks, rest) = padded.as_chunks::<BLOCK>();
    debug_assert!(rest.is_empty());
    for chunk in blocks {
        let (words, _) = chunk.as_chunks::<4>();
        for (word, bytes) in w.iter_mut().zip(words) {
            *word = u32::from_be_bytes(*bytes);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let t1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        for (slot, value) in h.iter_mut().zip([a, b, c, d, e, f, g, hh]) {
            *slot = slot.wrapping_add(value);
        }
    }

    h.iter().map(|v| format!("{v:08x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_matches_the_published_test_vectors() {
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        // 56 バイト = パディングの境界 (ちょうど 1 ブロック追加になる長さ)。
        assert_eq!(
            sha256_hex(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
        // 複数ブロック。
        assert_eq!(
            sha256_hex(&b"a".repeat(1000)),
            "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"
        );
    }
}
