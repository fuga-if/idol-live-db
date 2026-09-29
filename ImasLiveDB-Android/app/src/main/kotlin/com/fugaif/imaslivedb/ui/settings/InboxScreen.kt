package com.fugaif.imaslivedb.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

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

    Scaffold(
        containerColor = DS.bg,
        topBar = {
            TopAppBar(
                title = { Text("お知らせ", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    TextButton(onClick = { store.markAllRead(); generation++ }) { Text("すべて既読") }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = DS.bg, titleContentColor = DS.ink,
                    navigationIconContentColor = DS.ink, actionIconContentColor = DS.sys
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(AnnouncementCatalog.all, key = { it.id }) { item ->
                AnnouncementRow(item, unread = item.id !in readIds) {
                    store.markRead(item.id)
                    generation++
                    opened = item
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
    val theme = ImasTheme.derive(item.tint)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            item.icon, contentDescription = null, tint = theme.accent,
            modifier = Modifier.size(36.dp).clip(CircleShape).background(theme.bar.copy(alpha = 0.18f)).padding(7.dp)
        )
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (unread) {
                    Box(Modifier.size(7.dp).clip(CircleShape).background(theme.accent))
                }
                Text(item.title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            }
            Text(item.summary, fontSize = 12.sp, color = DS.ink2, modifier = Modifier.padding(top = 2.dp))
            Text(item.date, fontSize = 11.sp, color = DS.ink3, modifier = Modifier.padding(top = 4.dp))
        }
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
            containerColor = DS.bg,
            topBar = {
                TopAppBar(
                    title = { Text(item.title, fontWeight = FontWeight.Bold, fontSize = 17.sp) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = DS.bg, titleContentColor = DS.ink, navigationIconContentColor = DS.ink
                    )
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier.fillMaxSize().padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Text(item.date, fontSize = 12.sp, color = DS.ink3)
                item.body.forEach { paragraph ->
                    Text(paragraph, fontSize = 14.sp, color = DS.ink, lineHeight = 22.sp)
                }
                if (item.link == AnnouncementLink.WIDGET_HOW_TO && onOpenWidgetHowTo != null) {
                    TextButton(onClick = onOpenWidgetHowTo) { Text("ウィジェットの使い方を見る") }
                }
            }
        }
    }
}
