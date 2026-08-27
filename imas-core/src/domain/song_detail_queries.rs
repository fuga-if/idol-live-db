//! 曲詳細まわりのスナップショットクエリ (純粋ロジック)。
//!
//! SQL 時代の対応 (iOS AppDatabase+SongQueries.swift):
//! - [`song_records_by_ids`]          ← fetchSongs(ids:) / fetchSong(id:)
//! - [`search_songs`]                ← searchSongsAsync(query:limit:)
//! - [`related_songs`]               ← fetchRelatedSongsAsync(to:limit:)
//! - [`songs_by_creator`]            ← fetchSongsByCreatorAsync(_:)
//! - [`all_songs_for_picker`]        ← fetchAllSongsForPickerAsync()
//! - [`listable_song_records_by_ids`] ← fetchListableSongsAsync(ids:)
//! - [`performer_idol_ids_map`]       ← fetchSongPerformerIdolsMap(songIds:)
//! - [`performance_history`]          ← fetchSongPerformanceHistoryAsync(songId:)
//! - [`album_summaries`]              ← fetchAlbumsAsync(brandIds:query:)
//! - [`series_summaries`]             ← fetchSeriesAsync(brandIds:query:)
//! - [`series_group_names`]           ← fetchSeriesGroupsAsync(brandIds:)
//! - [`variant_song_records`]         ← fetchVariantSongsAsync(of:)
//!
//! SQL の暗黙挙動はここで明示コードに固定する (等価性はテストの照合で保証):
//! - `IN (...)` の結果順は SQL では未規定 → 入力 id 順・重複 id は 1 回、で決定化。
//! - `ORDER BY ... DESC` の NULL は SQLite では末尾 / `ASC` は先頭 → Option の
//!   Ord (None < Some) と Reverse で同じ位置に置く。
//! - 集計 (MIN/MAX/COUNT DISTINCT) は NULL を無視するが空文字 '' は値として扱う。
//! - `LIKE '%q%'` は ASCII のみ大文字小文字を無視 (SQLite の既定) → ASCII だけ
//!   小文字化してから部分一致。
//! - SQL が未規定だった同順位の並びは添字や名前で決定化する (プラットフォーム間で
//!   同一結果を返すのが共有コアの目的なので、非決定性は残さない)。

use crate::domain::snapshot::{Snapshot, Song};
use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};

// =============================================================================
// FFI 射影 Record (uniffi は型 derive のみ / ロジックはこのファイルの関数側)
// =============================================================================

/// songs 1 行の射影。詳細画面・派生曲一覧は行の全カラムを使うため全域射影になる
/// (GRDB `Song` / Room Entity と同じ「Record = Entity 兼用」の現実的判断)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongDetailRecord {
    pub id: String,
    pub title: String,
    pub title_kana: Option<String>,
    pub brand_id: Option<String>,
    pub song_type: Option<String>,
    pub release_date: Option<String>,
    pub duration_sec: Option<i64>,
    pub composer: Option<String>,
    pub lyricist: Option<String>,
    pub arranger: Option<String>,
    pub cd_series: Option<String>,
    pub cd_title: Option<String>,
    pub artwork_url: Option<String>,
    pub preview_url: Option<String>,
    pub apple_music_id: Option<String>,
    pub apple_music_album_id: Option<String>,
    pub isrc: Option<String>,
    pub lyrics_url: Option<String>,
    pub parent_song_id: Option<String>,
    pub singer_label: Option<String>,
    pub unit_name: Option<String>,
    pub unit_id: Option<String>,
    pub series_group: Option<String>,
    pub jasrac_code: Option<String>,
}

impl From<&Song> for SongDetailRecord {
    fn from(s: &Song) -> Self {
        Self {
            id: s.id.clone(),
            title: s.title.clone(),
            title_kana: s.title_kana.clone(),
            brand_id: s.brand_id.clone(),
            song_type: s.song_type.clone(),
            release_date: s.release_date.clone(),
            duration_sec: s.duration_sec,
            composer: s.composer.clone(),
            lyricist: s.lyricist.clone(),
            arranger: s.arranger.clone(),
            cd_series: s.cd_series.clone(),
            cd_title: s.cd_title.clone(),
            artwork_url: s.artwork_url.clone(),
            preview_url: s.preview_url.clone(),
            apple_music_id: s.apple_music_id.clone(),
            apple_music_album_id: s.apple_music_album_id.clone(),
            isrc: s.isrc.clone(),
            lyrics_url: s.lyrics_url.clone(),
            parent_song_id: s.parent_song_id.clone(),
            singer_label: s.singer_label.clone(),
            unit_name: s.unit_name.clone(),
            unit_id: s.unit_id.clone(),
            series_group: s.series_group.clone(),
            jasrac_code: s.jasrac_code.clone(),
        }
    }
}

/// 披露履歴 1 行 (iOS `PerformanceHistoryRow` / setlist_items × shows × events)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PerformanceHistoryEntry {
    pub show_id: String,
    pub event_id: String,
    pub event_name: String,
    pub show_name: String,
    /// YYYY-MM-DD (shows.date)。
    pub date: String,
    pub venue: Option<String>,
    pub position: i64,
    pub section: Option<String>,
}

/// CD シリーズ別アルバム集計 1 行 (iOS `AlbumSummary`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct AlbumSummaryRecord {
    pub cd_series: String,
    /// 代表ジャケット。SQL の MIN(artwork_url) = URL 文字列のバイト列最小 (NULL は無視)。
    pub artwork_url: Option<String>,
    pub song_count: u32,
    pub earliest_date: Option<String>,
    pub latest_date: Option<String>,
    /// 含まれる曲のブランド id (重複なし・出現順)。SQL の GROUP_CONCAT(DISTINCT) を
    /// Swift 側で split → 空要素除去していた最終形に合わせ、NULL と '' は含めない。
    pub brand_ids: Vec<String>,
}

/// CD シリーズグループ (series_group) 集計 1 行 (iOS `SeriesSummary`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SeriesSummaryRecord {
    pub name: String,
    pub song_count: u32,
    /// グループ内の cd_series 異なり数 (COUNT(DISTINCT)。NULL は数えず '' は数える)。
    pub cd_count: u32,
    pub earliest_date: Option<String>,
    pub latest_date: Option<String>,
    /// 代表ジャケット (最古リリース曲のもの)。元 SQL の相関サブクエリはブランド絞り込みの
    /// 影響を受けない仕様だったので、ここも全曲から選ぶ。
    pub artwork_url: Option<String>,
    pub brand_ids: Vec<String>,
}

/// 編集 UI の曲ピッカー 1 行 (iOS `PickedSong`)。
///
/// 全曲を運ぶので、行の描画と選択に要る id + title だけの軽量射影にする
/// (`SongDetailRecord` を全曲ぶん FFI 越しに渡すのは無駄が大きい)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PickedSongRecord {
    pub id: String,
    pub title: String,
}

/// クリエイター絞り込みの 1 行 (iOS `SongWithRoles`)。
///
/// iOS 版は `artists: [Idol]` も持つが常に空配列で埋められており、表示は
/// `song.singerLabel` を見ている。運ぶ意味が無いので FFI には載せない
/// (Android の移植版も持っていない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongWithRolesRecord {
    pub song: SongDetailRecord,
    /// その曲でその人が担った役割ラベル。並びは 作曲 → 作詞 → 編曲 で固定。
    pub roles: Vec<String>,
}

// =============================================================================
// クエリ関数 (Snapshot を引数に取る純粋関数)
// =============================================================================

/// 曲 id 群の一括取得 (fetchSongs(ids:) / N+1 防止用)。
///
/// SQL の `IN` は結果順未規定・重複 id も 1 行だったので、「入力 id 順・初出のみ・
/// 未知 id は読み飛ばし」で決定化する (呼び出し側は id で引き直す用途なので順序に
/// 意味はないが、非決定性を残さない)。
pub fn song_records_by_ids(snap: &Snapshot, song_ids: &[String]) -> Vec<SongDetailRecord> {
    let mut seen: HashSet<u32> = HashSet::new();
    song_ids
        .iter()
        .filter_map(|id| snap.song_index_by_id.get(id).copied())
        .filter(|&i| seen.insert(i))
        .map(|i| SongDetailRecord::from(&snap.songs[i as usize]))
        .collect()
}

/// 曲名検索 (検索画面のスコープ「曲」)。iOS `AppDatabase.searchSongsQuery` 相当。
///
/// 原本 Swift はこの 2 段:
///
/// ```swift
/// let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
/// guard !trimmed.isEmpty else { return [] }
/// let exact = try Song.filter(Column("title") == trimmed).fetchAll(db)
/// if !exact.isEmpty { return exact }
/// let pattern = "%\(trimmed.likeEscaped)%"
/// return try Song
///     .filter(Column("title").like(pattern, escape: "\\") || Column("title_kana").like(pattern, escape: "\\"))
///     .limit(limit).fetchAll(db)
/// ```
///
/// GRDB が生成する SQL は
/// `SELECT * FROM songs WHERE title = ?` と
/// `SELECT * FROM songs WHERE (title LIKE ? ESCAPE '\' OR title_kana LIKE ? ESCAPE '\') LIMIT ?`。
///
/// 元実装の非自明な挙動をそのまま写す (どれも「良くしない」対象):
/// - **完全一致の枝に LIMIT が無い**。同題の別曲 (別ブランド・カバー) が何件あっても
///   全部返る。上限が掛かるのは部分一致の枝だけ。
/// - 「完全一致優先」はスコアではなく**枝の切り替え**。完全一致が 1 件でもあれば
///   部分一致は評価されない (完全一致 1 件 + 部分一致 50 件 → 返るのは 1 件だけ)。
/// - 完全一致の `=` は BINARY 比較 (バイト列一致) なので ASCII の大小も区別する。
///   一方 LIKE は ASCII だけ大小を無視するので、両枝で当たり方が違う。
/// - どちらの枝も ORDER BY 無し。`songs.title` に索引が無く実行計画は SCAN なので、
///   結果順は rowid 昇順 = スナップショットの添字順になる。
/// - `title_kana` が NULL の行への LIKE は NULL = 不一致。
/// - トリムは Swift の `.whitespacesAndNewlines`。この集合 (Z* + U+000A–U+000D +
///   U+0085 + TAB) は Unicode の White_Space プロパティと同一で、Rust の
///   `char::is_whitespace` すなわち `str::trim()` がそのまま等価になる。
///
/// `limit` を u32 で受けるので負値は表現できない (SQL の `LIMIT -1` = 無制限に
/// あたる呼び方は存在しない)。呼び出し側は画面ごとの正の定数を渡す。
pub fn search_songs(snap: &Snapshot, query: &str, limit: u32) -> Vec<SongDetailRecord> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }
    let exact: Vec<SongDetailRecord> = snap
        .songs
        .iter()
        .filter(|s| s.title == trimmed)
        .map(SongDetailRecord::from)
        .collect();
    if !exact.is_empty() {
        return exact;
    }
    let needle = trimmed.to_ascii_lowercase();
    snap.songs
        .iter()
        .filter(|s| {
            ascii_ci_contains(&s.title, &needle)
                || s.title_kana.as_deref().is_some_and(|k| ascii_ci_contains(k, &needle))
        })
        .take(limit as usize)
        .map(SongDetailRecord::from)
        .collect()
}

