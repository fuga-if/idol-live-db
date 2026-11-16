//! AI に頼める操作 (アプリ内で利用者が自分でできる操作) の一覧と検査。
//!
//! 「昨日の公演に現地参加を付けて、チケット代 9,800 円も入れて」のような頼みを、モデルが
//! **操作の列**に直す。ここはその操作の語彙と、1 件ずつの検査を持つ。
//!
//! # 決めていること
//!
//! - **モデルは実行しない。** 操作ツールを呼んでも「予定に積んだ」が返るだけで、端末は
//!   往復が終わってから利用者に一覧を見せ、利用者が押して初めて実行する。
//! - **id は DB に実在するものだけ通す。** 名前から組み立てた id はここで落ちる。
//! - 操作ごとに「どこまで届くか」([`AiActionReach`]) を持つ。端末の中だけで済みすぐ戻せるもの、
//!   サーバに送られ他の人にも見えるもの、画面を開くだけのもの。端末は届く先を一覧に出す。
//! - 人が書くべき中身 (歌詞・コール・修正の文面) は操作にしない。その画面を開くところまで。
//!   消したら戻らない操作 (プレイリストや支出の削除) も載せない。
//!
//! 実行そのものは各 OS (GRDB・通知・再生は OS の持ち物)。操作 1 件 = 既存の書き込み口 1 回。

use crate::domain::ledger::{self, ExpenseCategory};
use crate::domain::show_naming::show_title;
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// 1 回の頼みで積める操作の上限。
pub const MAX_ACTIONS: usize = 30;
/// 1 つの操作で渡せる曲数の上限 (プレイリスト・再生)。
pub const MAX_SONGS_PER_ACTION: usize = 200;
/// メモ・座席・タグ名・プレイリスト名の上限 (文字数)。
pub const MAX_NOTE_CHARS: usize = 500;
pub const MAX_NAME_CHARS: usize = 40;

/// 操作がどこまで届くか。
#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiActionReach {
    /// この端末の記録だけ。同じ操作で戻せる。
    Device,
    /// サーバに送る。他の人の画面にも数として出る。
    Shared,
    /// 画面を開く・曲を流すだけ。記録は変わらない。
    Screen,
}

/// 検査を通った操作 1 件。各 OS はこれを見て既存の書き込み口を 1 回呼ぶ。
#[derive(uniffi::Enum, Debug, Clone, PartialEq, Eq)]
pub enum AiAction {
    /// 公演の参加。`attendance` は "live" / "stream" / "live_viewing"。
    SetAttendance { show_id: String, attendance: String, on: bool },
    /// 曲のお気に入り。
    SetFavoriteSong { song_id: String, on: bool },
    /// アイドルの担当。
    SetMyPick { idol_id: String, on: bool },
    /// メモ。`entity` は "song" / "idol" / "event" / "show"。空文字は消す。
    SetNote { entity: String, id: String, text: String },
    /// 公演の座席。空文字は消す。
    SetSeat { show_id: String, text: String },
    /// 自分用のタグ。`entity` は "idol" / "unit"。
    AddPersonalTag { entity: String, id: String, name: String },
    RemovePersonalTag { entity: String, id: String, name: String },
    /// プレイリストを作って曲を入れる。
    CreatePlaylist { name: String, song_ids: Vec<String> },
    /// 既存のプレイリストに曲を足す。どれに足すかは、名前からコアが決めて id で渡す。
    AddToPlaylist { playlist_id: String, song_ids: Vec<String> },
    /// 収支に 1 件足す。
    AddExpense {
        date: String,
        category: ExpenseCategory,
        amount: i64,
        show_id: Option<String>,
        event_id: Option<String>,
        note: Option<String>,
    },
    /// 詳細を開く。`entity` は "song" / "idol" / "event" / "show" / "unit"。
    /// `section` は "" / "history" (曲の披露履歴) / "lyrics" (曲の歌詞・コール)。
    Open { entity: String, id: String, section: String },
    /// 曲を続けて流す。
    PlaySongs { song_ids: Vec<String> },
    /// 曲の習熟度。`level` は 0 (未設定) から、利用者が決めた段数まで。
    SetMastery { song_ids: Vec<String>, level: u32 },
    /// 公演を端末のカレンダーに足す。
    AddToCalendar { show_id: String },
    /// 通知の種類ごとのオンオフ。`kind` は "oshi_birthday" / "live_week" / "ticket" / "monday"。
    SetNotification { kind: String, on: bool },
    /// 一覧 (タブ) を開いて、その検索欄に語を入れる。`list` は "events" / "songs" / "idols"。
    OpenList { list: String, query: String },
    /// セトリ予想の 1 票。
    PredictSong { show_id: String, song_id: String, on: bool },
    /// セトリの曲への「いいね」。
    LikeSetlistSong { show_id: String, song_id: String, on: bool },
}

