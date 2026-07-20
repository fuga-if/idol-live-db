#!/usr/bin/env bash
# ============================================================================
# push_v59_delta.sh — data_version 59 の CloudKit Production 逆同期マニフェスト
# ============================================================================
# 背景:
#   db/master.sql(v59, commit 12dc888) には、CloudKit Production に未反映の
#   「v58 実体デルタ + 原唱者修正(修正1) + SideM「Ｗ」是正(修正2)」が含まれる。
#   日次 cron(refresh-data.yml, 03:00 JST) は export_cloudkit で synced テーブルを
#   CloudKit から全置換するため、**これを push しないと次の cron で git から消える**。
#   (song_units / meta は非同期テーブルなので push 不要)
#
# 使い方:
#   検証(ネットワーク無し・鍵不要):  bash tools/push_v59_delta.sh --dry-run
#   本番反映(要 CLOUDKIT_KEY_ID):    CLOUDKIT_KEY_ID=$KID bash tools/push_v59_delta.sh
#
# baseline: dffbaa7(v56, 最後の既知 db/master.sql ≈ CloudKit) との内容 diff で算出。
#   seed_cloudkit は forceUpdate(冪等 upsert) なので、既存レコードの再 push は無害。
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRYRUN=""
if [ "${1:-}" = "--dry-run" ]; then DRYRUN="--dry-run"; fi
SEED=(python3 tools/seed_cloudkit.py --production $DRYRUN)

if [ -z "$DRYRUN" ] && [ -z "${CLOUDKIT_KEY_ID:-}" ]; then
  echo "本番反映には CLOUDKIT_KEY_ID が必要 (検証は --dry-run)"; exit 1
fi

# --- upsert 対象 (依存順: idols/units/songs → unit_members/song_artists) --------

# idols(4): 新規 876_秋月涼 / gakuen_賀陽燐羽 + v58 でプロフィール変更 ml_伴田路子 / sidem_アスランbbⅱ世
"${SEED[@]}" --tables idols --ids '876_秋月涼,gakuen_賀陽燐羽,ml_伴田路子,sidem_アスランbbⅱ世'

# units(7): 新規 gakuen 4(REVERSI/RippleSign/SyngUp!/ゆめぱしー) + brand補正3(RGP/RedQueen/VΔLZ を 765as→other)
"${SEED[@]}" --tables units --ids 'unit_real_girls_project,unit_red_queen,unit_vδlz,unit_reversi,unit_ripplesign,unit_syngup,unit_ゆめぱしー'

# songs(42): v58 のメタ補正(gakuen/sidem の unit_id 補完、315_steelo・組曲の singer_label 補正、sc game_size 群 等)
"${SEED[@]}" --tables songs --ids '876_ソライロ_vα-liv_ver,gakuen_sugar_flavor,gakuen_ときめきエモーション,gakuen_みちなるひろがる,sc_beast_mode_game_size,sc_karma_game_size,sc_kawaiiめたもる交響曲_game_size,sc_mytime_game_size,sc_naraku_game_size,sc_oh_yeah_game_size,sc_one_live_one_love_game_size,sc_queen_of_the_pirates_game_size,sc_sleepless_nights_game_size,sc_super_duper_dreamer_game_size,sc_tokyo自由系ガール_game_size,sc_アイノウ_game_size,sc_カウントダウンラブ_game_size,sc_キラピコexe_game_size,sc_ボーダーレスノンストレス_game_size,sc_感謝のコントレイル_game_size,sc_散花-sanka-_game_size,sc_紅花-benibana-_game_size,sidem_315_steelo,sidem_after_the_rain,sidem_amazing_moment,sidem_azur,sidem_datetoday,sidem_dont_u_worry,sidem_feeeel_gooood,sidem_growingroovin,sidem_leading_your_dream,sidem_lets_go_all_the_way,sidem_meet_the_world,sidem_our_colorful_stage,sidem_play_for_fun-tasy,sidem_sunrise_dreamer,sidem_super_kick_rap,sidem_supreme_stars_who_goes_first_ver,sidem_vivaファミリーリズム,sidem_watchword,sidem_yell_of_delight,sidem_組曲_-to_all_ages_concerto-'

# unit_members: --ids 非対応(複合PK)のため全テーブル push。
#   影響: 全 unit_members(約5300件)を forceUpdate で再 upsert(冪等)。実差分は新規9件 + 秋月涼 repoint 3件。
"${SEED[@]}" --tables unit_members

# song_artists(対象12曲=85行): 修正1の原唱者20行 + 315_steelo/組曲の原唱者8行を含む。--ids で song_id 絞り込み。
"${SEED[@]}" --tables song_artists --ids '765as_キミはメロディ,876_shininmagic,876_syncmylights,876_エンジェルドリーム,876_トアルトワ,876_ワンダーモモ,gakuen_howling_over_the_world,gakuen_古今東西ちょちょいのちょい,sidem_315_steelo,sidem_我が混沌のサバトマリアージュ,sidem_暗黒への前奏曲,sidem_組曲_-to_all_ages_concerto-'

# --- 削除 (upsert 後・46件) --------------------------------------------------
#   双海の誤紐付け40 + 幻ユニット unit_w 1 + unit_w双海メンバー2 + 秋月涼 repoint 前の残骸3
DELFILE="$ROOT/tools/pending_cloudkit_deletions_20260720.tsv"
if [ -n "$DRYRUN" ]; then
  "${SEED[@]}" --delete-file "$DELFILE"
else
  "${SEED[@]}" --delete-file "$DELFILE" --yes
fi

echo "✓ push_v59_delta 完了"
