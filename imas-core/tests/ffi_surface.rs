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

declare_and_call_checksums!(
    uniffi_imas_core_checksum_func_backup_import_summary,
    uniffi_imas_core_checksum_func_daily_pick_day_key,
    uniffi_imas_core_checksum_func_daily_pick_song_index,
    uniffi_imas_core_checksum_func_daily_pick_song_indices,
    uniffi_imas_core_checksum_func_daily_pick_stable_index,
    uniffi_imas_core_checksum_func_edit_permission_can_edit,
    uniffi_imas_core_checksum_func_edit_permission_outcome_on_edit_tap,
    uniffi_imas_core_checksum_func_edit_permission_should_prompt_login,
    uniffi_imas_core_checksum_func_edit_permission_show_edit_affordance,
    uniffi_imas_core_checksum_func_filter_event_indices,
    uniffi_imas_core_checksum_func_filter_idol_list,
    uniffi_imas_core_checksum_func_filter_song_list,
    uniffi_imas_core_checksum_func_group_event_indices_by_year,
    uniffi_imas_core_checksum_func_idol_sort_order_table,
    uniffi_imas_core_checksum_func_image_template_json,
    uniffi_imas_core_checksum_func_intro_quiz_choices_batch,
    uniffi_imas_core_checksum_func_jst_is_today_or_later,
    uniffi_imas_core_checksum_func_jst_today,
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
);