/// 一覧に出す 1 行。`title` は何をするか、`target` は何に対してか (DB の名前)。
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct AiPlannedAction {
    pub action: AiAction,
    pub reach: AiActionReach,
    pub title: String,
    pub target: String,
    /// 一覧で初めから選んでおくか。サーバに届くもの・外す/消すもの・前の中身を置き換えるものは
    /// 選ばないで出し、利用者が自分で選ぶ。
    pub preselected: bool,
}

/// 端末にあるプレイリスト 1 本 (名前から id を決めるのに使う)。各 OS が射影して渡す。
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct AiPlaylistRef {
    pub id: String,
    pub name: String,
}

/// 検査に要る、DB の外の事情。
#[derive(Debug, Clone, Copy)]
pub struct PlanContext<'a> {
    /// JST の今日 (`YYYY-MM-DD`)。
    pub today_key: &'a str,
    pub playlists: &'a [AiPlaylistRef],
    /// 習熟度の段階の名前 (LV.1 から順)。段数は利用者が決めるので端末から受ける。
    pub mastery_labels: &'a [String],
}

/// 端末の側の事情 (DB の外にあって、検査や頼み方に要るもの)。各 OS が 1 回射影して渡す。
#[derive(uniffi::Record, Debug, Clone, Default, PartialEq, Eq)]
pub struct AiDeviceContext {
    pub playlists: Vec<AiPlaylistRef>,
    /// 習熟度の段階の名前 (LV.1 から順)。
    pub mastery_labels: Vec<String>,
}

impl AiDeviceContext {
    pub fn plan_context<'a>(&'a self, today_key: &'a str) -> PlanContext<'a> {
        PlanContext { today_key, playlists: &self.playlists, mastery_labels: &self.mastery_labels }
    }
}

/// 操作ツール 1 本の定義 (名前・説明・引数の型)。
pub struct ActionSpec {
    pub name: &'static str,
    pub description: &'static str,
    pub properties: Value,
    pub required: &'static [&'static str],
}

fn string(description: &str) -> Value {
    json!({ "type": "string", "description": description })
}

fn on_flag() -> Value {
    json!({ "type": "boolean", "description": "付けるなら true、外すなら false。省くと true。" })
}

fn song_ids() -> Value {
    json!({ "type": "array", "items": { "type": "string" }, "description": "曲の id (songs.id) を流す・並べる順に。" })
}

