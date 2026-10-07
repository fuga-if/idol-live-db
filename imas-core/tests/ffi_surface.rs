//! FFI 面の完結性テスト (回帰: 2026-08-25 バインディング再生成漏れ)。
//!
//! UniFFI は `#[uniffi::export]` の対象ごとに、引数なしの checksum 関数を no_mangle で生成する。
//!
//! | 対象 | シンボル |
//! |---|---|
//! | 関数 | `uniffi_imas_core_checksum_func_<関数名>` |
//! | メソッド (export した impl の中の `pub fn`) | `uniffi_imas_core_checksum_method_<型名の小文字>_<名前>` |
//! | コンストラクタ (`#[uniffi::constructor]`) | `uniffi_imas_core_checksum_constructor_<型名の小文字>_<名前>` |
//!
//! ここで全部を extern 宣言して呼ぶことで、「エクスポートが消えた / 改名された」を
//! リンクエラーとして検出する (Swift / Kotlin のラッパが参照する生成元のシンボルが
//! 揃っていることの Rust 側の保証)。増えた分はリンクでは捕まらないので、
//! `declared_checksums_match_inbound_exports` が inbound のソースと名前で突き合わせる。
//! 一覧の更新が要るときは、そのテストが足す行・消す行をそのまま表示する。
//!
//! 注意: このテストは「クレートが正しい FFI 面を持つこと」までしか守れない。
//! 生成済みバインディング (build/imas-core/swift/imas_core.swift 等) が古いままの
//! 事故は imas-core/build.sh の再実行でのみ解消される。inbound を触ったら必ず
//! build.sh を回すこと。

use std::collections::BTreeSet;
use std::path::Path;

// extern 宣言だけではクレートがリンク対象にならないため、明示的にリンクする。
extern crate imas_core;

macro_rules! declare_and_call_checksums {
    ($($name:ident),+ $(,)?) => {
        extern "C" {
            $(fn $name() -> u16;)+
        }
        #[test]
        fn all_exports_have_ffi_checksum_symbols() {
            // 呼び出し自体がリンク成功の証明。値は署名変更で変わり得るため固定しない。
            let checksums = [$(unsafe { $name() }),+];
            assert_eq!(checksums.len(), DECLARED.len());
        }
        const DECLARED: &[&str] = &[$(stringify!($name)),+];
    };
}

