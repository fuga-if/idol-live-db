package com.fugaif.imaslivedb.ui.edit

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.putClearable
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongArtist
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import java.util.UUID

/** 曲種別の内部値と表示ラベル。iOS `SongEditView.songTypes` / `songTypeLabel` と同じ 4 種。 */
private val SONG_TYPES = listOf(
    "solo" to "ソロ",
    "unit" to "ユニット",
    "all" to "全体曲",
    "original" to "オリジナル"
)

/**
 * 曲の新規作成 / 編集。iOS `SongEditView` の移植。ログイン済みユーザーが使える
 * (admin は即時反映、一般ユーザーは修正リクエスト。振り分けは [submitMasterEdit])。
 *
 * 新規作成時:
 * - 歌唱アイドルを 1 名以上選び、SongArtist(role="original") を**同一 batch** で作る。
 *   一覧のアイコンはこの行を根拠に出すので、無いと「誰の曲か分からない曲」が増える。
 * - Song の recordName はクライアント採番 (`song_<uuid>`)。サーバ採番に任せると
 *   同じ batch の SongArtist から songId を参照できない。
 *
 * @param original null なら新規作成。
 * @param initialBrandId 新規作成時のブランド初期選択 (一覧のフィルタ文脈などから)。
 */
@Composable
fun SongEditScreen(
    original: Song? = null,
    initialBrandId: String? = null,
    onDismiss: () -> Unit,
    onSaved: (String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isCreate = original == null
    val key = original?.id ?: "new"

    var title by rememberSaveable(key) { mutableStateOf(original?.title ?: "") }
    var titleKana by rememberSaveable(key) { mutableStateOf(original?.titleKana ?: "") }
    var brandId by rememberSaveable(key) { mutableStateOf(original?.brandId ?: initialBrandId ?: "") }
    var songType by rememberSaveable(key) { mutableStateOf(original?.songType ?: "solo") }
    var unitName by rememberSaveable(key) { mutableStateOf(original?.unitName ?: "") }
    var lyricist by rememberSaveable(key) { mutableStateOf(original?.lyricist ?: "") }
    var composer by rememberSaveable(key) { mutableStateOf(original?.composer ?: "") }
    var arranger by rememberSaveable(key) { mutableStateOf(original?.arranger ?: "") }
    var releaseDate by rememberSaveable(key) { mutableStateOf(original?.releaseDate ?: "") }
    var singerLabel by rememberSaveable(key) { mutableStateOf(original?.singerLabel ?: "") }
    var durationSecText by rememberSaveable(key) { mutableStateOf(original?.durationSec?.toString() ?: "") }
    var appleMusicId by rememberSaveable(key) { mutableStateOf(original?.appleMusicId ?: "") }
    var appleMusicAlbumId by rememberSaveable(key) { mutableStateOf(original?.appleMusicAlbumId ?: "") }
    var artworkUrl by rememberSaveable(key) { mutableStateOf(original?.artworkUrl ?: "") }
    var previewUrl by rememberSaveable(key) { mutableStateOf(original?.previewUrl ?: "") }
    var cdSeries by rememberSaveable(key) { mutableStateOf(original?.cdSeries ?: "") }
    var cdTitle by rememberSaveable(key) { mutableStateOf(original?.cdTitle ?: "") }
    var isrc by rememberSaveable(key) { mutableStateOf(original?.isrc ?: "") }
    var lyricsUrl by rememberSaveable(key) { mutableStateOf(original?.lyricsUrl ?: "") }

    // 新規作成時の歌唱アイドル (SongArtist role=original)。回転しても消えないよう List で退避する。
    var artistIdolIds by rememberSaveable(
        key,
        stateSaver = listSaver<Set<String>, String>(save = { it.toList() }, restore = { it.toSet() })
    ) { mutableStateOf(emptySet()) }
    var showArtistPicker by remember { mutableStateOf(false) }

    var brands by remember { mutableStateOf<List<Brand>>(emptyList()) }
    var idolById by remember { mutableStateOf<Map<String, Idol>>(emptyMap()) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var requestedIssueUrl by remember { mutableStateOf<String?>(null) }
    var requestSent by remember { mutableStateOf(false) }

    LaunchedEffect(isCreate) {
        val module = AppModule.from(context)
        brands = runCatching { module.statsRepository.fetchBrands() }.getOrDefault(emptyList())
        if (isCreate) {
            idolById = runCatching { module.idolRepository.fetchIdols(null) }
                .getOrDefault(emptyList()).associateBy { it.id }
        }
    }

    // ブランドは「未指定」を許す (iOS の Picker 先頭の空タグと同じ)。
    val brandOptions = remember(brands) { listOf("" to "未指定") + brands.map { it.id to it.name } }

    fun save() {
        val trimmedTitle = title.trim()
        val trimmedAmId = appleMusicId.trim()
        val trimmedReleaseDate = releaseDate.trim()
        val trimmedDuration = durationSecText.trim()
        val parsedDuration = trimmedDuration.toIntOrNull()

        // --- 以下のバリデーションは iOS SongEditView.save() と 1:1 で同条件にすること ---
        if (trimmedTitle.isEmpty()) {
            errorMessage = "タイトルを入力してください"; return
        }
        // appleMusicId を入れるなら artworkUrl も必須。一覧のジャケ写は songs.artwork_url を
        // 直接見るので、ID だけ入ると「音は鳴るが絵が出ない曲」ができる。
        if (trimmedAmId.isNotEmpty() && artworkUrl.trim().isEmpty()) {
            errorMessage = "Apple Music ID を設定する場合は artwork URL も必須です (一覧のジャケ写表示に使います)"
            return
        }
        if (isCreate && artistIdolIds.isEmpty()) {
            errorMessage = "歌唱アイドルを 1 名以上選択してください"; return
        }
        if (trimmedReleaseDate.isNotEmpty() && !isValidIsoDate(trimmedReleaseDate)) {
            errorMessage = "リリース日は YYYY-MM-DD 形式で入力してください"; return
        }
        // 非数値は toIntOrNull() が null になるので、iOS の `(parsedDuration ?? -1) < 0` と同じく弾く。
        if (trimmedDuration.isNotEmpty() && (parsedDuration ?: -1) < 0) {
            errorMessage = "再生時間は秒数 (整数) で入力してください"; return
        }

        val songId = original?.id ?: "song_${UUID.randomUUID().toString().lowercase()}"
        val resolvedBrandId = brandId.ifEmpty { null }

        val fields = mutableMapOf<String, Any?>(
            "title" to trimmedTitle,
            "songType" to songType
        )
        // update はサーバ側マージ (未送信 = 現状維持 / null 明示 = クリア)。
        fields.putClearable("brandId", brandId, original?.brandId)
        fields.putClearable("titleKana", titleKana, original?.titleKana)
        fields.putClearable("appleMusicId", trimmedAmId, original?.appleMusicId)
        fields.putClearable("appleMusicAlbumId", appleMusicAlbumId, original?.appleMusicAlbumId)
        fields.putClearable("artworkUrl", artworkUrl, original?.artworkUrl)
        fields.putClearable("previewUrl", previewUrl, original?.previewUrl)
        fields.putClearable("cdSeries", cdSeries, original?.cdSeries)
        fields.putClearable("cdTitle", cdTitle, original?.cdTitle)
        fields.putClearable("lyricsUrl", lyricsUrl, original?.lyricsUrl)
        fields.putClearable("unitName", unitName, original?.unitName)
        fields.putClearable("lyricist", lyricist, original?.lyricist)
        fields.putClearable("composer", composer, original?.composer)
        fields.putClearable("arranger", arranger, original?.arranger)
        fields.putClearable("releaseDate", trimmedReleaseDate, original?.releaseDate)
        fields.putClearable("singerLabel", singerLabel, original?.singerLabel)
        fields.putClearable("isrc", isrc, original?.isrc)
        if (parsedDuration != null) {
            fields["durationSec"] = parsedDuration
        } else if (original?.durationSec != null) {
            fields["durationSec"] = null
        }

        val ops = mutableListOf(
            EditApi.EditOperation(
                op = if (isCreate) EditApi.EditOp.CREATE else EditApi.EditOp.UPDATE,
                recordType = "Song",
                recordName = songId,
                fields = fields
            )
        )
        if (isCreate) {
            // recordName 規約は seed と同じ "song_artists-<songId>-<idolId>-<role>"。
            for (idolId in artistIdolIds) {
                ops.add(
                    EditApi.EditOperation(
                        op = EditApi.EditOp.CREATE,
                        recordType = "SongArtist",
                        recordName = "song_artists-$songId-$idolId-original",
                        fields = mapOf("songId" to songId, "idolId" to idolId, "role" to "original")
                    )
                )
            }
        }

        isSaving = true
        scope.launch {
            val result = submitMasterEdit(
                context = context,
                ops = ops,
                summary = if (isCreate) "曲を追加" else "曲編集",
                fallbackRecordName = songId
            ) { resolvedId ->
                val syncDao = AppModule.from(context).database.syncDao()
                // フォームに無い列 (parentSongId / unitId / seriesGroup / unitVersionId) は
                // 元レコードから引き継ぐ。Room の upsert は行ごと REPLACE なので、
                // ここで copy しないと編集のたびにそれらが消える。
                val saved = (original ?: emptySong(resolvedId)).copy(
                    id = resolvedId,
                    title = trimmedTitle,
                    titleKana = titleKana.nonEmptyTrimmed(),
                    brandId = resolvedBrandId,
                    songType = songType,
                    appleMusicId = trimmedAmId.ifEmpty { null },
                    appleMusicAlbumId = appleMusicAlbumId.nonEmptyTrimmed(),
                    artworkUrl = artworkUrl.nonEmptyTrimmed(),
                    previewUrl = previewUrl.nonEmptyTrimmed(),
                    cdSeries = cdSeries.nonEmptyTrimmed(),
                    cdTitle = cdTitle.nonEmptyTrimmed(),
                    lyricsUrl = lyricsUrl.nonEmptyTrimmed(),
                    unitName = unitName.nonEmptyTrimmed(),
                    lyricist = lyricist.nonEmptyTrimmed(),
                    composer = composer.nonEmptyTrimmed(),
                    arranger = arranger.nonEmptyTrimmed(),
                    releaseDate = trimmedReleaseDate.ifEmpty { null },
                    singerLabel = singerLabel.nonEmptyTrimmed(),
                    isrc = isrc.nonEmptyTrimmed(),
                    durationSec = parsedDuration
                )
                syncDao.upsertSongs(listOf(saved))
                if (isCreate) {
                    syncDao.upsertSongArtists(artistIdolIds.map { SongArtist(resolvedId, it, "original") })
                }
            }
            isSaving = false
            when (result) {
                is MasterEditSubmitResult.Applied -> onSaved(result.recordName)
                is MasterEditSubmitResult.Requested -> {
                    requestedIssueUrl = result.issueUrl
                    requestSent = true
                }
                is MasterEditSubmitResult.Failed -> errorMessage = result.message
            }
        }
    }

    MasterEditScaffold(
        title = if (isCreate) "曲を追加" else "曲編集",
        canSave = title.trim().isNotEmpty(),
        isSaving = isSaving,
        onCancel = onDismiss,
        onSave = ::save
    ) {
        EditSection("基本情報") {
            if (original != null) EditReadonlyRow("ID", original.id)
            EditTextField("タイトル", title, { title = it })
            EditTextField("タイトル (カナ)", titleKana, { titleKana = it })
            EditDropdownField("ブランド", brandOptions, brandId) { brandId = it }
            EditDropdownField("種別", SONG_TYPES, songType) { songType = it }
            EditTextField("ユニット名", unitName, { unitName = it })
        }

        if (isCreate) {
            EditSection(
                "歌唱アイドル",
                footer = "一覧でアイコンを出すために必要です。ソロ曲なら 1 名、ユニット曲なら全員を選んでください。"
            ) {
                EditNavRow(
                    label = "歌唱アイドル (${artistIdolIds.size})",
                    value = artistIdolIds.mapNotNull { idolById[it]?.name }.sorted().joinToString(" / "),
                    placeholder = "歌唱アイドルを選択",
                    onClick = { showArtistPicker = true }
                )
            }
        }

        EditSection("制作情報") {
            EditTextField("作詞", lyricist, { lyricist = it })
            EditTextField("作曲", composer, { composer = it })
            EditTextField("編曲", arranger, { arranger = it })
            EditTextField("リリース日 (YYYY-MM-DD)", releaseDate, { releaseDate = it })
            EditTextField("歌唱表記 (例: 春香・千早)", singerLabel, { singerLabel = it })
            EditTextField("再生時間 (秒)", durationSecText, { durationSecText = it }, numeric = true)
        }

        EditSection("Apple Music") {
            EditTextField("apple_music_id", appleMusicId, { appleMusicId = it }, numeric = true)
            EditTextField("apple_music_album_id", appleMusicAlbumId, { appleMusicAlbumId = it }, numeric = true)
            EditTextField("artwork URL", artworkUrl, { artworkUrl = it })
            EditTextField("preview URL", previewUrl, { previewUrl = it })
        }

        EditSection("CD / その他") {
            EditTextField("cd_series", cdSeries, { cdSeries = it })
            EditTextField("cd_title", cdTitle, { cdTitle = it })
            EditTextField("ISRC", isrc, { isrc = it })
            EditTextField("歌詞 URL", lyricsUrl, { lyricsUrl = it })
        }

        if (!isCreate) {
            EditSection(
                "誤紐付けの修正",
                footer = "誤紐付けで他の曲が再生されるときに使う。サブスク未配信の曲はクリアすべき。"
            ) {
                TextButton(
                    onClick = {
                        appleMusicId = ""
                        appleMusicAlbumId = ""
                        artworkUrl = ""
                        previewUrl = ""
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Apple Music 関連を全て空にする", color = DS.danger)
                }
            }
        }

        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Text(
                "保存すると、この編集は「最近の編集」に記録されます。",
                fontSize = 11.sp, color = DS.ink3
            )
        }
    }

    if (showArtistPicker) {
        IdolMultiSelectSheet(
            selected = artistIdolIds,
            onDismiss = { showArtistPicker = false },
            onConfirm = { artistIdolIds = it; showArtistPicker = false },
            title = "歌唱アイドル"
        )
    }

    errorMessage?.let { EditErrorDialog(it) { errorMessage = null } }

    if (requestSent) {
        EditRequestSentDialog(requestedIssueUrl) { requestSent = false; onDismiss() }
    }
}

/** 新規作成時の土台。フォームで埋める列以外は既定値 (null) にする。 */
private fun emptySong(id: String) = Song(
    id = id,
    title = "",
    titleKana = null,
    brandId = null,
    songType = "solo",
    releaseDate = null,
    durationSec = null,
    composer = null,
    lyricist = null,
    arranger = null,
    cdSeries = null,
    cdTitle = null,
    artworkUrl = null,
    previewUrl = null,
    appleMusicId = null,
    appleMusicAlbumId = null,
    isrc = null,
    lyricsUrl = null,
    parentSongId = null,
    singerLabel = null,
    unitName = null,
    unitId = null
)
