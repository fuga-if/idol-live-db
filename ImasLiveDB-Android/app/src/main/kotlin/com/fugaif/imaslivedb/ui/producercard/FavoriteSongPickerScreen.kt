package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import com.fugaif.imaslivedb.data.producercard.FavoriteSong
import com.fugaif.imaslivedb.data.producercard.FavoriteSongSource
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasSongRow
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectionMark
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipe
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeAction
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import uniffi.imas_core.favoriteSongNormalize
import uniffi.imas_core.favoriteSongPicks
import uniffi.imas_core.favoriteSongToggle

/**
 * お気に入りの曲から、載せる曲を選ぶ画面。iOS `FavoriteSongPickerView` の移植。プロフィール帳の好きな曲に使い、
 * P名刺の編集からも同じ部品で開けるように、保存先は呼び出し側に任せる ([onChange] に曲 id の並びを渡す)。
 *
 * 上は載せる曲 (選んだ順。矢印で並べ替え、左に引くと外す)、下はお気に入りの曲すべて (付けた新しい順。
 * 押すと載せる / 外す)。お気に入りは何百曲にもなるので曲名で絞る (照合はコアの `TextSearchCatalog`)。
 * 上限・まだ選んでいないときの既定・お気に入りから外れた曲を抜くのはコア (`favoriteSongPicks`)。
 *
 * @param chosen 今の選択 (null はまだ選んでいない)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoriteSongPickerScreen(chosen: List<String>?, onChange: (List<String>) -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val haptics = rememberImasHaptics()
    var current by remember { mutableStateOf(chosen) }
    var favorites by remember { mutableStateOf<List<FavoriteSong>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        val loadedFavorites = FavoriteSongSource.load(module)
        // 並びはコア (付けた新しい順)。
        val order = favoriteSongPicks(null, loadedFavorites.map { it.input }).favorites.map { it.id }
        val byId = loadedFavorites.associateBy { it.id }
        favorites = order.mapNotNull { byId[it] }
        loaded = true
    }

    val inputs = remember(favorites) { favorites.map { it.input } }

    fun set(ids: List<String>) {
        if (ids == current) return
        current = ids
        onChange(ids)
    }

    fun toggle(id: String) {
        haptics.selection()
        set(favoriteSongToggle(current, inputs, id))
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("載せる曲") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                }
            )
        }
    ) { padding ->
        when {
            !loaded -> ImasLoadingState(Modifier.padding(padding))
            favorites.isEmpty() -> ImasPage(modifier = Modifier.padding(padding)) {
                ImasCard {
                    ImasEmptyState(
                        icon = Icons.Filled.FavoriteBorder,
                        title = "お気に入りの曲がありません",
                        message = "曲の一覧や詳細でお気に入りに付けた曲から選べます。"
                    )
                }
            }
            else -> ImasFormBackdrop(Modifier.fillMaxSize().padding(padding)) {
                val picks = favoriteSongPicks(current, inputs)
                val byId = remember(favorites) { favorites.associateBy { it.id } }
                val picked = picks.picked.mapNotNull { byId[it.id] }
                val pickedIds = picked.map { it.id }.toSet()
                val candidates = rememberSearchFiltered(favorites, query) { listOf(it.song.title, it.song.titleKana) }
                val searching = query.isNotBlank()
                LazyColumn(Modifier.fillMaxSize()) {
                    item {
                        ImasSearchField(
                            prompt = "曲名で検索", text = query, onTextChange = { query = it },
                            modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
                        )
                    }
                    if (!searching) {
                        item {
                            ImasListSection(
                                "載せる曲",
                                count = "${picked.size} / ${picks.max}",
                                footer = if (picks.chosenByHand) "載せる順に並びます。矢印で並べ替え、左に引くと外します。"
                                else "まだ選んでいないので、お気に入りに付けた新しい順に載せています。選び直すとその順になります。"
                            ) {
                                if (picked.isEmpty()) {
                                    Text(
                                        "下のお気に入りの曲から選んでください。",
                                        style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color,
                                        modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV)
                                    )
                                }
                                picked.forEachIndexed { index, fav ->
                                    ImasSwipe(background = DS.surface, trailing = listOf(ImasSwipeAction(ImasSwipeKind.DELETE, "外す") { toggle(fav.id) })) {
                                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                            ImasSongRow(
                                                song = fav.song, playsPreview = false, density = ImasRowDensity.COMPACT,
                                                modifier = Modifier.weight(1f)
                                            )
                                            fun move(to: Int) {
                                                val ids = picked.map { it.id }.toMutableList()
                                                ids.add(to, ids.removeAt(index))
                                                haptics.selection()
                                                set(favoriteSongNormalize(ids, inputs))
                                            }
                                            IconButton(onClick = { move(index - 1) }, enabled = index > 0) {
                                                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "${fav.song.title}を上へ")
                                            }
                                            IconButton(onClick = { move(index + 1) }, enabled = index < picked.size - 1) {
                                                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "${fav.song.title}を下へ")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    item {
                        ImasListSection(
                            "お気に入りの曲",
                            count = "${candidates.size}曲",
                            footer = if (picks.full) "載せられるのは ${picks.max} 曲までです。足すときは先にどれかを外してください。" else null
                        ) {
                            candidates.forEach { fav ->
                                val isPicked = fav.id in pickedIds
                                val locked = picks.full && !isPicked
                                ImasSongRow(
                                    song = fav.song, playsPreview = false, density = ImasRowDensity.COMPACT,
                                    trailing = ImasRowTrailing.Custom { ImasSelectionMark(isSelected = isPicked) },
                                    modifier = Modifier
                                        .alpha(if (locked) 0.45f else 1f)
                                        .imasRowPress(enabled = !locked, role = Role.Checkbox, onClick = { toggle(fav.id) })
                                        .semantics { selected = isPicked }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