declare_and_call_checksums! {
    uniffi_imas_core_checksum_constructor_snapshotstore_new,
    uniffi_imas_core_checksum_constructor_textsearchcatalog_new,
    uniffi_imas_core_checksum_func_app_navigation_sections,
    uniffi_imas_core_checksum_func_app_navigation_sections_with_tabs,
    uniffi_imas_core_checksum_func_play_queue_next_index,
    uniffi_imas_core_checksum_func_play_queue_previous_index,
    uniffi_imas_core_checksum_func_playlist_append_songs,
    uniffi_imas_core_checksum_func_playlist_move_song,
    uniffi_imas_core_checksum_func_tab_bar_choices,
    uniffi_imas_core_checksum_func_normalize_tab_bar_keys,
    uniffi_imas_core_checksum_func_max_tab_bar_count,
    uniffi_imas_core_checksum_func_asobi_order_history_url,
    uniffi_imas_core_checksum_func_assistant_example_prompts,
    uniffi_imas_core_checksum_func_assistant_instructions,
    uniffi_imas_core_checksum_func_assistant_timeline_reply_input,
    uniffi_imas_core_checksum_func_assistant_tool_progress_label,
    uniffi_imas_core_checksum_func_assistant_tools_json,
    uniffi_imas_core_checksum_func_attendance_status,
    uniffi_imas_core_checksum_func_auth_admin_capabilities,
    uniffi_imas_core_checksum_func_auth_adopt_session_response,
    uniffi_imas_core_checksum_func_auth_apply_me_response,
    uniffi_imas_core_checksum_func_auth_bearer_token,
    uniffi_imas_core_checksum_func_auth_credential_check_action,
    uniffi_imas_core_checksum_func_auth_display_name_from_apple_name,
    uniffi_imas_core_checksum_func_auth_is_valid_session_token,
    uniffi_imas_core_checksum_func_auth_restore_stored_state,
    uniffi_imas_core_checksum_func_auth_session_refresh_candidate,
    uniffi_imas_core_checksum_func_auth_stored_flag_value,
    uniffi_imas_core_checksum_func_auth_token_exchange_retry,
    uniffi_imas_core_checksum_func_backup_current_schema_version,
    uniffi_imas_core_checksum_func_backup_import_summary,
    uniffi_imas_core_checksum_func_backup_meaningful_mark_indices,
    uniffi_imas_core_checksum_func_build_backup_envelope,
    uniffi_imas_core_checksum_func_build_ledger_summary,
    uniffi_imas_core_checksum_func_card_case_sections,
    uniffi_imas_core_checksum_func_card_exchange_show_candidates,
    uniffi_imas_core_checksum_func_card_link_from_url,
    uniffi_imas_core_checksum_func_card_link_kinds,
    uniffi_imas_core_checksum_func_card_link_view,
    uniffi_imas_core_checksum_func_classify_scanned_code,
    uniffi_imas_core_checksum_func_decode_producer_card,
    uniffi_imas_core_checksum_func_encode_producer_card,
    uniffi_imas_core_checksum_func_normalize_card_link,
    uniffi_imas_core_checksum_func_producer_card_common,
    uniffi_imas_core_checksum_func_producer_card_input_error_message,
    uniffi_imas_core_checksum_func_producer_card_limits,
    uniffi_imas_core_checksum_func_producer_card_payload,
    uniffi_imas_core_checksum_func_producer_card_url_from_payload,
    uniffi_imas_core_checksum_func_validate_producer_card,
    uniffi_imas_core_checksum_func_card_file_name,
    uniffi_imas_core_checksum_func_card_file_type_info,
    uniffi_imas_core_checksum_func_card_invite_proof,
    uniffi_imas_core_checksum_func_card_issued_label,
    uniffi_imas_core_checksum_func_producer_card_face,
    uniffi_imas_core_checksum_func_producer_card_pick_oshi,
    uniffi_imas_core_checksum_func_card_photo_shape,
    uniffi_imas_core_checksum_func_card_photo_source_key,
    uniffi_imas_core_checksum_func_card_photo_source_from_key,
    uniffi_imas_core_checksum_func_card_link_kind_from_key,
    uniffi_imas_core_checksum_func_card_link_kind_key,
    uniffi_imas_core_checksum_func_card_links_from_json,
    uniffi_imas_core_checksum_func_card_links_to_json,
    uniffi_imas_core_checksum_func_card_peer_tag,
    uniffi_imas_core_checksum_func_decode_card_file,
    uniffi_imas_core_checksum_func_encode_card_file,
    uniffi_imas_core_checksum_func_producer_card_record_summary,
    uniffi_imas_core_checksum_func_normalize_card_qr_url,
    uniffi_imas_core_checksum_func_card_qr_link_view,
    uniffi_imas_core_checksum_func_card_name_fonts,
    uniffi_imas_core_checksum_func_card_name_font_info,
    uniffi_imas_core_checksum_func_card_designs,
    uniffi_imas_core_checksum_func_card_design_info,
    uniffi_imas_core_checksum_func_producer_card_display_design,
    uniffi_imas_core_checksum_func_card_design_key,
    uniffi_imas_core_checksum_func_card_design_from_key,
    uniffi_imas_core_checksum_func_card_x_avatar_handle,
    uniffi_imas_core_checksum_func_x_profile_api_url,
    uniffi_imas_core_checksum_func_x_avatar_lookup,
    uniffi_imas_core_checksum_func_x_avatar_lookup_message,
    uniffi_imas_core_checksum_func_profile_sheet_default,
    uniffi_imas_core_checksum_func_profile_auto_fields,
    uniffi_imas_core_checksum_func_profile_auto_field_info,
    uniffi_imas_core_checksum_func_profile_auto_field_rows,
    uniffi_imas_core_checksum_func_profile_toggle_field,
    uniffi_imas_core_checksum_func_profile_sheet_sizes,
    uniffi_imas_core_checksum_func_profile_sheet_size_info,
    uniffi_imas_core_checksum_func_profile_sheet_to_json,
    uniffi_imas_core_checksum_func_profile_sheet_from_json,
    uniffi_imas_core_checksum_func_profile_sheet_layout,
    uniffi_imas_core_checksum_func_profile_brand_marks,
    uniffi_imas_core_checksum_func_favorite_song_picks,
    uniffi_imas_core_checksum_func_favorite_song_toggle,
    uniffi_imas_core_checksum_func_favorite_song_normalize,
    uniffi_imas_core_checksum_func_brand_role_steps,
    uniffi_imas_core_checksum_func_brand_role_step,
    uniffi_imas_core_checksum_func_brand_role_from_index,
    uniffi_imas_core_checksum_func_brand_role_settings,
    uniffi_imas_core_checksum_func_brand_roles_configured,
    uniffi_imas_core_checksum_func_brand_role_set,
    uniffi_imas_core_checksum_func_brand_roles_to_json,
    uniffi_imas_core_checksum_func_build_mastery_groups,
    uniffi_imas_core_checksum_func_canonical_credit_key,
    uniffi_imas_core_checksum_func_ck_ingest_batch,
    uniffi_imas_core_checksum_func_ck_ingest_web_services_batch,
    uniffi_imas_core_checksum_func_ck_is_ingested_record_type,
    uniffi_imas_core_checksum_func_ck_map_record,
    uniffi_imas_core_checksum_func_ck_record_deleted_at_millis,
    uniffi_imas_core_checksum_func_ck_record_from_web_services_json,
    uniffi_imas_core_checksum_func_ck_validated_hex_color,
    uniffi_imas_core_checksum_func_collection_attendance_types,
    uniffi_imas_core_checksum_func_collection_attended_shows,
    uniffi_imas_core_checksum_func_collection_real_live_kinds,
    uniffi_imas_core_checksum_func_color_accessibility_name,
    uniffi_imas_core_checksum_func_color_match_accuracy_percent,
    uniffi_imas_core_checksum_func_color_match_build_pools,
    uniffi_imas_core_checksum_func_color_match_effective_pool,
    uniffi_imas_core_checksum_func_color_match_judge_round,
    uniffi_imas_core_checksum_func_color_match_start_game,
    uniffi_imas_core_checksum_func_color_quiz_answer,
    uniffi_imas_core_checksum_func_color_quiz_hint_state,
    uniffi_imas_core_checksum_func_color_quiz_session_result,
    uniffi_imas_core_checksum_func_color_quiz_start_game,
    uniffi_imas_core_checksum_func_daily_pick_day_key,
    uniffi_imas_core_checksum_func_daily_pick_idol_index,
    uniffi_imas_core_checksum_func_daily_pick_idol_indices,
    uniffi_imas_core_checksum_func_daily_pick_sheet_kind,
    uniffi_imas_core_checksum_func_daily_pick_song_index,
    uniffi_imas_core_checksum_func_daily_pick_song_indices,
    uniffi_imas_core_checksum_func_daily_pick_stable_index,
    uniffi_imas_core_checksum_func_date_range_display,
    uniffi_imas_core_checksum_func_date_label,
    uniffi_imas_core_checksum_func_default_ticket,
    uniffi_imas_core_checksum_func_edit_permission_can_edit,
    uniffi_imas_core_checksum_func_edit_permission_outcome_on_edit_tap,
    uniffi_imas_core_checksum_func_edit_permission_should_prompt_login,
    uniffi_imas_core_checksum_func_edit_permission_show_edit_affordance,
    uniffi_imas_core_checksum_func_ensure_master_schema,
    uniffi_imas_core_checksum_func_event_short_name,
    uniffi_imas_core_checksum_func_event_short_names,
    uniffi_imas_core_checksum_func_expense_categories,
    uniffi_imas_core_checksum_func_expense_category_from_key,
    uniffi_imas_core_checksum_func_expense_category_key,
    uniffi_imas_core_checksum_func_expense_category_label,
    uniffi_imas_core_checksum_func_filter_event_indices,
    uniffi_imas_core_checksum_func_filter_idol_list,
    uniffi_imas_core_checksum_func_filter_song_list,
    uniffi_imas_core_checksum_func_format_yen,
    uniffi_imas_core_checksum_func_fuzzy_matches,
    uniffi_imas_core_checksum_func_fuzzy_matches_multi,
    uniffi_imas_core_checksum_func_gallery_manifest_encode,
    uniffi_imas_core_checksum_func_gallery_manifest_reconcile,
    uniffi_imas_core_checksum_func_gallery_slideshow_entries,
    uniffi_imas_core_checksum_func_game_progress_apply_result,
    uniffi_imas_core_checksum_func_game_progress_best_rate_percent,
    uniffi_imas_core_checksum_func_game_progress_daily_sheet_gate,
    uniffi_imas_core_checksum_func_game_progress_did_clear_today,
    uniffi_imas_core_checksum_func_game_progress_display_streak,
    uniffi_imas_core_checksum_func_group_event_indices_by_year,
    uniffi_imas_core_checksum_func_group_indices_by_year_desc,
    uniffi_imas_core_checksum_func_group_venues_by_area,
    uniffi_imas_core_checksum_func_idol_profile_rows,
    uniffi_imas_core_checksum_func_idol_profile_rows_from_source,
    uniffi_imas_core_checksum_func_idol_quiz_answer,
    uniffi_imas_core_checksum_func_idol_quiz_hint_state,
    uniffi_imas_core_checksum_func_idol_quiz_pool_estimate,
    uniffi_imas_core_checksum_func_idol_quiz_session,
    uniffi_imas_core_checksum_func_idol_quiz_session_result,
    uniffi_imas_core_checksum_func_idol_search_target_counts,
    uniffi_imas_core_checksum_func_idol_short_name,
    uniffi_imas_core_checksum_func_idol_sort_order_table,
    uniffi_imas_core_checksum_func_image_template_json,
    uniffi_imas_core_checksum_func_input_clamp,
    uniffi_imas_core_checksum_func_input_is_acceptable,
    uniffi_imas_core_checksum_func_input_length,
    uniffi_imas_core_checksum_func_input_limit_max,
    uniffi_imas_core_checksum_func_intro_is_new_best_score,
    uniffi_imas_core_checksum_func_intro_is_new_best_time,
    uniffi_imas_core_checksum_func_intro_question_count,
    uniffi_imas_core_checksum_func_intro_quiz_choices_batch,
    uniffi_imas_core_checksum_func_intro_quiz_playable_indices,
    uniffi_imas_core_checksum_func_intro_score_after_answer,
    uniffi_imas_core_checksum_func_is_character_live,
    uniffi_imas_core_checksum_func_jst_is_today_or_later,
    uniffi_imas_core_checksum_func_show_view_decision,
    uniffi_imas_core_checksum_func_show_credit_lines,
    uniffi_imas_core_checksum_func_lyrics_credit_line,
    uniffi_imas_core_checksum_func_jst_today,
    uniffi_imas_core_checksum_func_kamisabi_card_label,
    uniffi_imas_core_checksum_func_kamisabi_completion_label,
    uniffi_imas_core_checksum_func_ledger_show_totals,
    uniffi_imas_core_checksum_func_lyric_chunk_at,
    uniffi_imas_core_checksum_func_lyric_chunks,
    uniffi_imas_core_checksum_func_lyric_active_call,
    uniffi_imas_core_checksum_func_lyric_active_line,
    uniffi_imas_core_checksum_func_lyric_active_overlay,
    uniffi_imas_core_checksum_func_lyric_call_echoes_lyric,
    uniffi_imas_core_checksum_func_lyric_call_echoes_line,
    uniffi_imas_core_checksum_func_lyric_call_spans,
    uniffi_imas_core_checksum_func_lyric_has_timing,
    uniffi_imas_core_checksum_func_lyric_is_overlay_line,
    uniffi_imas_core_checksum_func_lyric_like_heat,
    uniffi_imas_core_checksum_func_lyric_likes_parse,
    uniffi_imas_core_checksum_func_lyric_likes_toggle,
    uniffi_imas_core_checksum_func_lyric_line_spans,
    uniffi_imas_core_checksum_func_lyric_next_recordable,
    uniffi_imas_core_checksum_func_lyric_overlay_spans,
    uniffi_imas_core_checksum_func_lyric_overlay_range,
    uniffi_imas_core_checksum_func_lyric_overlay_split,
    uniffi_imas_core_checksum_func_lyric_parts_applicable,
    uniffi_imas_core_checksum_func_lyric_part_erase,
    uniffi_imas_core_checksum_func_lyric_part_paint,
    uniffi_imas_core_checksum_func_lyric_part_segments,
    uniffi_imas_core_checksum_func_lyric_part_toggle_break,
    uniffi_imas_core_checksum_func_lyric_part_union,
    uniffi_imas_core_checksum_func_lyric_ruby_spans,
    uniffi_imas_core_checksum_func_lyric_ruby_choices,
    uniffi_imas_core_checksum_func_lyric_aside_spans,
    uniffi_imas_core_checksum_func_lyric_main_range,
    uniffi_imas_core_checksum_func_lyric_ocr_append,
    uniffi_imas_core_checksum_func_lyric_ocr_latin_words,
    uniffi_imas_core_checksum_func_lyric_ocr_layout,
    uniffi_imas_core_checksum_func_lyric_ocr_pick_candidate,
    uniffi_imas_core_checksum_func_lyric_ocr_steps,
    uniffi_imas_core_checksum_func_lyric_remove_lines,
    uniffi_imas_core_checksum_func_lyric_ruby_join,
    uniffi_imas_core_checksum_func_lyric_ruby_like_lines,
    uniffi_imas_core_checksum_func_lyric_ruby_mark_at,
    uniffi_imas_core_checksum_func_lyric_ruby_mark_found,
    uniffi_imas_core_checksum_func_lyric_ruby_rebase,
    uniffi_imas_core_checksum_func_lyric_ruby_split,
    uniffi_imas_core_checksum_func_lyric_wrap_ruby,
    uniffi_imas_core_checksum_func_lyric_submission_allowed,
    uniffi_imas_core_checksum_func_lyric_submission_check,
    uniffi_imas_core_checksum_func_lyric_submission_guideline,
    uniffi_imas_core_checksum_func_lyric_submission_issue_blocks,
    uniffi_imas_core_checksum_func_lyric_submission_issue_message,
    uniffi_imas_core_checksum_func_lyric_submission_max_chars,
    uniffi_imas_core_checksum_func_lyrics_quiz_answer,
    uniffi_imas_core_checksum_func_lyrics_quiz_excerpt,
    uniffi_imas_core_checksum_func_lyrics_quiz_hint_state,
    uniffi_imas_core_checksum_func_lyrics_quiz_minimum_pool,
    uniffi_imas_core_checksum_func_lyrics_quiz_pool_estimate,
    uniffi_imas_core_checksum_func_lyrics_quiz_session,
    uniffi_imas_core_checksum_func_lyrics_quiz_session_result,
    uniffi_imas_core_checksum_func_mastery_bulk_targets,
    uniffi_imas_core_checksum_func_mastery_song_filter,
    uniffi_imas_core_checksum_func_mastery_summary,
    uniffi_imas_core_checksum_func_masthead_date,
    uniffi_imas_core_checksum_func_next_mastery_level,
    uniffi_imas_core_checksum_func_next_show_index,
    uniffi_imas_core_checksum_func_non_performance_performer_types,
    uniffi_imas_core_checksum_func_non_performance_venue_modes,
    uniffi_imas_core_checksum_func_normalize_ticket_sale_moment,
    uniffi_imas_core_checksum_func_parse_store_orders,
    uniffi_imas_core_checksum_func_parse_time_minutes,
    uniffi_imas_core_checksum_func_pending_favorite_is_still_queued,
    uniffi_imas_core_checksum_func_pending_favorite_retry_delay_seconds,
    uniffi_imas_core_checksum_func_pending_favorites_after_attempt,
    uniffi_imas_core_checksum_func_pending_favorites_decode,
    uniffi_imas_core_checksum_func_pending_favorites_discard,
    uniffi_imas_core_checksum_func_pending_favorites_encode,
    uniffi_imas_core_checksum_func_pending_favorites_enqueue,
    uniffi_imas_core_checksum_func_penlight_accessibility_label,
    uniffi_imas_core_checksum_func_performer_display_name,
    uniffi_imas_core_checksum_func_performer_display_name_joined,
    uniffi_imas_core_checksum_func_performer_label,
    uniffi_imas_core_checksum_func_performer_name_mode_from_raw,
    uniffi_imas_core_checksum_func_performer_name_options,
    uniffi_imas_core_checksum_func_plan_backup_import,
    uniffi_imas_core_checksum_func_plan_vote_selection,
    uniffi_imas_core_checksum_func_progress_percent,
    uniffi_imas_core_checksum_func_song_credit_label,
    uniffi_imas_core_checksum_func_quiz_accuracy_result,
    uniffi_imas_core_checksum_func_quiz_brand_ids_decode,
    uniffi_imas_core_checksum_func_quiz_grade_for_rate,
    uniffi_imas_core_checksum_func_quiz_brand_ids_encode,
    uniffi_imas_core_checksum_func_quiz_session_length,
    uniffi_imas_core_checksum_func_recents_after_visit,
    uniffi_imas_core_checksum_func_relative_time,
    uniffi_imas_core_checksum_func_relative_times,
    uniffi_imas_core_checksum_func_remap_mastery_level,
    uniffi_imas_core_checksum_func_reseed_common_columns,
    uniffi_imas_core_checksum_func_reseed_default_preserved_tables,
    uniffi_imas_core_checksum_func_reseed_master_target_tables,
    uniffi_imas_core_checksum_func_reseed_needed,
    uniffi_imas_core_checksum_func_reseed_parse_data_version,
    uniffi_imas_core_checksum_func_reseed_summary_label,
    uniffi_imas_core_checksum_func_reseed_target_tables,
    uniffi_imas_core_checksum_func_resolve_oshi_theme,
    uniffi_imas_core_checksum_func_search_match_texts,
    uniffi_imas_core_checksum_func_seed_common_columns,
    uniffi_imas_core_checksum_func_seed_common_tables,
    uniffi_imas_core_checksum_func_setlist_display_mode_from_stored,
    uniffi_imas_core_checksum_func_setlist_display_mode_is_compact,
    uniffi_imas_core_checksum_func_setlist_display_modes,
    uniffi_imas_core_checksum_func_setlist_full_cast_label,
    uniffi_imas_core_checksum_func_setlist_item_indexes_needing_sync,
    uniffi_imas_core_checksum_func_setlist_lineup,
    uniffi_imas_core_checksum_func_setlist_performer_indexes_needing_sync,
    uniffi_imas_core_checksum_func_setlist_quiz_answer,
    uniffi_imas_core_checksum_func_setlist_quiz_hint_state,
    uniffi_imas_core_checksum_func_setlist_quiz_session_result,
    uniffi_imas_core_checksum_func_setlist_section_label,
    uniffi_imas_core_checksum_func_share_event_text,
    uniffi_imas_core_checksum_func_share_event_url,
    uniffi_imas_core_checksum_func_share_intro_don_text,
    uniffi_imas_core_checksum_func_share_payload_plain_text,
    uniffi_imas_core_checksum_func_share_payload_x_post_url,
    uniffi_imas_core_checksum_func_share_poll_invite_payload,
    uniffi_imas_core_checksum_func_share_poll_url,
    uniffi_imas_core_checksum_func_share_poll_votes_payload,
    uniffi_imas_core_checksum_func_poll_competition_ranks,
    uniffi_imas_core_checksum_func_poll_result_card,
    uniffi_imas_core_checksum_func_share_prediction_votes_payload,
    uniffi_imas_core_checksum_func_share_quiz_result_text,
    uniffi_imas_core_checksum_func_sort_maker_estimate_total,
    uniffi_imas_core_checksum_func_sort_maker_replay,
    uniffi_imas_core_checksum_func_sort_maker_share_text,
    uniffi_imas_core_checksum_func_ticket_application_choices,
    uniffi_imas_core_checksum_func_ticket_application_from_raw,
    uniffi_imas_core_checksum_func_ticket_application_label,
    uniffi_imas_core_checksum_func_ticket_application_raw,
    uniffi_imas_core_checksum_func_tier_list_assign_from_ranking,
    uniffi_imas_core_checksum_func_tier_list_cycle_color,
    uniffi_imas_core_checksum_func_tier_list_max_tiers,
    uniffi_imas_core_checksum_func_tier_list_min_tiers,
    uniffi_imas_core_checksum_func_tier_list_new_tier,
    uniffi_imas_core_checksum_func_tier_list_normalize_tier_label,
    uniffi_imas_core_checksum_func_tier_list_normalize_title,
    uniffi_imas_core_checksum_func_tier_list_title_max_chars,
    uniffi_imas_core_checksum_func_tier_list_tiers,
    uniffi_imas_core_checksum_func_tier_list_share_text,
    uniffi_imas_core_checksum_func_tier_list_tier_label_max_chars,
    uniffi_imas_core_checksum_func_share_setlist_text,
    uniffi_imas_core_checksum_func_share_show_url,
    uniffi_imas_core_checksum_func_short_year_month,
    uniffi_imas_core_checksum_func_show_display_title,
    uniffi_imas_core_checksum_func_show_time_block,
    uniffi_imas_core_checksum_func_similar_idols_fetch_limit,
    uniffi_imas_core_checksum_func_simple_lyrics_query,
    uniffi_imas_core_checksum_func_song_singer_quiz_answer,
    uniffi_imas_core_checksum_func_song_singer_quiz_hint_state,
    uniffi_imas_core_checksum_func_song_singer_quiz_pool_estimate,
    uniffi_imas_core_checksum_func_song_singer_quiz_session,
    uniffi_imas_core_checksum_func_song_singer_quiz_session_result,
    uniffi_imas_core_checksum_func_song_type_term,
    uniffi_imas_core_checksum_func_sort_idol_list,
    uniffi_imas_core_checksum_func_sort_idol_list_rows,
    uniffi_imas_core_checksum_func_split_credit_names,
    uniffi_imas_core_checksum_func_spoken_date,
    uniffi_imas_core_checksum_func_store_order_expenses,
    uniffi_imas_core_checksum_func_sync_chunk_progress,
    uniffi_imas_core_checksum_func_sync_classify_error,
    uniffi_imas_core_checksum_func_sync_completion_plan,
    uniffi_imas_core_checksum_func_sync_default_full_sync_interval_seconds,
    uniffi_imas_core_checksum_func_sync_default_max_fetch_retries,
    uniffi_imas_core_checksum_func_sync_next_chunk_action,
    uniffi_imas_core_checksum_func_sync_orphan_ids,
    uniffi_imas_core_checksum_func_sync_parse_composite_record_name,
    uniffi_imas_core_checksum_func_sync_partition_by_deleted,
    uniffi_imas_core_checksum_func_sync_preflight,
    uniffi_imas_core_checksum_func_sync_progress_fraction,
    uniffi_imas_core_checksum_func_sync_retry_action,
    uniffi_imas_core_checksum_func_sync_run_start_plan,
    uniffi_imas_core_checksum_func_sync_should_delete_orphans,
    uniffi_imas_core_checksum_func_sync_startup_plan,
    uniffi_imas_core_checksum_func_sync_step_failure_plan,
    uniffi_imas_core_checksum_func_sync_step_finish_plan,
    uniffi_imas_core_checksum_func_sync_step_start_plan,
    uniffi_imas_core_checksum_func_sync_steps_in_order,
    uniffi_imas_core_checksum_func_sync_supports_orphan_cleanup,
    uniffi_imas_core_checksum_func_sync_table_info,
    uniffi_imas_core_checksum_func_text_search_match_range,
    uniffi_imas_core_checksum_func_theme_color_from_hsl,
    uniffi_imas_core_checksum_func_theme_derive,
    uniffi_imas_core_checksum_func_theme_derive_batch,
    uniffi_imas_core_checksum_func_theme_derive_for_category_key,
    uniffi_imas_core_checksum_func_theme_ensure_contrast,
    uniffi_imas_core_checksum_func_theme_first_valid_hex,
    uniffi_imas_core_checksum_func_theme_hex_to_hsl,
    uniffi_imas_core_checksum_func_theme_neutral_seed,
    uniffi_imas_core_checksum_func_theme_normalized_hex,
    uniffi_imas_core_checksum_func_theme_on_color,
    uniffi_imas_core_checksum_func_theme_on_color_over,
    uniffi_imas_core_checksum_func_theme_variant_hex,
    uniffi_imas_core_checksum_func_ticket_archive,
    uniffi_imas_core_checksum_func_ticket_expense_backfill,
    uniffi_imas_core_checksum_func_ticket_expense_note,
    uniffi_imas_core_checksum_func_ticket_expense_prompt,
    uniffi_imas_core_checksum_func_ticket_kind_from_attendance,
    uniffi_imas_core_checksum_func_ticket_kind_label,
    uniffi_imas_core_checksum_func_ticket_price_range,
    uniffi_imas_core_checksum_func_ticket_price_ranges,
    uniffi_imas_core_checksum_func_ticket_sale_issue_message,
    uniffi_imas_core_checksum_func_ticket_sale_kind_raw,
    uniffi_imas_core_checksum_func_ticket_stub_date,
    uniffi_imas_core_checksum_func_tickets_for_kind,
    uniffi_imas_core_checksum_func_timeline_epoch_at_x,
    uniffi_imas_core_checksum_func_timeline_fit_points_per_day,
    uniffi_imas_core_checksum_func_timeline_hit_index,
    uniffi_imas_core_checksum_func_timeline_pack_rows,
    uniffi_imas_core_checksum_func_timeline_x,
    uniffi_imas_core_checksum_func_timeline_x_positions,
    uniffi_imas_core_checksum_func_timeline_year_boundaries,
    uniffi_imas_core_checksum_func_timeline_year_range,
    uniffi_imas_core_checksum_func_validate_expense,
    uniffi_imas_core_checksum_func_validate_ticket,
    uniffi_imas_core_checksum_func_validate_ticket_sale_draft,
    uniffi_imas_core_checksum_func_venue_mode_options,
    uniffi_imas_core_checksum_func_vocabulary,
    uniffi_imas_core_checksum_func_voice_answer_matches,
    uniffi_imas_core_checksum_func_voice_answer_targets,
    uniffi_imas_core_checksum_func_voice_needs_reading,
    uniffi_imas_core_checksum_func_voice_strip_title_decorations,
    uniffi_imas_core_checksum_func_vote_limit_per_target,
    uniffi_imas_core_checksum_func_votes_remaining,
    uniffi_imas_core_checksum_func_week_timed_layout,
    uniffi_imas_core_checksum_func_weighted_sample_indices,
    uniffi_imas_core_checksum_func_year_range_display,
    uniffi_imas_core_checksum_func_youtube_is_upload_url,
    uniffi_imas_core_checksum_func_youtube_video_refs,
    uniffi_imas_core_checksum_method_snapshotstore_next_song_recommendations,
    uniffi_imas_core_checksum_method_snapshotstore_album_summaries,
    uniffi_imas_core_checksum_method_snapshotstore_all_idols_for_picker,
    uniffi_imas_core_checksum_method_snapshotstore_all_shows_with_event_name,
    uniffi_imas_core_checksum_method_snapshotstore_all_songs_for_picker,
    uniffi_imas_core_checksum_method_snapshotstore_all_unit_records,
    uniffi_imas_core_checksum_method_snapshotstore_assistant_call_tool,
    uniffi_imas_core_checksum_method_snapshotstore_assistant_talk_instructions,
    uniffi_imas_core_checksum_method_snapshotstore_assistant_timeline_reply_instructions,
    uniffi_imas_core_checksum_method_snapshotstore_assistant_timeline_request,
    uniffi_imas_core_checksum_method_snapshotstore_attended_event_type_sets,
    uniffi_imas_core_checksum_method_snapshotstore_attended_events_with_date,
    uniffi_imas_core_checksum_method_snapshotstore_brand_records,
    uniffi_imas_core_checksum_method_snapshotstore_brand_song_counts,
    uniffi_imas_core_checksum_method_snapshotstore_branded_song_ids,
    uniffi_imas_core_checksum_method_snapshotstore_calendar_entries,
    uniffi_imas_core_checksum_method_snapshotstore_cast_show_count_ranking,
    uniffi_imas_core_checksum_method_snapshotstore_cd_series_list,
    uniffi_imas_core_checksum_method_snapshotstore_co_occurring_songs,
    uniffi_imas_core_checksum_method_snapshotstore_collection_dashboard,
    uniffi_imas_core_checksum_method_snapshotstore_costume_event_records,
    uniffi_imas_core_checksum_method_snapshotstore_costume_record,
    uniffi_imas_core_checksum_method_snapshotstore_costume_records,
    uniffi_imas_core_checksum_method_snapshotstore_costume_show_records,
    uniffi_imas_core_checksum_method_snapshotstore_daily_pick_song_ids,
    uniffi_imas_core_checksum_method_snapshotstore_edit_record_target,
    uniffi_imas_core_checksum_method_snapshotstore_event_attendance,
    uniffi_imas_core_checksum_method_snapshotstore_event_costume_records,
    uniffi_imas_core_checksum_method_snapshotstore_event_hero,
    uniffi_imas_core_checksum_method_snapshotstore_event_ids_at_venue,
    uniffi_imas_core_checksum_method_snapshotstore_event_ids_for_shows,
    uniffi_imas_core_checksum_method_snapshotstore_event_names,
    uniffi_imas_core_checksum_method_snapshotstore_event_record,
    uniffi_imas_core_checksum_method_snapshotstore_event_records,
    uniffi_imas_core_checksum_method_snapshotstore_event_releases,
    uniffi_imas_core_checksum_method_snapshotstore_event_search_sides,
    uniffi_imas_core_checksum_method_snapshotstore_event_stats,
    uniffi_imas_core_checksum_method_snapshotstore_events_with_date_by_ids,
    uniffi_imas_core_checksum_method_snapshotstore_events_with_date_by_year,
    uniffi_imas_core_checksum_method_snapshotstore_events_with_first_date,
    uniffi_imas_core_checksum_method_snapshotstore_global_search,
    uniffi_imas_core_checksum_method_snapshotstore_idol_cast_names,
    uniffi_imas_core_checksum_method_snapshotstore_idol_current_voice_actor,
    uniffi_imas_core_checksum_method_snapshotstore_idol_list,
    uniffi_imas_core_checksum_method_snapshotstore_idol_original_song_sections,
    uniffi_imas_core_checksum_method_snapshotstore_idol_performed_song_records,
    uniffi_imas_core_checksum_method_snapshotstore_idol_records_by_ids,
    uniffi_imas_core_checksum_method_snapshotstore_idol_shows,
    uniffi_imas_core_checksum_method_snapshotstore_idol_song_history_records,
    uniffi_imas_core_checksum_method_snapshotstore_idol_song_records,
    uniffi_imas_core_checksum_method_snapshotstore_idol_unit_song_ids,
    uniffi_imas_core_checksum_method_snapshotstore_idol_units,
    uniffi_imas_core_checksum_method_snapshotstore_idol_voice_actor_history,
    uniffi_imas_core_checksum_method_snapshotstore_idols_by_birth_month,
    uniffi_imas_core_checksum_method_snapshotstore_idols_by_birth_place,
    uniffi_imas_core_checksum_method_snapshotstore_idols_by_blood_type,
    uniffi_imas_core_checksum_method_snapshotstore_idols_by_constellation,
    uniffi_imas_core_checksum_method_snapshotstore_idols_by_voice_actor,
    uniffi_imas_core_checksum_method_snapshotstore_is_loaded,
    uniffi_imas_core_checksum_method_snapshotstore_kamisabi_completion,
    uniffi_imas_core_checksum_method_snapshotstore_latest_show,
    uniffi_imas_core_checksum_method_snapshotstore_listable_song_records_by_ids,
    uniffi_imas_core_checksum_method_snapshotstore_load,
    uniffi_imas_core_checksum_method_snapshotstore_meta_value,
    uniffi_imas_core_checksum_method_snapshotstore_notification_plan,
    uniffi_imas_core_checksum_method_snapshotstore_now_playing_bar,
    uniffi_imas_core_checksum_method_snapshotstore_on_this_day,
    uniffi_imas_core_checksum_method_snapshotstore_open_archives,
    uniffi_imas_core_checksum_method_snapshotstore_open_ticket_sales,
    uniffi_imas_core_checksum_method_snapshotstore_original_artist_ids_map,
    uniffi_imas_core_checksum_method_snapshotstore_original_song_ids_for_show_cast,
    uniffi_imas_core_checksum_method_snapshotstore_performed_unit_ids,
    uniffi_imas_core_checksum_method_snapshotstore_pick_similar_idols,
    uniffi_imas_core_checksum_method_snapshotstore_related_songs,
    uniffi_imas_core_checksum_method_snapshotstore_search_counts,
    uniffi_imas_core_checksum_method_snapshotstore_search_events_by_name_or_venue,
    uniffi_imas_core_checksum_method_snapshotstore_search_idols,
    uniffi_imas_core_checksum_method_snapshotstore_search_shows_with_event_name,
    uniffi_imas_core_checksum_method_snapshotstore_search_songs,
    uniffi_imas_core_checksum_method_snapshotstore_series_group_names,
    uniffi_imas_core_checksum_method_snapshotstore_series_summaries,
    uniffi_imas_core_checksum_method_snapshotstore_setlist_forecast,
    uniffi_imas_core_checksum_method_snapshotstore_setlist_item_costume_records,
    uniffi_imas_core_checksum_method_snapshotstore_setlist_quiz_pool_estimate,
    uniffi_imas_core_checksum_method_snapshotstore_setlist_quiz_session,
    uniffi_imas_core_checksum_method_snapshotstore_show_cast_idol_ids,
    uniffi_imas_core_checksum_method_snapshotstore_show_costume_records,
    uniffi_imas_core_checksum_method_snapshotstore_show_record,
    uniffi_imas_core_checksum_method_snapshotstore_show_setlist,
    uniffi_imas_core_checksum_method_snapshotstore_show_setlist_performers,
    uniffi_imas_core_checksum_method_snapshotstore_show_setlist_row_meta,
    uniffi_imas_core_checksum_method_snapshotstore_show_title,
    uniffi_imas_core_checksum_method_snapshotstore_shows_at_venue,
    uniffi_imas_core_checksum_method_snapshotstore_shows_by_event,
    uniffi_imas_core_checksum_method_snapshotstore_shows_on_date,
    uniffi_imas_core_checksum_method_snapshotstore_singers_for_song,
    uniffi_imas_core_checksum_method_snapshotstore_song_artist_ids,
    uniffi_imas_core_checksum_method_snapshotstore_song_collected_count_map,
    uniffi_imas_core_checksum_method_snapshotstore_song_collected_shows,
    uniffi_imas_core_checksum_method_snapshotstore_song_ids_with_any_artist,
    uniffi_imas_core_checksum_method_snapshotstore_song_list,
    uniffi_imas_core_checksum_method_snapshotstore_song_performance_count_map,
    uniffi_imas_core_checksum_method_snapshotstore_song_performance_counts,
    uniffi_imas_core_checksum_method_snapshotstore_song_performance_history,
    uniffi_imas_core_checksum_method_snapshotstore_song_performance_insights,
    uniffi_imas_core_checksum_method_snapshotstore_song_performer_idol_ids_map,
    uniffi_imas_core_checksum_method_snapshotstore_song_play_count_ranking,
    uniffi_imas_core_checksum_method_snapshotstore_song_records_by_ids,
    uniffi_imas_core_checksum_method_snapshotstore_songs_by_cd_series,
    uniffi_imas_core_checksum_method_snapshotstore_songs_by_creator,
    uniffi_imas_core_checksum_method_snapshotstore_songs_by_ids_ordered,
    uniffi_imas_core_checksum_method_snapshotstore_songs_by_release_year,
    uniffi_imas_core_checksum_method_snapshotstore_songs_by_series_group,
    uniffi_imas_core_checksum_method_snapshotstore_theme_derive_batch_for_brand_ids,
    uniffi_imas_core_checksum_method_snapshotstore_theme_derive_for_brand_id,
    uniffi_imas_core_checksum_method_snapshotstore_ticket_board,
    uniffi_imas_core_checksum_method_snapshotstore_ticket_sale_deadlines,
    uniffi_imas_core_checksum_method_snapshotstore_ticket_sale_spotlight,
    uniffi_imas_core_checksum_method_snapshotstore_ticket_sales_for_event,
    uniffi_imas_core_checksum_method_snapshotstore_timeline_bars,
    uniffi_imas_core_checksum_method_snapshotstore_unit_ids_with_songs,
    uniffi_imas_core_checksum_method_snapshotstore_unit_index_record,
    uniffi_imas_core_checksum_method_snapshotstore_unit_member_idol_ids,
    uniffi_imas_core_checksum_method_snapshotstore_unit_record,
    uniffi_imas_core_checksum_method_snapshotstore_unit_song_ids,
    uniffi_imas_core_checksum_method_snapshotstore_unload,
    uniffi_imas_core_checksum_method_snapshotstore_variant_song_records,
    uniffi_imas_core_checksum_method_snapshotstore_venue_directory,
    uniffi_imas_core_checksum_method_snapshotstore_venues_matching,
    uniffi_imas_core_checksum_method_snapshotstore_yearly_show_counts,
    uniffi_imas_core_checksum_method_textsearchcatalog_matching_indices,
}

