package com.fugaif.imaslivedb.widget

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.layout.Box
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import androidx.glance.state.PreferencesGlanceStateDefinition
import com.fugaif.imaslivedb.MainActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 担当画像ウィジェット。iOS `ImasLiveDBWidget/OshiImageWidget.swift` の移植。
 *
 * 2 種類あるのは iOS と同じで、**絵は同じ・タップの意味だけが違う**。
 * - [OshiImageWidget] … タップで次の画像へ送る
 * - [OshiLauncherWidget] … タップでアプリを開く
 *
 * ## 状態はウィジェット 1 個ごとに持つ (iOS はアイドルごと)
 *
 * iOS は App Group の UserDefaults にアイドル ID をキーとしてローテーション位置を
 * 置いていた。Android は Glance がウィジェットインスタンスごとの Preferences を
 * 持っているので、そちらに置く。同じアイドルのウィジェットを 2 個並べたときに
 * 片方をタップしてもう片方まで送られてしまう、が起きない方が期待に合う。
 *
 * ## 表示するアイドルの決まり方
 *
 * 設定 Activity ([OshiWidgetConfigureActivity]) が選んだ ID を state に書く。
 * 未設定 (Android 12 以降は設定を飛ばして置ける) のときは候補の先頭
 * = ブランド順で最初のアイドル (iOS の `catalog.first` と同じ)。
 */
abstract class OshiImageWidgetBase(private val advanceOnTap: Boolean) : GlanceAppWidget() {

    // 中身は画面いっぱいの 1 枚絵で、サイズが変わってもレイアウトは変わらない。
    // サイズごとに作り分ける必要が無いので Single (更新のたびに複数レイアウトを
    // 組み立てないぶん軽い)。
    final override val sizeMode = SizeMode.Single

    final override suspend fun provideGlance(context: Context, id: GlanceId) {
        // 画像のデコードは I/O なので、必ず provideContent の外で済ませる
        // (Glance のコンポジションは RemoteViews を組む処理で、ブロックしてはいけない)。
        val bitmap = loadOshiImage(context, id)
        provideContent {
            OshiWidgetContent(
                bitmap = bitmap,
                onClick = if (advanceOnTap) {
                    actionRunCallback<NextOshiImageAction>()
                } else {
                    // ディープリンクではなく素の起動。アプリ内の画面遷移を URL で受ける口が
                    // まだ無いので、まずアプリを開くところまで (iOS の imaslivedb://open 相当)。
                    actionStartActivity<MainActivity>()
                }
            )
        }
    }
}

/** タップで次の画像へ送る版。 */
object OshiImageWidget : OshiImageWidgetBase(advanceOnTap = true)

/** タップでアプリを開く版。 */
object OshiLauncherWidget : OshiImageWidgetBase(advanceOnTap = false)

// MARK: - 状態

/** 表示するアイドル ID。設定 Activity が書き、ウィジェットが読む。 */
internal val KEY_OSHI_IDOL_ID = stringPreferencesKey("oshi_idol_id")

/**
 * ローテーション位置。タップと日付変わりで +1 される単調増加の値で、
 * 画像枚数での剰余を取って使う (枚数が変わっても壊れないように剰余は読む側で取る)。
 */
internal val KEY_OSHI_ROTATION = intPreferencesKey("oshi_rotation_index")

/**
 * このウィジェットに今出す 1 枚を読む。画像が 1 枚も無ければ null。
 *
 * 表示するアイドルは「設定で選ばれた ID」→ 無ければ候補の先頭 (ブランド順で最初のアイドル。
 * iOS の `catalog.first` と同じ)。Android 12 以降は設定を飛ばして置けるので、
 * 未設定でも何か出る方が期待に合う。
 */
private suspend fun loadOshiImage(context: Context, id: GlanceId): Bitmap? {
    val preferences: Preferences = getAppWidgetState(context, PreferencesGlanceStateDefinition, id)
    val idolId = preferences[KEY_OSHI_IDOL_ID]
        ?: OshiCatalog.candidates(context).firstOrNull()?.idolId
        ?: return null
    // ファイルの列挙とデコードはディスク I/O。Glance の更新は同じプロセスの
    // 他の仕事と同居するので、明示的に IO へ逃がす。
    return withContext(Dispatchers.IO) {
        val images = OshiCatalog.slideshowImages(context, idolId)
        if (images.isEmpty()) return@withContext null

        // 剰余は「読むとき」に取る。位置は単調増加のまま持っておかないと、
        // 画像を 1 枚消した瞬間に別の絵へ飛ぶ (剰余を保存する実装だとそうなる)。
        val rotation = preferences[KEY_OSHI_ROTATION] ?: 0
        val index = ((rotation % images.size) + images.size) % images.size
        WidgetImages.decode(images[index])
    }
}

