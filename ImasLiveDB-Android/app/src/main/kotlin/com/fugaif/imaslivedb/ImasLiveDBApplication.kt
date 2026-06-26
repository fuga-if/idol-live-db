package com.fugaif.imaslivedb

import android.app.Application
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager

class ImasLiveDBApplication : Application() {

    /** Eagerly initialised DI container; accessible from ViewModels via AppModule.from(context). */
    lateinit var appModule: AppModule
        private set

    override fun onCreate() {
        super.onCreate()
        // Initialise DI container (warms up database singleton and repositories)
        appModule = AppModule.from(this)
        // Initialise audio preview player
        AudioPreviewManager.init(this)
    }

    override fun onTerminate() {
        super.onTerminate()
        AudioPreviewManager.release()
    }
}
