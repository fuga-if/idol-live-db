package com.fugaif.imaslivedb.ui.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.RoutedLyricsPlayback
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRowKind
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceDialog
import com.fugaif.imaslivedb.ui.designsystem.ImasCopyField
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasMenuRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPoint
import com.fugaif.imaslivedb.ui.designsystem.ImasPointList
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasStep
import com.fugaif.imaslivedb.ui.designsystem.ImasStepList
import com.fugaif.imaslivedb.ui.designsystem.ImasTextFieldRow
import com.fugaif.imaslivedb.ui.designsystem.ImasValueRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import uniffi.imas_core.FullPlaybackService
import uniffi.imas_core.fullPlaybackOptions
import uniffi.imas_core.spotifyCheckClientId
import uniffi.imas_core.SpotifyGuidePlatform
import uniffi.imas_core.spotifySetupGuide

/** 設定の「Spotify」の行。状態を出して、案内の画面へ進む。iOS `SpotifySettingsRow`。 */
@Composable
fun SpotifySettingsRow(onOpen: () -> Unit) {
    val state by AppModule.from(LocalContext.current).spotifyService.state.collectAsState()
    ImasNavRow(
        title = if (state.isConnected) state.accountName ?: "Spotify" else "Spotify と連携",
        subtitle = if (state.isConnected) "Spotify でフル尺で鳴らし、書き出せます"
        else "自分の Spotify アプリの Client ID で使います",
        icon = Icons.AutoMirrored.Filled.QueueMusic,
        value = if (state.isConnected) "連携中" else null,
        onClick = onOpen,
    )
}

/**
 * Spotify 連携の案内と状態。iOS `SpotifySettingsView`。手順・貼る値・注意の文言はコア (`spotifySetupGuide`)。
 *
 * 連携していなければ、上から順にやれば終わるように「アプリを作る手順 → Client ID → ログイン」と並べる。
 * 手順の中で要る操作 (開発者サイトを開く・Redirect URI を写す) はその手順の真下に置く。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SpotifySettingsScreen(onBack: () -> Unit) {
    var showsHowTo by remember { mutableStateOf(false) }
    if (showsHowTo) {
        SpotifyHowToScreen(onBack = { showsHowTo = false })
        return
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Spotify") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                }
            )
        }
    ) { padding ->
        ImasFormBackdrop(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                SpotifySettingsContent(onOpenHowTo = { showsHowTo = true })
            }
        }
    }
}

/**
 * 設定の画面と書き出しのシートで同じ中身。
 *
 * @param onOpenHowTo 図つきの手順へ進む。null なら入口を出さない (シートの中から画面を積まない)。
 */
@Composable
fun SpotifySettingsContent(onOpenHowTo: (() -> Unit)? = null) {
    val service = AppModule.from(LocalContext.current).spotifyService
    val state by service.state.collectAsState()
    if (state.isConnected) ConnectedSections() else SetupSections(onOpenHowTo)
    ImasErrorAlert(message = state.signInError, onDismiss = service::clearSignInError, title = "Spotify にログインできませんでした")
}

@Composable
private fun ConnectedSections() {
    val service = AppModule.from(LocalContext.current).spotifyService
    val state by service.state.collectAsState()
    var confirmSignOut by remember { mutableStateOf(false) }
    ImasListSection("Spotify") {
        ImasRow(
            title = state.accountName ?: "Spotify アカウント",
            subtitle = "連携中",
            leading = ImasRowLeading.Icon(Icons.Filled.Verified, tone = ImasIconTileTone.SOLID),
            titleRole = ImasTextRole.ROW_LABEL,
        )
        state.clientId?.let { ImasValueRow(key = "Client ID", value = masked(it), monospaced = true) }
    }
    PlaybackSection()
    ImasListSection("できること") {
        ImasPointList(
            points = listOf(
                ImasPoint(Icons.AutoMirrored.Filled.QueueMusic, "公演のメニューから、セトリを Spotify のプレイリストにできます。"),
                ImasPoint(Icons.AutoMirrored.Filled.PlaylistAdd, "自分のプレイリストを Spotify に書き出せます。"),
                ImasPoint(Icons.Filled.PlayArrow, "曲を Spotify でフル尺で鳴らし、歌詞を追いかけられます (Spotify Premium が要ります)。"),
                ImasPoint(Icons.AutoMirrored.Filled.OpenInNew, "曲の画面のメニューから、その曲を Spotify で開けます。"),
            ),
            modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
        )
    }
    ImasListSection(footer = "Spotify 側の許可も外すときは、Spotify のアカウント設定の「アプリ」から外します。") {
        ImasActionRow(
            title = "連携を解除",
            onClick = { confirmSignOut = true },
            icon = Icons.AutoMirrored.Filled.Logout,
            kind = ImasActionRowKind.DESTRUCTIVE,
        )
    }
    ImasChoiceDialog(
        title = "Spotify との連携を解除しますか？",
        isPresented = confirmSignOut,
        options = listOf("keep" to "解除する", "forget" to "Client ID も消して解除する"),
        onPick = { if (it == "keep") service.signOut() else service.forgetClientId() },
        onDismiss = { confirmSignOut = false },
        dismissTitle = "やめる",
    )
}

