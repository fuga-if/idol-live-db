package com.fugaif.imaslivedb.ui.events

import android.app.Application
import android.content.Context
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.fugaif.imaslivedb.data.auth.AuthState
import com.fugaif.imaslivedb.data.community.SetlistLikeService
import com.fugaif.imaslivedb.data.local.localWrite
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformerRow
import com.fugaif.imaslivedb.data.model.SetlistRow
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowTicket
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.data.repository.SetlistRowMetaResult
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.PerformerNameMode
import uniffi.imas_core.SetlistDisplayMode
import uniffi.imas_core.SetlistDisplayModeOption
import uniffi.imas_core.SetlistRowMetaRecord
import uniffi.imas_core.ShowCollectionRecord
import uniffi.imas_core.setlistDisplayModeFromStored

data class SetlistSection(
    val sectionName: String,
    val items: List<SetlistRow>
)

data class SetlistUiState(
    val isLoading: Boolean = true,
    val show: Show? = null,
    /** キャラクターが出演する公演か (名義の出し方が変わる)。判定はコア。 */
    val isCharacterLive: Boolean = false,
    val brandId: String? = null,
    val setlist: List<SetlistRow> = emptyList(),
    val performersByItemId: Map<String, List<PerformerRow>> = emptyMap(),
    /**
     * 歌唱者のアイドル実体 (id → Idol)。セトリの行がアイコンの束 (写真か判子) を出すための
     * 略称 ([Idol.shortName]) を引く。歌唱者の判定・表示名そのものはコア/[PerformerRow] が正で、
     * ここはアイコン描画に要る実体を添えるだけ。
     */
    val idolsById: Map<String, Idol> = emptyMap(),
    /**
     * この公演の券種 (マスタ・生の行)。「どんな価格の券があったか」を出す。
     * 絞り込み・並び・価格帯の判断は画面側で共有コア (`ticketsForKind` 等) へ委ねる。
     */
    val tickets: List<ShowTicket> = emptyList(),
    /**
     * setlist_items.id → 行の添え物 (名義・ユニットの札・全員・何回目・いつぶり・自分の回収)。
     * **中身を決めるのは共有コア。** 画面はキーで引いて出すだけ。
     */
    val rowMetaByItemId: Map<String, SetlistRowMetaRecord> = emptyMap(),
    /**
     * 公演の頭に出す「自分の回収」の要約 (この公演で N 曲回収 / 未回収 N 曲)。
     * **出すかどうかも文言も共有コアが決める。** null なら何も出さない
     * (参加記録が無い人・回収の対象でない催し・シンプル表示)。
     */
    val collectionSummary: ShowCollectionRecord? = null,
    /** 公演が属するイベントの名前。パンくずの 2 段目と、セトリ編集の見出しに使う。 */
    val eventName: String = "",
    /** パンくずの 1 段目 (ブランドの短縮名)。 */
    val brandShortName: String? = null,
    /** 会場名を「公演日時点の名前」で出すための会場マスタ (改名前の公演は当時名)。 */
    val venues: VenueDirectory = VenueDirectory.EMPTY
) {
    /**
     * 区切りの塊。**どこで塊を切るかも見出しの文言も共有コアが決める**
     * (`rowMetaByItemId[id].startsSection` / `sectionHeading`)。ここは true の行で
     * 新しい塊を始めるだけで、`section` の生の値を隣と比べない。
     * 添え物が無い (まだ読めていない) ときは全体を 1 つの「本編」にする。
     */
    val sections: List<SetlistSection>
        get() {
            val result = mutableListOf<SetlistSection>()
            for (item in setlist) {
                val meta = rowMetaByItemId[item.id]
                if (result.isEmpty() || meta?.startsSection == true) {
                    result.add(SetlistSection(sectionName = meta?.sectionHeading ?: "本編", items = listOf(item)))
                } else {
                    val last = result.last()
                    result[result.lastIndex] = last.copy(items = last.items + item)
                }
            }
            return result
        }
}

