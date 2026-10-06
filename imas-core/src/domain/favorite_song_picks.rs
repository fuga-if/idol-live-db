//! お気に入りの曲から「載せる曲」を選ぶ規則 (プロフィール帳の好きな曲。P名刺からも同じ部品で呼ぶ)。
//!
//! お気に入りは何百曲にもなるので、載せるのは本人が選んだ数曲 ([`MAX_PICKED_SONGS`] まで)。
//! - 選んだ曲は選んだ順に並び、並べ替え・外すができる。保存は曲 id の並び。
//! - まだ選んでいない (`chosen = None`) ときは、お気に入りに付けた新しい順の先頭から上限まで。
//! - お気に入りから外された曲・引けない曲は、選んでいても自動で抜ける (重複も 1 つに)。
//! - 選んでから全部外した (`Some([])`) ときは何も載せない (勝手に既定へ戻さない)。
//!
//! 端末は候補を並べて、打った語で絞り (`TextSearchCatalog`)、押した曲 id をここへ渡すだけにする。

use std::collections::HashSet;

/// 載せる曲の上限 (志望の動機の欄いっぱいに)。
pub const MAX_PICKED_SONGS: usize = 5;

/// お気に入りの曲 1 つ (端末がマスタとマークから引いて渡す)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSongInput {
    pub id: String,
    pub title: String,
    /// お気に入りに付けた時刻 (ISO 8601。並びと既定の選び方に使う。分からなければ空)。
    pub favorited_at: String,
}

/// 選ぶ画面に並べるもの。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct FavoriteSongPicks {
    /// 載せる曲 (載せる順)。
    pub picked: Vec<ProfileSongInput>,
    /// 本人が選んだか (false はまだ選んでいなくて、新しい順の先頭が入っている)。
    pub chosen_by_hand: bool,
    /// お気に入りの曲すべて (付けた新しい順)。
    pub favorites: Vec<ProfileSongInput>,
    /// 上限。
    pub max: u32,
    /// 上限まで選んだか (選んでいない曲は足せない)。
    pub full: bool,
}

/// お気に入りを付けた新しい順に並べ直す (同時刻は id の順。同じ id は 1 つに)。
fn newest_first(favorites: &[ProfileSongInput]) -> Vec<ProfileSongInput> {
    let mut seen = HashSet::new();
    let mut out: Vec<ProfileSongInput> = favorites
        .iter()
        .filter(|s| seen.insert(s.id.as_str()))
        .cloned()
        .collect();
    out.sort_by(|a, b| {
        b.favorited_at
            .cmp(&a.favorited_at)
            .then_with(|| a.id.cmp(&b.id))
    });
    out
}

/// 選んだ曲 id を、お気に入りに今ある曲だけ・重複なし・上限までに整える。
pub fn favorite_song_normalize(ids: &[String], favorites: &[ProfileSongInput]) -> Vec<String> {
    let known: HashSet<&str> = favorites.iter().map(|s| s.id.as_str()).collect();
    let mut seen = HashSet::new();
    ids.iter()
        .filter(|id| known.contains(id.as_str()) && seen.insert(id.as_str()))
        .take(MAX_PICKED_SONGS)
        .cloned()
        .collect()
}

/// 載せる曲 id (載せる順)。まだ選んでいなければお気に入りの新しい順の先頭から。
pub fn favorite_song_picked_ids(
    chosen: Option<&[String]>,
    favorites: &[ProfileSongInput],
) -> Vec<String> {
    match chosen {
        Some(ids) => favorite_song_normalize(ids, favorites),
        None => newest_first(favorites)
            .into_iter()
            .take(MAX_PICKED_SONGS)
            .map(|s| s.id)
            .collect(),
    }
}

/// 載せる曲 (載せる順)。
pub fn favorite_song_picked(
    chosen: Option<&[String]>,
    favorites: &[ProfileSongInput],
) -> Vec<ProfileSongInput> {
    favorite_song_picked_ids(chosen, favorites)
        .into_iter()
        .filter_map(|id| favorites.iter().find(|s| s.id == id).cloned())
        .collect()
}

