package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.ui.components.ImasBrandPicker
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasToolbarButton
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

/**
 * フィルタシートの中で開く「選択ページ」。
 *
 * iOS はシートの NavigationStack に NavigationLink で push しているが、Compose に同じものは
 * 無い。ModalBottomSheet を入れ子にすると スクリム が二重に掛かって、どちらを閉じているのか
 * 読めなくなるので、**同じシートの中身を差し替える**ことで push/pop を再現する。
 * 選択して戻るまでシート自体は一度も閉じないので、選択中のほかの条件も消えない。
 */
@Composable
fun FilterPickerPage(
    title: String,
    onBack: () -> Unit,
    content: @Composable () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ImasToolbarButton(icon = Icons.AutoMirrored.Filled.ArrowBack, label = "フィルタに戻る", onClick = onBack)
            ImasText(title, ImasTextRole.SECTION_TITLE)
        }
        content()
    }
}

/**
 * 候補から 1 つだけ選ぶページ (シリーズ / CD シリーズ / ライブ名)。
 * 候補が数百件あるので、頭に名前絞り込みを置く。
 *
 * @param selected いま選ばれている値。null = 選択なし。
 */
@Composable
fun SingleValuePickerPage(
    title: String,
    items: List<String>,
    selected: String?,
    onBack: () -> Unit,
    onSelect: (String?) -> Unit
) {
    var query by remember { mutableStateOf("") }
    val visible = rememberSearchFiltered(items, query) { listOf(it) }

    FilterPickerPage(title = title, onBack = onBack) {
        NameFilterField(prompt = "${title}で絞り込み", value = query, onValueChange = { query = it })
        LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
            item(key = "__none__") {
                ImasSelectableRow(title = "選択なし", isSelected = selected == null, isSingle = true, onClick = { onSelect(null) })
            }
            items(visible, key = { it }) { value ->
                ImasSelectableRow(title = value, isSelected = selected == value, isSingle = true, onClick = { onSelect(value) })
            }
        }
    }
}

/**
 * アイドルを複数選ぶページ。ブランドチップ + 名前絞り込みで目当てまで降りる。
 *
 * 選択は押すたびに呼び出し側へ返す (ページを閉じるまで溜めない)。フィルタシート本体が
 * 「適用」を押すまで反映しないので、ここで二重に確定を挟むと確定ボタンが 2 つになる。
 */
@Composable
fun IdolMultiPickerPage(
    idols: List<Idol>,
    brands: List<Brand>,
    selected: Set<String>,
    onBack: () -> Unit,
    onToggle: (String) -> Unit,
    onClear: () -> Unit
) {
    var query by remember { mutableStateOf("") }
    var brandId by remember { mutableStateOf<String?>(null) }
    // 語で絞ってからブランドで絞る (索引は idols 全体で組んであるため)。並びは入力順のまま。
    val matched = rememberSearchFiltered(idols, query) { listOf(it.name, it.nameKana, it.aliases) }
    val visible = remember(matched, brandId) {
        matched.filter { brandId == null || it.brandId == brandId }
    }

    FilterPickerPage(title = "アイドル (${selected.size})", onBack = onBack) {
        ImasBrandPicker(
            brands = brands,
            selection = brandId?.let { setOf(it) } ?: emptySet(),
            onSelectionChange = { brandId = it.firstOrNull() },
            allowsMultiple = false,
            modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
        )
        NameFilterField(prompt = "アイドル名で絞り込み", value = query, onValueChange = { query = it })
        if (selected.isNotEmpty()) {
            ImasCardList {
                ImasActionRow(title = "選択をすべて解除", onClick = onClear)
            }
        }
        LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
            items(visible, key = { it.id }) { idol ->
                ImasSelectableRow(
                    title = idol.name,
                    subtitle = idol.nameKana?.takeIf { it.isNotBlank() },
                    isSelected = selected.contains(idol.id),
                    seed = idol.color,
                    brand = idol.brandId,
                    onClick = { onToggle(idol.id) }
                )
            }
        }
    }
}