/** この公演に付けた自分のマーク (参加 / お気に入り / メモ / 座席)。 */
data class ShowMarks(
    val attendance: AttendanceType? = null,
    val favoriteOn: Boolean = false,
    val note: String? = null,
    val seat: String? = null
)

/**
 * 公演のセトリ画面。読み込み (セトリ・出演者・添え物・パンくず・会場マスタ・マーク・👍) と、
 * マーク・👍 の書き込みをここに集める。画面はこれを呼んで出すだけ。
 *
 * 書き込み (マーク・👍) はアプリのスコープで行う。画面のスコープだと、押した直後に
 * 画面を離れると途中で止まることがある。
 */
class SetlistViewModel(app: Application, private val showId: String) : AndroidViewModel(app) {

    private val module = AppModule.from(app)
    private val events = module.eventRepository
    private val marks = module.userMarkRepository
    private val likeService = module.setlistLikeService

    private val _uiState = MutableStateFlow(SetlistUiState())
    val uiState: StateFlow<SetlistUiState> = _uiState.asStateFlow()

    private val _marks = MutableStateFlow(ShowMarks())
    val showMarks: StateFlow<ShowMarks> = _marks.asStateFlow()

    /** 曲 ID → 👍 の集計と自分の 👍。 */
    private val _likes = MutableStateFlow<Map<String, SetlistLikeService.LikeEntry>>(emptyMap())
    val likes: StateFlow<Map<String, SetlistLikeService.LikeEntry>> = _likes.asStateFlow()

    /**
     * 表示の詳しさ。公演をまたいで端末に残す。「1 枚のスクショに収めたい」人は
     * 次の公演でも同じ見方をするので、画面を離れるたびに戻ると毎回押し直しになる。
     */
    private val _displayMode = MutableStateFlow(SetlistViewPrefs.displayMode(app))
    val displayMode: StateFlow<SetlistDisplayMode> = _displayMode.asStateFlow()

    /** ログイン誘導を出しているか (編集・👍 の導線、または 👍 がサーバに断られたとき)。 */
    private val _loginPrompt = MutableStateFlow(false)
    val loginPrompt: StateFlow<Boolean> = _loginPrompt.asStateFlow()

    val authState: StateFlow<AuthState> = module.authService.state

    /** 最後に頼まれた読み込みの設定。参加の付け外しや編集の保存の後に同じ設定で読み直す。 */
    private var lastRequest: LoadRequest? = null
    private var loadJob: Job? = null
    /** 会場マスタは小さく公演で変わらないので、この画面で 1 回だけ読む。 */
    private var venues: VenueDirectory? = null
    private val rowMetaCache = RowMetaCache()

    private data class LoadRequest(val nameMode: PerformerNameMode, val includeStreamInCollection: Boolean)

    /**
     * @param nameMode 歌唱者をどの名前で出すか。**行の添え物の中身が変わる**ので、
     *   設定が変わったら呼び直すこと (画面側が設定を鍵にした LaunchedEffect で呼ぶ)。
     * @param includeStreamInCollection 設定「配信参加も回収に含める」の現在値。
     *   **回収の答えが変わる**ので、変わったら呼び直すこと。
     *
     * 表示の詳しさ ([displayMode]) はこの ViewModel が持ち、変えたら自分で読み直す。
     * 履歴の札・回収の札・要約を出すかどうかもコアがこれで決める。
     */
    fun load(nameMode: PerformerNameMode, includeStreamInCollection: Boolean) {
        val request = LoadRequest(nameMode, includeStreamInCollection)
        lastRequest = request
        // 後から頼まれた読み込みが勝つ (先の読み込みが後から終わって古い値で上書きしない)。
        loadJob?.cancel()
        loadJob = viewModelScope.launch { fetch(request, _displayMode.value) }
    }

    /** 最後と同じ設定で読み直す (参加の付け外し・セトリ編集の保存の後)。 */
    fun reload() {
        lastRequest?.let { load(it.nameMode, it.includeStreamInCollection) }
    }

    fun setDisplayMode(option: SetlistDisplayModeOption) {
        SetlistViewPrefs.setDisplayMode(getApplication(), option.raw)
        _displayMode.value = option.mode
        reload()
    }

