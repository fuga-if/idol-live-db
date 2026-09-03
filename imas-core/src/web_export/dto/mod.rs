//! Web 出面に配る JSON の serde 構造体。
//!
//! ここが **Rust ↔ TypeScript の唯一の境界**。`cargo test --features web-export` が
//! `web/src/lib/schema/*.ts` を再生成し、CI が `git diff --exit-code` で
//! ドリフトを落とす (型を 2 箇所に書かないための仕掛け)。
//!
//! 型は「そのまま描ける形」まで作り込む。TS 側で href を組んだり、日付を比べたり、
//! 色を計算したりしなくて済むようにしておくのが、この層の目的。

pub mod brand;
pub mod common;
pub mod event;
pub mod idol;
pub mod index;
pub mod search;
pub mod show;
pub mod song;
pub mod unit;
pub mod venue;

pub use brand::BrandPage;
pub use common::{
    mark_current, AppLinks, AppOpen, Counts, Crumb, NavLink, Ref, RefKind, Robots, SeoBlock, SiteMeta,
    StatTile, ThemePair, ThemeTable, ThemeTokens, SCHEMA_VERSION,
};
pub use event::{
    EventCast, EventCastMember, EventCastShow, EventPage, EventStats, ReleaseInfo, ShowSummary,
    TicketInfo,
};
pub use idol::{IdolPage, IdolPerformedRow, IdolShowRow, IdolSongRow, ProfileRow, VoiceActorRow};
pub use index::{
    AboutLink, AboutPage, AboutSection, BrandListItem, BrandListPage, EventListItem,
    EventListKind, EventListPage, HomePage, IdolListItem, IdolListKind, IdolListPage,
    KanaSection, RouteEntry, RouteKind, RoutesFile, SongListItem, SongListKind, SongListPage,
    UnitListItem, UnitListPage, VenueListItem, VenueListPage, YearGroup,
};
pub use search::{FoldCase, FoldParity, SearchManifest, SearchRow, SearchShard, SearchShardMeta};
pub use show::{PerformerRef, SetlistRow, ShowPage};
pub use song::{CoOccurRow, CreditGroup, PerformanceRow, SingerRow, SongPage};
pub use unit::UnitPage;
pub use venue::{HallRow, VenueNameRow, VenuePage};
