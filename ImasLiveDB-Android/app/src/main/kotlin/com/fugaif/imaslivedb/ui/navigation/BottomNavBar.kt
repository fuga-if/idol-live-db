package com.fugaif.imaslivedb.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector

private data class BottomNavItem(
    val tab: TopLevelTab,
    val label: String,
    val icon: ImageVector
)

private val navItems = listOf(
    BottomNavItem(TopLevelTab.Schedule, "スケジュール", Icons.Filled.CalendarMonth),
    BottomNavItem(TopLevelTab.Events, "ライブ", Icons.Filled.Mic),
    BottomNavItem(TopLevelTab.Songs, "楽曲", Icons.Filled.LibraryMusic),
    BottomNavItem(TopLevelTab.Idols, "アイドル", Icons.Filled.Groups),
    BottomNavItem(TopLevelTab.Produce, "プロデュース", Icons.Filled.Star)
)

@Composable
fun BottomNavBar(
    currentTab: TopLevelTab,
    onTabSelected: (TopLevelTab) -> Unit
) {
    NavigationBar {
        navItems.forEach { item ->
            NavigationBarItem(
                selected = currentTab == item.tab,
                onClick = { onTabSelected(item.tab) },
                icon = { Icon(imageVector = item.icon, contentDescription = item.label) },
                label = { Text(text = item.label) }
            )
        }
    }
}
