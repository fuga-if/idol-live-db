package com.fugaif.imaslivedb.ui.mastery

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 行のスワイプで段階を変えるラッパ (iOS `MasterySwipeActions` の移植)。
 *
 * iOS の swipe actions は段ごとのボタンを並べられるが、Compose の
 * [SwipeToDismissBox] は**向きしか区別できない**ので、一番多い操作だけを割り当てる
 * (右 = 1 段上げる / 左 = 未設定に戻す)。任意の段へ飛ばすのは長押しのピッカーが受け持つ。
 *
 * 引き切っても行は消さない ([SwipeToDismissBox] の確定を必ず断って元へ戻す)。
 * 一覧から行が消えると「何をしたのか」が読めなくなる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MasterySwipeRow(
    /** 右スワイプ (→) のときに走る操作。ラベルは [startLabel]。 */
    onStart: () -> Unit,
    startLabel: String,
    /**
     * 左スワイプ (←) のときに走る操作。null なら左へは引けない。
     *
     * 既定で使わないのは、**端から引くと OS の「戻る」に取られる**ため
     * (右端始まりの左スワイプで画面ごと閉じるのをエミュで実測)。
     */
    onEnd: (() -> Unit)? = null,
    endLabel: String = "",
    /** 背景の色。どの段に変わるかが引いている最中に見える。 */
    startColor: Color,
    endColor: Color = DS.fill,
    content: @Composable () -> Unit,
) {
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> onStart()
                SwipeToDismissBoxValue.EndToStart -> onEnd?.invoke()
                SwipeToDismissBoxValue.Settled -> Unit
            }
            false
        }
    )

    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = true,
        enableDismissFromEndToStart = onEnd != null,
        backgroundContent = {
            val toStart = state.dismissDirection == SwipeToDismissBoxValue.StartToEnd
            Box(
                Modifier.fillMaxSize()
                    .background(if (toStart) startColor else endColor)
                    .padding(horizontal = 20.dp),
                contentAlignment = if (toStart) Alignment.CenterStart else Alignment.CenterEnd,
            ) {
                Text(if (toStart) startLabel else endLabel,
                     fontSize = 13.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            }
        },
    ) {
        content()
    }
}
