//! 再生中バー (ミニプレイヤー) に何を出すか。
//!
//! # 何がここの持ち物か
//!
//! 音を鳴らすのは OS SDK (iOS は `AVPlayer` / `ApplicationMusicPlayer`) なので各 OS。
//! **鳴っているものをどう見せるかの判断はここ** — バーを出すのか、題と名義に何を置くのか、
//! 試聴とフル尺をどう書き分けるのか。iOS と Android で別々に書くと、
//! `color_match.rs` 冒頭に残っている二重管理の事故を繰り返す。
//!
//! # 曲名では引き当てない
//!
//! 入口を `song_id` にしてあるのは、**同名で別録音の曲が実在する**ため。
//! 「私はアイドル♡ (M@STER VERSION)」は歌唱者の違う 2 録音があり、
//! 曲名で突き合わせると別バージョンのジャケと名義が出る。
//! iOS の `MusicKitService` は長らく `nowPlayingTitle: String?` で同一性を見ていた。
//!
//! # 材料集めもここでやる
//!
//! 曲と原唱者は snapshot にあるので、OS 側に 2 回引かせて詰め替えさせる必要が無い。
//! `song_id` を 1 つ渡せば 1 枚返る形にしておくと、**1 操作 = 1 FFI 呼び出し**
//! (docs/ARCHITECTURE.md) が守れて、Android 移植でも同じ手組みを書き直さずに済む。

use crate::domain::performer_label::{performer_label, PerformerNaming};
use crate::domain::snapshot::Snapshot;

/// 鳴らし方。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum NowPlayingKind {
    /// 30 秒試聴 (`songs.preview_url`)。**勝手に終わる**ので、その旨を出す。
    /// 黙って止まると「なぜか止まった」に見える。
    Preview,
    /// フル尺 (Apple Music のカタログ再生)。最後まで鳴る。
    Full,
}

/// バーに出す 1 枚ぶん。これをそのまま描く。
///
/// OS 側に `if` を持たせないため、**出す文字はすべてここで確定させる**。
/// 出さないものは `None` で返す ([`crate::domain::display_join::join_parts`] と同じ約束)
/// ので、OS 側は「空文字かどうか」を判定しなくてよい。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct NowPlayingBar {
    /// タップしたときに開く曲。
    pub song_id: String,
    /// 1 行目。
    pub title: String,
    /// 2 行目の名義。出せるものが無ければ `None`。
    pub subtitle: Option<String>,
    /// 試聴中に名義へ添える印。フル尺なら `None`。
    ///
    /// 名義と繋げた 1 本の文字列にしないのは、2 行目が 1 行に収まらないとき
    /// **末尾のこれだけが真っ先に消える**から。伝えたいのは「30 秒で終わる」の方なので、
    /// OS 側が別の `Text` として優先度を付けられるように分けて返す。
    pub preview_mark: Option<String>,
    pub artwork_url: Option<String>,
    /// 再生ボタンの向き。false なら「再生」、true なら「一時停止」を出す。
    pub is_playing: bool,
}

/// 試聴中であることを示す語。
const PREVIEW_MARK: &str = "試聴";

/// バーに出す内容。鳴らす曲を知らなければ `None` = バーごと出さない。
///
/// 「止めたら消す」ではなく **「鳴らすものが無ければ消す」**。一時停止では
/// `song_id` が残るのでバーも残り、再生ボタンだけが向きを変える (Apple Music と同じ)。
pub fn now_playing_bar(
    snap: &Snapshot,
    song_id: &str,
    kind: NowPlayingKind,
    is_playing: bool,
) -> Option<NowPlayingBar> {
    let song = snap.song(song_id)?;
    let performer_names = snap
        .song_artists(song_id, Some("original"))
        .iter()
        .map(|i| i.name.clone())
        .collect();
    Some(compose_bar(
        &song.id,
        &song.title,
        &PerformerNaming {
            unit_name: song.unit_name.clone(),
            singer_label: song.singer_label.clone(),
            performer_names,
        },
        song.artwork_url.as_deref(),
        kind,
        is_playing,
    ))
}

/// 材料が揃ったあとの組み立て。snapshot に触らないので、判断だけを試せる。
fn compose_bar(
    song_id: &str,
    title: &str,
    naming: &PerformerNaming,
    artwork_url: Option<&str>,
    kind: NowPlayingKind,
    is_playing: bool,
) -> NowPlayingBar {
    NowPlayingBar {
        song_id: song_id.to_string(),
        title: title.to_string(),
        subtitle: performer_label(naming),
        preview_mark: (kind == NowPlayingKind::Preview).then(|| PREVIEW_MARK.to_string()),
        // 空文字の URL を掴ませると、OS 側に壊れた画像枠が出る。
        artwork_url: artwork_url
            .map(str::trim)
            .filter(|u| !u.is_empty())
            .map(str::to_string),
        is_playing,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn naming(unit: Option<&str>, performers: &[&str]) -> PerformerNaming {
        PerformerNaming {
            unit_name: unit.map(str::to_string),
            singer_label: None,
            performer_names: performers.iter().map(|s| s.to_string()).collect(),
        }
    }

    fn bar(kind: NowPlayingKind, is_playing: bool) -> NowPlayingBar {
        compose_bar(
            "sc_take_ur_time",
            "Take Ur Time",
            &naming(None, &["八宮めぐる"]),
            Some("https://example.invalid/600x600bb.jpg"),
            kind,
            is_playing,
        )
    }

    /// 試聴は黙って終わるので、必ず印が付く。
    #[test]
    fn preview_carries_a_mark() {
        let b = bar(NowPlayingKind::Preview, true);
        assert_eq!(b.subtitle.as_deref(), Some("八宮めぐる"));
        assert_eq!(b.preview_mark.as_deref(), Some("試聴"));
    }

    /// 名義が無い曲でも印だけは出る。名義と繋いでいないので区切りが浮かない。
    #[test]
    fn preview_without_naming_still_marks() {
        let b = compose_bar(
            "x",
            "名義なしの曲",
            &naming(None, &[]),
            None,
            NowPlayingKind::Preview,
            true,
        );
        assert_eq!(b.subtitle, None);
        assert_eq!(b.preview_mark.as_deref(), Some("試聴"));
    }

    /// 空のジャケ URL はキーごと無かったことにする。
    #[test]
    fn blank_artwork_url_becomes_none() {
        let b = compose_bar(
            "x",
            "曲",
            &naming(None, &["八宮めぐる"]),
            Some("   "),
            NowPlayingKind::Full,
            true,
        );
        assert!(b.artwork_url.is_none());
    }

    /// 知らない曲 id を渡してもバーは出ない (曲を消した直後など)。
    #[test]
    fn unknown_song_yields_no_bar() {
        let snap = crate::test_support::bundle_snapshot();
        assert!(now_playing_bar(snap, "no_such_song", NowPlayingKind::Full, true).is_none());
    }

    /// 実データで、原唱者しか無い曲でも名義が出ること。
    #[test]
    fn real_song_resolves_naming() {
        let snap = crate::test_support::bundle_snapshot();
        let b = now_playing_bar(snap, "sc_take_ur_time", NowPlayingKind::Preview, true)
            .expect("実データに在る曲");
        assert_eq!(b.title, "Take Ur Time");
        assert_eq!(b.subtitle.as_deref(), Some("八宮めぐる"));
        assert_eq!(b.preview_mark.as_deref(), Some("試聴"));
    }
}
