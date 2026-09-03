//! Web 出面用 JSON エクスポータの CLI。
//!
//! 本体は `imas_core::web_export`。ここは引数を読んで呼ぶだけにしてある
//! (ロジックを bin に置くとテストから触れないため)。
//!
//! ```text
//! cargo run --release --features web-export --bin web-export -- \
//!     --sql ../db/master.sql --out ../web/data
//! ```
//!
//! 終了コード: 0=成功 / 1=引数エラー / 2=DB エラー / 3=出力エラー / 4=不変条件違反。

use imas_core::web_export::{run, Args, WebExportError};
use std::path::PathBuf;

const USAGE: &str = "\
使い方:
  web-export --sql <master.sql> --out <dir>     db/master.sql から出力する
  web-export --db  <master.sqlite> --out <dir>  既存の .sqlite から出力する
  web-export --emit-fixture <dir>               各 DTO の代表値だけを書き出す
  web-export --fixture-check <dir>              手書きフィクスチャを DTO で検証する

任意:
  --work-db <path>   --sql のときの中間 DB (既定: <out>/../.cache/master-web.sqlite)
  --today <Y-m-d>    JST の「今日」を固定する (省略時は現在時刻から求める)
  --pretty           整形して書く (既定は minify)
";

fn main() {
    match parse() {
        Ok(args) => match run(&args) {
            Ok(stats) => {
                eprintln!(
                    "pages={} files={} bytes={} fallbackSlugs={}",
                    stats.pages, stats.files, stats.bytes, stats.fallback_slugs
                );
            }
            Err(e) => fail(&e),
        },
        Err(e) => {
            eprint!("{USAGE}");
            fail(&e);
        }
    }
}

fn fail(e: &WebExportError) -> ! {
    eprintln!("web-export: {e}");
    std::process::exit(e.exit_code());
}

/// `std::env::args` を手で読む。引数がこれだけで、増える予定も無いので clap は入れない。
fn parse() -> Result<Args, WebExportError> {
    let mut args = Args::default();
    let mut it = std::env::args().skip(1);
    while let Some(flag) = it.next() {
        let mut value = || {
            it.next()
                .map(PathBuf::from)
                .ok_or_else(|| WebExportError::Args(format!("{flag} に値がない")))
        };
        match flag.as_str() {
            "--sql" => args.sql = Some(value()?),
            "--db" => args.db = Some(value()?),
            "--work-db" => args.work_db = Some(value()?),
            "--out" => args.out = Some(value()?),
            "--emit-fixture" => args.emit_fixture = Some(value()?),
            "--fixture-check" => args.fixture_check = Some(value()?),
            "--today" => {
                args.today = Some(value()?.to_string_lossy().into_owned());
            }
            "--pretty" => args.pretty = true,
            "-h" | "--help" => {
                print!("{USAGE}");
                std::process::exit(0);
            }
            other => return Err(WebExportError::Args(format!("知らない引数: {other}"))),
        }
    }
    validate(&args)?;
    Ok(args)
}

fn validate(args: &Args) -> Result<(), WebExportError> {
    if args.emit_fixture.is_some() || args.fixture_check.is_some() {
        return Ok(());
    }
    if args.sql.is_some() == args.db.is_some() {
        return Err(WebExportError::Args("--sql と --db のどちらか一方が要る".into()));
    }
    if args.out.is_none() {
        return Err(WebExportError::Args("--out が要る".into()));
    }
    Ok(())
}
