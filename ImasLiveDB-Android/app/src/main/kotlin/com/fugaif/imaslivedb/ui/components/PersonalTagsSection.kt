package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 個人用タグ。端末ローカルのみに保存され、サーバー(コミュニティタグ)には一切送信されない。
 * コミュニティタグと混同されないよう、グレー基調・鍵アイコンで視覚的に区別する。
 * 削除はチップの長押し。アイドル/ユニット等、複数の詳細画面のコミュニティタブで共用する。
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
fun PersonalTagsSection(
    tags: List<String>,
    onAdd: (String) -> Unit,
    onRemove: (String) -> Unit
) {
    var input by rememberSaveable { mutableStateOf("") }
    Column {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 16.dp)) {
            Icon(Icons.Filled.Lock, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(14.dp))
            Text(
                "マイタグ(自分だけに表示)", fontSize = 13.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold, color = DS.ink2,
                modifier = Modifier.padding(start = 6.dp)
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedTextField(
                value = input,
                onValueChange = { if (it.length <= 30) input = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("例: 聞いた", fontSize = 13.sp) },
                singleLine = true
            )
            IconButton(onClick = {
                val name = input.trim()
                if (name.isNotEmpty()) {
                    onAdd(name)
                    input = ""
                }
            }) {
                Icon(Icons.Filled.Add, contentDescription = "マイタグを追加", tint = DS.ink2)
            }
        }
        if (tags.isEmpty()) {
            Text(
                "マイタグはまだありません", fontSize = 13.sp, color = DS.ink3,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
            )
        } else {
            FlowRow(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                tags.forEach { name ->
                    Row(
                        modifier = Modifier.clip(RoundedCornerShape(999.dp))
                            .background(DS.fill)
                            .border(1.dp, DS.sep, RoundedCornerShape(999.dp))
                            .combinedClickable(onClick = {}, onLongClick = { onRemove(name) })
                            .padding(start = 10.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(name, fontSize = 13.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold, color = DS.ink2)
                        Icon(
                            Icons.Filled.Close, contentDescription = "削除",
                            tint = DS.ink3, modifier = Modifier.size(14.dp).padding(start = 4.dp)
                        )
                    }
                }
            }
            Text(
                "長押しで削除", fontSize = 11.sp, color = DS.ink3,
                modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 2.dp)
            )
        }
    }
}