/// 関連楽曲 (曲詳細の「関連楽曲」節)。iOS `AppDatabase.fetchRelatedSongsQuery` 相当。
///
/// 同シリーズ 3 点・同ユニット 2 点・原唱者共有 1 点を足し合わせ、点の高い順 →
/// リリース日の新しい順に並べて先頭 `limit` 件。原本は SQL 4 本 + Swift の合算で、
/// 合算部分の挙動が結果順を決めている。写すべき非自明な点:
///
/// - **点は加算**。同シリーズかつ同ユニットなら 5 点になる (どれか 1 つではない)。
/// - 自分自身はどの枝でも除く。
/// - 走査順が同点時の並びを決める。原本の Swift は初出順に `ordered` へ積み、
///   最後に `sorted` で並べ替える。Swift の `sort` は仕様上は安定と明記されていないが
///   実装は安定で、出荷済みの並びは初出順のまま。ここでも安定ソートで初出順を保つ
///   (プラットフォーム間で同じ並びを返すため、タイの順序も契約として固定する)。
/// - 各枝の初出順は元 SQL の結果順そのもの。実行計画まで込みで次のとおり:
///   - `WHERE series_group = ?` … `idx_songs_series_group` の等値レンジ = rowid 昇順
///   - `WHERE unit_id = ?` … 索引が無く SCAN = rowid 昇順
///   - `WHERE id IN (...)` … PK 索引を使い **id 昇順** (rowid 順ではない)。
///     ここだけ順序が違うので、原唱者共有の枝は id 昇順に並べてから積む。
///   rowid 昇順はスナップショットの添字順に一致する (ORDER BY 無しで読み込むため)。
/// - リリース日は `releaseDate ?? ""` の降順。空文字は最小なので NULL は末尾に来る。
///   NULL と空文字は**同じ扱い** (原本の `?? ""` がそうなっている)。
/// - シリーズ・ユニットは「NULL でも空文字でもない」ときだけ枝が動く
///   (原本の `if let sg = ..., !sg.isEmpty`)。
/// - 原唱者共有は `song_artists` を 2 段で辿る (自分の原唱者 → その人たちの原唱曲)。
///   FK 孤児の行はスナップショットに載らないので、そこは載らない世界で数える
///   (他のクエリと同じ規約。同梱 DB は song_artists の孤児ゼロ)。
///
/// 原本は `unit_id` だけ引数の `Song` から読み、`series_group` は id で引き直していた。
/// ここは両方ともスナップショットの行から読む (呼び出し側は DB から読んだ `Song` を
/// 渡しており、値は一致する)。
pub fn related_songs(snap: &Snapshot, song_id: &str, limit: u32) -> Vec<SongDetailRecord> {
    let Some(&self_i) = snap.song_index_by_id.get(song_id) else { return Vec::new() };
    let song = &snap.songs[self_i as usize];

    let mut ordered: Vec<u32> = Vec::new();
    let mut scores: HashMap<u32, i32> = HashMap::new();
    let mut add = |candidates: Vec<u32>, weight: i32| {
        for i in candidates {
            if i == self_i {
                continue;
            }
            let entry = scores.entry(i).or_insert_with(|| {
                ordered.push(i);
                0
            });
            *entry += weight;
        }
    };

    if let Some(sg) = non_empty(&song.series_group) {
        add(indexes_where(snap, |s| s.series_group.as_deref() == Some(sg)), 3);
    }
    if let Some(unit) = non_empty(&song.unit_id) {
        add(indexes_where(snap, |s| s.unit_id.as_deref() == Some(unit)), 2);
    }
    let shared = songs_sharing_original_artists(snap, self_i);
    if !shared.is_empty() {
        add(shared, 1);
    }

    // 安定ソートなので同点・同日は初出順のまま (原本 Swift の並びと一致)。
    ordered.sort_by(|&a, &b| {
        scores[&b].cmp(&scores[&a]).then_with(|| release_key(snap, b).cmp(release_key(snap, a)))
    });
    ordered.truncate(limit as usize);
    ordered.into_iter().map(|i| SongDetailRecord::from(&snap.songs[i as usize])).collect()
}

/// 条件に合う曲の添字を**添字順** (= 元 SQL の rowid 昇順) で集める。
fn indexes_where(snap: &Snapshot, pred: impl Fn(&Song) -> bool) -> Vec<u32> {
    snap.songs
        .iter()
        .enumerate()
        .filter(|(_, s)| pred(s))
        .map(|(i, _)| i as u32)
        .collect()
}

/// 自分の原唱者が原唱している曲の添字を **id 昇順**で返す。
///
/// 原本は `WHERE id IN (...)` で引いており、PK 索引経由なので結果は rowid 順ではなく
/// id 昇順で戻る (実測済み)。同点時の並びはこの初出順で決まるので、ここを添字順に
/// すると関連楽曲の並びが黙って変わる。
fn songs_sharing_original_artists(snap: &Snapshot, self_i: u32) -> Vec<u32> {
    let mut shared: HashSet<u32> = HashSet::new();
    for link in &snap.artists_by_song[self_i as usize] {
        if link.role != "original" {
            continue;
        }
        for song_link in &snap.songs_by_idol[link.idol as usize] {
            if song_link.role == "original" {
                shared.insert(song_link.song);
            }
        }
    }
    let mut indexes: Vec<u32> = shared.into_iter().collect();
    indexes.sort_unstable_by(|&a, &b| snap.songs[a as usize].id.cmp(&snap.songs[b as usize].id));
    indexes
}

/// リリース日の比較キー。原本の `releaseDate ?? ""` と同じく NULL は空文字と同一視する
/// (空文字は最小なので降順では末尾)。
fn release_key(snap: &Snapshot, i: u32) -> &str {
    snap.songs[i as usize].release_date.as_deref().unwrap_or("")
}

/// クリエイター名 (作詞/作曲/編曲 横断) で引いた曲と、その曲での役割。
/// iOS `AppDatabase.fetchSongsByCreator` 相当。
///
/// 原本は **2 段構え**で、SQL と Swift で当たり方が違うのが要点:
///
/// ```sql
/// -- ① 候補: 3 列のどれかに部分一致した曲を 50 音順で
/// SELECT * FROM songs
///  WHERE composer LIKE ? ESCAPE '\' OR lyricist LIKE ? ESCAPE '\' OR arranger LIKE ? ESCAPE '\'
///  ORDER BY title_kana, title
/// ```
/// ```swift
/// // ② 役割: 区切り文字で割った断片と「完全一致」した列だけをラベルにし、
/// //    1 つも無い候補は落とす
/// let separators = CharacterSet(charactersIn: "/／,、・")
/// let parts = value.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespaces) }
/// return parts.contains(trimmedName) ? label : nil
/// ```
///
/// 写すべき非自明な点:
/// - ① が部分一致・② が完全一致なので、**候補に挙がっても落ちる曲がある**。
///   例: 「TAKT」で引くと `TAKT (TRYTONELABO)` は LIKE には当たるが、区切り文字で
///   割っても断片は `TAKT (TRYTONELABO)` のままなので役割が付かず落ちる。
///   これは絞り込みの実効仕様 (「区切りで割った 1 人ぶんと丸ごと一致すること」) であって
///   バグではない。①だけ・②だけに寄せると結果が変わる。
/// - ② の区切りは `/／,、・` の 5 文字**だけ**。`domain::credit_names::split_credits`
///   (曲詳細のクレジット行が使う賢い分割) とは別物で、括弧の中も全角スペースも見ない。
///   揃えると「クレジット行に出る名前」と「絞り込みで当たる名前」の対応が変わるので、
///   等価移送の範囲では触らない。
/// - ② のトリムは `.whitespaces` (Zs + TAB) で、**改行を含まない**。外側の
///   `normalizedCreatorName` が使う `.whitespacesAndNewlines` とは別の集合なので、
///   `str::trim()` では代用できない。
/// - `parts.contains(trimmedName)` の Swift `==` は Unicode 正準等価だが、①の LIKE が
///   バイト比較である以上、②だけ正規化しても当たり方は揃わない。同梱データは全件 NFC で
///   バイト比較と一致するので、ここもバイト比較で写す。
/// - 役割ラベルの並びは 作曲 → 作詞 → 編曲 で固定 (フィールドの走査順そのもの)。
/// - `ORDER BY title_kana, title` は SQLite の ASC なので title_kana の NULL が先頭。
///   同着は SQL 未規定なので添字 (= rowid 読み込み順) を最終キーにして決定化する。
/// - 空・空白だけの名前は即空 (原本の `normalizedCreatorName` が nil を返す枝)。
pub fn songs_by_creator(snap: &Snapshot, name: &str) -> Vec<SongWithRolesRecord> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }
    let needle = trimmed.to_ascii_lowercase();

    let mut candidates: Vec<u32> = snap
        .songs
        .iter()
        .enumerate()
        .filter(|(_, s)| {
            [&s.composer, &s.lyricist, &s.arranger]
                .into_iter()
                .any(|v| v.as_deref().is_some_and(|v| ascii_ci_contains(v, &needle)))
        })
        .map(|(i, _)| i as u32)
        .collect();
    candidates.sort_by(|&l, &r| {
        let (a, b) = (&snap.songs[l as usize], &snap.songs[r as usize]);
        a.title_kana.cmp(&b.title_kana).then_with(|| a.title.cmp(&b.title)).then(l.cmp(&r))
    });

    candidates
        .into_iter()
        .filter_map(|i| {
            let s = &snap.songs[i as usize];
            let roles: Vec<String> = [("作曲", &s.composer), ("作詞", &s.lyricist), ("編曲", &s.arranger)]
                .into_iter()
                .filter(|(_, field)| credit_field_names_exactly(field, trimmed))
                .map(|(label, _)| label.to_string())
                .collect();
            (!roles.is_empty()).then(|| SongWithRolesRecord { song: SongDetailRecord::from(s), roles })
        })
        .collect()
}

/// クレジット欄を区切り文字で割った断片のどれかが `name` と丸ごと一致するか。
/// 区切りとトリムの集合は原本の `songsWithCreatorRoles` そのまま (関数コメント参照)。
fn credit_field_names_exactly(field: &Option<String>, name: &str) -> bool {
    field.as_deref().is_some_and(|value| {
        value
            .split(CREDIT_ROLE_SEPARATORS)
            .any(|part| trim_foundation_spaces(part) == name)
    })
}

