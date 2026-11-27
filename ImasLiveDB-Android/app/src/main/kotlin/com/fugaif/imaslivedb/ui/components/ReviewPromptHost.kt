package com.fugaif.imaslivedb.ui.components

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.di.AppModule
import com.google.android.play.core.review.ReviewManagerFactory
import com.google.android.play.core.ktx.launchReview
import com.google.android.play.core.ktx.requestReview

/**
 * 起動時に一度だけ、条件を満たしていれば Play のアプリ内レビューを出す
 * (iOS `ContentView` の `requestReview()` と同じ位置)。
 *
 * 聞くのは「参加ライブを登録した次に立ち上げたとき」になる。作業の途中や登録直後に
 * 被せず、落ち着いてタブ画面を見ている場面で出す。条件を満たしていなければ
 * [com.fugaif.imaslivedb.data.local.ReviewPrompt.shouldAsk] が false を返して何も起きない。
 * Play から入れていない端末 (開発機) では Play 側が何も出さない。
 */
@Composable
fun ReviewPromptHost() {
    val context = LocalContext.current
    LaunchedEffect(Unit) {
        val prompt = AppModule.from(context).reviewPrompt
        prompt.registerLaunch()
        if (!prompt.shouldAsk()) return@LaunchedEffect
        val activity = context.findActivity() ?: return@LaunchedEffect
        runCatching {
            val manager = ReviewManagerFactory.create(activity)
            manager.launchReview(activity, manager.requestReview())
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
