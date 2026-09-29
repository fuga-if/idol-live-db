//! 投入ドラフトの書き出しと検証の実行。
//!
//! 組み立て規則は `agent::proposal`。ここは「ファイルに書く」「`tools/apply_data.py
//! --check` を動かして結果を読む」だけを持つ。検証規則を Rust に写経しない —
//! 写経すると apply 側と二重管理になり、必ず片方だけ書き換わる。
//!
//! ## 子プロセスの stdio は必ず隔離する (RedTeam C4)
//!
//! `tools/apply_data.py` は `--check` の最中でも人間向けの案内行を stdout に書く
//! (例: `db/master.sql から master.sqlite を生成しました`, `tools/apply_data.py:51`)。
//! MCP サーバは stdio トランスポートで JSON-RPC を標準入出力に流すので、この子プロセスの
//! stdout をサーバ自身の stdout に継承させると、この 1 行が JSON-RPC のメッセージ境界に
//! 混ざってクライアントが黙って壊れる。だから `run_apply_check` は
//! `Stdio::piped()` を明示し (`Command::output()` は既定でも piped だが、ここでは
//! 「継承させない」という意図をコードで固定する)、stdin も `Stdio::null()` にして
//! python 側が入力待ちでハングする経路自体を潰す。シェルは経由しない
//! (`sh -c` を使わず `Command::new("python3")` に `.arg()` で個別に渡すので、
//! `--only` の値に何が入っていてもシェル展開/注入の余地が無い)。

use super::Ctx;
use crate::agent::tools::{args, ToolError};
use crate::agent::proposal::{self, ProposalDraft, ProposalKind};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// 書き込みツールを実行する (ドラフト作成 → 書き出し → --check)。
///
/// `check_proposals` だけはドラフトを組まない (既存の `data/` を検証し直すだけ) ので、
/// `proposal::build_proposal` を経由せずここで直接 `--check` を回す。
pub fn run(ctx: &Ctx, name: &str, args: &Value) -> Result<Value, ToolError> {
    if name == "check_proposals" {
        return run_check_proposals(ctx, args);
    }
    let draft = proposal::build_proposal(name, args, &ctx.today_key())?;
    write_and_check(ctx, &draft)
}

fn run_check_proposals(ctx: &Ctx, a: &Value) -> Result<Value, ToolError> {
    match args::str_opt(a, "file") {
        Some(file) => Ok(json!({ "check": run_apply_check(ctx, Some(&file)) })),
        None => Ok(run_check_all(ctx)),
    }
}

/// `data/README.md` が挙げている投入ディレクトリ + `fixes`。「いま data/ にある
/// 全ドラフト」(人間の PR 分も含む) を列挙するためだけのディレクトリ一覧で、
/// 値の妥当性判定は一切持たない (単なるファイル列挙)。
const DATA_KIND_DIRS: &[&str] = &[
    "songs", "setlists", "events", "idols", "units", "unit_versions", "creators", "costumes", "fixes",
];

/// `data/<kind>/*.json` (`_` 始まりのテンプレートは除く) を列挙する。
fn list_pending_files(repo_root: &Path) -> Vec<String> {
    let mut files = Vec::new();
    for kind in DATA_KIND_DIRS {
        let dir = repo_root.join("data").join(kind);
        let Ok(entries) = std::fs::read_dir(&dir) else { continue };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else { continue };
            if name.starts_with('_') {
                continue; // _template.json 等
            }
            files.push(name.to_string());
        }
    }
    files.sort();
    files
}

