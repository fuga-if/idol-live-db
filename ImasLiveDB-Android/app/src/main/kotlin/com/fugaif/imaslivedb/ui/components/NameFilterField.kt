package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.ui.draw.alpha
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 一覧を名前で絞り込むフィールド (iOS `NameFilterField` の移植)。
 *
 * これは検索ではなく **フィルタ** である (ブランド絞り込み・並び順と合成され、一覧の並びを保つ)。
 * 以前は虫眼鏡アイコン + 「〜で検索」の文言だったため、ツールバーの検索 (詳細へ飛ぶ) と
 * 区別が付かなかった。役割どおりフィルタのアイコンと文言にしている。
 * 横断的に探すのは `SearchScreen` の担当。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NameFilterField(
    prompt: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(prompt, color = DS.ink3) },
        leadingIcon = { Icon(Icons.Filled.FilterList, contentDescription = null, tint = DS.ink3) },
        trailingIcon = {
            // 出し入れせず常に置いて、見た目だけ消す。入力の 1 文字目で
            // 「空 → 非空」に変わった瞬間に入力欄の幅が変わり、文字が横にずれるのを防ぐ
            // (iOS 側は同じ作りで日本語 IME の 1 文字目が変換できなくなっていた)。
            val hasText = value.isNotEmpty()
            IconButton(
                onClick = { onValueChange("") },
                enabled = hasText,
                modifier = Modifier.alpha(if (hasText) 1f else 0f)
            ) {
                Icon(Icons.Filled.Clear, contentDescription = "絞り込みを解除", tint = DS.ink3)
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(50),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = DS.fill,
            unfocusedContainerColor = DS.fill,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            focusedTextColor = DS.ink,
            unfocusedTextColor = DS.ink
        ),
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    )
}