/** フル尺をどちらで鳴らすか。鳴らす許可の無いログイン (プレイリストだけの頃) なら、ログインし直しを促す。iOS と対。 */
@Composable
private fun PlaybackSection() {
    val context = LocalContext.current
    val service = AppModule.from(context).spotifyService
    val playback = AppModule.from(context).lyricsPlayback as? RoutedLyricsPlayback
    val state by service.state.collectAsState()
    if (state.canControlPlayback) {
        val options = remember { fullPlaybackOptions() }
        ImasListSection(
            "フル再生",
            footer = "Spotify で鳴らすときは、音は Spotify アプリから出ます。鳴らす前に一度 Spotify アプリを開いておいてください。",
        ) {
            ImasMenuRow(
                title = "フル尺で鳴らす",
                options = options.map { it.service },
                selection = playback?.currentService() ?: state.fullPlaybackPreference ?: FullPlaybackService.SPOTIFY,
                onSelect = service::setFullPlaybackPreference,
                label = { s -> options.first { it.service == s }.label },
                icon = Icons.Filled.PlayArrow,
            )
        }
    } else {
        ImasListSection("フル再生") {
            ImasNotice(
                kind = ImasNoticeKind.INFO,
                title = "Spotify で鳴らすには、もう一度ログインが要ります",
                message = "曲を鳴らす許可を足すためです。Client ID はそのまま使います。",
                modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
            )
            state.clientId?.let { clientId ->
                ImasActionRow(
                    title = "もう一度ログイン",
                    onClick = { service.startSignIn(context, clientId) },
                    icon = Icons.AutoMirrored.Filled.Login,
                    isLoading = state.isSigningIn,
                )
            }
        }
    }
}

@Composable
private fun SetupSections(onOpenHowTo: (() -> Unit)?) {
    val context = LocalContext.current
    val service = AppModule.from(context).spotifyService
    val state by service.state.collectAsState()
    val guide = remember { spotifySetupGuide(SpotifyGuidePlatform.ANDROID) }
    var clientIdInput by remember { mutableStateOf(state.clientId ?: "") }
    val check = spotifyCheckClientId(clientIdInput)

    ImasListSection {
        ImasText(guide.lead, role = ImasTextRole.BODY, modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap))
    }
    ImasListSection("Spotify のアプリを作る") {
        ImasStepList(
            steps = guide.steps.mapIndexed { index, step ->
                when (index) {
                    0 -> ImasStep(step.title, step.detail) {
                        ImasButton(
                            title = "開発者サイトを開く",
                            onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(guide.dashboardUrl))) },
                            icon = Icons.Filled.Language,
                            role = ImasButtonRole.SECONDARY,
                            size = ImasButtonSize.SMALL,
                        )
                    }
                    else -> if (step.values.isEmpty()) {
                        ImasStep(step.title, step.detail)
                    } else {
                        ImasStep(step.title, step.detail) {
                            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                                step.values.forEach { ImasCopyField(it.label, it.value) }
                            }
                        }
                    }
                }
            },
            modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapLoose),
        )
        if (onOpenHowTo != null) {
            ImasNavRow(
                title = "図つきの手順を見る",
                subtitle = "Spotify の画面のどこを押すかを絵で案内します",
                icon = Icons.Filled.Image,
                onClick = onOpenHowTo,
            )
        }
    }
    ImasListSection("Client ID", footer = guide.notes.joinToString("\n")) {
        ImasTextFieldRow(
            title = "Client ID",
            text = clientIdInput,
            onTextChange = { clientIdInput = it },
            prompt = "32 文字の英数字",
            error = check.problem,
        )
        ImasButton(
            title = "Spotify にログイン",
            onClick = { check.normalized?.let { service.startSignIn(context, it) } },
            modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
            icon = Icons.AutoMirrored.Filled.Login,
            size = ImasButtonSize.LARGE,
            isLoading = state.isSigningIn,
            enabled = check.normalized != null,
        )
    }
    ImasListSection("うまくいかないとき") {
        Column(
            Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
            verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
        ) {
            guide.troubleshooting.forEach { ImasNote(it) }
        }
    }
}

/** 長い値は頭と尾だけ見せる (どのアプリの ID かが分かれば足りる)。 */
private fun masked(id: String): String = if (id.length <= 8) id else "${id.take(4)}…${id.takeLast(4)}"