// MARK: - 表示

@Composable
private fun OshiWidgetContent(bitmap: Bitmap?, onClick: Action) {
    if (bitmap == null) {
        // 画像が無いときだけ文言を出す。ここもタップは効かせておく
        // (「どうすれば出るのか」を探してタップする人が多いので、アプリ/設定に繋ぐ)。
        Box(modifier = GlanceModifier.fillMaxSize().clickable(onClick)) {
            WidgetPlaceholder("アプリで画像を追加", "アイドル詳細から取り込めます")
        }
        return
    }
    // 文字は載せない (iOS と同じ)。画像だけで成立させる。
    Image(
        provider = ImageProvider(bitmap),
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .cornerRadius(WidgetTheme.corner)
            .clickable(onClick)
    )
}

// MARK: - タップで次の画像へ

/**
 * タップされたウィジェットのローテーション位置を 1 つ進めて描き直す。
 * iOS の `NextOshiImageIntent` に対応する。
 */
class NextOshiImageAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        advanceRotation(context, glanceId)
        OshiImageWidget.update(context, glanceId)
    }
}

/** ローテーション位置を 1 つ進める (保存のみ。描き直しは呼び出し側)。 */
internal suspend fun advanceRotation(context: Context, glanceId: GlanceId) {
    updateAppWidgetState(context, glanceId) { preferences: MutablePreferences ->
        preferences[KEY_OSHI_ROTATION] = (preferences[KEY_OSHI_ROTATION] ?: 0) + 1
    }
}

/** 設定 Activity から書き込む口 (表示アイドルの確定)。 */
internal suspend fun setOshiIdol(context: Context, glanceId: GlanceId, idolId: String) {
    updateAppWidgetState(context, glanceId) { preferences: MutablePreferences ->
        preferences[KEY_OSHI_IDOL_ID] = idolId
        // 別のアイドルに変えたら 1 枚目から見せる。前のアイドルの位置を引き継ぐと
        // 「選んだ直後に 3 枚目が出る」ことになって、選んだ手応えが無い。
        preferences[KEY_OSHI_ROTATION] = 0
    }
}

/** state を読むだけの口 (設定 Activity で現在の選択にチェックを付けるため)。 */
internal suspend fun selectedOshiIdolId(context: Context, glanceId: GlanceId): String? {
    val preferences: Preferences = getAppWidgetState(context, PreferencesGlanceStateDefinition, glanceId)
    return preferences[KEY_OSHI_IDOL_ID]
}

// MARK: - Receiver

// 更新予約の面倒 (日付が変わったら次の画像へ送る) は ImasWidgetReceiver が見る。
class OshiImageWidgetReceiver : ImasWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget get() = OshiImageWidget
}

class OshiLauncherWidgetReceiver : ImasWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget get() = OshiLauncherWidget
}

/**
 * 置いてある担当画像ウィジェット全部を「次の画像」へ送る (日付変わりの定期更新から呼ぶ)。
 *
 * iOS はタイムラインを先に組めるので 30 分ごとに送っているが、Android は送るたびに
 * プロセスを起こす必要がある。電池と引き換えにするほどの価値は無いので、
 * どのみち起きる日付変わりの 1 回に相乗りさせる。
 */
internal suspend fun advanceAllOshiWidgets(context: Context) {
    val manager = GlanceAppWidgetManager(context)
    manager.getGlanceIds(OshiImageWidget::class.java).forEach { glanceId ->
        advanceRotation(context, glanceId)
        OshiImageWidget.update(context, glanceId)
    }
    manager.getGlanceIds(OshiLauncherWidget::class.java).forEach { glanceId ->
        advanceRotation(context, glanceId)
        OshiLauncherWidget.update(context, glanceId)
    }
}