/// 役割判定で使う区切り文字。`domain::credit_names` の分割規則とは**別物**
/// (あちらは括弧や全角スペースも見る)。ここは原本の 5 文字だけ。
const CREDIT_ROLE_SEPARATORS: [char; 5] = ['/', '／', ',', '、', '・'];

/// Swift `String.trimmingCharacters(in: .whitespaces)` の写し。
///
/// Foundation の `.whitespaces` は「Unicode General Category Zs + TAB」で、
/// **改行 (U+000A–U+000D) と U+0085 を含まない**。Rust の `str::trim()`
/// (Unicode White_Space) はそれらも落とすので、ここでは代用できない。
fn trim_foundation_spaces(s: &str) -> &str {
    s.trim_matches(|c: char| {
        matches!(c,
            '\u{0009}' | '\u{0020}' | '\u{00A0}' | '\u{1680}'
            | '\u{2000}'..='\u{200A}' | '\u{202F}' | '\u{205F}' | '\u{3000}')
    })
}

/// 編集 UI の曲ピッカー用の全曲列。iOS `AppDatabase.fetchAllSongsForPickerQuery` 相当:
///
/// ```sql
/// SELECT id, title FROM songs ORDER BY title
/// ```
///
/// 写すべき非自明な点:
/// - 並びは `title` であって `title_kana` ではない。BINARY 照合 (バイト列比較) なので、
///   かなも漢字も英字も**音読み順には並ばない**。曲一覧 (50 音順) とは別の並びだが、
///   SQL 時代からこうで、直すとピッカーの並びが黙って変わる。
/// - 絞り込みは一切なし。カバーも派生曲もその他ブランドも全部出る (編集時に
///   どの曲でも選べる必要があるため)。
/// - 同題の曲が複数あるときの並びは SQL 未規定なので、添字 (= rowid 読み込み順) を
///   最終キーにして決定化する。
pub fn all_songs_for_picker(snap: &Snapshot) -> Vec<PickedSongRecord> {
    let mut indexes: Vec<u32> = (0..snap.songs.len() as u32).collect();
    indexes.sort_by(|&l, &r| {
        snap.songs[l as usize].title.cmp(&snap.songs[r as usize].title).then(l.cmp(&r))
    });
    indexes
        .into_iter()
        .map(|i| {
            let s = &snap.songs[i as usize];
            PickedSongRecord { id: s.id.clone(), title: s.title.clone() }
        })
        .collect()
}

/// 一覧に出す資格のある曲だけを id で引く (fetchListableSongsAsync(ids:))。
///
/// 歌詞検索など「マスタを持たないサーバ側が返した id」を一覧規則に通すための入口。
/// 一覧が既定で隠すものをここでも落とす (判断をビューに書くと二重管理になるため、
/// SQL 時代からクエリ側の責務):
/// - 派生曲 (`parent_song_id` あり)。ソロ Ver. や Remix は親に代表させる。
/// - その他ブランド (`brand_id = 'other'`、歌枠カバー等)。
///   `IS NOT 'other'` だったので brand_id が NULL の曲は通る。
pub fn listable_song_records_by_ids(snap: &Snapshot, song_ids: &[String]) -> Vec<SongDetailRecord> {
    let mut seen: HashSet<u32> = HashSet::new();
    song_ids
        .iter()
        .filter_map(|id| snap.song_index_by_id.get(id).copied())
        .filter(|&i| seen.insert(i))
        .filter(|&i| {
            let s = &snap.songs[i as usize];
            s.parent_song_id.is_none() && s.brand_id.as_deref() != Some("other")
        })
        .map(|i| SongDetailRecord::from(&snap.songs[i as usize]))
        .collect()
}

/// song_id → 歌唱者 (role='original') の idol id 列 (fetchSongPerformerIdolsMap)。
///
/// 一覧表示でアイドルアイコンを並べるための一括取得。並びは SQL 時代の
/// `ORDER BY i.sort_order` (スナップショット構築時に前計算済み)。
/// Swift 実装と同じく、original 歌唱者が 1 人もいない曲はキー自体を作らない。
/// 同一 idol の重複行にも Swift と同じく初出だけ採用で防御する。
pub fn performer_idol_ids_map(
    snap: &Snapshot,
    song_ids: &[String],
) -> HashMap<String, Vec<String>> {
    let mut result: HashMap<String, Vec<String>> = HashMap::new();
    for id in song_ids {
        let Some(&si) = snap.song_index_by_id.get(id) else { continue };
        if result.contains_key(id) {
            continue; // 入力 id の重複は 1 回だけ (SQL の IN と同じ)
        }
        let mut seen: HashSet<u32> = HashSet::new();
        let idol_ids: Vec<String> = snap.artists_by_song[si as usize]
            .iter()
            .filter(|l| l.role == "original")
            .filter(|l| seen.insert(l.idol))
            .map(|l| snap.idols[l.idol as usize].id.clone())
            .collect();
        if !idol_ids.is_empty() {
            result.insert(id.clone(), idol_ids);
        }
    }
    result
}

/// 曲の披露履歴 (fetchSongPerformanceHistory)。show.date 降順。
///
/// SQL は `ORDER BY sh.date DESC` だけで同日内が未規定だった。スナップショットの
/// 前計算 (setlist_items_by_song) は同日を (show.sort_order ASC, position ASC, 添字)
/// で決定化してあるので、その並びをそのまま流す。
pub fn performance_history(snap: &Snapshot, song_id: &str) -> Vec<PerformanceHistoryEntry> {
    let Some(&si) = snap.song_index_by_id.get(song_id) else { return Vec::new() };
    snap.setlist_items_by_song[si as usize]
        .iter()
        .map(|&ii| {
            let item = &snap.setlist_items[ii as usize];
            let show = &snap.shows[item.show as usize];
            let event = &snap.events[show.event as usize];
            PerformanceHistoryEntry {
                show_id: show.id.clone(),
                event_id: event.id.clone(),
                event_name: event.name.clone(),
                show_name: show.name.clone(),
                date: show.date.clone(),
                venue: show.venue.clone(),
                position: item.position,
                section: item.section.clone(),
            }
        })
        .collect()
}

/// CD シリーズ別アルバム一覧 (fetchAlbumsAsync)。MIN(release_date) 降順。
///
/// - 対象: cd_series が NULL でも '' でもない曲。brand_ids 指定時はそのブランドのみ
///   (brand_id が NULL の曲は IN に一致しないので落ちる)。
/// - query は cd_series への部分一致 (SQLite LIKE と同じく ASCII のみ大小無視)。
/// - 並び: MIN(release_date) 降順・全曲 NULL のグループは末尾 (SQLite DESC の NULL 位置)。
///   同日は SQL 未規定だったので cd_series 昇順 (バイト列) で決定化。
pub fn album_summaries(
    snap: &Snapshot,
    brand_ids: &[String],
    query: Option<&str>,
) -> Vec<AlbumSummaryRecord> {
    let brand_set = to_brand_set(brand_ids);
    let needle = normalized_needle(query);

    // グループは出現順 (テーブルスキャン順) に積む。GROUP_CONCAT(DISTINCT) の並びを
    // 初出順で決定化するのと同じ理由で、グループ自体も走査順に一度だけ作る。
    let mut order: Vec<String> = Vec::new();
    let mut groups: HashMap<String, AlbumSummaryRecord> = HashMap::new();

    for song in &snap.songs {
        let Some(series) = non_empty(&song.cd_series) else { continue };
        if !brand_matches(&brand_set, &song.brand_id) {
            continue;
        }
        if let Some(n) = &needle {
            if !ascii_ci_contains(series, n) {
                continue;
            }
        }
        let entry = groups.entry(series.to_owned()).or_insert_with(|| {
            order.push(series.to_owned());
            AlbumSummaryRecord {
                cd_series: series.to_owned(),
                artwork_url: None,
                song_count: 0,
                earliest_date: None,
                latest_date: None,
                brand_ids: Vec::new(),
            }
        });
        entry.song_count += 1;
        // MIN/MAX は NULL を無視し '' は値として扱う (SQL 集計と同じ)。
        merge_min(&mut entry.artwork_url, &song.artwork_url);
        merge_min(&mut entry.earliest_date, &song.release_date);
        merge_max(&mut entry.latest_date, &song.release_date);
        if let Some(b) = non_empty(&song.brand_id) {
            if !entry.brand_ids.iter().any(|x| x == b) {
                entry.brand_ids.push(b.to_owned());
            }
        }
    }

    let mut result: Vec<AlbumSummaryRecord> =
        order.into_iter().map(|k| groups.remove(&k).expect("group は必ず存在する")).collect();
    result.sort_by(|a, b| {
        (Reverse(&a.earliest_date), &a.cd_series).cmp(&(Reverse(&b.earliest_date), &b.cd_series))
    });
    result
}

/// CD シリーズグループ別一覧 (fetchSeriesAsync)。MIN(release_date) 降順。
///
/// 代表ジャケットの相関サブクエリは brand / query の絞り込みを受けずに全曲から
/// 「artwork を持つ最古リリース曲」を選んでいた (release_date ASC = NULL 先頭、
/// 同日は SQL 未規定 → テーブルスキャン順の初出で決定化)。ここも同じにする。
pub fn series_summaries(
    snap: &Snapshot,
    brand_ids: &[String],
    query: Option<&str>,
) -> Vec<SeriesSummaryRecord> {
    let brand_set = to_brand_set(brand_ids);
    let needle = normalized_needle(query);

    // パス1: series_group → 代表ジャケット (絞り込み前の全曲が母集団)。
    // キーは (release_date ASC・NULL 先頭, 走査順)。Option の Ord は None < Some なので
    // 素の比較が SQLite ASC の NULL 先頭に一致する。
    let mut artwork_rep: HashMap<&str, (&Option<String>, &str)> = HashMap::new();
    for song in &snap.songs {
        let Some(group) = non_empty(&song.series_group) else { continue };
        let Some(art) = non_empty(&song.artwork_url) else { continue };
        match artwork_rep.entry(group) {
            std::collections::hash_map::Entry::Vacant(e) => {
                e.insert((&song.release_date, art));
            }
            std::collections::hash_map::Entry::Occupied(mut e) => {
                // 走査順に見ているので、更新条件を「より古い日付のみ」(同値は据え置き)
                // にすれば初出優先の決定化になる。
                if song.release_date < *e.get().0 {
                    e.insert((&song.release_date, art));
                }
            }
        }
    }

    // パス2: 絞り込み後の曲で集計。cd_series の異なり数は NULL を数えず '' は数える
    // (COUNT(DISTINCT) の挙動)。
    let mut order: Vec<String> = Vec::new();
    let mut groups: HashMap<String, SeriesSummaryRecord> = HashMap::new();
    let mut cd_sets: HashMap<String, HashSet<&str>> = HashMap::new();

    for song in &snap.songs {
        let Some(group) = non_empty(&song.series_group) else { continue };
        if !brand_matches(&brand_set, &song.brand_id) {
            continue;
        }
        if let Some(n) = &needle {
            if !ascii_ci_contains(group, n) {
                continue;
            }
        }
        let entry = groups.entry(group.to_owned()).or_insert_with(|| {
            order.push(group.to_owned());
            SeriesSummaryRecord {
                name: group.to_owned(),
                song_count: 0,
                cd_count: 0,
                earliest_date: None,
                latest_date: None,
                artwork_url: artwork_rep.get(group).map(|(_, art)| (*art).to_owned()),
                brand_ids: Vec::new(),
            }
        });
        entry.song_count += 1;
        merge_min(&mut entry.earliest_date, &song.release_date);
        merge_max(&mut entry.latest_date, &song.release_date);
        if let Some(cd) = song.cd_series.as_deref() {
            cd_sets.entry(group.to_owned()).or_default().insert(cd);
        }
        if let Some(b) = non_empty(&song.brand_id) {
            if !entry.brand_ids.iter().any(|x| x == b) {
                entry.brand_ids.push(b.to_owned());
            }
        }
    }

    let mut result: Vec<SeriesSummaryRecord> = order
        .into_iter()
        .map(|k| {
            let mut rec = groups.remove(&k).expect("group は必ず存在する");
            rec.cd_count = cd_sets.get(&k).map_or(0, |s| s.len() as u32);
            rec
        })
        .collect();
    result.sort_by(|a, b| {
        (Reverse(&a.earliest_date), &a.name).cmp(&(Reverse(&b.earliest_date), &b.name))
    });
    result
}

