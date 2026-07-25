package com.fugaif.imaslivedb.ui.share

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// =============================================================================
// テキストシェア (X 投稿 / 標準シェアシート)。iOS SocialShare.swift の移植。
// =============================================================================

/** シェア用 Universal Links URL の生成 (iOS DeeplinkBuilder の移植)。 */
object ShareLinkBuilder {
    private const val BASE = "https://imas-live-api.tokata3011.workers.dev"

    fun pollUrl(id: String): String = "$BASE/app/polls/${Uri.encode(id)}"

    fun showUrl(id: String): String = "$BASE/app/shows/${Uri.encode(id)}"
}

/**
 * シェアする一言 + 着地先 URL。
 * X の intent は本文と URL を別パラメータで受けるとリンクカードが出るので、分けて保持する。
 */
data class SocialSharePayload(val message: String, val url: String? = null) {
    /** 標準シェアシート用のプレーンテキスト。 */
    val plainText: String get() = if (url == null) message else "$message\n$url"
}

object SocialShare {
    /** X (Twitter) の投稿画面 URL。X アプリ未インストールでもブラウザの投稿画面に着地する。 */
    fun xPostUrl(payload: SocialSharePayload): String {
        val builder = Uri.parse("https://x.com/intent/post").buildUpon()
            .appendQueryParameter("text", payload.message)
        payload.url?.let { builder.appendQueryParameter("url", it) }
        return builder.build().toString()
    }

    fun postToX(context: Context, payload: SocialSharePayload) {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(xPostUrl(payload))))
    }

    fun shareSheet(context: Context, payload: SocialSharePayload) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, payload.plainText)
        }
        context.startActivity(Intent.createChooser(intent, null))
    }
}

/** 投票系シェアの文面ビルダー。ハッシュタグはアプリ共通の #アイドルライブDB に揃える。 */
object ShareMessage {
    const val HASHTAG = "#アイドルライブDB"

    /** 「A」「B」「C」形式。 */
    fun quoted(names: List<String>): String = names.joinToString("") { "「$it」" }

    /** みんなの投票 (お題) への投票シェア。 */
    fun pollVotes(pollTitle: String, entityNames: List<String>): String =
        "お題「$pollTitle」で${quoted(entityNames)}に投票しました！ $HASHTAG"

    /**
     * お題への誘いシェアのペイロード。一覧と詳細で文面/リンクがズレないよう組み立てはここだけ
     * (iOS の `SocialSharePayload.pollInvite(poll:)` と対)。締切は開催中のときだけ載せる。
     */
    fun pollInvitePayload(id: String, title: String, endsAtMs: Long?, isActive: Boolean) =
        SocialSharePayload(
            message = pollInvite(title, endsAtMs.takeIf { isActive }),
            url = ShareLinkBuilder.pollUrl(id)
        )

    /** お題そのもののシェア (まだ投票していない人への誘い)。endsAtMs が未知なら締切は省く。 */
    fun pollInvite(title: String, endsAtMs: Long?): String {
        val deadline = endsAtMs
            ?.takeIf { it != Long.MAX_VALUE }
            ?.let { " 締切は${deadlineFormat.format(Date(it))}！" }
            .orEmpty()
        return "お題「$title」に投票しよう！$deadline $HASHTAG"
    }

    private val deadlineFormat = SimpleDateFormat("M月d日", Locale.JAPAN)
}

/**
 * 「X にポスト」/「その他でシェア」のドロップダウンを開くトリガー。
 * iOS の `SocialShareMenu<MenuLabel>` と同じく、開閉の配線はここ 1 箇所に持ち、
 * 見た目 (アイコン/チップ) だけ呼び出し側が差し替える。
 */
@Composable
fun SocialShareMenu(
    payload: SocialSharePayload,
    trigger: @Composable (onClick: () -> Unit) -> Unit
) {
    val context = LocalContext.current
    var expanded by remember { mutableStateOf(false) }
    Box {
        trigger { expanded = true }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text("X にポスト") },
                leadingIcon = { Icon(Icons.AutoMirrored.Filled.Send, contentDescription = null) },
                onClick = {
                    expanded = false
                    SocialShare.postToX(context, payload)
                }
            )
            DropdownMenuItem(
                text = { Text("その他でシェア") },
                leadingIcon = { Icon(Icons.Filled.Share, contentDescription = null) },
                onClick = {
                    expanded = false
                    SocialShare.shareSheet(context, payload)
                }
            )
        }
    }
}

/** アイコンボタン版のトリガー (ツールバー・カード右上用)。 */
@Composable
fun SocialShareIconButton(
    payload: SocialSharePayload,
    contentDescription: String = "シェア",
    tint: Color = DS.ink2
) {
    SocialShareMenu(payload) { onClick ->
        IconButton(onClick = onClick) {
            Icon(Icons.Filled.Share, contentDescription = contentDescription, tint = tint)
        }
    }
}

/** チップ (淡い塗りのカプセル) 版のトリガー。行末に置く投票シェア用。 */
@Composable
fun SocialShareChip(
    title: String,
    payload: SocialSharePayload,
    accent: Color = DS.pick
) {
    SocialShareMenu(payload) { onClick ->
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .background(accent.copy(alpha = 0.12f))
                .clickable(onClick = onClick)
                .padding(horizontal = 12.dp, vertical = 7.dp)
        ) {
            Icon(Icons.Filled.Share, contentDescription = null, tint = accent, modifier = Modifier.size(14.dp))
            Text(
                title,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = accent,
                modifier = Modifier.padding(start = 5.dp)
            )
        }
    }
}
