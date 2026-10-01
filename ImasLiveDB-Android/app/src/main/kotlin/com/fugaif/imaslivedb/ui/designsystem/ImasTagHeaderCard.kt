package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

// =============================================================================
// タグ詳細の頭 (docs/DESIGN_SYSTEM.md §5・§10.1)。iOS `Community/ImasTagHeaderCard.swift` の移植。
//
// 曲 / アイドル / ユニットのタグ詳細で共通の頭。色の丸・名前・カテゴリの札・説明文 (無ければ「説明なし」)。
// カテゴリは「色で意味を分けない」のですべて同じ札にする。
// =============================================================================

/**
 * タグ詳細の頭 (iOS `ImasTagHeaderCard`)。説明文は選んでコピーできる。
 *
 * @param colorHex タグの色 (データとしての色)。読み上げは「タグカラー: 色名」。
 */
@Composable
fun ImasTagHeaderCard(
    name: String,
    modifier: Modifier = Modifier,
    colorHex: String? = null,
    categoryLabel: String? = null,
    description: String? = null
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.note)) {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
            if (colorHex != null) {
                // 色の既定の読み上げ (「カラー: ...」) ではこの画面の文脈が伝わらないため、「タグカラー:」に替える。
                Box(Modifier.clearAndSetSemantics { contentDescription = "タグカラー: ${ImasColorNames.of(colorHex)}" }) {
                    ImasSwatch(colorHex, size = ImasSwatchSize.SMALL, isDecorative = true)
                }
            }
            Text(name, style = ImasTextRole.HERO_TITLE.style, color = DS.ink, modifier = Modifier.weight(1f))
            if (categoryLabel != null) {
                Box(Modifier.clearAndSetSemantics { contentDescription = "カテゴリ: $categoryLabel" }) {
                    ImasBadge(categoryLabel, kind = ImasBadgeKind.NEUTRAL)
                }
            }
        }
        if (!description.isNullOrEmpty()) {
            SelectionContainer {
                Text(description, style = ImasTextRole.BODY.style, color = DS.ink)
            }
        } else {
            Text("説明なし", style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
        }
    }
}