/// 楽曲シリーズ (series_group) 名の一覧 (fetchSeriesGroupsAsync)。曲数降順。
///
/// フィルタピッカーの選択肢用。brand_ids 指定時はそのブランドの曲だけ数える。
/// 同数のときの並びは SQL 未規定だったので名前昇順 (バイト列) で決定化。
pub fn series_group_names(snap: &Snapshot, brand_ids: &[String]) -> Vec<String> {
    let brand_set = to_brand_set(brand_ids);
    let mut counts: HashMap<&str, u32> = HashMap::new();
    for song in &snap.songs {
        let Some(group) = non_empty(&song.series_group) else { continue };
        if !brand_matches(&brand_set, &song.brand_id) {
            continue;
        }
        *counts.entry(group).or_insert(0) += 1;
    }
    let mut pairs: Vec<(&str, u32)> = counts.into_iter().collect();
    pairs.sort_by(|a, b| (Reverse(a.1), a.0).cmp(&(Reverse(b.1), b.0)));
    pairs.into_iter().map(|(name, _)| name.to_owned()).collect()
}

/// 同じ曲の別バージョン一族 (fetchVariantSongsAsync)。自分は除く。
///
/// 一覧・統計・クイズは派生曲 (`parent_song_id` あり) を隠しているので、詳細画面が
/// ここを通して「Crossing! のソロ 15 種」等に辿り着けるようにする。
/// 自分が派生側でも親側でも同じ一族が返るよう、根 (parent_song_id ?? 自分) を求めて
/// から根+根の子を集める (SQL と同じ 1 段のみの遡り)。
///
/// 並びは SQL の `ORDER BY (親なしが先), title_kana, title` を踏襲し、
/// title_kana の NULL は先頭 (SQLite ASC)、完全同値は添字で決定化。
pub fn variant_song_records(snap: &Snapshot, song_id: &str) -> Vec<SongDetailRecord> {
    let Some(&si) = snap.song_index_by_id.get(song_id) else { return Vec::new() };
    let root = snap.variant_root(si);
    let mut family: Vec<u32> = Vec::new();
    if root != si {
        family.push(root);
    }
    family.extend(snap.variants_by_song[root as usize].iter().copied().filter(|&c| c != si));
    family.sort_by(|&a, &b| variant_order_key(snap, a).cmp(&variant_order_key(snap, b)));
    family
        .into_iter()
        .map(|i| SongDetailRecord::from(&snap.songs[i as usize]))
        .collect()
}

/// fetchVariantSongs の ORDER BY 相当キー:
/// (親なし=0 / 派生=1, title_kana (NULL 先頭), title, 添字)。
fn variant_order_key(snap: &Snapshot, i: u32) -> (u8, &Option<String>, &String, u32) {
    let s = &snap.songs[i as usize];
    (u8::from(s.parent_song_id.is_some()), &s.title_kana, &s.title, i)
}

// =============================================================================
// SQL の暗黙挙動を明示するヘルパ
// =============================================================================

/// `IS NOT NULL AND <> ''` の射影。NULL と空文字を「値なし」に畳む。
fn non_empty(v: &Option<String>) -> Option<&str> {
    v.as_deref().filter(|s| !s.is_empty())
}

/// brand フィルタの集合化。空 Vec は「絞り込みなし」(SQL で IN 句自体を組まない状態)。
fn to_brand_set(brand_ids: &[String]) -> Option<HashSet<&str>> {
    if brand_ids.is_empty() {
        None
    } else {
        Some(brand_ids.iter().map(String::as_str).collect())
    }
}

/// `brand_id IN (...)` の判定。NULL はどの IN にも一致しない (SQL と同じ)。
fn brand_matches(set: &Option<HashSet<&str>>, brand_id: &Option<String>) -> bool {
    match set {
        None => true,
        Some(s) => brand_id.as_deref().is_some_and(|b| s.contains(b)),
    }
}

/// 検索語の正規化。空文字は「絞り込みなし」(Swift 側の `!query.isEmpty` ガードと同じ)。
/// LIKE の ASCII 大小無視に合わせて先に ASCII 小文字化しておく。
fn normalized_needle(query: Option<&str>) -> Option<String> {
    query.filter(|q| !q.is_empty()).map(|q| q.to_ascii_lowercase())
}

/// SQLite `LIKE '%q%'` の部分一致。ASCII のみ大小無視・非 ASCII は区別 (SQLite の既定)。
/// needle は [`normalized_needle`] で小文字化済みであること。
fn ascii_ci_contains(haystack: &str, needle_lower: &str) -> bool {
    haystack.to_ascii_lowercase().contains(needle_lower)
}

/// MIN 集計 (NULL 無視・バイト列比較 = SQLite BINARY 照合)。
fn merge_min(acc: &mut Option<String>, v: &Option<String>) {
    if let Some(v) = v {
        match acc {
            Some(cur) if v >= cur => {}
            _ => *acc = Some(v.clone()),
        }
    }
}

/// MAX 集計 (NULL 無視・バイト列比較)。
fn merge_max(acc: &mut Option<String>, v: &Option<String>) {
    if let Some(v) = v {
        match acc {
            Some(cur) if v <= cur => {}
            _ => *acc = Some(v.clone()),
        }
    }
}

