package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectionMark
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipe
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeAction
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeKind
import com.fugaif.imaslivedb.ui.designsystem.imasListSectionItems
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import uniffi.imas_core.CardOshiEntry
import uniffi.imas_core.producerCardOshiNormalize
import uniffi.imas_core.producerCardOshiPicks
import uniffi.imas_core.producerCardOshiToggle

/**
 * アプリの担当から、名刺に載せる担当を選ぶ画面。iOS `CardOshiPickerView` の移植。保存先は呼び出し側に任せる
 * ([onChange] に idol id の並びを渡す。null はおまかせに戻した)。
 *
 * 上は名刺に載せる担当 (選んだ順。矢印で並べ替え、左に引くと外す)、下はアプリの担当すべて (押すと載せる / 外す)。
 * 1 人だけ選べば名刺の担当はその 1 人になる (「担当を大きく」は 1 人の大きな画像、他のデザインは判子 1 つ)。
 * 上限・まだ選んでいないときの既定 (ブランドごとに 1 人)・担当から外れた人を抜く・最後の 1 人を外さないのはコア
 * (`producerCardOshiPicks` / `producerCardOshiToggle` / `producerCardOshiNormalize`)。
 *
 * @param chosen 今の選択 (null はまだ選んでいない)。
 * @param oshi 担当の名前とブランド (アプリの並び)。
 * @param idols 担当のアイドル (行に写真か判子を出す)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardOshiPickerScreen(
    chosen: List<String>?,
    oshi: List<CardOshiEntry>,
    idols: Map<String, Idol>,
    onChange: (List<String>?) -> Unit,
    onBack: () -> Unit
) {
    val haptics = rememberImasHaptics()
    var current by remember { mutableStateOf(chosen) }

    fun set(ids: List<String>) {
        if (ids == current) return
        current = ids
        onChange(ids)
    }

    fun toggle(id: String) {
        haptics.selection()
        set(producerCardOshiToggle(current, oshi, id))
    }

    fun reset() {
        haptics.selection()
        current = null
        onChange(null)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("名刺に載せる担当") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                }
            )
        }
    ) { padding ->
        if (oshi.isEmpty()) {
            ImasPage(modifier = Modifier.padding(padding)) {
                ImasCard {
                    ImasEmptyState(
                        icon = Icons.Filled.FavoriteBorder,
                        title = "担当がいません",
                        message = "アイドル詳細で「担当」を付けると、ここから名刺に載せる担当を選べます。"
                    )
                }
            }
            return@Scaffold
        }
        ImasFormBackdrop(Modifier.fillMaxSize().padding(padding)) {
            val picks = producerCardOshiPicks(current, oshi)
            val pickedIds = picks.picked.map { it.idolId }.toSet()
            LazyColumn(Modifier.fillMaxSize()) {
                // 名刺に載せる担当。行は人で見分ける (外したとき、隣の行が引いた量を引き継がないように)。
                // 名刺に載せる担当 (選んでいれば末尾に「おまかせに戻す」の行。null がその行)。
                // 行は人で見分ける (外したとき、隣の行が引いた量を引き継がないように)。
                val pickedRows: List<CardOshiEntry?> = picks.picked + if (picks.chosenByHand) listOf(null) else emptyList()
                imasListSectionItems(
                    sectionKey = "picked",
                    items = pickedRows,
                    key = { it?.idolId ?: "#reset" },
                    title = "名刺に載せる担当",
                    count = "${picks.picked.size} / ${picks.max}",
                    footer = if (picks.chosenByHand) "載せる順に並びます。矢印で並べ替え、左に引くと外します (1 人は残します)。"
                    else "まだ選んでいないので、ブランドごとに 1 人ずつ載せています。選ぶとその人だけ・その順になります。"
                ) { entry ->
                    if (entry == null) {
                        ImasNavRow(title = "おまかせに戻す", icon = Icons.AutoMirrored.Filled.Undo, showsChevron = false) { reset() }
                        return@imasListSectionItems
                    }
                    val index = picks.picked.indexOfFirst { it.idolId == entry.idolId }
                    val idol = idols[entry.idolId] ?: return@imasListSectionItems
                    val trailing = if (picks.single) emptyList()
                    else listOf(ImasSwipeAction(ImasSwipeKind.DELETE, "外す") { toggle(entry.idolId) })
                    ImasSwipe(background = DS.surface, trailing = trailing) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            ImasIdolRow(
                                idol = idol, subtitle = entry.brandLabel.ifEmpty { null }, isPick = true,
                                density = ImasRowDensity.COMPACT, modifier = Modifier.weight(1f)
                            )
                            fun move(to: Int) {
                                val ids = picks.picked.map { it.idolId }.toMutableList()
                                ids.add(to, ids.removeAt(index))
                                haptics.selection()
                                set(producerCardOshiNormalize(ids, oshi))
                            }
                            IconButton(onClick = { move(index - 1) }, enabled = index > 0) {
                                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "${idol.name}を上へ")
                            }
                            IconButton(onClick = { move(index + 1) }, enabled = index < picks.picked.size - 1) {
                                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "${idol.name}を下へ")
                            }
                        }
                    }
                }
                imasListSectionItems(
                    sectionKey = "oshi",
                    items = picks.oshi,
                    key = { it.idolId },
                    title = "アプリの担当",
                    count = "${picks.oshi.size}人",
                    footer = if (picks.full) "名刺に載せられるのは ${picks.max} 人までです。足すときは先にどれかを外してください。" else null
                ) { entry ->
                    val idol = idols[entry.idolId] ?: return@imasListSectionItems
                    val isPicked = entry.idolId in pickedIds
                    val locked = (picks.full && !isPicked) || (picks.single && isPicked)
                    ImasIdolRow(
                        idol = idol, subtitle = entry.brandLabel.ifEmpty { null }, isPick = true,
                        density = ImasRowDensity.COMPACT,
                        trailing = ImasRowTrailing.Custom { ImasSelectionMark(isSelected = isPicked) },
                        modifier = Modifier
                            .alpha(if (locked && !isPicked) 0.45f else 1f)
                            .imasRowPress(enabled = !locked, role = Role.Checkbox, onClick = { toggle(entry.idolId) })
                            .semantics { selected = isPicked }
                    )
                }
            }
        }
    }
}
