//! アイドルライブ DB を LLM から引くための MCP サーバ / CLI。
//!
//! 本体は `imas_core::agent`。ここは引数を読んで呼ぶだけにしてある
//! (ロジックを bin に置くとテストから触れないため)。
//!
//! ```text
//! imas-mcp --stdio [--db <master.sqlite>] [--repo-root <dir>] [--today <Y-m-d>] [--read-only]
//! imas-mcp <tool> [引数...] [--db ...]
//! imas-mcp tools [--json]
//! ```
//!
//! 終了コード: 0=成功 / 1=引数エラー / 2=DB エラー / 3=ツール実行エラー。

use imas_core::agent::{cli, stdio, Ctx};
use imas_core::outbound::sqlite_loader::load_snapshot;
use std::path::PathBuf;
use std::time::Instant;

const USAGE: &str = "\
使い方:
  imas-mcp --stdio [オプション]      MCP サーバとして起動 (stdin/stdout の行区切り JSON-RPC)
  imas-mcp <tool> [引数...]          ツールを 1 回実行して結果を stdout に書く
  imas-mcp tools [--json]            使えるツールの一覧

引数の渡し方 (<tool> 実行時):
  --json '{\"query\":\"春日未来\"}'      ツール引数をまとめて JSON で渡す
  --query 春日未来 --limit 5         --key value の組で渡す (同じキーの複数回は配列)

オプション (共通):
  --db <path>          読む master.sqlite (既定: <repo-root>/ImasLiveDB/Resources/master.sqlite)
  --repo-root <dir>    リポジトリルート (既定: カレントから上に辿って .git があるところ)
  --today <Y-m-d>      JST の「今日」を固定する (既定: 現在時刻から JST で求める)
  --read-only          書き込み (ドラフト作成) ツールを出さない (既定は書き込み可)
";

#[derive(Default)]
struct Opts {
    stdio: bool,
    read_only: bool,
    db: Option<PathBuf>,
    repo_root: Option<PathBuf>,
    today: Option<String>,
}

fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let (opts, rest) = match parse_argv(argv) {
        Ok(v) => v,
        Err(msg) => {
            eprint!("{USAGE}");
            eprintln!("imas-mcp: {msg}");
            std::process::exit(1);
        }
    };

    let Some(repo_root) = opts.repo_root.clone().or_else(find_repo_root) else {
        eprint!("{USAGE}");
        eprintln!("imas-mcp: リポジトリルート (.git) が見つかりません。--repo-root で指定してください");
        std::process::exit(1);
    };

    if !opts.stdio && rest.is_empty() {
        eprint!("{USAGE}");
        eprintln!("imas-mcp: --stdio か、実行するツール名 (または tools) が要ります");
        std::process::exit(1);
    }

    let db_path = opts
        .db
        .clone()
        .unwrap_or_else(|| repo_root.join("ImasLiveDB/Resources/master.sqlite"));

    // `Ctx::today_key()` が呼ぶたびに現在時刻から計算する (H9)。`--today` はテスト・
    // 固定運用のための上書きなので、そのまま `today_override` に渡すだけでよい。
    let ctx = Ctx {
        db_path: db_path.clone(),
        repo_root,
        today_override: opts.today.clone(),
        allow_write: !opts.read_only,
    };

    let Some(db_path_str) = db_path.to_str() else {
        eprintln!("imas-mcp: --db のパスが UTF-8 として読めません: {}", db_path.display());
        std::process::exit(2);
    };

    // `master.sqlite` は gitignore の生成物で、clone 直後や CI では存在しない。
    // 読み込み失敗の一般エラーだけだと原因が伝わらないので、無い場合は作り方を案内する。
    if !db_path.exists() {
        eprintln!(
            "imas-mcp: DB が見つかりません: {}\n  master.sqlite はリポジトリに同梱していない生成物です。\n  リポジトリルートで `bash tools/build_db.sh` を実行してから、もう一度お試しください。",
            db_path.display()
        );
        std::process::exit(2);
    }

    // 10MB 超の DB を読むので起動時に 1 回だけ読み、以降 (特に --stdio のループ中) は
    // 使い回す。CloudKit 同期後の再読み込みはこのプロセスの再起動で行う想定
    // (MCP サーバは 1 プロセス = 1 スナップショットの寿命)。
    let load_started = Instant::now();
    let snap = match load_snapshot(db_path_str) {
        Ok(snap) => snap,
        Err(e) => {
            eprintln!("imas-mcp: DB の読み込みに失敗 ({db_path_str}): {e}");
            std::process::exit(2);
        }
    };
    eprintln!(
        "imas-mcp: {} を読み込み完了 (曲{}件 アイドル{}件 イベント{}件, {:.0}ms)",
        db_path_str,
        snap.songs.len(),
        snap.idols.len(),
        snap.events.len(),
        load_started.elapsed().as_secs_f64() * 1000.0,
    );

    if opts.stdio {
        if let Err(e) = stdio::serve(&ctx, &snap) {
            eprintln!("imas-mcp: stdio 入出力エラー: {e}");
            std::process::exit(2);
        }
        return;
    }

    if let Err(e) = cli::run(&ctx, &snap, &rest) {
        eprintln!("imas-mcp: {e}");
        std::process::exit(3);
    }
}

/// 認識したオプションを `Opts` に、残りをツール呼び出し用の引数列 (`rest`) に振り分ける。
/// `--db` 等は `<tool>` の前後どちらに書いても拾えるよう、位置を問わず 1 パスで抜く。
fn parse_argv(argv: Vec<String>) -> Result<(Opts, Vec<String>), String> {
    let mut opts = Opts::default();
    let mut rest = Vec::new();
    let mut it = argv.into_iter();
    while let Some(flag) = it.next() {
        match flag.as_str() {
            "--stdio" => opts.stdio = true,
            "--read-only" => opts.read_only = true,
            "--db" => {
                let v = it.next().ok_or("--db に値がありません")?;
                opts.db = Some(PathBuf::from(v));
            }
            "--repo-root" => {
                let v = it.next().ok_or("--repo-root に値がありません")?;
                opts.repo_root = Some(PathBuf::from(v));
            }
            "--today" => {
                opts.today = Some(it.next().ok_or("--today に値がありません")?);
            }
            "-h" | "--help" => {
                print!("{USAGE}");
                std::process::exit(0);
            }
            other => rest.push(other.to_string()),
        }
    }
    Ok((opts, rest))
}

/// カレントディレクトリから上へ辿って `.git` があるところをリポジトリルートとみなす。
fn find_repo_root() -> Option<PathBuf> {
    let mut dir = std::env::current_dir().ok()?;
    loop {
        if dir.join(".git").exists() {
            return Some(dir);
        }
        if !dir.pop() {
            return None;
        }
    }
}