/// 操作ツールの一覧。並びがそのままモデルに見える順。
pub fn catalog() -> Vec<ActionSpec> {
    vec![
        ActionSpec {
            name: "set_attendance",
            description: "公演 (ライブの 1 日ぶん) に、利用者が参加した記録を付ける・外す。端末の中だけの記録。",
            properties: json!({
                "show_id": string("公演の id (shows.id)。ライブ (event) の id ではない。"),
                "type": { "type": "string", "enum": ["live", "stream", "live_viewing"],
                          "description": "live = 現地、stream = 配信、live_viewing = ライブビューイング。言われなければ live。" },
                "on": on_flag(),
            }),
            required: &["show_id"],
        },
        ActionSpec {
            name: "set_favorite_song",
            description: "曲をお気に入りに入れる・外す。端末の中だけの記録。",
            properties: json!({ "song_id": string("曲の id。"), "on": on_flag() }),
            required: &["song_id"],
        },
        ActionSpec {
            name: "set_my_pick",
            description: "アイドルを利用者の担当にする・外す。端末の中だけの記録。",
            properties: json!({ "idol_id": string("アイドルの id。"), "on": on_flag() }),
            required: &["idol_id"],
        },
        ActionSpec {
            name: "set_note",
            description: "曲・アイドル・ライブ・公演に、利用者のメモを書く。text は利用者が言った文面をそのまま。空文字で消す。前のメモは上書きされる。",
            properties: json!({
                "kind": { "type": "string", "enum": ["song", "idol", "event", "show"] },
                "id": string("対象の id。"),
                "text": string("メモの文面。"),
            }),
            required: &["kind", "id", "text"],
        },
        ActionSpec {
            name: "set_seat",
            description: "公演の座席 (「アリーナ A3 ブロック 12 列」など) を記録する。空文字で消す。",
            properties: json!({ "show_id": string("公演の id。"), "text": string("座席。利用者が言ったとおり。") }),
            required: &["show_id", "text"],
        },
        ActionSpec {
            name: "add_personal_tag",
            description: "アイドルかユニットに、利用者だけが見る自分用のタグを付ける。みんなに見える公開タグではない。",
            properties: json!({
                "kind": { "type": "string", "enum": ["idol", "unit"] },
                "id": string("対象の id。"),
                "name": string("タグの名前。利用者が言ったとおり。"),
            }),
            required: &["kind", "id", "name"],
        },
        ActionSpec {
            name: "remove_personal_tag",
            description: "自分用のタグを外す。",
            properties: json!({
                "kind": { "type": "string", "enum": ["idol", "unit"] },
                "id": string("対象の id。"),
                "name": string("外すタグの名前。"),
            }),
            required: &["kind", "id", "name"],
        },
        ActionSpec {
            name: "create_playlist",
            description: "プレイリストを新しく作り、曲を入れる。端末の中に作る (公開はしない)。",
            properties: json!({ "name": string("プレイリストの名前。"), "song_ids": song_ids() }),
            required: &["name", "song_ids"],
        },
        ActionSpec {
            name: "add_to_playlist",
            description: "利用者が名前で指したプレイリストに曲を足す。その名前のものが無ければ新しく作る (一覧にそう出る)。同じ名前が複数あると積めない。",
            properties: json!({ "playlist_name": string("プレイリストの名前。"), "song_ids": song_ids() }),
            required: &["playlist_name", "song_ids"],
        },
        ActionSpec {
            name: "add_expense",
            description: "収支 (この趣味に使ったお金の帳簿) に支出を 1 件足す。金額は利用者が言った額だけを使う。DB のチケット価格から勝手に入れない。",
            properties: json!({
                "date": string("支払った日 YYYY-MM-DD。言われなければ、公演に紐づくなら公演の日、無ければ今日。"),
                "category": { "type": "string",
                              "enum": ledger::expense_categories().into_iter().map(|c| c.key).collect::<Vec<_>>(),
                              "description": "費目。" },
                "amount": { "type": "integer", "description": "円。整数。" },
                "show_id": string("紐づける公演の id。遠征・チケットなど公演にかかった支出のとき。"),
                "note": string("メモ。"),
            }),
            required: &["date", "category", "amount"],
        },
        ActionSpec {
            name: "open",
            description: "曲・アイドル・ライブ・公演・ユニットの詳細を開く。歌詞の投稿・コールの編集・修正の依頼のように人が中身を書くことは、ここで画面を開くところまで (曲は section に lyrics)。",
            properties: json!({
                "kind": { "type": "string", "enum": ["song", "idol", "event", "show", "unit"] },
                "id": string("対象の id。"),
                "section": { "type": "string", "enum": ["", "history", "lyrics"],
                             "description": "曲のとき: history = 披露履歴、lyrics = 歌詞とコール。ほかは空。" },
            }),
            required: &["kind", "id"],
        },
        ActionSpec {
            name: "play_songs",
            description: "曲を続けて流す (Apple Music か Spotify)。",
            properties: json!({ "song_ids": song_ids() }),
            required: &["song_ids"],
        },
        ActionSpec {
            name: "set_mastery",
            description: "曲の習熟度 (どれくらい覚えたか) を付ける。段階の番号と名前は指示文にある。0 で未設定に戻す。前の段階は置き換わる。",
            properties: json!({
                "song_ids": song_ids(),
                "level": { "type": "integer", "description": "段階の番号。0 は未設定。" },
            }),
            required: &["song_ids", "level"],
        },
        ActionSpec {
            name: "add_to_calendar",
            description: "公演を端末のカレンダーに予定として足す。",
            properties: json!({ "show_id": string("公演の id。") }),
            required: &["show_id"],
        },
        ActionSpec {
            name: "set_notification",
            description: "アプリの通知を種類ごとにオンオフする。",
            properties: json!({
                "kind": { "type": "string", "enum": ["oshi_birthday", "live_week", "ticket", "monday"],
                          "description": "oshi_birthday = 担当の誕生日、live_week = ライブの前、ticket = チケットの受付、monday = 月曜のお知らせ。" },
                "on": on_flag(),
            }),
            required: &["kind"],
        },
        ActionSpec {
            name: "open_list",
            description: "ライブ・楽曲・アイドルの一覧を開いて、検索欄に語を入れる。たくさんの結果を利用者が自分で眺めたいときに。",
            properties: json!({
                "list": { "type": "string", "enum": ["events", "songs", "idols"] },
                "query": string("検索欄に入れる語 (曲名・名前・会場など)。空でもよい。"),
            }),
            required: &["list"],
        },
        ActionSpec {
            name: "predict_song",
            description: "これからの公演のセトリ予想に、この曲で 1 票入れる・取り消す。サーバに送られ、票の数は他の人にも見える。",
            properties: json!({ "show_id": string("公演の id。"), "song_id": string("曲の id。"), "on": on_flag() }),
            required: &["show_id", "song_id"],
        },
        ActionSpec {
            name: "like_setlist_song",
            description: "終わった公演のセトリの 1 曲に「いいね」を付ける・外す。サーバに送られ、数は他の人にも見える。",
            properties: json!({ "show_id": string("公演の id。"), "song_id": string("曲の id。"), "on": on_flag() }),
            required: &["show_id", "song_id"],
        },
    ]
}