/// `data/` 配下の未反映ドラフトを **1 件ずつ** `--only` で検証する。
///
/// RedTeam H2: `--only` を付けずに `tools/apply_data.py --check` を走らせると、
/// クリーンなツリーでも push 済みの残骸で数百件の無関係な問題が返り、LLM が
/// 「自分の提案が無効だった」と誤認する (`docs/DATA_PIPELINE.md` に実測 975 件の例がある)。
/// この関数を含め、`run_apply_check` を `only_file: None` で呼ぶ経路はこのファイルに
/// 一切作らない。
///
/// RedTeam M5: 1 件ごとに python の起動と DB オープンをやり直すので実測 0.29 秒/件かかる。
/// `data/` に実測 69 件ある状態で無制限に回すと 20 秒を超え、MCP クライアントのツール
/// 呼び出しタイムアウト (一般に 30〜60 秒) に触れる。`proposal::MAX_AUTO_CHECK_FILES`
/// で打ち切り、残りは `total_pending` と `message` で「未検証」だとはっきり返す
/// (打ち切ったことを黙らない)。
fn run_check_all(ctx: &Ctx) -> Value {
    let mut files = list_pending_files(&ctx.repo_root);
    if files.is_empty() {
        return json!({
            "files_checked": 0,
            "results": [],
            "message": "data/ に未反映のドラフトはありません。",
        });
    }
    let total = files.len();
    let capped = total > proposal::MAX_AUTO_CHECK_FILES;
    files.truncate(proposal::MAX_AUTO_CHECK_FILES);

    let results: Vec<Value> = files
        .iter()
        .map(|f| json!({ "file": f, "check": run_apply_check(ctx, Some(f)) }))
        .collect();
    let all_ok = results.iter().all(|r| r["check"]["ok"].as_bool().unwrap_or(false));

    let mut out = json!({
        "files_checked": results.len(),
        "total_pending": total,
        "all_ok": all_ok,
        "results": results,
    });
    if capped {
        let remaining = total - proposal::MAX_AUTO_CHECK_FILES;
        out["message"] = json!(format!(
            "data/ に {total} 件のドラフトがあるうち先頭 {} 件だけ検証しました。残り {remaining} 件は \
             未検証です。特定のファイルを確かめるには file 引数を指定してください。",
            proposal::MAX_AUTO_CHECK_FILES,
        ));
    }
    out
}

/// ドラフトを書き出し、そのファイルだけを `--check --only` にかけて結果を返す。
fn write_and_check(ctx: &Ctx, draft: &ProposalDraft) -> Result<Value, ToolError> {
    let dir = prepare_kind_dir(&ctx.repo_root, draft.kind)?;
    let final_name = reserve_file_name(&dir, &draft.file_name)?;
    let abs_path = dir.join(&final_name);

    std::fs::write(&abs_path, &draft.contents)
        .map_err(|e| ToolError::Failed(format!("ドラフトを書き込めません ({}): {e}", abs_path.display())))?;

    let check = run_apply_check(ctx, Some(&final_name));
    let result = json!({
        "draft": {
            "path": format!("data/{}/{final_name}", draft.kind.dir()),
            "summary": draft.summary,
        },
        "check": check,
        "notice": "これは提案 (ドラフト) です。data/ に書いただけで、まだ何も反映されていません。\
            反映にはオーナーが手元で `tools/apply_data.py --apply --push` を実行する必要があります。",
        // RedTeam M4: 既知ホストのときだけ省くと「上手な捏造ほど無警告」になるので、
        // ここでは常に draft.source_advisory (常に非空) をそのまま載せる。
        "source_advisory": draft.source_advisory,
    });
    Ok(result)
}

/// `data/<kind>/` を用意し、実体が想定外の場所を指していないか確かめて返す。
///
/// RedTeam M7: `agent::proposal` 側で `ProposalDraft::file_name` はパス区切りを
/// 含まない安全な値であることを検証済みだが (`is_valid_slug`)、経路の組み立てそのものは
/// 最後の砦としてここでも検算する。`data/<kind>` がシンボリックリンク等で `data/` の外を
/// 指すよう細工されていたら、`canonicalize` した実体の親ディレクトリが `data/` の実体と
/// 一致しなくなるので、そこで弾く。
///
/// RedTeam L4: それだけでは **`data/` 自体**がシンボリックリンクで外を指しているケースを
/// すり抜ける (`canon_data` が既にリダイレクト先を指していて、`canon_dir` もその配下に
/// 矛盾なく収まってしまうため)。`canon_data` が `repo_root` の実体の配下にあることも
/// 併せて確かめて閉じる。
fn prepare_kind_dir(repo_root: &Path, kind: ProposalKind) -> Result<PathBuf, ToolError> {
    let dir = repo_root.join("data").join(kind.dir());
    std::fs::create_dir_all(&dir)
        .map_err(|e| ToolError::Failed(format!("ディレクトリを作れません ({}): {e}", dir.display())))?;

    let canon_repo_root = repo_root
        .canonicalize()
        .map_err(|e| ToolError::Failed(format!("repo_root を解決できません: {e}")))?;
    let canon_data = repo_root
        .join("data")
        .canonicalize()
        .map_err(|e| ToolError::Failed(format!("data/ を解決できません: {e}")))?;
    if !canon_data.starts_with(&canon_repo_root) {
        return Err(ToolError::Failed(format!(
            "data/ の実体がリポジトリの外を指しています ({})",
            canon_data.display(),
        )));
    }
    let canon_dir = dir
        .canonicalize()
        .map_err(|e| ToolError::Failed(format!("ディレクトリを解決できません ({}): {e}", dir.display())))?;
    if canon_dir.parent() != Some(canon_data.as_path()) {
        return Err(ToolError::Failed(format!(
            "data/{} の実体が想定外の場所を指しています ({})",
            kind.dir(),
            canon_dir.display(),
        )));
    }
    Ok(dir)
}