/// リンク検査は「消えた・改名された」しか捕まえず、**増えた分は素通りする**
/// (回帰: Phase 6/8 で 36 件、メソッドは 104 本が一度も見られていなかった)。
/// inbound のソースから読んだエクスポートの全量と、上の一覧を名前で突き合わせる。
#[test]
fn declared_checksums_match_inbound_exports() {
    let exported = inbound_export_symbols();
    let declared: BTreeSet<String> = DECLARED.iter().map(|s| s.to_string()).collect();
    let as_lines = |names: Vec<&String>| {
        names
            .iter()
            .map(|s| format!("    {s},"))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let missing = as_lines(exported.difference(&declared).collect());
    let stale = as_lines(declared.difference(&exported).collect());
    assert!(
        missing.is_empty() && stale.is_empty(),
        "inbound のエクスポートと declare_and_call_checksums! の一覧が食い違っている。\n\
         一覧に足す行:\n{missing}\n一覧から消す行:\n{stale}"
    );
}

/// UniFFI が checksum を生やすエクスポートを、inbound のソースから全部拾う。
///
/// - `#[uniffi::export]` + `fn f` → `func_f` (`#[uniffi::export(default(..))]` も同じ名前)
/// - `#[uniffi::export]` + `impl T {` → 中の `fn m` ごとに `method_t_m`。
///   `#[uniffi::constructor]` が付いたものは `constructor_t_m`
///
/// UniFFI 0.32 は、export したブロックの中の fn を `pub` かどうかに関係なく全部 export する。
/// なので `pub` の有無・`pub(crate)`・`async` などを問わず、fn はすべて数える。
///
/// impl ブロックは「0 桁目の `}` で閉じ、メソッドは 4 桁下げ」というこのリポジトリの
/// 書き方を前提に読む。前提が崩れて拾い損ねたら、一覧との食い違いとして落ちる。
fn inbound_export_symbols() -> BTreeSet<String> {
    let mut symbols = BTreeSet::new();
    let mut stack = vec![Path::new(env!("CARGO_MANIFEST_DIR")).join("src/inbound")];
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
            let mut lines = text.lines();
            while let Some(line) = lines.next() {
                let line = line.trim_start();
                if !line.starts_with("#[uniffi::export") {
                    continue;
                }
                // `default(...)` は引数の既定値だけで、シンボル名は変わらない。
                assert!(
                    line == "#[uniffi::export]" || line.starts_with("#[uniffi::export(default("),
                    "{}: 引数付きの export はシンボル名が変わるので、このテストの読み方を足すこと",
                    path.display()
                );
                // 属性とコメントを読み飛ばして、対象の宣言に着く。
                let item = lines
                    .by_ref()
                    .map(str::trim_start)
                    .find(|l| !l.is_empty() && !l.starts_with("//") && !l.starts_with("#["))
                    .expect("#[uniffi::export] の後に宣言がある");
                if let Some(name) = fn_name(item) {
                    symbols.insert(format!("uniffi_imas_core_checksum_func_{name}"));
                    continue;
                }
                let object = item
                    .strip_prefix("impl ")
                    .and_then(|rest| {
                        rest.split(|c: char| !c.is_alphanumeric() && c != '_')
                            .next()
                    })
                    .unwrap_or_else(|| {
                        panic!("{}: 関数でも impl でもない export: {item}", path.display())
                    })
                    .to_lowercase();
                let mut constructor = false;
                for member in lines.by_ref().take_while(|l| *l != "}") {
                    if member.trim() == "#[uniffi::constructor]" {
                        constructor = true;
                    }
                    if let Some(name) = member.strip_prefix("    ").and_then(fn_name) {
                        let kind = if constructor { "constructor" } else { "method" };
                        symbols.insert(format!("uniffi_imas_core_checksum_{kind}_{object}_{name}"));
                        constructor = false;
                    }
                }
            }
        }
    }
    symbols
}

/// fn の宣言行 (`fn name(…` / `fn name<…`) の name。先頭の可視性 (`pub` / `pub(crate)` など) と
/// `const` / `async` / `unsafe` は読み飛ばす。fn の宣言でなければ None。
fn fn_name(line: &str) -> Option<&str> {
    let mut rest = line;
    if let Some(after_pub) = rest.strip_prefix("pub") {
        rest = match after_pub.strip_prefix('(') {
            Some(scoped) => scoped.split_once(')')?.1.trim_start(),
            None => after_pub.strip_prefix(' ')?,
        };
    }
    for qualifier in ["const ", "async ", "unsafe "] {
        rest = rest.strip_prefix(qualifier).unwrap_or(rest);
    }
    rest.strip_prefix("fn ")?.split(['(', '<']).next()
}
