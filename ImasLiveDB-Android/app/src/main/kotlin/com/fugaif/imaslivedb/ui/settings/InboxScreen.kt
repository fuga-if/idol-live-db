package com.fugaif.imaslivedb.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTile
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasProse
import com.fugaif.imaslivedb.ui.designsystem.ImasProseBlock
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatch
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatchSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress

/**
 * お知らせ受信箱。iOS `Views/Settings/InboxView.swift` の移植。
 *
 * 一覧で未読に印を付け、開いたら既読にする。「すべて既読」も置く。
 * 中身は [AnnouncementCatalog] のアプリ内蔵定数で、通信は一切しない。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InboxScreen(onBack: () -> Unit, onOpenWidgetHowTo: (() -> Unit)? = null) {
    val context = LocalContext.current
    val store = remember { AnnouncementStore(context) }
    // 既読は SharedPreferences 側が正。書いたあとに読み直させるための世代カウンタ
    // (StateFlow を持たせるほどの頻度ではないので、画面ローカルで済ませる)。
    var generation by remember { mutableIntStateOf(0) }
    var opened by remember { mutableStateOf<Announcement?>(null) }

    val readIds = remember(generation) { AnnouncementCatalog.all.filter { store.isRead(it.id) }.map { it.id }.toSet() }
    val unreadCount = AnnouncementCatalog.all.size - readIds.size

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("お知らせ") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    TextButton(onClick = { store.markAllRead(); generation++ }, enabled = unreadCount > 0) {
                        Text("すべて既読")
                    }
                }
            )
        }
    ) { padding ->
        ImasFormBackdrop(modifier = Modifier.fillMaxSize().padding(padding)) {
            if (AnnouncementCatalog.all.isEmpty()) {
                ImasEmptyState(icon = Icons.Outlined.NotificationsOff, title = "お知らせはありません")
            } else {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    ImasListSection {
                        AnnouncementCatalog.all.forEach { item ->
                            AnnouncementRow(item, unread = item.id !in readIds) {
                                store.markRead(item.id)
                                generation++
                                opened = item
                            }
                        }
                    }
                }
            }
        }
    }

    opened?.let { item ->
        AnnouncementDetail(
            item = item,
            onBack = { opened = null },
            onOpenWidgetHowTo = onOpenWidgetHowTo
        )
    }
}

@Composable
private fun AnnouncementRow(item: Announcement, unread: Boolean, onClick: () -> Unit) {
    ImasRow(
        title = item.title,
        subtitle = item.summary,
        leading = ImasRowLeading.Icon(item.icon, tone = ImasIconTileTone.THEMED, seed = item.tint),
        trailing = if (unread) {
            ImasRowTrailing.Custom { ImasSwatch(hex = item.tint, size = ImasSwatchSize.DOT, isDecorative = true) }
        } else {
            ImasRowTrailing.None
        },
        subtitleLineLimit = Int.MAX_VALUE,
        titleRole = ImasTextRole.ROW_TITLE,
        modifier = Modifier.imasRowPress(onClick = onClick)
    ) {
        Text(item.date, style = ImasTextRole.META.style, color = ImasTextRole.META.color)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AnnouncementDetail(
    item: Announcement,
    onBack: () -> Unit,
    onOpenWidgetHowTo: (() -> Unit)?
) {
    androidx.compose.ui.window.Dialog(
        onDismissRequest = onBack,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(item.title) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                        }
                    }
                )
            }
        ) { padding ->
            ImasPage(modifier = Modifier.padding(padding)) {
                ImasIconTile(item.icon, size = ImasIconTileSize.S56, tone = ImasIconTileTone.THEMED, seed = item.tint)
                Column {
                    Text(item.title, style = ImasTextRole.SECTION_TITLE.style, color = ImasTextRole.SECTION_TITLE.color)
                    Text(item.date, style = ImasTextRole.META.style, color = ImasTextRole.META.color)
                }
                ImasProse(blocks = item.body.map { ImasProseBlock.Paragraph(it) })
                if (item.link == AnnouncementLink.WIDGET_HOW_TO && onOpenWidgetHowTo != null) {
                    ImasButton(
                        title = "ウィジェットの使い方を見る",
                        onClick = onOpenWidgetHowTo,
                        icon = Icons.AutoMirrored.Filled.ArrowForward,
                        role = ImasButtonRole.PRIMARY,
                        size = ImasButtonSize.LARGE
                    )
                }
            }
        }
    }
}