/// この名前は操作ツールか。
pub fn is_action(name: &str) -> bool {
    catalog().iter().any(|s| s.name == name)
}

fn text_arg<'a>(args: &'a Value, key: &str) -> &'a str {
    args.get(key).and_then(Value::as_str).unwrap_or("").trim()
}

/// `on` は省けば true。真偽値でない値 (文字列の "false" など) は、付ける側に倒さずに弾く。
fn on_arg(args: &Value) -> Result<bool, String> {
    match args.get("on") {
        None | Some(Value::Null) => Ok(true),
        Some(Value::Bool(b)) => Ok(*b),
        Some(_) => Err("on は true か false (真偽値) で".into()),
    }
}

fn clipped(text: &str, max: usize, what: &str) -> Result<String, String> {
    if text.chars().count() > max {
        return Err(format!("{what}が長すぎます ({max} 字まで)"));
    }
    Ok(text.to_string())
}

fn song_title(snap: &Snapshot, id: &str) -> Result<(String, String), String> {
    snap.song(id).map(|s| (s.id.clone(), s.title.clone())).ok_or_else(|| format!("曲の id が DB にありません: {id}"))
}

fn show_name(snap: &Snapshot, id: &str) -> Result<(String, String), String> {
    let show = snap.show(id).ok_or_else(|| format!("公演の id が DB にありません: {id} (ライブの id なら get_event で公演の id を引く)"))?;
    Ok((show.id.clone(), show_title(snap, &show.id).unwrap_or_else(|| show.name.clone())))
}

/// (正しい id, 名前)。`kinds` に無い種別・DB に無い id は Err。
fn entity(snap: &Snapshot, kind: &str, id: &str, kinds: &[&str]) -> Result<(String, String), String> {
    if !kinds.contains(&kind) {
        return Err(format!("kind は {} のどれか", kinds.join(" / ")));
    }
    let missing = || format!("{kind} の id が DB にありません: {id}");
    match kind {
        "song" => song_title(snap, id),
        "show" => show_name(snap, id),
        "idol" => snap.idol(id).map(|i| (i.id.clone(), i.name.clone())).ok_or_else(missing),
        "event" => snap.event(id).map(|e| (e.id.clone(), e.name.clone())).ok_or_else(missing),
        "unit" => snap.unit(id).map(|u| (u.id.clone(), u.name.clone())).ok_or_else(missing),
        _ => Err(missing()),
    }
}

/// 曲の id 列を検査する。DB に無い id は落とし、同じ曲は最初の 1 回だけ。1 曲も残らなければ Err。
fn songs(snap: &Snapshot, args: &Value) -> Result<Vec<String>, String> {
    let mut out: Vec<String> = Vec::new();
    for id in args.get("song_ids").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
        if let Some(song) = snap.song(id.trim()) {
            if !out.contains(&song.id) {
                out.push(song.id.clone());
            }
        }
        if out.len() >= MAX_SONGS_PER_ACTION {
            break;
        }
    }
    if out.is_empty() {
        return Err("DB にある曲の id が 1 つもありません (id は search か resolve の結果から)".into());
    }
    Ok(out)
}

fn planned(action: AiAction, reach: AiActionReach, title: impl Into<String>, target: impl Into<String>) -> AiPlannedAction {
    let preselected = reach != AiActionReach::Shared && !replaces_or_removes(&action);
    AiPlannedAction { action, reach, title: title.into(), target: target.into(), preselected }
}

/// 外す・消す・前の中身を置き換える操作か (同じ操作では元に戻らないことがある)。
fn replaces_or_removes(action: &AiAction) -> bool {
    match action {
        AiAction::SetAttendance { on, .. }
        | AiAction::SetFavoriteSong { on, .. }
        | AiAction::SetMyPick { on, .. }
        | AiAction::PredictSong { on, .. }
        | AiAction::LikeSetlistSong { on, .. } => !on,
        AiAction::SetNotification { on, .. } => !on,
        AiAction::SetNote { .. } | AiAction::SetSeat { .. } | AiAction::RemovePersonalTag { .. } | AiAction::SetMastery { .. } => true,
        AiAction::AddPersonalTag { .. }
        | AiAction::CreatePlaylist { .. }
        | AiAction::AddToPlaylist { .. }
        | AiAction::AddExpense { .. }
        | AiAction::Open { .. }
        | AiAction::OpenList { .. }
        | AiAction::AddToCalendar { .. }
        | AiAction::PlaySongs { .. } => false,
    }
}

fn attendance_label(kind: &str) -> &'static str {
    match kind {
        "stream" => "配信",
        "live_viewing" => "ライブビューイング",
        _ => "現地",
    }
}

