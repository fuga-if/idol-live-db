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
import uniffi.imas_core.SharePayload
import uniffi.imas_core.sharePayloadPlainText
import uniffi.imas_core.sharePayloadXPostUrl
import uniffi.imas_core.sharePollInvitePayload
import uniffi.imas_core.sharePollVotesPayload
import java.util.TimeZone

// =============================================================================
// テキストシェア (X 投稿 / 標準シェアシート)。
//
// 文面と URL (本文・着地先・X の投稿画面の URL・シェアシートに渡す本文) はコア
// (share_text) が作る (iOS と同じ文面)。ここは Android のシェアシートと X の起動だけ。
// =============================================================================

object SocialShare {
    /** X の投稿画面を開く。X アプリ未インストールでもブラウザの投稿画面に着地する。 */
    fun postToX(context: Context, payload: SharePayload) {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(sharePayloadXPostUrl(payload))))
    }

    /** 標準シェアシートで本文 + URL を渡す。 */
    fun shareSheet(context: Context, payload: SharePayload) = shareText(context, sharePayloadPlainText(payload))

    /** 標準シェアシートで本文だけを渡す (文面をコアが作り終えているもの)。 */
    fun shareText(context: Context, text: String) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        context.startActivity(Intent.createChooser(intent, null))
    }
}

/** 投票系のシェアの材料をコアに渡す口。一覧と詳細で同じ文面・同じリンクになる。 */
object ShareMessage {
    /**
     * お題そのもののシェア (まだ投票していない人への誘い)。締切は開催中のときだけ載る。
     * 締切を「何月何日」に直すための端末の TZ のずれは、締切の時点のものを渡す (iOS と同じ)。
     */
    fun pollInvitePayload(id: String, title: String, endsAtMs: Long?, isActive: Boolean): SharePayload {
        // 締切が未知の値 (Long.MAX_VALUE) は「締切なし」として渡す。
        val endsAt = endsAtMs?.takeIf { it != Long.MAX_VALUE }
        val tzOffsetSeconds = TimeZone.getDefault().getOffset(endsAt ?: System.currentTimeMillis()) / 1000
        return sharePollInvitePayload(id, title, endsAt, isActive, tzOffsetSeconds)
    }

    /** みんなの投票で「〇〇に投票しました！」。 */
    fun pollVotesPayload(pollId: String, pollTitle: String, entityNames: List<String>): SharePayload =
        sharePollVotesPayload(pollId, pollTitle, entityNames)
}

/**
 * 「X にポスト」/「その他でシェア」のドロップダウンを開くトリガー。
 * iOS の `SocialShareMenu<MenuLabel>` と同じく、開閉の配線はここ 1 箇所に持ち、
 * 見た目 (アイコン/チップ) だけ呼び出し側が差し替える。
 */
@Composable
fun SocialShareMenu(
    payload: SharePayload,
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
    payload: SharePayload,
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
    payload: SharePayload,
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