    private suspend fun fetch(request: LoadRequest, displayMode: SetlistDisplayMode) {
        val showInfo = events.fetchShowInfo(showId)
        val show = showInfo?.show
        val event = show?.eventId?.let { events.fetchEvent(it) }
        val brandId = event?.brandId
        // 画面の 2 つの半分 (曲と出演者) は同じ所有者から読む。DAO を直接叩くと
        // どちらの経路がいつ更新されるかがリポジトリの外に散り、片方だけ古い値を
        // 表示する事故に戻る。
        val setlist = events.fetchSetlist(showId)
        // 曲ごとのグループ化と並びは共有コア (showSetlistPerformers) が持つ。
        val performersByItemId = events.fetchPerformersByItem(showId)
        // 歌唱者のアイコン (写真か判子) に要る略称 (Idol.shortName)。判断はしない単なる hydration。
        val performerIdolIds = performersByItemId.values.flatten().mapNotNull { it.idolId }.distinct()
        val idolsById = if (performerIdolIds.isEmpty()) {
            emptyMap()
        } else {
            module.idolRepository.fetchIdolsByIds(performerIdolIds).associateBy { it.id }
        }
        val tickets = module.showTicketRepository.forShow(showId)
        // 名義も「いつぶりか」も「自分の回収」も共有コアが決める。ここは受け取って配るだけ。
        // 読み直し (設定の切り替え等) が落ちても、同じ公演なら前の答えを残す
        // (消すと区切りの見出しが全部「本編」に潰れ、落ちたことが画面の形の変化として出る)。
        val rowMeta = try {
            rowMetaCache.loaded(showId, events.fetchSetlistRowMeta(
                showId, request.nameMode, displayMode, request.includeStreamInCollection
            ))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "load_failed setlist_row_meta", e)
            rowMetaCache.failed(showId)
        }
        val brandShortName = brandId?.let { events.fetchBrand(it)?.shortName }
        val venueDirectory = venues ?: events.fetchVenueDirectory().also { venues = it }
        loadMarks()