/// 選ぶ画面に並べるもの。
pub fn favorite_song_picks(
    chosen: Option<&[String]>,
    favorites: &[ProfileSongInput],
) -> FavoriteSongPicks {
    let picked = favorite_song_picked(chosen, favorites);
    FavoriteSongPicks {
        full: picked.len() >= MAX_PICKED_SONGS,
        chosen_by_hand: chosen.is_some(),
        favorites: newest_first(favorites),
        max: MAX_PICKED_SONGS as u32,
        picked,
    }
}

/// 1 曲を載せる / 外す。載っていなければ末尾に足し (上限なら変えない)、載っていれば外す。
/// まだ選んでいなければ、今載っている既定の並びから始める。
pub fn favorite_song_toggle(
    chosen: Option<&[String]>,
    favorites: &[ProfileSongInput],
    song_id: &str,
) -> Vec<String> {
    let mut ids = favorite_song_picked_ids(chosen, favorites);
    if let Some(i) = ids.iter().position(|id| id == song_id) {
        ids.remove(i);
    } else if ids.len() < MAX_PICKED_SONGS && favorites.iter().any(|s| s.id == song_id) {
        ids.push(song_id.to_string());
    }
    ids
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(id: &str, at: &str) -> ProfileSongInput {
        ProfileSongInput {
            id: id.into(),
            title: format!("曲{id}"),
            favorited_at: at.into(),
        }
    }

    fn favorites() -> Vec<ProfileSongInput> {
        vec![
            song("a", "2026-01-01T00:00:00Z"),
            song("b", "2026-03-01T00:00:00Z"),
            song("c", "2026-02-01T00:00:00Z"),
            song("d", "2026-05-01T00:00:00Z"),
            song("e", "2026-04-01T00:00:00Z"),
            song("f", "2026-06-01T00:00:00Z"),
            song("f", "2026-06-01T00:00:00Z"),
        ]
    }

    fn ids(v: &[ProfileSongInput]) -> Vec<&str> {
        v.iter().map(|s| s.id.as_str()).collect()
    }

    fn owned(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn unchosen_takes_the_newest_favorites() {
        let picks = favorite_song_picks(None, &favorites());
        assert_eq!(ids(&picks.picked), vec!["f", "d", "e", "b", "c"]);
        assert!(!picks.chosen_by_hand);
        assert!(picks.full);
        assert_eq!(ids(&picks.favorites), vec!["f", "d", "e", "b", "c", "a"]);
        assert_eq!(picks.max, 5);
        assert!(favorite_song_picks(None, &[]).picked.is_empty());
    }

    #[test]
    fn chosen_keeps_order_and_drops_unfavorited_songs() {
        let chosen = owned(&["a", "gone", "c", "a"]);
        let picks = favorite_song_picks(Some(&chosen), &favorites());
        assert_eq!(
            ids(&picks.picked),
            vec!["a", "c"],
            "お気に入りから外れた曲・重複は抜ける"
        );
        assert!(picks.chosen_by_hand && !picks.full);
        // 全部外したら何も載せない (既定に戻さない)。
        assert!(favorite_song_picks(Some(&[]), &favorites())
            .picked
            .is_empty());
    }

    #[test]
    fn toggle_adds_to_the_end_up_to_the_cap_and_removes() {
        let favs = favorites();
        // 選んでいなければ既定の並びから外す。
        assert_eq!(
            favorite_song_toggle(None, &favs, "d"),
            owned(&["f", "e", "b", "c"])
        );
        // 上限なら足さない。
        assert_eq!(
            favorite_song_toggle(None, &favs, "a"),
            owned(&["f", "d", "e", "b", "c"])
        );
        let two = owned(&["c", "a"]);
        assert_eq!(
            favorite_song_toggle(Some(&two), &favs, "f"),
            owned(&["c", "a", "f"])
        );
        assert_eq!(favorite_song_toggle(Some(&two), &favs, "c"), owned(&["a"]));
        // お気に入りに無い曲は足さない。
        assert_eq!(favorite_song_toggle(Some(&two), &favs, "zz"), two);
    }

    #[test]
    fn normalize_caps_and_dedups() {
        let raw = owned(&["a", "b", "b", "c", "d", "e", "f"]);
        assert_eq!(
            favorite_song_normalize(&raw, &favorites()),
            owned(&["a", "b", "c", "d", "e"])
        );
    }
}
