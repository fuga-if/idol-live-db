package com.fugaif.imaslivedb.ui.chatgpt

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRowKind
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceDialog
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasMenuRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasPoint
import com.fugaif.imaslivedb.ui.designsystem.ImasPointList
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.launch
import uniffi.imas_core.ChatGptSignInIntent
import uniffi.imas_core.naturalSearchExamples
import uniffi.imas_core.naturalSearchPickModel

private const val USAGE_URL = "https://chatgpt.com/#settings"

/** 設定の「ChatGPT」の行。状態を出して、案内の画面へ進む。iOS `ChatGPTSettingsRow`。 */
@Composable
fun ChatGptSettingsRow(onOpen: () -> Unit) {
    val state by AppModule.from(LocalContext.current).chatGptPlanService.state.collectAsState()
    ImasNavRow(
        title = if (state.isSignedIn) state.registration?.email ?: "ChatGPT" else "ChatGPT とつなぐ",
        subtitle = if (state.isSignedIn) "文で探せます" else "文で探せるようになります",
        icon = Icons.Filled.Search,
        value = if (state.isSignedIn) "連携中" else null,
        showsChevron = false,
        onClick = onOpen,
    )
}

/**
 * ChatGPT 連携の案内と状態。iOS `ChatGPTSettingsView`。
 *
 * 推論は利用者の ChatGPT プランで回る (このアプリからの請求は無い)。使えるのは ChatGPT Plus / Pro のアカウントだけで、
 * プラン外は推論時に ChatGPT 側で弾かれる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatGptSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val service = remember { AppModule.from(context).chatGptPlanService }
    val state by service.state.collectAsState()
    var searchQuery by remember { mutableStateOf<String?>(null) }
    var assistantOpen by remember { mutableStateOf(false) }

    LaunchedEffect(state.tokens?.accessToken) { runCatching { service.loadModelsIfNeeded() } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("ChatGPT") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                }
            )
        }
    ) { padding ->
        ImasFormBackdrop(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                if (state.isSignedIn) ConnectedSections(onExample = { searchQuery = it }, onOpenAssistant = { assistantOpen = true }) else SetupSections()
            }
        }
    }
    ImasErrorAlert(message = state.signInError, onDismiss = service::clearSignInError, title = "ChatGPT とつなげませんでした")
    searchQuery?.let { query ->
        NaturalSearchSheet(
            initialQuery = query,
            onDismiss = { searchQuery = null },
            // 設定の画面 (全画面) が本体の上にあるので、先に畳んでから詳細を開く。
            onOpen = { kind, id -> onBack(); NaturalSearchOpen.request(kind, id) },
        )
    }
    if (assistantOpen) {
        AssistantSheet(
            initialOrder = "",
            onDismiss = { assistantOpen = false },
            onOpen = { kind, id -> onBack(); NaturalSearchOpen.request(kind, id) },
        )
    }
}

@Composable
private fun ConnectedSections(onExample: (String) -> Unit, onOpenAssistant: () -> Unit) {
    val context = LocalContext.current
    val service = remember { AppModule.from(context).chatGptPlanService }
    val state by service.state.collectAsState()
    val scope = rememberCoroutineScope()
    var signOutNote by remember { mutableStateOf<String?>(null) }
    var confirmSignOut by remember { mutableStateOf(false) }
    var savedModel by remember { mutableStateOf(service.savedModel) }

    ImasListSection("ChatGPT", footer = signOutNote) {
        ImasRow(
            title = state.registration?.email ?: "ChatGPT アカウント",
            subtitle = if (state.canUsePlan) "連携中" else "プランの利用が許可されていません",
            leading = ImasRowLeading.Icon(
                if (state.canUsePlan) Icons.Filled.Verified else Icons.Filled.Warning,
                tone = ImasIconTileTone.SOLID,
            ),
            titleRole = ImasTextRole.ROW_LABEL,
        )
        if (!state.canUsePlan) {
            ImasActionRow(
                title = "ChatGPT プランの利用を許可する",
                onClick = { service.startSignIn(context, ChatGptSignInIntent.ENABLE_PLAN) },
                icon = Icons.Filled.Verified,
                isLoading = state.isSigningIn,
            )
            if (state.isSigningIn) {
                ImasActionRow(title = "ログインをやめる", onClick = service::cancelSignIn, icon = Icons.Filled.Close)
            }
        } else if (state.models.size > 1) {
            val slugs = state.models.map { it.slug }
            ImasMenuRow(
                title = "モデル",
                options = slugs,
                selection = naturalSearchPickModel(slugs, savedModel) ?: "",
                onSelect = { service.savedModel = it; savedModel = it },
                label = { slug -> state.models.firstOrNull { it.slug == slug }?.label ?: slug },
                icon = Icons.Filled.Memory,
            )
        }
    }
    if (state.canUsePlan) {
        ImasListSection(
            "文で探す",
            footer = "曲・アイドル・ライブの一覧の検索欄に文を打つと、「文で探す」が出ます。出てくるのはデータベースにあるものだけです。ライブのセトリ画面の「その他」メニューにある「予習 DJ」では、注文を聞いて曲を並べ、1 曲ごとの語りを付けます。",
        ) {
            remember { naturalSearchExamples() }.forEach { example ->
                ImasNavRow(title = example, icon = Icons.Filled.Search, iconTone = ImasIconTileTone.NEUTRAL, onClick = { onExample(example) })
            }
        }
    }
    if (state.canUsePlan) {
        ImasListSection(
            "チャット",
            footer = "データベースを引いて質問に答えます。参加の記録・お気に入り・プレイリスト・収支など、アプリの中で自分でできる操作も頼めます。頼んだ操作は一覧で確かめてから実行します。歌詞やコールのように人が書くものは、その画面を開くところまでです。",
        ) {
            ImasNavRow(
                title = "チャットを開く",
                icon = Icons.Outlined.ChatBubbleOutline,
                iconTone = ImasIconTileTone.NEUTRAL,
                onClick = onOpenAssistant,
            )
        }
    }
    ImasListSection(footer = "探すたび・話すたびに ChatGPT のプランの利用量を使います。このアプリからの請求はありません。") {
        ImasNavRow(
            title = "ChatGPT の設定を開く",
            icon = Icons.AutoMirrored.Filled.OpenInNew,
            showsChevron = false,
            onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(USAGE_URL))) },
        )
        ImasActionRow(
            title = "連携を解除",
            onClick = { confirmSignOut = true },
            icon = Icons.AutoMirrored.Filled.Logout,
            kind = ImasActionRowKind.DESTRUCTIVE,
        )
    }
    ImasChoiceDialog(
        title = "ChatGPT との連携を解除しますか？",
        isPresented = confirmSignOut,
        options = listOf("signout" to "解除する"),
        onPick = {
            scope.launch {
                val revoked = service.signOut()
                signOutNote = if (revoked) null else "ChatGPT 側の解除は確認できませんでした。ChatGPT の設定から連携を外せます。"
            }
        },
        onDismiss = { confirmSignOut = false },
        dismissTitle = "やめる",
    )
}

@Composable
private fun SetupSections() {
    val context = LocalContext.current
    val service = remember { AppModule.from(context).chatGptPlanService }
    val state by service.state.collectAsState()
    ImasListSection {
        ImasText(
            "ChatGPT とつなぐと、「去年の合同ライブに出たシャニマスのアイドル」のような文で探せるようになります。",
            role = ImasTextRole.BODY,
            modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
        )
    }
    ImasListSection("つなぐ", footer = "ブラウザで ChatGPT にログインして許可すると、自動でアプリに戻ります。") {
        ImasPointList(
            points = listOf(
                ImasPoint(Icons.Filled.GraphicEq, "ライブ前の「予習 DJ」で、注文どおりに曲を並べて語りを付けてもらえます。"),
                ImasPoint(Icons.Filled.AccountCircle, "ChatGPT Plus か Pro のアカウントが要ります。"),
                ImasPoint(Icons.Filled.Paid, "料金は ChatGPT のプランに含まれます。このアプリからの請求はありません。"),
                ImasPoint(Icons.Filled.Lock, "ログインの情報はこの端末の中にだけ保存します。"),
            ),
            modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
        )
        ImasButton(
            title = "ChatGPT でログイン",
            onClick = { service.startSignIn(context, ChatGptSignInIntent.SIGN_IN) },
            modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
            icon = Icons.AutoMirrored.Filled.Login,
            size = ImasButtonSize.LARGE,
            isLoading = state.isSigningIn,
        )
        if (state.isSigningIn) {
            ImasActionRow(title = "ログインをやめる", onClick = service::cancelSignIn, icon = Icons.Filled.Close)
        } else if (state.registration != null) {
            ImasActionRow(
                title = "別のアカウントでログイン",
                onClick = { service.startSignIn(context, ChatGptSignInIntent.NEW_ACCOUNT) },
                icon = Icons.Filled.Group,
            )
        }
    }
}
