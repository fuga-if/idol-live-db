package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.ManageAccounts
import androidx.compose.material.icons.outlined.ReportProblem
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress
import kotlinx.coroutines.launch

// =============================================================================
// 状態とお知らせ (docs/DESIGN_SYSTEM.md §11)。iOS `ImasFeedback.swift` の移植。
//
// ImasStateContainer     読み込み・空・失敗・中身を出し分ける。画面で `if (isLoading)` を書かない。
// ImasLoadingState       画面全体の読み込み。
// ImasInlineLoading      区画だけの読み込み。
// ImasEmptyState         何もない・見つからない・読めなかった・ログインが要る。
// ImasNotice             読まないと困ること (始められない・失敗した・オフライン)。囲む。
// ImasSignInPrompt       区画の中の「ログインが必要です」。
// ImasSavingOverlay      保存・送信中 (iOS `.imasSavingOverlay`)。
// ImasErrorAlert         操作の失敗 (iOS `.imasErrorAlert`)。
// ImasConfirmDestructive 消す前の確認 (iOS `.imasConfirmDestructive`)。
// =============================================================================

// MARK: - 読み込み

/**
 * 画面・シート全体の読み込み中 (iOS `ImasLoadingState`)。空いている領域いっぱいに出して中央に置く。
 *
 * @param title くるくるの下に出す文字 (「読み込み中…」)。null なら記号だけ (既定)。
 */
@Composable
fun ImasLoadingState(modifier: Modifier = Modifier, title: String? = null) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            CircularProgressIndicator(color = DS.ink3)
            if (title != null) Text(title, style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
        }
    }
}

/**
 * 区画や一覧の途中の読み込み中 (iOS `ImasInlineLoading`)。行 1 つ分の高さで横中央に置く。
 *
 * @param tint 暗い地 (ステージ) に置くときの色。
 */
@Composable
fun ImasInlineLoading(modifier: Modifier = Modifier, tint: Color? = null) {
    Box(
        modifier
            .fillMaxWidth()
            .padding(vertical = DS.Space.section / 2),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator(Modifier.size(20.dp), color = tint ?: DS.ink3, strokeWidth = 2.dp)
    }
}

// MARK: - 空状態

/** 空の理由 (iOS `ImasEmptyState.Kind`)。理由ごとに記号と言い方を揃える。 */
enum class ImasEmptyStateKind(internal val icon: ImageVector) {
    /** まだ何もない。 */
    EMPTY(Icons.Outlined.Inbox),

    /** 絞り込み・検索で 0 件。 */
    NO_RESULTS(Icons.Outlined.Search),

    /** 読み込めなかった。 */
    FAILED(Icons.Outlined.ReportProblem),

    /** ログインが要る。 */
    SIGN_IN_REQUIRED(Icons.Outlined.ManageAccounts)
}

/**
 * 何もない・見つからない・読めなかった・ログインが要る (iOS `ImasEmptyState`)。
 *
 * 記号は細い線の記号を薄い灰で 1 つ (記号を色の四角に入れない)。題は 19 太字、説明は灰、操作は主ボタン (中) 1 つ。
 * この形は Android の今の呼び出し (記号を渡す) のまま。理由から決めるなら [ImasEmptyStateKind] を渡す形。
 *
 * @param seed 旧い引数。空状態はもう色で飾らない (記号は灰)。受けるだけ。
 * @param brand 旧い引数。[seed] と同じ。
 */
@Composable
fun ImasEmptyState(
    icon: ImageVector,
    title: String,
    message: String? = null,
    @Suppress("UNUSED_PARAMETER") seed: String? = null,
    @Suppress("UNUSED_PARAMETER") brand: String? = null,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    Column(
        modifier
            .fillMaxWidth()
            .padding(vertical = 32.dp, horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = DS.ink3,
            modifier = Modifier
                .padding(bottom = DS.Space.gapLoose)
                .size(with(LocalDensity.current) { 38.sp.toDp() })
        )
        Text(
            title,
            style = ImasTextRole.CARD_TITLE.style,
            color = ImasTextRole.CARD_TITLE.color,
            textAlign = TextAlign.Center
        )
        if (message != null) {
            Text(
                message,
                style = ImasTextRole.NOTE.style,
                color = ImasTextRole.NOTE.color,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 6.dp)
            )
        }
        if (actionTitle != null && onAction != null) {
            ImasButton(
                title = actionTitle,
                onClick = onAction,
                role = ImasButtonRole.PRIMARY,
                size = ImasButtonSize.MEDIUM,
                modifier = Modifier.padding(top = DS.Space.card)
            )
        }
    }
}