/// 既存ファイルを上書きしない。同名があれば `_2` `_3`... と連番を足して空いている
/// ファイル名を探す。
///
/// **なぜ `BadArgs` で断らず連番にするか**: ファイル名は `agent::proposal` が
/// (今日の日付 + kind タグ + id の slug から) 完全に決めていて、呼び手 (LLM) は
/// ファイル名を指定できない。ここで機械的に拒否すると、LLM 側に「別の名前で
/// 再試行する」余地が無いまま行き詰まる。同じ日に同じ id を 2 度提案するのは
/// 訂正や別ソースでの再提案として普通に起こりうるので、連番で両方を残して
/// 人間のレビューに委ねる。
fn reserve_file_name(dir: &Path, file_name: &str) -> Result<String, ToolError> {
    // domain 側 (`is_valid_slug`) で検証済みだが、書き込み直前でももう一度だけ検算する
    // (最後の砦。ここを通らない限り `dir.join(file_name)` は 1 階層より深くならない)。
    if file_name.is_empty() || file_name.contains('/') || file_name.contains('\\') {
        return Err(ToolError::Failed(format!("不正なファイル名です: {file_name:?}")));
    }
    if !dir.join(file_name).exists() {
        return Ok(file_name.to_string());
    }
    let path = Path::new(file_name);
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("draft");
    let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("json");
    for n in 2..1000 {
        let candidate = format!("{stem}_{n}.{ext}");
        if !dir.join(&candidate).exists() {
            return Ok(candidate);
        }
    }
    Err(ToolError::Failed(format!(
        "{file_name} の連番候補 (_2〜_999) が全部埋まっています。data/ を整理してください。"
    )))
}

