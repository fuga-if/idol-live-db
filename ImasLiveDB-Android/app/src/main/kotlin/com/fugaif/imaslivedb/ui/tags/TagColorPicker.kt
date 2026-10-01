package com.fugaif.imaslivedb.ui.tags

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.ui.designsystem.ImasColorPicker

/**
 * タグ色の選択 (iOS `TagColorPicker` → DS `ImasColorPicker`)。「なし」+ プリセット 10 色を 6 列の格子で並べる。
 * SwiftUI の `ColorPicker` (システムの色の選択) に当たる部品は Compose 標準に無いので、プリセットだけで組む。
 *
 * 今の呼び出しの形 (selectedHex・onSelect・modifier) のまま。
 */
@Composable
fun TagColorPicker(selectedHex: String, onSelect: (String) -> Unit, modifier: Modifier = Modifier) {
    ImasColorPicker(selectedHex = selectedHex, onSelect = onSelect, modifier = modifier)
}