/** 理由から記号を決める形 (iOS `ImasEmptyState(.empty, title:…)`)。題と説明は画面の言葉で渡す。 */
@Composable
fun ImasEmptyState(
    kind: ImasEmptyStateKind,
    title: String,
    modifier: Modifier = Modifier,
    message: String? = null,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null
) {
    ImasEmptyState(
        icon = kind.icon,
        title = title,
        message = message,
        actionTitle = actionTitle,
        onAction = onAction,
        modifier = modifier
    )
}

// MARK: - 状態の出し分け

/** 画面・区画の中身の状態 (iOS `ImasContentState`)。 */
@Immutable
sealed interface ImasContentState {
    data object Loading : ImasContentState
    data object Loaded : ImasContentState
    data object Empty : ImasContentState
    data class Failed(val message: String? = null) : ImasContentState
}

/** 初回の読み込みのスケルトンの形 (iOS `ImasSkeletonKind`)。 */
@Immutable
sealed interface ImasSkeletonKind {
    data class List(val rows: Int = 10) : ImasSkeletonKind
    data object Grid : ImasSkeletonKind
}

/**
 * 読み込み・空・失敗・中身を出し分ける (iOS `ImasStateContainer`)。空と失敗の見せ方は呼び出し側が渡す。
 *
 * @param skeleton 初回の読み込みにスケルトンを出す (一覧)。null なら くるくる (詳細)。
 * @param onRetry 失敗のときの「もう一度」。null なら出さない。
 */
@Composable
fun ImasStateContainer(
    state: ImasContentState,
    modifier: Modifier = Modifier,
    skeleton: ImasSkeletonKind? = null,
    onRetry: (() -> Unit)? = null,
    empty: @Composable () -> Unit = {},
    content: @Composable () -> Unit
) {
    Box(modifier) {
        when (state) {
            ImasContentState.Loading -> when (skeleton) {
                is ImasSkeletonKind.List -> ImasListSkeleton(rows = skeleton.rows)
                ImasSkeletonKind.Grid -> ImasGridSkeleton()
                null -> ImasLoadingState()
            }
            ImasContentState.Loaded -> content()
            ImasContentState.Empty -> empty()
            is ImasContentState.Failed -> ImasEmptyState(
                ImasEmptyStateKind.FAILED,
                title = "読み込めませんでした",
                message = state.message ?: "通信状況を確かめて、もう一度試してください。",
                actionTitle = if (onRetry == null) null else "もう一度",
                onAction = onRetry
            )
        }
    }
}

// MARK: - お知らせの帯

/** お知らせの種類 (iOS `ImasNotice.Kind`)。意味の色は記号だけに出す。 */
enum class ImasNoticeKind(internal val icon: ImageVector) {
    INFO(Icons.Filled.Info),
    WARNING(Icons.Filled.Warning),
    ERROR(Icons.Filled.Cancel),
    SUCCESS(Icons.Filled.CheckCircle)
}

/**
 * 読まないと困ることを囲んで知らせる帯 (iOS `ImasNotice`)。補足 (読まなくても困らない) は [ImasNote]。
 * 地は面の色。意味の色 (注意 = 橙・失敗 = 朱・完了 = 緑) は記号だけに出す (色の地も、縁の色の帯も敷かない)。
 *
 * @param message 本文。見出しだけで足りる注意 (件数だけ伝えれば済む警告など) は null。
 * @param icon 記号の上書き。省くと種類ごとの既定。
 */
