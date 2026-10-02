package com.fugaif.imaslivedb.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.navigation.icon
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.AppDestination
import uniffi.imas_core.maxTabBarCount
import uniffi.imas_core.normalizeTabBarKeys
import uniffi.imas_core.tabBarChoices

/**
 * 設定の「タブバー」(iOS `TabBarSettingsView`)。載せる画面を選び、↑↓ で並べ替える。
 * 整え方 (プロデュースは必ず載る・上限・出せない行き先を落とす) はコア。
 */
@Composable
fun TabBarSettingsSection() {
    val choices = remember { tabBarChoices(lyricsAvailable = false, assistantAvailable = false) }
    val max = remember { maxTabBarCount().toInt() }
    val tabs = normalizeTabBarKeys(lyricsAvailable = false, assistantAvailable = false, tabKeys = AppPreferences.tabBarKeys)
    fun save(keys: List<String>) =
        AppPreferences.setTabBarKeys(normalizeTabBarKeys(lyricsAvailable = false, assistantAvailable = false, tabKeys = keys))
    fun item(key: String) = choices.firstOrNull { it.analyticsKey == key }

    Column {
        ImasListSection(
            "タブバー",
            count = "${tabs.size} / $max",
            footer = "プロデュースは外せません (設定と、タブから外した画面の入口があるため)。外した画面はプロデュースの「そのほか」から開けます。"
        ) {
            tabs.forEachIndexed { index, key ->
                val nav = item(key) ?: return@forEachIndexed
                ImasRow(
                    title = nav.label,
                    leading = ImasRowLeading.Icon(nav.destination.icon, tone = ImasIconTileTone.NEUTRAL),
                    density = ImasRowDensity.COMPACT,
                    trailing = ImasRowTrailing.Custom {
                        Row {
                            IconButton(onClick = { save(tabs.toMutableList().apply { add(index - 1, removeAt(index)) }) }, enabled = index > 0) {
                                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "${nav.label}を左へ", tint = DS.ink2)
                            }
                            IconButton(onClick = { save(tabs.toMutableList().apply { add(index + 1, removeAt(index)) }) }, enabled = index < tabs.lastIndex) {
                                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "${nav.label}を右へ", tint = DS.ink2)
                            }
                            if (nav.destination != AppDestination.PRODUCE) {
                                IconButton(onClick = { save(tabs - key) }) {
                                    Icon(Icons.Filled.Remove, contentDescription = "${nav.label}をタブバーから外す", tint = DS.danger)
                                }
                            }
                        }
                    }
                )
            }
        }

        val rest = choices.filter { it.analyticsKey !in tabs }
        if (rest.isNotEmpty()) {
            val full = tabs.size >= max
            ImasListSection(
                "追加できる画面",
                footer = if (full) "タブバーは $max つまでです。追加するには先にどれかを外してください。" else null
            ) {
                rest.forEach { nav ->
                    ImasRow(
                        title = nav.label,
                        modifier = Modifier.alpha(if (full) 0.45f else 1f),
                        leading = ImasRowLeading.Icon(nav.destination.icon, tone = ImasIconTileTone.NEUTRAL),
                        density = ImasRowDensity.COMPACT,
                        trailing = ImasRowTrailing.Custom {
                            IconButton(onClick = { save(tabs + nav.analyticsKey) }, enabled = !full) {
                                Icon(Icons.Filled.Add, contentDescription = "${nav.label}をタブバーに追加", tint = DS.ink2)
                            }
                        }
                    )
                }
            }
        }

        ImasListSection {
            ImasActionRow(title = "最初の並びに戻す", onClick = { AppPreferences.setTabBarKeys(emptyList()) }, icon = Icons.Filled.Restore)
        }
    }
}
