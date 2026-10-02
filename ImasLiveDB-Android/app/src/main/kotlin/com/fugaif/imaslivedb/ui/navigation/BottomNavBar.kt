package com.fugaif.imaslivedb.ui.navigation

import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Poll
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material.icons.filled.Whatshot
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.PermanentDrawerSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.designsystem.ImasFitText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.AppDestination
import uniffi.imas_core.NavItem
import uniffi.imas_core.NavSection

/**
 * 行き先のアイコン。並び・見出し・文言はコア (`appNavigationSections`) が持ち、
 * Material のアイコンだけ OS 側で引く (iOS は SF Symbols の別物になるため)。
 */
val AppDestination.icon: ImageVector
    get() = when (this) {
        AppDestination.SCHEDULE -> Icons.Filled.CalendarMonth
        AppDestination.EVENTS -> Icons.Filled.Mic
        AppDestination.SONGS -> Icons.Filled.LibraryMusic
        AppDestination.IDOLS -> Icons.Filled.Groups
        AppDestination.PRODUCE -> Icons.Filled.Star
        AppDestination.STATS -> Icons.Filled.BarChart
        AppDestination.TIMELINE -> Icons.Filled.Timeline
        AppDestination.POLLS -> Icons.Filled.Poll
        AppDestination.CALL_GUIDE -> Icons.Filled.Campaign
        AppDestination.COMMUNITY_ACTIVITY -> Icons.Filled.People
        AppDestination.TAG_ACTIVITY -> Icons.Filled.Whatshot
        AppDestination.GAMES -> Icons.Filled.SportsEsports
        AppDestination.ASSISTANT -> Icons.Filled.AutoAwesome
    }

/**
 * 狭い画面の下のタブバー。載せるのはコアが `inTabBar` とした行き先だけ。
 * アプリの枠は墨 (iOS は `UITabBar.appearance().tintColor = .label` と同じ無彩の方針。
 * 色はブランド・実体側だけが持つので、タブの選択状態に色は差さない)。
 */
@Composable
fun BottomNavBar(
    items: List<NavItem>,
    current: AppDestination,
    onSelect: (AppDestination) -> Unit
) {
    NavigationBar(containerColor = DS.surface) {
        items.forEach { item ->
            NavigationBarItem(
                selected = current == item.destination,
                onClick = { onSelect(item.destination) },
                icon = { Icon(imageVector = item.destination.icon, contentDescription = item.label) },
                // 1 行に収める (「スケジュール」「プロデュース」が 2 行に割れないように)。
                // 幅が足りない端末・大きい文字では縮めて収める。
                label = {
                    ImasFitText(
                        item.label,
                        style = ImasTextRole.META.style,
                        color = LocalContentColor.current,
                        minScale = 0.75f
                    )
                },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = DS.ink,
                    selectedTextColor = DS.ink,
                    indicatorColor = DS.fill,
                    unselectedIconColor = DS.ink3,
                    unselectedTextColor = DS.ink3
                )
            )
        }
    }
}

/**
 * 広い画面 (タブレット) の左のサイドバー。iOS の `TabView(.sidebarAdaptable)` と同じ並び。
 * サイドバーだけの行き先の中身は、狭い画面でプロデュースの入口から開く画面と同じ。
 */
@Composable
fun AppSidebar(
    sections: List<NavSection>,
    current: AppDestination,
    onSelect: (AppDestination) -> Unit
) {
    PermanentDrawerSheet(modifier = Modifier.width(240.dp), drawerContainerColor = DS.surface) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Space.screen, vertical = DS.Space.card)
        ) {
            sections.forEach { section ->
                section.title?.let { title ->
                    Spacer(Modifier.height(DS.Space.gapLoose))
                    Text(
                        text = title,
                        style = ImasTextRole.SECTION_LABEL.style,
                        color = ImasTextRole.SECTION_LABEL.color,
                        modifier = Modifier.padding(start = DS.Space.rowH, bottom = DS.Space.gapTight)
                    )
                }
                section.items.forEach { item ->
                    NavigationDrawerItem(
                        label = { Text(item.label) },
                        icon = { Icon(item.destination.icon, contentDescription = null) },
                        selected = current == item.destination,
                        onClick = { onSelect(item.destination) },
                        colors = NavigationDrawerItemDefaults.colors(
                            selectedContainerColor = DS.fill,
                            selectedIconColor = DS.ink,
                            selectedTextColor = DS.ink,
                            unselectedIconColor = DS.ink2,
                            unselectedTextColor = DS.ink2
                        )
                    )
                }
            }
        }
    }
}

/**
 * 下のタブバーを隠している画面の数 (iOS の `.toolbar(.hidden, for: .tabBar)` 相当)。
 * クイズのステージ画面のように全画面で見せたい画面が、表示中だけ [hide] で数を上げる。
 * 数で持つのは、画面の出入りのアニメーション中に 2 画面が同時に居ても取り違えないため。
 */
object BottomBarVisibility {
    var hiddenBy by mutableIntStateOf(0)
        private set

    val isHidden: Boolean get() = hiddenBy > 0

    /** 表示中だけタブバーを隠す。 */
    @Composable
    fun Hide() {
        DisposableEffect(Unit) {
            hiddenBy += 1
            onDispose { hiddenBy -= 1 }
        }
    }
}
