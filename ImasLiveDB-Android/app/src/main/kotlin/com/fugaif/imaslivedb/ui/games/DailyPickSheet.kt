package com.fugaif.imaslivedb.ui.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.DailyPick
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.tags.IdolTagPickerSheet
import com.fugaif.imaslivedb.ui.tags.SongTagPickerSheet
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import uniffi.imas_core.DailyPickKind

/**
 * 起動時の日替わりピック「今日の1曲」/「今日のアイドル」。iOS `DailyPickSheet` の移植。
 *
 * 各ブランドから 1 件を日替わり (決定論) でピックし、タグを付けてもらう。
 * タグは曲もアイドルもユーザーが育てるデータで、こちらから初期値は入れない。
 * だから「付けてもらう入口」の数がそのままデータの育ち方になる。曲とアイドルを
 * 同じ画面に縦に並べるとブランド数 × 2 枚になって読まれなくなるので、**日で交互**に
 * して 1 回あたりの分量は変えずに入口を 2 系統に増やしている
 * (どちらの日かはコア `DailyPick.sheetKind` が日付から決める)。
 *
 * ## なぜ ModalBottomSheet ではなく全面オーバーレイなのか
 *
 * このシートからさらにタグピッカー (`SongTagPickerSheet` / `IdolTagPickerSheet`) を
 * 開く。どちらも `ModalBottomSheet` = 内部で独自のウィンドウを持つ実装なので、
 * ボトムシートの中からボトムシートを開くと重なりとタッチ処理が壊れる。
 * こちらは通常のコンポーザブルとして本文の上に重ね、ピッカーだけを
 * ModalBottomSheet に任せる。
 */