// =============================================================================
// テスト: 実 Bundle DB で「元 SQL の結果 = スナップショット関数の結果」を照合する。
// これが SQL 全廃 (Phase 2) の等価性保証。rusqlite はテスト内でのみ使用する。
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::{Connection, OpenFlags};

    fn db_path() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    fn snapshot() -> Snapshot {
        crate::outbound::sqlite_loader::load_snapshot(&db_path()).expect("bundle DB はロードできる")
    }

    fn conn() -> Connection {
        Connection::open_with_flags(
            db_path(),
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .expect("bundle DB は開ける")
    }

    /// `SELECT * FROM songs` 系の行を Record に写す (カラム名で引くので列順に依存しない)。
    fn record_from_row(row: &rusqlite::Row<'_>) -> SongDetailRecord {
        SongDetailRecord {
            id: row.get_unwrap("id"),
            title: row.get_unwrap("title"),
            title_kana: row.get_unwrap("title_kana"),
            brand_id: row.get_unwrap("brand_id"),
            song_type: row.get_unwrap("song_type"),
            release_date: row.get_unwrap("release_date"),
            duration_sec: row.get_unwrap("duration_sec"),
            composer: row.get_unwrap("composer"),
            lyricist: row.get_unwrap("lyricist"),
            arranger: row.get_unwrap("arranger"),
            cd_series: row.get_unwrap("cd_series"),
            cd_title: row.get_unwrap("cd_title"),
            artwork_url: row.get_unwrap("artwork_url"),
            preview_url: row.get_unwrap("preview_url"),
            apple_music_id: row.get_unwrap("apple_music_id"),
            apple_music_album_id: row.get_unwrap("apple_music_album_id"),
            isrc: row.get_unwrap("isrc"),
            lyrics_url: row.get_unwrap("lyrics_url"),
            parent_song_id: row.get_unwrap("parent_song_id"),
            singer_label: row.get_unwrap("singer_label"),
            unit_name: row.get_unwrap("unit_name"),
            unit_id: row.get_unwrap("unit_id"),
            series_group: row.get_unwrap("series_group"),
            jasrac_code: row.get_unwrap("jasrac_code"),
        }
    }

    fn placeholders(n: usize) -> String {
        vec!["?"; n].join(",")
    }

    /// 照合: allSongsForPicker。元 SQL と**順序込み**で一致する。
    #[test]
    fn all_songs_for_picker_matches_sql() {
        let snap = snapshot();
        let db = conn();
        let mut stmt = db.prepare("SELECT id, title FROM songs ORDER BY title").unwrap();
        let expected: Vec<PickedSongRecord> = stmt
            .query_map([], |r| {
                Ok(PickedSongRecord { id: r.get_unwrap("id"), title: r.get_unwrap("title") })
            })
            .unwrap()
            .map(Result::unwrap)
            .collect();

        let actual = all_songs_for_picker(&snap);
        assert_eq!(actual.len(), snap.songs.len(), "絞り込みは一切ない (全曲)");
        assert!(actual.len() > 3000, "全曲が載っている前提: {}", actual.len());
        assert_eq!(actual, expected);
    }

    /// 並びは title (BINARY) であって title_kana ではない。
    /// 50 音順に「直す」と編集 UI のピッカーの並びが黙って変わる。
    #[test]
    fn all_songs_for_picker_is_ordered_by_title_not_kana() {
        let snap = snapshot();
        let picker = all_songs_for_picker(&snap);
        assert!(
            picker.windows(2).all(|w| w[0].title <= w[1].title),
            "title のバイト列昇順"
        );

        // 50 音順 (title_kana) とは実際に違うこと (同じなら検証として退化する)。
        let mut by_kana: Vec<u32> = (0..snap.songs.len() as u32).collect();
        by_kana.sort_by(|&l, &r| {
            let (a, b) = (&snap.songs[l as usize], &snap.songs[r as usize]);
            a.title_kana.cmp(&b.title_kana).then_with(|| a.title.cmp(&b.title)).then(l.cmp(&r))
        });
        let kana_ids: Vec<&str> =
            by_kana.iter().map(|&i| snap.songs[i as usize].id.as_str()).collect();
        let picker_ids: Vec<&str> = picker.iter().map(|p| p.id.as_str()).collect();
        assert_ne!(picker_ids, kana_ids, "title 順と title_kana 順が同じ DB では検証にならない");
    }

    /// 原本 `fetchSongsByCreator` の写経 (SQL の候補抽出 + Swift の役割判定)。
    /// 役割判定は Swift 側のコードなので、区切りとトリムの集合ごと書き写す。
    fn run_original_creator_sql(name: &str) -> Vec<(SongDetailRecord, Vec<String>)> {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            return Vec::new();
        }
        let db = conn();
        let pattern = format!("%{}%", like_escaped(trimmed));
        let mut stmt = db
            .prepare(
                "SELECT * FROM songs
                  WHERE composer LIKE ?1 ESCAPE '\\'
                     OR lyricist LIKE ?1 ESCAPE '\\'
                     OR arranger LIKE ?1 ESCAPE '\\'
                  ORDER BY title_kana, title",
            )
            .unwrap();
        let candidates: Vec<SongDetailRecord> = stmt
            .query_map([&pattern], |r| Ok(record_from_row(r)))
            .unwrap()
            .map(Result::unwrap)
            .collect();

        // Swift `songsWithCreatorRoles` の写経。
        let separators: [char; 5] = ['/', '／', ',', '、', '・'];
        let foundation_spaces = |c: char| {
            matches!(c,
                '\u{0009}' | '\u{0020}' | '\u{00A0}' | '\u{1680}'
                | '\u{2000}'..='\u{200A}' | '\u{202F}' | '\u{205F}' | '\u{3000}')
        };
        candidates
            .into_iter()
            .filter_map(|song| {
                let roles: Vec<String> = [
                    ("作曲", &song.composer),
                    ("作詞", &song.lyricist),
                    ("編曲", &song.arranger),
                ]
                .into_iter()
                .filter_map(|(label, field)| {
                    let value = field.as_deref()?;
                    value
                        .split(separators)
                        .any(|p| p.trim_matches(foundation_spaces) == trimmed)
                        .then(|| label.to_string())
                })
                .collect();
                (!roles.is_empty()).then_some((song, roles))
            })
            .collect()
    }

    /// 実データのクレジット欄から、区切りで割った実在の名前を集める (テストの入力源)。
    fn sample_creator_names(snap: &Snapshot, take: usize) -> Vec<String> {
        let mut names: Vec<String> = Vec::new();
        let mut seen: HashSet<String> = HashSet::new();
        for s in &snap.songs {
            for field in [&s.composer, &s.lyricist, &s.arranger] {
                let Some(v) = field.as_deref() else { continue };
                for part in v.split(['/', '／', ',', '、', '・']) {
                    let p = part.trim();
                    if !p.is_empty() && seen.insert(p.to_string()) {
                        names.push(p.to_string());
                    }
                }
            }
            if names.len() >= take {
                break;
            }
        }
        names
    }

    /// 照合: songsByCreator。実在の作家名を広く舐めて、元 SQL + Swift の役割判定と
    /// **順序込み・全カラム・役割ラベル込み**で一致する。
    #[test]
    fn songs_by_creator_matches_sql() {
        let snap = snapshot();
        let mut names = sample_creator_names(&snap, 60);
        // 空・空白・部分一致だけの語・ワイルドカード・空振りも混ぜる。
        names.extend(
            ["", "  ", "\u{3000}", "%", "_", "存在しない作家", "BNSI"].map(str::to_string),
        );

        let mut with_hits = 0usize;
        let mut multi_role = 0usize;
        for name in &names {
            let want = run_original_creator_sql(name);
            let got = songs_by_creator(&snap, name);
            assert_eq!(got.len(), want.len(), "name={name:?}");
            for (g, (song, roles)) in got.iter().zip(want.iter()) {
                assert_eq!(&g.song, song, "name={name:?}");
                assert_eq!(&g.roles, roles, "name={name:?}");
            }
            with_hits += usize::from(!got.is_empty());
            multi_role += got.iter().filter(|r| r.roles.len() >= 2).count();
        }
        assert!(with_hits > 30, "ヒットする作家名のサンプル数 ({with_hits})");
        assert!(multi_role > 5, "複数役割 (作曲+編曲 等) のサンプル数 ({multi_role})");
    }

    /// 候補は部分一致・役割は完全一致なので「LIKE には当たるが落ちる曲」がある。
    /// ①②のどちらか一方に寄せると結果が変わることを、実データで固定する。
    #[test]
    fn songs_by_creator_drops_substring_only_candidates() {
        let snap = snapshot();
        let db = conn();
        // 区切りで割っても丸ごと一致しない、部分文字列としてだけ現れる名前を探す。
        let name = sample_creator_names(&snap, 400)
            .into_iter()
            .find_map(|n| {
                if n.len() < 3 {
                    return None;
                }
                let head: String = n.chars().take(n.chars().count() - 1).collect();
                (!head.is_empty()
                    && !songs_by_creator(&snap, &head).is_empty()
                    && count_like_candidates(&db, &head) > songs_by_creator(&snap, &head).len())
                .then_some(head)
            })
            .expect("部分一致だけの候補が落ちる名前が実データにある前提");
        let candidates = count_like_candidates(&db, &name);
        let kept = songs_by_creator(&snap, &name).len();
        assert!(kept < candidates, "name={name:?} candidates={candidates} kept={kept}");
        assert_eq!(
            songs_by_creator(&snap, &name).len(),
            run_original_creator_sql(&name).len()
        );
    }

    fn count_like_candidates(db: &Connection, name: &str) -> usize {
        let pattern = format!("%{}%", like_escaped(name));
        db.query_row(
            "SELECT COUNT(*) FROM songs
              WHERE composer LIKE ?1 ESCAPE '\\'
                 OR lyricist LIKE ?1 ESCAPE '\\'
                 OR arranger LIKE ?1 ESCAPE '\\'",
            [&pattern],
            |r| r.get::<_, i64>(0),
        )
        .unwrap() as usize
    }

    /// 役割ラベルの並びは 作曲 → 作詞 → 編曲 で固定 (フィールドの走査順)。
    #[test]
    fn songs_by_creator_role_labels_keep_their_order() {
        let snap = snapshot();
        let order = ["作曲", "作詞", "編曲"];
        let mut checked = 0usize;
        for name in sample_creator_names(&snap, 120) {
            for row in songs_by_creator(&snap, &name) {
                let positions: Vec<usize> =
                    row.roles.iter().map(|r| order.iter().position(|o| o == r).unwrap()).collect();
                assert!(positions.windows(2).all(|w| w[0] < w[1]), "roles={:?}", row.roles);
                checked += usize::from(row.roles.len() >= 2);
            }
        }
        assert!(checked > 5, "複数役割のサンプル数 ({checked})");
    }

    /// 役割判定のトリムは `.whitespaces` (改行を含まない)。`str::trim()` で代用すると
    /// 改行入りのクレジット欄で当たり方が変わる。
    #[test]
    fn creator_role_trim_keeps_newlines() {
        assert_eq!(trim_foundation_spaces("\u{3000} 古屋真\u{00A0}"), "古屋真");
        assert_eq!(trim_foundation_spaces("\t 古屋真 "), "古屋真");
        // 改行は落とさない (Foundation の .whitespaces に入っていない)。
        assert_eq!(trim_foundation_spaces("\n古屋真\n"), "\n古屋真\n");
        assert_eq!(trim_foundation_spaces("\r\n古屋真"), "\r\n古屋真");
    }

    /// 原本 `fetchRelatedSongsQuery` の写経。SQL 4 本は rusqlite で実行し、
    /// 合算・並べ替え・打ち切りの Swift 側グルーはここに書き写す
    /// (原本は SQL と Swift の合わせ技なので、両方を写して初めて等価性の基準になる)。
    fn run_original_related_sql(song_id: &str, limit: u32) -> Vec<SongDetailRecord> {
        use rusqlite::OptionalExtension;
        let db = conn();

        let series_group: Option<String> = db
            .query_row("SELECT series_group FROM songs WHERE id = ?", [song_id], |r| r.get(0))
            .optional()
            .unwrap()
            .flatten();
        // 原本は引数の Song から unit_id を読む。呼び出し側は DB から読んだ行を渡すので同値。
        let unit_id: Option<String> = db
            .query_row("SELECT unit_id FROM songs WHERE id = ?", [song_id], |r| r.get(0))
            .optional()
            .unwrap()
            .flatten();
        let artist_ids: Vec<String> = {
            let mut stmt = db
                .prepare("SELECT idol_id FROM song_artists WHERE song_id = ? AND role = 'original'")
                .unwrap();
            let v = stmt
                .query_map([song_id], |r| r.get::<_, String>(0))
                .unwrap()
                .map(Result::unwrap)
                .collect();
            v
        };

        let fetch = |sql: &str, params: Vec<String>| -> Vec<SongDetailRecord> {
            let mut stmt = db.prepare(sql).unwrap();
            let v = stmt
                .query_map(rusqlite::params_from_iter(params.iter()), |r| Ok(record_from_row(r)))
                .unwrap()
                .map(Result::unwrap)
                .collect();
            v
        };

        let mut ordered: Vec<String> = Vec::new();
        let mut by_id: HashMap<String, (SongDetailRecord, i32)> = HashMap::new();
        let mut add = |rows: Vec<SongDetailRecord>, weight: i32| {
            for row in rows {
                if row.id == song_id {
                    continue;
                }
                let entry = by_id.entry(row.id.clone()).or_insert_with(|| {
                    ordered.push(row.id.clone());
                    (row, 0)
                });
                entry.1 += weight;
            }
        };

        if let Some(sg) = series_group.as_deref().filter(|v| !v.is_empty()) {
            add(fetch("SELECT * FROM songs WHERE series_group = ?", vec![sg.to_string()]), 3);
        }
        if let Some(unit) = unit_id.as_deref().filter(|v| !v.is_empty()) {
            add(fetch("SELECT * FROM songs WHERE unit_id = ?", vec![unit.to_string()]), 2);
        }
        if !artist_ids.is_empty() {
            let shared_ids: Vec<String> = {
                let sql = format!(
                    "SELECT DISTINCT song_id FROM song_artists
                      WHERE role = 'original' AND idol_id IN ({})",
                    placeholders(artist_ids.len())
                );
                let mut stmt = db.prepare(&sql).unwrap();
                let v = stmt
                    .query_map(rusqlite::params_from_iter(artist_ids.iter()), |r| {
                        r.get::<_, String>(0)
                    })
                    .unwrap()
                    .map(Result::unwrap)
                    .collect();
                v
            };
            if !shared_ids.is_empty() {
                let sql = format!(
                    "SELECT * FROM songs WHERE id IN ({})",
                    placeholders(shared_ids.len())
                );
                add(fetch(&sql, shared_ids), 1);
            }
        }

        // Swift の `.sorted { ... }` は実装が安定ソートなので同点・同日は初出順のまま。
        ordered.sort_by(|a, b| {
            let (ra, sa) = &by_id[a];
            let (rb, sb) = &by_id[b];
            sb.cmp(sa).then_with(|| {
                rb.release_date
                    .as_deref()
                    .unwrap_or("")
                    .cmp(ra.release_date.as_deref().unwrap_or(""))
            })
        });
        ordered.truncate(limit as usize);
        ordered.into_iter().map(|id| by_id[&id].0.clone()).collect()
    }

    /// 照合: relatedSongs。実データを広く舐めて、元 SQL + Swift グルーと
    /// **順序込み・全カラム**で一致する。
    #[test]
    fn related_songs_match_sql() {
        let snap = snapshot();
        // 3 枝それぞれが動く曲を確実に含めるため、条件つきの実在曲を明示的に足す。
        let mut targets: Vec<String> = snap.songs.iter().step_by(53).map(|s| s.id.clone()).collect();
        for pick in [
            snap.songs.iter().find(|s| non_empty(&s.series_group).is_some()),
            snap.songs.iter().find(|s| non_empty(&s.unit_id).is_some()),
            snap.songs.iter().find(|s| {
                non_empty(&s.series_group).is_some() && non_empty(&s.unit_id).is_some()
            }),
            snap.songs.iter().find(|s| {
                non_empty(&s.series_group).is_none()
                    && non_empty(&s.unit_id).is_none()
                    && !snap.artists_by_song[snap.song_index_by_id[&s.id] as usize].is_empty()
            }),
        ] {
            if let Some(s) = pick {
                targets.push(s.id.clone());
            }
        }
        targets.push("存在しない曲".to_string());

        let mut non_empty_results = 0usize;
        let mut hit_limit = 0usize;
        for id in &targets {
            for limit in [8u32, 3, 200] {
                let want = run_original_related_sql(id, limit);
                assert_eq!(related_songs(&snap, id, limit), want, "song={id} limit={limit}");
            }
            let r = related_songs(&snap, id, 8);
            non_empty_results += usize::from(!r.is_empty());
            hit_limit += usize::from(r.len() == 8);
        }
        assert!(non_empty_results > 20, "関連曲が出る曲のサンプル数 ({non_empty_results})");
        assert!(hit_limit > 10, "打ち切りが効くサンプル数 ({hit_limit})");
        assert!(related_songs(&snap, "存在しない曲", 8).is_empty());
    }

    /// 点は**加算**される (同シリーズかつ同ユニットは 3+2=5 点で、同シリーズだけの曲より前)。
    /// 「どれか 1 つの枝で決める」実装にすると並びが変わる。
    #[test]
    fn related_songs_scores_are_additive() {
        let snap = snapshot();
        // 同シリーズかつ同ユニットの相手がいる曲を実データから探す。
        let found = snap.songs.iter().find(|s| {
            let (Some(sg), Some(unit)) = (non_empty(&s.series_group), non_empty(&s.unit_id)) else {
                return false;
            };
            let both = snap.songs.iter().filter(|o| {
                o.id != s.id
                    && o.series_group.as_deref() == Some(sg)
                    && o.unit_id.as_deref() == Some(unit)
            });
            let series_only = snap.songs.iter().any(|o| {
                o.id != s.id
                    && o.series_group.as_deref() == Some(sg)
                    && o.unit_id.as_deref() != Some(unit)
            });
            both.count() > 0 && series_only
        });
        let song = found.expect("同シリーズかつ同ユニットの相手がいる曲がある前提");
        let sg = non_empty(&song.series_group).unwrap();
        let unit = non_empty(&song.unit_id).unwrap();

        let result = related_songs(&snap, &song.id, 200);
        let rank = |id: &str| result.iter().position(|r| r.id == id);
        let both = result
            .iter()
            .find(|r| r.series_group.as_deref() == Some(sg) && r.unit_id.as_deref() == Some(unit))
            .expect("5 点の相手が結果に居る");
        let series_only = result
            .iter()
            .find(|r| r.series_group.as_deref() == Some(sg) && r.unit_id.as_deref() != Some(unit))
            .expect("3 点の相手が結果に居る");
        assert!(
            rank(&both.id) < rank(&series_only.id),
            "5 点 ({}) が 3 点 ({}) より前に来る",
            both.id,
            series_only.id
        );
    }

    /// 自分自身はどの枝からも除かれる。
    #[test]
    fn related_songs_never_include_the_song_itself() {
        let snap = snapshot();
        for s in snap.songs.iter().step_by(29) {
            assert!(
                related_songs(&snap, &s.id, 200).iter().all(|r| r.id != s.id),
                "song={}",
                s.id
            );
        }
    }

    /// Swift `String.likeEscaped` の写経 (元 SQL のバインド値を組むのに使う)。
    fn like_escaped(s: &str) -> String {
        s.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_")
    }

    /// 原本 Swift `searchSongsQuery` の写経。**制御フローごと**写す
    /// (完全一致が空のときだけ部分一致に落ちる、という枝の切り替えが仕様の中心)。
    /// どちらの枝も ORDER BY 無しなので、結果は順序込みで比較する。
    fn run_original_search_sql(query: &str, limit: u32) -> Vec<SongDetailRecord> {
        let trimmed = query.trim();
        if trimmed.is_empty() {
            return Vec::new();
        }
        let db = conn();
        let exact: Vec<SongDetailRecord> = db
            .prepare("SELECT * FROM songs WHERE title = ?")
            .unwrap()
            .query_map([trimmed], |r| Ok(record_from_row(r)))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        if !exact.is_empty() {
            return exact;
        }
        let pattern = format!("%{}%", like_escaped(trimmed));
        let mut stmt = db
            .prepare(
                "SELECT * FROM songs
                  WHERE (title LIKE ? ESCAPE '\\' OR title_kana LIKE ? ESCAPE '\\')
                  LIMIT ?",
            )
            .unwrap();
        let rows: Vec<SongDetailRecord> = stmt
            .query_map(rusqlite::params![&pattern, &pattern, limit], |r| Ok(record_from_row(r)))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        rows
    }

    /// 照合: searchSongs。当たり方の違う検索語で、元 SQL と**順序込み・全カラム**で一致する。
    #[test]
    fn search_songs_matches_sql() {
        let snap = snapshot();
        // 完全一致する実在題・部分一致だけの語・かなでしか当たらない語・ASCII 大小混在・空振り
        let exact_title = snap.songs[0].title.clone();
        let queries = [
            exact_title.as_str(),
            "夢",
            "ハーモ",
            "ready",
            "READY",
            "M@STER",
            "zzz存在しない検索語",
        ];
        let mut saw_exact = false;
        let mut saw_partial = false;
        for q in queries {
            for limit in [3u32, 200] {
                let want = run_original_search_sql(q, limit);
                assert_eq!(search_songs(&snap, q, limit), want, "query={q:?} limit={limit}");
            }
            let hits = search_songs(&snap, q, 200);
            saw_exact |= hits.iter().any(|r| r.title == q);
            saw_partial |= !hits.is_empty() && hits.iter().all(|r| r.title != q);
        }
        assert!(saw_exact, "完全一致の枝を通る検索語が要る");
        assert!(saw_partial, "部分一致の枝を通る検索語が要る");
    }

    /// 完全一致の枝には LIMIT が掛からない (同題の別曲は limit を超えても全部返る)。
    /// ここを「両枝に limit」に直すと、同題が並ぶ曲で結果が黙って減る。
    #[test]
    fn search_songs_does_not_limit_the_exact_branch() {
        let snap = snapshot();
        let db = conn();
        // 同じ title が 2 件以上ある題を実データから探す (無ければ検証を諦めずに落とす)。
        let title: String = db
            .query_row(
                "SELECT title FROM songs GROUP BY title HAVING COUNT(*) >= 2 LIMIT 1",
                [],
                |r| r.get(0),
            )
            .expect("同題の曲が 2 件以上ある前提");
        let hits = search_songs(&snap, &title, 1);
        assert!(hits.len() >= 2, "limit=1 でも完全一致は全部返る: {}", hits.len());
        assert!(hits.iter().all(|r| r.title == title));
        assert_eq!(hits, run_original_search_sql(&title, 1));
    }

    /// 完全一致が 1 件でもあれば部分一致は評価されない (スコアではなく枝の切り替え)。
    #[test]
    fn search_songs_stops_at_the_exact_branch() {
        let snap = snapshot();
        // 「他の曲名の部分文字列でもある完全一致題」を探す。この語なら
        // 「両枝を足す実装」との差が出る。
        let Some(title) = snap
            .songs
            .iter()
            .map(|s| s.title.as_str())
            .find(|t| {
                t.len() >= 3 && snap.songs.iter().filter(|s| s.title.contains(*t)).count() > 1
            })
            .map(str::to_string)
        else {
            panic!("部分一致が広がる完全一致題がある前提");
        };
        let hits = search_songs(&snap, &title, 200);
        assert!(hits.iter().all(|r| r.title == title), "部分一致まで混ざっている: {title:?}");
        assert_eq!(hits, run_original_search_sql(&title, 200));
    }

    /// 空・空白だけの検索語は即空 (Swift の guard と同じ)。トリムは Foundation の
    /// `.whitespacesAndNewlines` = Unicode White_Space = Rust の `str::trim()`。
    #[test]
    fn search_songs_trims_like_foundation() {
        let snap = snapshot();
        for q in ["", " ", "\t\n", "\u{3000}", "\u{00A0}\u{2003}"] {
            assert!(search_songs(&snap, q, 200).is_empty(), "query={q:?}");
        }
        // 前後の空白は落として同じ結果になる (全角スペース・NBSP も Foundation の集合に入る)。
        let title = snap.songs[0].title.clone();
        let padded = format!("\u{3000} {title}\u{00A0}\n");
        assert_eq!(search_songs(&snap, &padded, 200), search_songs(&snap, &title, 200));
        assert_eq!(search_songs(&snap, &padded, 200), run_original_search_sql(&padded, 200));
    }

    /// likeEscaped の再現: `%` `_` はワイルドカードではなくリテラルとして当たる。
    #[test]
    fn search_songs_escapes_wildcards() {
        let snap = snapshot();
        for q in ["%", "_", "\\"] {
            assert_eq!(search_songs(&snap, q, 200), run_original_search_sql(q, 200), "query={q:?}");
        }
        // 素通しなら "%" は全曲 200 件になる。実データにリテラル % の題が無いので空。
        assert!(search_songs(&snap, "%", 200).is_empty());
    }

    /// 照合 1: fetchSongs(ids:)。IN の結果順は SQL 未規定なので id 順に正規化して
    /// 全カラムを比較する。未知 id ・重複 id の挙動 (読み飛ばし / 1 回) も含めて確認。
    #[test]
    fn songs_by_ids_matches_sql() {
        let snap = snapshot();
        let db = conn();
        // 実在 id (走査順の先頭 50 + 末尾 50) + 未知 id + 重複 id を混ぜる
        let mut ids: Vec<String> = snap.songs.iter().take(50).map(|s| s.id.clone()).collect();
        ids.extend(snap.songs.iter().rev().take(50).map(|s| s.id.clone()));
        ids.push("存在しないid".into());
        ids.push(snap.songs[0].id.clone()); // 重複

        let sql = format!("SELECT * FROM songs WHERE id IN ({})", placeholders(ids.len()));
        let mut stmt = db.prepare(&sql).unwrap();
        let mut expected: Vec<SongDetailRecord> = stmt
            .query_map(rusqlite::params_from_iter(ids.iter()), |r| Ok(record_from_row(r)))
            .unwrap()
            .map(Result::unwrap)
            .collect();

        let mut actual = song_records_by_ids(&snap, &ids);
        assert_eq!(actual.len(), 100, "実在 100 件・未知は読み飛ばし・重複は 1 回");

        expected.sort_by(|a, b| a.id.cmp(&b.id));
        actual.sort_by(|a, b| a.id.cmp(&b.id));
        assert_eq!(actual, expected);
    }

    /// 照合 2: fetchListableSongsAsync(ids:)。派生曲と brand='other' が落ち、
    /// brand_id NULL は通る (`IS NOT 'other'`) ことを SQL と突き合わせる。
    #[test]
    fn listable_songs_matches_sql() {
        let snap = snapshot();
        let db = conn();
        // 派生曲・other ブランド・通常曲を SQL 側から動的に混ぜる (データ変化に追従)
        let mut ids: Vec<String> = Vec::new();
        for q in [
            "SELECT id FROM songs WHERE parent_song_id IS NOT NULL LIMIT 20",
            "SELECT id FROM songs WHERE brand_id = 'other' LIMIT 20",
            "SELECT id FROM songs WHERE parent_song_id IS NULL AND brand_id IS NOT 'other' LIMIT 60",
            "SELECT id FROM songs WHERE brand_id IS NULL LIMIT 5",
        ] {
            let mut stmt = db.prepare(q).unwrap();
            ids.extend(
                stmt.query_map([], |r| r.get::<_, String>(0)).unwrap().map(Result::unwrap),
            );
        }
        assert!(ids.len() >= 100, "照合対象が痩せていないこと");

        let sql = format!(
            "SELECT * FROM songs
              WHERE id IN ({})
                AND parent_song_id IS NULL
                AND brand_id IS NOT 'other'",
            placeholders(ids.len())
        );
        let mut stmt = db.prepare(&sql).unwrap();
        let mut expected: Vec<SongDetailRecord> = stmt
            .query_map(rusqlite::params_from_iter(ids.iter()), |r| Ok(record_from_row(r)))
            .unwrap()
            .map(Result::unwrap)
            .collect();

        let mut actual = listable_song_records_by_ids(&snap, &ids);
        expected.sort_by(|a, b| a.id.cmp(&b.id));
        actual.sort_by(|a, b| a.id.cmp(&b.id));
        assert_eq!(actual, expected);
        assert!(!actual.is_empty());
    }

    /// 照合 3: fetchSongPerformerIdolsMap(songIds:)。全曲を対象に、曲ごとの
    /// original 歌唱者 id 列 (sort_order 順・重複除去・0 人はキーなし) を突き合わせる。
    #[test]
    fn performer_idol_ids_map_matches_sql() {
        let snap = snapshot();
        let db = conn();
        let all_ids: Vec<String> = snap.songs.iter().map(|s| s.id.clone()).collect();

        // 元 SQL: ORDER BY sa.song_id, i.sort_order + Swift 側の初出 dedup。
        // sort_order の同値タイは SQL 未規定なので (sort_order, idol id) で読んで
        // Swift と同じ初出 dedup を通す (実データにタイは無いことを probe 済みだが、
        // データが変わっても照合が壊れないよう並びを固定しておく)。
        let sql = format!(
            "SELECT sa.song_id, i.id
               FROM song_artists sa JOIN idols i ON i.id = sa.idol_id
              WHERE sa.song_id IN ({}) AND sa.role = 'original'
              ORDER BY sa.song_id, i.sort_order, i.id",
            placeholders(all_ids.len())
        );
        let mut stmt = db.prepare(&sql).unwrap();
        let mut expected: HashMap<String, Vec<String>> = HashMap::new();
        for row in stmt
            .query_map(rusqlite::params_from_iter(all_ids.iter()), |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
            })
            .unwrap()
            .map(Result::unwrap)
        {
            let (sid, iid) = row;
            let list = expected.entry(sid).or_default();
            if !list.contains(&iid) {
                list.push(iid);
            }
        }

        let actual = performer_idol_ids_map(&snap, &all_ids);
        assert_eq!(actual.len(), expected.len(), "original 歌唱者を持つ曲数が一致");
        for (sid, ids) in &expected {
            assert_eq!(actual.get(sid), Some(ids), "song={sid} の歌唱者列が一致");
        }
    }

    /// 照合 4: fetchSongPerformanceHistory。SQL は date DESC のみ規定なので、
    /// 両者を同一の決定キーに正規化して全カラム比較 + 自前出力の date 降順を検証。
    #[test]
    fn performance_history_matches_sql() {
        let snap = snapshot();
        let db = conn();
        // 披露回数の多い曲 + 同日複数披露の曲 + 披露ゼロの曲を対象にする
        let mut targets: Vec<String> = {
            let mut stmt = db
                .prepare(
                    "SELECT song_id FROM setlist_items GROUP BY song_id
                      ORDER BY COUNT(*) DESC LIMIT 5",
                )
                .unwrap();
            stmt.query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect()
        };
        targets.push("765as_902pm".into()); // 同日 2 披露の実例 (probe 済み)
        targets.push("存在しないid".into());

        for song_id in &targets {
            let mut stmt = db
                .prepare(
                    "SELECT sh.id AS show_id, e.id AS event_id,
                            e.name AS event_name, sh.name AS show_name, sh.date, sh.venue,
                            si.position, si.section
                       FROM setlist_items si
                       JOIN shows sh ON si.show_id = sh.id
                       JOIN events e ON sh.event_id = e.id
                      WHERE si.song_id = ?
                      ORDER BY sh.date DESC",
                )
                .unwrap();
            let mut expected: Vec<PerformanceHistoryEntry> = stmt
                .query_map([song_id], |r| {
                    Ok(PerformanceHistoryEntry {
                        show_id: r.get_unwrap("show_id"),
                        event_id: r.get_unwrap("event_id"),
                        event_name: r.get_unwrap("event_name"),
                        show_name: r.get_unwrap("show_name"),
                        date: r.get_unwrap("date"),
                        venue: r.get_unwrap("venue"),
                        position: r.get_unwrap("position"),
                        section: r.get_unwrap("section"),
                    })
                })
                .unwrap()
                .map(Result::unwrap)
                .collect();

            let actual = performance_history(&snap, song_id);

            // 可視の契約 (date 降順) をスナップショット出力側で検証
            assert!(
                actual.windows(2).all(|w| w[0].date >= w[1].date),
                "song={song_id} の履歴が date 降順"
            );

            // 同日内の並びは SQL 未規定なので、決定キーに正規化して全カラム照合
            let canon = |v: &mut Vec<PerformanceHistoryEntry>| {
                v.sort_by(|a, b| {
                    (Reverse(&a.date), &a.show_id, a.position, &a.section)
                        .cmp(&(Reverse(&b.date), &b.show_id, b.position, &b.section))
                });
            };
            let mut actual = actual;
            canon(&mut expected);
            canon(&mut actual);
            assert_eq!(actual, expected, "song={song_id} の披露履歴が一致");
        }
    }

    /// 照合 5: fetchAlbumsAsync。絞り込みなし / ブランド絞り / query (ASCII 大小無視の
    /// LIKE) の 3 パターンで、集計値と並びの契約 (MIN(release_date) 降順) を突き合わせる。
    #[test]
    fn album_summaries_matches_sql() {
        let snap = snapshot();
        let db = conn();
        let cases: [(&[&str], Option<&str>); 4] = [
            (&[], None),
            (&["ml", "cg"], None),
            (&[], Some("MASTER")), // 大文字で与え LIKE の ASCII 大小無視を照合する
            (&["sidem"], Some("st@rting")),
        ];
        for (brands, query) in cases {
            let brand_vec: Vec<String> = brands.iter().map(|s| s.to_string()).collect();
            let mut sql = String::from(
                "SELECT cd_series,
                        MIN(artwork_url) AS artwork_url,
                        COUNT(*) AS song_count,
                        MIN(release_date) AS earliest_date,
                        MAX(release_date) AS latest_date,
                        GROUP_CONCAT(DISTINCT brand_id) AS brand_ids
                   FROM songs
                  WHERE cd_series IS NOT NULL AND cd_series != ''",
            );
            let mut args: Vec<String> = Vec::new();
            if !brands.is_empty() {
                sql.push_str(&format!(" AND brand_id IN ({})", placeholders(brands.len())));
                args.extend(brand_vec.iter().cloned());
            }
            if let Some(q) = query {
                sql.push_str(" AND cd_series LIKE ? ESCAPE '\\'");
                args.push(format!("%{q}%"));
            }
            sql.push_str(" GROUP BY cd_series ORDER BY MIN(release_date) DESC");

            let mut stmt = db.prepare(&sql).unwrap();
            let mut expected: Vec<AlbumSummaryRecord> = stmt
                .query_map(rusqlite::params_from_iter(args.iter()), |r| {
                    Ok(AlbumSummaryRecord {
                        cd_series: r.get_unwrap("cd_series"),
                        artwork_url: r.get_unwrap("artwork_url"),
                        song_count: r.get_unwrap::<_, i64>("song_count") as u32,
                        earliest_date: r.get_unwrap("earliest_date"),
                        latest_date: r.get_unwrap("latest_date"),
                        // Swift の split(",") + 空要素除去と同じ写像
                        brand_ids: r
                            .get_unwrap::<_, Option<String>>("brand_ids")
                            .map(|s| {
                                s.split(',')
                                    .filter(|x| !x.is_empty())
                                    .map(str::to_owned)
                                    .collect()
                            })
                            .unwrap_or_default(),
                    })
                })
                .unwrap()
                .map(Result::unwrap)
                .collect();

            let mut actual = album_summaries(&snap, &brand_vec, query);
            assert_eq!(actual.len(), expected.len(), "brands={brands:?} q={query:?} の件数");

            // 可視の契約: MIN(release_date) 降順 (NULL 末尾) をスナップショット出力側で検証
            assert!(
                actual.windows(2).all(|w| {
                    (Reverse(&w[0].earliest_date)) <= (Reverse(&w[1].earliest_date))
                }),
                "brands={brands:?} q={query:?} が MIN(release_date) 降順"
            );

            // GROUP_CONCAT(DISTINCT) の並びと同日タイの並びは SQL 未規定なので正規化して照合
            let canon = |v: &mut Vec<AlbumSummaryRecord>| {
                for r in v.iter_mut() {
                    r.brand_ids.sort();
                }
                v.sort_by(|a, b| a.cd_series.cmp(&b.cd_series));
            };
            canon(&mut expected);
            canon(&mut actual);
            assert_eq!(actual, expected, "brands={brands:?} q={query:?} の集計が一致");
        }
    }

    /// 照合 6: fetchSeriesAsync。代表ジャケット相関サブクエリ (ブランド絞り込みの影響を
    /// 受けない) を含めて突き合わせる。
    #[test]
    fn series_summaries_matches_sql() {
        let snap = snapshot();
        let db = conn();
        let cases: [(&[&str], Option<&str>); 3] =
            [(&[], None), (&["ml"], None), (&[], Some("the@ter"))];
        for (brands, query) in cases {
            let brand_vec: Vec<String> = brands.iter().map(|s| s.to_string()).collect();
            let mut sql = String::from(
                "SELECT series_group AS name,
                        COUNT(*) AS song_count,
                        COUNT(DISTINCT cd_series) AS cd_count,
                        MIN(release_date) AS earliest_date,
                        MAX(release_date) AS latest_date,
                        GROUP_CONCAT(DISTINCT brand_id) AS brand_ids,
                        (SELECT s2.artwork_url FROM songs s2
                          WHERE s2.series_group = songs.series_group
                            AND s2.artwork_url IS NOT NULL AND s2.artwork_url != ''
                          ORDER BY s2.release_date LIMIT 1) AS artwork_url
                   FROM songs
                  WHERE series_group IS NOT NULL AND series_group != ''",
            );
            let mut args: Vec<String> = Vec::new();
            if !brands.is_empty() {
                sql.push_str(&format!(" AND brand_id IN ({})", placeholders(brands.len())));
                args.extend(brand_vec.iter().cloned());
            }
            if let Some(q) = query {
                sql.push_str(" AND series_group LIKE ? ESCAPE '\\'");
                args.push(format!("%{q}%"));
            }
            sql.push_str(" GROUP BY series_group ORDER BY MIN(release_date) DESC");

            let mut stmt = db.prepare(&sql).unwrap();
            let mut expected: Vec<SeriesSummaryRecord> = stmt
                .query_map(rusqlite::params_from_iter(args.iter()), |r| {
                    Ok(SeriesSummaryRecord {
                        name: r.get_unwrap("name"),
                        song_count: r.get_unwrap::<_, i64>("song_count") as u32,
                        cd_count: r.get_unwrap::<_, i64>("cd_count") as u32,
                        earliest_date: r.get_unwrap("earliest_date"),
                        latest_date: r.get_unwrap("latest_date"),
                        artwork_url: r.get_unwrap("artwork_url"),
                        brand_ids: r
                            .get_unwrap::<_, Option<String>>("brand_ids")
                            .map(|s| {
                                s.split(',')
                                    .filter(|x| !x.is_empty())
                                    .map(str::to_owned)
                                    .collect()
                            })
                            .unwrap_or_default(),
                    })
                })
                .unwrap()
                .map(Result::unwrap)
                .collect();

            let mut actual = series_summaries(&snap, &brand_vec, query);
            assert_eq!(actual.len(), expected.len(), "brands={brands:?} q={query:?} の件数");
            assert!(
                actual.windows(2).all(|w| {
                    (Reverse(&w[0].earliest_date)) <= (Reverse(&w[1].earliest_date))
                }),
                "brands={brands:?} q={query:?} が MIN(release_date) 降順"
            );

            // 代表ジャケットの「同日タイ」は SQL 未規定なので、タイの場合だけ
            // 候補集合の一員であることまでを検証し、それ以外は完全一致を要求する。
            let canon = |v: &mut Vec<SeriesSummaryRecord>| {
                for r in v.iter_mut() {
                    r.brand_ids.sort();
                }
                v.sort_by(|a, b| a.name.cmp(&b.name));
            };
            canon(&mut expected);
            canon(&mut actual);
            for (a, e) in actual.iter().zip(expected.iter()) {
                let mut a2 = a.clone();
                let mut e2 = e.clone();
                a2.artwork_url = None;
                e2.artwork_url = None;
                assert_eq!(a2, e2, "brands={brands:?} q={query:?} name={} の集計が一致", a.name);
                if a.artwork_url != e.artwork_url {
                    // 最古リリース日が同日の複数候補がある場合のみ許容される差
                    let candidates = representative_artwork_candidates(&db, &a.name);
                    assert!(
                        a.artwork_url.as_deref().is_some_and(|u| candidates.contains(u)),
                        "name={} の代表ジャケットが最古日候補のいずれか (actual={:?} sql={:?})",
                        a.name,
                        a.artwork_url,
                        e.artwork_url
                    );
                }
            }
        }
    }

    /// 代表ジャケットの正当な候補 = artwork を持つ曲のうち release_date が最小
    /// (NULL 先頭 = SQLite ASC) の曲の artwork_url 集合。
    fn representative_artwork_candidates(db: &Connection, group: &str) -> HashSet<String> {
        let mut stmt = db
            .prepare(
                "SELECT artwork_url FROM songs
                  WHERE series_group = ?1 AND artwork_url IS NOT NULL AND artwork_url != ''
                    AND (release_date IS (SELECT release_date FROM songs
                          WHERE series_group = ?1 AND artwork_url IS NOT NULL AND artwork_url != ''
                          ORDER BY release_date LIMIT 1))",
            )
            .unwrap();
        stmt.query_map([group], |r| r.get(0)).unwrap().map(Result::unwrap).collect()
    }

    /// 照合 7: fetchSeriesGroupsAsync。曲数降順 (同数タイは SQL 未規定 → 名前昇順に
    /// 正規化して照合) を全件 / ブランド絞りで突き合わせる。
    #[test]
    fn series_group_names_matches_sql() {
        let snap = snapshot();
        let db = conn();
        for brands in [vec![], vec!["ml".to_string(), "sc".to_string()]] {
            let mut sql = String::from(
                "SELECT series_group, COUNT(*) AS cnt FROM songs
                  WHERE series_group IS NOT NULL AND series_group <> ''",
            );
            if !brands.is_empty() {
                sql.push_str(&format!(" AND brand_id IN ({})", placeholders(brands.len())));
            }
            sql.push_str(" GROUP BY series_group ORDER BY cnt DESC, series_group");

            let mut stmt = db.prepare(&sql).unwrap();
            let expected: Vec<String> = stmt
                .query_map(rusqlite::params_from_iter(brands.iter()), |r| r.get(0))
                .unwrap()
                .map(Result::unwrap)
                .collect();

            let actual = series_group_names(&snap, &brands);
            assert_eq!(actual, expected, "brands={brands:?} のシリーズ名一覧が一致");
        }
    }

    /// 照合 8: fetchVariantSongsAsync。親から見ても子から見ても同じ一族が返り、
    /// ORDER BY (親なし先頭, title_kana, title) が一致することを確認する。
    #[test]
    fn variant_songs_matches_sql() {
        let snap = snapshot();
        let db = conn();
        // 派生の多い親と、その子の 1 つ + 派生を持たない曲を対象にする
        let parent: String = db
            .query_row(
                "SELECT parent_song_id FROM songs WHERE parent_song_id IS NOT NULL
                  GROUP BY parent_song_id ORDER BY COUNT(*) DESC LIMIT 1",
                [],
                |r| r.get(0),
            )
            .unwrap();
        let child: String = db
            .query_row(
                "SELECT id FROM songs WHERE parent_song_id = ? ORDER BY id LIMIT 1",
                [&parent],
                |r| r.get(0),
            )
            .unwrap();
        let loner: String = db
            .query_row(
                "SELECT id FROM songs s WHERE s.parent_song_id IS NULL
                  AND NOT EXISTS (SELECT 1 FROM songs c WHERE c.parent_song_id = s.id)
                  ORDER BY id LIMIT 1",
                [],
                |r| r.get(0),
            )
            .unwrap();

        for song_id in [&parent, &child, &loner] {
            // 元 Swift と同じく、まず root (parent_song_id ?? id) を求める
            let root: String = db
                .query_row(
                    "SELECT COALESCE(parent_song_id, id) FROM songs WHERE id = ?",
                    [song_id],
                    |r| r.get(0),
                )
                .unwrap();
            let mut stmt = db
                .prepare(
                    "SELECT * FROM songs
                      WHERE (id = ?1 OR parent_song_id = ?1) AND id != ?2
                      ORDER BY CASE WHEN parent_song_id IS NULL THEN 0 ELSE 1 END,
                               title_kana, title",
                )
                .unwrap();
            let mut expected: Vec<SongDetailRecord> = stmt
                .query_map([&root, song_id], |r| Ok(record_from_row(r)))
                .unwrap()
                .map(Result::unwrap)
                .collect();

            let mut actual = variant_song_records(&snap, song_id);

            // (kana, title) 完全同値のタイは SQL 未規定なので id で正規化して照合。
            // 可視の契約 (バケツ → kana → title の非減少) は actual 側で別途検証する。
            assert!(
                actual.windows(2).all(|w| {
                    let key = |r: &SongDetailRecord| {
                        (
                            u8::from(r.parent_song_id.is_some()),
                            r.title_kana.clone(),
                            r.title.clone(),
                        )
                    };
                    key(&w[0]) <= key(&w[1])
                }),
                "song={song_id} の並びが ORDER BY 契約に従う"
            );
            let canon = |v: &mut Vec<SongDetailRecord>| {
                v.sort_by(|a, b| {
                    (
                        u8::from(a.parent_song_id.is_some()),
                        &a.title_kana,
                        &a.title,
                        &a.id,
                    )
                        .cmp(&(
                            u8::from(b.parent_song_id.is_some()),
                            &b.title_kana,
                            &b.title,
                            &b.id,
                        ))
                });
            };
            canon(&mut expected);
            canon(&mut actual);
            assert_eq!(actual, expected, "song={song_id} の別バージョン一族が一致");
        }
        // 親起点は自分抜きの子全員、子起点は根+兄弟、独身曲は空になることの粗い確認
        assert!(!variant_song_records(&snap, &parent).is_empty());
        assert!(variant_song_records(&snap, &child).len() >= variant_song_records(&snap, &parent).len());
        assert!(variant_song_records(&snap, &loner).is_empty());
    }
}
