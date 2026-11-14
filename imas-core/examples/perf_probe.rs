//! 読み込みの所要時間を測る (cargo run --release --example perf_probe -- <db>)。
use imas_core::domain::snapshot_build;
use imas_core::outbound::sqlite_loader::load_raw_tables;
use std::time::Instant;

fn main() {
    let path = std::env::args().nth(1).expect("db path");
    let rounds: usize = std::env::args().nth(2).and_then(|s| s.parse().ok()).unwrap_or(5);
    for round in 0..rounds {
        let t0 = Instant::now();
        let raw = load_raw_tables(&path).unwrap();
        let t1 = Instant::now();
        let snap = snapshot_build::build(raw);
        let t2 = Instant::now();
        println!(
            "round {round}: raw {:>7.1}ms  build {:>7.1}ms  total {:>7.1}ms (songs {})",
            (t1 - t0).as_secs_f64() * 1e3,
            (t2 - t1).as_secs_f64() * 1e3,
            (t2 - t0).as_secs_f64() * 1e3,
            snap.songs.len()
        );
        let t3 = Instant::now();
        drop(snap);
        println!("  drop {:.1}ms", t3.elapsed().as_secs_f64() * 1e3);
    }
}
