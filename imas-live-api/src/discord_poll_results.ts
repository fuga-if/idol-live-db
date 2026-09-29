// discord_poll_results.ts — 締め切った「みんなの投票」のお題の結果を Discord の #投票結果 に出す。
//
// 5 分 cron (scheduled.ts の EVERY_RUN) から呼ぶ。どこまで出したかは discord_digest_cursors の
// source = 'poll_results' に「最後に出したお題の締切 (UNIX 秒)」として持つ (last_rowid 列を流用)。
// 位置がまだ無ければ今の時刻を入れるだけで、過去のお題は流さない。
// 投稿に成功したお題の分だけ位置を進めるので、Discord が落ちていても次の回に出る。
//
// #投票結果 はアナウンスチャンネルなので、投稿後に公開 (crosspost) してフォロー先にも届ける。
// 公開に失敗しても投稿は済んでいるので、位置は進める。
//
// ⚠️ 投票した人・お題を作った人は出さない。お題名は埋め込みの title (Markdown を解釈しない) にだけ入れ、
//    メンションは allowed_mentions で止める。

import { link, lookupNames } from "./discord_digest";
import type { Env } from "./env";

const WEB_BASE = "https://idollivedb.fugaapp.site";
const DISCORD_API = "https://discord.com/api/v10";
const CURSOR = "poll_results";
/** 1 回に出すお題の上限。超えた分は次の回。 */
const POLL_LIMIT = 5;
/** 結果に並べる順位の数。 */
const TOP = 3;
const MEDALS = ["🥇", "🥈", "🥉"];
const RESULT_COLOR = 0xf2b035;

type PollEnv = Pick<Env, "DB"> & Partial<Env>;

interface EndedPoll {
  id: string;
  title: string;
  target_type: string;
  ends: number;
}

interface Entry {
  entity_id: string;
  vote_count: number;
}

function entityUrl(targetType: string, id: string): string {
  const path = targetType === "idol" ? "idols" : targetType === "unit" ? "units" : "songs";
  return `${WEB_BASE}/${path}/${encodeURIComponent(id)}/`;
}

/** 投稿したメッセージをアナウンスチャンネルで公開する。失敗しても投げない。 */
async function crosspost(env: PollEnv, channelId: string, messageId: string): Promise<void> {
  try {
    await fetch(`${DISCORD_API}/channels/${channelId}/messages/${messageId}/crosspost`, {
      method: "POST",
      headers: { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}` },
    });
  } catch {
    // 公開できなくてもチャンネルには出ている。
  }
}

export async function postPollResults(env: PollEnv): Promise<void> {
  const channelId = env.DISCORD_POLL_RESULTS_CHANNEL_ID;
  if (!env.DISCORD_BOT_TOKEN || !channelId) return;

  const cursorRow = await env.DB.prepare("SELECT last_rowid FROM discord_digest_cursors WHERE source = ?")
    .bind(CURSOR)
    .first<{ last_rowid: number }>();
  if (!cursorRow) {
    await env.DB.prepare(
      "INSERT OR IGNORE INTO discord_digest_cursors (source, last_rowid) VALUES (?, CAST(strftime('%s', 'now') AS INTEGER))"
    )
      .bind(CURSOR)
      .run();
    return;
  }

  const ended = await env.DB.prepare(
    `SELECT id, title, target_type, CAST(strftime('%s', ends_at) AS INTEGER) AS ends
       FROM polls
      WHERE status = 'active' AND ends_at <= datetime('now') AND ends_at > datetime(?, 'unixepoch')
      ORDER BY ends_at ASC, id ASC
      LIMIT ${POLL_LIMIT}`
  )
    .bind(Number(cursorRow.last_rowid))
    .all<EndedPoll>();
  const polls = ended.results ?? [];
  if (polls.length === 0) return;

  const entryResults = await env.DB.batch(
    polls.map((p) =>
      env.DB.prepare(
        `SELECT entity_id, vote_count FROM poll_entries
          WHERE poll_id = ? AND vote_count > 0
          ORDER BY vote_count DESC, first_voted_at ASC
          LIMIT ${TOP}`
      ).bind(p.id)
    )
  );
  const totals = await env.DB.batch(
    polls.map((p) => env.DB.prepare("SELECT COALESCE(SUM(vote_count), 0) AS total FROM poll_entries WHERE poll_id = ?").bind(p.id))
  );
  const entriesOf = polls.map((_, i) => (entryResults[i].results ?? []) as Entry[]);

  const info = await lookupNames(env, [...new Set(entriesOf.flat().map((e) => e.entity_id))]);

  let advanceTo: number | null = null;
  for (let i = 0; i < polls.length; i++) {
    const poll = polls[i];
    const entries = entriesOf[i];
    // 1 票も入らなかったお題は出さない (位置だけ進める)。
    if (entries.length > 0) {
      const total = Number((totals[i].results?.[0] as { total?: number } | undefined)?.total ?? 0);
      const ranking = entries
        .map((e, rank) => {
          const name = info.get(e.entity_id)?.name ?? e.entity_id;
          return `${MEDALS[rank]} ${link(name, entityUrl(poll.target_type, e.entity_id))}　${e.vote_count}票`;
        })
        .join("\n");
      const winnerArt = info.get(entries[0].entity_id)?.artworkUrl;
      const res = await fetch(`${DISCORD_API}/channels/${channelId}/messages`, {
        method: "POST",
        headers: { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          allowed_mentions: { parse: [] },
          embeds: [
            {
              title: `🗳️ 「${poll.title}」の結果`.slice(0, 256),
              url: `${WEB_BASE}/polls/`,
              description: `${ranking}\n\n合計 ${total}票`,
              color: RESULT_COLOR,
              ...(winnerArt ? { thumbnail: { url: winnerArt } } : {}),
            },
          ],
        }),
      });
      if (!res.ok) break; // ここで止めて、次の回にこのお題から出し直す
      const posted = (await res.json().catch(() => ({}))) as { id?: string };
      if (posted.id) await crosspost(env, channelId, posted.id);
    }
    advanceTo = poll.ends;
  }

  if (advanceTo !== null) {
    await env.DB.prepare("UPDATE discord_digest_cursors SET last_rowid = ? WHERE source = ?").bind(advanceTo, CURSOR).run();
  }
}
