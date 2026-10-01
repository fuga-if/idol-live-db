package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.designsystem.ImasNameFilterField

/**
 * 一覧を名前で絞り込むフィールド (iOS `NameFilterField` の移植)。見た目は DS の [ImasNameFilterField]
 * (薄い溝のカプセル・フィルタの記号・消去の ⊗)。
 *
 * これは検索ではなく **フィルタ** である (ブランド絞り込み・並び順と合成され、一覧の並びを保つ)。
 * 横断的に探すのは `SearchScreen` の担当。
 *
 * 今の呼び出しの置き方 (左右 16・上下 8 の余白込み) のまま。
 */
@Composable
fun NameFilterField(
    prompt: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    ImasNameFilterField(
        prompt = prompt,
        text = value,
        onTextChange = onValueChange,
        modifier = modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}
