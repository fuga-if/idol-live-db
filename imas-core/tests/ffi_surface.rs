//! FFI 面の完結性テスト (回帰: 2026-08-25 バインディング再生成漏れ)。
//!
//! `#[uniffi::export]` された各関数には UniFFI が引数なしの checksum 関数
//! (`uniffi_imas_core_checksum_func_<name>`) を no_mangle で生成する。
//! ここで全エクスポートの checksum シンボルを extern 宣言して呼ぶことで、
//! 「inbound のエクスポートが消えた / 改名された」をリンクエラーとして検出する
//! (アプリ側ラッパ SongListFiltering.swift / SongListViewModel.kt が参照する
//! filterSongList 等の生成元シンボルが揃っていることの Rust 側の保証)。
//!
//! 注意: **エクスポートを足したらこの一覧にも足すこと**。列挙されていない関数は、改名しても
//! 削除してもこのテストが緑のまま通り、Swift/Kotlin ラッパのリンク時まで発覚しない
//! (回帰: Phase 8 sync の 20 関数が未登録のまま「テスト緑」と報告された)。
//!
//! 注意: このテストは「クレートが正しい FFI 面を持つこと」までしか守れない。
//! 生成済みバインディング (build/imas-core/swift/imas_core.swift 等) が古いままの
//! 事故は imas-core/build.sh の再実行でのみ解消される。inbound を触ったら必ず
//! build.sh を回すこと (README.md 参照)。

// extern 宣言だけではクレートがリンク対象にならないため、明示的にリンクする。
extern crate imas_core;

macro_rules! declare_and_call_checksums {
    ($($name:ident),+ $(,)?) => {
        extern "C" {
            $(fn $name() -> u16;)+
        }
        #[test]
        fn all_exported_functions_have_ffi_checksum_symbols() {
            // 呼び出し自体がリンク成功の証明。値は署名変更で変わり得るため固定しない。
            let checksums = [$(unsafe { $name() }),+];
            assert_eq!(checksums.len(), COUNT);
        }
        const COUNT: usize = [$(stringify!($name)),+].len();
    };
}

