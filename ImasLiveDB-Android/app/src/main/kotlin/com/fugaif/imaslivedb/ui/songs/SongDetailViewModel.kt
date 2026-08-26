package com.fugaif.imaslivedb.ui.songs

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.WeightedSampling
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongCall
import com.fugaif.imaslivedb.data.model.SongPerformanceEvidence
import com.fugaif.imaslivedb.data.model.SongVideo
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SongDetailUiState(
    val isLoading: Boolean = true,
    val song: Song? = null,
    val originalArtists: List<Idol> = emptyList(),
    val performerArtists: List<Idol> = emptyList(),
    val performanceHistory: List<PerformanceHistoryRow> = emptyList(),
    val unit: ImasUnit? = null,
    val brand: Brand? = null,
    /** 現地回収済み (参加ライブでこの曲が披露された) 公演一覧。 */
    val collectedShows: List<PerformanceHistoryRow> = emptyList(),
    /** 関連楽曲 (同シリーズ/ユニット/原唱共有, ローカル算出)。 */
    val relatedSongs: List<Song> = emptyList(),
    /**
     * 披露実績から出した共起曲と歌唱者 (共有コアのスナップショット走査)。
     * 披露 0 回の曲・スナップショット未ロードでは EMPTY。画面はそのとき節を出さない。
     */
    val performanceEvidence: SongPerformanceEvidence = SongPerformanceEvidence.EMPTY,
    /** タグが似ている楽曲 (この曲が好きな人にはこれも, サーバ算出)。 */
    val similarTagSongs: List<Song> = emptyList(),
    val similarSharedTags: Map<String, Int> = emptyMap(),
    val songCalls: List<SongCall> = emptyList(),
    val songVideos: List<SongVideo> = emptyList(),
    val tags: List<CommunityApi.SongTag> = emptyList(),
    val penlight: CommunityApi.PenlightResult? = null,
    val isFavorite: Boolean = false
)

class SongDetailViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(SongDetailUiState())
    val uiState: StateFlow<SongDetailUiState> = _uiState.asStateFlow()

    private var api: CommunityApi? = null
    private var currentSongId: String? = null
    private var appModule: AppModule? = null

    fun load(context: Context, songId: String) {
        currentSongId = songId
        viewModelScope.launch {
            val module = AppModule.from(context)
            appModule = module
            api = module.communityApi
            val song = module.songRepository.fetchSong(songId)
            val originalArtists = module.songRepository.fetchSongArtists(songId, "original")
            val performerArtists = module.songRepository.fetchSongArtists(songId, "performer")
            val history = module.songRepository.fetchSongPerformanceHistory(songId)
            val unit = if (song?.unitId != null) {
                module.unitRepository.fetchUnit(song.unitId)
            } else {
                null
            }
            val brand = song?.brandId?.let { brandId ->
                module.database.brandDao().fetchBrands().firstOrNull { it.id == brandId }
            }
            val collectedShows = module.songRepository.fetchCollectedShows(songId)
            val relatedSongs = if (song != null) module.songRepository.fetchRelatedSongs(song, limit = 8) else emptyList()
            // 曲詳細 1 オープンにつき FFI は 1 回だけ。共起と歌唱者はコア側で束ねてある。
            val evidence = module.performanceEvidenceRepository.fetchSongPerformanceEvidence(songId)
            val calls = module.database.communityDao().callsForSong(songId)
            val videos = module.database.communityDao().videosForSong(songId)
            val isFavorite = module.userMarkRepository.isOn(UserMark.SONG, songId, UserMark.FAVORITE)
            _uiState.value = SongDetailUiState(
                isLoading = false,
                song = song,
                originalArtists = originalArtists,
                performerArtists = performerArtists,
                performanceHistory = history,
                unit = unit,
                brand = brand,
                collectedShows = collectedShows,
                relatedSongs = relatedSongs,
                performanceEvidence = evidence,
                songCalls = calls,
                songVideos = videos,
                isFavorite = isFavorite
            )
            // 集計系コミュニティ (Worker D1) はネットワーク。失敗しても本体表示は維持。
            loadCommunity(songId)
            loadSimilarSongs(songId)
        }
    }

    private suspend fun loadCommunity(songId: String) {
        val a = api ?: return
        val tags = runCatching { a.songTags(songId) }.getOrDefault(emptyList())
        val pen = runCatching { a.penlightVotes(songId) }.getOrNull()
        if (currentSongId == songId) {
            _uiState.value = _uiState.value.copy(tags = tags, penlight = pen)
        }
    }

    /**
     * タグ類似のおすすめ楽曲をサーバから取得し、ローカル DB で Song に解決する。
     *
     * サーバは候補を近い順に多め (50 件) 返すので、そこから表示分を**毎回抽選**する。
     * 近さを重みにした重み付き抽選なので、似ている曲が中心に出つつ、
     * 少しだけタグが被っている曲もときどき混ざる。曲を開き直すと顔ぶれが変わる。
     */
    private suspend fun loadSimilarSongs(songId: String) {
        val a = api ?: return
        val module = appModule ?: return
        val candidates = runCatching { a.similarSongsByTags(songId) }.getOrDefault(emptyList())
        if (candidates.isEmpty() || currentSongId != songId) return
        val picked = WeightedSampling.pick(candidates, SIMILAR_SONGS_DISPLAY_COUNT) { it.pickWeight }
        val resolved = module.songRepository.fetchSongsByIds(picked.map { it.songId })
        val byId = resolved.associateBy { it.id }
        val sharedTags = picked.associate { it.songId to it.sharedTags }
        // 抽選順 (重み付きのランダム順) を維持する。
        val ordered = picked.mapNotNull { byId[it.songId] }
        if (currentSongId == songId) {
            _uiState.value = _uiState.value.copy(similarTagSongs = ordered, similarSharedTags = sharedTags)
        }
    }

    /**
     * タグ投票のトグル。完了後にタグを再取得。
     *
     * ここに権限判定は無い (書き込みの素の口)。付ける方向は必ず画面側の
     * `startCommunityEdit` ゲートを通してから呼ぶこと — 直接呼ぶと未ログイン/BAN 済みでも
     * 投票が飛ぶ。外す方向 (`tag.mine`) は iOS の contextMenu 同様ゲートしない。
     */
    fun toggleTag(tag: CommunityApi.SongTag) {
        val songId = currentSongId ?: return
        val a = api ?: return
        viewModelScope.launch {
            runCatching {
                if (tag.mine) a.removeTag(songId, tag.id) else a.applyTag(songId, tag.id)
            }
            loadCommunity(songId)
        }
    }

    /** タグ追加ピッカー (SongTagPickerSheet) で新規タグを適用した後の再取得。 */
    fun onTagsApplied() {
        val songId = currentSongId ?: return
        viewModelScope.launch { loadCommunity(songId) }
    }

    /** コーレス投稿/編集 (CallEditSheet) 成功後、一覧を差し替える (新規は先頭に追加)。 */
    fun onCallSaved(call: SongCall) {
        val current = _uiState.value.songCalls
        val updated = if (current.any { it.id == call.id }) {
            current.map { if (it.id == call.id) call else it }
        } else {
            listOf(call) + current
        }
        _uiState.value = _uiState.value.copy(songCalls = updated)
    }

    /** お気に入りトグル (端末ローカル)。 */
    fun toggleFavorite() {
        val songId = currentSongId ?: return
        val module = appModule ?: return
        viewModelScope.launch {
            val now = module.userMarkRepository.toggle(UserMark.SONG, songId, UserMark.FAVORITE)
            _uiState.value = _uiState.value.copy(isFavorite = now)
        }
    }

    /** ペンライト投票完了後の再取得。 */
    fun onPenlightVoted() {
        val songId = currentSongId ?: return
        viewModelScope.launch { loadCommunity(songId) }
    }

    private companion object {
        /** おすすめとして画面に出す件数。候補はサーバから多めに取り、ここまで絞る。 */
        const val SIMILAR_SONGS_DISPLAY_COUNT = 6
    }
}
