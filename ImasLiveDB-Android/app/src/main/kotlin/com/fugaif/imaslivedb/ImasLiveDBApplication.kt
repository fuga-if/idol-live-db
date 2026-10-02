package com.fugaif.imaslivedb

import android.app.Application
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager

/**
 * プロセスはウィジェット・通知の Receiver・設定 Activity からも起動するので、ここでは
 * 重い処理 (スナップショットの全読み・ExoPlayer の生成・サーバへの問い合わせ) をしない。
 * それらは画面が出たとき ([MainActivity]) か、初めて使うときに始まる。
 */
class ImasLiveDBApplication : Application() {

    /** Eagerly initialised DI container; accessible from ViewModels via AppModule.from(context). */
    lateinit var appModule: AppModule
        private set

    override fun onCreate() {
        super.onCreate()
        appModule = AppModule.from(this)
        // Apple Music の再生器は「いま前に出ている Activity」を Activity のライフサイクルで覚える。
        // 歌詞を開いた時点で初めて作ると最初の Activity を取り逃がすので、起動時に作っておく。
        appModule.lyricsPlayback
        // プレイヤーは初めて鳴らすときに作る。ここでは Context を渡すだけ。
        AudioPreviewManager.init(this)
    }

    override fun onTerminate() {
        super.onTerminate()
        AudioPreviewManager.release()
    }
}
