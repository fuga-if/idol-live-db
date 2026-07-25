package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 押して on/off できるチップ。フィルタ・カテゴリ・種別の選択に使う「唯一の正」。
 *
 * 見た目は [ImasChip] と完全に同一 (同じ Capsule・タイポ・余白) で、押下と選択状態だけを足す。
 * 以前は Material の primary / outline を直に塗っており、DS の「システムクロムはほぼ無彩、
 * 色は常にエンティティ側から来る」原則から外れ、余白・タイポも ImasChip と揃っていなかった。
 *
 * @param label     チップの表示文言
 * @param selected  選択中かどうか
 * @param seed      配色シード (アイドル色など)。指定するとその色から accent を導出する
 * @param brand     ブランド色シード
 * @param icon      先頭アイコン (任意)
 */
@Composable
fun ImasFilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    seed: String? = null,
    brand: String? = null,
    /** 実体色そのもの (ブランド色 Color 等)。WCAG コントラスト計算を通してから塗る。 */
    tintColor: Color? = null,
    icon: ImageVector? = null,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier) {
        ImasChip(
            text = label,
            icon = icon,
            style = if (selected) ImasChipStyle.SELECTED else ImasChipStyle.NEUTRAL,
            seed = seed,
            brand = brand,
            color = tintColor,
            onClick = onClick
        )
    }
}

/**
 * 適用中フィルタを表す除去可能チップ (× タップで解除)。iOS ImasRemovableChip 相当。
 * 曲一覧の「担当」「お気に入り」「回収済み」「タグ」等、適用中フィルタの一覧行に使う。
 */
@Composable
fun ImasRemovableChip(
    text: String,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        shape = CircleShape,
        color = DS.fill,
        modifier = modifier
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(start = 12.dp, end = 8.dp, top = 6.dp, bottom = 6.dp)
        ) {
            Text(text = text, style = MaterialTheme.typography.labelMedium, color = DS.ink)
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "${text}を解除",
                tint = DS.ink2,
                modifier = Modifier
                    .size(16.dp)
                    .clickable(onClick = onRemove)
            )
        }
    }
}