/// `tools/apply_data.py --check` を `ctx.repo_root` で実行する。`only_file` を渡すと
/// `--only <ファイル名>` を付ける (パスではなくファイル名で照合される: `docs/DATA_PIPELINE.md`)。
/// **このファイル内で `only_file: None` を渡すのは `run_check_all` が空だったとき用の
/// 早期リターン以外に存在しない** (H2)。
///
/// stdout/stderr は `Stdio::piped()` で明示的に隔離し、`Output` として読み取るだけなので
/// MCP サーバ自身の標準出力には一切流れない (このファイル冒頭の注記を参照)。stdin は
/// `Stdio::null()` にして python 側の入力待ちハングを構造的に無くす。引数は `.arg()` で
/// 個別に渡し、シェルは経由しない。
fn run_apply_check(ctx: &Ctx, only_file: Option<&str>) -> Value {
    let mut cmd = Command::new("python3");
    cmd.arg("tools/apply_data.py").arg("--check");
    if let Some(f) = only_file {
        cmd.arg("--only").arg(f);
    }
    cmd.current_dir(&ctx.repo_root);
    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    match cmd.output() {
        Ok(out) => json!({
            "ran": true,
            "exit_code": out.status.code(),
            "ok": out.status.success(),
            "stdout": String::from_utf8_lossy(&out.stdout),
            "stderr": String::from_utf8_lossy(&out.stderr),
        }),
        Err(e) => json!({
            "ran": false,
            "reason": format!("python3 tools/apply_data.py --check を実行できませんでした: {e}"),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::snapshot::Snapshot;
    use serde_json::json;
    use std::sync::atomic::{AtomicU64, Ordering};

    /// リポジトリの `data/` を汚さないよう、テストごとに使い捨てのディレクトリを
    /// `repo_root` に見立てる (`TempRepo`) か、symlink 攻撃のテストで「外」として
    /// 使う (`unique_temp_dir` 単体)。`tempfile` crate はこの crate の依存に無い
    /// (Cargo.toml を書き換えると並行するビルドと衝突するため足さない) ので
    /// `std::env::temp_dir()` の下に自前でユニークな名前を切って使う。
    fn unique_temp_dir(tag: &str) -> PathBuf {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!("imas_proposal_io_{tag}_{pid}_{n}_{nanos}"));
        std::fs::create_dir_all(&dir).expect("temp dir を作れない");
        dir
    }

    struct TempRepo {
        root: PathBuf,
    }

    impl TempRepo {
        fn new() -> Self {
            TempRepo { root: unique_temp_dir("test") }
        }
    }

    impl Drop for TempRepo {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.root);
        }
    }

    fn ctx_for(repo: &TempRepo) -> Ctx {
        Ctx {
            db_path: repo.root.join("master.sqlite"),
            repo_root: repo.root.clone(),
            today_override: Some("2026-09-19".to_string()),
            allow_write: true,
        }
    }

    fn song_args(id: &str) -> Value {
        json!({
            "id": id, "title": "テスト曲", "brand_id": "ml", "song_type": "unit",
            "original_singers": ["ml_idol_a"],
            "source": "https://example.com/news",
            "source_quote": "2026年9月19日発売",
        })
    }

    #[test]
    fn 同じファイル名に2度書くと連番になり既存ファイルを上書きしない() {
        let repo = TempRepo::new();
        let ctx = ctx_for(&repo);

        let first = run(&ctx, "propose_song", &song_args("ml_dup_test")).unwrap();
        let first_path = first["draft"]["path"].as_str().unwrap().to_string();
        std::fs::write(repo.root.join(&first_path), "MARKER-ORIGINAL").unwrap();

        let second = run(&ctx, "propose_song", &song_args("ml_dup_test")).unwrap();
        let second_path = second["draft"]["path"].as_str().unwrap().to_string();

        assert_ne!(first_path, second_path, "同名を上書きしてはいけない");
        assert_eq!(second_path, "data/songs/20260919_song_ml_dup_test_2.json");
        // 1 件目 (書き換えたマーカー) がそのまま残っている = 上書きされていない
        let untouched = std::fs::read_to_string(repo.root.join(&first_path)).unwrap();
        assert_eq!(untouched, "MARKER-ORIGINAL");
    }

    #[test]
    fn 連番になってもsummaryは古い_存在しない_ファイル名を案内しない() {
        // QA 実測バグ: draft.path は連番後の実ファイル (..._2.json) を正しく指すのに、
        // draft.summary が連番化される前の (存在しない) ファイル名の文言を含んでいた。
        // 修正は「summary からファイル名/パスを完全に落とす」方向 (proposal::
        // ProposalDraft::summary の doc コメント参照) なので、ここでは summary に
        // ファイル名の痕跡が一切無いこと、かつ path が実在するファイルを指すことを固定する。
        let repo = TempRepo::new();
        let ctx = ctx_for(&repo);

        let first = run(&ctx, "propose_song", &song_args("ml_dup_summary_test")).unwrap();
        let second = run(&ctx, "propose_song", &song_args("ml_dup_summary_test")).unwrap();

        let first_path = first["draft"]["path"].as_str().unwrap().to_string();
        let second_path = second["draft"]["path"].as_str().unwrap().to_string();
        assert_ne!(first_path, second_path);
        assert!(second_path.ends_with("_2.json"), "2 件目は連番化されるはず: {second_path}");

        let summary = second["draft"]["summary"].as_str().unwrap();
        assert!(!summary.contains(".json"), "summary にファイル名が混ざっている: {summary}");
        assert!(!summary.contains("data/songs/"), "summary にパスが混ざっている: {summary}");

        // path が指す実ファイルが本当にそこにある (誤案内でないことの本体側の確認)。
        assert!(repo.root.join(&second_path).exists());
    }

    #[test]
    fn source_無しは_ファイルを書かずに_bad_args_を返す() {
        let repo = TempRepo::new();
        let ctx = ctx_for(&repo);
        let a = json!({
            "id": "ml_no_source", "title": "テスト曲", "brand_id": "ml",
            "song_type": "unit", "original_singers": ["ml_idol_a"],
        });
        let err = run(&ctx, "propose_song", &a).unwrap_err();
        assert!(matches!(err, ToolError::BadArgs(_)));
        // BadArgs で止まった以上、ファイルは 1 つも書かれていないはず。
        assert!(!repo.root.join("data/songs").exists());
    }

    #[test]
    fn check_proposals_はファイルを書かない() {
        let repo = TempRepo::new();
        let ctx = ctx_for(&repo);
        let result = run(&ctx, "check_proposals", &json!({})).unwrap();
        assert!(result.get("draft").is_none());
        assert!(!repo.root.join("data").exists());
    }

    #[test]
    fn check_proposals_は省略時に保留中ファイルを1件ずつ検証する() {
        let repo = TempRepo::new();
        let ctx = ctx_for(&repo);
        run(&ctx, "propose_song", &song_args("ml_pending_a")).unwrap();
        run(&ctx, "propose_song", &song_args("ml_pending_b")).unwrap();

        let result = run(&ctx, "check_proposals", &json!({})).unwrap();
        assert_eq!(result["files_checked"], 2);
        let results = result["results"].as_array().unwrap();
        assert_eq!(results.len(), 2);
        for r in results {
            let file = r["file"].as_str().unwrap();
            assert!(file.ends_with(".json"));
            // 個別の結果であって、まとめて回した形跡が無いことだけ確認 (H2)。
            assert!(r["check"].get("ran").is_some());
        }
    }

    #[test]
    #[cfg(unix)]
    fn kind_ディレクトリがシンボリックリンクで外を指していると書き込みを拒否する() {
        use std::os::unix::fs::symlink;
        let repo = TempRepo::new();
        let outside = unique_temp_dir("outside_kind");
        std::fs::create_dir_all(repo.root.join("data")).unwrap();
        symlink(&outside, repo.root.join("data").join("songs")).unwrap();

        let ctx = ctx_for(&repo);
        let err = run(&ctx, "propose_song", &song_args("ml_symlink_test")).unwrap_err();
        assert!(matches!(err, ToolError::Failed(_)), "symlink 越しの書き込みは拒否されるはず: {err:?}");

        let _ = std::fs::remove_dir_all(&outside);
    }

    #[test]
    #[cfg(unix)]
    fn data_自体がシンボリックリンクで外を指していると書き込みを拒否する() {
        // RedTeam L4: 上の kind ディレクトリだけの検算だと、data/ 自体が丸ごと
        // 外を指しているケース (canon_data が既にリダイレクト先で、canon_dir がその
        // 配下に矛盾なく収まってしまう) をすり抜ける。
        use std::os::unix::fs::symlink;
        let repo = TempRepo::new();
        let outside = unique_temp_dir("outside_data");
        symlink(&outside, repo.root.join("data")).unwrap();

        let ctx = ctx_for(&repo);
        let err = run(&ctx, "propose_song", &song_args("ml_data_symlink_test")).unwrap_err();
        assert!(matches!(err, ToolError::Failed(_)), "data/ 自体の symlink 越しも拒否されるはず: {err:?}");

        let _ = std::fs::remove_dir_all(&outside);
    }

    #[test]
    fn check_proposals_は上限を超えたら打ち切って残り件数を報告する() {
        let repo = TempRepo::new();
        let ctx = ctx_for(&repo);
        let dir = repo.root.join("data").join("songs");
        std::fs::create_dir_all(&dir).unwrap();
        let total = proposal::MAX_AUTO_CHECK_FILES + 5;
        for i in 0..total {
            std::fs::write(dir.join(format!("dummy_{i:03}.json")), "{}").unwrap();
        }

        let result = run(&ctx, "check_proposals", &json!({})).unwrap();
        assert_eq!(result["files_checked"], proposal::MAX_AUTO_CHECK_FILES);
        assert_eq!(result["total_pending"], total);
        let message = result["message"].as_str().expect("上限超過なので message があるはず");
        assert!(message.contains("残り 5 件"));
    }

    #[test]
    fn dispatch_経由でも書き込みツールとして振り分けられる() {
        let repo = TempRepo::new();
        let ctx = ctx_for(&repo);
        let snap = Snapshot::default();
        let result = super::super::dispatch(&ctx, &snap, "propose_song", &song_args("ml_dispatch_test"));
        assert!(result.is_ok());
    }

    #[test]
    fn allow_write_falseだと未知のツール扱いになる() {
        let repo = TempRepo::new();
        let mut ctx = ctx_for(&repo);
        ctx.allow_write = false;
        let snap = Snapshot::default();
        let err = super::super::dispatch(&ctx, &snap, "propose_song", &song_args("ml_blocked_test")).unwrap_err();
        assert_eq!(err, ToolError::UnknownTool("propose_song".to_string()));
    }
}