@Composable
fun ImasNotice(
    kind: ImasNoticeKind,
    message: String?,
    modifier: Modifier = Modifier,
    title: String? = null,
    icon: ImageVector? = null,
    actionTitle: String? = null,
    actionIcon: ImageVector? = null,
    onAction: (() -> Unit)? = null
) {
    val tint = when (kind) {
        ImasNoticeKind.INFO -> DS.ink2
        ImasNoticeKind.WARNING -> DS.warning
        ImasNoticeKind.ERROR -> DS.danger
        ImasNoticeKind.SUCCESS -> DS.successInk
    }
    Row(
        modifier
            .fillMaxWidth()
            .background(DS.surface, RoundedCornerShape(DS.rControl(50.dp)))
            .padding(DS.Space.gapLoose + 2.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
    ) {
        Icon(
            icon ?: kind.icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier
                .padding(top = 1.dp)
                .size(with(LocalDensity.current) { 18.sp.toDp() })
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            if (title != null) {
                Text(title, style = ImasType.text(15.sp, FontWeight.Bold), color = DS.ink)
            }
            if (message != null) Text(message, style = ImasType.text(13.sp), color = DS.ink2)
            if (actionTitle != null && onAction != null) {
                ImasButton(
                    title = actionTitle,
                    onClick = onAction,
                    icon = actionIcon,
                    role = ImasButtonRole.SECONDARY,
                    size = ImasButtonSize.SMALL,
                    modifier = Modifier.padding(top = DS.Space.gapTight)
                )
            }
        }
    }
}

// MARK: - ログインの誘い

/**
 * 区画の中の「〇〇にはログインが必要です」(iOS `ImasSignInPrompt`)。ログインしていれば何も出さない。
 * カード全体が押せる (「ログイン」だけの小さい押し場所にはしない)。押すとログイン
 * (Google の Credential Manager のシート) を始める (`CommunityLoginPromptDialog` と同じ入口)。
 *
 * @param buttonTitle ボタンの文言 (読み上げの動詞もこれに揃える)。呼び出しによって
 *   「Googleでログイン」等、前の画面の文言に合わせたい時に渡す。
 */
@Composable
fun ImasSignInPrompt(
    modifier: Modifier = Modifier,
    message: String = "投稿・投票にはログインが必要です",
    buttonTitle: String = "ログイン"
) {
    val context = LocalContext.current
    val auth = remember(context) { AppModule.from(context).authService }
    val state by auth.state.collectAsState()
    if (state.isSignedIn) return
    val scope = rememberCoroutineScope()
    // signIn はアカウント選択のシートを出すため Activity の context が要る。
    val signIn: () -> Unit = { scope.launch { auth.signIn(context) } }
    Row(
        modifier
            .fillMaxWidth()
            .imasPress(onClickLabel = buttonTitle, onClick = signIn)
            .background(DS.surface, RoundedCornerShape(DS.rCard))
            .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapLoose),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            Icons.Outlined.ManageAccounts,
            contentDescription = null,
            tint = DS.ink2,
            modifier = Modifier.size(with(LocalDensity.current) { 20.sp.toDp() })
        )
        Text(
            message,
            style = ImasType.text(13.sp, FontWeight.SemiBold),
            color = DS.ink2,
            modifier = Modifier.weight(1f)
        )
        // 見た目だけ。押すのはカード全体 (入れ子の押し場所にしない)。
        ImasButton(
            title = buttonTitle,
            onClick = signIn,
            role = ImasButtonRole.PRIMARY,
            size = ImasButtonSize.SMALL,
            modifier = Modifier.clearAndSetSemantics { }
        )
    }
}

// MARK: - 保存中・失敗・確認

/**
 * 保存・送信中に画面を覆う (iOS `.imasSavingOverlay`)。下の操作を止め、何をしているかを 1 語で出す。
 * 画面の Box の最後に置く。[progress] を渡すと (0〜1)、くるくるの代わりに進み具合の線を出す
 * (画像の一括取り込みなど、割合が意味を持つ処理向け)。
 *
 * @param blocksInteraction false で地を暗くせず、箱だけ浮かせる (長く走る一括処理の間も後ろの一覧を
 *   触れたままにしたいとき。既定 (true) は地を暗くして止める)。
 */
@Composable
fun ImasSavingOverlay(
    isSaving: Boolean,
    label: String = "保存中",
    progress: Double? = null,
    blocksInteraction: Boolean = true
) {
    AnimatedVisibility(visible = isSaving, enter = fadeIn(), exit = fadeOut()) {
        Box(
            if (blocksInteraction) {
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.25f))
                    // 下の操作を止める (押しても何もしない)。
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { }
            } else {
                // 地を暗くせず、箱だけ浮かせる (後ろの一覧は触れたまま)。
                Modifier.fillMaxSize()
            },
            contentAlignment = Alignment.Center
        ) {
            Column(
                Modifier
                    .background(DS.surface, RoundedCornerShape(DS.rCard))
                    .padding(horizontal = 32.dp, vertical = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
            ) {
                if (progress != null) {
                    LinearProgressIndicator(
                        progress = { progress.toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.width(160.dp),
                        color = DS.sys,
                        trackColor = DS.fill
                    )
                } else {
                    CircularProgressIndicator(color = DS.ink2)
                }
                Text(label, style = ImasType.text(15.sp, FontWeight.SemiBold), color = DS.ink)
            }
        }
    }
}

/**
 * 操作の失敗を知らせる (iOS `.imasErrorAlert`)。題は「〇〇できませんでした」、本文に理由。
 * [message] が null の間は出ない。閉じると [onDismiss] (呼び出し側が message を null に戻す)。
 */
@Composable
fun ImasErrorAlert(message: String?, onDismiss: () -> Unit, title: String = "保存できませんでした") {
    if (message == null) return
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        containerColor = DS.surface,
        titleContentColor = DS.ink,
        textContentColor = DS.ink2
    )
}

