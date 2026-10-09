package com.fugaif.imaslivedb.ui.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTile
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasMockBrowser
import com.fugaif.imaslivedb.ui.designsystem.ImasMockButton
import com.fugaif.imaslivedb.ui.designsystem.ImasMockCheck
import com.fugaif.imaslivedb.ui.designsystem.ImasMockField
import com.fugaif.imaslivedb.ui.designsystem.ImasStep
import com.fugaif.imaslivedb.ui.designsystem.ImasStepList
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import uniffi.imas_core.spotifySetupGuide

/**
 * Spotify 連携の始め方を、Spotify の開発者サイトの画面を模した図つきで案内する画面。iOS `SpotifyHowToView`。
 * 使い方の「Spotify と連携する」と、設定の「Spotify」から開く。
 *
 * 手順の題と説明・注意はコア (`spotifySetupGuide`) が持つ (設定の画面と同じ文)。
 * 図の中の英語は Spotify の画面に出る表記そのまま (探すときに同じ字面で見つけられるように)。
 *
 * @param onOpenSettings 「Spotify の設定を開く」。null なら出さない (設定の画面から開いたときは戻ればよい)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SpotifyHowToScreen(onBack: () -> Unit, onOpenSettings: (() -> Unit)? = null) {
    val guide = remember { spotifySetupGuide() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Spotify と連携する") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                }
            )
        }
    ) { padding ->
        ImasFormBackdrop(Modifier.fillMaxSize().padding(padding)) {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = DS.Space.screen, vertical = DS.Space.gapLoose),
                verticalArrangement = Arrangement.spacedBy(DS.Space.section),
            ) {
                Column(
                    Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
                ) {
                    ImasIconTile(Icons.AutoMirrored.Filled.QueueMusic, size = ImasIconTileSize.S56, tone = ImasIconTileTone.SOLID)
                    ImasText("Spotify と連携する", role = ImasTextRole.CARD_TITLE)
                    ImasText(guide.lead, role = ImasTextRole.NOTE, textAlign = TextAlign.Center)
                }
                guide.steps.forEachIndexed { index, step ->
                    ImasCard {
                        ImasStepList(
                            steps = listOf(ImasStep(step.title, step.detail) { Illustration(index, guide.dashboardUrl, guide.redirectUri) }),
                            startIndex = index + 1,
                        )
                    }
                }
                ImasCard {
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                        guide.notes.forEach { Tip(Icons.Filled.Info, it) }
                        guide.troubleshooting.forEach { Tip(Icons.Filled.Warning, it) }
                    }
                }
                if (onOpenSettings != null) {
                    ImasButton(
                        title = "Spotify の設定を開く",
                        onClick = onOpenSettings,
                        icon = Icons.AutoMirrored.Filled.QueueMusic,
                        size = ImasButtonSize.LARGE,
                    )
                }
            }
        }
    }
}

@Composable
private fun Tip(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        Icon(icon, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(16.dp))
        ImasText(text, role = ImasTextRole.NOTE, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun Illustration(index: Int, dashboardUrl: String, redirectUri: String) {
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        when (index) {
            0 -> {
                ImasMockBrowser("developer.spotify.com/dashboard") {
                    ImasText("Dashboard", role = ImasTextRole.ROW_TITLE)
                    ImasMockButton("Log in", isTarget = true)
                }
                ImasButton(
                    title = "開発者サイトを開く",
                    onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(dashboardUrl))) },
                    icon = Icons.Filled.Language,
                    role = ImasButtonRole.SECONDARY,
                    size = ImasButtonSize.SMALL,
                )
            }
            1 -> ImasMockBrowser("developer.spotify.com/dashboard") {
                ImasMockButton("Create app", isTarget = true)
                ImasMockField("App name", "アイドルライブDB")
                ImasMockField("App description", "アイマスのライブの記録")
            }
            2 -> {
                ImasMockBrowser("developer.spotify.com/dashboard/create") {
                    ImasMockField("Redirect URIs", redirectUri, isTarget = true)
                    ImasMockButton("Add", isTarget = true)
                }
                CopyRedirectUriButton(redirectUri)
            }
            3 -> ImasMockBrowser("developer.spotify.com/dashboard/create") {
                ImasText("Which API/SDKs are you planning to use?", role = ImasTextRole.META)
                ImasMockCheck("Web API", isChecked = true)
                ImasMockCheck("Web Playback SDK")
                ImasMockCheck("Android")
                ImasMockCheck("iOS")
                ImasMockButton("Save", isTarget = true)
            }
            else -> ImasMockBrowser("developer.spotify.com/dashboard/…/settings") {
                ImasText("Basic Information", role = ImasTextRole.ROW_TITLE)
                ImasMockField("Client ID", "1a2b3c4d5e6f…", isTarget = true)
                ImasMockField("Client secret", "View client secret", isUnused = true)
            }
        }
    }
}

@Composable
private fun CopyRedirectUriButton(value: String) {
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    var copied by remember { mutableStateOf(false) }
    ImasButton(
        title = if (copied) "コピー済み" else "Redirect URI をコピー",
        onClick = {
            clipboard.setText(AnnotatedString(value))
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            copied = true
        },
        icon = if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy,
        role = ImasButtonRole.SECONDARY,
        size = ImasButtonSize.SMALL,
    )
}
