package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipe
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeAction
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeKind
import com.fugaif.imaslivedb.ui.designsystem.imasListSectionItems
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import uniffi.imas_core.ProfileSheet
import uniffi.imas_core.ProfileSheetRecord
import uniffi.imas_core.ProfileShowInput
import uniffi.imas_core.profileMemoryPicks
import uniffi.imas_core.profileMoveMemory
import uniffi.imas_core.profileToggleMemory

/**
 * 参加した公演から、P履歴書の「思い出の公演」に載せる公演を選ぶ画面。iOS `MemoryShowPickerView` の移植。
 * 保存先は呼び出し側に任せる ([onChange] に選び直した P名刺の画像の選択を渡す)。
 *
 * 上は載せる公演 (選んだ順。矢印で並べ替え、左に引くと外す)、下は参加した公演すべて (新しい順。
 * 押すと載せる / 外す)。公演は何百にもなるので公演名・会場で絞る (照合はコアの `TextSearchCatalog`)。
 * 上限・まだ選んでいないときの既定 (お気に入りのライブの公演)・並べ替えはコア
 * (`profileMemoryPicks` / `profileToggleMemory` / `profileMoveMemory`)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MemoryShowPickerScreen(
    sheet: ProfileSheet,
    record: ProfileSheetRecord,
    onChange: (ProfileSheet) -> Unit,
    onBack: () -> Unit
) {
    var current by remember { mutableStateOf(sheet) }
    var query by remember { mutableStateOf("") }

    fun set(next: ProfileSheet) {
        if (next == current) return
        current = next
        onChange(next)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("思い出の公演") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                }
            )
        }
    ) { padding ->
        ImasFormBackdrop(Modifier.fillMaxSize().padding(padding)) {
            val picks = profileMemoryPicks(current, record)
            val pickedIds = picks.picked.map { it.showId }.toSet()
            val candidates = rememberSearchFiltered(picks.candidates, query) { listOf(it.title, it.venue) }
            val searching = query.isNotBlank()
            LazyColumn(Modifier.fillMaxSize()) {
                item {
                    ImasSearchField(
                        prompt = "公演名・会場で検索", text = query, onTextChange = { query = it },
                        modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
                    )
                }
                if (!searching) {
                    imasListSectionItems(
                        sectionKey = "picked",
                        items = picks.picked,
                        key = { it.showId },
                        title = "載せる公演",
                        count = "${picks.picked.size} / ${picks.max}",
                        footer = if (picks.chosenByHand) "載せる順に並びます。矢印で並べ替え、左に引くと外します。"
                        else "まだ選んでいないので、お気に入りに付けたライブの公演を新しい順に載せています。選び直すとその順になります。",
                        emptyContent = {
                            Text(
                                "下の参加した公演から選んでください。",
                                style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color,
                                modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV)
                            )
                        }
                    ) { show ->
                        val index = picks.picked.indexOfFirst { it.showId == show.showId }
                        ImasSwipe(
                            background = DS.surface,
                            trailing = listOf(ImasSwipeAction(ImasSwipeKind.DELETE, "外す") {
                                set(profileToggleMemory(current, record, show.showId))
                            })
                        ) {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                ImasRow(
                                    title = show.title, subtitle = subtitle(show), density = ImasRowDensity.COMPACT,
                                    modifier = Modifier.weight(1f)
                                )
                                IconButton(
                                    onClick = { set(profileMoveMemory(current, record, index.toUInt(), (index - 1).toUInt())) },
                                    enabled = index > 0
                                ) { Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "${show.title}を上へ") }
                                IconButton(
                                    onClick = { set(profileMoveMemory(current, record, index.toUInt(), (index + 1).toUInt())) },
                                    enabled = index < picks.picked.size - 1
                                ) { Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "${show.title}を下へ") }
                            }
                        }
                    }
                }
                imasListSectionItems(
                    sectionKey = "attended",
                    items = candidates,
                    key = { it.showId },
                    title = "参加した公演",
                    count = "${candidates.size}公演",
                    footer = if (picks.full) "載せられるのは ${picks.max} 公演までです。足すときは先にどれかを外してください。" else null
                ) { show ->
                    val isPicked = show.showId in pickedIds
                    ImasSelectableRow(
                        title = show.title, subtitle = subtitle(show), isSelected = isPicked,
                        isDisabled = picks.full && !isPicked,
                        onClick = { set(profileToggleMemory(current, record, show.showId)) }
                    )
                }
            }
        }
    }
}

private fun subtitle(show: ProfileShowInput): String =
    listOfNotNull(show.date.replace("-", "."), show.venue).joinToString(" · ")
