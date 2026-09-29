package com.fugaif.imaslivedb.ui.events

import android.app.Application
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.viewmodel.MutableCreationExtras
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import uniffi.imas_core.setlistDisplayModes

/** 公演のセトリ画面の [SetlistViewModel]。 */
@RunWith(RobolectricTestRunner::class)
class SetlistViewModelTest {

    private val app: Application = RuntimeEnvironment.getApplication()

    /** お気に入りを押した直後に画面 (ViewModel) が破棄されても、書き込みは最後まで入る。 */
    @Test
    fun favoriteIsSavedEvenAfterTheScreenGoesAway() = runBlocking {
        val showId = "sh_test_favorite"
        val marks = AppModule.from(app).userMarkRepository
        val store = ViewModelStore()

        viewModel(store, showId).toggleFavorite()
        store.clear()

        withTimeout(10_000) {
            while (!marks.isOn(UserMark.SHOW, showId, UserMark.FAVORITE)) delay(20)
        }
    }

    /** 表示の詳しさは端末に残り、次に開いた公演でも同じ見方になる。 */
    @Test
    fun displayModeCarriesOverToTheNextShow() {
        val options = setlistDisplayModes()
        val first = viewModel(ViewModelStore(), "sh_test_first")
        val chosen = options.first { it.mode != first.displayMode.value }

        first.setDisplayMode(chosen)

        assertEquals(chosen.mode, first.displayMode.value)
        assertEquals(chosen.mode, viewModel(ViewModelStore(), "sh_test_next").displayMode.value)
    }

    private fun viewModel(store: ViewModelStore, showId: String): SetlistViewModel {
        val extras = MutableCreationExtras().apply {
            set(ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY, app)
        }
        return ViewModelProvider(store, SetlistViewModel.factory(showId), extras)[showId, SetlistViewModel::class.java]
    }
}
