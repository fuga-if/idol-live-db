package com.fugaif.imaslivedb.ui.search

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.navigation.TopLevelTab
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.delay
import androidx.compose.runtime.mutableIntStateOf

/**
 * タブを跨いだ検索の引き継ぎ。iOS `Views/Search/CrossTabSearch.swift` の移植。
 *
 * ## なぜこれがあるか
 *
 * 以前は虫眼鏡 1 つで横断検索 ([SearchScreen]) を開いていた。検索を各一覧の中に
 * 入れてから、横断検索が単独で提供するものは「すべて」スコープだけになっていた —
 * 曲・アイドル・ライブ・歌詞は全部それぞれの一覧が持っている。しかも一覧側の方が
 * 強い (ブランド絞り込みや並び順と組み合わせられる)。
 *
 * 残っていた価値は「どのタブにあるか分からないものを探せる」ことだけなので、
 * 画面ごと畳んで、各一覧が「他のタブに N 件」を出す形に移した。
 */
object CrossTabSearch {
    // **Compose の状態で持つこと。** ただの `var` にしていたら、値は変わるのに
    // 再コンポーズが起きず、チップを押してもタブが切り替わらなかった
    // (iOS は @Observable なので動いていて、移植で落ちた差分)。
    private var _target by mutableStateOf<TopLevelTab?>(null)
    private var _generation by mutableIntStateOf(0)

    /** 移動先のタブ。ナビが拾って切り替え、受け取った一覧が null に戻す。 */
    val target: TopLevelTab? get() = _target

    /** 世代カウンタ。同じタブへ続けて渡したときも受け側が気づけるようにする。 */
    val generation: Int get() = _generation

    private var query: String = ""

    fun hand(query: String, to: TopLevelTab) {
        this.query = query
        _target = to
        _generation++
    }

    /**
     * 自分宛なら語を受け取る (受け取ったら消す)。
     * 消さないと、そのタブへ戻るたびに同じ語が入り直して、利用者が消した検索欄が
     * 勝手に復活する。
     */
    fun take(tab: TopLevelTab): String? {
        if (_target != tab) return null
        _target = null
        return query
    }
}

/**
 * 「他のタブに N 件」のチップ列。
 *
 * 件数はコアが数える (各一覧の絞り込みと同じ索引を通るので、押した先で数が変わらない)。
 * 0 件の種別は出さない。
 */
@Composable
fun CrossTabCountChips(query: String, from: TopLevelTab) {
    val context = LocalContext.current
    val repo = remember { AppModule.from(context).searchRepository }
    var counts by remember { mutableStateOf<CrossTabSearchCounts?>(null) }

    LaunchedEffect(query) {
        val needle = query.trim()
        if (needle.isEmpty()) {
            counts = null
            return@LaunchedEffect
        }
        // スナップショットは起動直後にバックグラウンドで載る。それより先に訊くと
        // 数えようがないので、載るまで数回だけ待ち直す。0 件と「まだ分からない」は
        // 別物なので、repo は後者を null で返す。
        repeat(6) { attempt ->
            if (attempt > 0) delay(400)
            val got = repo.crossTabCounts(needle)
            if (got != null) {
                counts = got
                return@LaunchedEffect
            }
        }
        counts = null
    }

    val suggestions = remember(counts, from) {
        val c = counts ?: return@remember emptyList()
        listOf(
            TopLevelTab.Events to c.events,
            TopLevelTab.Songs to c.songs,
            TopLevelTab.Idols to c.idols
        ).filter { (tab, n) -> tab != from && n > 0 }
    }
    if (suggestions.isEmpty()) return

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // 上のスコープ列と同じ形の見出し。見出しが無いと、同じ見た目のチップ列が
        // 2 段あるだけになり、「絞り込む対象を変える」のか「別の画面へ移る」のかが読めない。
        Text("別のタブ", fontSize = 12.sp, color = DS.ink3)
        suggestions.forEach { (tab, n) ->
            ImasFilterChip(label = "${tab.label}に $n", selected = false, onClick = {
                CrossTabSearch.hand(query, tab)
            })
        }
    }
}

/** 種別ごとの一致件数。コアの `SearchCounts` をアプリ側の型に写したもの。 */
data class CrossTabSearchCounts(
    val songs: Int = 0,
    val idols: Int = 0,
    val events: Int = 0
)
