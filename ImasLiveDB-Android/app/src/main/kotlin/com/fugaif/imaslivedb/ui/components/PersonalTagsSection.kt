package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.designsystem.ImasChip
import com.fugaif.imaslivedb.ui.designsystem.ImasChipInputField
import com.fugaif.imaslivedb.ui.designsystem.ImasChipStyle
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

/**
 * 個人用タグ (iOS の詳細画面の「マイタグ」と同じ形)。端末ローカルのみに保存され、サーバー (コミュニティタグ) には
 * 一切送信されない。コミュニティタグと混同されないよう、灰の札と鍵の記号で区別する。
 * 追加は DS の `ImasChipInputField` (30 文字まで)、削除はチップの長押し。アイドル/ユニット等、複数の詳細画面の
 * コミュニティタブで共用する。
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
fun PersonalTagsSection(
    tags: List<String>,
    /** (名前, 足せたときに呼ぶ) — 書けなかったときは入力を消さない。 */
    onAdd: (String, () -> Unit) -> Unit,
    onRemove: (String) -> Unit
) {
    var input by rememberSaveable { mutableStateOf("") }
    val canAdd = input.trim().isNotEmpty()
    fun add() {
        val name = input.trim()
        if (name.isNotEmpty()) onAdd(name) { input = "" }
    }
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = DS.Space.screen),
        verticalArrangement = Arrangement.spacedBy(DS.sp3)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight), verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.Lock,
                    contentDescription = null,
                    tint = ImasTextRole.NOTE.color,
                    modifier = Modifier.size(with(LocalDensity.current) { 13.sp.toDp() })
                )
                Text("マイタグ", style = ImasTextRole.CARD_TITLE.style, color = DS.ink)
            }
            Text("自分だけに表示されます (コミュニティには公開されません)", style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
        }
        if (tags.isEmpty()) {
            Text("マイタグはまだありません", style = ImasTextRole.NOTE.style, color = DS.ink3)
        } else {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(DS.sp3),
                verticalArrangement = Arrangement.spacedBy(DS.sp3)
            ) {
                tags.forEach { name ->
                    ImasChip(
                        text = name,
                        icon = Icons.Filled.Lock,
                        style = ImasChipStyle.NEUTRAL,
                        modifier = Modifier
                            .semantics {
                                customActions = listOf(CustomAccessibilityAction("マイタグを削除") { onRemove(name); true })
                            }
                            .combinedClickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                onClick = {},
                                onLongClickLabel = "マイタグを削除",
                                onLongClick = { onRemove(name) }
                            )
                    )
                }
            }
            Text("長押しで削除", style = ImasTextRole.META.style, color = ImasTextRole.META.color)
        }
        ImasChipInputField(
            text = input,
            onTextChange = { input = it },
            prompt = "マイタグを追加 (例: 聞いた)",
            submitAccessibilityLabel = "マイタグを追加",
            onSubmit = ::add,
            limit = 30,
            isEnabled = canAdd
        )
    }
}
