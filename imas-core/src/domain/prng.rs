//! シード注入型の決定論 PRNG (SplitMix64)。
//!
//! 乱数を使う UseCase (出題生成・重み付き抽選) はこれをシード付きで使う。
//! OS の RNG に依存しないので、同じシードなら iOS / Android / テストで同じ列になる。
//! シード (現在時刻等) の調達は各プラットフォームのラッパが担う。

pub struct SplitMix64(pub u64);

impl SplitMix64 {
    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E3779B97F4A7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
        z ^ (z >> 31)
    }

    /// `0..bound` の一様乱数 (bound=0 は 0)。剰余バイアスは用途上無視できる規模。
    pub fn next_below(&mut self, bound: u64) -> u64 {
        if bound == 0 { 0 } else { self.next_u64() % bound }
    }

    /// Fisher–Yates シャッフル。
    pub fn shuffle<T>(&mut self, items: &mut [T]) {
        for i in (1..items.len()).rev() {
            items.swap(i, self.next_below(i as u64 + 1) as usize);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic_for_same_seed() {
        let (mut a, mut b) = (SplitMix64(42), SplitMix64(42));
        for _ in 0..8 {
            assert_eq!(a.next_u64(), b.next_u64());
        }
    }

    #[test]
    fn shuffle_is_permutation() {
        let mut v: Vec<u32> = (0..50).collect();
        SplitMix64(7).shuffle(&mut v);
        let mut sorted = v.clone();
        sorted.sort();
        assert_eq!(sorted, (0..50).collect::<Vec<_>>());
    }
}