/// 操作ツールの呼び出し 1 件を検査して、一覧の 1 行にする。
///
/// Err は**モデルに返す**文言 (読んで引き直せるように、何が違うかを書く)。
pub fn plan(snap: &Snapshot, name: &str, args: &Value, ctx: PlanContext<'_>) -> Result<AiPlannedAction, String> {
    use AiActionReach::{Device, Screen, Shared};
    let on = on_arg(args)?;
    let toggled = |what: &str| if on { format!("{what}に入れる") } else { format!("{what}から外す") };
    match name {
        "set_attendance" => {
            let (show_id, target) = show_name(snap, text_arg(args, "show_id"))?;
            let attendance = match text_arg(args, "type") {
                "" => "live",
                t @ ("live" | "stream" | "live_viewing") => t,
                other => return Err(format!("type は live / stream / live_viewing のどれか: {other}")),
            };
            let label = attendance_label(attendance);
            let title = if on { format!("{label}参加を付ける") } else { format!("{label}参加を外す") };
            Ok(planned(AiAction::SetAttendance { show_id, attendance: attendance.into(), on }, Device, title, target))
        }
        "set_favorite_song" => {
            let (song_id, target) = song_title(snap, text_arg(args, "song_id"))?;
            Ok(planned(AiAction::SetFavoriteSong { song_id, on }, Device, toggled("お気に入り"), target))
        }
        "set_my_pick" => {
            let (idol_id, target) = entity(snap, "idol", text_arg(args, "idol_id"), &["idol"])?;
            Ok(planned(AiAction::SetMyPick { idol_id, on }, Device, toggled("担当"), target))
        }
        "set_note" => {
            let kind = text_arg(args, "kind");
            let (id, target) = entity(snap, kind, text_arg(args, "id"), &["song", "idol", "event", "show"])?;
            let text = clipped(text_arg(args, "text"), MAX_NOTE_CHARS, "メモ")?;
            let title = if text.is_empty() { "メモを消す".to_string() } else { format!("メモを「{text}」にする (前のメモは置き換わります)") };
            Ok(planned(AiAction::SetNote { entity: kind.into(), id, text }, Device, title, target))
        }
        "set_seat" => {
            let (show_id, target) = show_name(snap, text_arg(args, "show_id"))?;
            let text = clipped(text_arg(args, "text"), MAX_NAME_CHARS, "座席")?;
            let title = if text.is_empty() { "座席を消す".to_string() } else { format!("座席を「{text}」にする (前の座席は置き換わります)") };
            Ok(planned(AiAction::SetSeat { show_id, text }, Device, title, target))
        }
        "add_personal_tag" | "remove_personal_tag" => {
            let kind = text_arg(args, "kind");
            let (id, target) = entity(snap, kind, text_arg(args, "id"), &["idol", "unit"])?;
            let tag = clipped(text_arg(args, "name"), MAX_NAME_CHARS, "タグの名前")?;
            if tag.is_empty() {
                return Err("name が空です".into());
            }
            if name == "add_personal_tag" {
                let title = format!("自分用のタグ「{tag}」を付ける");
                Ok(planned(AiAction::AddPersonalTag { entity: kind.into(), id, name: tag }, Device, title, target))
            } else {
                let title = format!("自分用のタグ「{tag}」を外す");
                Ok(planned(AiAction::RemovePersonalTag { entity: kind.into(), id, name: tag }, Device, title, target))
            }
        }
        "create_playlist" | "add_to_playlist" => {
            let key = if name == "create_playlist" { "name" } else { "playlist_name" };
            let list = clipped(text_arg(args, key), MAX_NAME_CHARS, "プレイリストの名前")?;
            if list.is_empty() {
                return Err(format!("{key} が空です"));
            }
            let song_ids = songs(snap, args)?;
            let target = format!("{} 曲", song_ids.len());
            if name == "create_playlist" {
                let title = format!("プレイリスト「{list}」を作る");
                return Ok(planned(AiAction::CreatePlaylist { name: list, song_ids }, Device, title, target));
            }
            // どのプレイリストに足すかはここで決める (各 OS で名前を照らし合わせない)。
            let matches: Vec<&AiPlaylistRef> = ctx.playlists.iter().filter(|p| p.name.trim() == list).collect();
            match matches.as_slice() {
                [] => {
                    let title = format!("プレイリスト「{list}」を新しく作って入れる");
                    Ok(planned(AiAction::CreatePlaylist { name: list, song_ids }, Device, title, target))
                }
                [one] => {
                    let title = format!("プレイリスト「{list}」に足す");
                    Ok(planned(AiAction::AddToPlaylist { playlist_id: one.id.clone(), song_ids }, Device, title, target))
                }
                _ => Err(format!("「{list}」という名前のプレイリストが複数あって、どれに足すか決められません。利用者にそう伝える")),
            }
        }
        "add_expense" => {
            let date = text_arg(args, "date");
            let amount = args.get("amount").and_then(Value::as_i64).ok_or("amount は整数の円で")?;
            if ledger::validate_expense(date, amount).is_some() || amount <= 0 {
                return Err("date は YYYY-MM-DD、amount は 1 円以上の整数で".into());
            }
            let key = text_arg(args, "category");
            let info = ledger::expense_categories()
                .into_iter()
                .find(|c| c.key == key)
                .ok_or_else(|| format!("category が語彙にありません: {key}"))?;
            let (show_id, event_id, show_label) = match text_arg(args, "show_id") {
                "" => (None, None, None),
                id => {
                    let (show_id, label) = show_name(snap, id)?;
                    let event_id = snap.show(&show_id).map(|s| snap.events[s.event as usize].id.clone());
                    (Some(show_id), event_id, Some(label))
                }
            };
            let note = Some(clipped(text_arg(args, "note"), MAX_NOTE_CHARS, "メモ")?).filter(|n| !n.is_empty());
            let title = format!("収支に {} {} を足す", info.label, ledger::format_yen(amount));
            let target = show_label.map(|l| format!("{date} {l}")).unwrap_or_else(|| date.to_string());
            Ok(planned(
                AiAction::AddExpense { date: date.into(), category: info.category, amount, show_id, event_id, note },
                Device,
                title,
                target,
            ))
        }
        "open" => {
            let kind = text_arg(args, "kind");
            let (id, target) = entity(snap, kind, text_arg(args, "id"), &["song", "idol", "event", "show", "unit"])?;
            let section = match (kind, text_arg(args, "section")) {
                ("song", s @ ("history" | "lyrics")) => s,
                _ => "",
            };
            let title = match section {
                "history" => "披露履歴を開く",
                "lyrics" => "歌詞とコールを開く",
                _ => "開く",
            };
            Ok(planned(AiAction::Open { entity: kind.into(), id, section: section.into() }, Screen, title, target))
        }
        "play_songs" => {
            let song_ids = songs(snap, args)?;
            let target = format!("{} 曲", song_ids.len());
            Ok(planned(AiAction::PlaySongs { song_ids }, Screen, "続けて流す", target))
        }
        "set_mastery" => {
            let song_ids = songs(snap, args)?;
            let steps = ctx.mastery_labels.len() as i64;
            let level = args.get("level").and_then(Value::as_i64).ok_or("level は整数で")?;
            if !(0..=steps).contains(&level) {
                return Err(format!("level は 0 から {steps} まで"));
            }
            let title = match level {
                0 => "習熟度を未設定に戻す".to_string(),
                n => format!("習熟度を「{}」にする (前の段階は置き換わります)", ctx.mastery_labels[n as usize - 1]),
            };
            let target = match song_ids.as_slice() {
                [one] => song_title(snap, one)?.1,
                many => format!("{} 曲", many.len()),
            };
            Ok(planned(AiAction::SetMastery { song_ids, level: level as u32 }, Device, title, target))
        }
        "add_to_calendar" => {
            let (show_id, target) = show_name(snap, text_arg(args, "show_id"))?;
            Ok(planned(AiAction::AddToCalendar { show_id }, Device, "カレンダーに足す", target))
        }
        "set_notification" => {
            let (kind, label) = match text_arg(args, "kind") {
                k @ "oshi_birthday" => (k, "担当の誕生日"),
                k @ "live_week" => (k, "ライブの前"),
                k @ "ticket" => (k, "チケットの受付"),
                k @ "monday" => (k, "月曜のお知らせ"),
                other => return Err(format!("kind が語彙にありません: {other}")),
            };
            let title = if on { "通知をオンにする" } else { "通知をオフにする" };
            Ok(planned(AiAction::SetNotification { kind: kind.into(), on }, Device, title, label))
        }
        "open_list" => {
            let (list, label) = match text_arg(args, "list") {
                l @ "events" => (l, "ライブ"),
                l @ "songs" => (l, "楽曲"),
                l @ "idols" => (l, "アイドル"),
                other => return Err(format!("list は events / songs / idols のどれか: {other}")),
            };
            let query = clipped(text_arg(args, "query"), MAX_NAME_CHARS, "検索の語")?;
            let title = if query.is_empty() { "一覧を開く".to_string() } else { format!("一覧を開いて「{query}」で探す") };
            Ok(planned(AiAction::OpenList { list: list.into(), query }, Screen, title, label))
        }
        "predict_song" | "like_setlist_song" => {
            let (show_id, show) = show_name(snap, text_arg(args, "show_id"))?;
            let (song_id, song) = song_title(snap, text_arg(args, "song_id"))?;
            let target = format!("{song} — {show}");
            // 画面と同じ前提: 予想はこれからの公演、いいねは始まった公演。取り消しはいつでもできる。
            let date = snap.show(&show_id).map(|s| s.date.as_str()).unwrap_or("");
            if on && name == "predict_song" && !date.is_empty() && date < ctx.today_key {
                return Err("終わった公演のセトリは予想できません".into());
            }
            if on && name == "like_setlist_song" && (date.is_empty() || date > ctx.today_key) {
                return Err("まだ開かれていない公演のセトリには「いいね」できません".into());
            }
            if name == "predict_song" {
                let title = if on { "セトリ予想に 1 票入れる" } else { "セトリ予想の票を取り消す" };
                Ok(planned(AiAction::PredictSong { show_id, song_id, on }, Shared, title, target))
            } else {
                let title = if on { "セトリの曲に「いいね」を付ける" } else { "「いいね」を外す" };
                Ok(planned(AiAction::LikeSetlistSong { show_id, song_id, on }, Shared, title, target))
            }
        }
        other => Err(format!("知らない操作: {other}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    const CTX: PlanContext<'static> = PlanContext { today_key: "2026-11-16", playlists: &[], mastery_labels: &[] };

    fn first_ids(snap: &Snapshot) -> (String, String, String) {
        (snap.songs[0].id.clone(), snap.idols[0].id.clone(), snap.shows[0].id.clone())
    }

    #[test]
    fn 一覧の名前は重ならず_必須の引数は型に載っている() {
        let specs = catalog();
        let mut names: Vec<&str> = specs.iter().map(|s| s.name).collect();
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), specs.len());
        for spec in &specs {
            for key in spec.required {
                assert!(spec.properties.get(key).is_some(), "{} の {key}", spec.name);
            }
            assert!(is_action(spec.name));
        }
        assert!(!is_action("search"));
    }

    #[test]
    fn 実在する公演に参加を付ける() {
        let snap = bundle_snapshot();
        let (_, _, show) = first_ids(&snap);
        let p = plan(&snap, "set_attendance", &json!({ "show_id": show }), CTX).unwrap();
        assert_eq!(p.reach, AiActionReach::Device);
        assert_eq!(p.title, "現地参加を付ける");
        assert!(!p.target.is_empty());
        assert_eq!(p.action, AiAction::SetAttendance { show_id: show.clone(), attendance: "live".into(), on: true });

        let off = plan(&snap, "set_attendance", &json!({ "show_id": show, "type": "stream", "on": false }), CTX).unwrap();
        assert_eq!(off.title, "配信参加を外す");
        assert!(plan(&snap, "set_attendance", &json!({ "show_id": show, "type": "online" }), CTX).is_err());
    }

    #[test]
    fn 名前から組み立てた_id_は通さない() {
        let snap = bundle_snapshot();
        assert!(plan(&snap, "set_favorite_song", &json!({ "song_id": "ready" }), CTX).is_err());
        assert!(plan(&snap, "set_my_pick", &json!({ "idol_id": "天海春香" }), CTX).is_err());
        assert!(plan(&snap, "open", &json!({ "kind": "venue", "id": "x" }), CTX).is_err());
        assert!(plan(&snap, "delete_playlist", &json!({}), CTX).is_err());
    }

    #[test]
    fn 曲の列は実在する曲だけにして重複を除く() {
        let snap = bundle_snapshot();
        let (song, _, _) = first_ids(&snap);
        let p = plan(&snap, "create_playlist", &json!({ "name": "予習", "song_ids": [song, "nope", song] }), CTX).unwrap();
        assert_eq!(p.action, AiAction::CreatePlaylist { name: "予習".into(), song_ids: vec![song] });
        assert_eq!(p.target, "1 曲");
        assert!(plan(&snap, "play_songs", &json!({ "song_ids": ["nope"] }), CTX).is_err());
        assert!(plan(&snap, "create_playlist", &json!({ "name": "", "song_ids": [] }), CTX).is_err());
    }

    #[test]
    fn 支出は金額と日付と費目を確かめる() {
        let snap = bundle_snapshot();
        let (_, _, show) = first_ids(&snap);
        let p = plan(
            &snap,
            "add_expense",
            &json!({ "date": "2026-11-15", "category": "ticket", "amount": 9800, "show_id": show }),
            CTX,
        )
        .unwrap();
        let AiAction::AddExpense { amount, show_id, event_id, category, .. } = p.action else { panic!("支出でない") };
        assert_eq!((amount, category), (9800, ExpenseCategory::Ticket));
        assert_eq!(show_id.as_deref(), Some(show.as_str()));
        assert!(event_id.is_some());
        assert!(p.title.contains("9,800"), "{}", p.title);

        assert!(plan(&snap, "add_expense", &json!({ "date": "2026-11-15", "category": "ticket", "amount": 0 }), CTX).is_err());
        assert!(plan(&snap, "add_expense", &json!({ "date": "きのう", "category": "ticket", "amount": 100 }), CTX).is_err());
        assert!(plan(&snap, "add_expense", &json!({ "date": "2026-11-15", "category": "チケット", "amount": 100 }), CTX).is_err());
    }

    #[test]
    fn サーバに届く操作はそう札が付く() {
        let snap = bundle_snapshot();
        let (song, _, show) = first_ids(&snap);
        // 予想はこれからの公演だけ (取り消しはいつでも)。
        let future = PlanContext { today_key: "1990-01-01", playlists: &[], mastery_labels: &[] };
        let vote = plan(&snap, "predict_song", &json!({ "show_id": show, "song_id": song }), future).unwrap();
        assert_eq!(vote.reach, AiActionReach::Shared);
        assert!(!vote.preselected);
        let far = PlanContext { today_key: "2999-01-01", playlists: &[], mastery_labels: &[] };
        assert!(plan(&snap, "predict_song", &json!({ "show_id": show, "song_id": song }), far).is_err());
        assert!(plan(&snap, "predict_song", &json!({ "show_id": show, "song_id": song, "on": false }), far).is_ok());
        assert!(plan(&snap, "like_setlist_song", &json!({ "show_id": show, "song_id": song }), future).is_err());
        let open = plan(&snap, "open", &json!({ "kind": "song", "id": song, "section": "lyrics" }), CTX).unwrap();
        assert_eq!(open.reach, AiActionReach::Screen);
        assert_eq!(open.action, AiAction::Open { entity: "song".into(), id: song, section: "lyrics".into() });
    }

    #[test]
    fn 外す_置き換える操作は初めから選ばない() {
        let snap = bundle_snapshot();
        let (song, _, show) = first_ids(&snap);
        assert!(plan(&snap, "set_favorite_song", &json!({ "song_id": song }), CTX).unwrap().preselected);
        assert!(!plan(&snap, "set_favorite_song", &json!({ "song_id": song, "on": false }), CTX).unwrap().preselected);
        let note = plan(&snap, "set_note", &json!({ "kind": "show", "id": show, "text": "最高だった" }), CTX).unwrap();
        assert!(!note.preselected && note.title.contains("置き換わります"));
        // 真偽値でない on は、付ける側に倒さない。
        assert!(plan(&snap, "set_attendance", &json!({ "show_id": show, "on": "false" }), CTX).is_err());
    }

    #[test]
    fn 足す先のプレイリストは名前からコアが決める() {
        let snap = bundle_snapshot();
        let (song, _, _) = first_ids(&snap);
        let lists = [
            AiPlaylistRef { id: "p1".into(), name: "予習".into() },
            AiPlaylistRef { id: "p2".into(), name: "かぶり".into() },
            AiPlaylistRef { id: "p3".into(), name: "かぶり".into() },
        ];
        let ctx = PlanContext { today_key: "2026-11-16", playlists: &lists, mastery_labels: &[] };
        let args = |name: &str| json!({ "playlist_name": name, "song_ids": [song] });
        let hit = plan(&snap, "add_to_playlist", &args("予習"), ctx).unwrap();
        assert_eq!(hit.action, AiAction::AddToPlaylist { playlist_id: "p1".into(), song_ids: vec![song.clone()] });
        let new = plan(&snap, "add_to_playlist", &args("復習"), ctx).unwrap();
        assert!(matches!(new.action, AiAction::CreatePlaylist { .. }) && new.title.contains("新しく作って"));
        assert!(plan(&snap, "add_to_playlist", &args("かぶり"), ctx).is_err());
    }

    #[test]
    fn 習熟度は利用者の段数まで_設定と一覧も積める() {
        let snap = bundle_snapshot();
        let (song, _, show) = first_ids(&snap);
        let labels = ["聴いた".to_string(), "歌える".to_string()];
        let ctx = PlanContext { today_key: "2026-11-16", playlists: &[], mastery_labels: &labels };
        let p = plan(&snap, "set_mastery", &json!({ "song_ids": [song], "level": 2 }), ctx).unwrap();
        assert!(p.title.contains("歌える") && !p.preselected);
        assert!(plan(&snap, "set_mastery", &json!({ "song_ids": [song], "level": 3 }), ctx).is_err());
        assert!(plan(&snap, "set_mastery", &json!({ "song_ids": [song], "level": 1 }), CTX).is_err());

        let cal = plan(&snap, "add_to_calendar", &json!({ "show_id": show }), CTX).unwrap();
        assert!(cal.preselected && cal.reach == AiActionReach::Device);
        let off = plan(&snap, "set_notification", &json!({ "kind": "monday", "on": false }), CTX).unwrap();
        assert!(!off.preselected && off.target == "月曜のお知らせ");
        assert!(plan(&snap, "set_notification", &json!({ "kind": "all" }), CTX).is_err());
        let list = plan(&snap, "open_list", &json!({ "list": "songs", "query": "READY" }), CTX).unwrap();
        assert_eq!(list.action, AiAction::OpenList { list: "songs".into(), query: "READY".into() });
        assert!(plan(&snap, "open_list", &json!({ "list": "polls" }), CTX).is_err());
    }
}