        _uiState.value = SetlistUiState(
            isLoading = false,
            show = show,
            isCharacterLive = showInfo?.isCharacterLive == true,
            brandId = brandId,
            setlist = setlist,
            performersByItemId = performersByItemId,
            idolsById = idolsById,
            tickets = tickets,
            rowMetaByItemId = rowMeta.rowsByItemId,
            collectionSummary = rowMeta.collection,
            eventName = event?.name.orEmpty(),
            brandShortName = brandShortName,
            venues = venueDirectory
        )
    }

    private suspend fun loadMarks() {
        _marks.value = ShowMarks(
            attendance = marks.attendance(UserMark.SHOW, showId),
            favoriteOn = marks.isOn(UserMark.SHOW, showId, UserMark.FAVORITE),
            note = marks.note(UserMark.SHOW, showId),
            seat = marks.seat(UserMark.SHOW, showId)
        )
    }

    fun toggleFavorite() = write {
        val on = localWrite("お気に入りの切り替え") { marks.toggle(UserMark.SHOW, showId, UserMark.FAVORITE) }
            ?: return@write
        _marks.update { it.copy(favoriteOn = on) }
    }

    /** 保存できたときだけ [onSaved] (編集を閉じる)。書けなかったら入力を捨てない。 */
    fun setNote(text: String?, onSaved: () -> Unit) = write {
        localWrite("メモの保存") { marks.setNote(UserMark.SHOW, showId, text) } ?: return@write
        val saved = marks.note(UserMark.SHOW, showId)
        _marks.update { it.copy(note = saved) }
        withContext(Dispatchers.Main) { onSaved() }
    }

    /** 保存できたときだけ [onSaved] (編集を閉じる)。書けなかったら入力を捨てない。 */
    fun setSeat(text: String?, onSaved: () -> Unit) = write {
        localWrite("座席の保存") { marks.setSeat(UserMark.SHOW, showId, text) } ?: return@write
        val saved = marks.seat(UserMark.SHOW, showId)
        _marks.update { it.copy(seat = saved) }
        withContext(Dispatchers.Main) { onSaved() }
    }

    /** 参加を付け外しすると回収の札と要約が変わるので、行の添え物も読み直す。 */
    fun setAttendance(type: AttendanceType?) = write {
        localWrite("参加の記録") { marks.setAttendance(UserMark.SHOW, showId, type) } ?: return@write
        loadMarks()
        // 読み直しは画面のスコープ (メインスレッド) で。画面を離れていれば読み直すものも無い。
        viewModelScope.launch { reload() }
    }

    /** 👍 の集計を取る。セトリが埋まっている公演だけ (画面がセトリの有無を鍵に呼ぶ)。 */
    fun refreshLikes() {
        viewModelScope.launch {
            _likes.value = likeService.fetch(showId).associateBy { it.songId }
        }
    }

    /**
     * 👍 のトグル。押した瞬間の状態から反転を決め、サーバが返した確定値で行を更新する。
     *
     * 送信前に「ログインしているか」を見て弾かないのは意図的 — セッション更新中の一瞬に
     * トークンが空になることがあり、そこで先回りして落とすと投票が無言で失敗する。
     * 認証が要るという判断はサーバの 401 に任せ、返ってきたときだけログイン誘導を出す。
     */
    fun toggleLike(songId: String) {
        val liked = _likes.value[songId]?.hasUserLiked == true
        write {
            try {
                val result = if (liked) likeService.unlike(showId, songId) else likeService.like(showId, songId)
                _likes.update { it + (result.songId to result) }
            } catch (e: SetlistLikeService.Unauthorized) {
                _loginPrompt.value = true
            } catch (e: Exception) {
                // 通信断などは黙る。次回 fetch で正しい状態に戻る。
            }
        }
    }

    fun requestLogin() {
        _loginPrompt.value = true
    }

    fun dismissLoginPrompt() {
        _loginPrompt.value = false
    }

    private fun write(block: suspend () -> Unit) {
        module.appScope.launch { block() }
    }

    companion object {
        private const val TAG = "SetlistViewModel"

        /** 公演ごとに 1 つ (画面は `viewModel(key = showId, factory = factory(showId))` で取る)。 */
        fun factory(showId: String): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                SetlistViewModel(checkNotNull(this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY]), showId)
            }
        }
    }
}

/**
 * セトリの詳しさを端末に残す。画面をまたいで見方を保つためだけの設定。
 *
 * 3 値にする前は [KEY_SIMPLE] という Bool 1 つだった。新しい鍵がまだ無い端末は
 * その Bool から移行するが、**その判断はコア (setlistDisplayModeFromStored) が持つ**
 * — iOS と Android で別々に書くと片方だけ移行しそこねる。
 */
private object SetlistViewPrefs {
    private const val PREFS_NAME = "setlist_view_prefs"
    private const val KEY_SIMPLE = "simple_mode"
    private const val KEY_MODE = "display_mode"

    fun displayMode(context: Context): SetlistDisplayMode {
        val prefs = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return setlistDisplayModeFromStored(
            prefs.getString(KEY_MODE, null),
            prefs.getBoolean(KEY_SIMPLE, false)
        )
    }

    fun setDisplayMode(context: Context, raw: String) {
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_MODE, raw).apply()
    }
}

/**
 * 行の添え物の最後の答えと、それがどの公演のものか (iOS `SetlistViewModel.rowMetaShowId` と同じ)。
 * 読み直しが落ちたとき、同じ公演なら前の答えを残し、別の公演なら持ち越さない (空にする)。
 */
internal class RowMetaCache {
    private var showId: String? = null
    private var result = SetlistRowMetaResult()

    /** 読めた答えを覚えて返す。 */
    fun loaded(showId: String, result: SetlistRowMetaResult): SetlistRowMetaResult {
        this.showId = showId
        this.result = result
        return result
    }

    /** 読み直しが落ちたときに出す答え。 */
    fun failed(showId: String): SetlistRowMetaResult {
        if (this.showId != showId) {
            this.showId = null
            result = SetlistRowMetaResult()
        }
        return result
    }
}

