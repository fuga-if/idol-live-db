//! ver 違いの一族 (原曲と、`parent_song_id` でそこにぶら下がる曲)。
//!
//! 回収は原曲単位で数える (2026-11-24): 一族のどれか 1 曲を生で聴いていれば原曲を回収済みにする。
//! 回収ダッシュボード・曲一覧の回収の絞り込みと回収バッジ・曲詳細の「現地回収」が、同じ一族の
//! 区切りを使うためにここに置く。
//!
//! ver 違いの曲そのものの回収は、その曲を聴いたかどうか (曲ごと) のまま。原曲の行だけが一族を代表する。

use std::collections::HashMap;

use crate::domain::snapshot::Snapshot;

/// `parent_song_id` を遡る上限 (今のデータは 1 段だけ。壊れて輪になっていても止まる)。
const MAX_VARIANT_DEPTH: usize = 8;

/// 曲の一族の表 (songs と同じ添字)。
pub(crate) struct SongFamilies {
    /// その曲の根 (原曲)。根なら自分。
    pub root_of: Vec<u32>,
    /// 根 → 根以外の一族 (songs の添字順)。ver 違いの無い根は載らない。
    pub variants: HashMap<u32, Vec<u32>>,
}

impl SongFamilies {
    pub fn new(snap: &Snapshot) -> Self {
        let root_of: Vec<u32> = (0..snap.songs.len() as u32).map(|song| family_root(snap, song)).collect();
        let mut variants: HashMap<u32, Vec<u32>> = HashMap::new();
        for (song, &root) in root_of.iter().enumerate() {
            if root as usize != song {
                variants.entry(root).or_default().push(song as u32);
            }
        }
        Self { root_of, variants }
    }

    pub fn is_root(&self, song: u32) -> bool {
        self.root_of[song as usize] == song
    }

    /// 根なら一族 (根 + ver 違い)、ver 違いなら自分だけ。原曲の行が一族を代表し、ver 違いの行は
    /// その曲だけを見る、という数え方の単位。
    pub fn counted_members(&self, song: u32) -> Vec<u32> {
        let mut members = vec![song];
        if self.is_root(song) {
            members.extend(self.variants.get(&song).into_iter().flatten().copied());
        }
        members
    }

    /// 回収済みの曲 (聴いた曲) に、それを含む一族の原曲を足した集合 (songs の添字順、重複なし)。
    /// 未知の id は落とす。
    pub fn with_roots(&self, snap: &Snapshot, collected_song_ids: &[String]) -> Vec<u32> {
        let mut hit = vec![false; snap.songs.len()];
        for id in collected_song_ids {
            if let Some(&song) = snap.song_index_by_id.get(id) {
                hit[song as usize] = true;
                hit[self.root_of[song as usize] as usize] = true;
            }
        }
        (0..hit.len() as u32).filter(|&song| hit[song as usize]).collect()
    }
}

/// ver 違いの一族の根: `parent_song_id` を辿れるだけ辿る (空文字・未知の id は親無しと同じ)。
/// 辿り着いた先が根でない (親が輪になっている・深すぎる壊れたデータ) ときは自分を根にする
/// (数えから落ちないように)。
pub(crate) fn family_root(snap: &Snapshot, song: u32) -> u32 {
    let root = walk_to_root(snap, song);
    if walk_to_root(snap, root) == root {
        root
    } else {
        song
    }
}

fn walk_to_root(snap: &Snapshot, song: u32) -> u32 {
    let mut root = song;
    for _ in 0..MAX_VARIANT_DEPTH {
        let parent = snap.songs[root as usize]
            .parent_song_id
            .as_deref()
            .filter(|id| !id.is_empty())
            .and_then(|id| snap.song_index_by_id.get(id).copied());
        match parent {
            Some(parent) if parent != root => root = parent,
            _ => break,
        }
    }
    root
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    #[test]
    fn roots_are_their_own_root_and_variants_point_at_them() {
        let snap = bundle_snapshot();
        let f = SongFamilies::new(snap);
        assert!(!f.variants.is_empty());
        for (&root, variants) in &f.variants {
            assert!(f.is_root(root));
            for &v in variants {
                assert_eq!(f.root_of[v as usize], root);
                assert!(!f.is_root(v));
                assert_eq!(f.counted_members(v), vec![v], "ver 違いの行はその曲だけ");
            }
            assert_eq!(f.counted_members(root).len(), variants.len() + 1);
        }
    }

    #[test]
    fn hearing_a_variant_adds_its_original_song() {
        let snap = bundle_snapshot();
        let f = SongFamilies::new(snap);
        let (&root, variants) = f.variants.iter().next().unwrap();
        let v = variants[0];
        let ids = [snap.songs[v as usize].id.clone(), "存在しない".into()];
        let mut expected = vec![root, v];
        expected.sort();
        assert_eq!(f.with_roots(snap, &ids), expected);
    }
}