declare_and_call_checksums! {
    uniffi_imas_core_checksum_func_backup_current_schema_version,
    uniffi_imas_core_checksum_func_backup_import_summary,
    uniffi_imas_core_checksum_func_backup_kind_to_android,
    uniffi_imas_core_checksum_func_backup_kind_to_canonical,
    uniffi_imas_core_checksum_func_build_backup_envelope,
    uniffi_imas_core_checksum_func_ck_ingest_batch,
    uniffi_imas_core_checksum_func_ck_ingest_web_services_batch,
    uniffi_imas_core_checksum_func_ck_is_ingested_record_type,
    uniffi_imas_core_checksum_func_ck_map_record,
    uniffi_imas_core_checksum_func_ck_record_deleted_at_millis,
    uniffi_imas_core_checksum_func_ck_record_from_web_services_json,
    uniffi_imas_core_checksum_func_ck_validated_hex_color,
    uniffi_imas_core_checksum_func_color_match_accuracy_percent,
    uniffi_imas_core_checksum_func_color_match_build_pools,
    uniffi_imas_core_checksum_func_color_match_effective_pool,
    uniffi_imas_core_checksum_func_color_match_judge_round,
    uniffi_imas_core_checksum_func_color_match_start_game,
    uniffi_imas_core_checksum_func_daily_pick_day_key,
    uniffi_imas_core_checksum_func_daily_pick_song_index,
    uniffi_imas_core_checksum_func_daily_pick_song_indices,
    uniffi_imas_core_checksum_func_daily_pick_stable_index,
    uniffi_imas_core_checksum_func_edit_permission_can_edit,
    uniffi_imas_core_checksum_func_edit_permission_outcome_on_edit_tap,
    uniffi_imas_core_checksum_func_edit_permission_should_prompt_login,
    uniffi_imas_core_checksum_func_edit_permission_show_edit_affordance,
    uniffi_imas_core_checksum_func_ensure_master_schema,
    uniffi_imas_core_checksum_func_filter_event_indices,
    uniffi_imas_core_checksum_func_filter_idol_list,
    uniffi_imas_core_checksum_func_filter_song_list,
    uniffi_imas_core_checksum_func_game_progress_apply_result,
    uniffi_imas_core_checksum_func_game_progress_best_rate_percent,
    uniffi_imas_core_checksum_func_game_progress_daily_sheet_gate,
    uniffi_imas_core_checksum_func_game_progress_did_clear_today,
    uniffi_imas_core_checksum_func_game_progress_display_streak,
    uniffi_imas_core_checksum_func_group_event_indices_by_year,
    uniffi_imas_core_checksum_func_idol_profile_rows,
    uniffi_imas_core_checksum_func_idol_quiz_answer,
    uniffi_imas_core_checksum_func_idol_quiz_hint_state,
    uniffi_imas_core_checksum_func_idol_quiz_pool_estimate,
    uniffi_imas_core_checksum_func_idol_quiz_session,
    uniffi_imas_core_checksum_func_idol_quiz_session_result,
    uniffi_imas_core_checksum_func_idol_sort_order_table,
    uniffi_imas_core_checksum_func_image_template_json,
    uniffi_imas_core_checksum_func_inspect_backup_envelope,
    uniffi_imas_core_checksum_func_intro_quiz_choices_batch,
    uniffi_imas_core_checksum_func_jst_is_today_or_later,
    uniffi_imas_core_checksum_func_jst_today,
    uniffi_imas_core_checksum_func_plan_backup_import,
    uniffi_imas_core_checksum_func_quiz_brand_ids_decode,
    uniffi_imas_core_checksum_func_quiz_brand_ids_encode,
    uniffi_imas_core_checksum_func_quiz_session_length,
    uniffi_imas_core_checksum_func_reseed_common_columns,
    uniffi_imas_core_checksum_func_reseed_default_preserved_tables,
    uniffi_imas_core_checksum_func_reseed_needed,
    uniffi_imas_core_checksum_func_reseed_parse_data_version,
    uniffi_imas_core_checksum_func_reseed_summary_label,
    uniffi_imas_core_checksum_func_reseed_target_tables,
    uniffi_imas_core_checksum_func_resolve_oshi_theme,
    uniffi_imas_core_checksum_func_seed_common_columns,
    uniffi_imas_core_checksum_func_seed_common_tables,
    uniffi_imas_core_checksum_func_setlist_item_indexes_needing_sync,
    uniffi_imas_core_checksum_func_setlist_performer_indexes_needing_sync,
    uniffi_imas_core_checksum_func_short_year_month,
    uniffi_imas_core_checksum_func_song_singer_quiz_answer,
    uniffi_imas_core_checksum_func_song_singer_quiz_hint_state,
    uniffi_imas_core_checksum_func_song_singer_quiz_pool_estimate,
    uniffi_imas_core_checksum_func_song_singer_quiz_session,
    uniffi_imas_core_checksum_func_song_singer_quiz_session_result,
    uniffi_imas_core_checksum_func_sort_idol_list,
    uniffi_imas_core_checksum_func_sync_completion_plan,
    uniffi_imas_core_checksum_func_sync_default_full_sync_interval_seconds,
    uniffi_imas_core_checksum_func_sync_next_chunk_action,
    uniffi_imas_core_checksum_func_sync_orphan_ids,
    uniffi_imas_core_checksum_func_sync_parse_composite_record_name,
    uniffi_imas_core_checksum_func_sync_partition_by_deleted,
    uniffi_imas_core_checksum_func_sync_run_start_plan,
    uniffi_imas_core_checksum_func_sync_startup_plan,
    uniffi_imas_core_checksum_func_sync_step_start_plan,
    uniffi_imas_core_checksum_func_sync_steps_in_order,
    uniffi_imas_core_checksum_func_sync_supports_orphan_cleanup,
    uniffi_imas_core_checksum_func_sync_table_info,
    uniffi_imas_core_checksum_func_timeline_epoch_at_x,
    uniffi_imas_core_checksum_func_timeline_fit_points_per_day,
    uniffi_imas_core_checksum_func_timeline_hit_index,
    uniffi_imas_core_checksum_func_timeline_pack_rows,
    uniffi_imas_core_checksum_func_timeline_x,
    uniffi_imas_core_checksum_func_timeline_x_positions,
    uniffi_imas_core_checksum_func_timeline_year_boundaries,
    uniffi_imas_core_checksum_func_timeline_year_range,
    uniffi_imas_core_checksum_func_weighted_sample_indices,
}

/// リンク検査は「消えた・改名された」しか捕まえず、**増えた分は素通りする**。
/// エクスポートを足したのに一覧へ登録し忘れる事故 (Phase 6/8 で実際に 36 件発生) を防ぐため、
/// inbound 配下の `#[uniffi::export]` 属性の総数と、この一覧の件数を突き合わせる。
///
/// 数が合わなくなったら:
///   nm <target>/release/libimas_core.dylib | grep -o 'uniffi_imas_core_checksum_func_\w*' | sort -u
/// の結果でこのファイルの一覧を作り直す (imas-core/README.md 参照)。
#[test]
fn export_count_matches_declared_checksums() {
    let inbound = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src/inbound");
    let attribute = concat!("#[uniffi", "::export]");
    let mut found = 0usize;
    let mut stack = vec![inbound];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir).expect("inbound を読める") {
            let path = entry.expect("dir entry").path();
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            if path.extension().is_none_or(|e| e != "rs") {
                continue;
            }
            let text = std::fs::read_to_string(&path).expect("ソースを読める");
            // impl ブロックへの #[uniffi::export] は関数 1 本を意味しないので、
            // 属性の次の非空行が `impl` で始まるものは除外して関数だけ数える。
            let mut lines = text.lines().peekable();
            while let Some(line) = lines.next() {
                if !line.trim_start().starts_with(attribute) {
                    continue;
                }
                let next = lines
                    .clone()
                    .find(|l| !l.trim().is_empty() && !l.trim_start().starts_with("//"));
                if next.is_some_and(|l| l.trim_start().starts_with("impl")) {
                    continue;
                }
                found += 1;
            }
        }
    }
    assert_eq!(
        found, COUNT,
        "inbound の #[uniffi::export] 関数 {found} 本に対し一覧は {COUNT} 本。\n\
         エクスポートを増減したらこのファイルの一覧を更新すること (上のコメント参照)。"
    );
}