@Composable
fun DailyPickSheet(
    onDismiss: () -> Unit,
    kind: DailyPickKind = DailyPick.sheetKind()
) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }

    var songPicks by remember { mutableStateOf<List<Pair<Song, Brand?>>>(emptyList()) }
    var idolPicks by remember { mutableStateOf<List<Pair<Idol, Brand?>>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var taggedIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var songTarget by remember { mutableStateOf<Song?>(null) }
    var idolTarget by remember { mutableStateOf<Idol?>(null) }

    LaunchedEffect(kind) {
        val dayKey = DailyPick.dayKey()
        // 「その他」は日替わりピックの母集団に入れない (ブランドの代表曲/代表アイドルではない)。
        val brands = module.database.brandDao().fetchBrands()
            .filter { it.id != "other" }
            .sortedBy { it.sortOrder }
        when (kind) {
            DailyPickKind.SONG -> {
                val candidates = brands.mapNotNull { brand ->
                    // 候補列も番号と同じく共有コアが正本。未ロード時だけ Room の同条件クエリへ落ちる
                    // (ウィジェット側 InfoWidgetData.todaySong も同じ 2 段で、両者は必ず同じ列を見る)。
                    val ids = module.snapshotStoreProvider.query {
                        it.dailyPickSongIds(brand.id, includeCovers = false, excludeRemixes = true)
                    } ?: module.database.songDao().fetchDailyPickSongIds(brand.id)
                    if (ids.isEmpty()) null else brand to ids
                }
                // 全ブランド分を 1 回の FFI 呼び出しで解決する。
                val indices = DailyPick.songIndices(dayKey, candidates.map { it.first.id to it.second.size })
                val chosen = candidates.zip(indices) { (brand, ids), i -> brand to ids[i] }
                val byId = module.songRepository.fetchSongsByIds(chosen.map { it.second }).associateBy { it.id }
                songPicks = chosen.mapNotNull { (brand, id) -> byId[id]?.let { it to brand } }
            }
            DailyPickKind.IDOL -> {
                val candidates = brands.mapNotNull { brand ->
                    // 一覧と同じ母集団 (外部ゲスト演者を除く)。iOS `idols(brandId:)` と同一条件。
                    val idols = module.idolRepository.fetchIdolsForList(brand.id)
                    if (idols.isEmpty()) null else brand to idols
                }
                val indices = DailyPick.idolIndices(dayKey, candidates.map { it.first.id to it.second.size })
                idolPicks = candidates.zip(indices) { (brand, idols), i -> idols[i] to brand }
            }
        }
        loading = false
    }

    Surface(modifier = Modifier.fillMaxSize(), color = DS.bg) {
        // enableEdgeToEdge() が効いているのでシステムバーの裏まで描かれる。
        // インセットを入れないと見出しと「閉じる」がステータスバーに潜り込み、
        // タップがシステム側に吸われてボタンが押せなくなる (実際に押せなかった)。
        Column(modifier = Modifier.fillMaxSize().safeDrawingPadding()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (kind == DailyPickKind.SONG) "今日の1曲" else "今日のアイドル",
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    color = DS.ink,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "閉じる", tint = DS.ink2)
                }
            }

            if (loading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = DS.sys)
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)
                ) {
                    item {
                        Text(
                            text = if (kind == DailyPickKind.SONG) {
                                "各ブランドから今日の1曲をピックしました。ジャケットをタップで試聴、気になる曲にタグを付けて投票しよう（複数OK・同じタグは人数が貯まります）。"
                            } else {
                                "各ブランドから今日のアイドルをピックしました。性格でも髪型でも口ぐせでも、思いついたタグを付けて投票しよう（複数OK・同じタグは人数が貯まります）。"
                            },
                            fontSize = 13.sp, color = DS.ink2,
                            modifier = Modifier.padding(vertical = 8.dp)
                        )
                    }
                    if (kind == DailyPickKind.SONG) {
                        items(songPicks, key = { it.first.id }) { (song, brand) ->
                            PickCard(
                                seed = brand?.color,
                                brandLabel = brand?.shortName.orEmpty(),
                                title = song.title,
                                subtitle = song.singerLabel,
                                tagged = song.id in taggedIds,
                                onVote = { songTarget = song },
                                thumbnail = {
                                    ArtworkImage(
                                        url = song.artworkUrl,
                                        size = 52.dp,
                                        previewUrl = song.previewUrl,
                                        songTitle = song.title
                                    )
                                }
                            )
                        }
                    } else {
                        items(idolPicks, key = { it.first.id }) { (idol, brand) ->
                            PickCard(
                                seed = brand?.color,
                                brandLabel = brand?.shortName.orEmpty(),
                                title = idol.name,
                                subtitle = idol.currentVoiceActor?.let { "CV: $it" },
                                tagged = idol.id in taggedIds,
                                onVote = { idolTarget = idol },
                                // アバターは本人の推しカラー。左の色帯だけがブランド色 (曲側と揃える)。
                                thumbnail = { ImasAvatar(label = idol.shortName, seed = idol.color, size = 44.dp) }
                            )
                        }
                    }
                }
            }
        }
    }

    songTarget?.let { song ->
        SongTagPickerSheet(
            songId = song.id,
            alreadyAppliedTagIds = emptySet(),
            onDismiss = { songTarget = null },
            onApplied = { taggedIds = taggedIds + song.id }
        )
    }
    idolTarget?.let { idol ->
        IdolTagPickerSheet(
            idolId = idol.id,
            alreadyAppliedTagIds = emptySet(),
            onDismiss = { idolTarget = null },
            onApplied = { taggedIds = taggedIds + idol.id }
        )
    }
}

/**
 * 曲/アイドルで共通のカード外形。色帯・サムネ・見出し列・タグボタンの並びは同じで、
 * サムネと見出しだけが差し替わる (iOS `DailyPickSheet.pickCard` と対)。
 */
@Composable
private fun PickCard(
    seed: String?,
    brandLabel: String,
    title: String,
    subtitle: String?,
    tagged: Boolean,
    onVote: () -> Unit,
    thumbnail: @Composable () -> Unit
) {
    val accent = ImasTheme.derive(seed).accent
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .clickable(onClick = onVote)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ImasLeadBar(seedHex = seed, height = 52.dp)
        thumbnail()
        Column(modifier = Modifier.weight(1f)) {
            Text(brandLabel, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
            Text(
                title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            if (!subtitle.isNullOrEmpty()) {
                Text(subtitle, fontSize = 11.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (tagged) {
                Icon(Icons.Default.Check, contentDescription = null, tint = DS.success, modifier = Modifier.size(18.dp))
            }
            Text(
                if (tagged) "投票済" else "タグ",
                fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                color = if (tagged) DS.success else accent
            )
        }
    }
}