/**
 * 操作の完了を知らせる (iOS の `.alert("〇〇しました", isPresented:)`)。送信・投稿が
 * 完了したときなど。[message] が null の間は出ない。閉じると [onDismiss]。
 */
@Composable
fun ImasCompletionAlert(title: String, message: String?, onDismiss: () -> Unit, confirmLabel: String = "OK") {
    if (message == null) return
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onDismiss) { Text(confirmLabel) } },
        containerColor = DS.surface,
        titleContentColor = DS.ink,
        textContentColor = DS.ink2
    )
}

/**
 * 2 つの入力欄を持つダイアログ (プレイリストの公開: タイトル + ひとこと)。
 * iOS の `.alert("…", isPresented:) { TextField; TextField }` と同じ役目。
 */
@Composable
fun ImasTwoFieldTextInputDialog(
    title: String,
    confirmLabel: String,
    onDismiss: () -> Unit,
    onConfirm: (String, String) -> Unit,
    message: String? = null,
    initialValue1: String = "",
    initialValue2: String = "",
    label1: String = "タイトル",
    label2: String = "ひとこと (なくてもよい)",
    dismissTitle: String = "やめる"
) {
    var text1 by remember(title) { mutableStateOf(initialValue1) }
    var text2 by remember(title) { mutableStateOf(initialValue2) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                if (message != null) {
                    Text(message, color = DS.ink2)
                    Spacer(Modifier.height(12.dp))
                }
                OutlinedTextField(
                    value = text1,
                    onValueChange = { text1 = it },
                    label = { Text(label1) },
                    singleLine = true
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = text2,
                    onValueChange = { text2 = it },
                    label = { Text(label2) },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(text1, text2) }, enabled = text1.isNotBlank()) { Text(confirmLabel) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(dismissTitle, color = DS.ink) } },
        containerColor = DS.surface,
        titleContentColor = DS.ink,
        textContentColor = DS.ink2
    )
}

/**
 * 消す前の確認 (iOS `.imasConfirmDestructive`)。題は「〇〇を削除しますか？」、破壊のボタンは「削除」(朱)。
 * [isPresented] が true の間だけ出る。
 *
 * @param style iOS の出し方の区別 (下からの確認 / 中央のアラート)。Android はどちらも中央のダイアログ
 *   (Android で取り消せない操作を確かめる標準の形)。呼び出しの形を iOS と揃えるために受ける。
 */
@Composable
fun ImasConfirmDestructive(
    title: String,
    isPresented: Boolean,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
    actionTitle: String = "削除",
    message: String? = null,
    dismissTitle: String = "キャンセル",
    @Suppress("UNUSED_PARAMETER") style: ImasConfirmDestructiveStyle = ImasConfirmDestructiveStyle.CONFIRMATION_DIALOG
) {
    if (!isPresented) return
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = message?.let { { Text(it) } },
        confirmButton = {
            TextButton(onClick = {
                onDismiss()
                onConfirm()
            }) { Text(actionTitle, color = DS.danger) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(dismissTitle, color = DS.ink) } },
        containerColor = DS.surface,
        titleContentColor = DS.ink,
        textContentColor = DS.ink2
    )
}

/**
 * 1 行の名前を入れてもらうダイアログ (新規作成・名前の変更。プレイリストの名付け等)。
 * iOS の `.alert("…", isPresented:) { TextField… }` と同じ役目。
 */
@Composable
fun ImasTextInputDialog(
    title: String,
    confirmLabel: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
    initialValue: String = "",
    label: String = "名前",
    dismissTitle: String = "やめる"
) {
    var text by remember(title) { mutableStateOf(initialValue) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            androidx.compose.material3.OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                label = { Text(label) },
                singleLine = true
            )
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(text) }, enabled = text.isNotBlank()) { Text(confirmLabel) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(dismissTitle, color = DS.ink) } },
        containerColor = DS.surface,
        titleContentColor = DS.ink,
        textContentColor = DS.ink2
    )
}

/** 消す前の確認の出し方 (iOS `ImasConfirmDestructiveStyle`)。 */
enum class ImasConfirmDestructiveStyle {
    /** 既定。iOS は下からの確認シート (操作系の一覧の削除など、軽い取り消し)。 */
    CONFIRMATION_DIALOG,

    /** iOS は中央のアラート (アカウント削除など、取り消せない重い操作)。 */
    ALERT
}

/** 行の末尾などに置く小さなくるくる (iOS `ImasInlineSpinner`)。画面のコードで素の進捗の丸を書かない。 */
@Composable
fun ImasInlineSpinner(modifier: Modifier = Modifier) {
    CircularProgressIndicator(modifier = modifier.size(18.dp), color = DS.ink2, strokeWidth = 2.dp)
}
