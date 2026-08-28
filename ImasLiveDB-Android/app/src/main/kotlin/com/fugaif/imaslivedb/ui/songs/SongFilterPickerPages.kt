package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered

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
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(end = 16.dp)
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "フィルタに戻る", tint = DS.ink)
            }
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        }
        HorizontalDivider(color = DS.sep)
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
                PickerRow(label = "選択なし", checked = selected == null, muted = true) { onSelect(null) }
            }
            items(visible, key = { it }) { value ->
                PickerRow(label = value, checked = selected == value) { onSelect(value) }
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
@OptIn(ExperimentalLayoutApi::class)
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
        FlowRow(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ImasFilterChip(label = "全て", selected = brandId == null, onClick = { brandId = null })
            brands.forEach { brand ->
                ImasFilterChip(
                    label = brand.shortName,
                    selected = brandId == brand.id,
                    tintColor = brandColor(brand.id),
                    onClick = { brandId = if (brandId == brand.id) null else brand.id }
                )
            }
        }
        NameFilterField(prompt = "アイドル名で絞り込み", value = query, onValueChange = { query = it })
        if (selected.isNotEmpty()) {
            PickerRow(label = "選択をすべて解除", checked = false, muted = true, onClick = onClear)
        }
        LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
            items(visible, key = { it.id }) { idol ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onToggle(idol.id) }
                        .padding(start = 16.dp, end = 8.dp, top = 4.dp, bottom = 4.dp)
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(idol.name, fontSize = 15.sp, color = DS.ink)
                        idol.nameKana?.takeIf { it.isNotBlank() }?.let {
                            Text(it, fontSize = 11.sp, color = DS.ink3)
                        }
                    }
                    Checkbox(checked = selected.contains(idol.id), onCheckedChange = { onToggle(idol.id) })
                }
                HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
            }
        }
    }
}

/** 選択ページの 1 行。選択中はチェックを出す。 */
@Composable
private fun PickerRow(
    label: String,
    checked: Boolean,
    muted: Boolean = false,
    onClick: () -> Unit
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Text(
            label,
            fontSize = 15.sp,
            color = if (muted) DS.ink2 else DS.ink,
            modifier = Modifier.weight(1f)
        )
        if (checked) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = DS.success)
        }
    }
    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
}
